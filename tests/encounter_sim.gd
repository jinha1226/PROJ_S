extends SceneTree
const Session = preload("res://expedition/session.gd")
const Builder = preload("res://expedition/encounter_builder.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")
func rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new(); r.seed = seed_value; return r

func run() -> void:
	await rules_and_party()
	print("Encounter sim: %d failures" % failures); quit(1 if failures else 0)

func rules_and_party() -> void:
	for size in [1,2,3]:
		var s = Session.new(731,true,size > 1,true,size)
		check(s.party.size() == size and s.companions == (size > 1),"party_size %d builds %d members" % [size,size])
	var legacy = Session.new(731,true,true,true)
	check(legacy.party.size() == 2,"party_size 0 keeps the legacy rule")
	check(Session.new(731,true,false,true).rules_config == Session.DEFAULT_RULES,"default rules")
	var solo = Session.new(731,true,false,true,1); solo.depart()
	check(solo.action_budget(solo.party[0]) == 1,"default solo budget is one action")
	solo.rules_config = {"solo_actions":2,"solo_max_members":0}
	check(solo.action_budget(solo.party[0]) == 2,"solo_actions 2 doubles the budget")
	var duo = Session.new(731,true,true,true,2); duo.rules_config = {"solo_actions":2,"solo_max_members":0}; duo.depart()
	check(duo.action_budget(duo.party[0]) == 1,"solo_actions never applies to a party")
	# Two actions before the round advances.
	var c := Fixture.arena(solo,6)
	solo.party[0].ap = solo.action_budget(solo.party[0])
	var round_before: int = solo.round_number
	check(solo.act("WAIT",c) and solo.round_number == round_before and solo.party[0].ap == 1,"first action leaves the round open")
	check(solo.act("WAIT",c) and solo.round_number == round_before+1 and solo.party[0].ap == 2,"second action ends the round and refills")
	solo.rules_config = Session.DEFAULT_RULES.duplicate(); solo.party[0].ap = 1; round_before = solo.round_number
	check(solo.act("WAIT",c) and solo.round_number == round_before+1,"default rules end the round after one action")
	# max_members cap on fill.
	var seen_three := false; var capped_ok := true
	for seed_value in range(60):
		if Builder.fill(rng(seed_value),1,9,false).size() >= 3: seen_three = true
		if Builder.fill(rng(seed_value),1,9,false,2).size() > 2: capped_ok = false
	check(seen_three and capped_ok,"max_members caps fill at two")
