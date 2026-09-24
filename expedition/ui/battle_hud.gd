extends RefCounted
## The one popup of the floor-mode auto-battle HUD: the battle report card.
## Kept out of main.gd, which owns the board, the rows and the timer.
const CharacterUI = preload("res://expedition/ui/screens/character_folio.gd")
const Stances = preload("res://expedition/ai/stances.gd")

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
		text += " · 실수 %d" % int(row.get("mistakes",0))
		var entry := line(ui,list,text,13)
		if bool(row.downed) or actor.hp <= 0: entry.add_theme_color_override("font_color",Color("d1685f"))
	line(ui,list,"적 파츠: %s · 끊김 %d" % [used(ui,stats.get("enemy_parts",{})),int(stats.get("interrupts",0))],12)
	line(ui,list,"획득: %s" % used(ui,stats.get("drops",{})),12)
	if downed > 0:
		for entry in s.log_lines.slice(maxi(0,s.log_lines.size()-3)): line(ui,list,entry,11)
	ui.button(list,"파츠·규칙 보기",func(): ui.show_character(0,"파츠"))
	# A battle test ends where it began: back to the setup screen, or straight
	# into the same fight again.
	if ui.mode_arena_active:
		var again := HBoxContainer.new(); again.add_theme_constant_override("separation",4); list.add_child(again)
		ui.button(again,"설정으로",ui.show_arena_setup)
		ui.button(again,"다시",ui.start_arena)
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
