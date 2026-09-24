extends RefCounted
## Adapted from ../playtest status folio and mastery cards, using expedition data.
const Growth = preload("res://expedition/progression/growth.gd")
const Mastery = preload("res://expedition/progression/mastery.gd")
const CombatStats = preload("res://expedition/combat/combat_stats.gd")
static var mastery_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/mastery.json"))
const Emblem = preload("res://expedition/art/growth_emblem.gd")
const Art = preload("res://expedition/art/mobile_art.gd")
const Stances = preload("res://expedition/ai/stances.gd")
const Memory = preload("res://sim/party_memory_state.gd")

static func surface(color: Color, border: Color = Color("6d5b3f")) -> StyleBoxFlat:
	var skin := StyleBoxFlat.new(); skin.bg_color = color; skin.border_color = border
	skin.set_border_width_all(2); skin.set_content_margin_all(8)
	skin.shadow_size = 0
	return skin

static func place(node: Control, parent: Node, rect: Rect2) -> void:
	parent.add_child(node); node.position = rect.position; node.size = rect.size

static func shell(ui, tab: String) -> VBoxContainer:
	# Design coordinates match the approved 390 x 844 portrait folio.
	var screen: Vector2 = ui.get_viewport_rect().size
	var skin: Theme = ui.theme.duplicate()
	skin.set_color("font_color","Button",Color("e0d4bc"))
	skin.set_color("font_pressed_color","Button",Color("ffe0a3"))
	var opaque := surface(Color("0e0d0c")); opaque.set_content_margin_all(0)
	opaque.shadow_size = 0; opaque.set_border_width_all(0)
	skin.set_stylebox("panel","PopupPanel",opaque)
	ui.details_popup.theme = skin
	ui.modal_content.custom_minimum_size = screen
	var canvas := Control.new(); canvas.custom_minimum_size = screen; ui.modal_content.add_child(canvas)
	var background := ColorRect.new(); background.color = Color("0e0d0c"); background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(background,canvas,Rect2(Vector2.ZERO,screen))
	var design := Control.new(); design.name = "CharacterFolio"
	var factor: float = minf(screen.x/390.0,screen.y/844.0)
	place(design,canvas,Rect2((screen-Vector2(390,844)*factor)/2,Vector2(390,844))); design.scale = Vector2.ONE*factor
	var header_panel := Panel.new(); header_panel.add_theme_stylebox_override("panel",surface(Color("171512")))
	place(header_panel,design,Rect2(8,8,374,150))
	var header := HBoxContainer.new(); header.name = "CharacterHeader"; header.add_theme_constant_override("separation",12)
	place(header,design,Rect2(16,16,358,134))
	var portrait := TextureRect.new(); portrait.texture = Art.portrait_face(ui.tactics_actor)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(128,128); header.add_child(portrait)
	var info := VBoxContainer.new(); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(info)
	var title := HBoxContainer.new(); info.add_child(title)
	text(title,ui.session.party[ui.tactics_actor].name,24)
	var close = ui.button(title,"×",func(): ui.details_popup.hide()); close.size_flags_horizontal = 0; close.custom_minimum_size.x = 32
	var members := HBoxContainer.new(); info.add_child(members)
	for index in range(ui.session.party.size()):
		var member = ui.button(members,ui.session.party[index].name,func(): ui.show_character(index,ui.character_tab))
		member.toggle_mode = true; member.button_pressed = index == ui.tactics_actor
	var tabs := HBoxContainer.new(); tabs.name = "CharacterTabs"; tabs.add_theme_constant_override("separation",0)
	place(tabs,design,Rect2(0,168,390,46))
	for name in ["상태","성격","기억","숙련","파츠"]:
		var button = ui.button(tabs,name,func(): ui.show_character(ui.tactics_actor,name))
		button.toggle_mode = true; button.button_pressed = tab == name; button.custom_minimum_size.y = 46
		button.size_flags_stretch_ratio = 1
	var heading := Label.new(); heading.text = "파츠 슬롯 %d / 2" % ui.session.party[ui.tactics_actor].equipped_abilities.filter(func(id): return not str(id).is_empty()).size() if tab == "파츠" else "현재 상태" if tab == "상태" else tab
	heading.add_theme_font_size_override("font_size",19); heading.add_theme_color_override("font_color",Color("d0c8b4"))
	place(heading,design,Rect2(22,220,346,28))
	var scroll := ScrollContainer.new(); scroll.name = "CharacterScroll"; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	place(scroll,design,Rect2(12,252,366,504))
	var list := VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",12); scroll.add_child(list)
	var close_button := Button.new(); close_button.text = "닫기"; close_button.add_theme_font_size_override("font_size",20)
	close_button.pressed.connect(func(): ui.details_popup.hide())
	place(close_button,design,Rect2(12,768,366,56)); close_button.name = "CharacterClose"
	return list

