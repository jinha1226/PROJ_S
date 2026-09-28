extends RefCounted
## Adapted from ../sim/abilities/tactical_action_selector.gd:
## enumerate legal candidates, compare effective damage and before/after threat,
## then deterministic ranking. Timeline costs are equal in this action-turn host.
##
## The live attack/wait profile ranks legal actions in Utility.combat_pick,
## then checks stress for a possible hesitation at execution. The legacy
## profile still uses stance weights and a separate retreat line.
##   hp% <= retreat_hp    태세를 건너뛰고 거리를 벌리는 MOVE 150, 회복 파츠 190
const Knobs = preload("res://expedition/ai/knobs.gd")
const Stances = preload("res://expedition/ai/stances.gd")
const Utility = preload("res://expedition/ai/utility.gd")
const PartsCandidates = preload("res://expedition/ai/parts_candidates.gd")
const RETREAT := {"score":150}

static func danger(s, point: Vector2i) -> int:
	var value := int(s.tile(point).fire)
	for intent in s.intents:
		if intent.cell == point: value += int(intent.damage)
	return value

## Decision previews remain deterministic and never roll. Only the execution
## caller asks this after all commands, rescues and utility choices are settled.
static func execution_choice(s, actor: Dictionary, choice: Dictionary) -> Dictionary:
	if str(choice.get("kind","WAIT")) == "WAIT" or not Stances.mistaken(s,actor): return choice
	return {"kind":"WAIT","cell":actor.pos,"reason":"머뭇거림","mistake":"HESITATE","explain":[]}

static func threat(s, enemy: Dictionary, point: Vector2i, position: Vector2i) -> int:
	if enemy.get("recovery",0) > 0: return 0
	if enemy.get("charging",false):
		for intent in s.intents:
			if intent.id == enemy.id and intent.cell == point: return int(intent.damage)
		return 0
	return 6 if s.melee_reach(position,point) else 0

## The live profile uses the shared evaluator below. This older stance pool
## remains for legacy combat sessions; neither branch rolls a mistake here.
static func choose(s, actor: Dictionary) -> Dictionary:
	if s.MobileEffects.active(actor): return Utility.combat_pick(s,actor,live_candidates(s,actor))
	var knobs: Dictionary = Knobs.effective(actor)
	var stance: String = Stances.effective(actor)
	# Standing in fire is the one thing every stance answers the same way.
	if int(s.tile(actor.pos).fire) > 0:
		var out: Vector2i = Stances.off_the_fire(s,actor,Stances.party_target(s,actor))
		if out != actor.pos: return {"kind":"MOVE","cell":out,"reason":"불길 회피","score":0,"explain":[]}
	var low: bool = actor.hp*100/actor.max_hp <= int(knobs.retreat_hp)
	# Below the retreat line staying alive outranks everything below it: this
	# stage sits above the utility pool, so it keeps its own hand constants.
	if low:
		var pool: Array = []
		var away: Vector2i = retreat_cell(s,actor)
		if s.free_movement:
			var world: Vector2 = s.Free.retreat(s,actor)
			if world != s.Free.position(actor):
				var retreat: Dictionary = s.Free.choice(actor,"MOVE",world,"후퇴"); retreat.score = RETREAT.score; pool.append(retreat)
		elif away != actor.pos: pool.append({"kind":"MOVE","cell":away,"score":RETREAT.score,"reason":"후퇴"})
		for o in PartsCandidates.candidates(s,actor):
			if s.Abilities.definition(o.kind).get("effect","") != "HEAL": continue
			o.score = 40+RETREAT.score; pool.append(o)
		if pool.is_empty(): pool = [{"kind":"WAIT","cell":actor.pos,"score":0,"reason":"대기"}]
		pool.sort_custom(rank); return pool[0]
	# 4단계: the stance's candidates and the parts in one pool. A 거리형 in
	# contact no longer needs a filter — `contact_penalty` (−1000) is what keeps
	# its reaching parts holstered.
	var stance_options: Array = Stances.candidates(s,actor,stance,knobs)+PartsCandidates.candidates(s,actor)
	if stance_options.is_empty(): return {"kind":"WAIT","cell":actor.pos,"reason":"대기"}
	return best(s,actor,stance_options,stance,knobs)

