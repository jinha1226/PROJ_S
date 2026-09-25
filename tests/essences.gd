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
