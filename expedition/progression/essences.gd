extends RefCounted
## Stones are BASE/part[@element]; a bare BASE aliases its headline part.
## Boss stones have no parts. Storage uses canonical ids, actions use species ids.
const Abilities = preload("res://expedition/items/abilities.gd")
const Bestiary = preload("res://expedition/progression/bestiary.gd")
const ROLES := {"TANK":"탱커","MELEE":"근접","RANGED":"원거리","MAGIC":"마법","SUPPORT":"지원"}
const ELEMENTS := {"fire":"화염","ice":"냉기","air":"전기","poison":"독","will":"의지","bleed":"출혈"}
## A soul stone has no tiers any more (2026-09-26 spec §4): one absorption
## switches all of it on, and a member absorbs a stone once.
const MAX_TIER := 1
const MAX_LEVEL := 10
const MAX_SLOTS := 6
## Every permanent stone can supply a spell; the HUD keeps five quick buttons.
const READY_SPELLS := MAX_SLOTS
const QUICK_SPELLS := 5
const FIRST_KILL_PERCENT := 100
const REPEAT_PERCENT := 25
const CASTER_BY_SCHOOL := {"fire":"FIRE_CALLER","ice":"FROST_IMP","air":"STORM_BAT","hex":"GOBLIN_HEXER","summon":"GNOLL_SUMMONER"}
static var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/essences.json"))
static var combat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/combat.json"))

static func base_of(id: String) -> String:
	return id.get_slice("@",0).get_slice("/",0)

static func variant_element(id: String) -> String:
	return id.get_slice("@",1) if id.contains("@") else ""

static func canonical(id: String) -> String:
	if id.is_empty() or id.count("@") > 1 or id.count("/") > 1 or not content.rows.has(base_of(id)): return ""
	var element := variant_element(id)
	if id.contains("@") and not ELEMENTS.has(element): return ""
	var base: String = base_of(id)
	var entry: Dictionary = content.rows[base]
	var raw: String = id.get_slice("@",0)
	if entry.has("parts"):
		var part: String = raw.get_slice("/",1) if raw.contains("/") else str(entry.headline)
		if not entry.parts.has(part): return ""
		base += "/"+part
	elif raw.contains("/"): return ""
	return base+("@"+element if not element.is_empty() else "")

static func part_of(id: String) -> String:
	var stone: String = canonical(id).get_slice("@",0)
	return stone.get_slice("/",1) if stone.contains("/") else ""

static func has(id: String) -> bool:
	return not canonical(id).is_empty()

## All concrete stones in catalog order (90 parts and three boss stones).
static func catalog() -> Array:
	var result: Array = []
	for base in content.rows:
		var entry: Dictionary = content.rows[base]
		if entry.has("parts"):
			for part in entry.parts: result.append(str(base)+"/"+str(part))
		else: result.append(str(base))
	return result

## Quantity aliases combine; ownership aliases stay one absorption. Known
## canonical entries take precedence when migrating nonnumeric selections.
static func normalize_keys(values: Dictionary, quantities: bool = false, ownership: bool = true) -> Dictionary:
	var result: Dictionary = {}
	var keys: Array = values.keys()
	keys.sort_custom(func(a,b): return str(a) < str(b))
	var aliases: Array = keys.filter(func(key): return str(key) != canonical(str(key)))
	keys = keys.filter(func(key): return str(key) == canonical(str(key)))
	keys.append_array(aliases)
	for key in keys:
		var id: String = canonical(str(key))
		if id.is_empty(): continue
		if quantities: result[id] = int(result.get(id,0))+maxi(0,int(values[key]))
		elif values[key] is int or values[key] is float: result[id] = mini(1,maxi(int(result.get(id,0)),int(values[key]))) if ownership else maxi(int(result.get(id,0)),int(values[key]))
		elif not result.has(id): result[id] = values[key]
	return result

static func normalize_actor(actor: Dictionary) -> void:
	for field in ["essences","essence_spells"]:
		if actor.has(field): actor[field] = normalize_keys(actor[field])
	if actor.has("sealed"): actor.sealed = normalize_keys(actor.sealed,false,false)
	var slots: Array = []
	for raw in actor.get("equipped_abilities",[]):
		var id: String = canonical(str(raw))
		if id.is_empty() and Abilities.has(str(raw)) and str(Abilities.definition(str(raw)).get("species","")).is_empty(): id = Abilities.active_id(str(raw))
		slots.append(id if id not in slots else "")
	actor.equipped_abilities = slots
	var cooldowns: Dictionary = {}
	for key in actor.get("cooldowns",{}):
		var id: String = Abilities.cooldown_id(str(key),actor) if Abilities.has(str(key)) else str(key)
		cooldowns[id] = maxi(int(cooldowns.get(id,0)),int(actor.cooldowns[key]))
	actor.cooldowns = cooldowns
	var rules: Array = []; var seen: Array = []
	for entry in actor.get("rules",[]):
		var rule: Dictionary = entry.duplicate(true)
		var skill: String = str(rule.get("skill",""))
		if Abilities.has(skill):
			rule.skill = Abilities.active_id(skill)
			var key: String = Abilities.base_id(skill)
			if key in seen: continue
			seen.append(key)
		rules.append(rule)
	actor.rules = rules
	# A seal can change which variant supplies a shared active; update existing
	# rules without adding rules to passive-only fixtures or fresh caster kits.
	for id in Abilities.held(actor):
		for rule in actor.rules:
			if Abilities.base_id(str(rule.get("skill",""))) == Abilities.base_id(str(id)): rule.skill = str(id)
	if actor.has("reservation") and Abilities.has(str(actor.reservation.get("kind",""))): actor.reservation.kind = Abilities.active_id(str(actor.reservation.kind))

