extends RefCounted
## §3.9: how a stranger picks the essences it wears, and what it takes from its
## own hunts. Party members are the player's to dress; nothing here touches them.
const Essences = preload("res://expedition/progression/essences.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
const DROP_PERCENT := 25
const SET_BONUS := 300
const PLAIN := 300
const Forms = preload("res://expedition/combat/forms.gd")
const Subtypes = preload("res://expedition/progression/subtypes.gd")
const Effects = preload("res://expedition/progression/stone_effects.gd")

## Low A leans to 광폭·기습, high C to 수호, high O to 술사; a stone it has
## absorbed counts a little over one it has not.
static func preference(npc: Dictionary, id: String) -> int:
	var profile = npc.profile
	var score: int = 100 if Essences.absorbed(npc,id) else 0
	match str(Essences.role(id)):
		"MELEE": score += 1000-int(profile.value("A"))
		"TANK", "SUPPORT": score += int(profile.value("C"))
		"MAGIC": score += int(profile.value("O"))
		_: score += PLAIN
	var effect: String = Effects.effect_of(id)
	var subtype := Subtypes.of(effect)
	var group: String = str(Subtypes.GROUP.get(subtype,""))
	match group:
		"MELEE": score += (1000-int(profile.value("A")))/2
		"TANK", "SUPPORT": score += int(profile.value("C"))/2
		"MAGIC": score += int(profile.value("O"))/2

	return score

## How many already chosen essences share a role or an element with `id`.
static func continuing(picked: Array, id: String) -> int:
	var count := 0
	for other in picked:
		var same_role: bool = not str(Essences.role(id)).is_empty() and Essences.role(id) == Essences.role(str(other))
		var same_element: bool = not str(Essences.element(id)).is_empty() and Essences.element(id) == Essences.element(str(other))
		var subtype := Subtypes.of(Effects.effect_of(id))
		var same_build: bool = not subtype.is_empty() and subtype == Subtypes.of(Effects.effect_of(str(other)))
		if same_role or same_element or same_build: count += 1
	return count

## Initial/legacy pools choose only empty slots. A hunt never replaces a stone.
static func choose(s, npc: Dictionary) -> void:
	Essences.sync_slots(npc)
	var pool: Array = npc.get("essences",{}).keys().filter(func(id): return id not in npc.equipped_abilities)
	# Pending legacy choices are not permanent until selected.
	for id in pool: npc.essences.erase(id)
	while Essences.free_slot(npc) >= 0 and not pool.is_empty():
		var best := ""; var best_score := -(1 << 30)
		var picked: Array = npc.equipped_abilities.filter(func(id): return not str(id).is_empty())
		for entry in pool:
			var id: String = str(entry)
			var score: int = preference(npc,id)+SET_BONUS*continuing(picked,id)
			if score > best_score or (score == best_score and id < best): best = id; best_score = score
		pool.erase(best)
		Essences.bind(npc,best)
		if not str(Essences.school(best)).is_empty():
			var choices: Array = Essences.spell_choices(npc,best)
			var core: Array = choices.filter(func(spell): return str(Essences.combat.spells[spell].shape) in ["bolt","line","cone","burst","mark","summon"] and not bool(Essences.combat.spells[spell].get("sacrifice",false)))
			if not core.is_empty(): npc.get_or_add("essence_spells",{})[best] = str(core.back())
	Essences.sync_spells(npc)
	StatSheet.refresh_pools(s,npc)

## An independent NPC's own kill: the first of a species always gives its
## essence, later ones one time in four; only a free slot can absorb it.
static func on_hunt(s, enemy: Dictionary, hunters: Array) -> void:
	var id: String = str(enemy.get("part_id",""))
	id = Essences.canonical(id)
	if not Essences.has(id): return
	for npc in hunters:
		if npc in s.party or not bool(npc.get("npc",false)) or int(npc.hp) <= 0: continue
		var seen: Dictionary = npc.get_or_add("essence_seen",{})
		var species: String = Abilities.kind_key(enemy)
		if seen.has(species) and Hexaco.sample(s.seed_value,int(s.depth)*100000+int(enemy.id)*100+int(npc.id)%100,"npc_essence",100) >= DROP_PERCENT: continue
		seen[species] = true
		var part: String = Forms.pick_part(str(enemy.get("last_form","")),Hexaco.sample(s.seed_value,int(s.depth)*10000+int(enemy.id),"essence_part",100),int(enemy.get("part_own_bonus",0)))
		enemy.part_kind = part
		var stone: String = Essences.canonical(Essences.base_of(id)+"/"+part+("@"+Essences.variant_element(id) if not Essences.variant_element(id).is_empty() else "")) if not Essences.part_of(id).is_empty() else id
		if Essences.absorbed(npc,stone): continue
		if Essences.bind(npc,stone).is_empty(): StatSheet.refresh_pools(s,npc)