## Current attack/wait combat has no manually pressed part or chosen stance.
## Legal attacks, route steps and waiting compete in the shared evaluator.
static func live_candidates(s, actor: Dictionary) -> Array:
	if s.free_movement: return s.Free.candidates(s,actor,"")
	var options: Array = [{"kind":"WAIT","cell":actor.pos,"tag":"WAIT","reason":"대기"}]
	var foes: Array = s.hostiles_of(actor).filter(func(e): return int(e.hp) > 0 and s.Floor.MonsterAI.line(s,actor.pos,e.pos,6))
	if foes.is_empty(): return options
	foes.sort_custom(func(a,b): return s.distance(actor.pos,a.pos) < s.distance(actor.pos,b.pos) if s.distance(actor.pos,a.pos) != s.distance(actor.pos,b.pos) else int(a.id) < int(b.id))
	for foe in foes:
		var preview: Dictionary = s.attack_preview(foe.pos,actor.id)
		if not preview.is_empty(): options.append({"kind":"ATTACK","cell":foe.pos,"tag":"ATTACK","damage":int(preview.damage),"target_id":int(foe.id),"reason":"공격"})
	if s.status_blocks(actor,"MOVE"): return options
	var reach: int = int(s.CombatStats.stats(s,actor).range)
	var target: Dictionary = foes[0]
	var goals: Array = []
	for cell in Stances.near_free(s,target.pos,maxi(1,reach)):
		if s.distance(cell,target.pos) <= reach and s.Floor.MonsterAI.line(s,cell,target.pos,reach):
			goals.append(cell)
	if goals.is_empty(): goals = Stances.adjacent_free(s,target.pos)
	for step in Stances.steps_toward(s,actor,goals):
		options.append(Stances.move(actor,step,"MOVE:approach","접근"))
	if reach > 1 and s.melee_reach(actor.pos,target.pos):
		var away: Vector2i = retreat_cell(s,actor)
		if away != actor.pos: options.append(Stances.move(actor,away,"MOVE:disengage","거리 확보"))
	return options

## 설계 §1.5: the pool weighed against the stance's own profile. The context is
## the same for every candidate, so it is built once — and it carries the pool,
## which `rule_ready` reads to tell a rule's preferred target from its siblings.
static func best(s, actor: Dictionary, options: Array, stance: String, knobs: Dictionary) -> Dictionary:
	var ctx := Utility.context(s,actor,options)
	for o in options:
		var scored: Dictionary = Utility.score(s,actor,o,ctx,stance,knobs)
		o.score = scored.score; o.base_score = scored.base_score
		o.explain = scored.explain; o.build_terms = scored.build_terms
	options.sort_custom(rank)
	return options[0]

## Score first, then a stable name so that two equal candidates never flip.
static func rank(a, b) -> bool:
	return a.score > b.score if a.score != b.score else str(a.kind)+str(a.cell) < str(b.kind)+str(b.cell)

## Living allies whose melee reach `cell` sits inside.
static func adjacent_allies(s, actor: Dictionary, cell: Vector2i) -> int:
	var count := 0
	for mate in s.friends():
		if mate.id != actor.id and s.melee_reach(cell,mate.pos): count += 1
	return count

## The adjacent cell that puts the most ground between the actor and the
## nearest threat, or its own cell when nothing is better. Shared by the
## retreat line here and the RETREAT party command.
static func retreat_cell(s, actor: Dictionary) -> Vector2i:
	var threats: Array = s.combat_enemies()
	var best: Vector2i = actor.pos
	var score := -1
	for direction in s.DIRECTIONS:
		var cell: Vector2i = actor.pos+direction
		if not s.can_step(actor.pos,cell) or not s.is_free(cell): continue
		var nearest := 999
		for enemy in threats: nearest = mini(nearest,s.distance(cell,enemy.pos))
		if nearest > score: score = nearest; best = cell
	return best
