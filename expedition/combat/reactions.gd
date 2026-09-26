extends RefCounted
## Element reactions. A hit of one element reacts with the ground it lands on
## and with the statuses its target already wears. The ground and the
## statuses belong to the fight, not to whoever put them there, so a
## companion's frost and the hero's blade react just as two monsters would.
## Damage a reaction deals never reacts again.
const TagSets = preload("res://expedition/progression/tag_sets.gd")
const HIT_FORM := "HIT"
const EXTRA_FORM := "EXTRA"
const REACTION_FORM := "REACTION"
const COUNTER_FORM := "COUNTER"
## Forms that run no passive, no set extra, no set proc and no trigger.
const SECONDARY := ["EXTRA","REACTION","COUNTER","RETALIATE"]
const WET_LEVEL := 20
const DRY_TICKS := 200
const ELEMENT_OF := {"fire":"fire","FIRE":"fire","ice":"ice","air":"air","ELECTRIC":"air","poison":"poison","POISON":"poison","will":"will","bleed":"bleed"}
const FIRE_MEETS_WATER := 30
const STEAM_SUPPRESSION := 20
const STEAM_TICKS := 200
const STEAM_DAMAGE := 2
const DISCHARGE_PERCENT := 30
const POOL_POISON_TICKS := 300
const NAMES := {"steam":"증기","ice":"얼음","discharge":"방전","poison_pool":"독 웅덩이",
	"poison_blast":"독 폭발!","shatter":"파쇄!","boiling":"끓는 피!","electrocute":"감전!","betrayal":"배신!"}
const BLAST_DAMAGE := 8
const BLAST_POISON_TICKS := 300
const STUN_TICKS := 100
const EXTRA_DAMAGE := 3
const EXTRA_ELEMENTS := ["fire","ice","air","poison"]
## Element step three: the status, its chance in a hundred and its ticks.
const PROCS := {"fire":["burn",15,300],"ice":["freeze",10,100],"poison":["poison",15,300],"will":["confuse",10,200],"bleed":["bleed",15,300]}

static func element_of(form: String) -> String:
	return str(ELEMENT_OF.get(form,"physical"))

static func round_of(s) -> int:
	return int(s.time)/100

## Every action opens a new window for the once-per-action triggers.
static func begin_action(s) -> void:
	s.action_serial += 1
	s.effect_depth = 0
	for actor in s.party+s.npcs+s.enemies:
		actor.repeat_reaction = false
		s.StoneEffects.Stacks.expire(actor,"action",int(s.time))

## True the first time `key` fires for `actor` in this action.
static func once(s, actor: Dictionary, key: String) -> bool:
	var fired: Dictionary = actor.get_or_add("triggers",{})
	if int(fired.get(key,-1)) == int(s.action_serial): return false
	fired[key] = int(s.action_serial)
	return true

## True the first time `name` reacts on `target` this round.
static func fresh_reaction(s, target: Dictionary, name: String) -> bool:
	var seen: Dictionary = target.get_or_add("reactions",{})
	if int(seen.get(name,-1)) == round_of(s): return false
	seen[name] = round_of(s)
	return true

## How much water a cell holds: standing water, deep water and bog are full.
static func water_level(cell: Dictionary) -> int:
	if str(cell.get("terrain","")) in ["water","deep_water","bog"]: return 100
	if bool(cell.get("deep_water",false)) or bool(cell.get("bog",false)): return 100
	return int(cell.get("wet",0))

static func wet_ground(s, point: Vector2i) -> bool:
	return s.inside(point) and water_level(s.tile(point)) >= WET_LEVEL

static func is_wet(s, actor: Dictionary) -> bool:
	if actor.get("statuses",{}).has("wet"): return true
	return actor.has("pos") and wet_ground(s,actor.pos)

## Whoever stands on wet ground is wet, and stays wet two rounds after leaving.
static func refresh_wet(s) -> void:
	for actor in s.party+s.npcs+s.enemies:
		if int(actor.hp) > 0 and wet_ground(s,actor.pos): actor.statuses["wet"] = int(s.time)+DRY_TICKS

## A landed hit (`HIT`) or a set's extra hit (`EXTRA`). Later tasks add the
## ground, the procs, the status reactions and the extras.
## Everything a landed blow sets off, in order: the ground under the target,
## the target's statuses, the attacker's element procs, then the attacker's
## element extras. The statuses react before the procs so a blow never
## shatters the ice its own proc just laid; a proc's status reacts on its own
## as it is hung. An extra hit reacts with the ground and the statuses but
## carries no proc and no extra of its own.
static func on_hit(s, source: Dictionary, target: Dictionary, element: String, amount: int, form: String) -> void:
	if source.is_empty() or form not in [HIT_FORM,EXTRA_FORM]: return
	target["last_hit"] = amount
	if target.has("pos"): tile_react(s,target.pos,element,amount,source)
	if int(target.hp) <= 0: return
	status_react(s,target,source,element,form)
	if int(target.hp) <= 0: return
	if form == HIT_FORM: procs(s,source,target)
	if form == HIT_FORM: extras(s,source,target)

