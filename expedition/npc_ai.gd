extends RefCounted
## Dungeon NPCs: their senses, their round, and their manners toward the party.
const MonsterAI = preload("res://expedition/monster_ai.gd")
const Tactics = preload("res://expedition/tactical_action_selector.gd")
const Stances = preload("res://expedition/stances.gd")
const Knobs = preload("res://expedition/knobs.gd")
const Modes = preload("res://expedition/npc_modes.gd")
const NOISE_RADIUS := 10
const SLEEP_AFTER := 5
const MATE_LABEL := "동료에게 이동 중"
const LABELS := {"FIGHT":"교전 중","APPROACH":"다가오는 중","HOLD":"거리를 두고 지켜보는 중","REST":"부상으로 대기 중","EXPLORE":"주변을 탐색 중","":""}

## Wakes on its own sight of the party or on nearby combat; sleeps after five quiet rounds unseen.
static func sense(s, npc: Dictionary) -> bool:
	var seen: int = MonsterAI.sight(s)
	var sees_party: bool = s.alive().any(func(a): return MonsterAI.line(s,npc.pos,a.pos,seen))
	var hears: bool = s.noise.any(func(p): return s.distance(p,npc.pos) <= NOISE_RADIUS)
	if sees_party or hears:
		npc.awake = true; npc.noise_seen = s.npc_clock()
		return true
	if npc.awake and not s.floor_state.visible.has(npc.pos) and s.npc_clock()-int(npc.noise_seen) >= (500 if s.manual_mode else SLEEP_AFTER):
		npc.awake = false; npc.mode = ""; npc.activity = ""
	if npc.awake and s.floor_state.visible.has(npc.pos): npc.noise_seen = s.npc_clock()
	return npc.awake

## One round of an awake npc: it fights whatever its own eyes find, and
## otherwise runs the field modes — approach, hold, rest, explore — off a small
## utility table, a duo's cohesion coming before the mode's own step.
static func turn(s, npc: Dictionary) -> void:
	npc.ap = 1
	var seen: int = MonsterAI.sight(s)
	var foes: Array = s.enemies.filter(func(e): return e.hp > 0 and MonsterAI.line(s,npc.pos,e.pos,seen))
	if not foes.is_empty():
		npc.activity = LABELS.FIGHT; npc.mode = ""
		var choice: Dictionary = Tactics.choose(s,npc)
		perform(s,npc,choice)
		return
	var pick: Dictionary = Modes.choose(s,npc)
	if pick.mode != str(npc.get("mode","")): npc.mode = pick.mode; npc.mode_until = s.npc_clock()+(Modes.COMMIT_ROUNDS*100 if s.manual_mode else Modes.COMMIT_ROUNDS)
	npc.activity = LABELS[pick.mode]
	npc.explains.append({"round":s.round_number,"kind":pick.mode,"cell":npc.pos,"explain":pick.explain})
	while npc.explains.size() > 20: npc.explains.pop_front()
	# A duo keeps together before anything else: the one lagging behind walks to
	# the other, so a pair never spends the round swapping places.
	var mate: Dictionary = partner_of(s,npc)
	if not mate.is_empty() and mate.awake and s.distance(npc.pos,mate.pos) > 1 and lagging(s,npc,mate):
		if close_on(s,npc,Stances.adjacent_free(s,mate.pos),mate.pos):
			npc.activity = MATE_LABEL
			return
	match pick.mode:
		"APPROACH":
			var near: Dictionary = nearest_member(s,npc)
			if s.melee_reach(npc.pos,near.pos):
				if s.npc_clock() >= int(npc.get("offered_until",-99)) and s.pending_offer < 0: s.offer(npc)
				return
			close_on(s,npc,Stances.adjacent_free(s,near.pos),near.pos)
		"HOLD":
			var near: Dictionary = nearest_member(s,npc)
			var d: int = s.distance(npc.pos,near.pos)
			if d < 3 or d > 5:
				var ring: Array = Stances.near_free(s,near.pos,4).filter(func(p): return s.distance(p,near.pos) >= 3 and s.distance(p,near.pos) <= 5)
				var steps: Array = Stances.steps_toward(s,npc,ring)
				if not steps.is_empty(): s.act_as(npc,"MOVE",steps[0],false)
		"REST": pass
		"EXPLORE":
			var goal: Vector2i = explore_goal(s,npc)
			# A room centre can be a wall or an occupied cell: aim for the free
			# ground around it rather than idling on an unreachable goal.
			var goals: Array = [goal] if s.is_free(goal) else Stances.near_free(s,goal,2)
			var steps: Array = Stances.steps_toward(s,npc,goals)
			if not steps.is_empty(): s.act_as(npc,"MOVE",steps[0],false)

