extends SceneTree
func _init()->void:
	var failures:int=0
	var cases:={
		"test_elements.gd":["test_fire_and_electric_damage_use_common_damage_system","test_two_environment_ticks_apply_two_fire_and_wetness_steps","test_electric_distance_parent_arcs_and_cycle_single_damage"],
		"test_phase5_combat_status_lifecycle.gd":["test_canonical_active_fire_electric_damage_roundtrip_and_source_whitelist","test_typed_fire_electric_damage_three_way_schema_dispatch","test_canonical_downed_fire_electric_hazard_roundtrip_and_source_reason_forges"],
		"test_deterministic_dungeon_map.gd":["test_campaign_floor_one_and_two_publish_distinct_portals_and_authored_routes","test_solo_session_uses_large_map_los_memory_and_seeded_spawns","test_large_map_save_load_regenerates_seeded_layout_exactly"]}
	for file in cases:
		for method in cases[file]:
			var test=load("res://tests/"+str(file)).new()
			var result:Variant=test.call(str(method))
			if result!=true or not test.errors.is_empty():
				failures+=1;printerr(method,": ",test.errors)
			else:print("PASS ",method)
	print("Shared damage/maps: %d failures"%failures);quit(0 if failures==0 else 1)
