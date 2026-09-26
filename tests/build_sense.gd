extends SceneTree
const Fixture = preload("res://tests/followup_fixture.gd")
const Build = preload("res://expedition/ai/build_sense.gd")
var checks := 0
var failures := 0
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(why)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var d := Fixture.reset(); var s = d.s
	check(Build.profile(d.hero).is_empty() and Build.main(d.hero).is_empty(),"no effects means no build preference")
	check(Build.inputs(s,d.hero,{"kind":"ATTACK","cell":d.foe.pos,"damage":10}).values().all(func(v): return float(v) == 0),"no-build inputs preserve old decisions")
	Fixture.slot(d.hero,["LEECH_SEGMENT","LEECH_SUCKER","ORC_CLEAVER"])
	check(is_equal_approx(float(Build.profile(d.hero)[1]),2.0/3.0) and Build.main(d.hero) == [1,4],"build contribution normalizes and selects two dominant families")
	Fixture.slot(d.hero,["LEECH_SEGMENT","ORC_CLEAVER","SHIELD_STANCE","ARCHER_EYE"])
	check(Build.main(d.hero).is_empty(),"four diffuse builds do not create a false main build")
	Fixture.slot(d.hero,["ARCHER_EYE"]); d.hero.gear.ring1 = {"type":"power","affix":"GEAR_AMP_1"}; d.hero.gear.ring2 = {"type":"power","affix":"GEAR_AMP_1"}
	check(Build.main(d.hero).size() == 2 and is_equal_approx(float(Build.profile(d.hero)[1]),0.5),"duplicate gear amplification counts once in build profile")
	d.hero.gear.ring1 = {}; d.hero.gear.ring2 = {}; Fixture.slot(d.hero,["RAT_GNAW"]); d.hero.gear.weapon = {"type":"mace"}
	Fixture.slot(d.ally,["LEECH_SEGMENT"])
	check(Build.inputs(s,d.hero,{"kind":"ATTACK","cell":d.foe.pos,"damage":10}).build_setup == 0,"support build does not invent a bleeding capability")
	d.hero.gear.weapon = {"type":"sword"}
	check(Build.inputs(s,d.hero,{"kind":"ATTACK","cell":d.foe.pos,"damage":10}).build_setup == 1,"real slash attack can prepare ally bleed build")
	var before: Dictionary = d.hero.duplicate(true)
	Build.profile(d.hero); Build.inputs(s,d.hero,{"kind":"ATTACK","cell":d.foe.pos,"damage":10})
	check(d.hero == before,"build display preview does not mutate actor")
	Fixture.slot(d.hero,["LEECH_SEGMENT"])
	check(Build.main(d.hero) == [1],"changing equipment updates build without a stale battle cache")
	print("Build sense: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