## One step along the route to `goals`. The route ties on a diagonal as often
## as not, so among the steps that close just as fast the one that ends nearest
## `target` wins, and the cell itself breaks the last tie: the walk is
## deterministic and never idles a round sidling across the party's row.
static func close_on(s, npc: Dictionary, goals: Array, target: Vector2i) -> bool:
	if goals.is_empty(): return false
	# The cells that stand closest to `target` are aimed for first; the rest are
	# the fallback when none of them can be reached.
	var near: int = goals.map(func(g): return s.distance(g,target)).min()
	var steps: Array = Stances.steps_toward(s,npc,goals.filter(func(g): return s.distance(g,target) == near))
	if steps.is_empty(): steps = Stances.steps_toward(s,npc,goals)
	if steps.is_empty(): return false
	steps.sort_custom(func(a,b):
		var da: int = s.distance(a,target); var db: int = s.distance(b,target)
		if da != db: return da < db
		return a.x < b.x if a.x != b.x else a.y < b.y)
	return s.act_as(npc,"MOVE",steps[0],false)

## Which of a pair closes the gap: the one standing farther from the party, the
## higher id breaking a tie. The other holds its own mode.
static func lagging(s, npc: Dictionary, mate: Dictionary) -> bool:
	var mine: int = s.distance(npc.pos,nearest_member(s,npc).pos)
	var theirs: int = s.distance(mate.pos,nearest_member(s,mate).pos)
	return mine > theirs or (mine == theirs and int(npc.id) > int(mate.id))

## The partner of a duo, while it lives.
static func partner_of(s, npc: Dictionary) -> Dictionary:
	if int(npc.get("partner",-1)) < 0: return {}
	for n in s.npcs:
		if n.id == npc.partner and n.hp > 0: return n
	return {}

## The living party member nearest this npc.
static func nearest_member(s, npc: Dictionary) -> Dictionary:
	var best: Dictionary = s.alive()[0]
	for a in s.alive():
		if s.distance(npc.pos,a.pos) < s.distance(npc.pos,best.pos): best = a
	return best

## Room centres farthest from the entry first, cycling by npc id so two npcs do
## not walk the same room and a reached goal never stalls the walk.
static func explore_goal(s, npc: Dictionary) -> Vector2i:
	var layout: Dictionary = s.floor_state.layout
	var centres: Array = layout.rooms.map(func(r): return Vector2i(r.rect.get_center()))
	centres.sort_custom(func(a,b): return s.distance(a,layout.entry) > s.distance(b,layout.entry))
	var start: int = npc.id % maxi(1,centres.size())
	for i in range(centres.size()):
		var c: Vector2i = centres[(start+i) % centres.size()]
		if s.distance(c,npc.pos) > 2: return c
	return npc.pos

## The chosen action, with a wait as the fallback when it will not run.
static func perform(s, npc: Dictionary, choice: Dictionary) -> void:
	var kind: String = str(choice.get("kind","WAIT"))
	var cell: Vector2i = choice.get("cell",npc.pos)
	if not s.act_as(npc,kind,cell,false): s.act_as(npc,"WAIT",npc.pos,false)
	npc.explains.append({"round":s.round_number,"kind":kind,"cell":cell,"explain":choice.get("explain",[])})
	while npc.explains.size() > 20: npc.explains.pop_front()
