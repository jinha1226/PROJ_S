extends RefCounted
const Stats = preload("res://expedition/combat_stats.gd")
const Rules = preload("res://expedition/combat_rules.gd")
const Mastery = preload("res://expedition/mastery.gd")
const Effects = preload("res://expedition/mastery_effects.gd")
const Kernel = preload("res://sim/combat_kernel.gd")
const IMPLEMENTED := ["bolt", "blast", "blink", "confuse", "mend", "cone", "cloud", "hound"]

static func definition(id: String) -> Dictionary:
	return Stats.content.spells.get(id, {}) if id in IMPLEMENTED else {}

static func failure(s, caster: Dictionary, id: String) -> int:
	var spell: Dictionary = definition(id)
	if spell.is_empty(): return 100
	var school: String = str(spell.school)
	return clampi(8 + int(spell.level) * 9 + int(Stats.stats(s,caster).enc) * 5 - Mastery.rank(caster,school) * 5 - int(Stats.species(caster).int), 0, 85)

static func cells(s, caster: Dictionary, id: String, target: Vector2i) -> Array:
	if id == "cone": return cone_cells(s,caster,target)
	if id == "hound": return []
	if id != "blast" and id != "cloud" and not (id == "bolt" and Mastery.rank(caster,"fire") >= 5): return [target]
	var result: Array = []
	for y in range(target.y-1,target.y+2):
		for x in range(target.x-1,target.x+2):
			var cell := Vector2i(x,y)
			if s.inside(cell) and maxi(absi(x-target.x),absi(y-target.y)) <= 1: result.append(cell)
	return result

## The frost fan: the aimed cell and the two beside it, square across the line
## the caster looks along.
static func cone_cells(s, caster: Dictionary, target: Vector2i) -> Array:
	var step := Vector2i(signi(target.x-caster.pos.x),signi(target.y-caster.pos.y))
	if step == Vector2i.ZERO: step = Vector2i(1,0)
	var side := Vector2i(-step.y,step.x)
	var result: Array = []
	for cell in [target,target+side,target-side]:
		if s.inside(cell) and cell not in result: result.append(cell)
	return result

## Where a summon can stand: a free cell the caster could reach with an arm.
static func summon_cells(s, caster: Dictionary) -> Array:
	var result: Array = []
	for direction in s.DIRECTIONS:
		var cell: Vector2i = caster.pos+direction
		if s.is_free(cell) and s.melee_reach(caster.pos,cell): result.append(cell)
	result.sort_custom(func(a,b): return a.y < b.y or a.y == b.y and a.x < b.x)
	return result

static func can_cast(s, caster: Dictionary, id: String, target: Vector2i) -> bool:
	var spell: Dictionary = definition(id)
	if spell.is_empty() or id not in caster.get("prepared",[]) or caster.mp < int(spell.mp): return false
	if id == "mend": return caster.hp < caster.max_hp
	if id == "blink": return not blink_cells(s,caster).is_empty()
	if id == "hound": return not summon_cells(s,caster).is_empty()
	if not s.inside(target) or not s.floor_state.visible.has(target): return false
	if s.distance(caster.pos,target) > int(spell.range): return false
	if not Kernel.sees(caster.pos,target,func(p): return s.tile(p).terrain == "wall",int(spell.range)): return false
	if id in ["bolt","confuse","cone","cloud"]:
		var victim: Dictionary = s.at(target)
		return not victim.is_empty() and bool(victim.enemy) != bool(caster.enemy)
	return true

static func blink_cells(s, caster: Dictionary) -> Array:
	var result: Array = []
	for cell in s.floor_state.visible:
		if maxi(absi(cell.x-caster.pos.x),absi(cell.y-caster.pos.y)) <= 3 and s.is_free(cell): result.append(cell)
	result.sort_custom(func(a,b): return a.y < b.y or a.y == b.y and a.x < b.x)
	return result

