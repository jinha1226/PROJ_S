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

## One npc from the roster parked at `offset` from the hero on a cleared arena.
func field(offset: Vector2i) -> Dictionary:
	var s = Session.new(51,true,true,true,3); s.depart(); var c := Fixture.arena(s,12)
	Fixture.equip_basics(s)
	var npc: Dictionary = s.npcs[0]
	s.npcs = [npc]; npc.pos = c+offset; npc.awake = false; npc.hp = npc.max_hp; npc.noise_seen = -99
	s.floor_state.observe(s)
	return {"s":s,"c":c,"npc":npc}

func run() -> void:
	sight(); noise(); sleep(); no_cost()
	print("NPC sense: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func sight() -> void:
	var f := field(Vector2i(9,0)); var s = f.s; var npc: Dictionary = f.npc
	check(not NpcAI.sense(s,npc) and not npc.awake,"nine tiles away, out of its sight: asleep")
	npc.pos = f.c+Vector2i(4,0)
	check(NpcAI.sense(s,npc) and npc.awake,"four tiles: sees the party and wakes")
	# A wall between them blocks sight.
	var g := field(Vector2i(3,0)); for y in range(-3,4): g.s.tile(g.c+Vector2i(2,y)).terrain = "wall"
	check(not NpcAI.sense(g.s,g.npc),"a wall blocks the npc's sight")

func noise() -> void:
	var f := field(Vector2i(8,0)); var s = f.s; var npc: Dictionary = f.npc
	check(not NpcAI.sense(s,npc),"eight tiles: cannot see")
	# Out of the hero's reach: a retaliation passive would add a second noise cell.
	var foe: Dictionary = s.enemies[0]; foe.hp = 30; foe.pos = f.c+Vector2i(3,0); foe.alert = true; s.floor_state.observe(s)
	s.damage(foe,5,0,"SLASH")
	check(s.noise.size() == 1 and s.noise[0] == foe.pos,"a hit is noise on the victim's cell")
	check(NpcAI.sense(s,npc) and npc.awake,"combat within ten tiles wakes it")
	var far := field(Vector2i(12,0)); var foe2: Dictionary = far.s.enemies[0]; foe2.hp = 30; foe2.pos = far.c+Vector2i(1,0); far.s.floor_state.observe(far.s)
	far.s.damage(foe2,5,0,"SLASH")
	check(not NpcAI.sense(far.s,far.npc),"noise beyond ten tiles is not heard")
	s.end_round()
	check(s.noise.is_empty(),"noise clears at the end of the round")
	# What an npc does is heard next round: two npcs eight tiles apart, both out
	# of the party's sight, and the first one's fight is what wakes the second.
	var g := field(Vector2i(9,-4)); var t = g.s
	var first: Dictionary = g.npc
	var second: Dictionary = t.roster.filter(func(r): return r.id != first.id)[0]
	t.npcs = [first,second]
	first.awake = true; first.noise_seen = t.round_number; first.stance = "CHARGER"
	first.equipped_abilities = ["",""]; first.rules = []; t.mistake_override[first.id] = false
	second.pos = g.c+Vector2i(9,4); second.hp = second.max_hp; second.awake = false; second.noise_seen = -99
	var near: Dictionary = t.enemies.filter(func(e): return e.hp <= 0)[0]
	near.hp = 40; near.max_hp = 40; near.pos = first.pos+Vector2i(1,0); near.alert = true; near.role = "MELEE"
	near.part_id = ""; near.charging = false; near.cast_recovery = 0
	t.floor_state.observe(t)
	check(not t.floor_state.visible.has(first.pos) and not t.floor_state.visible.has(second.pos),"neither npc is in the party's sight")
	t.end_round()
	check(first.activity == "교전 중" and not second.awake,"the first fights; the second has not heard it yet")
	check(not t.noise.is_empty(),"the fight's noise survives the round it was made in")
	t.end_round()
	check(second.awake,"an npc's own fight is heard by the next npc next round")

func sleep() -> void:
	var f := field(Vector2i(4,0)); var s = f.s; var npc: Dictionary = f.npc
	NpcAI.sense(s,npc); check(npc.awake,"awake")
	npc.pos = f.c+Vector2i(9,0)
	for i in range(4): NpcAI.sense(s,npc); s.round_number += 1
	check(npc.awake,"still awake after four quiet rounds out of sight")
	NpcAI.sense(s,npc); s.round_number += 1; NpcAI.sense(s,npc)
	check(not npc.awake,"asleep after five")
	# Awake NPCs act even when the party cannot see them.
	npc.pos = f.c+Vector2i(4,0); NpcAI.sense(s,npc); npc.pos = f.c+Vector2i(7,0)
	check(NpcAI.sense(s,npc) and npc.awake and not s.floor_state.visible.has(npc.pos),"acts out of the party's sight while awake")

func no_cost() -> void:
	var f := field(Vector2i(9,0)); var s = f.s; var npc: Dictionary = f.npc
	var pos: Vector2i = npc.pos
	for i in range(3): s.end_round()
	check(npc.pos == pos and npc.activity == "","a sleeping npc neither moves nor gets an activity")
	# Sleep, not the absence of a turn, is what keeps it still: a living foe two
	# tiles away is fought by whoever is awake, and this one is not.
	var g := field(Vector2i(9,0)); var t = g.s; var n2: Dictionary = g.npc
	var foe: Dictionary = t.enemies[0]
	foe.hp = 30; foe.max_hp = 30; foe.pos = n2.pos+Vector2i(2,0); foe.alert = true; foe.role = "MELEE"
	t.floor_state.observe(t)
	var spot: Vector2i = n2.pos; var health: int = n2.hp
	for i in range(3): t.end_round()
	check(n2.pos == spot and n2.hp == health and not n2.awake and n2.activity == "","asleep two tiles from a foe: no turn of its own, and nothing hits it")
