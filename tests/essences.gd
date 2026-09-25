extends SceneTree
## Essences: the catalog every monster and caster leaves behind, the tiers a
## member absorbs, the slots a level opens, and the drops a hunt yields.
const Session = preload("res://expedition/run/session.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	catalog()
	sets()
	levels()
	absorbing()
	drops()
	print("Essences: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func catalog() -> void:
	for id in Abilities.DEFINITIONS: check(Essences.has(id),"every part is an essence: "+id)
	for id in Abilities.droppable():
		var row: Dictionary = Essences.row(id)
		check(str(row.role) in Essences.ROLES,"%s has a role tag" % id)
		check(str(row.species) == str(Abilities.DEFINITIONS[id].species),"%s belongs to its species" % id)
		check(not (row.stats as Dictionary).is_empty(),"%s gives base stats" % id)
	for school in Essences.CASTER_BY_SCHOOL:
		var id: String = str(Essences.CASTER_BY_SCHOOL[school])
		check(Essences.has(id) and Essences.school(id) == school,"%s gives the %s school" % [id,school])
		check(Essences.role(id) == "CASTER","%s is a caster" % id)
		check(not Essences.title(id).is_empty(),"%s is named" % id)
	check(Essences.element("FIRE_CALLER") == "fire" and Essences.element("GOBLIN_HEXER") == "will","caster element tags follow the school")
	var variant: Dictionary = Essences.row("GOBLIN_SHIV@fire")
	check(variant.element == "fire" and int(variant.stats.res_fire) == 10 and int(variant.stats.dex) == 2,"a variant is the base plus its element")
	check(variant.role == "AMBUSH","a variant keeps the base role")
	check(Essences.title("GOBLIN_SHIV@fire").begins_with("화염"),"a variant's title names its element")
	check(not Essences.has("GOBLIN_SHIV@lava") and not Essences.has("NOPE") and not Essences.has(""),"unknown ids are not essences")
	check(int(Essences.stats("ORC_CLEAVER",1).str) == 2 and int(Essences.stats("ORC_CLEAVER",3).str) == 6,"base stats scale with the tier")
	check(int(Essences.stats("ORC_CLEAVER",9).str) == 6,"the tier stops at three")
	check(Essences.spell_cap(1) == 3 and Essences.spell_cap(2) == 6 and Essences.spell_cap(3) == 10,"spell level caps by tier")
	check(Essences.active_power(1,20) == 20 and Essences.active_power(2,20) == 25 and Essences.active_power(3,20) == 30,"active power +25% a tier")
	var actor := {"level":4,"equipped_abilities":["RAT_GNAW","",""],"essences":{}}
	check(Essences.tier(actor,"RAT_GNAW") == 1,"a slotted essence nobody absorbed counts as tier one")
	check(Essences.tier(actor,"ORC_CLEAVER") == 0,"an unknown essence has no tier")
	actor.essences = {"RAT_GNAW":3}
	check(Essences.tier(actor,"RAT_GNAW") == 3,"an absorbed essence has its own tier")
	check(Essences.equipped(actor) == ["RAT_GNAW"],"empty slots are not essences")
	check(Essences.slot_count(actor) == 4 and Essences.slot_count({"level":15}) == 10 and Essences.slot_count({}) == 1,"slots follow the level, one to ten")

func sets() -> void:
	var actor := {"level":5,"essences":{},"equipped_abilities":["RAT_GNAW","RIVER_RAT_SPLASH","FIRE_CALLER","",""]}
	var counts: Dictionary = TagSets.counts(actor)
	check(int(counts.PACK) == 2 and int(counts.CASTER) == 1 and int(counts.fire) == 1,"roles and elements are counted apart")
	check(TagSets.level(actor,"PACK") == 2 and TagSets.level(actor,"CASTER") == 0,"two of a tag switch a set on")
	actor.equipped_abilities[3] = "RAT_GNAW@ice"
	check(TagSets.level(actor,"PACK") == 3,"three of a tag is the second step")
	var active: Array = TagSets.active(actor)
	check(active.size() == 1 and active[0].tag == "PACK" and int(active[0].level) == 3 and str(active[0].text).contains("받는 피해"),"active sets carry their text")
	var guard := {"level":3,"essences":{},"equipped_abilities":["LIZARD_TAIL","HOB_CLUB",""]}
	var bonus: Dictionary = TagSets.stat_bonus(guard)
	check(int(bonus.ac) == 2 and int(bonus.sh) == 5,"수호 2 gives armour and block")
	var burning := {"level":3,"essences":{},"equipped_abilities":["LIZARD_TAIL@fire","HOB_CLUB@fire",""]}
	check(int(TagSets.stat_bonus(burning).res_fire) == 20,"화염 2 gives fire resistance")
	var casters := {"level":2,"essences":{},"equipped_abilities":["FIRE_CALLER","FROST_IMP"]}
	check(int(TagSets.stat_bonus(casters).mp) == 5,"술사 2 gives MP")
	var hexers := {"level":2,"essences":{},"equipped_abilities":["GOBLIN_HEXER","GNOLL_SUMMONER"]}
	check(int(TagSets.stat_bonus(hexers).res_will) == 20,"의지 2 gives will")
	var ambush := {"level":3,"essences":{},"equipped_abilities":["GOBLIN_SHIV","GOBLIN_SHIV@fire","GOBLIN_SHIV@ice"]}
	check(int(TagSets.stat_bonus(ambush).ev) == 5,"기습 3 gives evasion")

func levels() -> void:
	var s = Session.new_run(731,"sword"); var hero: Dictionary = s.party[0]
	check(hero.equipped_abilities == [""],"a first-level hero has one slot")
	s.events.clear()
	check(s.gain_level_xp(hero,65) == 1 and hero.equipped_abilities.size() == 2,"level two opens a second slot")
	check(s.events.any(func(e): return e.kind == "LEVEL_UP" and int(e.level) == 2 and int(e.actor) == int(hero.id)),"a level-up is announced")
	s.gain_level_xp(hero,999999)
	check(int(hero.level) == 10 and hero.equipped_abilities.size() == 10,"level ten is the top, with ten slots")
	check(s.gain_level_xp(hero,999999) == 0,"nothing past ten")

func absorbing() -> void:
	var s = Session.new_run(731,"sword"); var hero: Dictionary = s.party[0]
	s.phase = "CAMP"
	s.parts_bag = {"ORC_CLEAVER":4}
	var hp: int = hero.max_hp
	check(s.absorb_essence(0,"ORC_CLEAVER") == "" and int(hero.essences.ORC_CLEAVER) == 1 and int(s.parts_bag.ORC_CLEAVER) == 3,"absorbing takes one from the bag")
	check(s.absorb_essence(0,"ORC_CLEAVER") == "" and s.absorb_essence(0,"ORC_CLEAVER") == "" and int(hero.essences.ORC_CLEAVER) == 3,"absorbing again raises the tier")
	check(s.absorb_essence(0,"ORC_CLEAVER") == "최고 단계" and int(s.parts_bag.ORC_CLEAVER) == 1,"the fourth is refused and stays in the bag")
	check(s.absorb_essence(0,"GOBLIN_SHIV") == "가방에 없음","nothing absorbed from an empty bag")
	check(int(hero.max_hp) == hp,"absorbing alone changes no pool")
	check(s.equip_part(0,0,"ORC_CLEAVER") and hero.equipped_abilities == ["ORC_CLEAVER"],"an absorbed essence fills a slot")
	check(int(hero.max_hp) == hp+18,"a tier-three orc is six constitution")
	check(not s.equip_part(0,1,"GOBLIN_SHIV"),"no second slot at level one")
	check(s.unequip_part(0,0) and hero.equipped_abilities == [""] and int(s.parts_bag.ORC_CLEAVER) == 1,"taking it off keeps it absorbed, not bagged")
	check(int(hero.max_hp) == hp and int(hero.essences.ORC_CLEAVER) == 3,"the pools drop, the tier stays")
	s.parts_bag["GOBLIN_SHIV"] = 1
	check(s.equip_part(0,0,"GOBLIN_SHIV") and int(hero.essences.GOBLIN_SHIV) == 1 and int(s.parts_bag.GOBLIN_SHIV) == 0,"equipping from the bag absorbs on the way")
	check(hero.rules.any(func(r): return r.skill == "GOBLIN_SHIV"),"a part essence brings its rule")
	s.phase = "BATTLE"
	s.parts_bag["RAT_GNAW"] = 1
	check(s.absorb_essence(0,"RAT_GNAW") == "전투 중" and not s.unequip_part(0,0),"nothing changes hands in a fight")
	check(Essences.put(hero,0,"ORC_CLEAVER") and hero.equipped_abilities[0] == "ORC_CLEAVER","the unchecked put works mid-fight, for NPCs")
	check(Essences.take(hero,0) and hero.equipped_abilities[0] == "","and so does take")
	s.phase = "EXPLORE"
	check(Essences.can_manage(s) == s.floor_state.safe(s),"a quiet corridor counts as safe")

func drops() -> void:
	var s = Session.new_run(731,"sword"); var hero: Dictionary = s.party[0]
	s.essence_seen.clear(); s.events.clear(); s.parts_bag.clear()
	var foe: Dictionary = s.enemies[0]
	foe.part_id = "GOBLIN_SHIV"; foe.species_id = "goblin"
	check(Essences.drop_chance(s,"goblin") == 100,"the first goblin always leaves its essence")
	s.damage(foe,9999,int(hero.id),"SLASH")
	check(int(s.parts_bag.get("GOBLIN_SHIV",0)) == 1,"the first kill drops it")
	check(s.essence_seen.has("goblin") and Essences.drop_chance(s,"goblin") == 25,"after that, one in four")
	check(s.events.any(func(e): return e.kind == "ESSENCE" and e.id == "GOBLIN_SHIV" and bool(e.new)),"a new essence is announced")
	s.parts_bag.clear()
	var dropped := 0
	for seed_value in range(40):
		var t = Session.new_run(seed_value,"sword")
		t.essence_seen["goblin"] = true; t.parts_bag.clear()
		var other: Dictionary = t.enemies[0]
		other.part_id = "GOBLIN_SHIV"; other.species_id = "goblin"
		t.damage(other,9999,int(t.party[0].id),"SLASH")
		dropped += int(t.parts_bag.get("GOBLIN_SHIV",0))
	check(dropped > 0 and dropped < 40,"repeat drops are seeded, not certain (%d of 40)" % dropped)
	var npc_only = Session.new_run(733,"sword")
	npc_only.parts_bag.clear()
	var lone: Dictionary = npc_only.enemies[0]
	lone.part_id = "GOBLIN_SHIV"; lone.species_id = "goblin"; lone.hp = 0
	npc_only.roll_part(lone,[])
	check(npc_only.parts_bag.is_empty(),"a hunt without the party drops nothing into the bag")
