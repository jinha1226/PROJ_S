extends RefCounted
## Adapted from ../playtest status folio and mastery cards, using expedition data.
const Growth = preload("res://expedition/growth.gd")
const Body = preload("res://game/rebuilt/body_bridge.gd")
const Silhouette = preload("res://expedition/body_status_silhouette.gd")
const BodyPresentation = preload("res://expedition/body_presentation.gd")
const Emblem = preload("res://expedition/growth_emblem.gd")
const Art = preload("res://expedition/mobile_art.gd")

static func surface(color: Color, border: Color = Color("65522a")) -> StyleBoxFlat:
	var skin := StyleBoxFlat.new(); skin.bg_color = color; skin.border_color = border
	skin.set_border_width_all(1); skin.set_content_margin_all(10)
	skin.shadow_color = Color(0,0,0,0.35); skin.shadow_size = 2
	return skin

static func place(node: Control, parent: Node, rect: Rect2) -> void:
	parent.add_child(node); node.position = rect.position; node.size = rect.size

static func shell(ui, tab: String) -> VBoxContainer:
	# Design coordinates match the approved 390 x 844 portrait folio.
	var skin: Theme = ui.theme.duplicate()
	for state in ["normal","hover","pressed","focus","disabled"]:
		skin.set_stylebox(state,"Button",surface(Color("15191d"),Color("74cfca") if state in ["pressed","focus"] else Color("65522a")))
	skin.set_color("font_color","Button",Color("d0c8b4"))
	skin.set_color("font_pressed_color","Button",Color("9fece6"))
	var opaque := surface(Color("101416")); opaque.set_content_margin_all(0)
	opaque.shadow_size = 0; opaque.set_border_width_all(0)
	skin.set_stylebox("panel","PopupPanel",opaque)
	ui.details_popup.theme = skin
	ui.modal_content.custom_minimum_size = ui.size
	var canvas := Control.new(); canvas.custom_minimum_size = ui.size; ui.modal_content.add_child(canvas)
	var background := ColorRect.new(); background.color = Color("101416"); background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(background,canvas,Rect2(Vector2.ZERO,ui.size))
	var design := Control.new(); design.name = "CharacterFolio"
	var factor: float = minf(ui.size.x/390.0,ui.size.y/844.0)
	place(design,canvas,Rect2((ui.size-Vector2(390,844)*factor)/2,Vector2(390,844))); design.scale = Vector2.ONE*factor
	var header := HBoxContainer.new(); header.name = "CharacterHeader"; header.add_theme_constant_override("separation",14)
	place(header,design,Rect2(8,8,374,94))
	var portrait := TextureRect.new(); portrait.texture = Art.portrait(ui.tactics_actor)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(94,94); header.add_child(portrait)
	var info := VBoxContainer.new(); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(info)
	var title := HBoxContainer.new(); info.add_child(title)
	text(title,ui.session.party[ui.tactics_actor].name+" · 캐릭터",20)
	var close = ui.button(title,"×",func(): ui.details_popup.hide()); close.size_flags_horizontal = 0; close.custom_minimum_size.x = 32
	var members := HBoxContainer.new(); info.add_child(members)
	for index in range(ui.session.party.size()):
		var member = ui.button(members,ui.session.party[index].name,func(): ui.show_character(index,ui.character_tab))
		member.toggle_mode = true; member.button_pressed = index == ui.tactics_actor
	var tabs := HBoxContainer.new(); tabs.name = "CharacterTabs"; tabs.add_theme_constant_override("separation",0)
	place(tabs,design,Rect2(0,110,390,42))
	for name in ["상태","성격","기억","숙련","이능"]:
		var button = ui.button(tabs,name,func(): ui.show_character(ui.tactics_actor,name))
		button.toggle_mode = true; button.button_pressed = tab == name; button.custom_minimum_size.y = 42
		button.size_flags_stretch_ratio = 1
	var heading := Label.new(); heading.text = "장착 이능 2 / 2" if tab == "이능" else "현재 상태" if tab == "상태" else tab
	heading.add_theme_font_size_override("font_size",19); heading.add_theme_color_override("font_color",Color("d0c8b4"))
	place(heading,design,Rect2(22,166,346,30))
	var scroll := ScrollContainer.new(); scroll.name = "CharacterScroll"; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	place(scroll,design,Rect2(12,206,366,536))
	var list := VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",12); scroll.add_child(list)
	var close_button := Button.new(); close_button.text = "닫기"; close_button.add_theme_font_size_override("font_size",20)
	close_button.pressed.connect(func(): ui.details_popup.hide())
	place(close_button,design,Rect2(12,768,366,56)); close_button.name = "CharacterClose"
	return list

