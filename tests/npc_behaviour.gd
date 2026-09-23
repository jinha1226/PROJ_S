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

func targeted() -> void:
	var f := field(Vector2i(4,0)); var s = f.s; var npc: Dictionary = f.npc
	var foe := foe_at(s,npc.pos+Vector2i(1,0))
	for a in s.party: a.pos = f.c+Vector2i(-6,0)+Vector2i(0,s.party.find(a))
	s.floor_state.observe(s)
	var hp: int = npc.hp
	s.floor_state.enemy_turn(s,foe)
	check(npc.hp < hp,"monsters target an awake npc")

func dies() -> void:
	var f := field(Vector2i(2,0)); var s = f.s; var npc: Dictionary = f.npc
	npc.hp = 3; var foe := foe_at(s,npc.pos+Vector2i(1,0))
	s.floor_state.enemy_turn(s,foe)
	check(npc.hp <= 0 and npc.state == "DEAD" and s.roster.any(func(r): return r.id == npc.id and r.state == "DEAD"),"a killed npc is DEAD on the roster")
	check(s.phase == "BATTLE","npc death does not end the party's battle")
