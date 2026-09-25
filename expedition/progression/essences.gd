extends RefCounted
## Essences: what a monster leaves behind and a member absorbs. Every catalog
## part is one; the caster essences have no part and give a spell instead.
## A variant id is "<BASE>@<element>": the base row with that element's tag
## and ten more points of that element's resistance.
const Abilities = preload("res://expedition/items/abilities.gd")
const Bestiary = preload("res://expedition/progression/bestiary.gd")
const ROLES := {"PACK":"무리","BERSERK":"광폭","AMBUSH":"기습","GUARD":"수호","ARCHER":"사수","CASTER":"술사"}
const ELEMENTS := {"fire":"화염","ice":"냉기","air":"전기","poison":"독","will":"의지","bleed":"출혈"}
const MAX_TIER := 3
const MAX_LEVEL := 10
## How many spells stand ready at once: the floor HUD draws this many buttons.
const READY_SPELLS := 5
const FIRST_KILL_PERCENT := 100
const REPEAT_PERCENT := 25
const CASTER_BY_SCHOOL := {"fire":"FIRE_CALLER","ice":"FROST_IMP","air":"STORM_BAT","hex":"GOBLIN_HEXER","summon":"GNOLL_SUMMONER"}
const SPELL_CAP := {1:3,2:6,3:10}
static var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/essences.json"))
static var combat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/combat.json"))

static func base_of(id: String) -> String:
	return id.get_slice("@",0)

static func variant_element(id: String) -> String:
	return id.get_slice("@",1) if id.contains("@") else ""

static func has(id: String) -> bool:
	if id.is_empty() or not content.rows.has(base_of(id)): return false
	var element := variant_element(id)
	return element.is_empty() or ELEMENTS.has(element)

## A row's stats come from its role (zones spec §3.1); a role-less row (the
## basics) keeps what it lists. A variant adds ten of its element's
## resistance, except bleed, which nothing resists.
static func row(id: String) -> Dictionary:
	if not has(id): return {}
	var base: Dictionary = content.rows[base_of(id)]
	var role: String = str(base.get("role",""))
	var stats: Dictionary = Bestiary.essence_stats(role,str(base.get("school",""))) if not role.is_empty() else (base.get("stats",{}) as Dictionary).duplicate()
	var result := {"name":str(base.get("name","")),"stats":stats,"role":role,"element":str(base.get("element","")),
		"school":str(base.get("school","")),"species":str(base.get("species","")),"family":str(base.get("family",""))}
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

static func stats(id: String, tier: int) -> Dictionary:
	var result: Dictionary = {}
	var base: Dictionary = row(id).get("stats",{})
	for key in base: result[key] = int(base[key])*clampi(tier,1,MAX_TIER)
	return result

static func role(id: String) -> String: return str(row(id).get("role",""))

static func element(id: String) -> String: return str(row(id).get("element",""))

static func school(id: String) -> String: return str(row(id).get("school",""))

## The absorbed tier; an essence put straight into a slot (fixtures, sims)
## counts as tier one.
static func tier(actor: Dictionary, id: String) -> int:
	if id.is_empty(): return 0
	var known: int = int(actor.get("essences",{}).get(id,0))
	if known > 0: return mini(known,MAX_TIER)
	return 1 if id in actor.get("equipped_abilities",[]) else 0

static func equipped(actor: Dictionary) -> Array:
	var sealed: Dictionary = actor.get("sealed",{})
	return actor.get("equipped_abilities",[]).filter(func(id): return has(str(id)) and not sealed.has(str(id)))

static func slot_count(actor: Dictionary) -> int:
	return clampi(int(actor.get("level",1)),1,MAX_LEVEL)

static func spell_cap(tier: int) -> int:
	return int(SPELL_CAP[clampi(tier,1,MAX_TIER)])

static func active_power(tier: int, base: int) -> int:
	return base*(100+25*(clampi(tier,1,MAX_TIER)-1))/100

static func can_manage(s) -> bool:
	if s.phase in ["IDLE","CAMP"]: return true
	return s.phase == "EXPLORE" and s.floor_state.safe(s)

## Grows the slot row to the level. A level never falls, so slots never close.
static func sync_slots(actor: Dictionary) -> void:
	var slots: Array = actor.get("equipped_abilities",[])
	while slots.size() < slot_count(actor): slots.append("")
	actor.equipped_abilities = slots

