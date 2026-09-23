extends RefCounted
const Generator = preload("res://expedition/floor_generator.gd")
const MonsterAI = preload("res://expedition/monster_ai.gd")
const Objective = preload("res://expedition/expedition_objective.gd")
const Abilities = preload("res://expedition/abilities.gd")
const THEME_ID := "F1_RUINS"
## Roster health was tuned for a pair; a lone hero meets the same groups at
## reduced health so each fight is decided in a few exchanges.
const SOLO_HP_PERCENT := 45
const SOLO_HP_MIN := 20
const SOLO_HP_MAX := 32
var size := 64
var theme_id := THEME_ID
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

func build(s) -> void:
	var theme: Dictionary = Generator.theme(theme_id)
	apply(s,theme,Generator.generate(theme,s.seed_value+s.expedition_number*7919,int(theme.depth)))

## Consumes a §7 layout: tiles, enemies, features, party spawn, objective.
## Static so a simulator can drive the floor without the generator; the session
## always owns the instance the layout is written into.
static func apply(s, theme: Dictionary, p_layout: Dictionary) -> void:
	var state = s.floor_state
	state.layout = p_layout
	var layout: Dictionary = state.layout
	assert(not layout.is_empty(),"floor generator returned no layout")
	var side: int = layout.size
	state.size = side
	state.epoch = str(s.seed_value)+"/"+str(s.expedition_number)
	state.visible.clear(); state.explored.clear(); state.discoveries.clear(); state.features.clear(); state.seen_enemies.clear()
	state.discovered_curios = 0
	s.BOARD_SIDE = side; s.tiles = []
	for y in range(side):
		for x in range(side):
			var terrain: String = layout.terrain[y*side+x]
			s.tiles.append({"terrain":terrain,"source_terrain":terrain,"fire":0,"wet":70 if terrain == "water" else 0,"variant":posmod(x*13+y*7,3),"palette":0})
	s.enemies = []
	for e in range(layout.encounters.size()):
		var encounter: Dictionary = layout.encounters[e]
		for member in encounter.members:
			mint_enemy(s,member,"F%d_E%02d" % [int(theme.depth),e+1],encounter.tier,encounter.mandatory)
	for p in layout.features: state.features[p] = layout.features[p].duplicate(true)
	for i in range(s.party.size()):
		s.party[i].pos = layout.entry+Vector2i(0,i); s.party[i].ap = 1
		s.party[i].reservation = {}
	if layout.relic != Vector2i(-1,-1): Objective.register(s,layout.relic)
	else: s.objective = {}
	s.rooms = [{"id":0,"name":"1층 · "+str(theme.label),"kind":"floor","links":[],"tiles":s.tiles,"enemies":s.enemies,"started":true,"cleared":false,"shield":false,"pattern":-1,"used":false,"feature":Vector2i(-1,-1)}]
	s.room = 0; s.phase = "BATTLE"; s.round_number = 1
	state.observe(s); state.ambush(s)

## One floor monster from an encounter member: the roster health (scaled down for
## a lone hero), its group, home and role. Appended to `s.enemies` and returned.
static func mint_enemy(s, member: Dictionary, group: String, tier: String, mandatory: bool) -> Dictionary:
	var enemy: Dictionary = s.make_actor(100+s.enemies.size(),member.display_name,true)
	enemy.pos = member.pos; enemy.hp = int(member.max_health)
	if s.party.size() == 1: enemy.hp = clampi(enemy.hp*SOLO_HP_PERCENT/100,SOLO_HP_MIN,SOLO_HP_MAX)
	enemy.max_hp = enemy.hp
	enemy.group = group; enemy.home = enemy.pos; enemy.alert = false
	enemy.species_id = member.species_id; enemy.tier = tier; enemy.mandatory = mandatory
	MonsterAI.configure(enemy,member.role)
	enemy.part_id = Abilities.species_part(member.species_id)
	s.enemies.append(enemy)
	return enemy

static func sight_side(light: int) -> int:
	return ceili(sight_radius(light))*2+1

static func sight_radius(light: int) -> float:
	# Light changes sight within a bounded four-to-six tile radius.
	return lerpf(4.0,6.0,clampf(light/60.0,0,1))

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
		for y in range(maxi(0,actor.pos.y-before),mini(size,actor.pos.y-before+side)):
			for x in range(maxi(0,actor.pos.x-before),mini(size,actor.pos.x-before+side)):
				var p := Vector2i(x,y)
				if Vector2(actor.pos).distance_to(Vector2(p)) > radius: continue
				# Adjacent tiles stay readable so legal diagonal steps can be tapped at corners.
				var adjacent: bool = maxi(absi(p.x-actor.pos.x),absi(p.y-actor.pos.y)) <= 1
				if not adjacent and not s.TurnCore.Geometry.sees(actor.pos,p,func(c): return s.tile(c).terrain == "wall",before): continue
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
	return {"width":size,"height":size,"epoch":epoch,"cells":discoveries,"discovery_rows":discoveries,"static_count":discoveries.size(),"visible":visible.keys().map(func(p): return [p.x,p.y]),"markers":markers}

func threats(s) -> Array:
	return s.enemies.filter(func(e): return e.hp > 0 and visible.has(e.pos))

func safe(s) -> bool:
	return threats(s).is_empty()

func interact(s, p: Vector2i) -> bool:
	if s.phase != "BATTLE" or s.party[s.selected].hp <= 0 or s.party[s.selected].ap <= 0: return false
	if not visible.has(p) or not features.has(p) or s.distance(s.party[s.selected].pos,p) > 1: return false
	var feature: Dictionary = features[p]
	if feature.kind in ["curio","relic"]: return false # Explicit choice required; never auto-claim.
	if not safe(s): s.message("주변에 적 있음"); return false
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

## Everyone trails the leader in a single column, one cell per rank in the
## marching order. The leader itself waits; a blocked slot falls back to any
## free cell adjacent to the leader.
func follow(s, actor: Dictionary) -> Dictionary:
	var leader: Dictionary = s.leader()
	if actor.id == leader.id: return {"kind":"WAIT","cell":actor.pos,"reason":"대형 유지"}
	var order: Array = s.formation.filter(func(i): return i != leader.id)
	var rank: int = order.find(actor.id)+1
	var destination: Vector2i = leader.pos+Vector2i(0,rank)
	if actor.pos == destination: return {"kind":"WAIT","cell":actor.pos,"reason":"대형 유지"}
	if s.is_free(destination):
		var route: Dictionary = s.TurnCore.path(size,size,actor.pos,[destination],func(a,b): return s.can_step(a,b),func(_p): return 100)
		if route.found and route.path.size() > 1: return {"kind":"MOVE","cell":route.path[1],"reason":"대형 이동"}
	if maxi(absi(actor.pos.x-leader.pos.x),absi(actor.pos.y-leader.pos.y)) <= 1: return {"kind":"WAIT","cell":actor.pos,"reason":"대형 유지"}
	var goals: Array = []
	for d in s.DIRECTIONS:
		if s.is_free(leader.pos+d): goals.append(leader.pos+d)
	if not goals.is_empty():
		var route: Dictionary = s.TurnCore.path(size,size,actor.pos,goals,func(a,b): return s.can_step(a,b),func(_p): return 100)
		if route.found and route.path.size() > 1: return {"kind":"MOVE","cell":route.path[1],"reason":"동료 따라가기"}
	return {"kind":"WAIT","cell":actor.pos,"reason":"대기"}