static func card(parent: Node, title: String) -> VBoxContainer:
	var panel := PanelContainer.new(); panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var skin := surface(Color("1b1916"))
	panel.add_theme_stylebox_override("panel",skin); parent.add_child(panel)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation",6); panel.add_child(box)
	if not title.is_empty(): text(box,title,18).add_theme_color_override("font_color",Color("e5d0a4"))
	return box

static func text(parent: Node, value: String, font_size: int = 14) -> Label:
	var label := Label.new(); label.text = value; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",Color("e0d4bc")); parent.add_child(label); return label

static func gauge(parent: Node, value: float, maximum: float, color: Color) -> ProgressBar:
	var bar := ProgressBar.new(); bar.max_value = maxf(1,maximum); bar.value = value; bar.show_percentage = false
	bar.custom_minimum_size.y = 10
	var fill := StyleBoxFlat.new(); fill.bg_color = color; bar.add_theme_stylebox_override("fill",fill)
	var bg := StyleBoxFlat.new(); bg.bg_color = Color("090807"); bar.add_theme_stylebox_override("background",bg)
	parent.add_child(bar); return bar

static func grid(parent: Node, columns: int) -> GridContainer:
	var result := GridContainer.new(); result.columns = columns
	result.add_theme_constant_override("h_separation",6); result.add_theme_constant_override("v_separation",6)
	parent.add_child(result); return result

static func status(ui, list: VBoxContainer, actor: Dictionary) -> void:
	if ui.session.manual_mode:
		var vitals := card(list,"Lv.%d · %s" % [int(actor.get("level",1)),actor.name])
		text(vitals,"HP  %d / %d" % [actor.hp,actor.max_hp]); gauge(vitals,actor.hp,actor.max_hp,Color("bf5450"))
		text(vitals,"MP  %d / %d" % [actor.mp,actor.max_mp]); gauge(vitals,actor.mp,actor.max_mp,Color("507eb9"))
		text(vitals,"스트레스  %d / 200" % actor.stress); gauge(vitals,actor.stress,200,Color("c9a251"))
		var values: Dictionary = CombatStats.stats(ui.session,actor)
		var combat := card(list,"전투")
		var stats := grid(combat,2)
		for entry in [["피해",values.damage],["공격 시간",values.delay],["방어",values.ac],["회피",values.ev]]:
			var stat := card(stats,str(entry[0])); text(stat,str(entry[1]),20)
		var equipped := card(list,"장비")
		var gear: Dictionary = actor.get("gear",{})
		var slot_names := {"weapon":"무기","armour":"갑옷","shield":"방패","ring":"반지"}
		for slot in ["weapon","armour","shield","ring"]:
			var item: Dictionary = gear.get(slot,{})
			var catalogue: Dictionary = CombatStats.content.weapons if slot == "weapon" else CombatStats.content.armours if slot == "armour" else CombatStats.content.rings if slot == "ring" else {}
			var item_id: String = str(item.get("type",""))
			var item_name: String = "—" if item.is_empty() else "방패" if slot == "shield" else str(catalogue.get(item_id,{}).get("name",item_id))
			text(equipped,"%s   %s" % [slot_names[slot],item_name],13)
		return
	var vitals := card(list,"Lv.%d · %s" % [actor.growth.level,actor.name])
	vitals.get_parent().custom_minimum_size.y = 130
	text(vitals,"체력 %d / %d" % [actor.hp,actor.max_hp]); gauge(vitals,actor.hp,actor.max_hp,Color("9f4544"))
	text(vitals,"정신 상태 · "+actor.condition); gauge(vitals,actor.stress,200,Color("c6a34c"))
	if ui.session.party.size() == 1:
		text(vitals,"스트레스 150 이상: 받는 피해 +1 · 정신 안정제로 완화",12)
	var stats := card(list,"능력치 · 남은 포인트 %d" % actor.growth.stat_points)
	var attributes := grid(stats,3)
	for id in Growth.STATS:
		var box := card(attributes,Growth.STATS[id]); text(box,str(actor.growth.stats[id]),20)
		ui.button(box,"+",func(): preview(ui,id,true),can_invest(ui,actor) and actor.growth.stat_points > 0)
	text(stats,"일반 공격 %d · 피해 감소 %d%%" % [Growth.power(actor,"MELEE",18),actor.growth.ranks.DEFENSE*4])

