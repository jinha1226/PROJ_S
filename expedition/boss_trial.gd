extends RefCounted
## Simplified SPD-inspired patterns, implemented independently for an 8x8 arena.
const NAMES = ["수렁 포식자", "폭탄 암살자", "과부하 거인"]
const HINTS = ["충전 폭발 회피 · 보스는 물에서 회복", "폭탄 예고 회피 · 순간이동한 보스 추격", "보호막 가동 시 전력탑 옆에서 탑 터치"]

static func prepare(s) -> void:
	for row in s.rooms:
		row.kind = "boss"; row.cleared = false
		row.pattern = row.id % 3; row.name = NAMES[row.pattern]
		row.pylon = Vector2i(4,4); row.shield = false; row.overloaded = false
		for y in range(8):
			for x in range(8):
				var cell: Dictionary = row.tiles[y*8+x]
				cell.terrain = "water" if row.pattern == 0 and x == 5 else "stone"
				cell.wet = 70 if cell.terrain == "water" else 0; cell.fire = 0

static func spawn(s) -> void:
	var row: Dictionary = s.rooms[s.room]
	if row.started: return
	row.started = true
	var boss: Dictionary = s.make_actor(100+s.room,NAMES[row.pattern],true)
	boss.pos = Vector2i(5,4); boss.hp = 64; boss.max_hp = 64
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
				if s.at(cell).is_empty(): row.pylon = cell; break
		return
	if s.round_number % 3 != 0: return
	boss.charging = true
	boss.fuse = 2
	var center: Vector2i = boss.pos if row.pattern == 0 else s.party[0].pos
	for y in range(8):
		for x in range(8):
			var cell := Vector2i(x,y)
			var marked: bool = s.distance(center,cell) <= 2 if row.pattern == 0 else absi(center.x-x) <= 1 and absi(center.y-y) <= 1
			if marked: s.intents.append({"id":boss.id,"cell":cell,"damage":16})

static func turn(s, boss: Dictionary) -> void:
	var row: Dictionary = s.rooms[s.room]
	var hero: Dictionary = s.party[0]
	if row.pattern == 0 and s.tile(boss.pos).terrain == "water": boss.hp = mini(boss.max_hp,boss.hp+3)
	if boss.get("charging",false):
		boss.fuse = maxi(0,boss.get("fuse",1)-1)
		if boss.fuse > 0: return
		for intent in s.intents:
			if intent.cell == hero.pos: s.damage(hero,intent.damage,boss.id,"IMPACT")
		if row.pattern == 1:
			for cell in [Vector2i(6,6),Vector2i(1,6),Vector2i(6,1),Vector2i(1,1)]:
				if s.is_free(cell) and s.distance(cell,hero.pos) >= 3:
					boss.pos = cell; break
		return
	if s.distance(boss.pos,hero.pos) == 1:
		s.damage(hero,6,boss.id,"IMPACT"); return
	var goals: Array = []
	for direction in s.DIRECTIONS:
		if s.is_free(hero.pos+direction): goals.append(hero.pos+direction)
	var route: Dictionary = s.TurnCore.path(8,8,boss.pos,goals,func(a,b): return s.distance(a,b) == 1 and s.is_free(b),func(_p): return 100)
	if route.found and route.path.size() > 1: boss.pos = route.path[1]

static func disable_pylon(s, point: Vector2i) -> bool:
	var row: Dictionary = s.rooms[s.room]
	var hero: Dictionary = s.party[0]
	if s.phase != "BATTLE" or not row.shield or point != row.pylon or hero.ap <= 0 or s.distance(hero.pos,point) != 1: return false
	row.shield = false; hero.ap -= 1
	s.message("전력탑 파괴 · 보스 보호막 해제!")
	return true
