extends RefCounted
## Adapted from ../sim/abilities/tactical_action_selector.gd:
## enumerate legal candidates, compare effective damage and before/after threat,
## then deterministic ranking. Timeline costs are equal in this action-turn host.
##
## The behaviour knobs (spec §3.2) only shift scores between the candidates the
## rules did not pick, except the retreat line, which outranks the rules:
##   ATTACK / 피해 파츠          + posture * 15 / 100
##   위험 회피 MOVE          신중: + (-posture) * 30 / 100;
##                        공격적: 예고 칸이 아닌 위험(불)만이면 후보에서 제외
##   엄호 GUARD            + cohesion * 20 / 100
##   모든 이동 후보          ± cohesion * 10 / 100 (도착 칸의 인접 아군 수 증감)
##   hp% <= retreat_hp    rule_choice를 건너뛰고 거리를 벌리는 MOVE 150,
##                        회복 파츠 +150, 공격 후보 -20
const Knobs = preload("res://expedition/knobs.gd")
const KNOB := {"attack":15,"escape":30,"guard":20,"cohesion":10,"retreat_score":150,"retreat_attack":-20}

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

static func choose(s, actor: Dictionary) -> Dictionary:
	var knobs: Dictionary = Knobs.effective(actor)
	var low: bool = actor.hp*100/actor.max_hp <= int(knobs.retreat_hp)
	var options: Array = []
	var here := danger(s,actor.pos)
	# Nothing is coming for this cell: the danger underfoot is fire alone, and
	# an aggressive member simply stands in it.
	var fire_only: bool = not s.intents.any(func(intent): return intent.cell == actor.pos)
	for cell in s.movement_cells(actor.id):
		if danger(s,cell) >= here: continue
		if int(knobs.posture) > 0 and fire_only: continue
		var escape_score: int = 200+here-danger(s,cell)+(-int(knobs.posture))*KNOB.escape/100
		escape_score += cohesion_shift(s,actor,cell,knobs)
		options.append({"kind":"MOVE","cell":cell,"score":escape_score,"reason":"위험 회피"})
	for enemy in s.combat_enemies():
		if enemy.hp <= 0 or not s.melee_reach(actor.pos,enemy.pos): continue
		var preview: Dictionary = s.attack_preview(enemy.pos,actor.id)
		if preview.is_empty(): continue
		var amount := int(preview.get("damage",0))
		options.append({"kind":"ATTACK","cell":enemy.pos,"score":amount+(12 if amount >= enemy.hp else 0)+attack_shift(knobs,low),"reason":"기본 공격"})
		if "PUSH" in actor.equipped_abilities:
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
	# Below the retreat line staying alive outranks the rule list: open distance.
	if low:
		var away: Vector2i = retreat_cell(s,actor)
		if away != actor.pos:
			options.append({"kind":"MOVE","cell":away,"score":KNOB.retreat_score+cohesion_shift(s,actor,away,knobs),"reason":"후퇴"})
	# Otherwise the configured rules are resolved first so that a matched 엄호 can
	# answer before the escape move: holding the line means not stepping away. Any
	# other matched rule still yields to the escape, exactly as before.
	var ruled: Dictionary = {} if low else rule_choice(s,actor,options)
	if not ruled.is_empty() and s.Abilities.DEFINITIONS.get(ruled.kind,{}).get("target","") == "ALLY": return ruled
	var escapes: Array = options.filter(func(o): return o.kind == "MOVE")
	if not escapes.is_empty():
		escapes.sort_custom(func(a,b): return a.score > b.score)
		return escapes[0]
	if not ruled.is_empty(): return ruled
	# Basic attack is a fallback, never a reorderable skill rule.
	var attacks: Array = options.filter(func(o): return o.kind == "ATTACK")
	if not attacks.is_empty():
		attacks.sort_custom(func(a,b):
			var av: int = s.at(a.cell).hp if actor.basic_target == "LOWEST_HP" else s.distance(actor.pos,a.cell)
			var bv: int = s.at(b.cell).hp if actor.basic_target == "LOWEST_HP" else s.distance(actor.pos,b.cell)
			if av != bv: return av < bv
			return a.score > b.score if a.score != b.score else str(a.cell) < str(b.cell))
		return attacks[0]
	options.clear()
	var goals: Array = []
	for enemy in s.combat_enemies():
		if enemy.hp <= 0: continue
		for d in s.DIRECTIONS:
			if s.is_free(enemy.pos+d) and s.melee_reach(enemy.pos+d,enemy.pos) and danger(s,enemy.pos+d) == 0: goals.append(enemy.pos+d)
	if goals.is_empty(): return {"kind":"WAIT","cell":actor.pos,"reason":"대기"}
	var route: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,actor.pos,goals,func(a,b): return s.can_step(a,b) and danger(s,b) == 0,func(_p): return 100)
	if route.found and route.path.size() > 1:
		options.append({"kind":"MOVE","cell":route.path[1],"score":1+cohesion_shift(s,actor,route.path[1],knobs),"reason":"안전한 접근"})
	options.append({"kind":"WAIT","cell":actor.pos,"score":0,"reason":"대기"})
	options.sort_custom(func(a,b): return a.score > b.score if a.score != b.score else str(a.kind)+str(a.cell) < str(b.kind)+str(b.cell))
	return options[0]

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
