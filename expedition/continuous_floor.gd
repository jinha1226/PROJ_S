extends RefCounted
const Source = preload("res://expedition/legacy/four_zone_floor.gd")
const Registry = preload("res://expedition/legacy/dcss_enemy_registry.gd")
const LegacyAI = preload("res://expedition/floor_tactics_adapter.gd")
const SIZE := 100
var layout: Dictionary
var visible: Dictionary = {}
var explored: Dictionary = {}
var features: Dictionary = {}
var discoveries: Array = []
var epoch := ""

static func point(p: Vector2i) -> Vector2i:
	return p*2+Vector2i(2,2)

func build(s) -> void:
	layout = Source.generate(1,s.seed_value+s.expedition_number*7919)
	epoch = str(s.seed_value)+"/"+str(s.expedition_number)
	visible.clear(); explored.clear(); discoveries.clear(); features.clear()
	s.BOARD_SIDE = SIZE; s.tiles = []
	for y in range(SIZE):
		for x in range(SIZE):
			var source := Vector2i((x-2)/2,(y-2)/2)
			var terrain := "wall"
			if x >= 2 and y >= 2 and x < 98 and y < 98: terrain = layout.terrain[source.y*48+source.x]
			var translated: String = {"floor":"stone","stone_floor":"stone","rubble":"stone","wood_floor":"wood","shallow_water":"water"}.get(terrain,terrain)
			s.tiles.append({"terrain":translated,"source_terrain":terrain,"fire":0,"wet":70 if translated == "water" else 0,"variant":posmod(x*13+y*7,3),"palette":0})
	s.enemies = []
	for row in layout.runtime_enemy_roster:
		var profile: Dictionary = Registry.profile(row.species_id)
		var enemy: Dictionary = s.make_actor(100+s.enemies.size(),profile.get("display_name","코볼트" if row.species_id == "kobold" else "고블린"),true)
		enemy.pos = point(row.position); enemy.hp = profile.get("max_health",28); enemy.max_hp = enemy.hp
		enemy.group = row.group_id; enemy.home = enemy.pos; enemy.alert = false
		enemy.essence_id = ["BOMB","SHOCKWAVE","IRON_HIDE"][s.enemies.size()%3]
		s.enemies.append(enemy)
	for i in range(s.party.size()):
		s.party[i].pos = point(layout.entry_position)+Vector2i(0,i); s.party[i].ap = 1
		s.party[i].reservation = {}
	for p in layout.supply_positions: features[point(p)] = {"kind":"loot","used":false,"label":"보급 상자"}
	features[point(layout.entry_position)] = {"kind":"entry","used":false,"label":"귀환 관문"}
	features[point(layout.transition_portal_position)] = {"kind":"exit","used":false,"label":"1층 출구"}
	for row in layout.landmarks:
		features[point(row.position)] = {"kind":"camp" if row.kind == "CAMP" else "relic","used":false,"label":row.label}
	s.rooms = [{"id":0,"name":"1층 · 갈림길 미궁","kind":"floor","links":[],"tiles":s.tiles,"enemies":s.enemies,"started":true,"cleared":false,"shield":false,"pattern":-1,"used":false,"feature":Vector2i(-1,-1)}]
	s.room = 0; s.phase = "BATTLE"; s.round_number = 1
	observe(s)

func observe(s) -> void:
	visible.clear()
	for actor in s.alive():
		for y in range(maxi(0,actor.pos.y-7),mini(SIZE,actor.pos.y+8)):
			for x in range(maxi(0,actor.pos.x-7),mini(SIZE,actor.pos.x+8)):
				var p := Vector2i(x,y)
				if actor.pos.distance_squared_to(p) > 49: continue
				if not s.TurnCore.Geometry.sees(actor.pos,p,func(c): return s.tile(c).terrain == "wall"): continue
				visible[p] = true
				if not explored.has(p):
					explored[p] = true
					var feature: Dictionary = features.get(p,{})
					discoveries.append({"position":[x,y],"terrain_id":s.tile(p).terrain,"visibility_state":"MEMORY","marker":"EXIT" if feature.get("kind","") in ["entry","exit"] else "PORTAL" if feature.get("kind","") == "relic" else ""})