static func card(parent: Node, title: String) -> VBoxContainer:
	var panel := PanelContainer.new(); panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var skin := surface(Color("111719"))
	panel.add_theme_stylebox_override("panel",skin); parent.add_child(panel)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation",6); panel.add_child(box)
	if not title.is_empty(): text(box,title,18).add_theme_color_override("font_color",Color("e2d6be"))
	return box

static func text(parent: Node, value: String, font_size: int = 14) -> Label:
	var label := Label.new(); label.text = value; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",Color("d0c8b4")); parent.add_child(label); return label

static func gauge(parent: Node, value: float, maximum: float, color: Color) -> void:
	var bar := ProgressBar.new(); bar.max_value = maxf(1,maximum); bar.value = value; bar.show_percentage = false
	bar.custom_minimum_size.y = 8
	var fill := StyleBoxFlat.new(); fill.bg_color = color; bar.add_theme_stylebox_override("fill",fill)
	var bg := StyleBoxFlat.new(); bg.bg_color = Color("070b0c"); bar.add_theme_stylebox_override("background",bg)
	parent.add_child(bar)

static func grid(parent: Node, columns: int) -> GridContainer:
	var result := GridContainer.new(); result.columns = columns
	result.add_theme_constant_override("h_separation",6); result.add_theme_constant_override("v_separation",6)
	parent.add_child(result); return result

static func status(ui, list: VBoxContainer, actor: Dictionary) -> void:
	var vitals := card(list,"Lv.%d · %s" % [actor.growth.level,actor.name])
	vitals.get_parent().custom_minimum_size.y = 130
	text(vitals,"체력 %d / %d" % [actor.hp,actor.max_hp]); gauge(vitals,actor.hp,actor.max_hp,Color("9f4544"))
	text(vitals,"정신 상태 · "+actor.condition); gauge(vitals,actor.stress,200,Color("c6a34c"))
	if ui.session.floor_mode and ui.session.party.size() == 1:
		text(vitals,"스트레스 150 이상: 받는 피해 +1 · 정신 안정제로 완화",12)
	var stats := card(list,"능력치 · 남은 포인트 %d" % actor.growth.stat_points)
	var attributes := grid(stats,3)
	for id in Growth.STATS:
		var box := card(attributes,Growth.STATS[id]); text(box,str(actor.growth.stats[id]),20)
		ui.button(box,"+",func(): preview(ui,id,true),can_invest(ui,actor) and actor.growth.stat_points > 0)
	text(stats,"일반 공격 %d · 피해 감소 %d%%" % [Growth.power(actor,"MELEE",18),actor.growth.ranks.DEFENSE*4])
	var body := card(list,"육체 상태")
	text(body,BodyPresentation.summary(actor),18)
	if actor.attack_factor < 100: text(body,"팔 손상 · 공격력 감소",14)
	if actor.move_factor > 100: text(body,"다리 손상",14)
	if actor.blood < 60: text(body,"혈액 부족",14)
	var row := HBoxContainer.new(); body.add_child(row)
	var silhouette := Silhouette.new(); silhouette.body = {"parts":actor.body.parts}; row.add_child(silhouette)
	var parts := VBoxContainer.new(); parts.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(parts)
	for part in actor.body.parts:
		if BodyPresentation.part_state(part) == "정상": continue
		var line = ui.button(parts,"%s · %s" % [Body.PART_NAMES[part.part_id],BodyPresentation.part_state(part)],func(): detail(ui,Body.PART_NAMES[part.part_id],BodyPresentation.detail(part)))
		line.custom_minimum_size.y = 44; line.add_theme_color_override("font_color",BodyPresentation.color(part))
	if parts.get_child_count() == 0: text(parts,"모든 부위가 정상입니다.",16)
	text(body,"초록: 정상 · 노랑: 상처 · 빨강: 기능 상실",12)

static func can_invest(ui, actor: Dictionary) -> bool:
	return ui.session.safe_management() and actor.hp > 0

static func mastery(ui, list: VBoxContainer, actor: Dictionary) -> void:
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