static func can_invest(ui, actor: Dictionary) -> bool:
	return ui.session.safe_management() and actor.hp > 0

static func mastery(ui, list: VBoxContainer, actor: Dictionary) -> void:
	if ui.session.manual_mode:
		var cards := grid(list,5); cards.name = "MasteryGrid"
		for axis in Mastery.AXES:
			var level := Mastery.rank(actor,axis)
			var cell := VBoxContainer.new(); cell.name = "MasteryCell_"+axis
			cell.add_theme_constant_override("separation",2); cards.add_child(cell)
			var tile = ui.button(cell,"",func(): ui.show_mastery_detail(ui.tactics_actor,axis))
			tile.name = "MasteryIcon_"+axis; tile.custom_minimum_size = Vector2(60,52)
			tile.tooltip_text = "%s · %s" % [Mastery.NAMES[axis],Mastery.bonus(axis,level)]
			var glyph := TextureRect.new(); glyph.texture = Art.mastery_icon(axis)
			glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			glyph.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
			glyph.custom_minimum_size = Vector2(30,30); glyph.size = Vector2(30,30); tile.add_child(glyph)
			glyph.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
			glyph.offset_left = -15; glyph.offset_top = -15; glyph.offset_right = 15; glyph.offset_bottom = 15
			var xp: int = int(actor.get("skill_xp",{}).get(axis,0))
			var floor_xp: int = 0 if level == 0 else Mastery.required_xp(actor,axis,level)
			var next_xp: int = Mastery.required_xp(actor,axis,mini(10,level+1))
			var bar := gauge(cell,1 if level == 10 else float(xp-floor_xp),1 if level == 10 else float(next_xp-floor_xp),Color("c6a34c") if axis in Mastery.AXES.slice(0,5) else Color("69cfc2"))
			bar.name = "MasteryXP_"+axis
			text(cell,"%s %d" % [Mastery.NAMES[axis],level],10).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return
	var summary := card(list,"Lv.%d · 숙련 포인트 %d" % [actor.growth.level,actor.growth.points])
	summary.get_parent().custom_minimum_size.y = 86
	var floor_xp := Growth.threshold(actor.growth.level)
	var next_xp := Growth.threshold(mini(Growth.MAX_LEVEL,actor.growth.level+1))
	text(summary,"최고 레벨" if actor.growth.level == Growth.MAX_LEVEL else "경험치 %d / %d" % [actor.growth.xp,next_xp])
	gauge(summary,actor.growth.xp-floor_xp,maxi(1,next_xp-floor_xp),Color("4d8f98"))
	var cards := grid(list,2); cards.name = "MasteryGrid"
	for axis in Growth.AXES:
		var box := card(cards,""); var heading := HBoxContainer.new(); box.add_child(heading)
		box.get_parent().custom_minimum_size = Vector2(0,130)
		var emblem := Emblem.new(); emblem.symbol = axis; heading.add_child(emblem)
		text(heading,"%s %d/10" % [Growth.AXES[axis],actor.growth.ranks[axis]],14)
		text(box,"피해 감소 %d%%" % (actor.growth.ranks[axis]*4) if axis == "DEFENSE" else "위력 +%d%%" % (actor.growth.ranks[axis]*8))
		ui.button(box,"+ 1점 투자",func(): preview(ui,axis),can_invest(ui,actor) and actor.growth.points > 0 and actor.growth.ranks[axis] < Growth.MAX_RANK)
	text(list,"전투 밖에서 투자 · 레벨업마다 1점 · 재분배 불가")

