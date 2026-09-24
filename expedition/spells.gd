extends RefCounted
## Fifty spells in five schools, all of them built from eight shapes. A row in
## `combat.json.spells` says which shape a spell is and what it carries; the
## code below knows the shapes, not the spells.
const Stats = preload("res://expedition/combat_stats.gd")
const Rules = preload("res://expedition/combat_rules.gd")
const Mastery = preload("res://expedition/mastery.gd")
const Effects = preload("res://expedition/mastery_effects.gd")
const Kernel = preload("res://sim/combat_kernel.gd")

## The eight effect primitives every school is written in.
const primitives := ["bolt", "line", "cone", "burst", "wall", "self", "mark", "summon"]
## The ten statuses a spell can hang on what it hits.
const STATUSES := ["confuse", "slow", "freeze", "bind", "burn", "weak", "brittle", "distort", "vulnerable", "dominate"]
## The port's own spells, kept out of every book: they no longer drop.
const RELICS := ["bolt", "blast", "blink", "confuse", "mend", "cone", "cloud", "hound"]

static var _implemented: Array = []

## Every spell the code can actually resolve: the relics and all fifty rows.
static func implemented() -> Array:
	if _implemented.is_empty(): _implemented = RELICS + schooled()
	return _implemented

## Every spell that belongs to a school, in table order.
static func schooled() -> Array:
	var result: Array = []
	for id in Stats.content.spells:
		if not str(Stats.content.spells[id].get("shape", "")).is_empty(): result.append(str(id))
	return result

static func definition(id: String) -> Dictionary:
	return Stats.content.spells.get(id, {}) if id in implemented() else {}

static func shape_of(spell: Dictionary) -> String:
	return str(spell.get("shape", ""))

static func book(id: String) -> Dictionary:
	return Stats.content.books.get(id, {})

## The spells a book teaches, lowest level first.
static func book_spells(book_id: String) -> Array:
	var row: Dictionary = book(book_id)
	if row.is_empty(): return []
	return row.levels.map(func(level): return "%s_%d" % [str(row.school), int(level)])

## Why this actor may not learn the spell right now — empty when it may.
static func learnable(s, actor: Dictionary, id: String) -> String:
	var spell: Dictionary = definition(id)
	if spell.is_empty() or str(spell.get("book", "")).is_empty(): return "없는 주문"
	if id in actor.get("spells", []): return "이미 배움"
	if s != null and str(s.phase) != "CAMP": return "야영에서만"
	if str(spell.book) not in actor.get("books", []): return "주문서 없음"
	if Mastery.rank(actor, str(spell.school)) < int(spell.level) - 1: return "숙련 부족"
	return ""

static func failure(s, caster: Dictionary, id: String) -> int:
	var spell: Dictionary = definition(id)
	if spell.is_empty(): return 100
	var school: String = str(spell.school)
	return clampi(8 + int(spell.level) * 9 + int(Stats.stats(s,caster).enc) * 5 - Mastery.rank(caster,school) * 5 - int(Stats.species(caster).int), 0, 85)

# ── shapes ────────────────────────────────────────────────────────────────

static func cells(s, caster: Dictionary, id: String, target: Vector2i) -> Array:
	var spell: Dictionary = definition(id)
	var shape: String = shape_of(spell)
	if shape.is_empty(): return relic_cells(s,caster,id,target)
	match shape:
		"self": return [caster.pos]
		"summon": return []
		"line": return line_cells(s,caster,target,int(spell.get("length",3)))
		"cone": return cone_cells(s,caster,target)
		"burst": return burst_cells(s,target,int(spell.get("radius",1)))
		"wall": return wall_cells(s,caster,target,int(spell.get("length",3)))
	return [target] if s.inside(target) else []

## The straight run: n cells from the caster towards the aimed one, stopped by
## the first wall.
static func line_cells(s, caster: Dictionary, target: Vector2i, length: int) -> Array:
	var step := Vector2i(signi(target.x-caster.pos.x),signi(target.y-caster.pos.y))
	if step == Vector2i.ZERO: step = Vector2i(1,0)
	var result: Array = []
	for i in range(1,maxi(1,length)+1):
		var cell: Vector2i = caster.pos+step*i
		if not s.inside(cell) or s.tile(cell).terrain == "wall": break
		result.append(cell)
	return result