## The same ground reaction on the same cell: once a round.
static func fresh_cell(s, cell: Dictionary, name: String) -> bool:
	var seen: Dictionary = cell.get_or_add("reactions",{})
	if int(seen.get(name,-1)) == round_of(s): return false
	seen[name] = round_of(s)
	return true

static func conductive(s, point: Vector2i) -> bool:
	return s.conductive(point)

static func blocks_sight(s, point: Vector2i) -> bool:
	return s.inside(point) and int(s.tile(point).get("steam_until",0)) > int(s.time)

## What an element does to the ground it lands on.
static func tile_react(s, cell: Vector2i, element: String, amount: int, source: Dictionary) -> void:
	if not s.inside(cell): return
	var ground: Dictionary = s.tile(cell)
	if str(ground.get("terrain","")) == "wall": return
	match element_of(element):
		"fire":
			if bool(ground.get("ice",false)):
				ground.ice = false; ground.wet = maxi(int(ground.wet),50)
				return
			var suppression: int = mini(FIRE_MEETS_WATER,water_level(ground))
			if suppression < STEAM_SUPPRESSION or not fresh_cell(s,ground,"steam"): return
			if water_level(ground) < 100: ground.wet = maxi(0,int(ground.wet)-suppression)
			steam(s,cell,source)
		"ice":
			if bool(ground.get("ice",false)) or water_level(ground) < WET_LEVEL: return
			ground.ice = true; ground.wet = 0
			var standing: Dictionary = s.at(cell)
			if not standing.is_empty(): s.Statuses.apply(s,standing,"freeze",100,source)
			announce(s,cell,"ice",source)
		"air":
			if amount <= 0 or not conductive(s,cell) or not fresh_cell(s,ground,"discharge"): return
			announce(s,cell,"discharge",source)
			s.discharge(cell,int(source.get("id",999)),maxi(1,reaction_damage(source,amount*DISCHARGE_PERCENT/100,s)))
		"poison":
			if bool(ground.get("poison_pool",false)) or water_level(ground) < WET_LEVEL: return
			ground.poison_pool = true
			announce(s,cell,"poison_pool",source)

## Steam on the cell and its four neighbours for two rounds.
static func steam(s, cell: Vector2i, source: Dictionary) -> void:
	for point in [cell,cell+Vector2i.LEFT,cell+Vector2i.RIGHT,cell+Vector2i.UP,cell+Vector2i.DOWN]:
		if s.inside(point) and str(s.tile(point).terrain) != "wall": s.tile(point).steam_until = int(s.time)+STEAM_TICKS
	announce(s,cell,"steam",source)

## One environment tick of the reaction ground on one cell. `suppression` is
## how much fire and water just cancelled there.
static func tile_tick(s, point: Vector2i, cell: Dictionary, suppression: int) -> void:
	if suppression >= STEAM_SUPPRESSION and fresh_cell(s,cell,"steam"): steam(s,point,{})
	if int(cell.get("steam_until",0)) > 0:
		if int(cell.steam_until) <= int(s.time): cell.erase("steam_until")
		else:
			var scalded: Dictionary = s.at(point)
			if not scalded.is_empty(): s.CombatRules.damage(s,{},scalded,STEAM_DAMAGE,"fire",0,REACTION_FORM)
	if bool(cell.get("ice",false)) and int(cell.get("fire",0)) > 0: cell.ice = false; cell.wet = maxi(int(cell.wet),50)
	if bool(cell.get("poison_pool",false)):
		if water_level(cell) <= 0: cell.poison_pool = false
		else:
			var soaked: Dictionary = s.at(point)
			if not soaked.is_empty(): hang(s,soaked,"poison",POOL_POISON_TICKS)

## A status a reaction hangs: resisted like any other, but it sets off no
## further reaction of its own.
static func hang(s, victim: Dictionary, status: String, ticks: int) -> void:
	ticks = s.Statuses.resisted_ticks(s,victim,status,ticks)
	if ticks <= 0: return
	victim.statuses[status] = int(s.time)+ticks
	if status == "burn": victim.get_or_add("status_power",{})["burn"] = s.Statuses.BURN_DAMAGE

## What a reaction bites for: its own number. (The old 술사 3 bonus went with
## the role sets; the role combos never touch secondary damage.)
static func reaction_damage(source: Dictionary, amount: int, s = null) -> int:
	var value: int = amount if s == null else amount*(100+s.StoneEffects.modifier(s,"reaction_percent",source))/100
	return value*2 if bool(source.get("repeat_reaction",false)) else value

