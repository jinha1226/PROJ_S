extends RefCounted
## Stones are BASE/part[@element]; a bare BASE aliases its headline part.
## Boss stones have no parts. Storage uses canonical ids, actions use species ids.
const Abilities = preload("res://expedition/items/abilities.gd")
const Bestiary = preload("res://expedition/progression/bestiary.gd")
const ROLES := {"PACK":"무리","BERSERK":"광폭","AMBUSH":"기습","GUARD":"수호","ARCHER":"사수","CASTER":"술사"}
const ELEMENTS := {"fire":"화염","ice":"냉기","air":"전기","poison":"독","will":"의지","bleed":"출혈"}
## A soul stone has no tiers any more (2026-09-26 spec §4): one absorption
## switches all of it on, and a member absorbs a stone once.
const MAX_TIER := 1
const MAX_LEVEL := 10
## How many spells stand ready at once: the floor HUD draws this many buttons.
const READY_SPELLS := 5
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
		"part":part,"part_name":str(piece.get("name","")),"effect":str(piece.get("effect",base.get("effect","")))}
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
	for raw in actor.get("equipped_abilities",[]):
		var id: String = canonical(str(raw))
		if id.is_empty() or id in result or sealed.keys().any(func(key): return canonical(str(key)) == id): continue
		result.append(id)
	return result

static func slot_count(actor: Dictionary) -> int:
	return clampi(int(actor.get("level",1)),1,MAX_LEVEL)

## The highest spell level a caster stone opens: the character's own level.
static func spell_cap(actor: Dictionary) -> int:
	return clampi(int(actor.get("level",1)),1,MAX_LEVEL)

static func can_manage(s) -> bool:
	if s.phase in ["IDLE","CAMP"]: return true
	return s.phase == "EXPLORE" and s.floor_state.safe(s)

## Grows the slot row to the level. A level never falls, so slots never close.
static func sync_slots(actor: Dictionary) -> void:
	normalize_actor(actor)
	var slots: Array = actor.get("equipped_abilities",[])
	while slots.size() < slot_count(actor): slots.append("")
	actor.equipped_abilities = slots

## One from the bag into the member, once: a stone already absorbed stays in
## the bag for somebody else. The bag loses it for good.
static func absorb(s, actor: Dictionary, id: String) -> String:
	id = canonical(id)
	if id.is_empty(): return "없는 영혼석"
	s.parts_bag = normalize_keys(s.parts_bag,true)
	normalize_actor(actor)
	if int(s.parts_bag.get(id,0)) <= 0: return "가방에 없음"
	if int(actor.hp) <= 0: return "쓰러짐"
	if not can_manage(s): return "전투 중"
	var known: Dictionary = actor.get_or_add("essences",{})
	if int(known.get(id,0)) > 0: return "이미 흡수함"
	s.parts_bag[id] = int(s.parts_bag[id])-1
	known[id] = 1
	s.Codex.note_absorb(s,id)
	var chosen: Dictionary = actor.get_or_add("essence_spells",{})
	if not school(id).is_empty() and not chosen.has(id):
		var choices := spell_choices(actor,id)
		var existing: Array = chosen.keys().filter(func(other): return base_of(str(other)) == base_of(id) and str(chosen[other]) in choices)
		if not choices.is_empty(): chosen[id] = chosen[existing[0]] if not existing.is_empty() else choices[0]
	sync_spells(actor)
	return ""

static func equip(s, actor: Dictionary, slot: int, id: String) -> bool:
	if not can_manage(s) or int(actor.hp) <= 0: return false
	return put(actor,slot,id)

static func unequip(s, actor: Dictionary, slot: int) -> bool:
	if not can_manage(s) or int(actor.hp) <= 0: return false
	return take(actor,slot)

## The slot change itself, with no question of where or when: NPCs re-slot on
## their own in the middle of a floor (plan 3/3), the player only through
## `equip`/`unequip`.
static func put(actor: Dictionary, slot: int, id: String) -> bool:
	id = canonical(id)
	if id.is_empty(): return false
	sync_slots(actor)
	if slot < 0 or slot >= slot_count(actor): return false
	if int(actor.get("essences",{}).get(id,0)) <= 0 or id in actor.equipped_abilities: return false
	var retained: Array = []
	var previous: String = str(actor.equipped_abilities[slot])
	if not previous.is_empty():
		if base_of(previous) == base_of(id): retained = actor.get("rules",[]).filter(func(r): return Abilities.base_id(str(r.get("skill",""))) == base_of(id)).duplicate(true)
		take(actor,slot)
		for rule in retained:
			if not actor.rules.any(func(r): return Abilities.base_id(str(r.get("skill",""))) == base_of(id)): actor.rules.append(rule)
	actor.equipped_abilities[slot] = id
	actor.reservation = {}
	sync_rules(actor)
	sync_spells(actor)
	return true