## One from the bag into the member: a new essence at tier one, a known one a
## tier higher. The bag loses it for good.
static func absorb(s, actor: Dictionary, id: String) -> String:
	if not has(id): return "없는 영혼석"
	if int(s.parts_bag.get(id,0)) <= 0: return "가방에 없음"
	if int(actor.hp) <= 0: return "쓰러짐"
	if not can_manage(s): return "전투 중"
	var known: Dictionary = actor.get_or_add("essences",{})
	var before: int = int(known.get(id,0))
	if before >= MAX_TIER: return "최고 단계"
	s.parts_bag[id] = int(s.parts_bag[id])-1
	known[id] = before+1
	var chosen: Dictionary = actor.get_or_add("essence_spells",{})
	if not school(id).is_empty() and not chosen.has(id):
		var choices := spell_choices(actor,id)
		if not choices.is_empty(): chosen[id] = choices[0]
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
	sync_slots(actor)
	if slot < 0 or slot >= slot_count(actor): return false
	if int(actor.get("essences",{}).get(id,0)) <= 0 or id in actor.equipped_abilities: return false
	if not str(actor.equipped_abilities[slot]).is_empty(): take(actor,slot)
	actor.equipped_abilities[slot] = id
	actor.reservation = {}
	if Abilities.has(id) and not actor.get("rules",[]).any(func(r): return r.skill == id):
		actor.get_or_add("rules",[]).append(Abilities.default_rule(id))
	sync_spells(actor)
	return true

static func take(actor: Dictionary, slot: int) -> bool:
	var slots: Array = actor.get("equipped_abilities",[])
	if slot < 0 or slot >= slots.size() or str(slots[slot]).is_empty(): return false
	var old: String = str(slots[slot])
	slots[slot] = ""
	actor.rules = actor.get("rules",[]).filter(func(r): return r.skill != old)
	actor.reservation = {}
	sync_spells(actor)
	return true

## The school's spells this essence's tier reaches, lowest level first.
static func spell_choices(actor: Dictionary, id: String) -> Array:
	var wanted := school(id)
	if wanted.is_empty(): return []
	var cap := spell_cap(maxi(1,tier(actor,id)))
	var result: Array = []
	for spell_id in combat.spells:
		var spell: Dictionary = combat.spells[spell_id]
		if str(spell.get("shape","")).is_empty(): continue
		if str(spell.get("school","")) == wanted and int(spell.level) <= cap: result.append(str(spell_id))
	result.sort_custom(func(a,b): return int(combat.spells[a].level) < int(combat.spells[b].level) or int(combat.spells[a].level) == int(combat.spells[b].level) and a < b)
	return result

static func choose_spell(s, actor: Dictionary, id: String, spell_id: String) -> bool:
	if not can_manage(s) or int(actor.get("essences",{}).get(id,0)) <= 0: return false
	if spell_id not in spell_choices(actor,id): return false
	actor.get_or_add("essence_spells",{})[id] = spell_id
	sync_spells(actor)
	return true

## `spells` is every spell an absorbed caster essence has chosen; `prepared`
## is the ones in a slot now, at most READY_SPELLS, in slot order.
static func sync_spells(actor: Dictionary) -> void:
	var chosen: Dictionary = actor.get("essence_spells",{})
	var known: Array = []
	for id in actor.get("essences",{}):
		var spell: String = str(chosen.get(id,""))
		if not school(str(id)).is_empty() and not spell.is_empty() and spell not in known: known.append(spell)
	var ready: Array = []
	for id in equipped(actor):
		var spell: String = str(chosen.get(str(id),""))
		if not school(str(id)).is_empty() and not spell.is_empty() and spell not in ready and ready.size() < READY_SPELLS: ready.append(spell)
	actor.spells = known
	actor.prepared = ready

## The best tier among the slotted caster essences of that school.
static func caster_tier(actor: Dictionary, wanted: String) -> int:
	var best := 0
	for id in equipped(actor):
		if school(id) == wanted: best = maxi(best,tier(actor,id))
	return best

static func drop_chance(s, species_id: String) -> int:
	return REPEAT_PERCENT if s.essence_seen.has(species_id) else FIRST_KILL_PERCENT
