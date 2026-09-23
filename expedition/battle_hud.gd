extends RefCounted
## Popups of the floor-mode auto-battle HUD: the battle report card, the stop
## options and the battle-start formation swap. Kept out of main.gd, which owns
## the board, the rows and the timer.
const CharacterUI = preload("res://expedition/character_ui.gd")
const Stances = preload("res://expedition/stances.gd")
const STOP_NAMES := {"BATTLE_START":"전투 시작","BATTLE_END":"전투 종료","DEATH":"아군 사망","ALLY_LETHAL":"치명 위기","HP_LOW":"체력 낮음"}
const HP_THRESHOLDS := [20,30,40,50]

## One battle, as the tallies saw it: the header, a row per member, what the
## enemies used, what dropped. A downed member is coloured and brings the log.
static func report(ui) -> void:
	var s = ui.session
	ui.clear(ui.modal_content); ui.modal_content.custom_minimum_size.y = 0
	var card := PanelContainer.new(); card.name = "BattleReport"
	card.add_theme_stylebox_override("panel",CharacterUI.surface(Color("151c24")))
	ui.modal_content.add_child(card)
	var list := VBoxContainer.new(); list.add_theme_constant_override("separation",4); card.add_child(list)
	var stats: Dictionary = s.battle_stats
	var downed: int = s.party.filter(func(a): return a.hp <= 0).size()
	line(ui,list,"전투 종료 · %d라운드 · 적 %d 처치 · 아군 사망 %d" % [int(stats.get("rounds",0)),int(stats.get("kills",0)),downed],17)
	for actor in s.party:
		var row: Dictionary = s.member_stats(actor.id)
		if row.is_empty(): continue
		var text := "%s · 입힘 %d · 받음 %d · 엄호 %d회/%d · 파츠 %s" % [actor.name,int(row.dealt),int(row.taken),int(row.guards),int(row.redirected),used(ui,row.parts)]
		text += role(actor,row)
		if bool(row.conflict): text += " · 갈등"
		var entry := line(ui,list,text,13)
		if bool(row.downed) or actor.hp <= 0: entry.add_theme_color_override("font_color",Color("d1685f"))
	line(ui,list,"적 파츠: %s · 끊김 %d" % [used(ui,stats.get("enemy_parts",{})),int(stats.get("interrupts",0))],12)
	line(ui,list,"획득: %s" % used(ui,stats.get("drops",{})),12)
	if downed > 0:
		for entry in s.log_lines.slice(maxi(0,s.log_lines.size()-3)): line(ui,list,entry,11)
	ui.button(list,"파츠·규칙 보기",func(): ui.show_character(0,"파츠"))
	ui.button(list,"닫기",func(): ui.details_popup.hide())
	ui.details_popup.popup_centered()

## How much of the battle the member spent where its stance wanted it, and the
## one build mistake the stance cannot work around.
static func role(actor: Dictionary, row: Dictionary) -> String:
	var rounds: Dictionary = row.get("role_rounds",{"in_role":0,"total":0})
	var stance: String = Stances.effective(actor)
	var line := " · 역할 %s %d/%d" % [Stances.NAMES[stance],int(rounds.in_role),int(rounds.total)]
	if stance == "SKIRMISHER" and Stances.ranged_part(actor).is_empty(): line += " · 원거리 파츠 없음"
	return line

static func line(ui, parent: Node, text: String, font_size: int) -> Label:
	var node: Label = ui.label(parent,text,font_size)
	node.custom_minimum_size.x = ui.popup_width()-24
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node

## "밀치기×2, 엄호×1" out of a {part_id: count} tally.
static func used(ui, counts: Dictionary) -> String:
	var parts: Array = []
	for id in counts:
		parts.append("%s×%d" % [ui.Session.Rules.skill(id).get("name",id),int(counts[id])])
	return ", ".join(parts) if not parts.is_empty() else "없음"

## Which events stop the run, and where "체력 낮음" sits.
static func options(ui) -> void:
	ui.clear(ui.modal_content); ui.modal_content.custom_minimum_size.y = 0
	var box := VBoxContainer.new(); box.name = "AutoOptions"; ui.modal_content.add_child(box)
	ui.label(box,"자동 진행 정지 조건",18)
	for id in ui.Session.AUTO_STOPS:
		var toggle := CheckButton.new(); toggle.name = "Stop_"+id; toggle.text = STOP_NAMES[id]
		toggle.button_pressed = bool(ui.session.auto.stops.get(id,false)); toggle.custom_minimum_size.y = 44
		box.add_child(toggle)
		toggle.toggled.connect(func(value): ui.session.auto.stops[id] = value)
	ui.label(box,"체력 낮음 기준",14)
	var pick := OptionButton.new(); pick.name = "HpThreshold"; pick.custom_minimum_size = Vector2(0,44)
	for value in HP_THRESHOLDS: pick.add_item("%d%%" % value)
	pick.select(maxi(0,HP_THRESHOLDS.find(int(ui.session.auto.hp_low))))
	box.add_child(pick)
	pick.item_selected.connect(func(index): ui.session.auto.hp_low = HP_THRESHOLDS[index])
	ui.button(box,"닫기",func(): ui.details_popup.hide())
	ui.details_popup.popup_centered()

## Two taps: pick a member, pick who trades places with them.
static func formation(ui) -> void:
	ui.clear(ui.modal_content); ui.modal_content.custom_minimum_size.y = 0
	ui.label(ui.modal_content,"자리를 바꿀 두 사람" if ui.formation_pick < 0 else "누구와 바꿀까요",18)
	for i in range(ui.session.party.size()):
		var index := i
		var actor: Dictionary = ui.session.party[i]
		ui.button(ui.modal_content,actor.name+(" ✓" if ui.formation_pick == i else ""),func(): ui.pick_formation(index),actor.hp > 0)
	ui.button(ui.modal_content,"닫기",func(): ui.formation_pick = -1; ui.details_popup.hide())
	ui.details_popup.popup_centered()
