extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const Command = preload("res://sim/sim_command.gd")
const Item = preload("res://sim/item_instance.gd")
const Operations = preload("res://sim/item_inventory_operations.gd")
const DefenseRules = preload("res://sim/combat_defense_rules.gd")


func test_active_protagonist_equipment_freezes_dodge_armor_and_parry_in_canonical_history() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_FIXTURE_SCENARIO_ID)
	var world = session.sim.world
	var state = world.party_encounter
	var hero_id := int(state.protagonist_id)
	# The pure single-inventory kernel builds the fixture row, then one explicit
	# world swap installs it through the same revision and validation gate the
	# entity-addressed transactions use.
	var next_item_state = world.item_state.clone()
	var inventory = next_item_state.inventory(hero_id)
	for row in [
		Item.new("DEFENSE_SHIELD_001", "SHIELD_WOOD"),
		Item.new("DEFENSE_ARMOR_001", "ARMOR_LEATHER"),
		Item.new("DEFENSE_CHARM_001", "ACCESSORY_BRASS_CHARM"),
	]:
		var added := Operations.commit_add(inventory, row)
		check(bool(added.accepted), "defense fixture adds %s" % row.instance_id)
		if not bool(added.accepted): return finish()
		inventory = added.inventory
	for equipment in [["DEFENSE_SHIELD_001", "OFF_HAND"], ["DEFENSE_ARMOR_001", "ARMOR"],
			["DEFENSE_CHARM_001", "ACCESSORY_1"]]:
		var equipped := Operations.commit_equip(inventory, str(equipment[0]), str(equipment[1]))
		check(bool(equipped.accepted), "defense fixture equips %s" % equipment[1])
		if not bool(equipped.accepted): return finish()
		inventory = equipped.inventory
	next_item_state.inventory_rows[hero_id] = inventory
	next_item_state.revision += 1
	world.item_state = next_item_state
	check_eq(world.world_state_error(), "", "defense fixture installs a valid world row")
	var totals: Dictionary = world.equipment_modifiers(hero_id).totals
	check_eq(totals, {"armor_flat":1, "parry_milli":100, "dodge_milli":25,
		"stealth":0, "affix_hook_ids":[]}, "equipped totals are the v3 defense input")
	check(session.commit_exploration(Command.wait(hero_id)).accepted \
			and session.enter_solo_combat().accepted, "defense fixture reaches canonical solo combat")
	var parried_action = null
	for _turn in range(16):
		var result: Dictionary = session.commit_direct_solo_action(hero_id, "HOLD")
		check(bool(result.accepted), "holding permits the enemy defense test turn: %s" % str(result.reason))
		if not bool(result.accepted): break
		for event in world.events:
			if event.type == "action.melee_attack" and event.target_id == hero_id \
					and event.data.get("schema_version") == 3 \
					and event.data.get("outcome") == "PARRIED":
				parried_action = event
				break
		if parried_action != null: break
	check(parried_action != null, "100-milli shield parry reaches a canonical PARRIED action")
	if parried_action != null:
		var action = parried_action
		check_eq([action.data.equipment_armor_flat, action.data.equipment_dodge_milli,
			action.data.equipment_parry_milli], [1, 25, 100],
			"v3 action stores frozen equipment values separately from base combat values")
		var snapshot := DefenseRules.build_snapshot(int(action.data.target_base_evasion_milli),
			int(action.data.target_base_armor_flat), {"armor_flat":int(action.data.equipment_armor_flat),
			"dodge_milli":int(action.data.equipment_dodge_milli),
			"parry_milli":int(action.data.equipment_parry_milli)})
		check_eq([action.data.target_evasion_milli, action.data.armor_flat,
			action.data.final_damage, action.data.bleed_proc_succeeded, action.data.parry_succeeded],
			[int(snapshot.effective_evasion_milli), int(snapshot.effective_armor_flat), 0, false, true],
			"parry is a zero-damage no-bleed result after a dodge-aware hit roll")
		var parry_event = null
		for event in world.events:
			if event.type == "combat.attack_parried" and event.cause_id == action.id:
				parry_event = event
				break
		check(parry_event != null, "PARRIED produces one explicit non-damage result event")
		if parry_event != null:
			check_eq([parry_event.magnitude, parry_event.target_id, parry_event.data.outcome],
				[0, hero_id, "PARRIED"], "parry event leaves the protagonist life lane untouched")
	check_eq(world.world_state_error(), "", "v3 defense action and result survive strict canonical validation")
	return finish()
