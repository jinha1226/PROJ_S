extends RefCounted
## What every boss shares: its reach, whom it hunts, the attack it announces
## and keeps on the floor until it lands, a line said over its head, and the
## zone numbers its health and blows are read from (spec §3.2, §7).
const Abilities = preload("res://expedition/items/abilities.gd")
const Zones = preload("res://expedition/level/zones.gd")
const ZONE_BASE_HP := [30,70,110,160]
const ZONE_BASE_ATTACK := [8,14,20,26]
const HP_FACTOR := 6

static func zone_index(depth: int) -> int:
	return clampi(int(Zones.zone_of(depth))-1,0,ZONE_BASE_HP.size()-1)

static func boss_hp(depth: int) -> int:
	return int(ZONE_BASE_HP[zone_index(depth)])*HP_FACTOR

static func boss_attack(depth: int) -> int:
	return int(ZONE_BASE_ATTACK[zone_index(depth)])

## Eight-way distance: what "within N cells" means on this board. The
## session's own `distance` is Manhattan and is not used for boss reach.
static func reach(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x-b.x),absi(a.y-b.y))

## Whom the boss is coming for. A dominated boss comes for its own kind.
static func victims(s, boss: Dictionary) -> Array:
	if s.dominated(boss): return s.hostiles_of(boss)
	return s.alive()

static func target(s, boss: Dictionary) -> Dictionary:
	var foes: Array = victims(s,boss)
	if foes.is_empty(): return {}
	foes.sort_custom(func(a,b):
		var da: int = reach(a.pos,boss.pos)
		var db: int = reach(b.pos,boss.pos)
		return da < db if da != db else int(a.id) < int(b.id))
	return foes[0]

## Every open cell within `radius` of `center`, row by row.
static func cells_within(s, center: Vector2i, radius: int) -> Array:
	var result: Array = []
	for y in range(center.y-radius,center.y+radius+1):
		for x in range(center.x-radius,center.x+radius+1):
			var cell := Vector2i(x,y)
			if s.inside(cell) and s.tile(cell).terrain != "wall": result.append(cell)
	return result

## An attack announced now that lands after `fuse` of the boss's own turns.
static func announce(boss: Dictionary, cells: Array, damage: int, kind: String, fuse: int) -> void:
	boss.telegraph = {"cells":cells.duplicate(),"damage":damage,"kind":kind,"fuse":fuse}
	boss.charging = true

static func clear(boss: Dictionary) -> void:
	boss.telegraph = {}
	boss.charging = false

## The announced cells go back on the board each time the intents are rebuilt.
static func emit(s, boss: Dictionary) -> void:
	var t: Dictionary = boss.get("telegraph",{})
	if t.is_empty(): return
	for cell in t.cells:
		s.intents.append({"id":int(boss.id),"cell":cell,"damage":int(t.damage),"kind":str(t.kind),"resolve_at":int(s.time)+int(t.fuse)*100})

## One boss turn spent on its announced attack: count down and land it at
## zero. Returns the landed announcement, or {} while it is still counting.
static func count_down(s, boss: Dictionary) -> Dictionary:
	var t: Dictionary = boss.get("telegraph",{})
	if t.is_empty(): return {}
	t.fuse = int(t.fuse)-1
	if int(t.fuse) > 0: return {}
	clear(boss)
	s.enemy_attack_effect(boss,t.cells,true)
	if int(t.damage) > 0:
		for foe in victims(s,boss):
			if foe.pos in t.cells: s.damage(foe,int(t.damage),int(boss.id),"IMPACT")
	return t

static func swing(s, boss: Dictionary, foe: Dictionary) -> void:
	var amount: int = Abilities.scaled(boss,int(boss.get("base_attack",8)))
	s.enemy_attack_effect(boss,[foe.pos])
	if s.manual_mode:
		boss.power = amount; s.CombatRules.attack(s,boss,foe)
	else: s.damage(foe,amount,int(boss.id),"IMPACT")

## One step along the route to any free cell beside `foe`.
static func step_toward(s, boss: Dictionary, foe: Dictionary) -> void:
	var goals: Array = []
	for direction in s.DIRECTIONS:
		var cell: Vector2i = foe.pos+direction
		if s.is_free(cell) and s.melee_reach(cell,foe.pos): goals.append(cell)
	if goals.is_empty(): return
	var route: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,boss.pos,goals,func(a,b): return s.can_step(a,b),func(_p): return 100)
	if route.found and route.path.size() > 1: boss.pos = route.path[1]

## A line over the speaker's head, and in the log.
static func say(s, speaker: Dictionary, text: String) -> void:
	s.message("%s: \"%s\"" % [speaker.name,text])
	s.effects.append({"kind":"SPEECH","actor":int(speaker.id),"cell":speaker.pos,"text":text})
