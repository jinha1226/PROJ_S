extends RefCounted
## Adapted from ../sim/abilities/tactical_action_selector.gd:
## enumerate legal candidates, compare effective damage and before/after threat,
## then deterministic ranking. Timeline costs are equal in this action-turn host.
##
## Ordering is fixed (spec §0.7): 명령 → 후퇴선 → 규칙 → 태세. The behaviour knobs
## shift scores inside a stage; the stance programmes in stances.gd read them too:
##   피해 파츠              + posture * 15 / 100
##   엄호 GUARD            + cohesion * 20 / 100
##   태세의 이동 후보        ± cohesion * 10 / 100 (도착 칸의 인접 아군 수 증감)
##   hp% <= retreat_hp    규칙과 태세를 건너뛰고 거리를 벌리는 MOVE 150,
##                        회복 파츠 +150, 공격 후보 -20
const Knobs = preload("res://expedition/knobs.gd")
const Stances = preload("res://expedition/stances.gd")
const KNOB := {"attack":15,"guard":20,"cohesion":10,"retreat_score":150,"retreat_attack":-20}

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

## Four stages, in this order: the party command (resolved by the caller), the
## retreat line, the configured rules, and then the stance. Nothing else makes
## a MOVE, an ATTACK or a WAIT — the stance owns the member's intent.
static func choose(s, actor: Dictionary) -> Dictionary:
	var knobs: Dictionary = Knobs.effective(actor)
	var stance: String = Stances.effective(actor)
	var low: bool = actor.hp*100/actor.max_hp <= int(knobs.retreat_hp)
	var options: Array = []
	rule_candidates(s,actor,knobs,low,options)
	# Below the retreat line staying alive outranks everything below it.
	if low:
		var away: Vector2i = retreat_cell(s,actor)
		if away != actor.pos: options.append({"kind":"MOVE","cell":away,"score":KNOB.retreat_score+cohesion_shift(s,actor,away,knobs),"reason":"후퇴"})
		var heals: Array = options.filter(func(o): return s.Abilities.DEFINITIONS.get(o.kind,{}).get("effect","") == "HEAL")
		var pool: Array = options.filter(func(o): return o.kind == "MOVE")+heals
		if pool.is_empty(): pool = [{"kind":"WAIT","cell":actor.pos,"score":0,"reason":"대기"}]
		pool.sort_custom(rank); return pool[0]
	var ruled: Dictionary = rule_choice(s,actor,options)
	if not ruled.is_empty(): return ruled
	var stance_options: Array = Stances.candidates(s,actor,stance,knobs)
	for o in stance_options:
		if o.kind == "MOVE": o.score += cohesion_shift(s,actor,o.cell,knobs)
	if stance_options.is_empty(): return {"kind":"WAIT","cell":actor.pos,"reason":"대기"}
	stance_options.sort_custom(rank)
	return stance_options[0]

## Score first, then a stable name so that two equal candidates never flip.
static func rank(a, b) -> bool:
	return a.score > b.score if a.score != b.score else str(a.kind)+str(a.cell) < str(b.kind)+str(b.cell)

## Everything the configured rules can pick from: 밀치기, 엄호 and the parts.
static func rule_candidates(s, actor: Dictionary, knobs: Dictionary, low: bool, options: Array) -> void:
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
				options.append({"kind":"GUARD","cell":mate.pos,"score":35+int(knobs.cohesion)*KNOB.guard/100,"reason":"엄호"})
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
			if def.effect in ["DAMAGE","LUNGE"]: part_score += attack_shift(knobs,low)
			elif def.effect == "HEAL" and low: part_score += KNOB.retreat_score
			options.append({"kind":id,"cell":target.pos,"score":part_score,"reason":def.name})

## Living allies whose melee reach `cell` sits inside.
static func adjacent_allies(s, actor: Dictionary, cell: Vector2i) -> int:
	var count := 0
	for mate in s.alive():
		if mate.id != actor.id and s.melee_reach(cell,mate.pos): count += 1
	return count

## What moving to `cell` is worth to a member who wants to keep (or break)
## contact with the others.
static func cohesion_shift(s, actor: Dictionary, cell: Vector2i, knobs: Dictionary) -> int:
	var delta := adjacent_allies(s,actor,cell)-adjacent_allies(s,actor,actor.pos)
	return signi(delta)*int(knobs.cohesion)*KNOB.cohesion/100

static func attack_shift(knobs: Dictionary, low: bool) -> int:
	return int(knobs.posture)*KNOB.attack/100+(KNOB.retreat_attack if low else 0)

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