func observation(s) -> Dictionary:
	var markers: Array = []
	for actor in s.party+s.enemies:
		if actor.hp > 0 and visible.has(actor.pos): markers.append({"position":[actor.pos.x,actor.pos.y],"marker":"ENEMY" if actor.enemy else "HERO"})
	return {"width":SIZE,"height":SIZE,"epoch":epoch,"cells":discoveries,"discovery_rows":discoveries,"static_count":discoveries.size(),"visible":visible.keys().map(func(p): return [p.x,p.y]),"markers":markers}

func threats(s) -> Array:
	return s.enemies.filter(func(e): return e.hp > 0 and visible.has(e.pos))

func safe(s) -> bool:
	return threats(s).is_empty()

func interact(s, p: Vector2i) -> bool:
	if s.phase != "BATTLE" or s.party[s.selected].hp <= 0 or s.party[s.selected].ap <= 0: return false
	if not visible.has(p) or not features.has(p) or s.distance(s.party[s.selected].pos,p) > 1: return false
	var feature: Dictionary = features[p]
	if not safe(s): s.message("주변 적을 먼저 처리하세요."); return false
	if feature.kind == "entry": return s.retreat()
	if feature.kind == "exit":
		if s.enemies.any(func(e): return e.hp > 0 and e.group == "F1_G05"):
			s.message("심부 관문의 적이 출구를 지키고 있습니다."); return false
		s.loot += 100; return s.retreat()
	if feature.used: return false
	feature.used = true
	if feature.kind == "camp":
		for actor in s.alive(): actor.hp = mini(actor.max_hp,actor.hp+25); s.stress(actor,-20)
	elif feature.kind == "loot": s.supplies[0] += 1; s.food += 3; s.loot += 15
	else: s.loot += 25; s.light = 100
	s.message(feature.label+" · 사용 완료"); s.act("WAIT",s.party[s.selected].pos); return true

func enemy_turn(s, enemy: Dictionary) -> void:
	var spotted := false
	for ally in s.alive():
		if s.distance(enemy.pos,ally.pos) <= 9 and s.TurnCore.Geometry.sees(enemy.pos,ally.pos,func(p): return s.tile(p).terrain == "wall"): spotted = true
	if spotted: enemy.alert = true
	if not enemy.alert: return
	if s.alive().all(func(a): return s.distance(enemy.pos,a.pos) > 15): enemy.alert = false; return
	var choice: Dictionary = LegacyAI.new(s,enemy).choose(enemy)
	if choice.kind == "MOVE": enemy.pos = choice.cell
	elif choice.kind == "ATTACK":
		var victim: Dictionary = s.at(choice.cell)
		if not victim.is_empty() and s.melee_reach(enemy.pos,victim.pos):
			s.enemy_attack_effect(enemy,[victim.pos]); s.damage(victim,7,enemy.id,"IMPACT")

func follow(s, actor: Dictionary) -> Dictionary:
	var leader: Dictionary = s.party[s.selected]
	if actor.id == leader.id: leader = s.alive()[0]
	if maxi(absi(actor.pos.x-leader.pos.x),absi(actor.pos.y-leader.pos.y)) <= 1: return {"kind":"WAIT","cell":actor.pos,"reason":"대형 유지"}
	var goals: Array = []
	for d in s.DIRECTIONS:
		if s.is_free(leader.pos+d): goals.append(leader.pos+d)
	if not goals.is_empty():
		var route: Dictionary = s.TurnCore.path(SIZE,SIZE,actor.pos,goals,func(a,b): return s.can_step(a,b),func(_p): return 100)
		if route.found and route.path.size() > 1: return {"kind":"MOVE","cell":route.path[1],"reason":"동료 따라가기"}
	return {"kind":"WAIT","cell":actor.pos,"reason":"대기"}
