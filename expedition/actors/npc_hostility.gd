extends RefCounted
## A stranger's decision to turn on the party. A committed enemy stays hostile;
## the score only decides whether a neutral stranger starts a fight.
const THRESHOLD := 420

static func score(s, npc: Dictionary) -> int:
	if npc.hp <= 0 or npc.state != "MET" or bool(npc.get("summoned",false)): return -999
	var health: float = float(npc.hp) / maxf(1.0,float(npc.max_hp))
	var weakest: float = 1.0
	for member in s.alive(): weakest = minf(weakest,float(member.hp)/maxf(1.0,float(member.max_hp)))
	var profile = npc.profile
	var value := 150.0
	value += (500-profile.value("H"))*0.35
	value += (500-profile.value("A"))*0.35
	value += (profile.value("X")-500)*0.10
	value += float(npc.stress)*0.25
	value += (0.5-weakest)*300.0
	value += (health-0.5)*150.0
	value -= maxi(0,s.alive().size()-1)*130.0
	if npc.memory.salience_for_subject(s.party[0].id+1,["AID_RECEIVED"]) > 0: value -= 300.0
	return roundi(value)

static func may_start(s, npc: Dictionary) -> bool:
	return not bool(npc.get("hostile",false)) and score(s,npc) >= THRESHOLD

static func provoke(s, npc: Dictionary, source: Dictionary) -> void:
	if bool(npc.get("hostile",false)): return
	npc.hostile = true
	npc.awake = true
	npc.activity = "적대 중"
	npc.mode = ""
	npc.noise_seen = s.npc_clock()
	if s.pending_offer == int(npc.id): s.pending_offer = -1
	if not source.is_empty():
		s.serial += 1
		s.remember_plain(npc,"ATTACKED_BY_PLAYER",int(source.id)+1,int(source.id)+1,800)
	s.message("%s 적대" % npc.name)
	s.floor_state.observe(s)
