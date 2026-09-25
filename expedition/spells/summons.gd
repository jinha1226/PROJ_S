extends RefCounted
## Summons: where one can stand, which ones a caster has out, how one is made,
## and the boundary tick that takes away the ones whose span has run out.
const Stats = preload("res://expedition/combat/combat_stats.gd")

## Where a summon can stand: a free cell the caster could reach with an arm.
static func summon_cells(s, caster: Dictionary) -> Array:
	var result: Array = []
	for direction in s.DIRECTIONS:
		var cell: Vector2i = caster.pos+direction
		if s.is_free(cell) and s.melee_reach(caster.pos,cell): result.append(cell)
	result.sort_custom(func(a,b): return a.y < b.y or a.y == b.y and a.x < b.x)
	return result

## The creatures this caster currently has standing.
static func summons_of(s, caster: Dictionary) -> Array:
	return s.npcs.filter(func(n): return bool(n.get("summoned",false)) and n.hp > 0 and bool(n.enemy) == bool(caster.get("enemy",false)))

## A summon: an allied dungeon actor that takes its turns through the same npc
## branch every wanderer uses, and fades when its time runs out. It never
## joins, is never placed by the roster and never shows in the run's history.
static func summon(s, caster: Dictionary, cell: Vector2i, kind: String = "hound") -> Dictionary:
	var row: Dictionary = Stats.content.summons.get(kind,{"name":"사냥개","hp":20,"power":7,"speed":100,"duration":300})
	var buffs: Dictionary = caster.get("buffs",{})
	s.serial += 1
	var pet: Dictionary = s.make_actor(2000+s.serial,str(row.name),false)
	pet.merge({"npc":true,"awake":true,"summoned":true,"summon_kind":kind,
		"expires_at":s.time+int(row.duration)+int(buffs.get("summon_time",0)),
		"mode":"","mode_until":0,"hungry":false,"partner":-1,"bond":"","situation":"RESTING",
		"state":"MET","floor_seen":int(s.depth),"joined_floor":0,"activity":"","explains":[],
		"noise_seen":s.npc_clock(),"declined_until":-99,"offered_until":-99},true)
	pet.gear = {"weapon":{},"armour":{},"shield":{},"ring":{}}
	pet.equipped_abilities = []; pet.rules = []
	pet.stance = "CHARGER"
	pet.hp = int(row.hp)*int(buffs.get("summon_hp",100))/100
	pet.max_hp = pet.hp
	pet.power = int(row.power); pet.speed = int(row.speed); pet.stress = 0
	pet.pos = cell; pet.ap = 1; pet.ready_at = s.time+100
	pet.enemy = bool(caster.get("enemy",false))
	pet.summoner = int(caster.get("id",-1))
	if caster.get("statuses",{}).has("summon_power"): pet.statuses["summon_power"] = int(caster.statuses.summon_power)
	s.npcs.append(pet)
	return pet

## A summon lasts the span its spell bought it and then simply is not there.
static func expire(s) -> void:
	for pet in s.npcs.duplicate():
		if bool(pet.get("summoned",false)) and int(pet.get("expires_at",0)) <= s.time:
			pet.hp = 0; s.npcs.erase(pet)
