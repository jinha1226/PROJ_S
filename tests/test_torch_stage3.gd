extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const Simulator = preload("res://sim/simulator.gd")
const VisualMap = preload("res://playtest/party_visual_test_map.gd")
const ItemOps = preload("res://sim/world_item_operations.gd")
const ItemRegistry = preload("res://sim/item_registry.gd")
const TorchRules = preload("res://sim/torch_rules.gd")
const VisionRules = preload("res://sim/vision_rules.gd")
const Sandbox = preload("res://playtest/party_encounter_sandbox.gd")

func _give_torch(session) -> String:
	var world = session.sim.world
	var hero_id := int(world.party_control_actor_id())
	var hero = world.entities[hero_id]
	var granted: Dictionary = ItemOps.commit_grant(world, hero_id, TorchRules.DEFINITION_ID,
		1, hero.position, "STAGE3_TEST")
	check(bool(granted.get("accepted", false)), "torch grant accepted")
	return str(granted.get("instance_id", ""))

func test_torch_registry_equip_ignite_and_dynamic_light() -> bool:
	check(ItemRegistry.has(TorchRules.DEFINITION_ID), "torch definition registered")
	var session = Session.new(731, 20260828, VisualMap.SOLO_FIXTURE_SCENARIO_ID)
	var world = session.sim.world
	var hero_id := int(world.party_control_actor_id())
	var instance_id := _give_torch(session)
	var equipped: Dictionary = session.equip_inventory_item(instance_id, TorchRules.EQUIP_SLOT)
	check(bool(equipped.get("accepted", false)), "torch equips in off hand")
	var before_time := int(world.world_time)
	var lit: Dictionary = session.ignite_torch(instance_id)
	check(bool(lit.get("accepted", false)), "torch ignites")
	check(int(world.world_time) > before_time, "ignition uses canonical action time")
	var torch_state: Dictionary = TorchRules.state(world, instance_id)
	check(bool(torch_state.get("lit", false)), "torch is lit")
	check_eq(int(torch_state.get("fuel_remaining", 0)), TorchRules.FUEL_DURATION,
		"fresh ignition retains full fuel")
	var lighting: Dictionary = VisionRules.lighting_for_world(world)
	check_eq((lighting.get("sources", []) as Array).size(), 1,
		"lit equipped torch contributes one shared light source")
	check_eq(int(lighting.sources[0].entity_id), hero_id, "light source follows torch carrier")
	var after_ignite_time := int(world.world_time)
	var advanced: Dictionary = session._advance_item_action_time()
	check(bool(advanced.get("accepted", false)), "canonical wait advances time")
	torch_state = TorchRules.state(world, instance_id)
	check_eq(int(torch_state.fuel_remaining), TorchRules.FUEL_DURATION -
		(int(world.world_time) - after_ignite_time), "fuel follows elapsed world time")
	var dark: Dictionary = {"ambient_level":VisionRules.DARK_AMBIENT,"sources":[]}
	var dark_without: Dictionary = VisionRules.observe(world, world.entities[hero_id].position,
		world.entities[hero_id].position + Vector2i(2, 0), Vector2i.RIGHT,
		VisionRules.profile_for("human"), dark)
	var dark_with: Dictionary = VisionRules.observe(world, world.entities[hero_id].position,
		world.entities[hero_id].position + Vector2i(2, 0), Vector2i.RIGHT,
		VisionRules.profile_for("human"), lighting)
	check(int(dark_with.observer_illumination) > int(dark_without.observer_illumination),
		"torch light changes shared illumination")
	var off: Dictionary = session.extinguish_torch(instance_id)
	check(bool(off.get("accepted", false)), "torch extinguishes")
	check(not bool(TorchRules.state(world, instance_id).lit), "extinguished torch has no light")
	return finish()

func test_torch_save_load_and_journal_replay_are_exact() -> bool:
	var session = Session.new(732, 20260828, VisualMap.SOLO_FIXTURE_SCENARIO_ID)
	var instance_id := _give_torch(session)
	check(bool(session.equip_inventory_item(instance_id, TorchRules.EQUIP_SLOT).accepted),
		"torch equips before save")
	check(bool(session.ignite_torch(instance_id).accepted), "torch ignites before save")
	var encoded: Dictionary = session.sim.snapshot()
	var restored = Simulator.from_snapshot(encoded)
	check(restored != null, "torch snapshot loads")
	check_eq(restored.snapshot(), encoded, "torch snapshot restores exactly")
	check_eq(TorchRules.state(restored.world, instance_id),
		TorchRules.state(session.sim.world, instance_id), "torch fuel/lit state replays exactly")
	return finish()