static func detail(ui, title: String, message: String) -> void:
	ui.clear(ui.item_detail); text(ui.item_detail,title,20); text(ui.item_detail,message)
	ui.button(ui.item_detail,"닫기",func(): ui.item_popup.hide()); ui.item_popup.popup_centered()

static func personality(list: VBoxContainer, actor: Dictionary) -> void:
	var box := card(list,actor.profile.style_summary().label)
	text(box,actor.name+"의 성향")
	var names := {"H":"정직·겸손","E":"정서성","X":"외향성","A":"우호성","C":"성실성","O":"개방성"}
	for id in names:
		var row := VBoxContainer.new(); row.custom_minimum_size.y = 44; box.add_child(row)
		text(row,"%s                         %d" % [names[id],actor.profile.value(id)])
		gauge(row,actor.profile.value(id),1000,Color("69cfc2"))

static func memories(ui, list: VBoxContainer, actor: Dictionary) -> void:
	var names := {"SELF_HARM":["죽음의 문턱","큰 부상을 입거나 빈사 상태에 빠졌다."],"ALLY_DOWNED":["동료가 쓰러짐","동료가 쓰러지는 모습을 보았다."],"ALLY_LOST":["동료를 잃음","함께하던 동료를 잃었다."],"AID_RECEIVED":["동료의 도움","동료에게 도움을 받았다."],"COMMAND_CONFLICT":["명령과 갈등","명령을 따르는 데 갈등을 겪었다."]}
	var important: Array = actor.memory.records.filter(func(record): return int(record.salience) >= 700)
	if important.is_empty(): text(card(list,"기억"),"남아 있는 중요 기억 없음")
	for record in important:
		var copy: Dictionary = record.duplicate(true)
		var entry: Array = names.get(record.kind,[record.kind,"기억이 남았다."])
		var box := card(list,entry[0]); box.get_parent().custom_minimum_size.y = 90
		text(box,entry[1])
		ui.button(box,"강도 %d    ›" % record.salience,func(): detail(ui,entry[0],entry[1]+"\n강도 %d\n발생 시각 %d · 사건 %d" % [copy.salience,copy.observed_time,copy.source_event_id]))

static func abilities(ui, list: VBoxContainer, actor: Dictionary) -> void:
	for index in range(actor.rules.size()):
		var rule: Dictionary = actor.rules[index]
		if rule.skill not in actor.equipped_abilities: continue
		var slot: int = actor.equipped_abilities.find(rule.skill)
		var box := card(list,""); box.get_parent().name = "EquippedAbility"+str(slot)
		box.get_parent().custom_minimum_size.y = 132
		var row := HBoxContainer.new(); box.add_child(row)
		var info := VBoxContainer.new(); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(info)
		text(info,ui.Session.Rules.SKILLS[rule.skill].name,20)
		var description: String = ui.Session.Abilities.DEFINITIONS.get(rule.skill,{}).get("description","인접한 적을 한 칸 밀어냅니다." if rule.skill == "PUSH" else "다음 공격의 피해를 줄입니다.")
		text(info,description,13)
		var actions := VBoxContainer.new(); row.add_child(actions)
		ui.button(actions,"교체",func(): replace(ui,slot),can_invest(ui,actor))
		var auto = ui.button(actions,"자동 ON" if rule.enabled else "자동 OFF",func(): ui.session.update_rule(ui.tactics_actor,index,"enabled",not rule.enabled); ui.refresh(); ui.show_tactics())
		auto.toggle_mode = true; auto.button_pressed = rule.enabled
		var policy = ui.button(box,"사용 방침 · "+ui.Session.Rules.summary(rule)+"  ›",func(): ui.open_rule(index))
		policy.add_theme_font_size_override("font_size",11)
		policy.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

static func replace(ui, slot: int) -> void:
	var index: int = ui.tactics_actor
	var actor: Dictionary = ui.session.party[index]
	ui.clear(ui.item_detail); text(ui.item_detail,"이능 교체",20)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(300,260); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; ui.item_detail.add_child(scroll)
	var list := VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(list)
	var count := 0
	for id in actor.learned_abilities:
		if id in actor.equipped_abilities: continue
		count += 1
		ui.button(list,ui.Session.Rules.SKILLS[id].name,func():
			if ui.session.equip_ability(index,slot,id):
				ui.item_popup.hide(); ui.refresh(); ui.show_character(index,"이능"),can_invest(ui,actor))
	if count == 0: text(list,"교체 가능한 이능 없음")
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
