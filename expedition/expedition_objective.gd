extends RefCounted
## Mission relic for the continuous floor: seeded placement, discovery, and the
## single pickup executor. Objective state lives in session.objective; UI, the
## map and navigation only read it.
const RELIC_LABEL := "봉인된 유물"
const RELIC_DESCRIPTION := "심부에 봉인된 유물입니다. 회수해 입구 관문으로 가져가면 임무가 완료됩니다.\n사용·판매·장착은 할 수 없습니다."
const RECOVERY_BONUS := 100
const MIN_DISTANCE_RATIO := 0.6
const FAR_BAND_RATIO := 0.8
const STATES := ["UNDISCOVERED","DISCOVERED","CARRIED","DELIVERED","LOST"]

static func create(expedition: int, pos: Vector2i) -> Dictionary:
	return {"expedition":expedition,"relic_id":"SEALED_RELIC_%d" % expedition,"pos":pos,"state":"UNDISCOVERED"}

## Player-rule reachability from origin: eight-way, diagonal blocked by either
## orthogonal wall (Session.melee_reach). Actors are not obstacles here.
static func reachability(s, origin: Vector2i) -> Dictionary:
	var dist: Dictionary = {origin:0}
	var queue: Array = [origin]
	var cursor := 0
	while cursor < queue.size():
		var p: Vector2i = queue[cursor]; cursor += 1
		for d in s.DIRECTIONS:
			var next: Vector2i = p+d
			if dist.has(next) or not s.inside(next) or s.tile(next).terrain == "wall": continue
			if not s.melee_reach(p,next): continue
			dist[next] = int(dist[p])+1; queue.append(next)
	return dist

static func has_interaction_cell(s, reach: Dictionary, p: Vector2i) -> bool:
	for d in s.DIRECTIONS:
		if reach.has(p+d) and s.melee_reach(p+d,p): return true
	return false

static func blocked(s, floor_state, p: Vector2i, entry: Vector2i) -> bool:
	if p == entry or floor_state.features.has(p): return true
	if s.tile(p).terrain in ["wall","water"] or s.tile(p).fire > 0: return true
	for enemy in s.enemies:
		if enemy.pos == p: return true
	return false

## Chooses the relic cell. The legacy deep exit is the preferred candidate;
## otherwise a seeded pick from the farthest 20% band; finally the farthest
## reachable cell. Never loops and never returns an unreachable cell.
static func choose(s, floor_state, entry: Vector2i, preferred: Vector2i) -> Vector2i:
	var reach := reachability(s,entry)
	var farthest := 0
	for value in reach.values(): farthest = maxi(farthest,int(value))
	if reach.has(preferred) and not blocked(s,floor_state,preferred,entry) and has_interaction_cell(s,reach,preferred) and reach[preferred] >= farthest*MIN_DISTANCE_RATIO:
		return preferred
	var band: Array = []
	for p in reach:
		if reach[p] >= farthest*FAR_BAND_RATIO and not blocked(s,floor_state,p,entry) and has_interaction_cell(s,reach,p): band.append(p)
	band.sort_custom(func(a,b): return reach[a] > reach[b] if reach[a] != reach[b] else (a.y < b.y if a.y != b.y else a.x < b.x))
	if not band.is_empty():
		return band[s.Hexaco.sample(s.seed_value,s.expedition_number,"relic",band.size())]
	var fallback := Vector2i(-1,-1)
	for p in reach:
		if p == entry or not has_interaction_cell(s,reach,p): continue
		if fallback.x < 0 or reach[p] > reach[fallback]: fallback = p
	if fallback.x < 0: push_error("mission relic: no reachable cell on floor")
	return fallback

static func place(s, floor_state, entry: Vector2i, preferred: Vector2i) -> Vector2i:
	var p := choose(s,floor_state,entry,preferred)
	if p.x >= 0: floor_state.features[p] = {"kind":"relic","used":false,"label":RELIC_LABEL}
	s.objective = create(s.expedition_number,p)
	return p

static func discover(s) -> void:
	if s.objective.get("state","") != "UNDISCOVERED": return
	s.objective.state = "DISCOVERED"
	s.message(RELIC_LABEL+" 발견 · 인접해서 조사하면 회수할 수 있습니다.")

static func text(s) -> String:
	match s.objective.get("state",""):
		"CARRIED": return "입구로 귀환"
		"DELIVERED": return "유물 반납 완료"
		"LOST": return "유물 분실"
		_: return "유물 찾기"

static func description(s) -> String:
	match s.objective.get("state",""):
		"UNDISCOVERED": return "심부의 봉인된 유물을 찾으세요. 아직 위치를 모릅니다.\n유물 없이 입구로 귀환해도 전리품은 정산됩니다."
		"DISCOVERED": return "봉인된 유물을 발견했습니다. 인접해서 조사하면 회수합니다.\n주변에 적이 보이면 회수할 수 없습니다."
		"CARRIED": return "유물을 가지고 입구 관문으로 돌아오세요.\n입구에 인접하고 적이 보이지 않을 때 귀환할 수 있습니다."
		_: return "임무가 종료되었습니다."

static func carrying(s) -> bool:
	return s.objective.get("state","") == "CARRIED"

## Empty string when pickup is legal; otherwise the reason shown to the player.
static func error(s) -> String:
	if not s.floor_mode or s.phase != "BATTLE": return "탐험 중에만 회수할 수 있습니다."
	var state: String = s.objective.get("state","")
	if state == "CARRIED": return "이미 회수했습니다."
	if state not in ["UNDISCOVERED","DISCOVERED"]: return "회수할 유물이 없습니다."
	var p: Vector2i = s.objective.pos
	if not s.floor_state.visible.has(p) or not s.floor_state.features.has(p): return "보이는 유물을 선택하세요."
	var actor: Dictionary = s.party[s.selected]
	if actor.hp <= 0 or actor.ap <= 0: return "지금은 행동할 수 없습니다."
	if not s.combat_enemies().is_empty(): return "주변 적을 먼저 처리하세요."
	if actor.pos != p and not s.melee_reach(actor.pos,p): return "유물 옆으로 이동하세요."
	return ""

## The only place that changes the world relic into a carried objective.
static func pickup(s) -> bool:
	if not error(s).is_empty(): return false
	var p: Vector2i = s.objective.pos
	s.floor_state.features.erase(p)
	s.floor_state.clear_marker(p)
	s.objective.state = "CARRIED"
	s.message(RELIC_LABEL+" 회수 · 입구 관문으로 돌아가세요.")
	var actor: Dictionary = s.party[s.selected]
	actor.ap -= 1; s.check_battle_end(); s.finish_player_action()
	return true
