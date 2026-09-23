extends SceneTree
## Autobattle: one rules-driven round per auto_step, stop events, party-wide
## commands, knobs from personality, battle stats and the marching order.
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Rules = preload("res://expedition/tactic_rules.gd")
const Knobs = preload("res://expedition/knobs.gd")
const Stances = preload("res://expedition/stances.gd")
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
const Runner = preload("res://expedition/sim/encounter_runner.gd")
const Policy = preload("res://expedition/sim/bot_policy.gd")
const Arena = preload("res://expedition/sim/encounter_arena.gd")
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
	knobs()
	stats()
	sim()
	formation()
	await ui()
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
	check(s.auto.stops == Session.AUTO_STOP_DEFAULTS and s.auto.hp_low == 30,"defaults")
	check(s.auto.stops.BATTLE_START and s.auto.stops.DEATH and s.auto.stops.BATTLE_END,"the three battle events stop by default")
	check(not s.auto.stops.ALLY_LETHAL and not s.auto.stops.HP_LOW,"the two rolling alerts are opt-in")
	check(s.auto_stop_reason() == "","nothing to stop for while safe")
	d.foes = [s.enemies[0]]; var foe: Dictionary = d.foes[0]
	foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.part_id = ""; foe.pos = d.c+Vector2i(3,0)
	s.floor_state.observe(s)
	check(s.auto_stop_reason() == "BATTLE_START","first visible foe stops for battle start")
	s.auto_step()
	check(s.auto_stop_reason() != "BATTLE_START","battle start fires once")
	# Lethal threat on an ally: the melee foe stands next to the weakened member,
	# wherever the round left that member standing.
	s.auto.stops.ALLY_LETHAL = true; s.auto.stops.HP_LOW = true   # opt-in alerts, switched on for these checks
	s.party[2].hp = 5; foe.pos = Fixture.beside(s,s.party[2].pos)
	check(foe.pos != Vector2i(-1,-1),"the foe found a cell beside the weakened member")
	s.floor_state.observe(s)
	check(s.auto_stop_reason() == "ALLY_LETHAL","a member who would die this round stops the run")
	s.auto_step()
	s.party[2].hp = 5
	check(s.auto_stop_reason() != "ALLY_LETHAL","same reason is suppressed for three rounds")
	# HP low fires when a member newly crosses the line.
	d = skirmish(); s = d.s; s.auto.stops.HP_LOW = true
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
	d = skirmish(); s = d.s; s.auto.stops.DEATH = false; s.auto.stops.HP_LOW = true
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
	# A retreat belongs to the fight it was called in: the end of the battle
	# clears the standing order, stop event or none.
	d = skirmish(); s = d.s; s.auto_step()
	s.party_command = "RETREAT"; s.command_target = d.foes[0].id
	for dead in d.foes: dead.hp = 0
	s.floor_state.observe(s)
	check(s.auto_stop_reason() == "BATTLE_END" and s.party_command == "FOLLOW" and s.command_target == -1,"the end of the battle calls the retreat off")
	d = skirmish(); s = d.s; s.auto.stops.BATTLE_END = false; s.auto_step()
	s.party_command = "RETREAT"
	for dead in d.foes: dead.hp = 0
	s.floor_state.observe(s)
	check(s.auto_stop_reason() == "" and s.party_command == "FOLLOW","a consumed battle end clears it too")

## Strands `s.party[index]` at `cell` with a healthy, alert `foe` beside it, so
## that no ally can 엄호 the killing blow away. The retreat line is switched off
## for that member, or it would simply walk away from the blow. False when the
## arena offers no free cell for the foe.
## An isolated member at 1 hp with a foe beside it. The stance is set to
## 돌격형 so that the member stands and fights where it was cut off instead of
## walking back to the party, which is what the stop events here are about.
func cut_off(s, index: int, foe: Dictionary, cell: Vector2i) -> bool:
	s.party[index].hp = 1; s.party[index].pos = cell; s.party[index].knobs.retreat_hp = 0
	s.party[index].stance = "CHARGER"
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

func profile(values: Dictionary) -> DungeonHexacoProfile:
	return Hexaco.new({"H":500,"E":500,"X":500,"A":500,"C":500,"O":500}.merged(values,true))