static func mastery_detail(ui, list: VBoxContainer, actor: Dictionary, axis: String) -> void:
	var current := Mastery.rank(actor,axis)
	var header := card(list,"%s · %d/10" % [Mastery.NAMES[axis],current])
	text(header,"현재: %s" % Mastery.bonus(axis,current))
	if current < 10: text(header,"다음 숙련까지 %d XP" % maxi(0,Mastery.required_xp(actor,axis,current+1)-int(actor.get("skill_xp",{}).get(axis,0))))
	var rewards: Dictionary = mastery_data.milestones.get(axis,{})
	for level in range(1,11):
		var state := "획득" if level <= current else "다음" if level == current+1 else "잠김"
		var row := card(list,"Lv%d · %s" % [level,state]); row.get_parent().name = "MasteryLevel%d" % level
		var line := HBoxContainer.new(); row.add_child(line)
		var icon := TextureRect.new()
		icon.texture = Art.spell_icon(axis+"_"+str(level)) if axis in Mastery.AXES.slice(5) else Art.mastery_icon(axis)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size = Vector2(30,30); line.add_child(icon)
		text(line,Mastery.bonus(axis,level))
		var reward: Dictionary = rewards.get(str(level),{})
		if not str(reward.get("effect_id","")).is_empty(): text(row,str(reward.name))
	var back = ui.button(list,"‹ 숙련 목록",func(): ui.show_character(ui.tactics_actor,"숙련")); back.name = "MasteryBack"

static func detail(ui, title: String, message: String) -> void:
	ui.clear(ui.item_detail); text(ui.item_detail,title,20); text(ui.item_detail,message)
	ui.button(ui.item_detail,"닫기",func(): ui.item_popup.hide()); ui.item_popup.popup_centered()

static func personality(ui, list: VBoxContainer, actor: Dictionary) -> void:
	var box := card(list,actor.profile.style_summary().label)
	var names := {"H":"정직·겸손","E":"정서성","X":"외향성","A":"우호성","C":"성실성","O":"개방성"}
	for id in names:
		var row := VBoxContainer.new(); row.custom_minimum_size.y = 44; box.add_child(row)
		text(row,"%s   %d / 100" % [names[id],int(actor.profile.value(id)/10)])
		gauge(row,actor.profile.value(id),1000,Color("c9a251"))
	stances(ui,list,actor)

