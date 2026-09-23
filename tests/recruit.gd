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
	aid(); aid_death(); memory_survives(); chance(); ask(); offer(); full_party(); duo_close(); duo_strained(); partner_dead()
	marching_order(); comrade_dies(); stale_offer(); kinds(); history()
	await scene()
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

## The debt the hero is owed: an npc it fed, dying where it can see, costs more
## — and the wound that writes a landmark first must not erase the debt.
func aid_death() -> void:
	var stresses: Array = []
	for fed in [false,true]:
		var f := solo(77); var s = f.s; var npc: Dictionary = f.npc
		npc.hungry = true
		if fed: check(s.aid(npc),"fed before the blow")
		s.damage(npc,npc.max_hp-npc.max_hp/5,999,"IMPACT")
		check(npc.memory.salience_for_subject(npc.id+1,["SELF_HARM"]) > 0,"the crisis writes a landmark over the debt")
		var before: int = s.party[0].stress
		s.damage(npc,999,999,"IMPACT")
		check(npc.hp <= 0 and s.floor_state.visible.has(npc.pos),"the npc dies in the hero's sight")
		stresses.append(s.party[0].stress-before)
	check(stresses[1] > stresses[0],"the death of one the hero fed weighs heavier (%d > %d)" % [stresses[1],stresses[0]])

## Social records are cheap, so every pruning rule keeps them: the landmark
## filter, the expedition filter and the eight-record eviction.
func memory_survives() -> void:
	var f := solo(); var s = f.s; var npc: Dictionary = f.npc
	var hero: int = s.party[0].id+1
	npc.hungry = true; check(s.aid(npc),"fed")
	s.serial += 1; s.remember_important(npc,"SELF_HARM",npc.id+1,npc.id+1,750)
	for i in range(8):
		s.serial += 1; s.world_time += 1
		s.remember_important(npc,"ALLY_LOST",2000+i,2000+i,900)
	check(npc.memory.records.size() <= 8 and npc.memory.salience_for_subject(hero,["AID_RECEIVED"]) == 500,"the aid outlives a landmark and eight evictions")
	set_facets(npc,0,0)
	check(s.propose(npc).accepted,"the promise still skips the roll")
	var g := solo(); var t = g.s; var hero_actor: Dictionary = t.party[0]
	t.serial += 1; t.remember_plain(hero_actor,"RECRUITED",1001,1001,500)
	t.phase = "TOWN"; t.depart()
	check(hero_actor.memory.salience_for_subject(1001,["RECRUITED"]) == 500,"and outlives the expedition it was made in")

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

## A partner who is already dead holds nobody back.
func partner_dead() -> void:
	var f := solo(78); var s = f.s; var a: Dictionary = f.npc
	var b: Dictionary = s.roster.filter(func(n): return n.id != a.id)[0]
	a.partner = b.id; b.partner = a.id; a.bond = "close"; b.bond = "close"
	b.pos = f.c+Vector2i(1,1); b.hp = 0; b.state = "DEAD"; s.npcs.append(b); s.floor_state.observe(s)
	set_facets(a,1000,1000)
	var answer: Dictionary = s.propose(a)
	check(answer.accepted and answer.line == "좋아, 같이 가지." and s.party.size() == 2,"a dead partner is no duo")
	check(b.memory.salience_for_subject(a.id+1,["LEFT_BY_PARTNER"]) == 0,"and nothing to remember")

## `formation` holds party indices: a recruit takes the last rank, not the
## leader's cell.
func marching_order() -> void:
	var f := solo(); var s = f.s; var a: Dictionary = f.npc
	var b: Dictionary = s.roster.filter(func(n): return n.id != a.id)[0]
	b.pos = f.c+Vector2i(0,-1); b.awake = true; b.hp = b.max_hp; b.state = "MET"
	b.partner = -1; b.bond = ""; b.hungry = true; a.partner = -1; a.hungry = true
	s.npcs.append(b); s.floor_state.observe(s)
	set_facets(a,1000,1000); set_facets(b,1000,1000)
	check(s.aid(a) and s.propose(a).accepted,"the first joins")
	check(s.aid(b) and s.propose(b).accepted,"the second joins")
	check(s.party.size() == 3 and s.formation == [0,1,2],"three ranks, by index")
	var leader: Dictionary = s.leader()
	check(leader.id == s.party[0].id,"the hero still leads")
	s.party[1].pos = leader.pos+Vector2i(0,1); s.party[2].pos = leader.pos+Vector2i(0,2); s.floor_state.observe(s)
	check(s.floor_state.follow(s,s.party[1]).kind == "WAIT" and s.floor_state.follow(s,s.party[2]).kind == "WAIT","each recruit holds its own rank behind the leader")
	s.party[1].pos = leader.pos+Vector2i(0,2); s.party[2].pos = leader.pos+Vector2i(0,1); s.floor_state.observe(s)
	check(s.floor_state.follow(s,s.party[1]).kind == "MOVE","out of place, it walks to its own rank")

