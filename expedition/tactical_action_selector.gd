extends RefCounted
## Adapted from ../sim/abilities/tactical_action_selector.gd:
## enumerate legal candidates, compare effective damage and before/after threat,
## then deterministic ranking. Timeline costs are equal in this action-turn host.
##
## Ordering is fixed (설계 §1): 명령 → 불길 → 후퇴선 → 실수 → 효용. The stance
## candidates carry no scores of their own any more: `Utility.score` weighs them
## against the stance's profile, and the knobs shift those weights (§4). Only the
## retreat line keeps hand numbers — it is the stage above the utility pool.
##   hp% <= retreat_hp    태세를 건너뛰고 거리를 벌리는 MOVE 150,
##                        회복 파츠 +150, 공격 파츠 -20
const Knobs = preload("res://expedition/knobs.gd")
const Stances = preload("res://expedition/stances.gd")
const Utility = preload("res://expedition/utility.gd")
const RETREAT := {"score":150,"attack":-20}

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
## underfoot, the retreat line, the mistake roll, the configured rules, and then
## the stance's candidates weighed by utility. Nothing else makes a MOVE, an
## ATTACK or a WAIT — the stance owns the member's intent.
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
	var options: Array = []
	rule_candidates(s,actor,low,options)
	# Below the retreat line staying alive outranks everything below it.
	if low:
		var away: Vector2i = retreat_cell(s,actor)
		if away != actor.pos: options.append({"kind":"MOVE","cell":away,"score":RETREAT.score,"reason":"후퇴"})
		var heals: Array = options.filter(func(o): return s.Abilities.DEFINITIONS.get(o.kind,{}).get("effect","") == "HEAL")
		var pool: Array = options.filter(func(o): return o.kind == "MOVE")+heals
		if pool.is_empty(): pool = [{"kind":"WAIT","cell":actor.pos,"score":0,"reason":"대기"}]
		pool.sort_custom(rank); return pool[0]
	# A 거리형 with a foe on it does not shoot: it opens distance first, so the
	# rules never see its reaching parts while it is in contact.
	var pool: Array = options
	if stance == "SKIRMISHER" and s.combat_enemies().any(func(e): return s.melee_reach(actor.pos,e.pos)):
		pool = options.filter(func(o): return int(s.Abilities.DEFINITIONS.get(o.kind,{}).get("range",0)) < 3)
	var ruled: Dictionary = rule_choice(s,actor,pool)
	if not ruled.is_empty(): return ruled
	var stance_options: Array = Stances.candidates(s,actor,stance,knobs)
	# A REVERT is only a mistake once the stance it reverted to is what answers:
	# a rule that would have won anyway is the same round either way.
	if stance_options.is_empty(): return {"kind":"WAIT","cell":actor.pos,"reason":"대기","mistake":mistake}
	var chosen: Dictionary = best(s,actor,stance_options,stance,knobs)
	if mistake != "": chosen.mistake = mistake
	return chosen

## 설계 §1.5: the stance's candidates weighed against its own profile. The
## context is the same for every candidate, so it is built once.
static func best(s, actor: Dictionary, options: Array, stance: String, knobs: Dictionary) -> Dictionary:
	var ctx := Utility.context(s,actor)
	for o in options:
		var scored: Dictionary = Utility.score(s,actor,o,ctx,stance,knobs)
		o.score = scored.score
		o.explain = scored.explain
	options.sort_custom(rank)
	return options[0]

## Score first, then a stable name so that two equal candidates never flip.
static func rank(a, b) -> bool:
	return a.score > b.score if a.score != b.score else str(a.kind)+str(a.cell) < str(b.kind)+str(b.cell)

