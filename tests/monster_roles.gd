extends SceneTree
const Session = preload("res://expedition/session.gd")
const AI = preload("res://expedition/actors/monster_ai.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; push_error(label)
func fixture(role: String) -> Dictionary:
	var s = Session.new(731,true,true,true); s.depart()
	for tile in s.tiles: tile.terrain = "stone"
	var c := Fixture.arena(s,10)
	Fixture.equip_basics(s)
	s.party[1].hp = 0
	var e: Dictionary = s.enemies[0]
	# Role behaviour only: the signature part is tested in tests/parts.gd and would go first.
	e.hp = e.max_hp; e.role = role; e.pos = c+Vector2i(4,0); e.alert = true; e.part_id = ""
	return {"s":s,"c":c}
func _initialize() -> void:
	var f := fixture("MELEE"); var s = f.s; var c: Vector2i = f.c
	var e: Dictionary = s.enemies[0]
	var hp: int = s.party[0].hp
	AI.turn(s,e)
	check(AI.distance(e.pos,s.party[0].pos) == 3 and s.party[0].hp == hp,"chaser moves without attacking")
	e.pos = c+Vector2i(1,1); AI.turn(s,e)
	check(s.party[0].hp < hp,"diagonal melee attack")
	f = fixture("RANGED"); s = f.s; c = f.c; e = s.enemies[0]; hp = s.party[0].hp
	AI.turn(s,e)
	check(e.pos == c+Vector2i(4,0) and s.party[0].hp < hp,"shooter attacks from range")
	e.pos = c+Vector2i(1,0); hp = s.party[0].hp; e.reload = 0; AI.turn(s,e)
	check(e.pos == c+Vector2i(1,0) and s.party[0].hp < hp,"adjacent shooter fights instead of endlessly retreating")
	# Reload: a volley, a round of reloading, a volley.
	f = fixture("RANGED"); s = f.s; c = f.c; e = s.enemies[0]; hp = s.party[0].hp
	AI.turn(s,e)
	check(s.party[0].hp < hp and int(e.reload) == 1,"a shot starts the reload")
	hp = s.party[0].hp; AI.turn(s,e)
	check(s.party[0].hp == hp and e.pos == c+Vector2i(4,0) and s.log_lines[-1].ends_with("재장전"),"reloading archer neither shoots nor shuffles")
	hp = s.party[0].hp; AI.turn(s,e)
	check(s.party[0].hp < hp,"shoots again after reloading")
	# Sight is symmetric: what the party cannot see cannot see the party.
	f = fixture("RANGED"); s = f.s; c = f.c; e = s.enemies[0]
	e.alert = false; e.pos = c+Vector2i(8,0); hp = s.party[0].hp
	AI.turn(s,e)
	check(not e.alert and s.party[0].hp == hp,"eight cells away beyond fixed sight: unseen and silent")
	e.pos = c+Vector2i(6,0); AI.turn(s,e)
	check(not e.alert and s.party[0].hp == hp,"six cells away: still unseen")
	e.pos = c+Vector2i(5,0); AI.turn(s,e)
	check(e.alert and s.party[0].hp < hp,"five cells away: seen, and the arrow flies")
	f = fixture("RANGED"); s = f.s; c = f.c; e = s.enemies[0]; hp = s.party[0].hp
	e.pos = c+Vector2i(6,0); e.alert = true; AI.turn(s,e)
	check(s.party[0].hp == hp,"an alert archer still cannot shoot beyond the shared sight radius")
	f = fixture("RANGED"); s = f.s; c = f.c; e = s.enemies[0]; hp = s.party[0].hp
	s.tile(c+Vector2i(2,0)).terrain = "wall"; AI.turn(s,e)
	check(s.party[0].hp == hp and e.pos != c+Vector2i(4,0),"blocked shooter repositions without shooting through wall")
	f = fixture("CASTER"); s = f.s; c = f.c; e = s.enemies[0]; hp = s.party[0].hp
	AI.turn(s,e); AI.turn(s,e)
	check(not e.charging and s.party[0].hp < hp,"caster starts with ordinary attacks")
	hp = s.party[0].hp; AI.turn(s,e); s.plan_enemies()
	check(e.charging and s.intents.size() == 1 and s.party[0].hp == hp,"windup costs full action and survives planning")
	s.party[0].pos += Vector2i.UP; AI.turn(s,e)
	check(not e.charging and s.intents.is_empty() and s.party[0].hp == hp,"cell-locked spell can be dodged")
	e.cast_cooldown = 0; AI.turn(s,e); hp = s.party[0].hp; AI.turn(s,e)
	check(s.party[0].hp < hp and not e.charging,"spell hits after full windup")
	e.cast_cooldown = 0; AI.turn(s,e)
	s.damage(e,1,s.party[0].id,"IMPACT")
	check(not e.charging and s.intents.is_empty(),"damage interrupts spell")
	hp = s.party[0].hp; AI.turn(s,e)
	check(s.party[0].hp == hp and e.cast_recovery == 0,"interruption loses next enemy action")
	e.cast_cooldown = 0; AI.turn(s,e)
	s.party[0].pos = e.pos+Vector2i.LEFT
	s.floor_state.observe(s)
	check(s.act("PUSH",e.pos),"push accepted")
	check(not e.charging and s.intents.is_empty(),"push cancels windup even without damage")
	f = fixture("CASTER"); s = f.s; c = f.c; e = s.enemies[0]; e.cast_cooldown = 0; AI.turn(s,e)
	s.damage(e,999,s.party[0].id,"IMPACT"); s.plan_enemies()
	check(s.intents.is_empty(),"dead caster leaves no warning")
	s = Session.new(731,true,true,true); s.depart()
	check(s.enemies.all(func(a): return a.role in AI.ROLES and a.name.ends_with(AI.ROLES[a.role].label)),"generated roles are labelled")
	check(s.enemies.any(func(a): return a.role != "MELEE"),"at least one backline enemy on the floor")
	print("Monster roles: %d failures" % failures); quit(1 if failures else 0)
