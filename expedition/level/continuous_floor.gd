extends RefCounted
const Generator = preload("res://expedition/level/floor_generator.gd")
const MonsterAI = preload("res://expedition/actors/monster_ai.gd")
const BossAI = preload("res://expedition/actors/boss_ai.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Variants = preload("res://expedition/level/variants.gd")
const Zones = preload("res://expedition/level/zones.gd")
const Hazards = preload("res://expedition/level/hazards.gd")
const Families = preload("res://expedition/combat/families.gd")
const Bestiary = preload("res://expedition/progression/bestiary.gd")
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
var element := ""
const SIGHT_RADIUS := 6.0

func sight_radius() -> float:
	return SIGHT_RADIUS

static func sight_side() -> int:
	return ceili(SIGHT_RADIUS)*2+1

static func theme_for(depth: int) -> Dictionary:
	var zone: int = Zones.zone_of(depth)
	var theme: Dictionary = Generator.theme(Zones.theme_id(depth))
	if depth >= 3:
		var scale: float = 1.0+0.25*(depth-2)
		theme.monsters.max_members = mini(4,2+int(depth/3))
		var cap: int = strongest_pack(depth,int(theme.monsters.max_members))*4/5
		for key in theme.monsters.budget: theme.monsters.budget[key] = mini(roundi(theme.monsters.budget[key]*scale),cap)
	theme.depth = depth
	theme.zone = zone
	theme.boss = Zones.is_boss_floor(depth)
	if theme.boss:
		theme.boss_template = Zones.boss_template(zone)
		theme.templates.required = ["entry_camp",theme.boss_template,"sealed_treasury"]
	return theme

## Threat total of the strongest pack the builder could legally assemble at
## `depth`: strongest rows first, at most two of one species/role, `max_members` units.
static func strongest_pack(depth: int, max_members: int) -> int:
	var rows: Array = Generator.Encounters.candidates(depth,999)
	rows.sort_custom(func(a,b): return int(a.threat) > int(b.threat))
	var total := 0
	var taken := 0
	for row in rows:
		for role in row.roles:
			var copies: int = mini(2,max_members-taken)
			if copies <= 0: return total
			total += int(row.threat)*copies; taken += copies
	return total

func build(s) -> void:
	var theme: Dictionary = theme_for(s.depth)
	apply(s,theme,Generator.generate(theme,s.seed_value+s.depth*7919,s.depth))

## Consumes a §7 layout: tiles, enemies, features, and party spawn.
## Static so a simulator can drive the floor without the generator; the session
## always owns the instance the layout is written into.
static func apply(s, theme: Dictionary, p_layout: Dictionary) -> void:
	var state = s.floor_state
	state.layout = p_layout
	state.theme_id = str(theme.id)
	var layout: Dictionary = state.layout
	assert(not layout.is_empty(),"floor generator returned no layout")
	var side: int = layout.size
	state.size = side
	state.epoch = str(s.seed_value)+"/"+str(s.depth)
	state.visible.clear(); state.explored.clear(); state.discoveries.clear(); state.features.clear(); state.seen_enemies.clear()
	state.discovered_curios = 0
	s.BOARD_SIDE = side; s.tiles = []
	for y in range(side):
		for x in range(side):
			var terrain: String = layout.terrain[y*side+x]
			var start: Dictionary = Hazards.initial(terrain)
			s.tiles.append({"terrain":terrain,"source_terrain":terrain,"pillar":layout.get("pillars",{}).has(Vector2i(x,y)),"fire":int(start.fire),"wet":int(start.wet),"variant":posmod(x*13+y*7,3),"palette":0})
	for p in layout.get("hazards",{}): s.tile(p).merge((layout.hazards[p] as Dictionary).duplicate(true),true)
	s.enemies = []
	for e in range(layout.encounters.size()):
		var encounter: Dictionary = layout.encounters[e]
		for member in encounter.members:
			mint_enemy(s,member,"F%d_E%02d" % [int(theme.depth),e+1],encounter.tier,encounter.mandatory)
	state.element = Variants.assign(s,s.enemies)
	if not state.element.is_empty(): s.message("이 층의 기운 · "+str(Abilities.ELEMENT_NAMES[state.element]))
	for p in layout.features: state.features[p] = layout.features[p].duplicate(true)
	for i in range(s.party.size()):
		s.party[i].pos = layout.entry+Vector2i(0,i); s.party[i].ap = 1
		s.party[i].reservation = {}
	if theme.get("boss",false): BossAI.spawn(s,layout,int(theme.depth))
	s.phase = "BATTLE" if s.simulation_arena else "EXPLORE"; s.round_number = 1
	state.observe(s)

## One floor monster from an encounter member: the roster health (scaled down for
## a lone hero), its group, home and role. Appended to `s.enemies` and returned.
static func mint_enemy(s, member: Dictionary, group: String, tier: String, mandatory: bool) -> Dictionary:
	var enemy: Dictionary = s.make_actor(100+s.enemies.size(),member.display_name,true)
	var stats: Dictionary = Bestiary.monster_stats(str(member.species_id),int(s.depth))
	enemy.pos = member.pos
	enemy.hp = int(stats.hp)*Bestiary.party_percent(s.party.size())/100
	enemy.max_hp = enemy.hp
	enemy.attack_percent = int(stats.attack_percent)
	enemy.basic_attack = int(stats.attack)
	enemy.group = group; enemy.home = enemy.pos; enemy.alert = false
	enemy.species_id = member.species_id; enemy.tier = tier; enemy.mandatory = mandatory
	var species: Dictionary = s.Encounters.species(str(member.species_id))
	enemy.speed = int(species.get("speed",100))
	enemy.ac = int(stats.ac); enemy.ev = int(stats.ev); enemy.sh = maxi(int(stats.sh),int(species.get("sh",0)))
	enemy.res = species.get("res",{}).duplicate(true)
	enemy.ready_at = int(s.time)+int(enemy.speed)
	MonsterAI.configure(enemy,member.role)
	enemy.power = int(MonsterAI.ROLES[str(member.role)].damage)
	enemy.part_id = Abilities.species_part(member.species_id)
	s.enemies.append(enemy)
	return enemy

func observer(s) -> Dictionary:
	return s.party[s.selected] if s.party[s.selected].hp > 0 else s.alive()[0] if not s.alive().is_empty() else {}

func observe(s) -> void:
	visible.clear()
	var center := observer(s)
	var radius: float = Hazards.sight_radius(s,center,SIGHT_RADIUS+float(Families.vision_bonus(center)))
	var before := ceili(radius)
	var side := before*2+1
	for actor in ([] if center.is_empty() else [center]):
		for y in range(maxi(0,actor.pos.y-before),mini(size,actor.pos.y-before+side)):
			for x in range(maxi(0,actor.pos.x-before),mini(size,actor.pos.x-before+side)):
				var p := Vector2i(x,y)
				if Vector2(actor.pos).distance_to(Vector2(p)) > radius: continue
				# Adjacent tiles stay readable so legal diagonal steps can be tapped at corners.
				var adjacent: bool = maxi(absi(p.x-actor.pos.x),absi(p.y-actor.pos.y)) <= 1
				if not adjacent and not s.TurnCore.Geometry.sees(actor.pos,p,
					func(c): return (s.tile(c).terrain == "wall" and not bool(s.tile(c).get("pillar",false))) or int(s.tile(c).get("steam_until",0)) > int(s.time),before): continue
				visible[p] = true
				if not explored.has(p):
					explored[p] = true
					var feature: Dictionary = features.get(p,{})
					if feature.get("kind","") == "curio": discovered_curios += 1
					discoveries.append({"position":[x,y],"terrain_id":s.tile(p).terrain,"visibility_state":"MEMORY","marker":"EXIT" if feature.get("kind","") == "entry" else "STAIRS" if feature.get("kind","") == "stairs" else ""})
		# Show the outline of the visible room without revealing actors beyond it.
		for floor_cell in visible.keys():
			if s.tile(floor_cell).terrain == "wall": continue
			for direction in s.DIRECTIONS:
				var edge: Vector2i = floor_cell+direction
				if not s.inside(edge) or maxi(absi(edge.x-actor.pos.x),absi(edge.y-actor.pos.y)) > before: continue
				if s.tile(edge).terrain != "wall": continue
				visible[edge] = true
				if not explored.has(edge):
					explored[edge] = true
					discoveries.append({"position":[edge.x,edge.y],"terrain_id":"wall","visibility_state":"MEMORY","marker":""})
	if not s.simulation_arena and s.phase in ["EXPLORE","BATTLE"]:
		var was: String = s.phase
		s.phase = "EXPLORE" if safe(s) else "BATTLE"
		if was == "EXPLORE" and s.phase == "BATTLE": Families.battle_start(s)

## Static markers are cached per epoch by the minimap; a state change rewrites
## the row and starts a new epoch so the next observation rebuilds once.
func clear_marker(p: Vector2i) -> void:
	for row in discoveries:
		if row.position == [p.x,p.y]: row.marker = ""
	epoch += "+"

func observation(s) -> Dictionary:
	var markers: Array = []
	for actor in s.party+s.enemies:
		if actor.hp > 0 and visible.has(actor.pos): markers.append({"position":[actor.pos.x,actor.pos.y],"marker":"ENEMY" if actor.enemy else "HERO"})
	return {"width":size,"height":size,"epoch":epoch,"cells":discoveries,"discovery_rows":discoveries,"static_count":discoveries.size(),"visible":visible.keys().map(func(p): return [p.x,p.y]),"markers":markers}

## The fight the party is in: the foes it can see, plus the ones an awake npc
## has in its own sight — an npc's battle is a battle on this floor.
func threats(s) -> Array:
	var seen: int = MonsterAI.sight(s)
	# Hoisted: the watchers are the same for every enemy this call weighs.
	var watchers: Array = s.npcs.filter(func(n): return n.awake and n.hp > 0)
	# A dominated monster fights beside the party: it threatens nobody.
	return s.enemies.filter(func(e): return e.hp > 0 and not s.dominated(e) and (visible.has(e.pos) or watchers.any(func(n): return MonsterAI.line(s,n.pos,e.pos,seen)))) + s.npcs.filter(func(n): return n.hp > 0 and n.get("hostile",false) and visible.has(n.pos))

## Only what the party itself sees: the auto-run's stop events are about the
## party's eyes, not an npc's.
func party_threats(s) -> Array:
	return s.enemies.filter(func(e): return e.hp > 0 and not s.dominated(e) and visible.has(e.pos)) + s.npcs.filter(func(n): return n.hp > 0 and n.get("hostile",false) and visible.has(n.pos))

## Whether the party may treat this cell as quiet: its own eyes decide, not a
## fight an npc picked out of its sight.
func safe(s) -> bool:
	return party_threats(s).is_empty()

func interact(s, p: Vector2i) -> bool:
	if s.phase != "EXPLORE" or s.party[s.selected].hp <= 0 or s.party[s.selected].ap <= 0: return false
	if not visible.has(p) or not features.has(p) or s.distance(s.party[s.selected].pos,p) > 1: return false
	var feature: Dictionary = features[p]
	if feature.kind in ["curio","stairs","lever","channel","binding","entry","camp","item"]: return false # Items are picked up by stepping onto them.
	if not safe(s): s.message("주변에 적 있음"); return false
	if feature.used: return false
	feature.used = true
	if feature.kind == "loot": s.food += 2; s.score += 5
	else: s.score += 10
	s.message(feature.label+" · 사용 완료"); s.act("WAIT",s.party[s.selected].pos); return true

func enemy_turn(s, enemy: Dictionary) -> void:
	MonsterAI.turn(s,enemy)

## Each member trails the preceding rank. This keeps the third member moving
## through a one-cell corridor even when the second occupies the only cell
## beside the leader.
func follow(s, actor: Dictionary) -> Dictionary:
	var leader: Dictionary = s.leader()
	if actor.id == leader.id: return {"kind":"WAIT","cell":actor.pos,"reason":"대형 유지"}
	var order: Array = s.formation.filter(func(i): return i < s.party.size() and s.party[i].hp > 0)
	var rank: int = order.find(s.party.find(actor))
	if rank < 1: return {"kind":"WAIT","cell":actor.pos,"reason":"대형 유지"}
	var anchor: Dictionary = s.party[order[rank-1]]
	if maxi(absi(actor.pos.x-anchor.pos.x),absi(actor.pos.y-anchor.pos.y)) <= 1 and maxi(absi(actor.pos.x-leader.pos.x),absi(actor.pos.y-leader.pos.y)) > 2:
		var leader_goals: Array = []
		for d in s.DIRECTIONS:
			if s.is_free(leader.pos+d): leader_goals.append(leader.pos+d)
		if not leader_goals.is_empty():
			var catch_up: Dictionary = s.TurnCore.path(size,size,actor.pos,leader_goals,func(a,b): return s.can_step(a,b),func(_p): return 100)
			if catch_up.found and catch_up.path.size() > 1: return {"kind":"MOVE","cell":catch_up.path[1],"reason":"동료 따라가기"}
	var destination: Vector2i = anchor.pos+Vector2i.DOWN
	if actor.pos == destination: return {"kind":"WAIT","cell":actor.pos,"reason":"대형 유지"}
	if s.is_free(destination):
		var route: Dictionary = s.TurnCore.path(size,size,actor.pos,[destination],func(a,b): return s.can_step(a,b),func(_p): return 100)
		if route.found and route.path.size() > 1: return {"kind":"MOVE","cell":route.path[1],"reason":"대형 이동"}
	if maxi(absi(actor.pos.x-anchor.pos.x),absi(actor.pos.y-anchor.pos.y)) <= 1: return {"kind":"WAIT","cell":actor.pos,"reason":"대형 유지"}
	var goals: Array = []
	for d in s.DIRECTIONS:
		if s.is_free(anchor.pos+d): goals.append(anchor.pos+d)
	if not goals.is_empty():
		var route: Dictionary = s.TurnCore.path(size,size,actor.pos,goals,func(a,b): return s.can_step(a,b),func(_p): return 100)
		if route.found and route.path.size() > 1: return {"kind":"MOVE","cell":route.path[1],"reason":"동료 따라가기"}
	return {"kind":"WAIT","cell":actor.pos,"reason":"대기"}
