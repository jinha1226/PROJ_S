extends RefCounted
## Joining the party: aid is certain, the rest is personality.
## Food answers a need — hunger or a wound — so a fed npc that is later hurt can
## be helped again; the debt itself is written once (the memory dedupes), and a
## second helping buys no second promise.
const COOLDOWN := 20

## Memory convention: a subject/instigator is an actor's id plus one, so the
## hero is never the 0 that `PartyMemoryState.remember` rejects.
static func hero(s) -> int:
	return int(s.party[0].id)+1

static func can_aid(s, npc: Dictionary) -> String:
	if npc.hp <= 0 or npc.state != "MET": return "대상 아님"
	if not s.alive().any(func(a): return s.melee_reach(a.pos,npc.pos)): return "거리 초과"
	if not (bool(npc.get("hungry",false)) or npc.hp*100 < npc.max_hp*50): return "도울 일이 없음"
	if s.food < 1: return "식량 없음"
	return ""

static func aid(s, npc: Dictionary) -> bool:
	if not can_aid(s,npc).is_empty(): return false
	s.food -= 1
	if bool(npc.get("hungry",false)): npc.hungry = false
	else: npc.hp = mini(npc.max_hp,npc.hp+10)
	s.serial += 1; s.remember_plain(npc,"AID_RECEIVED",hero(s),hero(s),500)
	s.message("%s에게 식량을 나눴습니다." % npc.name); return true

static func aided(s, npc: Dictionary) -> bool:
	return npc.memory.salience_for_subject(hero(s),["AID_RECEIVED"]) > 0

static func chance(s, npc: Dictionary) -> int:
	var c: int = 60+(npc.profile.value("X")+npc.profile.value("A")-1000)/25
	if npc.hp*100 < npc.max_hp*50: c += 15
	if npc.memory.salience_for_subject(hero(s),["DECLINED_BY_PLAYER"]) > 0: c -= 25
	if npc.memory.salience_for_subject(hero(s),["DECLINED_PLAYER"]) > 0: c -= 10
	return clampi(c,0,95)

static func dialogue(s, npc: Dictionary) -> Dictionary:
	var full: bool = s.alive().size() >= 3
	var waiting: bool = s.round_number < int(npc.get("declined_until",-99))
	var line: String = "자리가 없군" if full else ("고맙다. 같이 가지." if aided(s,npc) else "지금은 아니야" if waiting else "무슨 일이지?")
	return {"line":line,"can_propose":not full and not waiting,"can_aid":can_aid(s,npc).is_empty(),"aided":aided(s,npc)}

## The player asks. Shared food is a promise and skips the roll; otherwise the
## npc's own extraversion and warmth answer, once every twenty rounds.
static func propose(s, npc: Dictionary) -> Dictionary:
	var d := dialogue(s,npc)
	if not d.can_propose: return {"accepted":false,"line":d.line}
	if not aided(s,npc):
		var roll: int = s.Hexaco.sample(s.seed_value,s.NpcRoster.depth(s)*100000+s.round_number*100+npc.id,"recruit",100)
		if roll >= chance(s,npc):
			s.serial += 1
			s.remember_plain(npc,"DECLINED_PLAYER",hero(s),hero(s),300)
			s.remember_plain(s.party[0],"DECLINED_PLAYER",npc.id+1,npc.id+1,300)
			npc.declined_until = s.round_number+COOLDOWN
			return {"accepted":false,"line":"됐어."}
	return recruit(s,npc)

## The join itself, with the duo rules.
static func recruit(s, npc: Dictionary) -> Dictionary:
	if s.alive().size() >= 3 or npc.state != "MET": return {"accepted":false,"line":"자리가 없군"}
	var mate: Dictionary = {}
	for n in s.npcs:
		if n.id == int(npc.get("partner",-1)) and n.hp > 0: mate = n
	if not mate.is_empty() and npc.bond == "close":
		if s.alive().size() >= 2: return {"accepted":false,"line":"얘를 두고는 못 가"}
		join(s,npc); join(s,mate); return {"accepted":true,"line":"우리는 같이 간다."}
	if not mate.is_empty() and npc.bond == "strained":
		s.serial += 1; s.remember_plain(mate,"LEFT_BY_PARTNER",npc.id+1,npc.id+1,600)
		s.stress(npc,10)
		s.message("%s이(가) %s을(를) 두고 떠납니다." % [npc.name,mate.name])
	join(s,npc); return {"accepted":true,"line":"좋아, 같이 가지."}

static func join(s, npc: Dictionary) -> void:
	s.npcs.erase(npc)
	if s.pending_offer == int(npc.id): s.pending_offer = -1
	# The floor it actually joined on: `floor_seen` is only where it was met,
	# and a stranger that dies nearby is "DEAD" without ever having joined.
	npc.joined_floor = s.NpcRoster.depth(s)
	npc.state = "PARTY"; npc.awake = false; npc.mode = ""; npc.activity = ""
	npc.ap = 0; npc.reservation = {}; npc.hit_and_run = false
	var subject: int = hero(s)
	s.party.append(npc); s.formation.append(s.party.size()-1)
	s.serial += 1
	s.remember_plain(npc,"RECRUITED",subject,subject,500)
	s.remember_plain(s.party[0],"RECRUITED",npc.id+1,npc.id+1,500)
	s.battle_stats.members[npc.id] = {"dealt":0,"taken":0,"guards":0,"covers":0,"redirected":0,"parts":{},"healed":0,"downed":false,"conflict":false,"mistakes":0,"role_rounds":{"in_role":0,"total":0},"explains":[]}
	s.message("%s이(가) 동행합니다." % npc.name)