static func take(actor: Dictionary, slot: int) -> bool:
	normalize_actor(actor)
	var slots: Array = actor.get("equipped_abilities",[])
	if slot < 0 or slot >= slots.size() or str(slots[slot]).is_empty(): return false
	var old: String = str(slots[slot])
	slots[slot] = ""
	if not slots.any(func(id): return not str(id).is_empty() and base_of(str(id)) == base_of(old)):
		actor.rules = actor.get("rules",[]).filter(func(r): return Abilities.base_id(str(r.get("skill",""))) != base_of(old))
	sync_rules(actor)
	actor.reservation = {}
	sync_spells(actor)
	return true

## One rule per species; its configured condition survives removing one part.
## If variants share a species, the first unsealed slot supplies the element.
static func sync_rules(actor: Dictionary) -> void:
	for id in Abilities.held(actor):
		var base: String = Abilities.base_id(str(id))
		var existing: Array = actor.get("rules",[]).filter(func(r): return Abilities.base_id(str(r.get("skill",""))) == base)
		if existing.is_empty(): actor.get_or_add("rules",[]).append(Abilities.default_rule(str(id)))
		else: existing[0].skill = str(id)

## The school's spells up to the member's level, lowest level first.
static func spell_choices(actor: Dictionary, id: String) -> Array:
	var wanted := school(id)
	if wanted.is_empty(): return []
	var cap := spell_cap(actor)
	var result: Array = []
	for spell_id in combat.spells:
		var spell: Dictionary = combat.spells[spell_id]
		if str(spell.get("shape","")).is_empty(): continue
		if str(spell.get("school","")) == wanted and int(spell.level) <= cap: result.append(str(spell_id))
	result.sort_custom(func(a,b): return int(combat.spells[a].level) < int(combat.spells[b].level) or int(combat.spells[a].level) == int(combat.spells[b].level) and a < b)
	return result

static func choose_spell(s, actor: Dictionary, id: String, spell_id: String) -> bool:
	id = canonical(id)
	normalize_actor(actor)
	if not can_manage(s) or int(actor.get("essences",{}).get(id,0)) <= 0: return false
	if spell_id not in spell_choices(actor,id): return false
	actor.get_or_add("essence_spells",{})[id] = spell_id
	for other in actor.essences:
		if base_of(str(other)) == base_of(id): actor.essence_spells[other] = spell_id
	sync_spells(actor)
	return true

## `spells` is every spell an absorbed caster essence has chosen; `prepared`
## is the ones in a slot now, at most READY_SPELLS, in slot order.
static func sync_spells(actor: Dictionary) -> void:
	normalize_actor(actor)
	var chosen: Dictionary = actor.get("essence_spells",{})
	var shared: Dictionary = {}
	# Preserve the first equipped part's choice when migrating conflicting old selections.
	var order: Array = equipped(actor)
	order.append_array(actor.get("essences",{}).keys())
	for id in order:
		var base: String = base_of(str(id))
		var spell: String = str(chosen.get(id,""))
		if not school(str(id)).is_empty() and not shared.has(base) and spell in spell_choices(actor,str(id)): shared[base] = spell
	for id in actor.get("essences",{}):
		var base: String = base_of(str(id))
		if shared.has(base): chosen[id] = shared[base]
	actor.essence_spells = chosen
	var known: Array = []
	for id in actor.get("essences",{}):
		var spell: String = str(shared.get(base_of(str(id)),""))
		if not school(str(id)).is_empty() and not spell.is_empty() and spell not in known: known.append(spell)
	var ready: Array = []
	for id in equipped(actor):
		var spell: String = str(shared.get(base_of(str(id)),""))
		if not school(str(id)).is_empty() and not spell.is_empty() and spell not in ready and ready.size() < READY_SPELLS: ready.append(spell)
	actor.spells = known
	actor.prepared = ready

## Whether a caster stone of that school is slotted.
static func school_slotted(actor: Dictionary, wanted: String) -> bool:
	return equipped(actor).any(func(id): return school(str(id)) == wanted)

static func drop_chance(s, species_id: String) -> int:
	return REPEAT_PERCENT if s.essence_seen.has(species_id) else FIRST_KILL_PERCENT
