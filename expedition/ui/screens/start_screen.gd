extends RefCounted
## The start screen: the kit picker and the two ways out of it — a new run or
## the battle-test setup. Moved out of main.gd; the state still lives on `ui`.
const Session = preload("res://expedition/run/session.gd")
const AutoBattleHud = preload("res://expedition/ui/screens/autobattle_hud.gd")

static func build_start_screen(ui) -> void:
	var box := VBoxContainer.new(); box.name = "StartScreen"; box.size_flags_vertical = Control.SIZE_EXPAND_FILL; ui.root_layout.add_child(box)
	ui.label(box,"하강",26)
	ui.label(box,"시작 장비",15)
	build_kit_picker(ui,box)
	var start = ui.button(box,"새 탐험",func(): new_run(ui)); start.name = "NewRun"
	var arena = ui.button(box,"전투 시험",ui.show_arena_setup); arena.name = "ArenaButton"

## Ten kits, one per mastery axis: five weapons on the first row, five staves
## on the second. One is chosen at a time, and the chosen one wears the same
## gold border a selected member card does.
static func build_kit_picker(ui, parent: Node) -> void:
	var picker := VBoxContainer.new(); picker.name = "KitPick"; parent.add_child(picker)
	picker.add_theme_constant_override("separation",2)
	var kits: Array = Session.CombatStats.kits()
	for row in range(2):
		var line := HBoxContainer.new(); line.name = "KitRow%d" % row
		line.add_theme_constant_override("separation",2); picker.add_child(line)
		for kit in kits.slice(row*5,row*5+5):
			var id: String = str(kit.id)
			var detail: String = kit_detail(kit)
			var node = ui.button(line,"%s\n%s" % [str(kit.name),detail],func(): choose_kit(ui,id))
			node.name = "Kit_"+id
			node.custom_minimum_size = Vector2(0,48); node.clip_text = true
			node.add_theme_font_size_override("font_size",11)
			node.tooltip_text = "%s · %s\n%s" % [str(kit.name),str(kit.get("blurb","")),detail]
			if id == ui.kit_choice:
				var gold = node.get_theme_stylebox("normal").duplicate(); gold.border_color = Color("e9c575")
				gold.set_border_width_all(2); node.add_theme_stylebox_override("normal",gold)

## What the kit is, in one line: a weapon's numbers, or the spell it comes with.
static func kit_detail(kit: Dictionary) -> String:
	var content: Dictionary = Session.CombatStats.content
	var spell_id: String = str(kit.get("spell",""))
	if spell_id.is_empty():
		var weapon: Dictionary = content.weapons.get(str(kit.weapon),{})
		return "피해 %d · 속도 %d · 사거리 %d" % [int(weapon.get("damage",0)),int(weapon.get("delay",100)),int(weapon.get("range",1))]
	return "%s · %s" % [str(content.spells.get(spell_id,{}).get("name","")),str(kit.get("blurb",""))]

static func choose_kit(ui, id: String) -> void:
	ui.kit_choice = id; ui.refresh()

static func new_run(ui) -> void:
	ui.session = Session.new_run(randi(),ui.kit_choice)
	ui.stop_text = ""; ui.battle_reported = false
	ui.mode_arena_setup = false; ui.mode_arena_active = false; ui.mode = ""; ui.pending_item = -1; ui.pending_attack = {}; ui.show_attack_range = false; ui.action_effects = []; ui.reset_effects = true
	AutoBattleHud.check_stop(ui); ui.refresh()

static func depart(ui) -> void:
	new_run(ui)
