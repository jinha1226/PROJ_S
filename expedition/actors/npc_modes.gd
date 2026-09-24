extends RefCounted
## What an awake NPC does when nothing is attacking it: a four-mode utility table.
const MODES := ["APPROACH","HOLD","REST","EXPLORE"]
const COMMIT_ROUNDS := 10
const SWITCH_MARGIN := 80
static var _table: Dictionary = {}

static func table() -> Dictionary:
	if _table.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/tactics_profiles.json"))
		_table = parsed.npc_modes if parsed is Dictionary and parsed.has("npc_modes") else {}
		if _table.is_empty(): push_error("tactics_profiles.json has no npc_modes")
	return _table

static func inputs(s, npc: Dictionary) -> Dictionary:
	var seen: int = s.Floor.MonsterAI.sight(s)
	return {"X":npc.profile.value("X")/1000.0,"A":npc.profile.value("A")/1000.0,"C":npc.profile.value("C")/1000.0,"O":npc.profile.value("O")/1000.0,
		"wounded":1.0 if npc.hp*100 < npc.max_hp*40 else 0.0,"hp_ratio":float(npc.hp)/maxf(1.0,npc.max_hp),
		"party_room":float(s.alive().size())/3.0,"declined":1.0 if s.npc_clock() < int(npc.get("declined_until",-99)) or npc.memory.salience_for_subject(s.party[0].id+1,["DECLINED_BY_PLAYER"]) > 0 else 0.0,
		"stress":clampf(npc.stress/200.0,0.0,1.0),"party_seen":1.0 if s.alive().any(func(a): return s.Floor.MonsterAI.line(s,npc.pos,a.pos,seen)) else 0.0}

static func score_of(mode: String, inp: Dictionary) -> Dictionary:
	var row: Dictionary = table().get(mode,{})
	var total: float = float(row.get("base",0))
	var parts: Array = []
	var ids: Array = row.keys(); ids.sort()
	for id in ids:
		if id == "base": continue
		var contrib: float = float(row[id])*float(inp.get(id,0.0))
		total += contrib; parts.append({"id":id,"input":inp.get(id,0.0),"weight":row[id],"contrib":int(round(contrib))})
	parts.sort_custom(func(a,b): return a.contrib > b.contrib if a.contrib != b.contrib else a.id < b.id)
	return {"mode":mode,"score":int(round(total)),"explain":parts.slice(0,3)}

static func choose(s, npc: Dictionary) -> Dictionary:
	var inp := inputs(s,npc)
	var best: Dictionary = {}
	var current: Dictionary = {}
	for mode in MODES:
		var row := score_of(mode,inp)
		if mode == str(npc.get("mode","")): current = row
		if best.is_empty() or row.score > best.score: best = row
	if not current.is_empty() and s.npc_clock() < int(npc.get("mode_until",0)) and best.score-current.score < SWITCH_MARGIN: return current
	return best
