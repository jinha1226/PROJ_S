extends SceneTree
## Caster species (spec §3.6), boss essences and deep-floor scaling (spec §5).
const Session = preload("res://expedition/run/session.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Encounters = preload("res://expedition/level/encounter_builder.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Floor = preload("res://expedition/level/continuous_floor.gd")
const BossAI = preload("res://expedition/actors/boss_ai.gd")
const Passives = preload("res://expedition/combat/passives.gd")
## species: [part, element, min depth, max depth]
const CASTERS := {
	"kobold_firecaller":["FIRE_CALLER","fire",1,4],
	"frost_imp":["FROST_IMP","ice",2,5],
	"storm_bat":["STORM_BAT","air",2,6],
	"goblin_hexer":["GOBLIN_HEXER","will",1,5],
	"gnoll_summoner":["GNOLL_SUMMONER","will",3,8]}
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
		check(str(def.passive.get("kind","")) in Passives.KINDS,"%s has a known passive" % part)
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
	check(BossAI.BOSS_PARTS == ["SHOCKWAVE","BOMB","IRON_HIDE"],"one essence per boss pattern")
	check(BossAI.BOSS_SPECIES == ["boss_mire","boss_bomber","boss_giant"],"one species per boss pattern")
	for i in range(3):
		var part: String = BossAI.BOSS_PARTS[i]
		check(Essences.has(part),"%s is an essence" % part)
		check(str(Essences.row(part).get("species","")) == BossAI.BOSS_SPECIES[i],"%s belongs to %s" % [part,BossAI.BOSS_SPECIES[i]])
		check(not Essences.row(part).get("stats",{}).is_empty(),"%s gives stats" % part)
	var s = Session.new_run(731)
	s.depth = 3; s.floor_state.build(s)
	var bosses: Array = s.enemies.filter(func(e): return e.get("boss",false))
	check(bosses.size() == 1,"the third floor has its boss")
	if bosses.is_empty(): return
	var boss: Dictionary = bosses[0]
	check(boss.part_id == "SHOCKWAVE" and boss.species_id == "boss_mire","the mire boss carries the mire essence")
	var count: int = int(s.parts_bag.get("SHOCKWAVE",0))
	boss.hp = 1
	s.damage(boss,5,s.party[0].id,"physical")
	check(boss.hp <= 0 and int(s.parts_bag.get("SHOCKWAVE",0)) == count+1,"a boss always leaves its essence")

func deep() -> void:
	check(Floor.last_catalog_depth() == 8,"the monster catalog ends on floor eight")
	check(Floor.deep_scale(8) == {"hp":100,"attack":100},"no scaling inside the catalog")
	check(Floor.deep_scale(9) == {"hp":112,"attack":108},"one floor past: +12% health, +8% attack")
	check(Floor.deep_scale(11) == {"hp":136,"attack":124},"three floors past: +36% health, +24% attack")
	check(Floor.theme_for(10).deep == Floor.deep_scale(10),"the theme carries the scaling")
	var s = Session.new_run(731)
	var member := {"species_id":"goblin","display_name":"고블린","max_health":28,"pos":Vector2i(1,1),"role":"MELEE"}
	s.depth = 8
	var shallow: Dictionary = Floor.mint_enemy(s,member,"T8","early",false)
	s.depth = 9
	var deeper: Dictionary = Floor.mint_enemy(s,member,"T9","early",false)
	check(int(shallow.get("attack_percent",100)) == 100 and int(deeper.attack_percent) == 108,"monsters past the catalog hit harder")
	check(int(deeper.max_hp) == int(shallow.max_hp)*112/100 and int(deeper.hp) == int(deeper.max_hp),"monsters past the catalog have more health")
	check(Abilities.scaled(deeper,50) == 54 and Abilities.scaled(shallow,50) == 50,"attack scaling applies to any amount")
	check(Abilities.power(s,deeper,Abilities.definition("GOBLIN_SHIV")) == int(Abilities.DEFINITIONS.GOBLIN_SHIV.damage)*108/100,"a deep monster's part hits harder")