func test_top_hud_reports_equipped_torch_remaining_fuel() -> bool:
	var session=Session.new(733,20260828,VisualMap.SOLO_FIXTURE_SCENARIO_ID)
	var instance_id:=_give_torch(session)
	check(bool(session.equip_inventory_item(instance_id,TorchRules.EQUIP_SLOT).accepted),
		"torch equips for HUD")
	var sandbox=Sandbox.new();sandbox.size=Vector2(450,800)
	sandbox.initialize_for_headless_test(session,true)
	var off_spec:Dictionary=sandbox.expedition_hud_spec()
	check(str(off_spec.get("torch_text","")).begins_with("횃불 꺼짐"),
		"equipped unlit torch exposes remaining fuel")
	check(bool(session.ignite_torch(instance_id).accepted),"HUD torch ignites")
	sandbox._refresh()
	var lit_spec:Dictionary=sandbox.expedition_hud_spec()
	check(str(lit_spec.get("torch_text","")).begins_with("횃불 ") \
		and str(lit_spec.get("torch_band",""))=="LIT",
		"lit torch HUD exposes remaining duration")
	check(sandbox.torch_timer_label!=null and sandbox.torch_timer_label.visible \
		and sandbox.torch_timer_label.text==str(lit_spec.torch_text),
		"top rail renders torch duration")
	sandbox.free()
	return finish()


func test_torch_depletion_removes_light_and_blocks_reignite() -> bool:
	var session = Session.new(734, 20260828, VisualMap.SOLO_FIXTURE_SCENARIO_ID)
	var instance_id := _give_torch(session)
	check(bool(session.equip_inventory_item(instance_id, TorchRules.EQUIP_SLOT).accepted),
		"torch equips for depletion test")
	check(bool(session.ignite_torch(instance_id).accepted), "torch ignites for depletion test")
	session.sim.world.world_time += TorchRules.FUEL_DURATION
	var depleted:Dictionary=TorchRules.state(session.sim.world,instance_id)
	check(bool(depleted.get("depleted",false)), "elapsed fuel reaches depleted state")
	check(not bool(depleted.get("lit",true)), "depleted torch is no longer lit")
	check_eq(TorchRules.active_light_sources(session.sim.world).size(),0,
		"depleted torch contributes no dynamic light")
	check(not bool(session.ignite_torch(instance_id).get("accepted",false)),
		"depleted torch cannot be reignited")
	return finish()


func test_mobile_v_button_is_touch_sized_and_time_free() -> bool:
	var session = Session.new(735, 20260828, VisualMap.SHOWCASE_SCENARIO_ID)
	var sandbox = Sandbox.new()
	sandbox.size = Vector2(360, 640)
	sandbox.initialize_for_headless_test(session)
	check(sandbox.enemy_vision_overlay_button != null, "mobile V button exists")
	check(sandbox.enemy_vision_overlay_button.custom_minimum_size.x >= 44.0 \
		and sandbox.enemy_vision_overlay_button.custom_minimum_size.y >= 44.0,
		"mobile V button keeps touch target")
	var time_before := int(session.sim.world.world_time)
	sandbox._toggle_enemy_vision_overlay()
	check(sandbox.enemy_vision_overlay_enabled, "mobile V toggle enables overlay")
	check_eq(int(session.sim.world.world_time), time_before,
		"V overlay toggle does not advance world time")
	sandbox.free()
	return finish()


func test_inventory_equip_action_auto_ignites_fresh_torch() -> bool:
	var session = Session.new(736, 20260828, VisualMap.SOLO_FIXTURE_SCENARIO_ID)
	var instance_id := _give_torch(session)
	var sandbox = Sandbox.new()
	sandbox.size = Vector2(360, 640)
	sandbox.initialize_for_headless_test(session)
	sandbox.member_item_equip_button.set_meta("item_instance_id", instance_id)
	sandbox.member_item_equip_button.set_meta("item_slot", TorchRules.EQUIP_SLOT)
	sandbox.member_item_selected_id = instance_id
	sandbox._on_item_equip_selected()
	check(bool(TorchRules.state(session.sim.world, instance_id).get("lit", false)),
		"inventory equip action auto-ignites a fresh torch")
	check_eq(TorchRules.active_light_sources(session.sim.world).size(), 1,
		"auto-ignited equipped torch contributes a light source")
	sandbox.free()
	return finish()