func knobs() -> void:
	# Formulas from spec §3.3 on fixed profiles.
	var bold := profile({"X":900,"E":100,"A":900,"C":1000})
	var timid := profile({"X":100,"E":900,"A":100,"C":0})
	check(Knobs.defaults(bold) == {"posture":80,"cohesion":80,"retreat_hp":14},"bold defaults")
	check(Knobs.defaults(timid) == {"posture":-80,"cohesion":-80,"retreat_hp":46},"timid defaults")
	check(Knobs.comfort(bold).posture == [10,150] and Knobs.comfort(timid).posture == [-100,-60],"comfort half-width grows with C (70 vs 20)")
	check(Knobs.comfort(timid).retreat_hp == [36,56],"retreat comfort half-width 10 at C 0")
	var d := skirmish(); var s = d.s
	var hero: Dictionary = d.hero
	check(hero.knobs == Knobs.defaults(hero.profile),"new actors start at their personality defaults")
	check(not s.set_knob(0,"posture",120) and not s.set_knob(0,"nope",1),"range and key validated")
	s.phase = "TOWN"
	check(s.set_knob(0,"posture",-100) and hero.knobs.posture == -100,"knobs change in town")
	s.phase = "BATTLE"
	check(not s.set_knob(0,"posture",0),"not while fighting")
	# Conflict: forced far outside the comfort band.
	hero.profile = bold; hero.knobs = Knobs.defaults(bold); hero.knobs.posture = -100
	check(Knobs.conflicted(hero),"posture -100 conflicts with a bold profile")
	var stress: int = hero.stress; var memories: int = hero.memory.records.size()
	d.foes[0].pos = d.c+Vector2i(3,0); s.floor_state.observe(s)
	check(s.auto_stop_reason() == "BATTLE_START","battle starts")
	check(hero.stress == stress and hero.memory.records.size() == memories,"a conflict costs no stress and leaves no memory")
	check(hero.conflicted,"battle start still notes who fights against their orders")
	check(Knobs.effective(hero).posture == -100,"the forced knob is the one the member fights with")
	# Anxiety no longer swaps the knobs out: it multiplies the mistake chance.
	var calm: int = Stances.mistake_chance(hero)
	hero.stress = 120; s.stress(hero,0)
	check(hero.condition == "불안" and Knobs.effective(hero).posture == -100,"an anxious member keeps its orders")
	check(Stances.mistake_chance(hero) == mini(40,calm*3/2),"anxious: half again as many mistakes")
	hero.stress = 160; s.stress(hero,0)
	check(Stances.mistake_chance(hero) == mini(40,calm*2),"collapsed: twice as many")
	hero.stress = 0; s.stress(hero,0); hero.knobs.posture = 60
	check(not Knobs.conflicted(hero) and Knobs.effective(hero).posture == 60,"inside the band the knob is used as set")
	# Tactics: fire underfoot is left, cohesion keeps contact, the retreat line wins.
	d = skirmish(); s = d.s; hero = d.hero
	s.mistake_override[hero.id] = false   # the knobs are what these checks are about
	d.foes[0].pos = d.c+Vector2i(1,0); s.floor_state.observe(s)
	s.tile(hero.pos).fire = 40
	# Fire underfoot is left whatever the posture: every stance avoids it.
	hero.knobs = {"posture":-100,"cohesion":0,"retreat_hp":0}
	check(s.Tactics.choose(s,hero).kind == "MOVE","cautious: leaves the fire")
	s.tile(hero.pos).fire = 0
	# Cohesion +100 avoids moving away from allies; retreat line prefers distance.
	hero.knobs = {"posture":0,"cohesion":100,"retreat_hp":0}
	d.foes[0].pos = d.c+Vector2i(4,0); s.floor_state.observe(s)
	var choice: Dictionary = s.Tactics.choose(s,hero)
	check(choice.kind != "MOVE" or s.alive().any(func(a): return a.id != hero.id and s.melee_reach(choice.cell,a.pos)),"cohesive hero does not step out of contact with allies")
	hero.knobs = {"posture":0,"cohesion":0,"retreat_hp":50}; hero.hp = int(hero.max_hp*0.4)
	d.foes[0].pos = d.c+Vector2i(1,0); s.floor_state.observe(s)
	choice = s.Tactics.choose(s,hero)
	check(choice.kind == "MOVE" and s.distance(choice.cell,d.foes[0].pos) > 1,"below the retreat line the hero opens distance")

