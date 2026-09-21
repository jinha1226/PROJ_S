extends SceneTree
const Session = preload("res://expedition/session.gd")
const AI = preload("res://expedition/monster_ai.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; push_error(label)
func fixture(role: String):
	var s = Session.new(731,true,true,true); s.depart()
	for tile in s.tiles: tile.terrain = "stone"
	for enemy in s.enemies: enemy.hp = 0
	s.party[0].pos = Vector2i(50,50); s.party[1].hp = 0
	var e: Dictionary = s.enemies[0]
	e.hp = e.max_hp; e.role = role; e.pos = Vector2i(54,50); e.alert = true
	return s
func _initialize() -> void:
	var s = fixture("MELEE"); var e: Dictionary = s.enemies[0]
	var hp: int = s.party[0].hp
	AI.turn(s,e)
	check(AI.distance(e.pos,s.party[0].pos) == 3 and s.party[0].hp == hp,"chaser moves without attacking")
	e.pos = Vector2i(51,51); AI.turn(s,e)
	check(s.party[0].hp < hp,"diagonal melee attack")
	s = fixture("RANGED"); e = s.enemies[0]; hp = s.party[0].hp
	AI.turn(s,e)
	check(e.pos == Vector2i(54,50) and s.party[0].hp < hp,"shooter attacks from range")
	e.pos = Vector2i(51,50); hp = s.party[0].hp; AI.turn(s,e)
	check(e.pos == Vector2i(51,50) and s.party[0].hp < hp,"adjacent shooter fights instead of endlessly retreating")
	s = fixture("RANGED"); e = s.enemies[0]; hp = s.party[0].hp
	s.tile(Vector2i(52,50)).terrain = "wall"; AI.turn(s,e)
	check(s.party[0].hp == hp and e.pos != Vector2i(54,50),"blocked shooter repositions without shooting through wall")
	s = fixture("CASTER"); e = s.enemies[0]; hp = s.party[0].hp
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
	s = fixture("CASTER"); e = s.enemies[0]; e.cast_cooldown = 0; AI.turn(s,e)
	s.damage(e,999,s.party[0].id,"IMPACT"); s.plan_enemies()
	check(s.intents.is_empty(),"dead caster leaves no warning")
	s = Session.new(731,true,true,true); s.depart()
	check(s.enemies.filter(func(a): return a.role == "MELEE").size() == 5,"five melee units")
	check(s.enemies.filter(func(a): return a.role == "RANGED").size() == 2,"two ranged units")
	check(s.enemies.filter(func(a): return a.role == "CASTER").size() == 2,"two casters")
	print("Monster roles: %d failures" % failures); quit(1 if failures else 0)
