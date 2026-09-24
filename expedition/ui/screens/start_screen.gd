extends RefCounted
## The start screen: the kit picker and the two ways out of it — a new run or
## the battle-test setup. Moved out of main.gd; the state still lives on `ui`.
const Session = preload("res://expedition/run/session.gd")
const AutoBattleHud = preload("res://expedition/ui/screens/autobattle_hud.gd")
const CharacterUI = preload("res://expedition/ui/screens/character_folio.gd")
const Art = preload("res://expedition/art/mobile_art.gd")
const START_MOCKUP = preload("res://assets/ui/start-background.png")

static func build_start_screen(ui) -> void:
	var box := VBoxContainer.new(); box.name = "StartScreen"; box.size_flags_vertical = Control.SIZE_EXPAND_FILL; ui.root_layout.add_child(box)
	box.add_theme_constant_override("separation",7)
	var scene_art := TextureRect.new(); scene_art.name = "StartArt"
	var scene_crop := AtlasTexture.new(); scene_crop.atlas = START_MOCKUP; scene_crop.region = Rect2(0,0,853,640)
	scene_art.texture = scene_crop; scene_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scene_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	scene_art.custom_minimum_size.y = minf(300,ui.get_viewport_rect().size.y*0.35)
	box.add_child(scene_art)
	var hero := PanelContainer.new(); hero.name = "StartHero"
	hero.add_theme_stylebox_override("panel",CharacterUI.surface(Color("1b1916"))); box.add_child(hero)
	var hero_row := HBoxContainer.new(); hero.add_child(hero_row)
	var portrait := TextureRect.new(); portrait.texture = Art.portrait_face(0)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(72,72); hero_row.add_child(portrait)
	var hero_name = ui.label(hero_row,"아린",20); hero_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var heading = ui.label(box,"시작 장비",18); heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_kit_picker(ui,box)
	var chosen: Dictionary = Session.CombatStats.kits().filter(func(k): return str(k.id) == ui.kit_choice)[0]
	var detail = ui.label(box,kit_detail(chosen),13); detail.name = "KitDetail"
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var spacer := Control.new(); spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL; box.add_child(spacer)
	var actions := HBoxContainer.new(); box.add_child(actions)
	var start = ui.button(actions,"새 탐험",func(): new_run(ui)); start.name = "NewRun"; start.custom_minimum_size.y = 56
	var arena = ui.button(actions,"전투 시험",ui.show_arena_setup); arena.name = "ArenaButton"; arena.custom_minimum_size.y = 56

## Ten kits, one per mastery axis: five weapons on the first row, five staves
## on the second. One is chosen at a time, and the chosen one wears the same
## gold border a selected member card does.
static func build_kit_picker(ui, parent: Node) -> void:
	var picker := VBoxContainer.new(); picker.name = "KitPick"; parent.add_child(picker)
	picker.add_theme_constant_override("separation",2)
	var kits: Array = Session.CombatStats.kits()
	for row in range(2):
		var line := HBoxContainer.new(); line.name = "KitRow%d" % row
		line.add_theme_constant_override("separation",4); picker.add_child(line)
		for kit in kits.slice(row*5,row*5+5):
			var id: String = str(kit.id)
			var detail: String = kit_detail(kit)
			var node = ui.button(line,"\n\n"+str(kit.name),func(): choose_kit(ui,id))
			node.name = "Kit_"+id
			node.custom_minimum_size = Vector2(0,70); node.clip_text = true
			node.add_theme_font_size_override("font_size",11)
			node.tooltip_text = "%s · %s\n%s" % [str(kit.name),str(kit.get("blurb","")),detail]
			var glyph = preload("res://expedition/art/mastery_glyph.gd").new()
			glyph.axis = str(kit.axis); glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
			node.add_child(glyph); glyph.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
			glyph.offset_left = -16; glyph.offset_right = 16; glyph.offset_top = 5; glyph.offset_bottom = 37
			if id == ui.kit_choice:
				ui.mark_selected(node)

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
	ui.mode_arena_setup = false; ui.mode_arena_active = false; ui.mode = ""; ui.pending_item = ""; ui.pending_attack = {}; ui.show_attack_range = false; ui.action_effects = []; ui.reset_effects = true
	AutoBattleHud.check_stop(ui); ui.refresh()

static func depart(ui) -> void:
	new_run(ui)