static func react_damage(s, source: Dictionary, target: Dictionary, amount: int, element: String) -> int:
	return s.CombatRules.damage(s,source,target,reaction_damage(source,amount,s),element,0,REACTION_FORM)

## The reaction's name, big over the cell, in the log and in the event queue.
static func announce(s, cell: Vector2i, key: String, source: Dictionary) -> void:
	source.repeat_reaction = false
	var name: String = str(NAMES[key])
	s.effects.append({"kind":"REACTION","from":cell,"cell":cell,"text":name})
	s.message("%s 반응" % name.trim_suffix("!"))
	s.push_event({"kind":"REACTION","name":name,"cell":cell})
	s.StoneEffects.fire(s,"REACTION",{"source":source,"target":s.at(cell),"reaction":key,"cell":cell})

## What the statuses a target already wears do with each other and with the
## element that just struck it. `form` is "HIT", "EXTRA" or "STATUS" (a status
## was just hung).
static func status_react(s, target: Dictionary, source: Dictionary, element: String, form: String) -> void:
	if int(target.get("hp",0)) <= 0 or not target.has("pos"): return
	element = element_of(element)
	var worn: Dictionary = target.get("statuses",{})
	if worn.has("burn") and worn.has("poison") and fresh_reaction(s,target,"poison_blast"):
		worn.erase("burn"); worn.erase("poison")
		announce(s,target.pos,"poison_blast",source)
		var centre: Vector2i = target.pos
		for other in s.party+s.npcs+s.enemies:
			if int(other.hp) <= 0 or maxi(absi(other.pos.x-centre.x),absi(other.pos.y-centre.y)) > 1: continue
			react_damage(s,source,other,BLAST_DAMAGE,"poison")
			if int(other.hp) > 0 and int(other.id) != int(target.id): hang(s,other,"poison",BLAST_POISON_TICKS)
	if int(target.hp) <= 0: return
	if element == "physical" and form == HIT_FORM and worn.has("freeze") and fresh_reaction(s,target,"shatter"):
		worn.erase("freeze")
		announce(s,target.pos,"shatter",source)
		react_damage(s,source,target,maxi(1,int(target.get("last_hit",0))/2),"physical")
	if int(target.hp) <= 0: return
	if worn.has("bleed") and worn.has("burn") and fresh_reaction(s,target,"boiling"):
		# The ticks still to come, this boundary included: `Statuses.tick` bites
		# at every boundary up to and including the status's last one.
		var rounds: int = maxi(1,(int(worn.bleed)-int(s.time))/100+1)
		worn.erase("bleed")
		announce(s,target.pos,"boiling",source)
		react_damage(s,source,target,rounds*2,"fire")
	if int(target.hp) <= 0: return
	if element == "air" and is_wet(s,target) and fresh_reaction(s,target,"electrocute"):
		hang(s,target,"stun",STUN_TICKS)
		announce(s,target.pos,"electrocute",source)
	if worn.has("confuse") and worn.has("taunt") and fresh_reaction(s,target,"betrayal"): betray(s,target,source)

## 혼란 + 도발: the confused one strikes the nearest of its own side beside it
## instead of whoever taunted it. Nothing happens with nobody beside it.
static func betray(s, target: Dictionary, source: Dictionary) -> bool:
	var victims: Array = (s.party+s.npcs+s.enemies).filter(func(o): return int(o.hp) > 0 and int(o.id) != int(target.id) and s.side_of(o) == s.side_of(target) and s.melee_reach(target.pos,o.pos))
	if victims.is_empty(): return false
	victims.sort_custom(func(a,b): return int(a.id) < int(b.id))
	announce(s,target.pos,"betrayal",source)
	s.CombatRules.attack(s,target,victims[0])
	return true

static func procs(s, source: Dictionary, target: Dictionary) -> void:
	for element in PROCS:
		if int(target.hp) <= 0 or TagSets.level(source,element) < 3: continue
		var row: Array = PROCS[element]
		if s.CombatRules.roll(s,source,target,"set_"+element,100) < int(row[1]):
			s.Statuses.apply(s,target,str(row[0]),int(row[2]),source)

## Element step two: three more of each element the attacker's sets carry,
## each its own hit against its own resistance.
static func extras(s, source: Dictionary, target: Dictionary) -> void:
	for element in EXTRA_ELEMENTS:
		if int(target.hp) <= 0: return
		if TagSets.level(source,element) >= 2: s.CombatRules.damage(s,source,target,EXTRA_DAMAGE,element,0,EXTRA_FORM)
