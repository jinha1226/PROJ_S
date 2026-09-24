extends SceneTree
const Session = preload("res://expedition/session.gd")
const Mastery = preload("res://expedition/progression/mastery.gd")
const Effects = preload("res://expedition/progression/mastery_effects.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func run() -> void:
	var s = Session.new(902,false,false,true,2)
	var a: Dictionary = s.party[0]; var b: Dictionary = s.party[1]
	for pair in [[0,0],[25,1],[100,2],[225,3],[2500,10]]:
		a.skill_xp["sword"] = pair[0]
		check(Mastery.rank(a,"sword") == pair[1],"rank threshold %d" % pair[0])
	a.skill_xp["sword"] = 0
	check(Mastery.next_xp(2) == 225,"next XP")
	a.species_id = "elf"
	check(Mastery.aptitude(a,"sword") == 75,"elf melee aptitude applies to sword")
	a.species_id = "human"
	for i in range(3): Mastery.record(a,88,"sword")
	Mastery.record(b,88,"mace")
	Mastery.award([a,b],88,26)
	check(int(a.skill_xp.sword)+int(b.skill_xp.mace) == 26,"contribution distribution preserves XP")
	check(int(a.skill_xp.sword) == 20 and int(b.skill_xp.mace) == 6,"3:1 contribution assigns remainder deterministically")
	check(not a.usage.has(88) and not b.usage.has(88),"kill awards usage once")
	check(Mastery.catchup(a,"axe") and Mastery.required_xp(a,"axe",1) == 13 and Mastery.required_xp(a,"axe",2) == 50,"new weapon catches up through rank two")
	check(Mastery.rank(a,"axe") == 0,"catch-up grants no rank")
	a.skill_xp["sword"] = 2500; a.skill_xp["fire"] = 2500
	check(Mastery.unlocked(a,"sword").size() == 4 and Mastery.unlocked(a,"ice").is_empty(),"only implemented milestones unlock")
	check(Mastery.fusions(a).size() == 2,"both implemented fusions unlock")
	var fight = Session.new_run(903)
	var center: Vector2i = Fixture.arena(fight,8)
	var hero: Dictionary = fight.party[0]
	var foe: Dictionary = fight.enemies[0]
	hero.equipped_abilities = ["THROWING_KNIFE",""]
	foe.hp = 1; foe.max_hp = 1; foe.pos = center+Vector2i(2,0); foe.ready_at = 1000
	fight.phase = "BATTLE"; fight.floor_state.observe(fight)
	check(fight.submit("THROWING_KNIFE",foe.pos),"ranged part can land in manual combat")
	check(foe.hp == 0 and int(hero.skill_xp.get("bow",0)) == 26,"killing ranged part trains bow before XP award")
	hero.skill_xp["sword"] = 225; hero.skill_xp["fire"] = 625
	var adjacent: Dictionary = fight.enemies[1]
	adjacent.hp = 40; adjacent.max_hp = 40; adjacent.pos = foe.pos+Vector2i(0,1)
	Effects.on_spell_hit(fight,hero,foe,"fire")
	check(adjacent.hp < 40,"fire-sword fusion reaches an adjacent enemy even when the spell kills its target")
	var hp_before: int = hero.max_hp
	var mp_before: int = hero.max_mp
	check(fight.gain_level_xp(hero,65) == 1 and hero.max_hp == hp_before+4 and hero.max_mp == mp_before+2,"level XP raises HP by four and MP by two")
	print("Model B mastery: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
