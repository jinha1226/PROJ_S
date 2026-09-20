extends RefCounted
## Adapted from ../sim/abilities/tactical_action_selector.gd:
## enumerate legal candidates, compare effective damage and before/after threat,
## then deterministic ranking. Timeline costs are equal in this action-turn host.

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
	var options: Array = []
	var here := danger(s,actor.pos)
	for cell in s.movement_cells(actor.id):
		if danger(s,cell) < here:
			options.append({"kind":"MOVE","cell":cell,"score":200+here-danger(s,cell),"reason":"위험 회피"})
	for enemy in s.enemies:
		if enemy.hp <= 0 or not s.melee_reach(actor.pos,enemy.pos): continue
		var preview: Dictionary = s.attack_preview(enemy.pos,actor.id)
		if preview.is_empty(): continue
		var amount := int(preview.get("damage",0))
		options.append({"kind":"ATTACK","cell":enemy.pos,"score":amount+(12 if amount >= enemy.hp else 0),"reason":"기본 공격"})
		var landing: Vector2i = enemy.pos+(enemy.pos-actor.pos)
		var moved: bool = s.can_step(enemy.pos,landing)
		var benefit := 0
		var unsafe := false
		for ally in s.alive():
			var before := threat(s,enemy,ally.pos,enemy.pos)
			var after := 0 if enemy.get("charging",false) else threat(s,enemy,ally.pos,landing if moved else enemy.pos)
			benefit += before-after
			if after > before: unsafe = true
		var bonus := 0 if moved else 8
		if moved: bonus += maxi(0,int(s.tile(landing).fire)-int(s.tile(enemy.pos).fire))
		# Do not push a foe onto healing water or out of another ally's melee reach.
		if moved:
			if s.boss_trial and s.rooms[s.room].pattern == 0 and s.tile(landing).terrain == "water": unsafe = true
			for ally in s.alive():
				if ally.id != actor.id and s.melee_reach(ally.pos,enemy.pos) and not s.melee_reach(ally.pos,landing) and benefit <= 0: unsafe = true
		if not unsafe:
			options.append({"kind":"PUSH","cell":enemy.pos,"score":40+benefit+bonus,"reason":"밀치기"})
	options.append({"kind":"GUARD","cell":actor.pos,"score":35,"reason":"방어"})
	# Safety escape first, then the first matching configured rule. No score
	# from a lower-priority skill may override an earlier valid rule.
	var escapes: Array = options.filter(func(o): return o.kind == "MOVE")
	if not escapes.is_empty():
		escapes.sort_custom(func(a,b): return a.score > b.score)
		return escapes[0]
	for index in range(actor.rules.size()):
		var rule: Dictionary = actor.rules[index]
		var matches: Array = options.filter(func(o): return s.Rules.matches(s,actor,o,rule))
		if matches.is_empty(): continue
		matches.sort_custom(func(a,b):
			var first: Dictionary = s.at(a.cell)
			var second: Dictionary = s.at(b.cell)
			var av: int = first.hp if rule.target == "LOWEST_HP" else s.distance(actor.pos,a.cell)
			var bv: int = second.hp if rule.target == "LOWEST_HP" else s.distance(actor.pos,b.cell)
			if av != bv: return av < bv
			return a.score > b.score if a.score != b.score else str(a.cell) < str(b.cell))
		var choice: Dictionary = matches[0].duplicate()
		choice.reason = "%d순위 · %s" % [index+1,s.Rules.SKILLS[rule.skill].name]
		return choice
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
	for enemy in s.enemies:
		if enemy.hp <= 0: continue
		for d in s.DIRECTIONS:
			if s.is_free(enemy.pos+d) and s.melee_reach(enemy.pos+d,enemy.pos) and danger(s,enemy.pos+d) == 0: goals.append(enemy.pos+d)
	var route: Dictionary = s.TurnCore.path(8,8,actor.pos,goals,func(a,b): return s.can_step(a,b) and danger(s,b) == 0,func(_p): return 100)
	if route.found and route.path.size() > 1:
		options.append({"kind":"MOVE","cell":route.path[1],"score":1,"reason":"안전한 접근"})
	options.append({"kind":"WAIT","cell":actor.pos,"score":0,"reason":"대기"})
	options.sort_custom(func(a,b): return a.score > b.score if a.score != b.score else str(a.kind)+str(a.cell) < str(b.kind)+str(b.cell))
	return options[0]
