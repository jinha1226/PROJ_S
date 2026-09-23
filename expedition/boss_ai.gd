extends RefCounted
const Abilities = preload("res://expedition/abilities.gd")
## Simplified SPD-inspired patterns, implemented independently for an 10x10 arena.
const NAMES = ["수렁 포식자", "폭탄 암살자", "과부하 거인"]
const HINTS = ["폭발 후 탈진 틈에 공격 · 물에서 회복", "폭탄 예고 회피 · 순간이동한 보스 추격", "보호막 가동 시 전력탑 옆에서 탑 터치"]

static func target(s, boss: Dictionary) -> Dictionary:
	var allies: Array = s.alive()
	allies.sort_custom(func(a,b): return s.distance(a.pos,boss.pos) < s.distance(b.pos,boss.pos))
	return allies[0]

static func spawn(s, layout: Dictionary, depth: int) -> void:
	var pattern: int = posmod(int(depth/3)-1,3)
	var boss: Dictionary = s.make_actor(900+depth,NAMES[pattern],true)
	var lair: Dictionary = {}
	for room in layout.rooms:
		if room.template_id == "boss_lair": lair = room; break
	boss.pos = s.Floor.Generator.room_anchor(lair)
	boss.hp = 64+8*(int(depth/3)-1); boss.max_hp = boss.hp
	boss.speed = 100; boss.ready_at = int(s.time)+int(boss.speed)
	boss.boss = true; boss.pattern = pattern
	boss.cooldown = 4; boss.recovery = 0; boss.shield = false; boss.overloaded = false; boss.fuse = 0
	boss.alert = false; boss.charging = false; boss.role = "MELEE"
	boss.pylon = Vector2i(-1,-1)
	for point in layout.features:
		if layout.features[point].kind == "pylon": boss.pylon = point; break
	var drops: Array = Abilities.droppable()
	boss.part_id = drops[pattern % drops.size()] if not drops.is_empty() else ""
	s.enemies.append(boss)

static func plan(s, boss: Dictionary) -> void:
	if s.alive().is_empty(): return
	if boss.get("fuse",0) > 0:
		for cell in boss.get("intent_cells",[]): s.intents.append({"id":boss.id,"cell":cell,"damage":16,"kind":"BOSS","resolve_at":int(boss.get("resolve_at",s.time+int(boss.fuse)*100))})
		return
	boss.charging = false
	if boss.pattern == 2:
		if boss.hp <= boss.max_hp/2 and not boss.overloaded:
			boss.overloaded = true; boss.shield = true
		return
	if boss.get("recovery",0) > 0 or boss.get("cooldown",0) > 0: return
	if boss.pattern == 0 and not s.melee_reach(boss.pos,target(s,boss).pos): return
	boss.charging = true
	boss.fuse = 2
	boss.resolve_at = s.time+200
	var center: Vector2i = boss.pos if boss.pattern == 0 else target(s,boss).pos
	boss.intent_cells = []
	for y in range(s.BOARD_SIDE):
		for x in range(s.BOARD_SIDE):
			var cell := Vector2i(x,y)
			var marked: bool = s.distance(center,cell) <= 2 if boss.pattern == 0 else absi(center.x-x) <= 1 and absi(center.y-y) <= 1
			if marked:
				boss.intent_cells.append(cell)
				s.intents.append({"id":boss.id,"cell":cell,"damage":16,"kind":"BOSS","resolve_at":int(boss.resolve_at)})

static func turn(s, boss: Dictionary) -> void:
	var hero: Dictionary = target(s,boss)
	if boss.pattern == 0 and s.tile(boss.pos).terrain == "water": boss.hp = mini(boss.max_hp,boss.hp+3)
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
		if boss.pattern == 1:
			for room in s.floor_state.layout.rooms:
				if room.template_id != "boss_lair": continue
				for cell in s.Floor.Generator.floor_cells(s.floor_state.layout.terrain,s.BOARD_SIDE,room.rect):
					if s.is_free(cell) and s.distance(cell,hero.pos) >= 3: boss.pos = cell; break
		return
	boss.cooldown = maxi(0,boss.get("cooldown",0)-1)
	if s.melee_reach(boss.pos,hero.pos):
		s.enemy_attack_effect(boss,[hero.pos])
		if s.manual_mode:
			boss.power = 8; s.CombatRules.attack(s,boss,hero)
		else: s.damage(hero,8,boss.id,"IMPACT")
		return
	var goals: Array = []
	for direction in s.DIRECTIONS:
		if s.is_free(hero.pos+direction) and s.melee_reach(hero.pos+direction,hero.pos): goals.append(hero.pos+direction)
	var route: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,boss.pos,goals,func(a,b): return s.can_step(a,b),func(_p): return 100)
	if route.found and route.path.size() > 1: boss.pos = route.path[1]
	if s.melee_reach(boss.pos,hero.pos):
		s.enemy_attack_effect(boss,[hero.pos])
		if s.manual_mode:
			boss.power = 8; s.CombatRules.attack(s,boss,hero)
		else: s.damage(hero,8,boss.id,"IMPACT")

static func disable_pylon(s, point: Vector2i) -> bool:
	var hero: Dictionary = s.party[s.selected]
	var bosses: Array = s.enemies.filter(func(e): return e.get("boss",false) and e.hp > 0)
	if bosses.is_empty(): return false
	var boss: Dictionary = bosses[0]
	if s.phase != "BATTLE" or not boss.shield or point != boss.pylon or hero.ap <= 0 or s.distance(hero.pos,point) != 1: return false
	boss.shield = false; hero.ap -= 1
	s.message("전력탑 파괴 · 보호막 해제")
	return true
