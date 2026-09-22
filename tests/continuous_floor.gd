extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for seed_value in range(10):
		var sample = Session.new(seed_value,true,true,true); sample.depart()
		var seen: Dictionary = {sample.party[0].pos:true}
		var queue: Array = [sample.party[0].pos]
		var cursor := 0
		while cursor < queue.size():
			var p: Vector2i = queue[cursor]; cursor += 1
			for direction in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
				var next: Vector2i = p+direction
				if not seen.has(next) and sample.inside(next) and sample.tile(next).terrain != "wall":
					seen[next] = true; queue.append(next)
		for p in sample.floor_state.features: check(seen.has(p) or sample.DIRECTIONS.any(func(d): return seen.has(p+d)),"feature reachable across floor")
		for enemy in sample.enemies: check(seen.has(enemy.pos),"enemy reachable across floor")
	var s = Session.new(731,true,true,true)
	check(s.depart() and s.tiles.size() == s.BOARD_SIDE*s.BOARD_SIDE and s.BOARD_SIDE == 64,"one continuous 64x64 floor")
	check(s.rooms.size() == 1 and s.doors().is_empty(),"no room travel graph")
	check(s.enemies.size() >= 3 and s.enemies.size() <= 20 and s.floor_state.layout.encounters.size() >= 3,"generated roster grouped into encounters")
	check(s.enemies.all(func(e): return e.part_id == Session.Abilities.species_part(e.species_id)),"floor monsters carry their species part")
	check(s.floor_state.explored.size() < s.BOARD_SIDE*s.BOARD_SIDE,"unexplored fog retained")
	check(s.safe_management(),"safe exploration permits management")
	s.light = 50
	check(s.use_torch() and s.light == 100,"torch works during safe floor exploration")
	var enemy_positions: Array = s.enemies.map(func(e): return e.pos)
	check(not s.auto_attack(),"auto attack cannot target unseen enemies")
	s.act("WAIT",s.party[0].pos)
	check(s.enemies.map(func(e): return e.pos) == enemy_positions,"distant enemies remain asleep")
	var before: Vector2i = s.party[1].pos
	for i in range(3): check(s.act("MOVE",s.party[0].pos+Vector2i.RIGHT),"walk consumes one action")
	check(s.party[1].pos != before and s.distance(s.party[0].pos,s.party[1].pos) <= 3,"companion follows during exploration")
	var foe: Dictionary = s.enemies[0]
	s.party[0].pos = Fixture.beside(s,foe.pos)
	check(s.party[0].pos.x >= 0,"adjacent free cell exists")
	s.party[1].pos = Fixture.beside(s,s.party[0].pos)
	check(s.party[1].pos.x >= 0,"adjacent free cell exists")
	s.floor_state.observe(s)
	var hp: int = s.party[0].hp
	foe.part_id = "" # Role behaviour only; the signature part would be announced first (tests/parts.gd).
	s.floor_state.enemy_turn(s,foe)
	check(s.party[0].hp < hp,"legacy tactical selector attacks adjacent enemy")
	var scene = load("res://expedition/main.gd").new(); scene.session = s
	root.size = Vector2i(390,844); root.add_child(scene)
	for frame in range(3): await process_frame
	var camera: Vector2i = scene.board.camera_cell()
	for y in range(10):
		for x in range(10):
			var p := camera+Vector2i(x,y)
			check(scene.board.cell_at(scene.board.cell_center(p)) == p,"camera-aware input")
	for tab in ["상태","파츠","숙련"]:
		scene.show_character(0,tab); await process_frame
		var panel = scene.details_popup.get_theme_stylebox("panel","PopupPanel")
		check(panel is StyleBoxFlat and panel.bg_color.a == 1,"character popup opaque")
		check(scene.details_popup.size.x <= root.size.x and scene.details_popup.size.y <= root.size.y,"opaque character window fits viewport")
		scene.show_supplies(); await process_frame
		panel = scene.details_popup.get_theme_stylebox("panel","PopupPanel")
		check(panel is StyleBoxFlat and panel.bg_color.a == 1,"bag restores opaque background")
		scene.show_item_detail("supply:0"); await process_frame
		check(scene.item_popup.get_theme_stylebox("panel","PopupPanel") is StyleBoxFlat,"item detail opaque")
	scene.show_map(); await process_frame
	check(scene.map_view.floor_minimap != null,"original minimap connected")
	check(scene.map_view.floor_minimap.cell_draw_spec(s.party[0].pos).marker == "HERO","first minimap observation includes hero")
	var spec: Dictionary = scene.map_view.floor_minimap.cell_draw_spec(Vector2i(s.BOARD_SIDE-1,s.BOARD_SIDE-1))
	check(spec.visibility_state == "UNSEEN" and spec.marker == "","minimap hides unexplored enemies")
	scene.queue_free(); await process_frame
	print("Continuous floor: %d failures" % failures); quit(1 if failures else 0)
