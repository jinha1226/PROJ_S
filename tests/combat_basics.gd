extends SceneTree
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)

func run() -> void:
	var s = Session.new_run(311)
	var c: Vector2i = Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 100; foe.max_hp = 100; foe.pos = c+Vector2i(1,1)
	foe.ready_at = 1000
	s.tile(c+Vector2i(1,0)).terrain = "wall"
	s.floor_state.observe(s)
	check(s.melee_reach(c,foe.pos),"one-wall corner permits diagonal melee")
	check(s.walk_reach(c,foe.pos),"one-wall corner permits diagonal movement geometry")
	check(not s.attack_preview(foe.pos).is_empty(),"diagonal enemy is a legal attack target")
	check(s.submit("ATTACK",foe.pos),"diagonal attack executes through an open corner")
	s.tile(c+Vector2i(0,1)).terrain = "wall"
	s.floor_state.observe(s)
	check(s.melee_reach(c,foe.pos),"two-wall corner permits diagonal melee like movement")
	check(s.walk_reach(c,foe.pos),"two-wall corner retains the established diagonal movement")
	check(not s.attack_preview(foe.pos).is_empty(),"two-wall corner has an attack preview")
	s.phase = "BATTLE"; s.party[0].ap = 1; s.party[0].equipped_abilities = ["PUSH"]
	check(Session.Abilities.legal(s,s.party[0],"PUSH",foe.pos),"adjacent push uses the same diagonal rule")
	foe.hp = 0
	s.tile(c+Vector2i(1,0)).terrain = "stone"
	s.tile(c+Vector2i(0,1)).terrain = "stone"
	s.floor_state.observe(s)
	check(s.floor_state.visible.has(c+Vector2i(4,4)),"near diagonals are visible in an open room")
	check(s.floor_state.visible.has(c+Vector2i(6,0)),"six-tile cardinal sight is visible in an open room")
	check(not s.floor_state.visible.has(c+Vector2i(6,6)),"far corner stays outside sight")
	check(not s.floor_state.visible.has(c+Vector2i(7,0)),"sight ends after six tiles")
	s.tile(c+Vector2i(6,4)).terrain = "wall"
	s.floor_state.observe(s)
	check(s.floor_state.visible.has(c+Vector2i(6,4)),"the edge wall of a visible room remains legible")
	s.tile(c+Vector2i(1,0)).terrain = "wall"
	s.floor_state.observe(s)
	check(s.floor_state.visible.has(c+Vector2i(1,0)),"blocking wall itself remains visible")
	check(not s.floor_state.visible.has(c+Vector2i(2,0)),"enemy cells beyond a wall remain hidden")
	print("Combat basics: %d failures" % failures)
	quit(1 if failures else 0)
