extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Recruit = preload("res://expedition/npc_recruit.gd")
const NpcAI = preload("res://expedition/npc_ai.gd")
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func solo(seed: int = 71, party_size: int = 1) -> Dictionary:
	var s = Session.new(seed,party_size > 1,party_size > 1,true,party_size); s.depart(); var c := Fixture.arena(s,12)
	var npc: Dictionary = s.npcs[0]
	s.npcs = [npc]; npc.pos = c+Vector2i(1,0); npc.awake = true; npc.hp = npc.max_hp; npc.hungry = false; npc.stress = 0; npc.partner = -1; npc.bond = ""
	s.floor_state.observe(s); s.food = 3
	return {"s":s,"c":c,"npc":npc}

func set_facets(npc: Dictionary, x: int, a: int) -> void:
	var v: Dictionary = npc.profile.values.duplicate(); v.X = x; v.A = a
	npc.profile = Hexaco.new(v)

func run() -> void:
	aid(); aid_death(); chance(); ask(); offer(); full_party(); duo_close(); duo_strained(); kinds()
	print("Recruit: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func aid() -> void:
	var f := solo(); var s = f.s; var npc: Dictionary = f.npc
	var hero: int = s.party[0].id+1
	check(Recruit.can_aid(s,npc) == "도울 일이 없음","healthy, fed npc needs no aid")
	npc.hungry = true
	check(Recruit.can_aid(s,npc).is_empty() and s.aid(npc) and s.food == 2 and not npc.hungry,"food shared: -1 food, hunger gone")
	check(npc.memory.salience_for_subject(hero,["AID_RECEIVED"]) == 500,"npc remembers the aid")
	check(not s.aid(npc),"no second helping")
	npc.hp = npc.max_hp/3; npc.hungry = false
	check(s.aid(npc) and npc.hp == npc.max_hp/3+10,"a wounded npc takes food as +10 hp")
	set_facets(npc,0,0) # would never accept on personality alone
	var answer: Dictionary = s.propose(npc)
	check(answer.accepted and npc.state == "PARTY" and s.party.size() == 2,"aided npc joins without a roll")
	# Aid works with a full party; only the join is blocked.
	var g := solo(72,3); var t = g.s; var n: Dictionary = g.npc
	n.hungry = true
	check(Recruit.can_aid(t,n).is_empty() and t.aid(n) and t.food == 2 and not n.hungry,"a full party can still share its food")
	check(not Recruit.dialogue(t,n).can_propose and Recruit.dialogue(t,n).line == "자리가 없군","aided or not, there is no seat")

## The debt the hero is owed: an npc it fed, dying where it can see, costs more.
func aid_death() -> void:
	var stresses: Array = []
	for aided in [false,true]:
		var f := solo(77); var s = f.s; var npc: Dictionary = f.npc
		npc.hungry = true
		if aided: check(s.aid(npc),"fed before the fight")
		npc.hp = 3
		s.party[0].pos = f.c+Vector2i(-4,0)
		var foe: Dictionary = s.enemies.filter(func(e): return e.hp <= 0)[0]
		foe.hp = 30; foe.max_hp = 30; foe.pos = npc.pos+Vector2i(1,0); foe.alert = true
		foe.role = "MELEE"; foe.charging = false; foe.cast_recovery = 0; foe.part_id = ""
		s.floor_state.observe(s)
		var before: int = s.party[0].stress
		s.floor_state.enemy_turn(s,foe)
		check(npc.hp <= 0 and s.floor_state.visible.has(npc.pos),"the npc dies in the hero's sight")
		stresses.append(s.party[0].stress-before)
	check(stresses[1] > stresses[0],"the death of one the hero fed weighs heavier (%d > %d)" % [stresses[1],stresses[0]])

func chance() -> void:
	var f := solo(); var s = f.s; var npc: Dictionary = f.npc
	set_facets(npc,500,500); check(Recruit.chance(s,npc) == 60,"base 60")
	set_facets(npc,1000,1000); check(Recruit.chance(s,npc) == 95,"capped at 95 (60+40)")
	set_facets(npc,0,0); check(Recruit.chance(s,npc) == 20,"60-40")
	npc.hp = npc.max_hp/3; check(Recruit.chance(s,npc) == 35,"+15 wounded")
	npc.hp = npc.max_hp; s.serial += 1; s.remember_plain(npc,"DECLINED_BY_PLAYER",s.party[0].id+1,s.party[0].id+1,400)
	check(Recruit.chance(s,npc) == 0,"-25 after being declined, floored at 0")

func ask() -> void:
	var accepted := 0
	for seed in range(40):
		var f := solo(200+seed); var s = f.s; var npc: Dictionary = f.npc
		var hero: int = s.party[0].id+1
		set_facets(npc,500,500)
		var answer: Dictionary = s.propose(npc)
		if answer.accepted: accepted += 1
		else:
			check(npc.memory.salience_for_subject(hero,["DECLINED_PLAYER"]) == 300 and s.party[0].memory.salience_for_instigator(npc.id+1,["DECLINED_PLAYER"]) == 300,"both remember the refusal")
			check(not s.propose(npc).accepted and s.propose(npc).line == "지금은 아니야","cooldown: no re-ask for twenty rounds")
			s.round_number += 20
			check(Recruit.chance(s,npc) == 50,"re-ask after cooldown costs 10")
	check(accepted >= 14 and accepted <= 34,"about 60%% accept (%d/40)" % accepted)
	var same_a: Dictionary = solo(300); var same_b: Dictionary = solo(300)
	set_facets(same_a.npc,500,500); set_facets(same_b.npc,500,500)
	check(same_a.s.propose(same_a.npc).accepted == same_b.s.propose(same_b.npc).accepted,"deterministic per seed, round and npc")

func offer() -> void:
	var f := solo(); var s = f.s; var npc: Dictionary = f.npc
	var hero: int = s.party[0].id+1
	set_facets(npc,900,500)
	check(s.offer(npc) and s.pending_offer == npc.id,"an npc can put an offer on the table")
	check(not s.offer(npc),"one offer at a time")
	check(s.answer_offer(false) and s.pending_offer < 0 and npc.state == "MET","declined offer clears")
	check(npc.memory.salience_for_subject(hero,["DECLINED_BY_PLAYER"]) == 400 and s.round_number < npc.offered_until,"npc remembers, waits twenty rounds")
	check(not s.offer(npc),"no new offer inside the cooldown")
	s.round_number += 20
	check(s.offer(npc) and s.answer_offer(true) and npc.state == "PARTY" and s.party.size() == 2 and s.party[1] == npc and not (npc in s.npcs),"accepted offer recruits and leaves the npc list")
	check(npc.memory.salience_for_subject(hero,["RECRUITED"]) == 500 and s.party[0].memory.salience_for_instigator(npc.id+1,["RECRUITED"]) == 500,"both remember the recruitment")
	check(s.formation.size() == 2 and s.formation[1] == 1,"joins the marching order last")

func full_party() -> void:
	var f := solo(73,3); var s = f.s; var npc: Dictionary = f.npc
	set_facets(npc,1000,1000)
	check(Recruit.dialogue(s,npc).line == "자리가 없군" and not Recruit.dialogue(s,npc).can_propose,"full party: no proposing")
	check(s.offer(npc) and not s.answer_offer(true) and s.party.size() == 3,"an offer to a full party cannot be accepted")

func duo_close() -> void:
	var f := solo(74); var s = f.s; var a: Dictionary = f.npc
	var b: Dictionary = s.roster.filter(func(n): return n.id != a.id)[0]
	a.partner = b.id; b.partner = a.id; a.bond = "close"; b.bond = "close"
	b.pos = f.c+Vector2i(1,1); b.awake = true; b.hp = b.max_hp; b.state = "MET"; s.npcs.append(b); s.floor_state.observe(s)
	set_facets(a,1000,1000)
	check(s.propose(a).accepted and s.party.size() == 3 and a.state == "PARTY" and b.state == "PARTY","a close pair joins together")
	var g := solo(75,2); var t = g.s; var c: Dictionary = g.npc
	var d: Dictionary = t.roster.filter(func(n): return n.id != c.id)[0]
	c.partner = d.id; d.partner = c.id; c.bond = "close"; d.bond = "close"
	d.pos = g.c+Vector2i(1,1); d.awake = true; d.hp = d.max_hp; d.state = "MET"; t.npcs.append(d); t.floor_state.observe(t)
	set_facets(c,1000,1000)
	var answer: Dictionary = t.propose(c)
	check(not answer.accepted and answer.line == "얘를 두고는 못 가" and t.party.size() == 2,"one seat is not enough for a close pair")

func duo_strained() -> void:
	var f := solo(76); var s = f.s; var a: Dictionary = f.npc
	var b: Dictionary = s.roster.filter(func(n): return n.id != a.id)[0]
	a.partner = b.id; b.partner = a.id; a.bond = "strained"; b.bond = "strained"
	b.pos = f.c+Vector2i(1,1); b.awake = true; b.hp = b.max_hp; b.stress = 0; b.state = "MET"; s.npcs.append(b); s.floor_state.observe(s)
	set_facets(a,1000,1000); var stress_a: int = a.stress
	check(s.propose(a).accepted and a.state == "PARTY" and b.state == "MET" and b in s.npcs,"a strained partner stays behind")
	check(b.memory.salience_for_subject(a.id+1,["LEFT_BY_PARTNER"]) == 600 and a.stress > stress_a,"the one left remembers; the leaver pays stress")

func kinds() -> void:
	var Memory = load("res://sim/party_memory_state.gd")
	for k in ["RECRUITED","DECLINED_BY_PLAYER","DECLINED_PLAYER","LEFT_BY_PARTNER"]: check(k in Memory.KINDS,"memory kind "+k)