## The fan: the aimed cell and the two beside it, square across the line the
## caster looks along.
static func cone_cells(s, caster: Dictionary, target: Vector2i) -> Array:
	var step := Vector2i(signi(target.x-caster.pos.x),signi(target.y-caster.pos.y))
	if step == Vector2i.ZERO: step = Vector2i(1,0)
	var side := Vector2i(-step.y,step.x)
	var result: Array = []
	for cell in [target,target+side,target-side]:
		if s.inside(cell) and cell not in result: result.append(cell)
	return result

static func burst_cells(s, target: Vector2i, radius: int) -> Array:
	var result: Array = []
	for y in range(target.y-radius,target.y+radius+1):
		for x in range(target.x-radius,target.x+radius+1):
			var cell := Vector2i(x,y)
			if s.inside(cell): result.append(cell)
	return result

## The barrier: n cells laid across the caster's line of sight, centre first.
static func wall_cells(s, caster: Dictionary, target: Vector2i, length: int) -> Array:
	var step := Vector2i(signi(target.x-caster.pos.x),signi(target.y-caster.pos.y))
	if step == Vector2i.ZERO: step = Vector2i(1,0)
	var side := Vector2i(-step.y,step.x)
	if side == Vector2i.ZERO: side = Vector2i(0,1)
	var result: Array = []
	for i in range(maxi(1,length)):
		var offset: int = (i+1)/2 * (1 if i % 2 == 1 else -1)
		var cell: Vector2i = target+side*offset
		if s.inside(cell) and s.tile(cell).terrain != "wall" and cell not in result: result.append(cell)
	return result

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

# ── casting ───────────────────────────────────────────────────────────────

static func can_cast(s, caster: Dictionary, id: String, target: Vector2i) -> bool:
	var spell: Dictionary = definition(id)
	if spell.is_empty() or id not in caster.get("prepared",[]) or caster.mp < int(spell.mp): return false
	var shape: String = shape_of(spell)
	if shape.is_empty(): return relic_can_cast(s,caster,id,target,spell)
	if shape == "self": return true
	if shape == "summon": return not summon_cells(s,caster).is_empty()
	if bool(spell.get("sacrifice",false)): return not summons_of(s,caster).is_empty()
	if not s.inside(target) or not s.floor_state.visible.has(target): return false
	if s.distance(caster.pos,target) > int(spell.range): return false
	if not bool(spell.get("ignore_los",false)) and not Kernel.sees(caster.pos,target,func(p): return s.tile(p).terrain == "wall",int(spell.range)): return false
	if shape in ["bolt","mark"]:
		var victim: Dictionary = s.at(target)
		return not victim.is_empty() and bool(victim.enemy) != bool(caster.enemy)
	return true

static func cast(s, caster: Dictionary, id: String, target: Vector2i) -> bool:
	if not can_cast(s,caster,id,target): return false
	var spell: Dictionary = definition(id)
	caster.mp -= int(spell.mp)
	if Rules.roll(s,caster,{},"spell_failure_"+id,100) < failure(s,caster,id):
		s.message(str(spell.name)+" 실패")
		return true
	if shape_of(spell).is_empty(): relic_cast(s,caster,id,target,spell)
	else: shaped_cast(s,caster,id,target,spell)
	s.message(str(spell.name)+" 사용")
	return true

