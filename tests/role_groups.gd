extends SceneTree
const Essences = preload("res://expedition/progression/essences.gd")
const Bestiary = preload("res://expedition/progression/bestiary.gd")
const Subtypes = preload("res://expedition/progression/subtypes.gd")
const EXPECTED := {"TANK":["LIZARD_TAIL","HOB_TAUNT","SHIELD_STANCE","BEETLE_CURL","SERPENT_SHED","SKELETON_WALL","THORN_ARMOUR","FURNACE_HEART"],"MELEE":["GOBLIN_SHIV","ORC_CLEAVER","GNOLL_SPEAR","RIVER_RAT_SPLASH","ORE_SLAM","LEECH_LATCH","GHOUL_CLAW","VAMPIRE_BITE"],"RANGED":["KOBOLD_SLING","STORM_BAT","GOBLIN_AIM","ORC_THROW","TOAD_SPIT","SKELETON_VOLLEY"],"MAGIC":["FIRE_CALLER","FROST_IMP","GNOLL_SUMMONER","GRAVEKEEPER","SOUL_EATER"],"SUPPORT":["RAT_GNAW","GOBLIN_HEXER","SPIDER_WEB","WATER_WAVE","WRAITH","GOBLIN_CHIEF"]}
var checks := 0
var failures := 0
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(why)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	check(Essences.ROLES == Subtypes.GROUP_NAMES,"five consistent role names")
	for role in EXPECTED:
		for id in EXPECTED[role]: check(Essences.role(id) == role,"species role "+id)
	for pair in [["TANK",{"hp":20,"ac":3}],["MELEE",{"atk":4,"hp":8}],["RANGED",{"atk":3,"speed":5}],["MAGIC",{"spell":4,"mp":8}],["SUPPORT",{"hp":10,"mp":6}]]:
		check(Bestiary.essence_stats(pair[0]) == pair[1],"base stats "+str(pair[0]))
	for old in ["PACK","BERSERK","AMBUSH","GUARD","ARCHER","CASTER"]: check(Bestiary.essence_stats(old).is_empty(),"no stone alias: "+old)
	var snapshot: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/monster_stats_before_role_groups.json"))
	for row in snapshot:
		var expected: Dictionary = row.stats
		for key in expected: expected[key] = int(expected[key])
		check(Bestiary.monster_stats(row.species,int(row.depth)) == expected,"unchanged monster %s floor %d" % [row.species,int(row.depth)])
	check(Essences.school("GOBLIN_HEXER") == "hex" and Essences.school("STORM_BAT") == "air","schools remain independent of role")
	print("Role groups: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
