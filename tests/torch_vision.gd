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
	check(s.floor_state.visible.size() == 81 and not s.floor_state.visible.has(Vector2i(54,54)),"full torch reveals a radius-five circle, not square corners")
	var previous := 101
	for brightness in [100,80,60,40,20,0]:
		s.light = brightness; s.floor_state.observe(s)
		check(s.floor_state.visible.size() <= previous,"visibility shrinks monotonically")
		previous = s.floor_state.visible.size()
	check(previous == 13 and s.floor_state.visible.has(Vector2i(52,50)) and not s.floor_state.visible.has(Vector2i(52,52)),"darkness retains a radius-two circle")
	check(s.floor_state.explored.size() == 81,"darkness preserves discovered terrain memory")
	s.enemies[0].hp = 20; s.enemies[0].pos = Vector2i(53,50)
	s.floor_state.observe(s)
	check(s.combat_enemies().is_empty() and not s.auto_attack(),"enemy outside dark vision cannot be auto targeted")
	check(s.use_torch() and s.light == 50 and s.floor_state.visible.has(Vector2i(53,50)),"lighting torch expands sight immediately")
	s.enemies[0].hp = 0
	s.light = 100; s.tile(Vector2i(51,50)).terrain = "wall"; s.floor_state.observe(s)
	check(not s.floor_state.visible.has(Vector2i(52,50)),"walls still block light")
	s.tile(Vector2i(51,50)).terrain = "stone"
	s.light = 9; s.round_number = 19; s.floor_state.observe(s)
	check(s.floor_state.visible.size() == 21,"pre-decay threshold")
	s.act("WAIT",s.party[0].pos)
	check(s.light == 7 and s.floor_state.visible.size() == 13,"light decay updates visibility in the same turn")
	var glow = preload("res://expedition/radial_light.gd").new()
	check(glow.darkness(0,5) == 0 and glow.darkness(2,5) < glow.darkness(4,5) and glow.darkness(6,5) > 0.9,"continuous radial fade darkens with distance")
	var mesh = glow.get_mesh(Vector2(195,195),Vector2(390,430),39,5)
	check(mesh.get_surface_count() == 1,"radial overlay mesh built")
	glow.get_mesh(Vector2(195,195),Vector2(390,430),39,5)
	check(glow.builds == 1,"VFX redraws reuse radial mesh")
	glow.get_mesh(Vector2(195,195),Vector2(390,430),39,2)
	check(glow.builds == 2,"torch radius invalidates mesh")
	print("Torch vision: %d failures" % failures); quit(1 if failures else 0)
