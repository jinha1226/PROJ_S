extends SceneTree
## 엄호: a party member stands in front of an adjacent ally for the round and
## takes their hits at half. Covers the act() guard, the redirect in damage(),
## the round reset and the two UI paths (party and solo).
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Rules = preload("res://expedition/tactic_rules.gd")
const Tactics = preload("res://expedition/tactical_action_selector.gd")
const MonsterAI = preload("res://expedition/monster_ai.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

## `size` members in a column from the arena centre, `foes` revived enemies the
## caller places. party[1] is always in contact with the hero, party[2] is not.
func arena(size: int = 3, foes: int = 0) -> Dictionary:
	var s = Session.new(731,true,size > 1,true,size); s.depart()
	var c := Fixture.arena(s,8)
	s.simulation_arena = true; s.phase = "BATTLE"
	Fixture.equip_basics(s)
	s.selected = 0
	s.intents.clear()
	var revived: Array = []
	for i in range(foes):
		var foe: Dictionary = s.enemies[i]
		foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.charging = false
		foe.cast_recovery = 0; foe.cast_cooldown = 0
		foe.pos = c+Vector2i(1,1+i)
		revived.append(foe)
	s.floor_state.observe(s)
	# The hero keeps a spare action so the probe never rolls into end_round, and
	# the companions keep none so their own turns cannot disturb the case.
	for actor in s.party: actor.ap = 0
	s.party[0].ap = 3
	return {"s":s,"c":c,"hero":s.party[0],"ally":s.party[1],"foes":revived}

func run() -> void:
	check(Rules.defaults().is_empty() and Rules.skill("GUARD").conditions == ["ALLY_LETHAL"],"엄호 comes with its part, not as a default rule")
	legality()
	redirect()
	caster_intent()
	expiry()
	dead_protector()
	mutual_guard()
	fixed_intent()
	victory_clears()
	await user_interface()
	print("Protect: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func legality() -> void:
	var f := arena(3,1)
	var hero: Dictionary = f.hero
	var ap: int = hero.ap
	check(not f.s.act("GUARD",hero.pos),"a member cannot guard their own cell")
	check(not f.s.act("GUARD",f.s.party[2].pos),"a member two cells away cannot be covered")
	check(not f.s.act("GUARD",f.foes[0].pos),"an enemy cannot be covered")
	f.ally.hp = 0
	check(not f.s.act("GUARD",f.ally.pos),"a downed ally cannot be covered")
	check(hero.ap == ap,"a rejected 엄호 costs nothing")
	f.ally.hp = 40
	check(f.s.act("GUARD",f.ally.pos) and hero.ap == ap-1,"엄호 covers an adjacent living ally")
	check(hero.guarded and f.ally.protected_by == hero.id,"엄호 marks the protector and the protected")
	check(f.s.log_lines.any(func(line): return line.contains("엄호 →")),"엄호 is logged")

func redirect() -> void:
	var f := arena(3,1)
	check(f.s.act("GUARD",f.ally.pos),"엄호 for the redirect case")
	var ally_hp: int = f.ally.hp
	var hero_hp: int = f.hero.hp
	f.s.damage(f.ally,10,f.foes[0].id,"IMPACT")
	check(f.ally.hp == ally_hp,"the covered ally is untouched")
	check(f.hero.hp == hero_hp-5,"the protector takes the hit at half")
	check(f.s.member_stats(f.s.party[0].id).covers == 1,"the redirect is counted")
	check(f.s.log_lines.any(func(line): return line.contains("대신 맞습니다")),"the redirect is logged")

func caster_intent() -> void:
	var f := arena(3,1)
	var caster: Dictionary = f.foes[0]
	caster.role = "CASTER"; caster.pos = f.c+Vector2i(3,1)
	caster.charging = true; caster.cast_cell = f.ally.pos
	f.s.floor_state.observe(f.s)
	MonsterAI.plan(f.s)
	check(f.s.intents.any(func(i): return i.cell == f.ally.pos),"the wind-up is announced on the ally's cell")
	check(f.s.act("GUARD",f.ally.pos),"엄호 against the wind-up")
	var ally_hp: int = f.ally.hp
	var hero_hp: int = f.hero.hp
	MonsterAI.turn(f.s,caster)
	check(f.ally.hp == ally_hp,"the cell-locked spell does not reach the covered ally")
	check(f.hero.hp < hero_hp,"the protector eats the spell instead")

func expiry() -> void:
	var f := arena(3,0)
	check(f.s.act("GUARD",f.ally.pos),"엄호 before the round ends")
	f.s.end_round()
	check(not f.hero.guarded and f.ally.protected_by == -1,"엄호 expires with the round")
	var ally_hp: int = f.ally.hp
	f.s.damage(f.ally,10,999,"IMPACT")
	check(f.ally.hp == ally_hp-10,"after expiry the ally takes their own hits")

## A mutual guard has nobody left to step in: the hit comes back to the member
## it was aimed at, halved by their own guard, and nothing is counted or logged.
func mutual_guard() -> void:
	var f := arena(3,0)
	f.s.party[1].ap = 3
	check(f.s.act("GUARD",f.ally.pos),"the hero covers the ally")
	f.s.selected = 1
	check(f.s.act("GUARD",f.hero.pos),"the ally covers the hero back")
	var ally_hp: int = f.ally.hp
	var hero_hp: int = f.hero.hp
	f.s.damage(f.ally,10,999,"IMPACT")
	check(f.ally.hp == ally_hp-5 and f.hero.hp == hero_hp,"a mutual guard leaves the hit with its target, halved")
	check(f.s.member_stats(f.s.party[0].id).covers == 0,"a hit that never moved is not counted as a redirect")
	check(not f.s.log_lines.any(func(line): return line.contains("대신 맞습니다")),"a hit that never moved is not logged as a redirect")

## ALLY_LETHAL reads the announced damage with the fixed-sight combat rules.
func fixed_intent() -> void:
	var f := arena(3,1)
	check(f.s.floor_state.sight_radius() == 5.0,"the arena uses fixed sight")
	f.ally.hp = 14
	f.s.intents = [{"id":f.foes[0].id,"cell":f.ally.pos,"damage":14}]
	f.foes[0].hp = 0
	check(Rules.lethal_threat(f.s,f.ally) == 14,"the announced 14 remains 14")
	for actor in f.s.party: actor.rules = [Rules.make_rule("GUARD","ALLY","ALLY_LETHAL")]
	var choice: Dictionary = Tactics.choose(f.s,f.hero)
	check(choice.kind == "GUARD" and choice.cell == f.ally.pos,"엄호 fires on a lethal wind-up")

func dead_protector() -> void:
	var f := arena(3,0)
	check(f.s.act("GUARD",f.ally.pos),"엄호 before the protector falls")
	f.hero.hp = 0
	var ally_hp: int = f.ally.hp
	f.s.damage(f.ally,10,999,"IMPACT")
	check(f.ally.hp == ally_hp-10,"a fallen protector redirects nothing")
	check(f.s.member_stats(f.s.party[0].id).covers == 0,"no redirect is counted for a fallen protector")

## Clearing nearby foes on the continuous floor releases round guards.
func victory_clears() -> void:
	var s = Session.new(731,false,true,true,3); s.depart()
	Fixture.arena(s,8); Fixture.equip_basics(s)
	s.selected = 0
	var hero: Dictionary = s.party[0]
	var ally: Dictionary = s.party[1]
	ally.pos = hero.pos+Vector2i(1,0)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 10; foe.pos = hero.pos+Vector2i(2,0); s.floor_state.observe(s)
	check(s.act("GUARD",ally.pos),"엄호 before the last foe falls")
	for enemy in s.enemies: enemy.hp = 0
	s.floor_state.observe(s)
	check(s.end_round() and s.phase == "EXPLORE" and s.floor_state.safe(s),"the nearby fight clears by the round's end")
	check(ally.protected_by == -1 and not hero.guarded,"a cleared room does not carry 엄호 out of battle")

func user_interface() -> void:
	var scene = load("res://expedition/main.tscn").instantiate()
	scene.session = Session.new(731,true,true,true,3)
	scene.session.depart()
	root.size = Vector2i(390,844); root.add_child(scene)
	var c := Fixture.arena(scene.session,8)
	scene.session.simulation_arena = true; scene.session.phase = "BATTLE"
	Fixture.equip_basics(scene.session)
	scene.session.selected = 0
	for actor in scene.session.party: actor.ap = 0
	scene.session.party[0].ap = 3
	scene.refresh()
	for frame in range(3): await process_frame
	var hero: Dictionary = scene.session.party[0]
	var ally: Dictionary = scene.session.party[1]
	check(scene.skill_buttons.is_empty(),"auto-battle HUD has no manual skill row")
	scene.run_action(func(): return scene.session.act("GUARD",ally.pos))
	check(ally.protected_by == hero.id and hero.guarded,"the session guard action works through the UI update path")
	scene.queue_free()
	await process_frame
	var solo = load("res://expedition/main.tscn").instantiate()
	solo.session = Session.new(731,true,false,true,1)
	solo.session.depart()
	root.add_child(solo)
	Fixture.arena(solo.session,8)
	Fixture.equip_basics(solo.session)
	solo.refresh()
	for frame in range(3): await process_frame
	check(not solo.session.act("GUARD",solo.session.party[0].pos),"a lone hero cannot 엄호")
	solo.queue_free()
	await process_frame
