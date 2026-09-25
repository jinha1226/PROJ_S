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

## Low A leans to 광폭·기습, high C to 수호, high O to 술사; a stone it has
## absorbed counts a little over one it has not.
static func preference(npc: Dictionary, id: String) -> int:
	var profile = npc.profile
	var score: int = 100 if Essences.absorbed(npc,id) else 0
	match str(Essences.role(id)):
		"BERSERK", "AMBUSH": score += 1000-int(profile.value("A"))
		"GUARD": score += int(profile.value("C"))
		"CASTER": score += int(profile.value("O"))
		_: score += PLAIN
	return score

## How many already chosen essences share a role or an element with `id`.
static func continuing(picked: Array, id: String) -> int:
	var count := 0
	for other in picked:
		var same_role: bool = not str(Essences.role(id)).is_empty() and Essences.role(id) == Essences.role(str(other))
		var same_element: bool = not str(Essences.element(id)).is_empty() and Essences.element(id) == Essences.element(str(other))
		if same_role or same_element: count += 1
	return count

## Greedy loadout: each slot takes the best-scoring essence left, scored with a
## bonus for every chosen essence it would make a set with. Ties go to the id.
static func choose(s, npc: Dictionary) -> void:
	Essences.sync_slots(npc)
	var count: int = Essences.slot_count(npc)
	var pool: Array = npc.get("essences",{}).keys()
	var picked: Array = []
	while picked.size() < mini(count,pool.size()):
		var best := ""; var best_score := -(1 << 30)
		for entry in pool:
			var id: String = str(entry)
			if id in picked: continue
			var score: int = preference(npc,id)+SET_BONUS*continuing(picked,id)
			if score > best_score or (score == best_score and id < best): best = id; best_score = score
		picked.append(best)
	for slot in range(count):
		if not str(npc.equipped_abilities[slot]).is_empty(): Essences.take(npc,slot)
	for slot in range(picked.size()):
		var id: String = picked[slot]
		Essences.put(npc,slot,id)
		if not str(Essences.school(id)).is_empty() and str(npc.get("essence_spells",{}).get(id,"")).is_empty():
			var choices: Array = Essences.spell_choices(npc,id)
			if not choices.is_empty(): npc.get_or_add("essence_spells",{})[id] = str(choices[choices.size()-1])
	Essences.sync_spells(npc)
	StatSheet.refresh_pools(s,npc)

## An independent NPC's own kill: the first of a species always gives its
## essence, later ones one time in four; then the loadout is chosen again.
static func on_hunt(s, enemy: Dictionary, hunters: Array) -> void:
	var id: String = str(enemy.get("part_id",""))
	if not Essences.has(id): return
	for npc in hunters:
		if npc in s.party or not bool(npc.get("npc",false)) or int(npc.hp) <= 0: continue
		var seen: Dictionary = npc.get_or_add("essence_seen",{})
		var species: String = Abilities.kind_key(enemy)
		if seen.has(species) and Hexaco.sample(s.seed_value,int(s.depth)*100000+int(enemy.id)*100+int(npc.id)%100,"npc_essence",100) >= DROP_PERCENT: continue
		seen[species] = true
		if Essences.absorbed(npc,id): continue
		npc.get_or_add("essences",{})[id] = 1
		choose(s,npc)
