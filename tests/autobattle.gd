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
	check(s.party.all(func(a): return a.last_action != ""),"last_action recorded")
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
	# Lethal threat on an ally: the melee foe stands next to the weakened member,
	# wherever the round left that member standing.
	s.party[2].hp = 5; foe.pos = Fixture.beside(s,s.party[2].pos)
	check(foe.pos != Vector2i(-1,-1),"the foe found a cell beside the weakened member")
	s.floor_state.observe(s)
	check(s.auto_stop_reason() == "ALLY_LETHAL","a member who would die this round stops the run")
	s.auto_step()
	s.party[2].hp = 5
	check(s.auto_stop_reason() != "ALLY_LETHAL","same reason is suppressed for three rounds")
	# HP low fires when a member newly crosses the line.
	d = skirmish(); s = d.s
	s.auto_step()
	s.party[1].hp = int(s.party[1].max_hp*0.3)
	check(s.auto_stop_reason() == "HP_LOW","member at 30% stops")
	# A disabled stop is ignored from the start, not merely after it already fired.
	d = skirmish(); s = d.s; s.auto.stops.HP_LOW = false
	s.auto_step()
	s.party[1].hp = int(s.party[1].max_hp*0.3)
	check(s.auto_stop_reason() == "","disabled stop is ignored")
	# Death and battle end.
	d = skirmish(2); s = d.s; s.auto_step()
	check(cut_off(s,2,d.foes[0],d.c+Vector2i(-3,4)),"the isolated member has a foe beside it")
	s.auto_step()
	check(s.party[2].hp <= 0 and s.auto_stop_reason() == "DEATH","a downed member stops the run")
	# A hard event is not suppressed inside the three-round window.
	check(cut_off(s,1,d.foes[1],d.c+Vector2i(-3,-4)),"the second member is cut off too")
	s.auto_step()
	check(s.party[1].hp <= 0 and s.auto_stop_reason() == "DEATH","a second death next round stops again")
	check(s.auto.stops_log == ["DEATH","DEATH"],"stops accumulate in order for the battle report")
	# A disabled hard event must not swallow the lower-priority alert of the same round.
	d = skirmish(); s = d.s; s.auto.stops.DEATH = false
	s.auto_step()
	check(cut_off(s,2,d.foes[0],d.c+Vector2i(-3,4)),"the isolated member has a foe beside it")
	s.auto_step()
	s.party[1].hp = int(s.party[1].max_hp*0.3)
	check(s.party[2].hp <= 0 and s.auto_stop_reason() == "HP_LOW","a disabled DEATH still lets HP_LOW through")
	# Battle end.
	d = skirmish(); s = d.s; s.auto_step()
	d.foes[0].hp = 0; s.floor_state.observe(s)
	check(s.auto_stop_reason() == "BATTLE_END","no foes left stops for battle end")
	check(s.auto.stops_log.back() == "BATTLE_END","stops are logged for the battle report")

## Strands `s.party[index]` at `cell` with a healthy, alert `foe` beside it, so
## that no ally can 엄호 the killing blow away. False when the arena offers no
## free cell for the foe.
func cut_off(s, index: int, foe: Dictionary, cell: Vector2i) -> bool:
	s.party[index].hp = 1; s.party[index].pos = cell
	var beside: Vector2i = Fixture.beside(s,cell)
	if beside == Vector2i(-1,-1): return false
	foe.hp = foe.max_hp; foe.alert = true; foe.pos = beside
	s.floor_state.observe(s)
	return true

func commands() -> void:
	var d := skirmish(); var s = d.s
	d.foes[0].pos = d.c+Vector2i(3,0); s.floor_state.observe(s)
	s.party_command = "HOLD_POSITION"
	var pos: Vector2i = d.hero.pos
	s.auto_step()
	check(d.hero.pos == pos and s.party.all(func(a): return a.pos.x <= d.c.x),"hold position keeps the hero and the others in place")
	# An adjacent foe overrides 자리 지키기: the rules take the attack.
	var held := skirmish(); var h = held.s
	held.foes[0].pos = held.hero.pos+Vector2i(1,0); h.floor_state.observe(h)
	h.party_command = "HOLD_POSITION"
	var held_hp: int = held.foes[0].hp
	h.auto_step()
	check(held.foes[0].hp < held_hp,"hold position still lets the rules attack an adjacent foe")
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
