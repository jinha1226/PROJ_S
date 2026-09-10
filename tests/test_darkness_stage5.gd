extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const Simulator = preload("res://sim/simulator.gd")
const Command = preload("res://sim/sim_command.gd")
const VisualMap = preload("res://playtest/party_visual_test_map.gd")
const ItemOps = preload("res://sim/world_item_operations.gd")
const TorchRules = preload("res://sim/torch_rules.gd")
const VisionRules = preload("res://sim/vision_rules.gd")
const DarknessRules = preload("res://sim/darkness_stress_rules.gd")

func _dark_session(seed_value: int):
	var session = Session.new(seed_value, 20260828, VisualMap.SHOWCASE_SCENARIO_ID)
	session.sim.world.vision_scenario_id = VisionRules.DARK_TORCH_SCENARIO_ID
	return session

func _give_torch(session) -> String:
	var world = session.sim.world
	var hero_id := int(world.party_control_actor_id())
	var hero = world.entities[hero_id]
	var granted: Dictionary = ItemOps.commit_grant(world, hero_id, TorchRules.DEFINITION_ID,
		1, hero.position, "STAGE5_TEST")
	check(bool(granted.get("accepted", false)), "stage5 torch grant accepted")
	return str(granted.get("instance_id", ""))

func test_darkness_exposure_crosses_grace_and_emits_morale() -> bool:
	var session = _dark_session(751)
	var world = session.sim.world
	var hero_id := int(world.party_control_actor_id())
	for _i in range(4):
		var advanced: Dictionary = session._advance_item_action_time()
		check(bool(advanced.get("accepted", false)), "dark wait advances")
	var observed: Dictionary = DarknessRules.state(world, hero_id)
	check_eq(int(observed.exposure), 400, "dark exposure accumulates at the boundary")
	check(bool(observed.deep_dark), "fixture remains deeply dark without a torch")
	check(int(world.party_encounter.member(hero_id).stress) > 0,
		"exposure beyond grace reaches party morale")
	var darkness_events := 0
	var morale_events := 0
	for event in world.events:
		if event.type == DarknessRules.EVENT_EXPOSURE_CHANGED and event.actor_id == hero_id:
			darkness_events += 1
		if event.type == "party.morale_changed" and event.actor_id == hero_id:
			morale_events += 1
	check_eq(darkness_events, 4, "one exposure event per time boundary")
	check(morale_events >= 1, "darkness is represented in morale history")
	var validation_error: String = world.world_state_error()
	if not validation_error.is_empty():
		print("DARK_VALIDATION_DEBUG phase=%s contact_kind=%s enemy=%s events=%d" % [world.party_encounter.safe_phase, world.party_encounter.contact_kind, world.party_encounter.contact_enemy_id, world.events.size()])
	check_eq(validation_error, "", "darkness history validates")
	return finish()

func test_torch_removes_deep_dark_and_snapshot_preserves_exposure() -> bool:
	var session = _dark_session(752)
	var world = session.sim.world
	var hero_id := int(world.party_control_actor_id())
	for _i in range(4): session._advance_item_action_time()
	var before_torch := DarknessRules.state(world, hero_id)
	var instance_id := _give_torch(session)
	var equipped: Dictionary = session.equip_inventory_item(instance_id, TorchRules.EQUIP_SLOT)
	check(bool(equipped.get("accepted", false)), "stage5 torch equips: %s" % equipped)
	var ignited: Dictionary = session.ignite_torch(instance_id)
	check(bool(ignited.get("accepted", false)), "stage5 torch ignites: %s" % ignited)
	var lit_state := DarknessRules.state(world, hero_id)
	check(not bool(lit_state.deep_dark), "lit torch removes deep dark")
	check(int(lit_state.illumination) >= VisionRules.BRIGHT_THRESHOLD,
		"lit torch raises shared illumination")
	var after_ignite_exposure := int(lit_state.exposure)
	var lit_wait: Dictionary = session._advance_item_action_time()
	check(bool(lit_wait.get("accepted", false)), "lit wait advances: %s" % lit_wait)
	var after_wait := DarknessRules.state(world, hero_id)
	check(int(after_wait.exposure) <= after_ignite_exposure,
		"light prevents further dark exposure")
	var encoded: Dictionary = session.sim.snapshot()
	var restored = Simulator.from_snapshot(encoded)
	check(restored != null, "darkness snapshot loads")
	check_eq(DarknessRules.state(restored.world, hero_id),
		DarknessRules.state(world, hero_id), "darkness state survives snapshot")
	check_eq(restored.world.world_state_error(), "", "restored darkness history validates")
	var original_next = session.sim.step(Command.wait_for(100, hero_id))
	var restored_next = restored.step(Command.wait_for(100, hero_id))
	check(bool(original_next.accepted) and bool(restored_next.accepted),
		"original and restored darkness turns replay")
	check_eq(restored.snapshot(), session.sim.snapshot(),
		"snapshot replay remains deterministic after darkness")
	return finish()