## Everything the configured rules can pick from: 밀치기, 엄호 and the parts.
static func rule_candidates(s, actor: Dictionary, low: bool, options: Array) -> void:
	if "PUSH" in actor.equipped_abilities:
		for enemy in s.combat_enemies():
			if enemy.hp <= 0 or not s.melee_reach(actor.pos,enemy.pos): continue
			var landing: Vector2i = enemy.pos+(enemy.pos-actor.pos)
			var moved: bool = s.can_step(enemy.pos,landing)
			var benefit := 0
			var unsafe := false
			for ally in s.alive():
				var before := threat(s,enemy,ally.pos,enemy.pos)
				var after := 0 if enemy.get("charging",false) else threat(s,enemy,ally.pos,landing if moved else enemy.pos)
				benefit += before-after
				if after > before: unsafe = true
			var bonus: int = 0 if moved else s.Growth.power(actor,"MELEE",8)
			if moved: bonus += maxi(0,int(s.tile(landing).fire)-int(s.tile(enemy.pos).fire))
			# Do not push a foe onto healing water or out of another ally's melee reach.
			if moved:
				if s.boss_trial and s.rooms[s.room].pattern == 0 and s.tile(landing).terrain == "water": unsafe = true
				for ally in s.alive():
					if ally.id != actor.id and s.melee_reach(ally.pos,enemy.pos) and not s.melee_reach(ally.pos,landing) and benefit <= 0: unsafe = true
			if not unsafe:
				options.append({"kind":"PUSH","cell":enemy.pos,"score":40+benefit+bonus,"reason":"밀치기"})
	# 엄호 has no self form: one candidate per adjacent living ally.
	if "GUARD" in actor.equipped_abilities:
		for mate in s.alive():
			if mate.id != actor.id and s.melee_reach(actor.pos,mate.pos):
				options.append({"kind":"GUARD","cell":mate.pos,"score":35,"reason":"엄호"})
	for id in actor.equipped_abilities:
		if not s.Abilities.DEFINITIONS.has(id) or s.Abilities.DEFINITIONS[id].effect in ["PUSH","GUARD"]: continue
		var def: Dictionary = s.Abilities.DEFINITIONS[id]
		var targets: Array = [actor] if def.target == "SELF" else s.combat_enemies()
		for target in targets:
			if not s.Abilities.legal(s,actor,id,target.pos): continue
			if def.effect == "DAMAGE":
				var cells: Array = s.Abilities.cells(s,actor,id,target.pos)
				if s.alive().any(func(a): return (a.id != actor.id or def.self_hit) and a.pos in cells): continue
				if not s.combat_enemies().any(func(e): return e.hp > 0 and e.pos in cells): continue
			var part_score := 40
			if def.effect in ["DAMAGE","LUNGE"] and low: part_score += RETREAT.attack
			elif def.effect == "HEAL" and low: part_score += RETREAT.score
			options.append({"kind":id,"cell":target.pos,"score":part_score,"reason":def.name})

## Living allies whose melee reach `cell` sits inside.
static func adjacent_allies(s, actor: Dictionary, cell: Vector2i) -> int:
	var count := 0
	for mate in s.alive():
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

## First matching configured rule, or {} — the ranking the rule list promises.
static func rule_choice(s, actor: Dictionary, options: Array) -> Dictionary:
	for index in range(actor.rules.size()):
		var rule: Dictionary = actor.rules[index]
		if rule.skill not in actor.equipped_abilities: continue
		var matches: Array = options.filter(func(o): return s.Rules.matches(s,actor,o,rule))
		if matches.is_empty(): continue
		matches.sort_custom(func(a,b):
			var first: Dictionary = s.at(a.cell)
			var second: Dictionary = s.at(b.cell)
			var av: int = first.hp if rule.target in ["LOWEST_HP","ALLY"] else s.distance(actor.pos,a.cell)
			var bv: int = second.hp if rule.target in ["LOWEST_HP","ALLY"] else s.distance(actor.pos,b.cell)
			if av != bv: return av < bv
			return a.score > b.score if a.score != b.score else str(a.cell) < str(b.cell))
		var choice: Dictionary = matches[0].duplicate()
		choice.reason = "%d순위 · %s" % [index+1,s.Rules.skill(rule.skill).name]
		return choice
	return {}
