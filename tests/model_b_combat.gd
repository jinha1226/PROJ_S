extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Stats = preload("res://expedition/combat_stats.gd")
const Rules = preload("res://expedition/combat_rules.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func duel(seed: int) -> Dictionary:
	var s = Session.new_run(seed)
	var center: Vector2i = Fixture.arena(s,8)
	var hero: Dictionary = s.party[0]
	var foe: Dictionary = s.enemies[0]
	foe.hp = 200; foe.max_hp = 200; foe.pos = center+Vector2i(1,0)
	foe.ev = 0; foe.ac = 0; foe.res = {}; foe.alert = true; foe.ready_at = 1000
	s.phase = "BATTLE"
	s.floor_state.observe(s)
	return {"s":s,"hero":hero,"foe":foe}

func run() -> void:
	var case := duel(311)
	var hero: Dictionary = case.hero
	var foe: Dictionary = case.foe
	var s = case.s
	var base: Dictionary = Stats.stats(s,hero)
	check(hero.gear.weapon.type == "sword" and hero.gear.armour.type == "robe","the hero starts with Model B sword and robe")
	check(base.damage == 12 and base.delay == 120 and base.ac == 1 and base.ev == 4,"starting equipment uses Model B numbers")
	check(Stats.stats(s,foe).ac == foe.ac and Stats.stats(s,foe).ev == foe.ev,"enemy stats use catalog values")
	hero.gear.armour = {"type":"mail","enchant":0}
	var mail: Dictionary = Stats.stats(s,hero)
	check(mail.ac > base.ac and mail.ev < base.ev and mail.enc > base.enc,"mail trades evasion for armour")
	hero.gear.weapon = {"type":"bow","enchant":0}
	check(Stats.stats(s,hero).range > 1 and Stats.stats(s,hero).trait == "ranged","bow changes range and trait")
	hero.gear.shield = {"type":"shield"}
	check(Stats.stats(s,hero).sh == 0,"two-handed bow cannot use shield")
	hero.gear.weapon = {"type":"sword","enchant":0}
	check(Stats.stats(s,hero).sh == 15,"melee weapon can use shield")
	hero.gear.armour = {"type":"robe","enchant":0}
	hero.gear.shield = {}
	var same := duel(311)
	var first: Dictionary = Rules.attack(s,hero,foe)
	var second: Dictionary = Rules.attack(same.s,same.hero,same.foe)
	check(first == second and foe.hp == same.foe.hp,"same seed and state produce identical attack")
	var armored := duel(311)
	armored.foe.ac = 10
	Rules.attack(armored.s,armored.hero,armored.foe)
	check(armored.foe.hp >= same.foe.hp,"armour cannot increase incoming damage")
	var wet: Vector2i = hero.pos+Vector2i(-1,0)
	s.tile(wet).terrain = "water"
	check(Rules.move_time(s,hero,wet) > Rules.move_time(s,hero,hero.pos+Vector2i(0,-1)),"water movement costs more ticks")
	var preview: Dictionary = same.s.attack_preview(same.foe.pos)
	check(preview.time == Stats.stats(same.s,same.hero).delay and preview.chance < 100,"attack preview uses tick delay and evasion")
	print("Model B combat: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
