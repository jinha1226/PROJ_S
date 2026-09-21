extends SceneTree
const Session = preload("res://expedition/session.gd")
var failures := 0
func check(ok: bool, why: String) -> void:
	if not ok: failures += 1; push_error(why)
func _initialize() -> void:
	var s = Session.new(731,true,true,true); s.depart()
	for enemy in s.enemies: enemy.hp = 0
	s.party[1].hp = 0; s.party[0].pos = Vector2i(50,50)
	for y in range(40,61):
		for x in range(40,61): s.tile(Vector2i(x,y)).terrain = "stone"
	s.floor_state.explored.clear(); s.floor_state.discoveries.clear()
	s.light = 100; s.floor_state.observe(s)
	check(s.floor_state.visible.size() == 100,"full torch reveals 10x10 per observer")
	var previous := 101
	for brightness in [100,80,60,40,20,0]:
		s.light = brightness; s.floor_state.observe(s)
		check(s.floor_state.visible.size() <= previous,"visibility shrinks monotonically")
		previous = s.floor_state.visible.size()
	check(previous == 25 and s.floor_state.visible.has(Vector2i(52,52)) and not s.floor_state.visible.has(Vector2i(53,50)),"darkness retains only two surrounding tiles")
	check(s.floor_state.explored.size() == 100,"darkness preserves discovered terrain memory")
	s.enemies[0].hp = 20; s.enemies[0].pos = Vector2i(54,50)
	s.floor_state.observe(s)
	check(s.combat_enemies().is_empty() and not s.auto_attack(),"enemy outside dark vision cannot be auto targeted")
	check(s.use_torch() and s.light == 50 and s.floor_state.visible.has(Vector2i(54,50)),"lighting torch expands sight immediately")
	s.enemies[0].hp = 0
	s.light = 100; s.tile(Vector2i(51,50)).terrain = "wall"; s.floor_state.observe(s)
	check(not s.floor_state.visible.has(Vector2i(52,50)),"walls still block light")
	s.tile(Vector2i(51,50)).terrain = "stone"
	s.light = 10; s.round_number = 19; s.floor_state.observe(s)
	check(s.floor_state.visible.size() == 36,"pre-decay threshold")
	s.act("WAIT",s.party[0].pos)
	check(s.light == 8 and s.floor_state.visible.size() == 25,"light decay updates visibility in the same turn")
	print("Torch vision: %d failures" % failures); quit(1 if failures else 0)
