extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const Command = preload("res://sim/sim_command.gd")
const Action = preload("res://sim/party_action_command.gd")
const Request = preload("res://sim/party_turn_request.gd")
const Profile = preload("res://sim/personality_profile.gd")


func _engaged():
	var session = Session.new()
	var state = session.sim.world.party_encounter
	session.commit_exploration(Command.wait(state.protagonist_id))
	session.preview_deployment("WEDGE", state.party_member_ids.slice(1))
	check(session.commit_deployment().accepted, "fixture deploys the party")
	return session


func _profile(aggression: int, altruism: int, boldness: int, composure: int):
	return Profile.new("personality-facets-v1", [
		{"facet_id": "aggression", "base_value": aggression},
		{"facet_id": "altruism", "base_value": altruism},
		{"facet_id": "boldness", "base_value": boldness},
		{"facet_id": "composure", "base_value": composure},
	])


func test_preview_is_pure_and_repeatable_with_utility_suggestions() -> bool:
	var session = _engaged()
	var sim = session.sim
	var state = sim.world.party_encounter
	var request = Request.new(Action.hold(state.protagonist_id), [])
	var before := JSON.stringify(sim.world.snapshot())
	var first: Dictionary = sim.preview_party_turn(request).to_dict()
	var second: Dictionary = sim.preview_party_turn(request).to_dict()
	check_eq(first, second, "two previews are byte-identical")
	check_eq(JSON.stringify(sim.world.snapshot()), before, "preview mutates nothing")
	check(bool(first.accepted), "preview accepted: %s" % str(first.get("reason")))
	for row in first.actor_rows:
		if str(row.source) == "SUGGESTED":
			check(str(row.action.type) in ["HOLD", "MOVE", "MELEE"],
				"suggested leaf is a legal type")
	var result = sim.step_party_turn(sim.preview_party_turn(request))
	check(bool(result.accepted), "utility-suggested plan commits: %s" % str(result.reason))
	return finish()


func test_override_contract_and_explanation_agree_with_suggestion() -> bool:
	var session = _engaged()
	var sim = session.sim
	var state = sim.world.party_encounter
	var companion: int = state.active_party_member_ids[1]
	var request = Request.new(Action.hold(state.protagonist_id), [])
	var plan: Dictionary = sim.preview_party_turn(request).to_dict()
	var explanation: Dictionary = sim.party_coordinator.explain_companion_turn(request)
	check(bool(explanation.accepted), "explanation available while engaged")
	var plan_row: Dictionary = {}
	for row in plan.actor_rows:
		if int(row.actor_id) == companion:
			plan_row = row
	var explained: Dictionary = {}
	for row in explanation.companions:
		if int(row.actor_id) == companion:
			explained = row
	check_eq(explained.selected_leaf, plan_row.suggestion,
		"explanation leaf equals the plan suggestion")
	check(not explained.candidates.is_empty(), "candidates disclosed")
	for candidate in explained.candidates:
		check(candidate.has("score") and candidate.has("legal") \
			and candidate.has("considerations"), "candidate row shape")
	var overridden = Request.new(Action.hold(state.protagonist_id), [
		{"actor_id": companion, "action": Action.hold(companion)},
	])
	var override_plan: Dictionary = sim.preview_party_turn(overridden).to_dict()
	for row in override_plan.actor_rows:
		if int(row.actor_id) == companion:
			check_eq(str(row.source), "OVERRIDE", "override source kept")
			check_eq(row.suggestion, plan_row.suggestion,
				"raw suggestion preserved under override")
	return finish()


func test_personality_changes_boundary_choice_protect_vs_engage() -> bool:
	var session = _engaged()
	var sim = session.sim
	var world = sim.world
	var state = world.party_encounter
	var hero: int = state.protagonist_id
	var companion: int = state.active_party_member_ids[1]
	var enemy: int = state.enemy_ids[0]
	world.entities[enemy].position = world.entities[hero].position + Vector2i.RIGHT
	world.entities[hero].health = maxi(1, int(world.entities[hero].max_health / 4))
	world.entities[companion].position = world.entities[hero].position - Vector2i(1, 1)
	state.member(companion).personality_profile = _profile(100, 950, 500, 500)
	var altruist: Dictionary = sim.party_coordinator.explain_companion_turn(
		Request.new(Action.hold(hero), []))
	state.member(companion).personality_profile = _profile(950, 50, 900, 500)
	var brawler: Dictionary = sim.party_coordinator.explain_companion_turn(
		Request.new(Action.hold(hero), []))
	check_eq(_selected(altruist, companion), "PROTECT",
		"altruistic companion protects the pinned protagonist")
	check_eq(_selected(brawler, companion), "ENGAGE",
		"aggressive companion attacks the same enemy")
	return finish()


func test_wounded_panicked_companion_retreats() -> bool:
	var session = _engaged()
	var sim = session.sim
	var world = sim.world
	var state = world.party_encounter
	var companion: int = state.active_party_member_ids[1]
	var enemy: int = state.enemy_ids[0]
	world.entities[enemy].position = world.entities[companion].position + Vector2i.RIGHT
	world.entities[companion].health = maxi(1,
		int(world.entities[companion].max_health / 5))
	state.member(companion).stress = 900
	state.member(companion).mental_mode = "PANIC"
	var explanation: Dictionary = sim.party_coordinator.explain_companion_turn(
		Request.new(Action.hold(state.protagonist_id), []))
	check_eq(_selected(explanation, companion), "RETREAT", "hp 20% + stress 900 retreats")
	for row in explanation.companions:
		if int(row.actor_id) == companion:
			check_eq(row.mode, "PANIC", "mode disclosed as PANIC")
	return finish()


func _selected(explanation: Dictionary, actor_id: int) -> String:
	for row in explanation.companions:
		if int(row.actor_id) == actor_id:
			return str(row.selected_action_id)
	return ""