## Once recruited it is a comrade: its death is the party's loss, not a
## stranger's.
func comrade_dies() -> void:
	var f := solo(); var s = f.s; var npc: Dictionary = f.npc
	npc.hungry = true; set_facets(npc,1000,1000)
	check(s.aid(npc) and s.propose(npc).accepted,"joined")
	s.damage(npc,999,999,"IMPACT")
	check(npc.hp <= 0 and s.party[0].memory.salience_for_subject(npc.id+1,["ALLY_LOST"]) > 0,"the party mourns a comrade lost")
	check(bool(s.member_stats(npc.id).get("downed",false)),"the battle report marks it downed")
	check(npc.state == "DEAD","the roster row is dead too")

## An offer nobody can answer never blocks the next one.
func stale_offer() -> void:
	var f := solo(80); var s = f.s; var npc: Dictionary = f.npc
	check(s.offer(npc),"offer on the table")
	s.damage(npc,999,999,"IMPACT")
	check(npc.hp <= 0 and s.pending_offer < 0,"a dead npc's offer leaves the table")
	var g := solo(81); var t = g.s; var n: Dictionary = g.npc
	check(t.offer(n) and t.pending_offer == n.id,"offer stands")
	t.npcs.erase(n)
	check(not t.answer_offer(true) and t.pending_offer < 0,"an offer from someone gone clears itself")
	var u := solo(82); var m: Dictionary = u.s.npcs[0]
	check(u.s.offer(m),"offer stands on this floor")
	u.s.NpcRoster.place(u.s)
	check(u.s.pending_offer < 0,"a new floor clears the table")

func kinds() -> void:
	var Memory = load("res://sim/party_memory_state.gd")
	for k in ["RECRUITED","DECLINED_BY_PLAYER","DECLINED_PLAYER","LEFT_BY_PARTNER"]: check(k in Memory.KINDS,"memory kind "+k)

## The result screen's companion list: only those who actually joined. A
## stranger that dies where the party can see it is "DEAD" too, and must not
## show up as a comrade.
func history() -> void:
	var f := solo(); var s = f.s; var a: Dictionary = f.npc
	var b: Dictionary = s.roster.filter(func(n): return n.id != a.id)[0]
	b.pos = f.c+Vector2i(0,-1); b.awake = true; b.hp = b.max_hp; b.state = "MET"; b.partner = -1; b.bond = ""
	s.npcs.append(b); s.floor_state.observe(s)
	a.partner = -1; a.hungry = true
	check(s.companion_rows().is_empty(),"nobody has joined yet")
	check(s.aid(a) and s.propose(a).accepted,"one joins")
	s.damage(b,999,999,"IMPACT")
	check(b.hp <= 0 and b.state == "DEAD","the other dies a stranger")
	var rows: Array = s.companion_rows()
	check(rows.size() == 1 and rows[0].name == a.name and rows[0].alive,"only the recruit is a companion")
	check(int(rows[0].joined_floor) == s.NpcRoster.depth(s),"with the floor it joined on")
	s.damage(a,999,999,"IMPACT")
	rows = s.companion_rows()
	check(rows.size() == 1 and not rows[0].alive and int(rows[0].joined_floor) == s.NpcRoster.depth(s),"a fallen comrade keeps its join floor")

## The HUD side: a tap on an adjacent npc opens its popup, the aid button
## shares the food, and an offer on the table waits in its own popup.
func scene() -> void:
	var main = load("res://expedition/main.tscn").instantiate()
	var s = Session.new(71,false,false,true,1)
	main.session = s; root.size = Vector2i(390,844); root.add_child(main); main.set_process(false)
	await process_frame
	s.depart(); var c := Fixture.arena(s,12)
	var npc: Dictionary = s.npcs[0]; s.npcs = [npc]; npc.pos = c+Vector2i(1,0); npc.awake = true; npc.hungry = true; npc.hp = npc.max_hp; s.food = 2
	s.floor_state.observe(s); main.refresh(); await process_frame
	main.on_cell(npc.pos); await process_frame
	var names := func(node: Node) -> Array:
		var out: Array = []; var stack: Array = [node]
		while not stack.is_empty():
			var n: Node = stack.pop_back(); out.append(n.name)
			for ch in n.get_children(): stack.append(ch)
		return out
	var found: Array = names.call(main)
	check("NpcPopup" in found and "ProposeButton" in found and "AidButton" in found,"tapping an adjacent npc opens its popup with propose and aid")
	main.find_child("AidButton",true,false).pressed.emit(); await process_frame
	check(s.food == 1 and not npc.hungry,"aid button shares food")
	s.offer(npc); main.refresh(); await process_frame
	found = names.call(main)
	check("OfferPopup" in found and "OfferAccept" in found and "OfferDecline" in found,"a pending offer shows the offer popup")
	main.find_child("OfferAccept",true,false).pressed.emit(); await process_frame
	check(npc.state == "PARTY" and s.party.size() == 2,"accepting recruits")
	main.on_cell(npc.pos); await process_frame
	check(s.selected == 1,"a tap on the recruit selects it by its rank, not its roster id")
	main.queue_free(); await process_frame
