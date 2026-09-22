extends RefCounted
const Source = preload("res://expedition/legacy/four_zone_floor.gd")
const Registry = preload("res://expedition/legacy/dcss_enemy_registry.gd")
const MonsterAI = preload("res://expedition/monster_ai.gd")
const Objective = preload("res://expedition/expedition_objective.gd")
const SIZE := 100
## Roster health was tuned for a pair; a lone hero meets the same groups at
## reduced health so each fight is decided in a few exchanges.
const SOLO_HP_PERCENT := 45
const SOLO_HP_MIN := 20
const SOLO_HP_MAX := 32
var layout: Dictionary
var visible: Dictionary = {}
var explored: Dictionary = {}
var features: Dictionary = {}
var discoveries: Array = []
var epoch := ""
var discovered_curios := 0
var seen_enemies: Dictionary = {}
## Light tiers (Darkest-Dungeon style): darker pays more and hits harder.
const TIERS := {"BRIGHT":{"min":60,"label":"밝음","loot":100,"drop":50,"bonus":0},
	"DIM":{"min":35,"label":"어둑","loot":125,"drop":65,"bonus":1},
	"DARK":{"min":0,"label":"암흑","loot":150,"drop":80,"bonus":2}}

static func light_tier(light: int) -> String:
	return "BRIGHT" if light >= 60 else "DIM" if light >= 35 else "DARK"

static func tier_label(light: int) -> String:
	return TIERS[light_tier(light)].label

static func loot_percent(light: int) -> int:
	return TIERS[light_tier(light)].loot

static func drop_percent(light: int) -> int:
	return TIERS[light_tier(light)].drop

static func enemy_bonus(light: int) -> int:
	return TIERS[light_tier(light)].bonus

static func point(p: Vector2i) -> Vector2i:
	return p*2+Vector2i(2,2)

func build(s) -> void:
	layout = Source.generate(1,s.seed_value+s.expedition_number*7919)
	epoch = str(s.seed_value)+"/"+str(s.expedition_number)
	visible.clear(); explored.clear(); discoveries.clear(); features.clear(); seen_enemies.clear()
	discovered_curios = 0
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
		enemy.pos = point(row.position); enemy.hp = profile.get("max_health",28)
		if s.party.size() == 1: enemy.hp = clampi(enemy.hp*SOLO_HP_PERCENT/100,SOLO_HP_MIN,SOLO_HP_MAX)
		enemy.max_hp = enemy.hp
		enemy.group = row.group_id; enemy.home = enemy.pos; enemy.alert = false
		MonsterAI.configure(enemy,s.enemies.size())
		enemy.essence_id = ["BOMB","SHOCKWAVE","IRON_HIDE"][s.enemies.size()%3]
		s.enemies.append(enemy)
	for i in range(s.party.size()):
		s.party[i].pos = point(layout.entry_position)+Vector2i(0,i); s.party[i].ap = 1
		s.party[i].reservation = {}
	for i in range(layout.supply_positions.size()):
		var id := "LOCKED_CHEST" if i%2 == 0 else "DIRT_PILE"
		features[point(layout.supply_positions[i])] = {"kind":"curio","curio_id":id,"used":false,"label":s.Curios.content.curios[id].name}
	features[point(layout.entry_position)] = {"kind":"entry","used":false,"label":"귀환 관문"}
	# The legacy relic landmark keeps its old effect as an altar; the mission
	# relic is a separate single object placed after every other feature.
	for row in layout.landmarks:
		var p := point(row.position)
		if features.has(p): continue
		features[p] = {"kind":"camp" if row.kind == "CAMP" else "altar","used":false,"label":row.label}
	if not features.has(point(layout.entry_position)) or features[point(layout.entry_position)].kind != "entry":
		features[point(layout.entry_position)] = {"kind":"entry","used":false,"label":"귀환 관문"}
	Objective.place(s,self,point(layout.entry_position),point(layout.transition_portal_position))
	s.rooms = [{"id":0,"name":"1층 · 갈림길 미궁","kind":"floor","links":[],"tiles":s.tiles,"enemies":s.enemies,"started":true,"cleared":false,"shield":false,"pattern":-1,"used":false,"feature":Vector2i(-1,-1)}]
	s.room = 0; s.phase = "BATTLE"; s.round_number = 1
	observe(s); ambush(s)

