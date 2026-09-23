extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const NpcAI = preload("res://expedition/npc_ai.gd")
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
