extends SceneTree
## Caster species, zone bosses, and floor-local monster stats.
const Session = preload("res://expedition/run/session.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Encounters = preload("res://expedition/level/encounter_builder.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Floor = preload("res://expedition/level/continuous_floor.gd")
const BossAI = preload("res://expedition/actors/boss_ai.gd")
const Zones = preload("res://expedition/level/zones.gd")
const Bestiary = preload("res://expedition/progression/bestiary.gd")
const StoneEffects = preload("res://expedition/progression/stone_effects.gd")
## species: [part, element, min depth, max depth]
const CASTERS := {
	"kobold_firecaller":["FIRE_CALLER","fire",4,6],
	"frost_imp":["FROST_IMP","ice",7,9],
	"storm_bat":["STORM_BAT","air",4,6],
	"goblin_hexer":["GOBLIN_HEXER","will",1,3],
	"gnoll_summoner":["GNOLL_SUMMONER","will",7,9]}
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	casters()
	bosses()
	deep()
	print("Caster species: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func casters() -> void:
	for species_id in CASTERS:
		var entry: Array = CASTERS[species_id]
		var row: Dictionary = Encounters.species(species_id)
		check(not row.is_empty(),"%s is in the monster table" % species_id)
		if row.is_empty(): continue
		check(int(row.min_depth) == int(entry[2]) and int(row.max_depth) == int(entry[3]),"%s appears on floors %d-%d" % [species_id,entry[2],entry[3]])
		check("CASTER" in row.roles,"%s can take the caster role" % species_id)
		var part: String = Abilities.species_part(species_id)
		check(part == str(entry[0]),"%s signature part is %s" % [species_id,entry[0]])
		var def: Dictionary = Abilities.definition(part)
		check(bool(def.get("monster_only",false)),"%s is a monster-only attack" % part)
		check(str(def.get("element","")) == str(entry[1]),"%s carries %s" % [part,entry[1]])
		check(StoneEffects.species_effect(species_id) == part and StoneEffects.EFFECTS.has(part),"%s's monsters carry their stone's headline effect" % part)
		check(int(def.damage) <= 14 and int(def.enemy.prep) == 1,"%s stays within floor-1 numbers" % part)
		check(Essences.has(part) and str(Essences.row(part).get("species","")) == species_id,"%s is the essence of %s" % [part,species_id])
	var s = Session.new_run(731)
	var hero: Dictionary = s.party[0]
	hero.equipped_abilities[0] = "FIRE_CALLER"
	check(not Abilities.holds(hero,"FIRE_CALLER") and not Abilities.usable_by(hero,"FIRE_CALLER"),"a party member never fires a caster's monster attack")
	var foe: Dictionary = s.enemies[0]
	foe.part_id = "FIRE_CALLER"
	check(Abilities.holds(foe,"FIRE_CALLER") and Abilities.usable_by(foe,"FIRE_CALLER"),"the monster fires it")
	var met: Dictionary = {}
	for seed_value in range(1,11):
		for depth in range(1,5):
			var run = Session.new_run(seed_value)
			run.depth = depth; run.floor_state.build(run)
			for enemy in run.enemies:
				if CASTERS.has(str(enemy.species_id)): met[str(enemy.species_id)] = true
	check(met.size() >= 3,"caster species turn up on the first floors (%d of 5 met)" % met.size())

func bosses() -> void:
	check(BossAI.KINDS == ["chief","golem","eater","fallen"],"one boss per zone")
	for kind in ["chief","golem","eater"]:
		var part: String = BossAI.ESSENCES[kind]
		check(Essences.has(part),"%s is an essence" % part)
		check(str(Essences.row(part).get("species","")) == BossAI.SPECIES[kind],"%s belongs to %s" % [part,BossAI.SPECIES[kind]])
		check(not Essences.row(part).get("stats",{}).is_empty(),"%s gives stats" % part)
	var s = Session.new_run(731)
	s.depth = 3; s.floor_state.build(s)
	var bosses: Array = s.enemies.filter(func(e): return e.get("boss",false))
	check(bosses.size() == 1,"the third floor has its boss")
	if bosses.is_empty(): return
	var boss: Dictionary = bosses[0]
	check(boss.part_id == "GOBLIN_CHIEF" and boss.species_id == "goblin_chief","the chief carries its essence")
	var count: int = int(s.parts_bag.get("GOBLIN_CHIEF",0))
	boss.hp = 1
	s.damage(boss,5,s.party[0].id,"physical")
	check(boss.hp <= 0 and int(s.parts_bag.get("GOBLIN_CHIEF",0)) == count+1,"a boss always leaves its essence")

func deep() -> void:
	check(Zones.zone_of(8) == 3 and Zones.zone_of(12) == 4,"depths use fixed zones")
	check(not Floor.theme_for(10).has("deep"),"themes no longer carry deep scaling")
	var s = Session.new_run(731)
	var member := {"species_id":"goblin","display_name":"고블린","max_health":28,"pos":Vector2i(1,1),"role":"MELEE"}
	s.depth = 8
	var shallow: Dictionary = Floor.mint_enemy(s,member,"T8","early",false)
	s.depth = 9
	var deeper: Dictionary = Floor.mint_enemy(s,member,"T9","early",false)
	check(int(shallow.attack_percent) == int(Bestiary.monster_stats("goblin",8).attack_percent) and int(deeper.attack_percent) == int(Bestiary.monster_stats("goblin",9).attack_percent),"monster power follows the zone-floor formula")
	check(int(deeper.max_hp) == int(Bestiary.monster_stats("goblin",9).hp) and int(deeper.hp) == int(deeper.max_hp),"monster health follows the zone-floor formula")
	check(Abilities.scaled(deeper,50) == 50*int(deeper.attack_percent)/100 and Abilities.scaled(shallow,50) == 50*int(shallow.attack_percent)/100,"parts use the monster's computed power")
	check(Bestiary.species("goblin").has("max_health"),"species owns its stats")
