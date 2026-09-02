extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const Command = preload("res://sim/sim_command.gd")


func test_wider_sighted_companion_reports_contact_before_protagonist() -> bool:
	var session = Session.new(7, 9)
	var world = session.sim.world
	var state = world.party_encounter
	var hero := int(state.protagonist_id)
	var spotter := int(state.party_member_ids[1])
	var enemy := int(state.enemy_ids[0])
	state.party_detection_radius = 2
	world.entities[spotter].tags.append("keen_sight")
	check_eq(_distance(world.entities[hero].position, world.entities[enemy].position), 4,
		"fixture enemy is outside protagonist range")
	var result: Dictionary = session.commit_exploration(Command.wait(hero))
	check(bool(result.get("accepted",false)), "companion sighting commits")
	check_eq(session.party_status().safe_phase, "CONTACT", "warning stops exploration")
	check_eq(session.party_status().contact_kind, "PARTY_AMBUSH",
		"shared sight gives the party first contact")
	var reports: Array = world.events.filter(func(event):
		return event.type == "party.contact_reported")
	check_eq(reports.size(), 1, "one sharing event is emitted")
	if not reports.is_empty():
		check_eq([reports[0].actor_id,reports[0].target_id], [spotter,enemy],
			"report names the real spotter and observed enemy")
		check_eq(reports[0].data.ruleset_id, "party-shared-perception-v1",
			"report owns the deterministic perception ruleset")
	var warning: Dictionary = session.party_status().contact_warning
	check(bool(warning.get("available",false)), "status exposes the automatic warning")
	check_eq(int(warning.get("spotter_id",-1)),spotter,"warning identifies the companion")
	check("경고했다" in str(warning.get("message","")),"warning has concise Korean copy")
	check_eq(world.world_state_error(), "", "shared perception world remains canonical")
	return finish()


func _distance(a:Vector2i,b:Vector2i)->int:
	return maxi(absi(a.x-b.x),absi(a.y-b.y))
