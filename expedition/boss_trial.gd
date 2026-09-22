extends RefCounted
const Abilities = preload("res://expedition/abilities.gd")
## Simplified SPD-inspired patterns, implemented independently for an 10x10 arena.
const NAMES = ["수렁 포식자", "폭탄 암살자", "과부하 거인"]
const HINTS = ["폭발 후 탈진 틈에 공격 · 물에서 회복", "폭탄 예고 회피 · 순간이동한 보스 추격", "보호막 가동 시 전력탑 옆에서 탑 터치"]

static func target(s) -> Dictionary:
	var allies: Array = s.alive()
	allies.sort_custom(func(a,b): return s.distance(a.pos,s.enemies[0].pos) < s.distance(b.pos,s.enemies[0].pos))
	return allies[0]

static func prepare(s) -> void:
	for row in s.rooms:
		row.kind = "boss"; row.cleared = false
		row.pattern = row.id % 3; row.name = NAMES[row.pattern]
		row.pylon = Vector2i(4,4); row.shield = false; row.overloaded = false
		# Preserve generated cover and routes. Goo always has a small water pool.
		if row.pattern == 0:
			for point in [Vector2i(7,4),Vector2i(7,5)]:
				var cell: Dictionary = row.tiles[point.y*s.BOARD_SIDE+point.x]
				cell.terrain = "water"; cell.wet = 70

static func spawn(s) -> void:
	var row: Dictionary = s.rooms[s.room]
	if row.started: return
	row.started = true
	var boss: Dictionary = s.make_actor(100+s.room,NAMES[row.pattern],true)
	boss.pos = Vector2i(5,4); boss.hp = 64; boss.max_hp = 64
	boss.cooldown = 4; boss.recovery = 0
	var drops: Array = Abilities.droppable()
	boss.essence_id = "" if drops.is_empty() else drops[row.pattern % drops.size()]
	s.enemies.append(boss)

static func plan(s) -> void:
	if not s.enemies.is_empty() and s.enemies[0].get("fuse",0) > 0: return
	s.intents.clear()
	if s.alive().is_empty(): return
	var boss: Dictionary = s.enemies[0]
	var row: Dictionary = s.rooms[s.room]
	boss.charging = false
	if row.pattern == 2:
		if boss.hp <= boss.max_hp/2 and not row.overloaded:
			row.overloaded = true; row.shield = true
			# Never create an objective underneath an actor.
			for cell in [Vector2i(4,4),Vector2i(1,4),Vector2i(6,6)]:
				if s.is_free(cell): row.pylon = cell; break
		return
	if boss.get("recovery",0) > 0 or boss.get("cooldown",0) > 0: return
	if row.pattern == 0 and not s.melee_reach(boss.pos,target(s).pos): return
	boss.charging = true
	boss.fuse = 2
	var center: Vector2i = boss.pos if row.pattern == 0 else target(s).pos
	for y in range(s.BOARD_SIDE):
		for x in range(s.BOARD_SIDE):
			var cell := Vector2i(x,y)
			var marked: bool = s.distance(center,cell) <= 2 if row.pattern == 0 else absi(center.x-x) <= 1 and absi(center.y-y) <= 1
			if marked: s.intents.append({"id":boss.id,"cell":cell,"damage":16})

static func turn(s, boss: Dictionary) -> void:
	var row: Dictionary = s.rooms[s.room]
	var hero: Dictionary = target(s)
	if row.pattern == 0 and s.tile(boss.pos).terrain == "water": boss.hp = mini(boss.max_hp,boss.hp+3)
	if boss.get("recovery",0) > 0:
		boss.recovery -= 1; return
	if boss.get("charging",false):
		boss.fuse = maxi(0,boss.get("fuse",1)-1)
		if boss.fuse > 0: return
		var cells: Array = []
		for intent in s.intents:
			if intent.id == boss.id: cells.append(intent.cell)
		s.enemy_attack_effect(boss,cells,true)
		for intent in s.intents:
			if intent.id != boss.id: continue
			for ally in s.alive():
				if intent.cell == ally.pos: s.damage(ally,intent.damage,boss.id,"IMPACT")
		boss.charging = false
		boss.recovery = 1; boss.cooldown = 6
		if row.pattern == 1:
			for cell in [Vector2i(6,6),Vector2i(1,6),Vector2i(6,1),Vector2i(1,1)]:
				if s.is_free(cell) and s.distance(cell,hero.pos) >= 3:
					boss.pos = cell; break
		return
	boss.cooldown = maxi(0,boss.get("cooldown",0)-1)
	if s.melee_reach(boss.pos,hero.pos):
		s.enemy_attack_effect(boss,[hero.pos])
		s.damage(hero,8,boss.id,"IMPACT"); return
	var goals: Array = []
	for direction in s.DIRECTIONS:
		if s.is_free(hero.pos+direction) and s.melee_reach(hero.pos+direction,hero.pos): goals.append(hero.pos+direction)
	var route: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,boss.pos,goals,func(a,b): return s.can_step(a,b),func(_p): return 100)
	if route.found and route.path.size() > 1: boss.pos = route.path[1]
	if s.melee_reach(boss.pos,hero.pos):
		s.enemy_attack_effect(boss,[hero.pos]); s.damage(hero,8,boss.id,"IMPACT")

static func disable_pylon(s, point: Vector2i) -> bool:
	var row: Dictionary = s.rooms[s.room]
	var hero: Dictionary = s.party[s.selected]
	if s.phase != "BATTLE" or not row.shield or point != row.pylon or hero.ap <= 0 or s.distance(hero.pos,point) != 1: return false
	row.shield = false; hero.ap -= 1
	s.message("전력탑 파괴 · 보스 보호막 해제!")
	return true