static func normalize_run(s) -> void:
	s.parts_bag = normalize_keys(s.parts_bag,true)
	if s.battle_stats.has("drops"): s.battle_stats.drops = normalize_keys(s.battle_stats.drops,true)
	for actor in s.party+s.roster+s.npcs:
		normalize_actor(actor)
		sync_rules(actor)
		sync_spells(actor)

## A row's stats come from its role (zones spec §3.1); a role-less row (the
## basics) keeps what it lists. A variant adds ten of its element's
## resistance, except bleed, which nothing resists.
static func row(id: String) -> Dictionary:
	if not has(id): return {}
	var base: Dictionary = content.rows[base_of(id)]
	var part: String = part_of(id)
	var piece: Dictionary = base.get("parts",{}).get(part,{})
	var role: String = str(base.get("role",""))
	var stats: Dictionary = Bestiary.essence_stats(role,str(base.get("school",""))) if not role.is_empty() else (base.get("stats",{}) as Dictionary).duplicate()
	var result := {"name":str(base.get("name","")),"stats":stats,"role":role,"element":str(base.get("element","")),
		"school":str(base.get("school","")),"species":str(base.get("species","")),"family":str(base.get("family","")),
		"part":part,"part_name":str(piece.get("name","")),"active":str(piece.get("active","")),"effect":str(piece.get("effect",base.get("effect",""))),
		"spells":piece.get("spells",base.get("spells",[])).duplicate()}
	if not part.is_empty(): result.name = result.part_name
	var element := variant_element(id)
	if not element.is_empty():
		result.element = element
		if element != "bleed":
			var key := "res_"+element
			result.stats[key] = int(result.stats.get(key,0))+10
	return result

static func family(id: String) -> String: return str(row(id).get("family",""))

## The part's item name for a part essence, the row's own name for a caster.
static func title(id: String) -> String:
	if not has(id): return ""
	var name: String = str(row(id).name)
	if name.is_empty(): name = str(Abilities.DEFINITIONS.get(base_of(id),{}).get("item",base_of(id)))
	var element := variant_element(id)
	return name if element.is_empty() else "%s %s" % [ELEMENTS[element],name]

## The stone's fixed base stats: its role's, plus a variant's resistance.
static func stats(id: String) -> Dictionary:
	var result: Dictionary = {}
	var base: Dictionary = row(id).get("stats",{})
	for key in base: result[key] = int(base[key])
	return result

static func role(id: String) -> String: return str(row(id).get("role",""))

static func element(id: String) -> String: return str(row(id).get("element",""))

static func school(id: String) -> String: return str(row(id).get("school",""))

## Whether the member has this stone: absorbed, or put straight into a slot
## (fixtures, sims).
static func absorbed(actor: Dictionary, id: String) -> bool:
	id = canonical(id)
	if id.is_empty(): return false
	return actor.get("essences",{}).keys().any(func(key): return canonical(str(key)) == id and int(actor.essences[key]) > 0) or actor.get("equipped_abilities",[]).any(func(key): return canonical(str(key)) == id)

static func equipped(actor: Dictionary) -> Array:
	var sealed: Dictionary = actor.get("sealed",{})
	var result: Array = []
	for raw in actor.get("equipped_abilities",[]).slice(0,MAX_SLOTS):
		var id: String = canonical(str(raw))
		if id.is_empty() or id in result or sealed.keys().any(func(key): return canonical(str(key)) == id): continue
		result.append(id)
	return result

static func slot_count(actor: Dictionary) -> int:
	return clampi(int(actor.get("level",1)),1,MAX_SLOTS)

## The highest spell level a caster stone opens: the character's own level.
static func spell_cap(actor: Dictionary) -> int:
	return clampi(int(actor.get("level",1)),1,MAX_LEVEL)

static func can_manage(s) -> bool:
	if s.phase in ["IDLE","CAMP"]: return true
	return s.phase == "EXPLORE" and s.floor_state.safe(s)

## The first six levels open one permanent absorption each.
static func sync_slots(actor: Dictionary) -> void:
	normalize_actor(actor)
	var slots: Array = actor.get("equipped_abilities",[])
	while slots.size() < slot_count(actor): slots.append("")
	actor.equipped_abilities = slots.slice(0,MAX_SLOTS)

## Sealed stones still occupy their permanent slots.
static func free_slot(actor: Dictionary) -> int:
	var slots: Array = actor.get("equipped_abilities",[])
	for slot in range(slot_count(actor)):
		if slot >= slots.size() or str(slots[slot]).is_empty(): return slot
	return -1

