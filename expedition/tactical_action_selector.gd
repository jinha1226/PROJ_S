extends RefCounted
## Adapted from ../sim/abilities/tactical_action_selector.gd:
## enumerate legal candidates, compare effective damage and before/after threat,
## then deterministic ranking. Timeline costs are equal in this action-turn host.
const POLICIES = ["PROTECT", "OFFENSE", "MANUAL"]

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
	return 6 if s.distance(position,point) == 1 else 0

static func choose(s, actor: Dictionary) -> Dictionary:
	var options: Array = []
	var here := danger(s,actor.pos)
	for cell in s.movement_cells(actor.id):
		if danger(s,cell) < here:
			options.append({"kind":"MOVE","cell":cell,"score":200+here-danger(s,cell),"reason":"위험 회피"})
	for enemy in s.enemies:
		if enemy.hp <= 0 or s.distance(actor.pos,enemy.pos) != 1: continue
		var preview: Dictionary = s.attack_preview(enemy.pos,actor.id)
		var amount := int(preview.get("damage",0))
		options.append({"kind":"ATTACK","cell":enemy.pos,"score":amount+(12 if amount >= enemy.hp else 0),"reason":"기본 공격"})
		var landing: Vector2i = enemy.pos+(enemy.pos-actor.pos)
		var moved: bool = s.is_free(landing)
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
				if ally.id != actor.id and s.distance(ally.pos,enemy.pos) == 1 and s.distance(ally.pos,landing) > 1 and benefit <= 0: unsafe = true
		var policy: String = actor.tactics.PUSH
		if not unsafe and ((policy == "PROTECT" and benefit > 0) or (policy == "OFFENSE" and bonus > 0)):
			options.append({"kind":"PUSH","cell":enemy.pos,"score":40+benefit+bonus,"reason":"아군 보호·예고 차단" if policy == "PROTECT" else "충돌·위험 지형 활용"})
	var guard: String = actor.tactics.GUARD
	var incoming := here
	for enemy in s.enemies:
		if enemy.hp > 0: incoming += threat(s,enemy,actor.pos,enemy.pos)
	if incoming > 0 and (guard == "DANGER" or guard == "LOW_HP" and actor.hp*2 <= actor.max_hp):
		options.append({"kind":"GUARD","cell":actor.pos,"score":35,"reason":"위험 대비 방어"})
	# Policy priority is explicit, except escaping a marked tile always wins.
	for option in options:
		if option.kind == actor.get("priority","PUSH"): option.score += 60
	var goals: Array = []
	for enemy in s.enemies:
		if enemy.hp <= 0: continue
		for d in s.DIRECTIONS:
			if s.is_free(enemy.pos+d) and danger(s,enemy.pos+d) == 0: goals.append(enemy.pos+d)
	var route: Dictionary = s.TurnCore.path(8,8,actor.pos,goals,func(a,b): return s.distance(a,b) == 1 and s.is_free(b) and danger(s,b) == 0,func(_p): return 100)
	if route.found and route.path.size() > 1:
		options.append({"kind":"MOVE","cell":route.path[1],"score":1,"reason":"안전한 접근"})
	options.append({"kind":"WAIT","cell":actor.pos,"score":0,"reason":"대기"})
	options.sort_custom(func(a,b): return a.score > b.score if a.score != b.score else str(a.kind)+str(a.cell) < str(b.kind)+str(b.cell))
	return options[0]