## How this member fights: one button per stance, the build the parts suggest,
## and the one number the tab is for — how often this member will get it wrong.
## The aptitudes themselves are not drawn; ⚠ and the tooltip carry them.
static func stances(ui, list: VBoxContainer, actor: Dictionary) -> void:
	var index: int = ui.tactics_actor
	var editable: bool = ui.session.phase == "CAMP"
	var chosen: String = str(actor.get("stance",Stances.default_stance(actor.profile)))
	var box := card(list,"태세"); box.name = "StanceCard"
	var columns := grid(box,Stances.IDS.size())
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry in Stances.IDS:
		var id: String = entry
		var column := VBoxContainer.new(); column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; columns.add_child(column)
		var solo: bool = id == "GUARDIAN" and ui.session.party.size() == 1
		var comfortable: bool = Stances.comfortable(actor.profile,id)
		var pick = ui.button(column,Stances.NAMES[id] if comfortable else Stances.NAMES[id]+" ⚠",func(): choose(ui,index,id),editable and not solo)
		pick.name = "Stance_"+id; pick.toggle_mode = true; pick.button_pressed = id == chosen
		pick.custom_minimum_size.y = 44
		# What this stance would cost in mistakes, asked of a copy of the member.
		var probe: Dictionary = actor.duplicate(); probe["stance"] = id
		pick.tooltip_text = "실수 확률 %d%%" % Stances.mistake_chance(probe)
	var badge := text(box,Stances.NAMES[Stances.suggested(actor)],13)
	badge.name = "StanceSuggestion"
	var line := text(box,mistake_line(actor),13); line.name = "MistakeLine"
	if not Stances.comfortable(actor.profile,chosen): line.add_theme_color_override("font_color",Color("d1a05f"))

## "실수 확률 12% · 성실 낮음": the chance, then the largest reason behind it.
static func mistake_line(actor: Dictionary) -> String:
	return "실수 확률 %d%% · %s" % [Stances.mistake_chance(actor),cause(actor)]

## Whichever of the three terms of `Stances.mistake_chance` adds the most:
## carelessness (only once it is a fault, C below 500), the stance the member
## was forced into, or what the stress multiplier piles on top.
static func cause(actor: Dictionary) -> String:
	var profile = actor.profile
	var chosen: String = str(actor.get("stance",Stances.default_stance(profile)))
	var careless: int = (1000-profile.value("C"))/60 if profile.value("C") < 500 else 0
	var forced := 0
	if not Stances.comfortable(profile,chosen):
		var apt := Stances.aptitude(profile)
		forced = mini(20,(int(apt[Stances.default_stance(profile)])-int(apt[chosen]))/40)
	var before: int = Stances.MISTAKE_BASE+(1000-profile.value("C"))/60+forced
	var after: int = before*2 if int(actor.stress) >= 150 else before*3/2 if int(actor.stress) >= 100 else before
	var anxious: int = after-before
	if careless > 0 and careless >= forced and careless >= anxious: return "성실 낮음"
	if forced > 0 and forced >= anxious: return "태세 강제"
	return "불안" if anxious > 0 else "안정"

## Taking a stance rebuilds the tab: the ⚠ badges and the mistake line both
## depend on it.
static func choose(ui, index: int, id: String) -> void:
	if not ui.session.set_stance(index,id): return
	ui.refresh(); ui.show_character(index,"성격")

static func memories(ui, list: VBoxContainer, actor: Dictionary) -> void:
	var names := {"SELF_HARM":["죽음의 문턱","빈사 상태에 빠졌다."],"ALLY_DOWNED":["동료가 쓰러짐","동료가 쓰러지는 모습을 보았다."],"ALLY_LOST":["동료를 잃음","함께하던 동료를 잃었다."],"AID_RECEIVED":["동료의 도움","동료에게 도움을 받았다."],"COMMAND_CONFLICT":["명령과 갈등","명령을 따르는 데 갈등을 겪었다."],"RECRUITED":["동행 시작","함께 가기로 했다."],"DECLINED_BY_PLAYER":["동행 거절당함","동행 제안을 거절당했다."],"DECLINED_PLAYER":["동행 거절","동행 제안을 거절했다."],"LEFT_BY_PARTNER":["동료의 이별","동료가 나를 두고 떠났다."]}
	# The same exemption the pruning rules make: a social record is cheap and stays.
	var important: Array = actor.memory.records.filter(func(record): return int(record.salience) >= 700 or str(record.kind) in Memory.SOCIAL_KINDS)
	if important.is_empty(): text(card(list,"기억"),"중요 기억 없음")
	for record in important:
		var copy: Dictionary = record.duplicate(true)
		var entry: Array = names.get(record.kind,[record.kind,"기억이 남았다."])
		var box := card(list,entry[0]); box.get_parent().custom_minimum_size.y = 90
		text(box,entry[1])
		ui.button(box,"›",func(): detail(ui,entry[0],entry[1]+"\n%d턴" % copy.observed_time))

