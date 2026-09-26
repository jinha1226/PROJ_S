extends RefCounted
const Subtypes = preload("res://expedition/progression/subtypes.gd")
const Equipment = preload("res://expedition/items/equipment.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
const Zones = preload("res://expedition/level/zones.gd")
static var effects: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/stone_effects.json")).effects
static var names: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/gear_names.json"))
static var artifacts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/unrands.json")).rows

static func roll(s, key: int, lane: String, modulus: int) -> int:
	return Hexaco.sample(int(s.seed_value),key,"randart:"+lane,modulus)

static func subtypes(s) -> Array:
	var result: Array = []
	for actor in s.party:
		for id in Essences.equipped(actor):
			var effect: String = str(Essences.row(id).get("effect",""))
			var subtype := Subtypes.of(effect)
			if not subtype.is_empty() and subtype not in result: result.append(subtype)
	return result

static func weighted(s, key: int, lane: String, pool: Array) -> Variant:
	if pool.is_empty(): return null
	var present := subtypes(s)
	var expanded: Array = []
	for row in pool:
		expanded.append(row)
		if str(row.get("subtype",Subtypes.of(str(row.get("affix",""))))) in present: expanded.append(row)
	return expanded[roll(s,key,lane,expanded.size())]

static func make(s, key: int, type: String, force_tier: String = "", boss: bool = false) -> Dictionary:
	var zone: int = Zones.zone_of(int(s.depth))
	var odds: Array = Equipment.content.loot.tiers_by_zone[str(zone)]
	var value: int = roll(s,key,"tier",100)
	var tier: String = force_tier
	if tier.is_empty(): tier = "base" if value < int(odds[0]) else "randart" if value < int(odds[0])+int(odds[1]) else "unrand"
	if boss: tier = "unrand" if value < 25 else "randart"
	if tier == "unrand":
		var available: Array = artifacts.filter(func(row): return not s.unrands_seen.has(str(row.id)))
		var chosen: Variant = weighted(s,key,"unrand",available)
		if chosen != null:
			s.unrands_seen[str(chosen.id)] = true
			return {"type":str(chosen.type),"tier":"unrand","enchant":zone-1,"props":[],"affix":chosen.affix,"cost_effect":chosen.cost_effect,"unrand":chosen.id,"name":chosen.name,"uid":key}
		tier = "randart"
	var item := {"type":type,"tier":tier,"enchant":clampi(zone-1,0,3),"props":[],"uid":key}
	if tier == "base": return item
	var slot: String = Equipment.slot(item)
	var count: int = 2 if zone == 1 else 2+roll(s,key,"count",2) if zone == 2 else 3 if zone == 3 else 3+roll(s,key,"count",2)
	var affixes: Array = []
	for id in effects:
		var row: Dictionary = effects[id]
		if row.get("source","") != "gear" or row.get("gear_kind","") != "affix" or slot not in row.get("slots",[]): continue
		if slot == "ring1" and (zone == 1 or (zone == 2 and Subtypes.GROUP.get(str(row.get("subtype","")),"") in ["MAGIC","SUPPORT"])): continue
		if slot == "offhand" and (str(type).begins_with("off_") != str(id).begins_with("GEAR_FORM_")): continue
		var copy: Dictionary = row.duplicate(); copy.id = id; affixes.append(copy)
	if not affixes.is_empty() and roll(s,key,"affix_exists",100) < 60:
		item.affix = weighted(s,key,"affix",affixes).id; count -= 1
	var pool: Array = Equipment.content.loot.randart_props.filter(func(row): return slot in row.slots or type in row.slots)
	for i in range(count):
		if pool.is_empty(): break
		var selected: int = roll(s,key,"prop:%d"%i,pool.size())
		var prop: Dictionary = pool[selected]; pool.remove_at(selected)
		var bounds: Array = prop.ranges[zone-1]
		item.props.append({"key":prop.key,"value":int(bounds[0])+roll(s,key,"value:%d"%i,int(bounds[1])-int(bounds[0])+1)})
	if roll(s,key,"flaw_exists",100) < 30:
		var flaws: Array = Equipment.content.loot.randart_flaws.filter(func(row): return not item.props.any(func(p): return p.key == row.key))
		var flaw: Dictionary = flaws[roll(s,key,"flaw",flaws.size())]
		item.flaw = {"key":flaw.key,"value":int(flaw.range[0])+roll(s,key,"flaw_value",int(flaw.range[1])-int(flaw.range[0])+1)}
		for prop in item.props: prop.value = ceili(float(prop.value)*1.5)
	var adjective: String = str(names.adjectives[roll(s,key,"adjective",names.adjectives.size())])
	var nouns: Array = names.nouns.get(slot,names.nouns.weapon)
	item.name = adjective+" "+str(nouns[roll(s,key,"noun",nouns.size())])+" · "+str(Equipment.definition(item).get("name",type))
	return item