## The battle report's tallies: one dictionary per battle, reset at BATTLE_START.
func stats() -> void:
	var d := skirmish(); var s = d.s
	d.foes[0].pos = d.c+Vector2i(1,0); s.floor_state.observe(s)
	check(s.auto_stop_reason() == "BATTLE_START" and s.battle_stats.rounds == 0 and s.battle_stats.enemies == 1,"battle start resets the stats")
	s.auto_step()
	var m: Dictionary = s.member_stats(d.hero.id)
	check(s.battle_stats.rounds == 1 and m.dealt > 0,"hero damage is tallied")
	check(s.battle_stats.members.has(s.party[1].id),"every member has a row")
	d.foes[0].hp = 30
	s.party[1].pos = d.c+Vector2i(0,1); d.hero.ap = 1
	s.act_as(d.hero,"GUARD",s.party[1].pos,false)
	d.foes[0].pos = d.c+Vector2i(1,1); s.floor_state.observe(s)
	s.damage(s.party[1],6,d.foes[0].id,"IMPACT")
	m = s.member_stats(d.hero.id)
	check(m.guards == 1 and m.covers == 1 and m.redirected == 3,"guard count and redirected damage")
	check(s.member_stats(s.party[1].id).taken == 0,"the covered member took nothing")
	d.foes[0].hp = 1; s.damage(d.foes[0],5,d.hero.id,"SLASH")
	s.floor_state.observe(s)
	check(s.auto_stop_reason() == "BATTLE_END" and s.battle_stats.kills >= 1 and s.battle_stats.stops == ["BATTLE_START","BATTLE_END"],"kills and stops recorded at battle end")
	check(not s.has_method("stats_redirects") and not s.get("stats_redirects"),"old counters are gone")

## The simulator drives the rules policy through the same auto_step.
func sim() -> void:
	var hob := [{"species_id":"dcss_hobgoblin","role":"MELEE"}]
	var arena: Dictionary = Arena.DEFAULT_SPEC.duplicate(true); arena.members = hob
	var config := {"arena":arena,"party_size":3,"build":"melee_1","policy":"rules","rules":Session.DEFAULT_RULES,"supplies":[0,0,0,0,0,0],"max_rounds":40}
	var one: Dictionary = Runner.run_one(config,11)
	check(one.result in ["WIN","DEFEAT","TIMEOUT"] and one.rounds >= 1,"rules policy runs through auto_step")
	check(one == Runner.run_one(config,11),"still deterministic")
	check(one.has("skill_uses") and one.has("guards_used") and one.has("heals_used") and one.has("protect_redirects") and one.has("enemy_skill_uses") and one.has("interrupts"),"metric keys unchanged")
	var s = Session.new(11,true,true,true,3)
	s.rules_config = Session.DEFAULT_RULES.duplicate()
	check(Policy.step(s,"rules") == "","no step before depart")

