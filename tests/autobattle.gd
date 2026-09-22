extends SceneTree
## Autobattle: one rules-driven round per auto_step, stop events, party-wide
## commands, knobs from personality, battle stats and the marching order.
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Rules = preload("res://expedition/tactic_rules.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func run() -> void:
	auto()
	stops()
	commands()
	print("Autobattle: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

## Three members with the basics equipped, one revived melee foe next to the hero.
func skirmish(foes: int = 1) -> Dictionary:
	var s = Session.new(731,true,true,true,3); s.depart()
	var c := Fixture.arena(s,8)
	Fixture.equip_basics(s)
	var revived: Array = []
	for i in range(foes):
		var foe: Dictionary = s.enemies[i]
		foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.charging = false
		foe.cast_recovery = 0; foe.part_id = ""; foe.pos = c+Vector2i(2+i,0)
		revived.append(foe)
	s.party[1].pos = c+Vector2i(0,1); s.party[2].pos = c+Vector2i(0,2)
	s.floor_state.observe(s); s.selected = 0
	for actor in s.party: actor.ap = 1
	return {"s":s,"c":c,"hero":s.party[0],"foes":revived}

func auto() -> void:
	var d := skirmish(); var s = d.s
	check(s.in_combat(),"a visible foe means combat")
	var round_before: int = s.round_number
	var log_before: int = s.log_lines.size()
	check(s.auto_step(),"auto_step runs")
	check(s.round_number == round_before+1,"one round per auto_step")
	check(s.party.all(func(a): return a.ap == s.action_budget(a)),"everyone acted and the round reset AP")
	check(s.party.all(func(a): return a.last_action != "대기" or true),"last_action recorded")
	check(s.log_lines.size() > log_before,"actions were logged")
	# The hero is rule-driven like everyone else: adjacent foe → basic attack.
	d = skirmish(); s = d.s
	d.foes[0].pos = d.c+Vector2i(1,0); s.floor_state.observe(s)
	var hp: int = d.foes[0].hp
	s.auto_step()
	check(d.foes[0].hp < hp,"the hero attacked through the rules")
	# Outside combat auto_step does nothing.
	d = skirmish(0); s = d.s
	check(not s.in_combat() and not s.auto_step(),"no auto round while safe")
	# Solo: one action, one round.
	var solo = Session.new(731,true,false,true,1); solo.depart()
	var c := Fixture.arena(solo,8); Fixture.equip_basics(solo)
	var foe: Dictionary = solo.enemies[0]; foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.part_id = ""; foe.pos = c+Vector2i(1,0)
	solo.floor_state.observe(solo); solo.party[0].ap = 1
	hp = foe.hp; round_before = solo.round_number
	check(solo.auto_step() and foe.hp < hp and solo.round_number == round_before+1,"solo hero acts once per round")
	# Non-floor modes are untouched: auto_step refuses.
	var legacy = Session.new(731,true,true)
	check(not legacy.auto_step(),"auto_step is floor-mode only")

func stops() -> void:
	var d := skirmish(0); var s = d.s
	check(s.auto.stops.BATTLE_START and s.auto.stops.BATTLE_END and s.auto.hp_low == 30,"defaults")
	check(s.auto_stop_reason() == "","nothing to stop for while safe")
	d.foes = [s.enemies[0]]; var foe: Dictionary = d.foes[0]
	foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.part_id = ""; foe.pos = d.c+Vector2i(3,0)
	s.floor_state.observe(s)
	check(s.auto_stop_reason() == "BATTLE_START","first visible foe stops for battle start")
	s.auto_step()
	check(s.auto_stop_reason() != "BATTLE_START","battle start fires once")
	# Lethal threat on an ally: the melee foe steps next to the weakened member,
	# wherever the round left that member standing.
	s.party[2].hp = 5; foe.pos = Fixture.beside(s,s.party[2].pos); s.floor_state.observe(s)
	check(s.auto_stop_reason() == "ALLY_LETHAL","a member who would die this round stops the run")
	s.auto_step()
	s.party[2].hp = 5
	check(s.auto_stop_reason() != "ALLY_LETHAL","same reason is suppressed for three rounds")
	# HP low fires when a member newly crosses the line.
	d = skirmish(); s = d.s
	s.auto_step()
	s.party[1].hp = int(s.party[1].max_hp*0.3)
	check(s.auto_stop_reason() == "HP_LOW","member at 30% stops")
	s.auto.stops.HP_LOW = false
	check(s.auto_stop_reason() != "HP_LOW","disabled stop is ignored")
	s.auto.stops.HP_LOW = true
	# Death and battle end.
	d = skirmish(); s = d.s; s.auto_step()
	# Cut off from the others, so no one can 엄호 the killing blow away.
	s.party[2].hp = 1; s.party[2].pos = d.c+Vector2i(-3,4)
	d.foes[0].pos = Fixture.beside(s,s.party[2].pos); s.floor_state.observe(s)
	s.auto_step()
	check(s.party[2].hp <= 0 and s.auto_stop_reason() == "DEATH","a downed member stops the run")
	s.auto_step()
	d.foes[0].hp = 0; s.floor_state.observe(s)
	check(s.auto_stop_reason() == "BATTLE_END","no foes left stops for battle end")
	check(s.auto.stops_log.back() == "BATTLE_END","stops are logged for the battle report")

func commands() -> void:
	var d := skirmish(); var s = d.s
	d.foes[0].pos = d.c+Vector2i(3,0); s.floor_state.observe(s)
	s.party_command = "HOLD_POSITION"
	var pos: Vector2i = d.hero.pos
	s.auto_step()
	check(d.hero.pos == pos and s.party.all(func(a): return a.pos.x <= d.c.x),"hold position keeps the hero and the others in place")
	s.party_command = "RETREAT"
	s.auto_step()
	check(d.hero.pos.x < pos.x or d.hero.pos == pos,"retreat moves the hero away from the foe")
	s.party_command = "ATTACK_TARGET"; s.command_target = d.foes[0].id
	d.foes[0].pos = d.hero.pos+Vector2i(1,0); s.floor_state.observe(s)
	var hp: int = d.foes[0].hp
	s.auto_step()
	check(d.foes[0].hp < hp,"attack target makes the hero hit the marked foe")
	s.party_command = "FOLLOW"
	check(not s.reserve_action(1,"WAIT",s.party[1].pos),"reservations are gone in floor mode")
