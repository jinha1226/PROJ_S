extends SceneTree
## Every active a member can use has its own icon (tools/art/build_skill_icons.py),
## and the battle skill menu shows it.
const Session = preload("res://expedition/run/session.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Art = preload("res://expedition/art/mobile_art.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Essences = preload("res://expedition/progression/essences.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	for id in Abilities.DEFINITIONS:
		# What a member can actually get: a soul stone's active, or a basic action.
		if bool(Abilities.DEFINITIONS[id].get("monster_only",false)): continue
		if not Essences.has(id) and id not in ["PUSH","GUARD"]: continue
		var icon: AtlasTexture = Art.part_icon(id)
		check(icon != null and icon.atlas != null and icon.atlas.resource_path.contains("items-v1/skills/%s.png" % id),"%s has its own skill icon" % id)
	check(Art.part_icon("GOBLIN_SHIV@fire").atlas.resource_path.contains("skills/GOBLIN_SHIV.png"),"a variant uses its base skill's icon")
	check(Art.part_icon("FIRE_CALLER") != null,"a monster-only part still gets some icon")
	await menu()
	print("Skill icons: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func menu() -> void:
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	var s = Session.new_run(731)
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene)
	for f in range(4): await process_frame
	var c: Vector2i = Fixture.arena(s,8)
	s.phase = "CAMP"; s.parts_bag["GOBLIN_SHIV"] = 1
	check(s.equip_part(0,0,"GOBLIN_SHIV"),"the hero slots the goblin's stone")
	s.end_camp()
	var foe: Dictionary = s.enemies[0]
	foe.hp = 40; foe.max_hp = 40; foe.pos = c+Vector2i(3,0); foe.alert = true
	s.floor_state.observe(s)
	scene.refresh()
	for f in range(2): await process_frame
	scene.FloorHud.show_manual_skills(scene)
	for f in range(2): await process_frame
	var button = scene.modal_content.find_child("Part_GOBLIN_SHIV",true,false)
	check(button != null and button.icon != null and button.icon.atlas.resource_path.contains("skills/GOBLIN_SHIV.png"),"the skill menu shows the skill's icon")