## Formation is the marching order; swapping is only allowed once, at a battle start.
func formation() -> void:
	var d := skirmish(0); var s = d.s
	check(s.formation == [0,1,2] and s.leader().id == 0,"marching order defaults to party order")
	check(not s.swap_formation(0,1),"no swap while safe — only at battle start")
	d.foes = [s.enemies[0]]; var foe: Dictionary = d.foes[0]
	foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.part_id = ""; foe.pos = d.c+Vector2i(3,0)
	s.floor_state.observe(s)
	check(s.auto_stop_reason() == "BATTLE_START","battle start")
	var a: Vector2i = s.party[0].pos; var b: Vector2i = s.party[1].pos
	check(s.swap_formation(0,1) and s.party[0].pos == b and s.party[1].pos == a and s.formation == [1,0,2],"swap exchanges cells and order")
	check(not s.swap_formation(1,2),"one swap per battle")
	check(s.leader().id == 1 and s.rally_point() == s.party[1].pos,"leader and rally point follow the order")
	s.auto_step()
	check(not s.swap_formation(0,1),"not after the first round")
	# Follow uses the order: the rear member trails the leader when safe.
	d = skirmish(0); s = d.s
	s.formation = [2,1,0]
	s.party[2].pos = d.c+Vector2i(4,4); s.party[0].pos = d.c; s.party[1].pos = d.c+Vector2i(0,1)
	var step: Dictionary = s.floor_state.follow(s,s.party[0])
	check(step.kind == "MOVE" and s.distance(step.cell,s.party[2].pos) < s.distance(s.party[0].pos,s.party[2].pos),"followers walk toward the leader, not toward selected")


	# A one-cell bend requires a diagonal across a corner outside leader sight.
	d = skirmish(0); s = d.s
	for y in range(d.c.y-2,d.c.y+4):
		for x in range(d.c.x-2,d.c.x+6): s.tile(Vector2i(x,y)).terrain = "wall"
	for offset in [Vector2i.ZERO,Vector2i(1,1),Vector2i(2,1),Vector2i(3,1),Vector2i(3,0)]:
		s.tile(d.c+offset).terrain = "stone"
	s.party[0].pos = d.c+Vector2i(3,0); s.party[1].pos = d.c; s.party[2].hp = 0
	s.selected = 0; s.floor_state.observe(s)
	var corner: Vector2i = d.c+Vector2i(1,1)
	check(not s.floor_state.visible.has(corner),"bend is outside the leader's line of sight")
	check(s.floor_state.follow(s,s.party[1]).cell == corner,"follower plans diagonal through a narrow bend")
	check(s.act("WAIT",s.party[0].pos) and s.party[1].pos == corner,"follower executes diagonal even outside leader sight")

