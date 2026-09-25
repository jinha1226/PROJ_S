extends RefCounted
## Element variants of floor monsters (spec §3.7): the element a floor leans
## to, which of its monsters wear an element, and what wearing one changes.
## Deterministic: every roll is a Hexaco sample of the run seed.
const Abilities = preload("res://expedition/items/abilities.gd")
const Encounters = preload("res://expedition/level/encounter_builder.gd")
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
## Chance that a monster whose species has variants is drawn as one.
const VARIANT_PERCENT := 40
const OWN_RESIST := 50
const OPPOSITE_WEAKNESS := 25

## The elements that suit a species, from `floor_monsters.json` `variants`.
static func allowed(species_id: String) -> Array:
	return Encounters.species(species_id).get("variants",[])

## The floor's main element: one that suits at least one monster on it. The
## first floor has none.
static func floor_element(seed_value: int, depth: int, enemies: Array) -> String:
	if depth <= 1: return ""
	var pool: Array = []
	for enemy in enemies:
		if enemy.get("boss",false): continue
		for element in allowed(str(enemy.get("species_id",""))):
			if element not in pool: pool.append(element)
	if pool.is_empty(): return ""
	pool.sort()
	return str(pool[Hexaco.sample(seed_value,depth,"floor_element",pool.size())])

## Turns a minted monster into its `element` variant.
static func apply(enemy: Dictionary, element: String) -> void:
	enemy["variant_element"] = element
	enemy.name = "%s %s" % [Abilities.ELEMENT_NAMES[element],enemy.name]
	var res: Dictionary = enemy.get("res",{}).duplicate(true)
	res[element] = maxi(int(res.get(element,0)),OWN_RESIST)
	if Abilities.OPPOSITE.has(element):
		var other: String = Abilities.OPPOSITE[element]
		res[other] = int(res.get(other,0))-OPPOSITE_WEAKNESS
	enemy.res = res
	if not str(enemy.get("part_id","")).is_empty(): enemy.part_id = "%s@%s" % [enemy.part_id,element]

## Picks the floor's element and makes variants of some of `enemies`, in id
## order. A monster whose species suits the floor's element takes it; one that
## does not may take another of its elements only while those stay fewer than
## the floor's own, so at least half the variants wear the floor's element.
## Returns the floor's element ("" on the first floor).
static func assign(s, enemies: Array) -> String:
	var element := floor_element(int(s.seed_value),int(s.depth),enemies)
	if element.is_empty(): return ""
	var ordered: Array = enemies.duplicate()
	ordered.sort_custom(func(a,b): return int(a.id) < int(b.id))
	var on_floor := 0
	var off_floor := 0
	for enemy in ordered:
		if enemy.get("boss",false): continue
		var options: Array = allowed(str(enemy.get("species_id","")))
		if options.is_empty(): continue
		var key: int = int(s.depth)*1000+int(enemy.id)
		if Hexaco.sample(int(s.seed_value),key,"variant",100) >= VARIANT_PERCENT: continue
		if element in options:
			apply(enemy,element); on_floor += 1
		elif off_floor < on_floor:
			apply(enemy,str(options[Hexaco.sample(int(s.seed_value),key,"variant_element",options.size())]))
			off_floor += 1
	return element