## The hound: an allied dungeon actor that takes its turns through the same
## npc branch every wanderer uses, and fades when its time runs out. It never
## joins, is never placed by the roster and never shows in the run's history.
static func summon(s, caster: Dictionary, cell: Vector2i) -> Dictionary:
	var pet: Dictionary = s.make_actor(2000+s.time%1000,"사냥개",false)
	pet.merge({"npc":true,"awake":true,"summoned":true,"expires_at":s.time+300,
		"mode":"","mode_until":0,"hungry":false,"partner":-1,"bond":"","situation":"RESTING",
		"state":"MET","floor_seen":int(s.depth),"joined_floor":0,"activity":"","explains":[],
		"noise_seen":s.npc_clock(),"declined_until":-99,"offered_until":-99},true)
	pet.gear = {"weapon":{},"armour":{},"shield":{},"ring":{}}
	pet.equipped_abilities = ["",""]; pet.rules = []
	pet.stance = "CHARGER"
	pet.hp = 20; pet.max_hp = 20; pet.stress = 0
	pet.pos = cell; pet.ap = 1; pet.ready_at = s.time+100
	pet.enemy = bool(caster.get("enemy",false))
	s.npcs.append(pet)
	return pet

static func cast(s, caster: Dictionary, id: String, target: Vector2i) -> bool:
	if not can_cast(s,caster,id,target): return false
	var spell: Dictionary = definition(id)
	caster.mp -= int(spell.mp)
	if Rules.roll(s,caster,{},"spell_failure_"+id,100) < failure(s,caster,id):
		s.message(str(spell.name)+" 실패")
		return true
	var school: String = str(spell.school)
	var power: int = int(spell.power) + Mastery.rank(caster,school) + int(Stats.stats(s,caster).power)
	if school == "fire": power = Effects.fire_power(caster,power)
	match id:
		"blink":
			var choices: Array = blink_cells(s,caster)
			caster.pos = choices[Rules.roll(s,caster,{},"blink",choices.size())]
		"mend":
			caster.hp = mini(caster.max_hp,caster.hp+power)
			caster.statuses["slow"] = s.time+300
		"confuse":
			var victim: Dictionary = s.at(target)
			if Rules.roll(s,caster,victim,"confuse",100)+power >= int(victim.get("will",80)):
				victim.statuses["confuse"] = s.time+300
				if victim.enemy: Mastery.record(caster,int(victim.id),school)
			else: s.message(str(victim.name)+" 저항")
		"cone":
			for cell in cells(s,caster,id,target):
				var victim: Dictionary = s.at(cell)
				if victim.is_empty() or bool(victim.enemy) == bool(caster.enemy): continue
				if victim.enemy: Mastery.record(caster,int(victim.id),school)
				Rules.damage(s,caster,victim,power,"ice")
				if victim.hp > 0: victim.statuses["slow"] = s.time+200
		"cloud":
			for cell in cells(s,caster,id,target):
				var victim: Dictionary = s.at(cell)
				if victim.is_empty() or bool(victim.enemy) == bool(caster.enemy): continue
				if victim.enemy: Mastery.record(caster,int(victim.id),school)
				Rules.damage(s,caster,victim,power,"air")
		"hound":
			summon(s,caster,summon_cells(s,caster)[0])
		"bolt", "blast":
			var penetration := 20 if Mastery.rank(caster,"fire") >= 7 else 0
			for cell in cells(s,caster,id,target):
				var victim: Dictionary = s.at(cell)
				if victim.is_empty(): continue
				if victim.enemy: Mastery.record(caster,int(victim.id),school)
				Rules.damage(s,caster,victim,power,"fire",penetration)
				Effects.on_spell_hit(s,caster,victim,school)
			if id == "blast":
				for cell in cells(s,caster,id,target): s.tile(cell).fire = mini(100,int(s.tile(cell).fire)+30)
	s.message(str(spell.name)+" 사용")
	return true
