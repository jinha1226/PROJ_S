extends RefCounted
## Adapted from legacy monster_ability_catalog, corpse_loot_system and
## GrowthBuildState.commit_mutation_swap: catalog, once-only loot, learned/loadout split.
const DROP_PERCENT := 50
const DEFINITIONS = {
	"SHOCKWAVE":{"name":"수렁 충격파","item":"수렁의 핵","description":"범위 2 · 피해 16 · 아군 피해 · 재사용 3턴","target":"SELF","range":0,"radius":2,"damage":16,"cooldown":3,"effect":"DAMAGE","axis":"MAGIC","rule_when":"ALWAYS","short":"충격파","shape":"CIRCLE","self_hit":false,"drop":true,"icon":4},
	"BOMB":{"name":"폭탄 투척","item":"암살자의 화약낭","description":"사거리 4 · 범위 1 · 피해 16 · 아군 피해 · 재사용 3턴","target":"ENEMY","range":4,"radius":1,"damage":16,"cooldown":3,"effect":"DAMAGE","axis":"RANGED","rule_when":"ALWAYS","short":"폭탄","shape":"SQUARE","self_hit":true,"drop":true,"icon":3},
	"IRON_HIDE":{"name":"철갑 방어","item":"거인의 철갑핵","description":"받는 피해 -75% · 1턴 · 재사용 3턴","target":"SELF","range":0,"radius":0,"damage":0,"cooldown":3,"effect":"SHIELD","axis":"","rule_when":"TELEGRAPHED","short":"철갑","shape":"SQUARE","self_hit":false,"drop":true,"icon":5},
	"HEAVY_STRIKE":{"name":"시험 강타","item":"시험용 강타 문양","description":"인접 대상 · 피해 28 · 재사용 3턴","target":"ENEMY","range":1,"radius":0,"damage":28,"cooldown":3,"effect":"DAMAGE","axis":"MELEE","rule_when":"ALWAYS","short":"강타","shape":"SQUARE","self_hit":false,"drop":false,"icon":5},
	"THROWING_KNIFE":{"name":"시험 투척","item":"시험용 투척 문양","description":"사거리 4 · 피해 10 · 재사용 1턴","target":"ENEMY","range":4,"radius":0,"damage":10,"cooldown":1,"effect":"DAMAGE","axis":"RANGED","rule_when":"ALWAYS","short":"투척","shape":"SQUARE","self_hit":false,"drop":false,"icon":5},
	"FIELD_DRESSING":{"name":"시험 응급처치","item":"시험용 처치 문양","description":"자신 체력 +15 · 재사용 4턴","target":"SELF","range":0,"radius":0,"damage":0,"heal":15,"cooldown":4,"effect":"HEAL","axis":"","rule_when":"HP","short":"응급","shape":"SQUARE","self_hit":false,"drop":false,"icon":5},
	"LUNGE":{"name":"시험 돌진","item":"시험용 돌진 문양","description":"사거리 3 · 적 옆으로 이동 후 피해 12 · 재사용 3턴","target":"ENEMY","range":3,"radius":0,"damage":12,"cooldown":3,"effect":"LUNGE","axis":"MELEE","rule_when":"ALWAYS","short":"돌진","shape":"SQUARE","self_hit":false,"drop":false,"icon":5}}
const STARTERS = ["PUSH","GUARD"]
## Basic actions, not catalog abilities: the only remaining literal id list.
const BASIC_BADGES := {"PUSH":"밀치기","GUARD":"방어","ATTACK":"공격","MOVE":"이동","WAIT":"대기"}

## Ability ids that drop as essences, in DEFINITIONS insertion order.
static func droppable() -> Array:
	var result: Array = []
	for id in DEFINITIONS:
		if DEFINITIONS[id].drop: result.append(id)
	return result

## Short badge text for any action kind, catalog ability or basic action.
static func badge(kind: String) -> String:
	return str(DEFINITIONS[kind].short) if DEFINITIONS.has(kind) else str(BASIC_BADGES.get(kind,kind))