static func sight_side(light: int) -> int:
	return ceili(sight_radius(light))*2+1

static func sight_radius(light: int) -> float:
	# Bright light covers even a zoomed-out view; depleted light keeps the old maximum.
	return lerpf(7.0,18.0,clampf(light/60.0,0,1))

static func darkness_strength(light: int) -> float:
	return 1.0-clampf(light/60.0,0,1)

func observer(s) -> Dictionary:
	return s.party[s.selected] if s.party[s.selected].hp > 0 else s.alive()[0] if not s.alive().is_empty() else {}

func observe(s) -> void:
	visible.clear()
	var radius := sight_radius(s.light)
	var before := ceili(radius)
	var side := before*2+1
	var center := observer(s)
	for actor in ([] if center.is_empty() else [center]):
		for y in range(maxi(0,actor.pos.y-before),mini(SIZE,actor.pos.y-before+side)):
			for x in range(maxi(0,actor.pos.x-before),mini(SIZE,actor.pos.x-before+side)):
				var p := Vector2i(x,y)
				if Vector2(actor.pos).distance_to(Vector2(p)) > radius: continue
				if not s.TurnCore.Geometry.sees(actor.pos,p,func(c): return s.tile(c).terrain == "wall",before): continue
				visible[p] = true
				if not explored.has(p):
					explored[p] = true
					var feature: Dictionary = features.get(p,{})
					if feature.get("kind","") == "curio": discovered_curios += 1
					if feature.get("kind","") == "relic": Objective.discover(s)
					discoveries.append({"position":[x,y],"terrain_id":s.tile(p).terrain,"visibility_state":"MEMORY","marker":"EXIT" if feature.get("kind","") == "entry" else "PORTAL" if feature.get("kind","") == "relic" else ""})

## Static markers are cached per epoch by the minimap; a state change rewrites
## the row and starts a new epoch so the next observation rebuilds once.
func clear_marker(p: Vector2i) -> void:
	for row in discoveries:
		if row.position == [p.x,p.y]: row.marker = ""
	epoch += "+"

## In the dark, an enemy sighted for the first time acts immediately.
## Every visible enemy is remembered so the ambush fires once per foe.
func ambush(s) -> void:
	for enemy in s.enemies:
		if enemy.hp <= 0 or not visible.has(enemy.pos) or seen_enemies.has(enemy.id): continue
		seen_enemies[enemy.id] = true
		if light_tier(s.light) != "DARK" or s.phase != "BATTLE": continue
		enemy.alert = true
		s.message("기습! 어둠 속에서 %s이(가) 먼저 움직입니다." % enemy.name)
		MonsterAI.turn(s,enemy)
		s.check_battle_end()
		if s.phase != "BATTLE": return

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
	if feature.kind in ["curio","relic"]: return false # Explicit choice required; never auto-claim.
	if not safe(s): s.message("주변 적을 먼저 처리하세요."); return false
	if feature.kind == "entry": return s.return_home()
	if feature.used: return false
	feature.used = true
	if feature.kind == "camp":
		for actor in s.alive(): actor.hp = mini(actor.max_hp,actor.hp+25); s.stress(actor,-20)
	elif feature.kind == "loot": s.add_stock("supply:0",1); s.add_stock("food",3); s.loot += s.loot_scaled(15)
	else: s.loot += s.loot_scaled(25); s.light = 100
	s.message(feature.label+" · 사용 완료"); s.act("WAIT",s.party[s.selected].pos); return true

func enemy_turn(s, enemy: Dictionary) -> void:
	MonsterAI.turn(s,enemy)

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
