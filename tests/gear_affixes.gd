extends SceneTree
const Fixture = preload("res://tests/followup_fixture.gd")
const Equipment = preload("res://expedition/items/equipment.gd")
const Effects = preload("res://expedition/progression/effect_engine.gd")
var checks := 0
var failures := 0
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(why)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var d := Fixture.reset(); var s = d.s
	check(Effects.validate(Effects.content).is_empty(),"gear shares the validated trigger schema: "+str(Effects.validate(Effects.content)))
	for pair in [[1,"bleed_tick",2],[2,"fracture_percent",15],[3,"crit_damage",50],[4,"stack_max",2],[5,"block",10],[6,"range",1],[7,"reaction_percent",40],[8,"status_ticks",25],[9,"poison_tick",2],[10,"summon_count",1],[11,"radius",1],[12,"heal_given_percent",30]]:
		d = Fixture.reset(s); d.hero.gear.ring1 = {"type":"power","affix":"GEAR_AMP_%d"%int(pair[0])}
		check(Effects.modifier(s,pair[1],d.hero,{"harmful":true}) == pair[2],"amplification %d reaches the runtime reader" % int(pair[0]))
	d = Fixture.reset(s); d.hero.gear.ring1 = {"type":"power","affix":"GEAR_AMP_8"}; d.foe.statuses = {"bleed":300,"weak":300,"marked":300}
	check(s.StoneEffects.outgoing(s,d.hero,d.foe,100,"physical") == 112,"curse amplifier scales actual damage by harmful status count")
	d = Fixture.reset(s); d.hero.gear.armour = {"type":"robe","affix":"GEAR_COMP_CRISIS"}; d.hero.hp = 20
	s.StoneEffects.round_start(s,d.hero)
	check(d.hero.statuses.has("ward"),"crisis protection activates")
	d.hero.statuses.erase("ward"); s.Reactions.begin_action(s); s.StoneEffects.round_start(s,d.hero)
	check(not d.hero.statuses.has("ward"),"crisis protection is once per fight")
	d = Fixture.reset(s); d.hero.gear.armour = {"type":"robe","affix":"GEAR_COMP_CLEANSE"}; s.StoneEffects.force = 0
	check(not s.Statuses.apply(s,d.hero,"weak",100,d.foe),"cleanse intercepts incoming harmful status")
	d = Fixture.reset(s); d.hero.gear.armour = {"type":"robe","affix":"GEAR_COMP_OPENING"}
	s.StoneEffects.fire(s,"BATTLE_START",{"actor":d.hero})
	check(s.StoneEffects.speed(s,d.hero) == 30,"opening speed lasts the first round")
	s.time = 100; check(s.StoneEffects.speed(s,d.hero) == 0,"opening speed expires after one hundred ticks")
	d = Fixture.reset(s); Fixture.slot(d.hero,["SPIDER_LEG"])
	s.StoneEffects.fire(s,"CRIT",{"source":d.hero,"target":d.foe})
	s.Reactions.begin_action(s)
	check(s.StoneEffects.speed(s,d.hero) == 30,"next-action speed survives other actors' action boundaries")
	s.act_as(d.hero,"WAIT",d.hero.pos,false)
	check(s.StoneEffects.speed(s,d.hero) == 0,"next-action speed is consumed by its owner")

	d = Fixture.reset(s); d.hero.gear.weapon = {"type":"sword","flaw":{"key":"noise","value":4}}
	d.foe.sleep_until = 500; d.foe.alert = false
	Equipment.attack_noise(s,d.hero)
	check(d.foe.sleep_until == 0 and d.foe.alert,"noisy weapon wakes sleeping enemies in its radius")
	d.hero.gear.weapon.props = [{"key":"accuracy","value":7},{"key":"crit_chance","value":5},{"key":"crit_damage","value":12}]
	check(s.StatSheet.value(s,d.hero,"accuracy") == 7 and s.StoneEffects.crit_chance(s,d.hero,d.foe) == 5 and s.StoneEffects.crit_percent(d.hero,s) == 162,"weapon properties reach stats and combat without duplicate counting")
	s.StoneEffects.force = -1
	print("Gear affixes: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