## One spell, resolved by its shape. Everything the row carries — power,
## element, status, ticks — travels through here unchanged.
static func shaped_cast(s, caster: Dictionary, id: String, target: Vector2i, spell: Dictionary) -> void:
	if not caster.has("buffs"): caster["buffs"] = {}
	var buffs: Dictionary = caster.buffs
	var statuses: Dictionary = caster.get("statuses",{})
	var school: String = str(spell.school)
	var shape: String = shape_of(spell)
	var power: int = int(spell.power)
	if power > 0: power += Mastery.rank(caster,school) + int(Stats.stats(s,caster).power)
	var penetration: int = int(spell.get("penetration",0))
	var ticks: int = int(spell.get("ticks",0))
	var chain: int = int(spell.get("chain",0))
	# What an earlier "축적" spell stored is spent on the first spell it fits.
	match school:
		"fire":
			power = Effects.fire_power(caster,power)
			if statuses.has("fire_mastery"): power = power*3/2
			if buffs.has("next_fire"): power = power*int(buffs.next_fire)/100; buffs.erase("next_fire")
			if buffs.has("next_pierce"): penetration += int(buffs.next_pierce); buffs.erase("next_pierce")
		"ice":
			if buffs.has("next_ice_slow"): ticks = ticks*int(buffs.next_ice_slow)/100; buffs.erase("next_ice_slow")
		"air":
			if statuses.has("air_chain"): chain += 1
			if buffs.has("next_chain"): chain += int(buffs.next_chain); buffs.erase("next_chain")
	if shape == "mark" and statuses.has("hex_mastery"): ticks *= 2
	match shape:
		"self": apply_self(s,caster,spell)
		"summon":
			var kind: String = str(spell.get("summon","hound"))
			var places: Array = summon_cells(s,caster)
			for i in range(mini(int(spell.get("count",1)),places.size())):
				summon(s,caster,places[i],kind)
		"mark":
			var victim: Dictionary = s.at(target)
			if victim.is_empty(): return
			mark(s,caster,victim,spell,power,ticks)
		"wall":
			for cell in cells(s,caster,id,target):
				var tile: Dictionary = s.tile(cell)
				tile["wall_until"] = s.time+maxi(100,ticks)
				tile["wall_burn"] = str(spell.get("status","")) == "burn"
		_:
			var centre: Vector2i = target
			if bool(spell.get("sacrifice",false)):
				var pets: Array = summons_of(s,caster)
				if pets.is_empty(): return
				centre = pets[0].pos
				pets[0].hp = 0; s.npcs.erase(pets[0])
			var struck: Array = []
			for cell in cells(s,caster,id,centre):
				var victim: Dictionary = s.at(cell)
				if victim.is_empty() or bool(victim.enemy) == bool(caster.get("enemy",false)) or victim.id == caster.id: continue
				var hit: int = power
				if bool(spell.get("wet_bonus",false)) and int(s.tile(cell).wet) > 0: hit *= 2
				strike(s,caster,victim,spell,hit,penetration,ticks)
				struck.append(int(victim.id))
				if int(spell.get("push",0)) > 0: push(s,caster,victim,int(spell.push))
			# The arc jumps to whoever stands next to what it already hit.
			for step in range(chain):
				var jumped := false
				for cell in cells(s,caster,id,centre):
					var source: Dictionary = s.at(cell)
					if source.is_empty() or int(source.id) not in struck: continue
					for other in s.enemies+s.npcs:
						if other.hp <= 0 or int(other.id) in struck: continue
						if bool(other.enemy) == bool(caster.get("enemy",false)): continue
						if not s.melee_reach(source.pos,other.pos): continue
						strike(s,caster,other,spell,maxi(1,power/2),penetration,ticks)
						struck.append(int(other.id)); jumped = true
						break
					if jumped: break
				if not jumped: break

## One victim, one hit: damage of the row's element, then whatever the row
## hangs on what survives.
static func strike(s, caster: Dictionary, victim: Dictionary, spell: Dictionary, power: int, penetration: int, ticks: int) -> void:
	var school: String = str(spell.school)
	if bool(victim.enemy): Mastery.record(caster,int(victim.id),school)
	if power > 0: Rules.damage(s,caster,victim,power,str(spell.get("element","physical")),penetration)
	if victim.hp <= 0: return
	var status: String = str(spell.get("status",""))
	if status in STATUSES and ticks > 0: victim.statuses[status] = s.time+ticks
	if status == "dominate" and ticks > 0: victim["dominated_until"] = s.time+ticks
	if school == "ice" and caster.get("statuses",{}).has("ice_freeze") and Rules.roll(s,caster,victim,"ice_freeze",100) < 30:
		victim.statuses["freeze"] = s.time+100
	if school == "fire": Effects.on_spell_hit(s,caster,victim,school)