## The floor-mode battle HUD after the diet: member cards without skill
## buttons, the auto toggle that runs one round per tick, the stop banner,
## the retreat toggle and the battle report.
func ui() -> void:
	var scene = load("res://expedition/main.tscn").instantiate()
	var s = Session.new(731,true,true,true,3)
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await process_frame
	for frame in range(3): await process_frame
	s.depart(); var c := Fixture.arena(s,8); Fixture.equip_basics(s)
	var foe: Dictionary = s.enemies[0]; foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.part_id = ""; foe.pos = c+Vector2i(3,0)
	s.floor_state.observe(s); scene.refresh()
	for frame in range(3): await process_frame
	check(scene.find_child("StopBanner",true,false).text.is_empty(),"a bare refresh raises no stop event")
	# The HUD asks for a stop event at the end of a player action — here the
	# torch that was lit as the pack came into sight.
	scene.find_child("TorchButton",true,false).pressed.emit()
	for frame in range(3): await process_frame
	check(scene.skill_buttons.is_empty() and scene.end_turn_button == null,"floor battle has no skill buttons and no end-turn button")
	var toggle: Button = scene.find_child("AutoToggle",true,false)
	check(toggle != null,"auto toggle")
	check(scene.find_child("CommandBar",true,false) == null and scene.find_child("FormationButton",true,false) == null and scene.find_child("AutoOptionsButton",true,false) == null,"the command bar, the formation swap and the options gear are gone")
	check(scene.find_child("StopBanner",true,false).text.begins_with("전투 시작"),"banner names the stop")
	check(toggle.text == "▶ 재개" and not scene.item_buttons[0].disabled,"stopped: the toggle resumes and items are usable")
	# 개입은 명령만: the board marks the focus target and does nothing else.
	var foe_hp: int = foe.hp
	var stopped_round: int = s.round_number
	scene.on_cell(foe.pos)
	check(s.party_command == "ATTACK_TARGET" and s.command_target == foe.id and foe.hp == foe_hp,"tapping a foe concentrates the party without attacking")
	scene.on_cell(s.party[0].pos)
	check(s.round_number == stopped_round and s.party[0].pos == c,"tapping own cell neither waits nor moves while fighting")
	s.party_command = "FOLLOW"
	toggle.pressed.emit(); await process_frame
	# Every action rebuilds the HUD, so each control is looked up again.
	check(s.auto.running,"the toggle starts the run")
	check(scene.find_child("AutoToggle",true,false).text == "⏸ 정지" and scene.item_buttons[0].disabled,"running: the toggle stops and items are locked")
	# This stretch measures the timer, so the soft alerts are switched off.
	s.auto.stops.ALLY_LETHAL = false; s.auto.stops.HP_LOW = false
	var round_before: int = s.round_number
	scene.details_popup.popup_centered(); await process_frame
	scene._process(scene.auto_interval())
	check(s.round_number == round_before,"an open popup pauses the timer")
	scene.details_popup.hide(); await process_frame
	scene._process(scene.auto_interval())
	await process_frame
	check(s.round_number == round_before+1,"the HUD timer runs one round per interval")
	round_before = s.round_number
	scene.auto_tick()  # one timer tick = one auto_step when running
	await process_frame
	check(s.round_number == round_before+1,"a tick advanced one round")
	var card: Button = scene.find_child("MemberCard0",true,false)
	check(card.find_children("*","Label",true,false).any(func(l): return l.text.contains(s.party[0].last_action)),"member card reports the last action")
	toggle = scene.find_child("AutoToggle",true,false)
	toggle.pressed.emit(); await process_frame
	check(not s.auto.running,"toggle stops")
	# Speed toggle changes the interval.
	var speed: Button = scene.find_child("SpeedToggle",true,false)
	speed.pressed.emit(); await process_frame
	check(s.auto.speed == 2 and scene.auto_interval() < 0.5,"2x halves the interval")
	# The one remaining order reaches the session and does not resume the run.
	scene.find_child("RetreatToggle",true,false).pressed.emit(); await process_frame
	check(s.party_command == "RETREAT" and not s.auto.running,"the retreat toggle sets the party command")
	scene.find_child("RetreatToggle",true,false).pressed.emit(); await process_frame
	check(s.party_command == "FOLLOW","the retreat toggle calls it off again")
	# Battle end shows the report.
	foe.hp = 0; s.floor_state.observe(s); s.auto.running = true; scene.auto_tick()
	for frame in range(3): await process_frame
	var report = scene.find_child("BattleReport",true,false)
	check(report != null and report.visible and not s.auto.running,"battle report card on battle end")
	var labels: Array = report.find_children("*","Label",true,false).map(func(l): return l.text)
	check(labels.any(func(t): return t.begins_with("전투 종료")),"report header")
	check(labels.any(func(t): return t.begins_with(s.party[0].name)),"report gives every member a row")
	check(report.find_children("*","Button",true,false).any(func(b): return b.text == "파츠·규칙 보기"),"report links to parts and rules")
	scene.details_popup.hide()
	# Personality tab carries no knobs any more; the engine still takes them.
	scene.show_character(0,"성격")
	for frame in range(3): await process_frame
	check(scene.modal_content.find_children("Knob_*","HSlider",true,false).is_empty() and scene.modal_content.find_children("Band_*","Control",true,false).is_empty(),"no knob sliders and no comfort bands on the personality tab")
	check(s.set_knob(0,"posture",40) and s.party[0].knobs.posture == 40,"the session still takes a knob for the sim")
	scene.details_popup.hide()
	# The stop events are fixed, so there is no options popup to open.
	check(s.auto.stops.BATTLE_START and s.auto.stops.DEATH and s.auto.stops.BATTLE_END,"the shipped stops are on")
	check(not s.auto.stops.ALLY_LETHAL and not s.auto.stops.HP_LOW,"the fussy stops are off")
	# The report is a summary, not a stop: switching BATTLE_END off still shows it.
	s.auto.stops.BATTLE_END = false
	var second: Dictionary = s.enemies[1]
	second.hp = 24; second.max_hp = 24; second.role = "MELEE"; second.alert = true; second.part_id = ""; second.pos = s.party[0].pos+Vector2i(1,0)
	s.floor_state.observe(s)
	scene.run_action(func(): return true)  # any accepted player action asks for the stop event
	check(s.auto.last_stop.reason == "BATTLE_START","the second pack opens a new battle")
	s.auto.running = true
	for round_index in range(12):
		if not s.in_combat(): break
		scene.auto_tick()
	for frame in range(3): await process_frame
	check(not s.in_combat(),"the second pack is dealt with")
	var second_report = scene.find_child("BattleReport",true,false)
	check(second_report != null and second_report.visible,"the report follows a battle end that raises no stop")
	scene.details_popup.hide()
	scene.queue_free(); await process_frame