## Two part slots: what is equipped and how to swap it. How the part is used
## is the rules' business, and the rules are no longer the player's.
static func parts(ui, list: VBoxContainer, actor: Dictionary) -> void:
	var town: bool = ui.session.phase == "CAMP" and actor.hp > 0
	for slot in range(2):
		var id: String = str(actor.equipped_abilities[slot])
		var box := card(list,""); box.get_parent().name = "PartSlot"+str(slot)
		box.get_parent().custom_minimum_size.y = 132
		var row := HBoxContainer.new(); box.add_child(row)
		var info := VBoxContainer.new(); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(info)
		var actions := VBoxContainer.new(); row.add_child(actions)
		if id.is_empty():
			text(info,"빈 슬롯",20)
			ui.button(actions,"장착",func(): replace(ui,slot),town)
			continue
		var def: Dictionary = ui.Session.Abilities.DEFINITIONS[id]
		text(info,str(def.name),20)
		text(info,str(def.description),13)
		ui.button(actions,"교체",func(): replace(ui,slot),town)
		ui.button(actions,"해제",func(): ui.session.unequip_part(ui.tactics_actor,slot); ui.refresh(); ui.show_character(ui.tactics_actor,"파츠"),town)

## The bag, minus what this member already carries, as one tap per part.
static func replace(ui, slot: int) -> void:
	var index: int = ui.tactics_actor
	var actor: Dictionary = ui.session.party[index]
	ui.clear(ui.item_detail); text(ui.item_detail,"파츠 장착",20)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(300,260); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; ui.item_detail.add_child(scroll)
	var list := VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(list)
	var count := 0
	for id in ui.session.parts_bag:
		if int(ui.session.parts_bag[id]) <= 0 or id in actor.equipped_abilities: continue
		count += 1
		ui.button(list,"%s ×%d" % [ui.Session.Rules.skill(id).name,ui.session.parts_bag[id]],func():
			if ui.session.equip_part(index,slot,id):
				ui.item_popup.hide(); ui.refresh(); ui.show_character(index,"파츠"),ui.session.phase == "CAMP" and actor.hp > 0)
	if count == 0: text(list,"가방에 파츠 없음")
	ui.button(ui.item_detail,"취소",func(): ui.item_popup.hide()); ui.item_popup.popup_centered()

static func preview(ui, id: String, stat: bool = false) -> void:
	var index: int = ui.tactics_actor
	var actor: Dictionary = ui.session.party[index]
	var pool := "stat_points" if stat else "points"
	var rows := "stats" if stat else "ranks"
	var before: int = actor.growth[rows][id]; var points: int = actor.growth[pool]
	var dialog := ConfirmationDialog.new(); dialog.title = "능력치 투자" if stat else "숙련 투자"
	dialog.ok_button_text = "1점 투자"; dialog.cancel_button_text = "취소"
	dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var change := "기본 위력 +2" if stat else "피해 감소 %d%% → %d%%" % [before*4,(before+1)*4] if id == "DEFENSE" else "위력 +%d%% → +%d%%" % [before*8,(before+1)*8]
	dialog.dialog_text = "%s %d → %d\n%s\n\n포인트 1점 소모 · 재분배 불가" % [(Growth.STATS if stat else Growth.AXES)[id],before,before+1,change]
	ui.details_popup.add_child(dialog); dialog.transient = true; dialog.exclusive = true
	dialog.confirmed.connect(func():
		if actor.growth[pool] == points and actor.growth[rows][id] == before:
			ui.session.spend_growth(index,id,stat)
		dialog.queue_free(); ui.refresh(); ui.show_character(index,"상태" if stat else "숙련"))
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(300,200))
