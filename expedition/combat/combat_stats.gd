extends RefCounted
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
static var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/combat.json"))

## The ten starting kits: five weapons and five spell schools.
static func kits() -> Array:
	return content.get("kits", [])

static func kit(id: String) -> Dictionary:
	for row in kits():
		if str(row.id) == id: return row
	return {}

static func species(actor: Dictionary) -> Dictionary:
	return content.species.get(str(actor.get("species_id", "human")), content.species.human)

static func stats(session, actor: Dictionary) -> Dictionary:
	var sheet: Dictionary = StatSheet.sheet(session,actor)
	var result := {"damage":int(actor.get("power", 7)), "delay":100, "ac":int(sheet.ac.total), "ev":int(sheet.ev.total), "sh":mini(StatSheet.BLOCK_CAP,int(sheet.sh.total)), "enc":0, "range":1, "brand":"", "trait":"", "res":{}, "power":0}
	for element in StatSheet.RES: result.res[element] = int(sheet["res_"+element].total)
	if not bool(actor.get("enemy", false)):
		var strength: int = int(sheet.str.total)
		var dexterity: int = int(sheet.dex.total)
		var gear: Dictionary = actor.get("gear", {})
		var weapon: Dictionary = gear.get("weapon", {})
		var weapon_def: Dictionary = content.weapons.get(str(weapon.get("type", "")), {})
		result.damage = 4 + strength / 6
		if not weapon_def.is_empty():
			result.trait = str(weapon_def.trait)
			var drive: int = dexterity if result.trait == "ranged" else strength
			result.damage = int(weapon_def.damage) + int(weapon.get("enchant", 0)) + drive / 6
			result.delay = int(weapon_def.delay)
			result.range = int(weapon_def.range) + (TagSets.range_bonus(actor) if result.trait == "ranged" else 0)
			result.brand = str(weapon.get("brand", ""))
			if result.trait == "focus": result.power += 4
		# A summoned creature carries no gear at all: it fights with the power
		# its own row in `combat.json.summons` gave it.
		if bool(actor.get("summoned", false)) and weapon_def.is_empty(): result.damage = int(actor.get("power", 7))
		var armour: Dictionary = gear.get("armour", {})
		var armour_def: Dictionary = content.armours.get(str(armour.get("type", "")), {})
		if not armour_def.is_empty(): result.enc = maxi(0, int(armour_def.enc) - strength / 5)
		var shield_worn: bool = not gear.get("shield", {}).is_empty()
		var shield: bool = shield_worn and result.trait not in ["ranged", "focus"]
		if shield: result.enc += 2
		var natural_block: int = maxi(0,int(sheet.sh.total)-(StatSheet.SHIELD_BLOCK if shield_worn else 0))
		result.sh = mini(StatSheet.BLOCK_CAP,natural_block+StatSheet.SHIELD_BLOCK if shield else natural_block/2)
		var ring: Dictionary = gear.get("ring", {})
		var ring_def: Dictionary = content.rings.get(str(ring.get("type", "")), {})
		if not ring_def.is_empty() and str(ring_def.stat) == "power": result.power += int(ring_def.value)
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
