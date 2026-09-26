extends SceneTree
## Essences: the catalog every monster and caster leaves behind, absorbed once
## each (no tiers), the slots a level opens, and the drops a hunt yields.
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const Stats = preload("res://expedition/combat/combat_stats.gd")
const Spells = preload("res://expedition/spells/spells.gd")
const Hunt = preload("res://expedition/progression/hunt.gd")
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
	actives()
	print("Essences: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func catalog() -> void:
	for id in Essences.content.rows: check(Essences.has(id),"every catalog row is an essence: "+id)
	check(not Essences.has("PUSH") and not Essences.has("GUARD") and not Essences.has("BOMB"),"basic actions and retired boss parts are not soul stones")
	for id in Abilities.droppable():
		var row: Dictionary = Essences.row(id)
		check(str(row.role) in Essences.ROLES,"%s has a role tag" % id)
		check(str(row.species) == str(Abilities.DEFINITIONS[id].species),"%s belongs to its species" % id)
		check(not (row.stats as Dictionary).is_empty(),"%s gives base stats" % id)
	for school in Essences.CASTER_BY_SCHOOL:
		var id: String = str(Essences.CASTER_BY_SCHOOL[school])
		check(Essences.has(id) and Essences.school(id) == school,"%s gives the %s school" % [id,school])
		check(Essences.role(id) == ("PACK" if school == "air" else "CASTER"),"%s has its current role" % id)
		check(not Essences.title(id).is_empty(),"%s is named" % id)
	check(Essences.element("FIRE_CALLER") == "fire" and Essences.element("GOBLIN_HEXER") == "will","caster element tags follow the school")
	var variant: Dictionary = Essences.row("GOBLIN_SHIV@fire")
	check(variant.element == "fire" and int(variant.stats.res_fire) == 10 and int(variant.stats.atk) == 3,"a variant is the base plus its element")
	check(variant.role == "AMBUSH","a variant keeps the base role")
	check(Essences.title("GOBLIN_SHIV@fire").begins_with("화염"),"a variant's title names its element")
	check(not Essences.has("GOBLIN_SHIV@lava") and not Essences.has("NOPE") and not Essences.has(""),"unknown ids are not essences")
	check(Essences.stats("ORC_CLEAVER") == {"atk":4,"hp":8},"base stats are the role's, fixed")
	check(Essences.MAX_TIER == 1,"a stone has no tiers")
	check(Essences.spell_cap({"level":1}) == 1 and Essences.spell_cap({"level":6}) == 6 and Essences.spell_cap({"level":15}) == 10,"spell levels open up to the character's level")
	var source: String = FileAccess.get_file_as_string("res://expedition/progression/essences.gd")
	check(not ["func active_power","func tier(","func caster_tier"].any(func(word): return source.contains(word)),"no tier scaling is left")
	var actor := {"level":4,"equipped_abilities":["RAT_GNAW","",""],"essences":{}}
	check(Essences.absorbed(actor,"RAT_GNAW"),"a slotted essence nobody absorbed counts as held")
	check(not Essences.absorbed(actor,"ORC_CLEAVER"),"an unknown essence is not held")
	actor.essences = {"RAT_GNAW":1}
	check(Essences.absorbed(actor,"RAT_GNAW"),"an absorbed essence is held")
	check(Essences.equipped(actor) == [Essences.canonical("RAT_GNAW")],"empty slots are not essences")
	check(Essences.slot_count(actor) == 4 and Essences.slot_count({"level":15}) == 10 and Essences.slot_count({}) == 1,"slots follow the level, one to ten")

func sets() -> void:
	var actor := {"level":5,"essences":{},"equipped_abilities":["RAT_GNAW","RIVER_RAT_SPLASH","FIRE_CALLER","",""]}
	var counts: Dictionary = TagSets.counts(actor)
	check(int(counts.PACK) == 2 and int(counts.CASTER) == 1 and int(counts.fire) == 1,"roles and elements are counted apart")
	check(TagSets.level(actor,"PACK") == 2 and TagSets.level(actor,"CASTER") == 0,"two of a role reach the first bracket")
	actor.equipped_abilities[3] = "RAT_GNAW@ice"
	check(TagSets.level(actor,"PACK") == 2,"three of a role are still the two bracket")
	var active: Array = TagSets.active(actor)
	var pack: Array = active.filter(func(r): return r.tag == "PACK")
	check(pack.size() == 1 and int(pack[0].level) == 2 and int(pack[0].count) == 3 and int(pack[0].next) == 4 and str(pack[0].text).contains("공격력"),"the combo list carries count, next bracket and text")
	var guard := {"level":3,"essences":{},"equipped_abilities":["HOB_TAUNT","SHIELD_STANCE",""]}
	var bonus: Dictionary = TagSets.stat_bonus(guard)
	check(int(bonus.ac) == 2 and not bonus.has("sh"),"수호 2 gives armour two, block only from four")
	var burning := {"level":3,"essences":{},"equipped_abilities":["HOB_TAUNT@fire","SHIELD_STANCE@fire",""]}
	check(int(TagSets.stat_bonus(burning).res_fire) == 20,"화염 2 gives fire resistance")
	var casters := {"level":2,"essences":{},"equipped_abilities":["FIRE_CALLER","FROST_IMP"]}
	check(not TagSets.stat_bonus(casters).has("mp"),"술사 2 gives spell power, not MP")
	var hexers := {"level":2,"essences":{},"equipped_abilities":["GOBLIN_HEXER","GNOLL_SUMMONER"]}
	check(int(TagSets.stat_bonus(hexers).res_will) == 20,"의지 2 gives will")
	var ambush := {"level":3,"essences":{},"equipped_abilities":["GOBLIN_SHIV","GOBLIN_SHIV@fire","GOBLIN_SHIV@ice"]}
	check(TagSets.level(ambush,"AMBUSH") == 2 and not TagSets.stat_bonus(ambush).has("ev"),"기습 3 is the two bracket and lends no evasion")

func levels() -> void:
	var s = Session.new_run(731,"sword"); var hero: Dictionary = s.party[0]
	check(hero.equipped_abilities == [""],"a first-level hero has one slot")
	s.events.clear()
	check(s.gain_level_xp(hero,65) == 1 and hero.equipped_abilities.size() == 2,"level two opens a second slot")
	check(s.log_lines[-1] == "%s 레벨 2" % hero.name and not s.events.any(func(e): return e.kind == "LEVEL_UP"),"a level-up appears only in the log")
	s.gain_level_xp(hero,999999)
	check(int(hero.level) == 10 and hero.equipped_abilities.size() == 10,"level ten is the top, with ten slots")
	check(s.gain_level_xp(hero,999999) == 0,"nothing past ten")

func absorbing() -> void:
	var s = Session.new_run(731,"sword"); var hero: Dictionary = s.party[0]
	s.phase = "CAMP"
	s.parts_bag = {"ORC_CLEAVER":4}
	var hp: int = hero.max_hp
	check(s.absorb_essence(0,"ORC_CLEAVER") == "" and int(hero.essences[Essences.canonical("ORC_CLEAVER")]) == 1 and int(s.parts_bag[Essences.canonical("ORC_CLEAVER")]) == 3,"absorbing takes one from the bag")
	check(s.absorb_essence(0,"ORC_CLEAVER") == "이미 흡수함" and int(hero.essences[Essences.canonical("ORC_CLEAVER")]) == 1,"absorbing again is refused: no tiers")
	check(s.absorb_essence(0,"ORC_CLEAVER") == "이미 흡수함" and int(s.parts_bag[Essences.canonical("ORC_CLEAVER")]) == 3,"the copy stays in the bag for somebody else")
	check(s.absorb_essence(0,"GOBLIN_SHIV") == "가방에 없음","nothing absorbed from an empty bag")
	check(int(hero.max_hp) == hp,"absorbing alone changes no pool")
	check(s.equip_part(0,0,"ORC_CLEAVER") and hero.equipped_abilities == [Essences.canonical("ORC_CLEAVER")],"an absorbed essence fills a slot")
	check(int(hero.max_hp) == hp+8,"an orc stone is eight HP")
	check(not s.equip_part(0,1,"GOBLIN_SHIV"),"no second slot at level one")
	check(s.unequip_part(0,0) and hero.equipped_abilities == [""] and int(s.parts_bag[Essences.canonical("ORC_CLEAVER")]) == 3,"taking it off keeps it absorbed, not bagged")
	check(int(hero.max_hp) == hp and int(hero.essences[Essences.canonical("ORC_CLEAVER")]) == 1,"the pools drop, the stone stays absorbed")
	s.parts_bag["GOBLIN_SHIV"] = 1
	check(s.equip_part(0,0,"GOBLIN_SHIV") and int(hero.essences[Essences.canonical("GOBLIN_SHIV")]) == 1 and int(s.parts_bag[Essences.canonical("GOBLIN_SHIV")]) == 0,"equipping from the bag absorbs on the way")
	check(hero.rules.any(func(r): return r.skill == "GOBLIN_SHIV"),"a part essence brings its rule")
	s.phase = "BATTLE"
	s.parts_bag["RAT_GNAW"] = 1
	check(s.absorb_essence(0,"RAT_GNAW") == "전투 중" and not s.unequip_part(0,0),"nothing changes hands in a fight")
	check(Essences.put(hero,0,"ORC_CLEAVER") and hero.equipped_abilities[0] == Essences.canonical("ORC_CLEAVER"),"the unchecked put works mid-fight, for NPCs")
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
	var dropped_id: String = "GOBLIN_SHIV/"+str(foe.part_kind)
	check(int(s.parts_bag.get(dropped_id,0)) == 1,"the first kill drops its finishing-form part")
	check(s.essence_seen.has("goblin") and Essences.drop_chance(s,"goblin") == 25,"after that, one in four")
	check(not s.events.any(func(e): return e.kind == "ESSENCE") and s.log_lines[-1] == Essences.title(dropped_id)+" 획득","a new essence appears only in the log")
	s.parts_bag.clear()
	var dropped := 0
	for seed_value in range(40):
		var t = Session.new_run(seed_value,"sword")
		t.essence_seen["goblin"] = true; t.parts_bag.clear()
		var other: Dictionary = t.enemies[0]
		other.part_id = "GOBLIN_SHIV"; other.species_id = "goblin"
		t.damage(other,9999,int(t.party[0].id),"SLASH")
		for id in t.parts_bag:
			if Essences.base_of(str(id)) == "GOBLIN_SHIV": dropped += int(t.parts_bag[id])
	check(dropped > 0 and dropped < 40,"repeat drops are seeded, not certain (%d of 40)" % dropped)
	var npc_only = Session.new_run(733,"sword")
	npc_only.parts_bag.clear()
	var lone: Dictionary = npc_only.enemies[0]
	lone.part_id = "GOBLIN_SHIV"; lone.species_id = "goblin"; lone.hp = 0
	npc_only.roll_part(lone,[])
	check(npc_only.parts_bag.is_empty(),"a hunt without the party drops nothing into the bag")

func actives() -> void:
	var s = Session.new_run(731,"sword"); var hero: Dictionary = s.party[0]
	var club: Dictionary = Abilities.DEFINITIONS.ORE_SLAM
	hero.level = 1; hero.equipped_abilities = ["ORE_SLAM"]; hero.essences = {"ORE_SLAM":1}
	var base: int = int(club.damage)+maxi(0,StatSheet.value(s,hero,"str")-10)/2
	check(Abilities.power(s,hero,club,"ORE_SLAM") == base,"a part reads the current strength")
	hero.level = 5
	check(Abilities.power(s,hero,club,"ORE_SLAM") == base,"no tier: the stone hits as hard however long it is worn")
	check(Abilities.power(s,hero,club) == base,"without an id the part hits the same")
	var sling: Dictionary = Abilities.DEFINITIONS.KOBOLD_SLING
	hero.equipped_abilities = ["GOBLIN_SHIV"]; hero.essences = {"GOBLIN_SHIV":1}
	check(Abilities.power(s,hero,sling,"KOBOLD_SLING") == int(sling.damage)+maxi(0,StatSheet.value(s,hero,"dex")-10)/2,"a ranged part reads dexterity")
	var foe: Dictionary = s.enemies[0]
	check(Abilities.power(s,foe,club,"ORE_SLAM") == int(club.damage),"a monster hits for the listed damage")
	hero.skill_xp = {"sword":2500}
	hero.equipped_abilities = [""]; hero.essences = {}
	check(int(Stats.stats(s,hero).damage) == int(Stats.content.weapons.sword.damage)+2,"old sword mastery adds nothing any more")
	Hunt.record(hero,int(foe.id))
	check(hero.usage.has(int(foe.id)),"a strike marks the member as a hunter")
	check(s.hunt_recipients(foe,{}).has(hero),"and the hunt counts them")
	hero.essences = {"FIRE_CALLER":1}; hero.equipped_abilities = ["FIRE_CALLER"]
	var enc: int = int(Stats.stats(s,hero).enc)
	check(Spells.failure(s,hero,"fire_4") == clampi(8+4*9+enc*5-StatSheet.value(s,hero,"int")-10-4*int(hero.level),0,85),"failure reads mind, ten for a slotted stone of the school and four a level")
	s.manual_mode = false
	hero.essences = {"ORC_CLEAVER":1}; hero.equipped_abilities = ["ORC_CLEAVER"]
	check(StatSheet.legacy_power(hero,"MELEE",18) == 18,"the old auto path reads attribute points, which a stone no longer gives")
