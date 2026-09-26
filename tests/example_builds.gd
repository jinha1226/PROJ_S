extends SceneTree
const Session = preload("res://expedition/run/session.gd")
const Builds = preload("res://expedition/progression/example_builds.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Equipment = preload("res://expedition/items/equipment.gd")
const Sets = preload("res://expedition/progression/tag_sets.gd")
var checks := 0
var failures := 0
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(why)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var s = Session.new_run(731); var hero: Dictionary = s.party[0]
	s.codex = {"version":1}; s.records_codex = true
	s.parts_bag = {"RAT_GNAW/cut":2}; s.essence_seen = {"dcss_rat":true}
	var bag: Dictionary = s.parts_bag.duplicate(true); var seen: Dictionary = s.essence_seen.duplicate(true)
	var hp_base: int = int(hero.max_hp)-int(hero.pool_bonus.get("hp",0))
	var mp_base: int = int(hero.max_mp)-int(hero.pool_bonus.get("mp",0))
	check(Builds.data.builds.size() == 11 and Builds.data.parties.size() == 4,"eleven builds and four parties")
	for b in Builds.data.builds:
		check(b.stones.size() == 10,"ten stones: "+str(b.id))
		check(b.stones.all(func(id): return Essences.has(str(id)) and Essences.canonical(str(id)) == str(id)),"canonical real stones: "+str(b.id))
		var unique := {}
		for id in b.stones: unique[id] = true
		check(unique.size() == 10,"unique stones: "+str(b.id))
		check(Equipment.content.weapons.has(b.weapon) and Equipment.content.armours.has(b.armour),"legal gear: "+str(b.id))
		check(str(b.offhand).is_empty() or Equipment.content.offhands.has(b.offhand),"legal offhand: "+str(b.id))
		check(Equipment.hands({"type":b.weapon}) != 2 or str(b.offhand).is_empty(),"two hand loadout: "+str(b.id))
		check(b.flow.size() >= 2,"flow documented: "+str(b.id))
		check(Builds.apply(s,hero,str(b.id)),"loadout applies: "+str(b.id))
		check(hero.level == 10 and Essences.equipped(hero).size() == 10,"ten usable slots: "+str(b.id))
		check(int(hero.max_hp)-int(hero.pool_bonus.hp) == hp_base+36 and int(hero.max_mp)-int(hero.pool_bonus.mp) == mp_base+18,"level-ten growth applied exactly once: "+str(b.id))
		check(Equipment.worn(hero).weapon.type == b.weapon and Equipment.worn(hero).armour.type == b.armour,"gear applied: "+str(b.id))
		check(Equipment.hands(Equipment.worn(hero).weapon) != 2 or Equipment.worn(hero).offhand.is_empty(),"switching clears offhand: "+str(b.id))
		var count: int = b.stones.filter(func(id): return Essences.role(str(id)) == b.group).size()
		check(Sets.bracket(hero,b.group) == Sets.bracket_of(count),"actual combo matches stones: "+str(b.id))
		check(s.parts_bag == bag and s.essence_seen == seen and s.codex == {"version":1} and not s.codex_dirty,"loadouts never record discoveries")
		for id in hero.essence_spells:
			check(str(hero.essence_spells[id]) in Essences.spell_choices(hero,str(id)),"spell is legal at ten")
		if not b.schools.is_empty(): check(not hero.prepared.is_empty(),"magic is prepared: "+str(b.id))
	for p in Builds.data.parties: check(p.members.size() == 3 and p.members.all(func(id): return not Builds.build(str(id)).is_empty()),"legal party: "+str(p.id))
	var before := hero.duplicate(true)
	check(not Builds.apply(s,hero,"unknown") and hero == before,"invalid build is a no-op")
	print("Example builds: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
