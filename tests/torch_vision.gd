extends SceneTree
const Session = preload("res://expedition/session.gd")
var failures := 0
func check(ok: bool, why: String) -> void:
	if not ok: failures += 1; push_error(why)
func _initialize() -> void:
	var s = Session.new(731,true,true,true); s.depart()
	for enemy in s.enemies: enemy.hp = 0
	s.party[1].hp = 0; s.party[0].pos = Vector2i(50,50)
	for y in range(30,71):
		for x in range(30,71): s.tile(Vector2i(x,y)).terrain = "stone"
	s.floor_state.explored.clear(); s.floor_state.discoveries.clear()
	s.light = 100; s.floor_state.observe(s)
	check(s.floor_state.visible.has(Vector2i(62,62)),"bright light covers zoomed-out viewport corners")
	check(Session.Floor.darkness_strength(100) == 0 and Session.Floor.darkness_strength(60) == 0,"bright torch removes radial shading")
	var discovered: int = s.floor_state.explored.size()
	var previous := discovered+1
	for brightness in [100,80,60,40,20,0]:
		s.light = brightness; s.floor_state.observe(s)
		check(s.floor_state.visible.size() <= previous,"visibility shrinks monotonically")
		previous = s.floor_state.visible.size()
	check(previous == 149 and s.floor_state.visible.has(Vector2i(57,50)) and not s.floor_state.visible.has(Vector2i(58,50)),"depleted torch retains previous maximum radius seven")
	check(Session.Floor.darkness_strength(30) == 0.5 and Session.Floor.darkness_strength(0) == 1,"shade gradually returns below sixty light")
	check(s.floor_state.explored.size() == discovered,"darkness preserves discovered terrain memory")
	s.enemies[0].hp = 20; s.enemies[0].pos = Vector2i(58,50)
	s.floor_state.observe(s)
	check(s.combat_enemies().is_empty() and not s.auto_attack(),"enemy outside dark vision cannot be auto targeted")
	check(s.use_torch() and s.light == 50 and s.floor_state.visible.has(Vector2i(58,50)),"lighting torch expands sight immediately")
	s.enemies[0].hp = 0
	s.light = 100; s.tile(Vector2i(51,50)).terrain = "wall"; s.floor_state.observe(s)
	check(not s.floor_state.visible.has(Vector2i(52,50)),"walls still block light")
	s.tile(Vector2i(51,50)).terrain = "stone"
	s.light = 6; s.round_number = 19; s.floor_state.observe(s)
	check(s.floor_state.visible.has(Vector2i(58,50)),"pre-decay threshold")
	s.act("WAIT",s.party[0].pos)
	check(s.light == 5 and not s.floor_state.visible.has(Vector2i(58,50)),"light decay updates visibility in the same turn")
	var glow = preload("res://expedition/radial_light.gd").new()
	check(glow.darkness(0,5) == 0 and glow.darkness(2,5) < glow.darkness(4,5) and glow.darkness(6,5) > 0.9,"continuous radial fade darkens with distance")
	var mesh = glow.get_mesh(Vector2(195,195),Vector2(390,430),39,5)
	check(mesh.get_surface_count() == 1,"radial overlay mesh built")
	glow.get_mesh(Vector2(195,195),Vector2(390,430),39,5)
	check(glow.builds == 1,"VFX redraws reuse radial mesh")
	glow.get_mesh(Vector2(195,195),Vector2(390,430),39,2)
	check(glow.builds == 2,"torch radius invalidates mesh")
	print("Torch vision: %d failures" % failures); quit(1 if failures else 0)
