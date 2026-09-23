extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const NpcAI = preload("res://expedition/npc_ai.gd")
const Modes = preload("res://expedition/npc_modes.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func field(offset: Vector2i, stance: String = "CHARGER") -> Dictionary:
	var s = Session.new(61,true,true,true,3); s.depart(); var c := Fixture.arena(s,12)
	Fixture.equip_basics(s)
	var npc: Dictionary = s.npcs[0]
	s.npcs = [npc]; npc.pos = c+offset; npc.hp = npc.max_hp; npc.stress = 0; npc.stance = stance; npc.awake = true; npc.noise_seen = s.round_number
	npc.equipped_abilities = ["",""]; npc.rules = []; npc.mode = ""; npc.mode_until = 0
	s.mistake_override[npc.id] = false
	s.floor_state.observe(s)
	return {"s":s,"c":c,"npc":npc}

func foe_at(s, p: Vector2i, hp: int = 30) -> Dictionary:
	var foe: Dictionary = s.enemies.filter(func(e): return e.hp <= 0)[0]
	foe.hp = hp; foe.max_hp = hp; foe.pos = p; foe.alert = true; foe.role = "MELEE"; foe.charging = false; foe.cast_recovery = 0; foe.part_id = ""
	s.floor_state.observe(s); return foe

func run() -> void:
	friends(); fights(); targeted(); dies()
	modes_approach(); modes_hold(); modes_rest(); modes_explore(); commitment(); shape(); duo(); labels(); cooldowns()
	print("NPC behaviour: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func friends() -> void:
	var f := field(Vector2i(3,0)); var s = f.s
	check(s.friends().size() == 4 and f.npc in s.friends(),"awake npc counts as a friend")
	f.npc.awake = false
	check(s.friends().size() == 3,"asleep: not a friend")
	f.npc.awake = true; f.npc.hp = 0
	check(s.friends().size() == 3 and s.alive().size() == 3,"dead npc is neither; alive() stays party-only")

func fights() -> void:
	var f := field(Vector2i(2,0)); var s = f.s; var npc: Dictionary = f.npc
	var foe := foe_at(s,npc.pos+Vector2i(1,0))
	var hp: int = foe.hp
	NpcAI.turn(s,npc)
	check(foe.hp < hp and npc.activity == "교전 중","charger npc attacks the adjacent foe through Tactics.choose")
	# A guardian npc covers the wounded hero with 엄호 it carries.
	var g := field(Vector2i(1,0),"GUARDIAN"); var t = g.s; var n2: Dictionary = g.npc
	n2.equipped_abilities = ["GUARD",""]; n2.rules = [t.Abilities.default_rule("GUARD")]
	t.party[0].hp = 5; var foe2 := foe_at(t,t.party[0].pos+Vector2i(-1,0)); foe2.charging = true
	t.intents = [{"id":foe2.id,"cell":t.party[0].pos,"damage":9,"kind":""}]
	NpcAI.turn(t,n2)
	check(t.party[0].get("protected_by",-1) == n2.id,"guardian npc guards the lethal hero")
	# An npc walks the party's own two-step frontier: a candidate two cells out
	# (a skirmisher's escape line) is executed instead of falling back to WAIT.
	var m := field(Vector2i(-2,0)); var u = m.s; var n3: Dictionary = m.npc
	var away := foe_at(u,n3.pos+Vector2i(-3,0))
	u.boss_trial = false   # the fixture's session is a trial one, where everybody moves a single cell
	n3.ap = 1
	var out: Vector2i = n3.pos+Vector2i(0,2)
	check(int(n3.move_factor) == 100 and out in u.movement_cells(n3.id),"the npc's frontier is the party's two-step one")
	check(u.act_as(n3,"MOVE",out,false) and n3.pos == out,"an npc crosses two cells in one action")
	n3.pos = m.c+Vector2i(-2,0)
	var gap: int = maxi(absi(n3.pos.x-away.pos.x),absi(n3.pos.y-away.pos.y))
	NpcAI.turn(u,n3)
	check(maxi(absi(n3.pos.x-away.pos.x),absi(n3.pos.y-away.pos.y)) < gap,"a charger npc closes on the foe its own eyes found")

func targeted() -> void:
	var f := field(Vector2i(4,0)); var s = f.s; var npc: Dictionary = f.npc
	var foe := foe_at(s,npc.pos+Vector2i(1,0))
	for a in s.party: a.pos = f.c+Vector2i(-6,0)+Vector2i(0,s.party.find(a))
	s.floor_state.observe(s)
	var hp: int = npc.hp
	s.floor_state.enemy_turn(s,foe)
	check(npc.hp < hp,"monsters target an awake npc")
	# An npc's own fight is the ai's business, not the party's state: the party
	# keys everything it does on what it can see itself.
	var g := field(Vector2i(11,0)); var t = g.s
	var far := foe_at(t,g.npc.pos+Vector2i(1,0))
	check(not t.floor_state.visible.has(far.pos),"the npc's foe stands out of the party's sight")
	check(not t.combat_enemies().is_empty() and t.party_enemies().is_empty(),"a target for the ai, no foe for the party")
	check(t.floor_state.safe(t) and not t.in_combat(),"the party is not in combat over an npc's fight")

func dies() -> void:
	var f := field(Vector2i(2,0)); var s = f.s; var npc: Dictionary = f.npc
	npc.hp = 3; var foe := foe_at(s,npc.pos+Vector2i(1,0))
	var stress: Array = s.party.map(func(a): return int(a.stress))
	s.floor_state.enemy_turn(s,foe)
	check(npc.hp <= 0 and npc.state == "DEAD","a killed npc is DEAD")
	check(s.roster.filter(func(r): return r.id == npc.id)[0].state == "DEAD","the roster row is DEAD")
	check(s.phase == "BATTLE","npc death does not end the party's battle")
	# A stranger's death is not a comrade's: those who watched are shaken by
	# five, and nobody remembers an ally lost.
	check(not s.party.any(func(a): return int(a.memory.salience_for_subject(npc.id+1,["ALLY_LOST"])) > 0),"no ALLY_LOST for a stranger")
	check(s.floor_state.visible.has(npc.pos),"the party watched it happen")
	check(s.party.all(func(a): return int(a.stress) > stress[s.party.find(a)]),"everyone watching is shaken")


func bold(npc: Dictionary, facet: String, value: int) -> void:
	var v: Dictionary = npc.profile.values.duplicate(); v[facet] = value
	npc.profile = load("res://sim/dungeon_population/hexaco_profile.gd").new(v)

func modes_approach() -> void:
	var f := field(Vector2i(6,0)); var s = f.s; var npc: Dictionary = f.npc
	bold(npc,"X",900); bold(npc,"O",100)
	var pick: Dictionary = Modes.choose(s,npc)
	check(pick.mode == "APPROACH" and pick.explain[0].id == "X","extravert approaches, X on top")
	var d: int = s.distance(npc.pos,s.party[0].pos)
	NpcAI.turn(s,npc)
	check(s.distance(npc.pos,s.party[0].pos) < d and npc.activity == "다가오는 중","steps toward the party")
	for i in range(8): NpcAI.turn(s,npc)
	check(s.party.any(func(a): return s.melee_reach(npc.pos,a.pos)),"arrives adjacent")
	check(s.pending_offer == npc.id,"adjacent extravert offers to join (Task 5 wires the answer)")

func modes_hold() -> void:
	var f := field(Vector2i(4,0)); var s = f.s; var npc: Dictionary = f.npc
	bold(npc,"X",100); bold(npc,"C",800); bold(npc,"O",100)
	check(Modes.choose(s,npc).mode == "HOLD","introvert holds")
	for i in range(6): NpcAI.turn(s,npc)
	var d: int = s.distance(npc.pos,s.party[0].pos)
	check(d >= 3 and d <= 5 and npc.activity == "거리를 두고 지켜보는 중","keeps three to five tiles")

func modes_rest() -> void:
	var f := field(Vector2i(5,0)); var s = f.s; var npc: Dictionary = f.npc
	npc.hp = npc.max_hp/4; bold(npc,"X",900)
	check(Modes.choose(s,npc).mode == "REST","wounded rests even when extravert")
	var pos: Vector2i = npc.pos; NpcAI.turn(s,npc)
	check(npc.pos == pos and npc.activity == "부상으로 대기 중","stays put")

func modes_explore() -> void:
	var f := field(Vector2i(9,0)); var s = f.s; var npc: Dictionary = f.npc
	bold(npc,"O",950); bold(npc,"X",300); npc.awake = true
	check(not s.floor_state.visible.has(npc.pos),"out of the party's sight")
	check(Modes.choose(s,npc).mode == "EXPLORE","open-minded npc explores when the party is not in view")
	var pos: Vector2i = npc.pos; NpcAI.turn(s,npc)
	check(npc.pos != pos and npc.activity == "주변을 탐색 중","walks toward a room centre")

func commitment() -> void:
	var f := field(Vector2i(6,0)); var s = f.s; var npc: Dictionary = f.npc
	bold(npc,"X",600); bold(npc,"C",600); bold(npc,"A",750); bold(npc,"O",100)
	var first: String = Modes.choose(s,npc).mode
	npc.mode = first; npc.mode_until = s.round_number+Modes.COMMIT_ROUNDS
	bold(npc,"X",680) # a small change must not flip the mode inside the commitment window
	npc.mode = ""      # uncommitted, this very change does flip the argmax
	check(Modes.choose(s,npc).mode != first,"the small change would flip an uncommitted npc")
	npc.mode = first
	check(Modes.choose(s,npc).mode == first,"committed mode holds against a small score change")
	npc.hp = npc.max_hp/5
	check(Modes.choose(s,npc).mode == "REST","an 80+ point swing switches at once")
	check(Modes.choose(s,npc) == Modes.choose(s,npc),"deterministic")

func duo() -> void:
	var f := field(Vector2i(5,0)); var s = f.s; var a: Dictionary = f.npc
	var b: Dictionary = s.roster.filter(func(n): return n.id != a.id)[0]
	a.partner = b.id; b.partner = a.id; a.bond = "close"; b.bond = "close"
	b.pos = f.c+Vector2i(5,3); b.awake = true; b.hp = b.max_hp; b.noise_seen = s.round_number; s.npcs.append(b)
	bold(a,"X",900); bold(b,"X",900)
	s.floor_state.observe(s)
	var behind: Vector2i = b.pos
	NpcAI.turn(s,a); NpcAI.turn(s,b)
	check(b.pos != behind and b.activity == "동료에게 이동 중","the one behind walks to its partner")
	check(a.activity == "다가오는 중","the one nearer the party keeps its own mode")
	for i in range(4): NpcAI.turn(s,a); NpcAI.turn(s,b)
	check(s.distance(a.pos,b.pos) <= 1,"the pair closes up")

## Every weight in the table is an input the modes actually compute.
func shape() -> void:
	var f := field(Vector2i(6,0))
	var inp: Dictionary = Modes.inputs(f.s,f.npc)
	for mode in Modes.MODES:
		check(mode in Modes.table(),"table has "+mode)
		for id in Modes.table()[mode].keys():
			if id == "base": continue
			check(inp.has(id),"%s weight %s is an input" % [mode,id])

func labels() -> void:
	var f := field(Vector2i(2,0)); var s = f.s; var npc: Dictionary = f.npc
	foe_at(s,npc.pos+Vector2i(1,0)); NpcAI.turn(s,npc)
	check(npc.activity == "교전 중" and npc.explains.size() == 1 and npc.explains[0].has("explain"),"combat label and an explain row")
	for i in range(25): npc.explains.append({"round":i,"kind":"WAIT","cell":npc.pos,"explain":[]})
	NpcAI.turn(s,npc)
	check(npc.explains.size() == 20,"explains capped at twenty")

## An awake npc fights with the party's rules, so it keeps the party's clocks:
## its cooldowns tick down with the round like anyone else's.
func cooldowns() -> void:
	var f := field(Vector2i(6,0)); var s = f.s; var npc: Dictionary = f.npc
	npc.cooldowns["PUSH"] = 2; npc.iron_guard = true
	s.end_round()
	check(int(npc.cooldowns.PUSH) == 1 and not npc.iron_guard,"one round, one tick")
	s.end_round()
	check(int(npc.cooldowns.PUSH) == 0,"and the part comes back")
