extends RefCounted
## Adapted from legacy monster_ability_catalog, corpse_loot_system and
## GrowthBuildState.commit_mutation_swap: catalog, once-only loot, learned/loadout split.
const DROP_PERCENT := 50
const DEFINITIONS = {
	"SHOCKWAVE":{"name":"수렁 충격파","item":"수렁의 핵","description":"자신 주변 2칸에 피해 16. 동료도 맞습니다. 재사용 3턴.","target":"SELF","range":0,"radius":2,"damage":16,"cooldown":3},
	"BOMB":{"name":"폭탄 투척","item":"암살자의 화약낭","description":"사거리 4. 대상 주변 1칸에 피해 16. 아군도 맞습니다. 재사용 3턴.","target":"ENEMY","range":4,"radius":1,"damage":16,"cooldown":3},
	"IRON_HIDE":{"name":"철갑 방어","item":"거인의 철갑핵","description":"이번 적 차례에 받는 피해를 75% 줄입니다. 재사용 3턴.","target":"SELF","range":0,"radius":0,"damage":0,"cooldown":3}}
const STARTERS = ["PUSH","GUARD"]

static func equip(actor: Dictionary, slot: int, id: String) -> bool:
	if slot < 0 or slot >= 2 or id not in actor.learned_abilities or id in actor.equipped_abilities: return false
	actor.equipped_abilities[slot] = id
	actor.reservation = {}
	return true

static func cells(s, actor: Dictionary, id: String, target: Vector2i) -> Array:
	var result: Array = []
	if not DEFINITIONS.has(id): return result
	var def: Dictionary = DEFINITIONS[id]
	var center: Vector2i = actor.pos if def.target == "SELF" else target
	for y in range(maxi(0,center.y-def.radius),mini(s.BOARD_SIDE,center.y+def.radius+1)):
		for x in range(maxi(0,center.x-def.radius),mini(s.BOARD_SIDE,center.x+def.radius+1)):
			var cell := Vector2i(x,y)
			var in_range: bool = s.distance(center,cell) <= def.radius if id == "SHOCKWAVE" else maxi(absi(center.x-x),absi(center.y-y)) <= def.radius
			if in_range and s.tile(cell).terrain != "wall" and s.TurnCore.Geometry.sees(center,cell,func(p): return s.tile(p).terrain == "wall"): result.append(cell)
	return result

static func legal(s, actor: Dictionary, id: String, target: Vector2i) -> bool:
	if not DEFINITIONS.has(id) or id not in actor.equipped_abilities or actor.cooldowns.get(id,0) > 0: return false
	if s.phase != "BATTLE" or actor.hp <= 0 or actor.ap <= 0 or not s.inside(target): return false
	var def: Dictionary = DEFINITIONS[id]
	if def.target == "SELF": return target == actor.pos
	var victim: Dictionary = s.at(target)
	return not victim.is_empty() and victim.enemy and s.distance(actor.pos,target) <= def.range and s.TurnCore.Geometry.sees(actor.pos,target,func(p): return s.tile(p).terrain == "wall")

static func execute(s, actor: Dictionary, id: String, target: Vector2i) -> bool:
	if not legal(s,actor,id,target): return false
	var def: Dictionary = DEFINITIONS[id]
	if id == "IRON_HIDE": actor.iron_guard = true
	else:
		var affected := cells(s,actor,id,target)
		var power: int = s.Growth.power(actor,"RANGED" if id == "BOMB" else "MAGIC",def.damage)
		s.effects.append({"kind":"ENEMY_ATTACK","from":actor.pos,"cell":target,"cells":affected,"area":true,"amount":0,"form":"IMPACT"})
		for victim in s.party+s.enemies:
			if victim.hp > 0 and victim.id != actor.id and victim.pos in affected: s.damage(victim,power,actor.id,"IMPACT")
		# Bombs can also hit the caster; self-centered shockwaves cannot.
		if id == "BOMB" and actor.pos in affected: s.damage(actor,power,actor.id,"IMPACT")
	actor.cooldowns[id] = int(def.cooldown)+1
	s.message(actor.name+" · "+def.name)
	return true