## Commits one permanent stone, shared by bag absorption and independent NPC hunts.
## A rejected choice never changes ownership, rules, spells or reservations.
static func bind(actor: Dictionary, id: String) -> String:
	id = canonical(id)
	if id.is_empty(): return "없는 영혼석"
	if absorbed(actor,id): return "이미 흡수함"
	var slot := free_slot(actor)
	if slot < 0: return "영혼석 가득 참"
	sync_slots(actor)
	actor.get_or_add("essences",{})[id] = 1
	actor.equipped_abilities[slot] = id
	actor.reservation = {}
	var chosen: Dictionary = actor.get_or_add("essence_spells",{})
	var choices := spell_choices(actor,id)
	if not choices.is_empty(): chosen[id] = choices[0]
	sync_rules(actor)
	sync_spells(actor)
	return ""

## One from the bag into an empty slot, immediately and permanently.
static func absorb(s, actor: Dictionary, id: String) -> String:
	id = canonical(id)
	if id.is_empty(): return "없는 영혼석"
	s.parts_bag = normalize_keys(s.parts_bag,true)
	if int(s.parts_bag.get(id,0)) <= 0: return "가방에 없음"
	if int(actor.hp) <= 0: return "쓰러짐"
	if not can_manage(s): return "전투 중"
	var reason := bind(actor,id)
	if not reason.is_empty(): return reason
	s.parts_bag[id] = int(s.parts_bag[id])-1
	s.Codex.note_absorb(s,id)
	return ""

## Compatibility entry points refuse the retired re-slotting operation.
static func equip(_s, _actor: Dictionary, _slot: int, _id: String) -> bool: return false
static func unequip(_s, _actor: Dictionary, _slot: int) -> bool: return false
static func put(_actor: Dictionary, _slot: int, _id: String) -> bool: return false
static func take(_actor: Dictionary, _slot: int) -> bool: return false

## One rule per species or granted build action; existing conditions survive absorption.
## If variants share a species, the first unsealed slot supplies the element.
static func sync_rules(actor: Dictionary) -> void:
	for id in Abilities.held(actor):
		var base: String = Abilities.base_id(str(id))
		var existing: Array = actor.get("rules",[]).filter(func(r): return Abilities.base_id(str(r.get("skill",""))) == base)
		if existing.is_empty(): actor.get_or_add("rules",[]).append(Abilities.default_rule(str(id)))
		else: existing[0].skill = str(id)

## Only the spells explicitly attached to this concrete stone, never a whole school.
static func spell_catalog(id: String) -> Array:
	var result: Array = []
	for entry in row(id).get("spells",[]):
		var spell_id := str(entry)
		var spell: Dictionary = combat.spells.get(spell_id,{})
		if str(spell.get("shape","")).is_empty() or spell_id in result: continue
		result.append(spell_id)
	result.sort_custom(func(a,b): return int(combat.spells[a].level) < int(combat.spells[b].level) or int(combat.spells[a].level) == int(combat.spells[b].level) and a < b)
	return result

static func spell_choices(actor: Dictionary, id: String) -> Array:
	var cap := spell_cap(actor)
	return spell_catalog(id).filter(func(spell): return int(combat.spells[spell].level) <= cap)

static func choose_spell(s, actor: Dictionary, id: String, spell_id: String) -> bool:
	id = canonical(id)
	normalize_actor(actor)
	if not can_manage(s) or int(actor.get("essences",{}).get(id,0)) <= 0: return false
	if spell_id not in spell_choices(actor,id): return false
	actor.get_or_add("essence_spells",{})[id] = spell_id
	sync_spells(actor)
	return true

## Each part keeps its own choice. Invalid legacy choices fall back to the
## first linked unlocked spell; level-up also activates previously locked stones.
static func sync_spells(actor: Dictionary) -> void:
	normalize_actor(actor)
	var chosen: Dictionary = actor.get("essence_spells",{})
	var order: Array = equipped(actor)
	for id in actor.get("essences",{}):
		if id not in order: order.append(id)
	var known: Array = []
	for id in order:
		var choices := spell_choices(actor,str(id))
		var spell: String = str(chosen.get(id,""))
		if spell not in choices:
			if choices.is_empty(): chosen.erase(id); continue
			spell = str(choices[0]); chosen[id] = spell
		if spell not in known: known.append(spell)
	actor.essence_spells = chosen
	var ready: Array = []
	for id in equipped(actor):
		var spell: String = str(chosen.get(id,""))
		if not spell.is_empty() and spell not in ready and ready.size() < READY_SPELLS: ready.append(spell)
	actor.spells = known
	actor.prepared = ready

## Whether a caster stone of that school is slotted.
static func school_slotted(actor: Dictionary, wanted: String) -> bool:
	return equipped(actor).any(func(id): return spell_catalog(str(id)).any(func(spell): return str(combat.spells[spell].school) == wanted))

static func drop_chance(s, species_id: String) -> int:
	return REPEAT_PERCENT if s.essence_seen.has(species_id) else FIRST_KILL_PERCENT