static func default_rule(id: String) -> Dictionary:
	var def: Dictionary = DEFINITIONS[id]
	return preload("res://expedition/tactic_rules.gd").make_rule(id,"SELF" if def.target == "SELF" else "NEAREST",def.rule_when)

## Nearest free cell adjacent to the target that the actor can reach within range.
static func lunge_cell(s, actor: Dictionary, target: Vector2i) -> Vector2i:
	var def: Dictionary = DEFINITIONS.LUNGE
	var best := Vector2i(-1,-1)
	var best_len := 1 << 30
	for d in s.DIRECTIONS:
		var cell: Vector2i = target+d
		if not s.inside(cell) or not s.is_free(cell) or not s.melee_reach(cell,target): continue
		var route: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,actor.pos,[cell],func(a,b): return s.can_step(a,b),func(_p): return 100)
		if not route.found: continue
		var steps: int = route.path.size()-1
		if steps > int(def.range): continue
		if steps < best_len or (steps == best_len and str(cell) < str(best)): best = cell; best_len = steps
	return best

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
			var in_range: bool = s.distance(center,cell) <= def.radius if def.shape == "CIRCLE" else maxi(absi(center.x-x),absi(center.y-y)) <= def.radius
			if in_range and s.tile(cell).terrain != "wall" and s.TurnCore.Geometry.sees(center,cell,func(p): return s.tile(p).terrain == "wall"): result.append(cell)
	return result

static func legal(s, actor: Dictionary, id: String, target: Vector2i) -> bool:
	if not DEFINITIONS.has(id) or id not in actor.equipped_abilities or actor.cooldowns.get(id,0) > 0: return false
	if s.phase != "BATTLE" or actor.hp <= 0 or actor.ap <= 0 or not s.inside(target): return false
	var def: Dictionary = DEFINITIONS[id]
	if def.target == "SELF":
		if def.effect == "HEAL" and actor.hp >= actor.max_hp: return false
		return target == actor.pos
	var victim: Dictionary = s.at(target)
	if victim.is_empty() or not victim.enemy: return false
	# distance() is Manhattan, so a range-1 skill would miss the diagonals a
	# basic attack reaches; "adjacent" means melee_reach everywhere else.
	var in_range: bool = s.melee_reach(actor.pos,target) if int(def.range) == 1 else s.distance(actor.pos,target) <= int(def.range)
	if not in_range or not s.TurnCore.Geometry.sees(actor.pos,target,func(p): return s.tile(p).terrain == "wall"): return false
	if def.effect == "LUNGE": return lunge_cell(s,actor,target) != Vector2i(-1,-1)
	return true

static func execute(s, actor: Dictionary, id: String, target: Vector2i) -> bool:
	if not legal(s,actor,id,target): return false
	var def: Dictionary = DEFINITIONS[id]
	match def.effect:
		"SHIELD": actor.iron_guard = true
		"HEAL":
			actor.hp = mini(int(actor.max_hp),int(actor.hp)+int(def.heal))
			s.Body.heal(actor)
		"LUNGE":
			var cell := lunge_cell(s,actor,target)
			actor.pos = cell
			var victim: Dictionary = s.at(target)
			s.effects.append({"kind":"ENEMY_ATTACK","from":actor.pos,"cell":target,"cells":[target],"area":false,"amount":0,"form":"SLASH"})
			s.damage(victim,s.Growth.power(actor,"MELEE",int(def.damage)),actor.id,"SLASH")
		"DAMAGE":
			var affected := cells(s,actor,id,target)
			var power: int = s.Growth.power(actor,def.axis,int(def.damage))
			s.effects.append({"kind":"ENEMY_ATTACK","from":actor.pos,"cell":target,"cells":affected,"area":true,"amount":0,"form":"IMPACT"})
			for victim in s.party+s.enemies:
				if victim.hp > 0 and victim.id != actor.id and victim.pos in affected: s.damage(victim,power,actor.id,"IMPACT")
			# Bombs can also hit the caster; self-centered shockwaves cannot.
			if def.self_hit and actor.pos in affected: s.damage(actor,power,actor.id,"IMPACT")
	actor.cooldowns[id] = int(def.cooldown)+1
	s.message(actor.name+" · "+def.name)
	return true
