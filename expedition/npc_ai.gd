extends RefCounted
## Dungeon NPCs: their senses, their round, and their manners toward the party.
const MonsterAI = preload("res://expedition/monster_ai.gd")
const Tactics = preload("res://expedition/tactical_action_selector.gd")
const Stances = preload("res://expedition/stances.gd")
const Knobs = preload("res://expedition/knobs.gd")
const NOISE_RADIUS := 10
const SLEEP_AFTER := 5
const LABELS := {"FIGHT":"교전 중","APPROACH":"다가오는 중","HOLD":"거리를 두고 지켜보는 중","REST":"부상으로 대기 중","EXPLORE":"주변을 탐색 중","":""}

## Wakes on its own sight of the party or on nearby combat; sleeps after five quiet rounds unseen.
static func sense(s, npc: Dictionary) -> bool:
	var seen: int = MonsterAI.sight(s)
	var sees_party: bool = s.alive().any(func(a): return MonsterAI.line(s,npc.pos,a.pos,seen))
	var hears: bool = s.noise.any(func(p): return s.distance(p,npc.pos) <= NOISE_RADIUS)
	if sees_party or hears:
		npc.awake = true; npc.noise_seen = s.round_number
		return true
	if npc.awake and not s.floor_state.visible.has(npc.pos) and s.round_number-int(npc.noise_seen) >= SLEEP_AFTER:
		npc.awake = false; npc.mode = ""; npc.activity = ""
	if npc.awake and s.floor_state.visible.has(npc.pos): npc.noise_seen = s.round_number
	return npc.awake

## One round of an awake npc: it fights whatever its own eyes find, and
## otherwise holds (Task 4 puts the activity modes here).
static func turn(s, npc: Dictionary) -> void:
	npc.ap = 1
	var seen: int = MonsterAI.sight(s)
	var foes: Array = s.enemies.filter(func(e): return e.hp > 0 and MonsterAI.line(s,npc.pos,e.pos,seen))
	if not foes.is_empty():
		npc.activity = LABELS.FIGHT; npc.mode = ""
		var choice: Dictionary = Tactics.choose(s,npc)
		perform(s,npc,choice)
		return
	npc.activity = LABELS.HOLD  # Task 4 replaces this with the mode selector.

## The chosen action, with a wait as the fallback when it will not run.
static func perform(s, npc: Dictionary, choice: Dictionary) -> void:
	var kind: String = str(choice.get("kind","WAIT"))
	var cell: Vector2i = choice.get("cell",npc.pos)
	if not s.act_as(npc,kind,cell,false): s.act_as(npc,"WAIT",npc.pos,false)
	npc.explains.append({"round":s.round_number,"kind":kind,"cell":cell,"explain":choice.get("explain",[])})
	if npc.explains.size() > 20: npc.explains.pop_front()
