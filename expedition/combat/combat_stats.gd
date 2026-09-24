extends RefCounted
const Mastery = preload("res://expedition/progression/mastery.gd")
static var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/combat.json"))

## The ten starting kits, in Mastery.AXES order: one weapon per mastery axis.
static func kits() -> Array:
	return content.get("kits", [])

static func kit(id: String) -> Dictionary:
	for row in kits():
		if str(row.id) == id: return row
	return {}

static func species(actor: Dictionary) -> Dictionary:
	return content.species.get(str(actor.get("species_id", "human")), content.species.human)

static func stats(_session, actor: Dictionary) -> Dictionary:
	var result := {"damage":int(actor.get("power", 7)), "delay":100, "ac":int(actor.get("ac", 0)), "ev":int(actor.get("ev", 3)), "sh":int(actor.get("sh", 0)), "enc":0, "range":1, "brand":"", "trait":"", "res":actor.get("res", {}).duplicate(), "power":0}
	if not bool(actor.get("enemy", false)):
		var spec: Dictionary = species(actor)
		var gear: Dictionary = actor.get("gear", {})
		var weapon: Dictionary = gear.get("weapon", {})
		var weapon_def: Dictionary = content.weapons.get(str(weapon.get("type", "")), {})
		result.damage = 4 + int(spec.str) / 6
		result.ac = 0; result.ev = int(spec.dex) / 3
		if not weapon_def.is_empty():
			var level := Mastery.rank(actor, Mastery.weapon_axis(str(weapon.type)))
			result.damage = int(weapon_def.damage) + int(weapon.get("enchant", 0)) + level + int(spec.str) / 6
			result.delay = maxi(60, int(weapon_def.delay) - level * 4)
			result.range = int(weapon_def.range)
			result.trait = str(weapon_def.trait)
			result.brand = str(weapon.get("brand", ""))
			if result.trait == "focus": result.power += 4
		# A summoned creature carries no gear at all: it fights with the power
		# its own row in `combat.json.summons` gave it.
		if bool(actor.get("summoned", false)) and weapon_def.is_empty(): result.damage = int(actor.get("power", 7))
		var armour: Dictionary = gear.get("armour", {})
		var armour_def: Dictionary = content.armours.get(str(armour.get("type", "")), {})
		if not armour_def.is_empty():
			result.ac += int(armour_def.ac) + int(armour.get("enchant", 0))
			result.enc = maxi(0, int(armour_def.enc) - int(spec.str) / 5)
			result.ev -= int(armour_def.ev_penalty)
		if not gear.get("shield", {}).is_empty() and result.trait not in ["ranged", "focus"]:
			result.sh = 15; result.enc += 2
		var ring: Dictionary = gear.get("ring", {})
		var ring_def: Dictionary = content.rings.get(str(ring.get("type", "")), {})
		if not ring_def.is_empty():
			if ring_def.stat in ["ev", "power"]: result[ring_def.stat] += int(ring_def.value)
			else: result.res[ring_def.stat] = int(ring_def.value)
	var statuses: Dictionary = actor.get("statuses", {})
	if statuses.has("ward"): result.ac += 6
	if statuses.has("rage"): result.damage += 8
	if statuses.has("corrode"): result.ac = maxi(0, int(result.ac) - 4)
	# 취성 eats armour the way corrosion does; 약화 takes the strength out of a
	# blow; 폭풍의 눈 is the air school's own coat of wind.
	if statuses.has("brittle"): result.ac = maxi(0, int(result.ac) - 4)
	if statuses.has("weak"): result.damage = int(result.damage) * 7 / 10
	if statuses.has("summon_power"): result.damage = int(result.damage) * 3 / 2
	if statuses.has("stormeye"): result.ev += 20
	return result
