extends RefCounted
## Mission relic for the continuous floor: placement is the generator's job;
## this holds registration, discovery and the single pickup executor.
## Objective state lives in session.objective; UI, the map and navigation only read it.
const RELIC_LABEL := "봉인된 유물"
const RELIC_DESCRIPTION := "임무 물품 · 입구에서 반납"
const RECOVERY_BONUS := 100
const STATES := ["UNDISCOVERED","DISCOVERED","CARRIED","DELIVERED","LOST"]

static func create(expedition: int, pos: Vector2i) -> Dictionary:
	return {"expedition":expedition,"relic_id":"SEALED_RELIC_%d" % expedition,"pos":pos,"state":"UNDISCOVERED"}

## Eight-way movement permits corner cutting. Actors are not obstacles here.
static func reachability(s, origin: Vector2i) -> Dictionary:
	var dist: Dictionary = {origin:0}
	var queue: Array = [origin]
	var cursor := 0
	while cursor < queue.size():
		var p: Vector2i = queue[cursor]; cursor += 1
		for d in s.DIRECTIONS:
			var next: Vector2i = p+d
			if dist.has(next) or not s.inside(next) or s.tile(next).terrain == "wall": continue
			if not s.walk_reach(p,next): continue
			dist[next] = int(dist[p])+1; queue.append(next)
	return dist

static func register(s, pos: Vector2i) -> void:
	s.objective = create(s.expedition_number,pos)

static func discover(s) -> void:
	if s.objective.get("state","") != "UNDISCOVERED": return
	s.objective.state = "DISCOVERED"
	s.message(RELIC_LABEL+" 발견")

static func text(s) -> String:
	match s.objective.get("state",""):
		"CARRIED": return "입구로 귀환"
		"DELIVERED": return "유물 반납 완료"
		"LOST": return "유물 분실"
		_: return "유물 찾기"

static func description(s) -> String:
	match s.objective.get("state",""):
		"UNDISCOVERED": return "유물 찾기"
		"DISCOVERED": return "유물 회수"
		"CARRIED": return "입구로 귀환"
		_: return "임무 종료"

static func carrying(s) -> bool:
	return s.objective.get("state","") == "CARRIED"

## Empty string when pickup is legal; otherwise the reason shown to the player.
static func error(s) -> String:
	if not s.floor_mode or s.phase != "BATTLE": return "회수 불가"
	var state: String = s.objective.get("state","")
	if state == "CARRIED": return "회수 완료"
	if state not in ["UNDISCOVERED","DISCOVERED"]: return "유물 없음"
	var p: Vector2i = s.objective.pos
	if not s.floor_state.visible.has(p) or not s.floor_state.features.has(p): return "시야 밖"
	var actor: Dictionary = s.party[s.selected]
	if actor.hp <= 0 or actor.ap <= 0: return "행동 불가"
	if not s.party_enemies().is_empty(): return "주변에 적 있음"
	if actor.pos != p and not s.melee_reach(actor.pos,p): return "거리 초과"
	return ""

## The only place that changes the world relic into a carried objective.
static func pickup(s) -> bool:
	if not error(s).is_empty(): return false
	var p: Vector2i = s.objective.pos
	s.floor_state.features.erase(p)
	s.floor_state.clear_marker(p)
	s.objective.state = "CARRIED"
	s.message(RELIC_LABEL+" 획득")
	var actor: Dictionary = s.party[s.selected]
	actor.ap -= 1; s.check_battle_end(); s.finish_player_action()
	return true