## The hex marks: a will save, then the status the row names. Four of them are
## not a status at all but something done to the statuses already there.
static func mark(s, caster: Dictionary, victim: Dictionary, spell: Dictionary, power: int, ticks: int) -> void:
	var school: String = str(spell.school)
	# Only the hex school argues with a will; a fire mark simply burns.
	var force: int = power + Mastery.rank(caster,school) + int(Stats.stats(s,caster).power)
	if school == "hex" and Rules.roll(s,caster,victim,"mark_"+str(spell.name),100)+force < int(victim.get("will",80)):
		s.message(str(victim.name)+" 저항"); return
	if bool(victim.enemy): Mastery.record(caster,int(victim.id),school)
	var status: String = str(spell.get("status",""))
	match status:
		"extend":
			for id in victim.statuses: victim.statuses[id] = int(victim.statuses[id])+ticks
			if int(victim.get("dominated_until",0)) > s.time: victim.dominated_until = int(victim.dominated_until)+ticks
		"spread_status", "spread_burn":
			var carried: Dictionary = {}
			if status == "spread_burn": carried["burn"] = s.time+ticks
			else:
				for id in victim.statuses: carried[id] = victim.statuses[id]
			if status == "spread_burn": victim.statuses["burn"] = s.time+ticks
			for other in s.enemies+s.npcs:
				if other.hp <= 0 or int(other.id) == int(victim.id): continue
				if bool(other.enemy) == bool(caster.get("enemy",false)): continue
				if not s.melee_reach(victim.pos,other.pos): continue
				for id in carried: other.statuses[id] = carried[id]
		"dominate":
			victim.statuses["dominate"] = s.time+ticks
			victim["dominated_until"] = s.time+ticks
			s.message(str(victim.name)+" 지배")
		_:
			if status in STATUSES: victim.statuses[status] = s.time+ticks
	if str(spell.get("element","")) != "" and int(spell.power) > 0:
		Rules.damage(s,caster,victim,power,str(spell.element))

## The self spells. A timed one is a status the caster wears; a stored one is a
## single charge in `buffs`, spent by the next spell that fits it.
static func apply_self(s, caster: Dictionary, spell: Dictionary) -> void:
	var buff: String = str(spell.get("buff",""))
	if buff.is_empty(): return
	var ticks: int = int(spell.get("ticks",0))
	var value: int = int(spell.get("value",0))
	if buff == "summon_power":
		for pet in summons_of(s,caster): pet.statuses["rage"] = s.time+ticks
		caster.statuses[buff] = s.time+ticks
		return
	if ticks > 0:
		caster.statuses[buff] = s.time+ticks
		return
	match buff:
		"summon_hp":
			for pet in summons_of(s,caster):
				pet.max_hp = maxi(1,int(pet.max_hp)*value/100)
				pet.hp = mini(int(pet.max_hp),maxi(1,int(pet.hp)*value/100))
			caster.buffs[buff] = value
		"summon_time":
			for pet in summons_of(s,caster): pet.expires_at = int(pet.expires_at)+value
			caster.buffs[buff] = value
		"summon_renew":
			for pet in summons_of(s,caster):
				pet.hp = int(pet.max_hp)
				pet.expires_at = s.time+int(Stats.content.summons.get(str(pet.get("summon_kind","hound")),{}).get("duration",300))
		_: caster.buffs[buff] = value

## One cell away from the caster, if the cell will have it.
static func push(s, caster: Dictionary, victim: Dictionary, distance: int) -> void:
	if victim.hp <= 0: return
	var step := Vector2i(signi(victim.pos.x-caster.pos.x),signi(victim.pos.y-caster.pos.y))
	if step == Vector2i.ZERO: return
	for i in range(distance):
		var cell: Vector2i = victim.pos+step
		if not s.is_free(cell) or not s.walk_reach(victim.pos,cell): return
		victim.pos = cell

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
	pet.equipped_abilities = ["",""]; pet.rules = []
	pet.stance = "CHARGER"
	pet.hp = int(row.hp)*int(buffs.get("summon_hp",100))/100
	pet.max_hp = pet.hp
	pet.power = int(row.power); pet.speed = int(row.speed); pet.stress = 0
	pet.pos = cell; pet.ap = 1; pet.ready_at = s.time+100
	pet.enemy = bool(caster.get("enemy",false))
	if caster.get("statuses",{}).has("summon_power"): pet.statuses["rage"] = int(caster.statuses.summon_power)
	s.npcs.append(pet)
	return pet

# ── the port's own spells, kept working and kept out of the books ─────────

static func relic_cells(s, caster: Dictionary, id: String, target: Vector2i) -> Array:
	if id == "cone": return cone_cells(s,caster,target)
	if id == "hound": return []
	if id != "blast" and id != "cloud" and not (id == "bolt" and Mastery.rank(caster,"fire") >= 5): return [target]
	return burst_cells(s,target,1)

static func relic_can_cast(s, caster: Dictionary, id: String, target: Vector2i, spell: Dictionary) -> bool:
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

static func relic_cast(s, caster: Dictionary, id: String, target: Vector2i, spell: Dictionary) -> void:
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
