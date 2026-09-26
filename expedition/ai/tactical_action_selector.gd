extends RefCounted
## Adapted from ../sim/abilities/tactical_action_selector.gd:
## enumerate legal candidates, compare effective damage and before/after threat,
## then deterministic ranking. Timeline costs are equal in this action-turn host.
##
## Ordering is fixed (설계 §1): 명령 → 불길 → 후퇴선 → 실수 → 효용. The stance
## candidates carry no scores of their own any more: `Utility.score` weighs them
## against the stance's profile, and the knobs shift those weights (§4). Only the
## retreat line keeps hand numbers — it is the stage above the utility pool.
##   hp% <= retreat_hp    태세를 건너뛰고 거리를 벌리는 MOVE 150, 회복 파츠 190
const BuildSense = preload("res://expedition/ai/build_sense.gd")
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

static func threat(s, enemy: Dictionary, point: Vector2i, position: Vector2i) -> int:
	if enemy.get("recovery",0) > 0: return 0
	if enemy.get("charging",false):
		for intent in s.intents:
			if intent.id == enemy.id and intent.cell == point: return int(intent.damage)
		return 0
	return 6 if s.melee_reach(position,point) else 0

## The stages, in this order: the party command (resolved by the caller), fire
## underfoot, the retreat line, the mistake roll, and then one pool — the
## stance's candidates and the equipped parts — weighed by utility. The parts
## no longer pre-empt: their `rule_when` is the consideration `rule_ready`.
## Nothing else makes a MOVE, an ATTACK or a WAIT — the stance owns the
## member's intent.
static func choose(s, actor: Dictionary) -> Dictionary:
	var knobs: Dictionary = Knobs.effective(actor)
	var stance: String = Stances.effective(actor)
	# Standing in fire is the one thing every stance answers the same way.
	if int(s.tile(actor.pos).fire) > 0:
		var out: Vector2i = Stances.off_the_fire(s,actor,Stances.party_target(s))
		if out != actor.pos: return {"kind":"MOVE","cell":out,"reason":"불길 회피","score":0,"explain":[]}
	var low: bool = actor.hp*100/actor.max_hp <= int(knobs.retreat_hp)
	# A mistake round: the member hesitates, overreaches, or falls back on the
	# stance it would have picked itself. Staying alive still comes first.
	# `choose` only reports it — `mistake` on the returned choice — so that a UI
	# preview costs nothing; auto_step is what tallies it.
	var mistake := ""
	if not low and Stances.mistaken(s,actor):
		var kind: String = Stances.mistake_kind(actor)
		match kind:
			"HESITATE": return {"kind":"WAIT","cell":actor.pos,"reason":"머뭇거림","mistake":kind,"score":0,"explain":[]}
			"RECKLESS":
				var bold: Dictionary = knobs.duplicate(); bold.posture = 100
				var reckless: Array = Stances.candidates(s,actor,"CHARGER",bold)
				# Nothing to overreach with: the round is an ordinary one, and
				# nothing is reported, so the tally matches what actually ran.
				if not reckless.is_empty():
					var pick: Dictionary = best(s,actor,reckless,"CHARGER",bold)
					pick.reason = "무모함 · "+str(pick.reason)
					pick.mistake = kind
					return pick
			"REVERT": stance = Stances.default_stance(actor.profile); mistake = kind
	# Below the retreat line staying alive outranks everything below it: this
	# stage sits above the utility pool, so it keeps its own hand constants.
	if low:
		var pool: Array = []
		var away: Vector2i = retreat_cell(s,actor)
		if away != actor.pos: pool.append({"kind":"MOVE","cell":away,"score":RETREAT.score,"reason":"후퇴"})
		for o in PartsCandidates.candidates(s,actor):
			if s.Abilities.definition(o.kind).get("effect","") != "HEAL": continue
			o.score = 40+RETREAT.score; pool.append(o)
		if pool.is_empty(): pool = [{"kind":"WAIT","cell":actor.pos,"score":0,"reason":"대기"}]
		pool.sort_custom(rank); return pool[0]
	# 4단계: the stance's candidates and the parts in one pool. A 거리형 in
	# contact no longer needs a filter — `contact_penalty` (−1000) is what keeps
	# its reaching parts holstered.
	var stance_options: Array = Stances.candidates(s,actor,stance,knobs)+PartsCandidates.candidates(s,actor)
	# A REVERT is only a mistake once the stance it reverted to is what answers:
	# a rule that would have won anyway is the same round either way.
	if stance_options.is_empty(): return {"kind":"WAIT","cell":actor.pos,"reason":"대기","mistake":mistake}
	var chosen: Dictionary = best(s,actor,stance_options,stance,knobs)
	if mistake != "": chosen.mistake = mistake
	return chosen

## 설계 §1.5: the pool weighed against the stance's own profile. The context is
## the same for every candidate, so it is built once — and it carries the pool,
## which `rule_ready` reads to tell a rule's preferred target from its siblings.
static func best(s, actor: Dictionary, options: Array, stance: String, knobs: Dictionary) -> Dictionary:
	var ctx := Utility.context(s,actor,options)
	options = BuildSense.safe_options(s,actor,options,ctx)
	for o in options:
		var scored: Dictionary = Utility.score(s,actor,o,ctx,stance,knobs)
		o.score = scored.score; o.base_score = scored.base_score
		o.explain = scored.explain; o.build_terms = scored.build_terms
	var baseline: Array = options.duplicate()
	baseline.sort_custom(func(a,b): return int(a.base_score) > int(b.base_score) if int(a.base_score) != int(b.base_score) else str(a.kind)+str(a.cell) < str(b.kind)+str(b.cell))
	options.sort_custom(rank)
	var chosen: Dictionary = options[0]
	if str(chosen.kind)+str(chosen.cell) != str(baseline[0].kind)+str(baseline[0].cell):
		var terms: Array = chosen.build_terms
		terms.sort_custom(func(a,b): return int(a.contrib) > int(b.contrib) if int(a.contrib) != int(b.contrib) else str(a.id) < str(b.id))
		if str(chosen.get("tag","")) == "WAIT:yield": chosen.reason_code = "FINISH_YIELD"
		elif not terms.is_empty(): chosen.reason_code = {"build_target":"BUILD_TARGET","build_setup":"BUILD_SETUP","build_hold":"BUILD_HOLD","finish_form":"FINISH_FORM"}.get(str(terms[0].id),"")
		if str(chosen.get("reason_code","")) == "BUILD_TARGET":
			var families: Array = BuildSense.main(actor)
			families.sort_custom(func(a,b): return BuildSense.fit(s,actor,chosen,int(a)) > BuildSense.fit(s,actor,chosen,int(b)))
			chosen.reason_text = BuildSense.Subtypes.label(BuildSense.top_subtype(actor))+" 대상 우선"
		else: chosen.reason_text = {"BUILD_SETUP":"동료 지원","BUILD_HOLD":"자리 유지","FINISH_FORM":"부위 노리기","FINISH_YIELD":"마무리 양보"}.get(str(chosen.get("reason_code","")),"")
	return chosen

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
