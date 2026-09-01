extends "res://tests/test_case.gd"

const Registry = preload("res://sim/growth_build_registry.gd")
const State = preload("res://sim/growth_build_state.gd")
const Calculator = preload("res://sim/growth_build_calculator.gd")
const Item = preload("res://sim/item_instance.gd")
const Session = preload("res://playtest/party_playtest_session.gd")
const Command = preload("res://sim/sim_command.gd")
const Sandbox = preload("res://playtest/party_encounter_sandbox.gd")


func test_registry_has_four_species_two_rank_branches_and_four_hook_kinds() -> bool:
	check_eq(Registry.registry_error(), "", "growth registry validates")
	check_eq(Registry.species_ids(), ["amphibian", "dwarf", "goblin", "human"],
		"MVP has the four established species")
	check_eq([Registry.STAT_DEFINITIONS.MIGHT.label, Registry.STAT_DEFINITIONS.AGILITY.label,
		Registry.STAT_DEFINITIONS.VITALITY.label, Registry.SAVE_MIGRATION_POLICY],
		["완력", "기민", "활력", "HARD_CUT"], "recommended stat names and save cut are explicit")
	for species_id in Registry.species_ids():
		var definition := Registry.species_definition(species_id)
		check(not definition.fixed_trait.is_empty(), "%s has one fixed trait" % species_id)
		check_eq(definition.branches.size(), 2, "%s has two branches" % species_id)
		for branch in definition.branches:
			check_eq(branch.ranks.size(), 2, "%s/%s has two ranks" % [species_id, branch.branch_id])
	var triggers: Array[String] = []
	for mutation_id in Registry.mutation_ids():
		triggers.append(str(Registry.MUTATION_DEFINITIONS[mutation_id].effect.trigger))
	triggers.sort()
	check_eq(triggers, ["INTERACT", "ON_HIT", "ON_HURT", "PASSIVE"],
		"MVP mutation traces cover the four approved trigger kinds")
	check_eq([Registry.stat_points_for_level(2), Registry.stat_points_for_level(3),
		Registry.species_points_for_level(6), Registry.species_points_for_level(7),
		Registry.species_points_for_level(17)], [0, 1, 0, 1, 2],
		"recommended level gates are explicit")
	return finish()


func test_state_spending_hard_cut_wire_and_round_trip_are_deterministic() -> bool:
	var state = State.new("human")
	state.xp_total = Registry.xp_floor_for_level(17)
	check_eq([state.level(), state.stat_points_available(), state.species_points_available()],
		[17, 5, 2], "level retains XP and exposes both point ledgers")
	var result := state.commit_spend_stat_point("MIGHT")
	check(result.accepted, "available stat point spends")
	state = result.state
	result = state.commit_spend_species_point("ADAPTIVE_BODY")
	check(result.accepted, "level 7 species point buys rank one")
	state = result.state
	result = state.commit_spend_species_point("ADAPTIVE_BODY")
	check(result.accepted, "level 17 species point buys rank two")
	state = result.state
	check_eq([state.stat_allocations.MIGHT, state.species_branch_ranks.ADAPTIVE_BODY,
		state.species_points_available()], [1, 2, 0], "points are bounded and branch ranks are sequential")
	check_eq(state.commit_spend_species_point("FIELDCRAFT").reason,
		"no_growth_species_points", "one run cannot spend a third species point")
	var wire: Dictionary = state.to_dict()
	var json_wire: Dictionary = JSON.parse_string(JSON.stringify(wire))
	check_eq(State.wire_error(json_wire), "", "strict schema accepts its JSON wire")
	var restored = State.from_dict(json_wire)
	check(restored != null, "valid growth wire restores")
	if restored != null:
		check_eq(restored.to_dict(), wire, "growth round trip is exact")
	var forged: Dictionary = wire.duplicate(true); forged["legacy_training"] = []
	check_eq(State.wire_error(forged), "invalid_growth_build_keys",
		"hard cut rejects legacy/unknown fields")
	var overspent: Dictionary = wire.duplicate(true); overspent.stat_allocations[0].points = 99
	check_eq(State.wire_error(overspent), "growth_stat_points_overspent",
		"wire cannot forge level-gated stat points")
	return finish()


func test_first_eligible_family_kill_guarantees_trace_and_grouped_swap_costs_100() -> bool:
	var state = State.new("goblin")
	var result := state.commit_mutation_kill(10, "GOBLINOID", false, false)
	check(result.accepted and not result.acquired and result.reason == "mutation_kill_not_eligible",
		"unseen non-participated death is consumed without a trace")
	state = result.state
	result = state.commit_mutation_kill(11, "GOBLINOID", true, false)
	check(result.accepted and result.acquired and result.mutation_id == "PREDATOR_NERVE",
		"first damage-participated family kill guarantees its trace")
	state = result.state
	result = state.commit_mutation_kill(12, "GOBLINOID", false, true)
	check(result.accepted and not result.acquired and result.reason == "mutation_family_already_acquired",
		"later valid kill in the same family cannot duplicate the trace")
	state = result.state
	for row in [[13, "BEAST"], [14, "OOZE"], [15, "ABERRATION"]]:
		result = state.commit_mutation_kill(int(row[0]), str(row[1]), false, true)
		check(result.accepted and result.acquired, "LOS witness guarantees %s trace" % row[1])
		state = result.state
	check_eq(state.unlocked_mutation_ids,
		["CAUSTIC_BLOOD", "DEEP_EYE", "HIDE_PLATING", "PREDATOR_NERVE"],
		"unlocked traces use canonical order")
	var unsafe: Dictionary = state.commit_mutation_swap(0, "PREDATOR_NERVE", "ENGAGED")
	check(not unsafe.accepted and unsafe.time_cost == 0 and unsafe.reason == "mutation_swap_requires_grouped",
		"combat swap is an atomic no-op")
	for row in [[0, "PREDATOR_NERVE"], [1, "HIDE_PLATING"], [2, "CAUSTIC_BLOOD"]]:
		result = state.commit_mutation_swap(int(row[0]), str(row[1]), "GROUPED")
		check(result.accepted and result.time_cost == 100, "GROUPED slot swap costs exactly 100")
		state = result.state
	check_eq(state.equipped_mutation_ids,
		["PREDATOR_NERVE", "HIDE_PLATING", "CAUSTIC_BLOOD"], "three ordered slots are authoritative")
	check_eq(state.commit_mutation_swap(1, "PREDATOR_NERVE", "GROUPED").reason,
		"mutation_already_equipped", "one trace cannot occupy two slots")
	check_eq(State.wire_error(state.to_dict()), "", "kill and slot ledgers serialize strictly")
	return finish()


func test_dwarf_rare_sword_hide_and_predator_build_composes_without_changing_weapon_identity() -> bool:
	var state = State.new("dwarf")
	state.xp_total = Registry.xp_floor_for_level(17)
	for _rank in range(2):
		var branch_result := state.commit_spend_species_point("IRON_FRAME")
		check(branch_result.accepted, "iron frame rank spends")
		state = branch_result.state
	for row in [[20, "GOBLINOID"], [21, "BEAST"]]:
		var kill_result: Dictionary = state.commit_mutation_kill(int(row[0]), str(row[1]), true, false)
		check(kill_result.accepted and kill_result.acquired, "fixture trace acquired")
		state = kill_result.state
	for row in [[0, "PREDATOR_NERVE"], [1, "HIDE_PLATING"]]:
		var swap_result: Dictionary = state.commit_mutation_swap(int(row[0]), str(row[1]), "GROUPED")
		check(swap_result.accepted, "fixture trace equipped")
		state = swap_result.state
	var sword = Item.new("BUILD_SWORD", "WEAPON_SHORT_SWORD", 1, "RARE", ["GUARDED", "NIMBLE"])
	var armor = Item.new("BUILD_ARMOR", "ARMOR_LEATHER")
	var result := Calculator.calculate(state, {"ARMOR":armor, "MAIN_HAND":sword})
	check(result.accepted, "species/item/mutation build calculates")
	if result.accepted:
		var build: Dictionary = result.build
		check_eq(build.max_health, 156,
			"level HP, vitality and species branch combine without level damage scaling")
		check_eq(build.defense, {"armor_flat":6, "parry_milli":0, "dodge_milli":0,
			"stealth":0}, "item, affix, species and passive trace defense add exactly")
		check_eq(build.hazard_tolerance_bonuses.fire, 0,
			"dwarf heat tolerance and hide side effect compose")
		check_eq([build.weapon.weapon_id, build.weapon.range_min, build.weapon.range_max,
			build.weapon.attack_time, build.weapon.resolved_damage],
			["SHORT_SWORD", 1, 1, 100, 4],
			"weapon attack form timing/range remain item authority and level does not add damage")
		check("FORM_SLASH" in build.item_tags and "MELEE" in build.item_tags \
			and "AFFIX_GUARDED" in build.item_tags and "AFFIX_NIMBLE" in build.item_tags,
			"weapon and affix inputs become canonical build tags")
		check_eq(build.effect_hooks.ON_HIT.size(), 1,
			"predator mutation activates from the melee item tag")
		if build.effect_hooks.ON_HIT.size() == 1:
			check_eq([build.effect_hooks.ON_HIT[0].hook_id,
				build.effect_hooks.ON_HIT[0].bonuses.damage_flat],
				["WOUNDED_TARGET_BITE", 2], "on-hit rule remains conditional, not passive damage")
		check_eq(build.effect_hooks.ON_HURT[0].hook_id, "ON_HURT_NIMBLE_STEP",
			"reactive affix enters the shared hook output")
	var reversed := Calculator.calculate(state, {"MAIN_HAND":sword, "ARMOR":armor})
	check(reversed.accepted and result.build == reversed.build,
		"dictionary insertion order cannot change the deterministic build")
	return finish()


func test_species_item_mutation_matrix_and_tag_gates_are_stable() -> bool:
	var species_ids := ["human", "dwarf", "goblin", "amphibian"]
	var item_ids := ["WEAPON_SHORT_SWORD", "WEAPON_MACE", "WEAPON_SPEAR", "WEAPON_BOW"]
	var families := ["GOBLINOID", "OOZE", "ABERRATION", "BEAST"]
	var expected_mutations := ["PREDATOR_NERVE", "CAUSTIC_BLOOD", "DEEP_EYE", "HIDE_PLATING"]
	var signatures := {}
	for index in range(species_ids.size()):
		var state = State.new(species_ids[index])
		var kill := state.commit_mutation_kill(100 + index, families[index], index % 2 == 0,
			index % 2 == 1)
		check(kill.accepted and kill.acquired, "matrix valid kill guarantees trace")
		state = kill.state
		var swap: Dictionary = state.commit_mutation_swap(0, expected_mutations[index], "GROUPED")
		check(swap.accepted, "matrix trace equips")
		state = swap.state
		var item = Item.new("MATRIX_%d" % index, item_ids[index])
		var first := Calculator.calculate(state, {"MAIN_HAND":item})
		var second := Calculator.calculate(State.from_dict(state.to_dict()), {"MAIN_HAND":item})
		check(first.accepted and second.accepted and first.build == second.build,
			"%s x %s x %s is exact after state round trip" % [species_ids[index],
				item_ids[index], expected_mutations[index]])
		if first.accepted:
			check_eq(first.build.species_id, species_ids[index], "matrix preserves species identity")
			check_eq(first.build.equipped_mutation_ids[0], expected_mutations[index],
				"matrix preserves trace slot identity")
			signatures[JSON.stringify(first.build)] = true
	check_eq(signatures.size(), 4, "four triple-axis combinations remain observably distinct")
	var bow_state = State.new("human")
	var kill := bow_state.commit_mutation_kill(200, "GOBLINOID", true, false)
	bow_state = kill.state
	bow_state = bow_state.commit_mutation_swap(0, "PREDATOR_NERVE", "GROUPED").state
	var bow = Item.new("TAG_GATE_BOW", "WEAPON_BOW")
	var bow_build := Calculator.calculate(bow_state, {"MAIN_HAND":bow})
	check(bow_build.accepted and "MUTATION_PREDATOR_NERVE" in bow_build.build.inactive_effect_ids \
		and bow_build.build.effect_hooks.ON_HIT.is_empty(),
		"melee-required mutation stays inactive for a ranged item")
	var shield = Item.new("TAG_GATE_SHIELD", "SHIELD_WOOD")
	check_eq(Calculator.calculate(bow_state, {"MAIN_HAND":bow, "OFF_HAND":shield}).reason,
		"growth_two_handed_offhand_conflict", "existing two-handed item contract survives composition")
	return finish()


func test_session_kill_awards_growth_trace_and_replays_exactly() -> bool:
	var session=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
	var sandbox=Sandbox.new();sandbox.size=Vector2(360,640)
	sandbox.initialize_for_headless_test(session,true)
	var state=session.sim.world.party_encounter
	var hero_id:int=state.protagonist_id
	var enemy_id:int=state.enemy_ids[0]
	for _step in range(16):
		if session.party_status().safe_phase!="GROUPED":break
		var hero=session.sim.world.entities[hero_id]
		var enemy=session.sim.world.entities[enemy_id]
		var delta:Vector2i=enemy.position-hero.position
		if not session.commit_exploration(Command.move_to(hero_id,
				hero.position+Vector2i(signi(delta.x),signi(delta.y)))).accepted:break
	if session.party_status().safe_phase=="CONTACT":session.enter_solo_combat()
	for _turn in range(40):
		if str(session.sim.world.combatant_states[enemy_id].life_state)=="DEAD":break
		var hero=session.sim.world.entities[hero_id]
		var enemy=session.sim.world.entities[enemy_id]
		var delta:Vector2i=enemy.position-hero.position
		var result:Dictionary=session.commit_direct_solo_action(hero_id,"MELEE",[],enemy_id) \
			if maxi(absi(delta.x),absi(delta.y))<=1 \
			else session.commit_direct_solo_action(hero_id,"MOVE",
				[hero.position.x+signi(delta.x),hero.position.y+signi(delta.y)])
		if not bool(result.get("accepted",false)):break
	state=session.sim.world.party_encounter
	check_eq(str(session.sim.world.combatant_states[enemy_id].life_state),"DEAD",
		"actual party combat reaches one canonical enemy death")
	check_eq([state.protagonist_growth.xp_total,
		state.protagonist_growth.unlocked_mutation_ids],
		[100,["PREDATOR_NERVE"]],
		"one goblinoid kill mirrors XP and guarantees its first eligible trace")
	sandbox._update_direct_solo_card(session.party_cards())
	var level_label:=sandbox.find_child("LevelProgress",true,false) as Label
	var xp_gauge=sandbox.find_child("CompactXPBar",true,false)
	var xp_spec:Dictionary=xp_gauge.call("gauge_spec") if xp_gauge!=null \
		and xp_gauge.has_method("gauge_spec") else {}
	check(level_label!=null and "02" in level_label.text \
		and int(xp_spec.get("value",-1))==0 \
		and int(xp_spec.get("max_value",0))==150,
		"the killing turn refreshes LV2 and its next XP threshold instead of looking unchanged")
	var growth_rewards:Array=[]
	for event in session.sim.world.events:
		if event.type=="growth.enemy_reward":growth_rewards.append(event)
	check_eq(growth_rewards.size(),1,"one death emits one growth reward")
	var build:Dictionary=session.protagonist_growth_build()
	check(bool(build.get("available",false)) and build.level==2 \
		and "PREDATOR_NERVE" in build.unlocked_mutation_ids,
		"session facade composes live species, equipment and trace ownership")
	var inspected:Dictionary=session.inspect_party_member(hero_id)
	check_eq(inspected.get("growth_build",{}),build,
		"protagonist inspection exposes the same complete growth build")
	check_eq(session.sim.world.world_state_error(),"",
		"growth award preserves canonical world state")
	var restored=Session.new(1,2,Session.SOLO_FIXTURE_SCENARIO_ID)
	var loaded:Dictionary=restored.load_session_json(session.save_session_json())
	check(bool(loaded.get("accepted",false)),"growth kill state survives exact journal replay")
	if bool(loaded.get("accepted",false)):
		check_eq(restored.protagonist_growth_build(),build,
			"restored triple-axis build is byte-for-byte equivalent")
	sandbox.free()
	return finish()


func test_session_stat_spend_is_atomic_and_schema10_uses_hard_cut() -> bool:
	var session=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
	var state=session.sim.world.party_encounter
	var awarded:Dictionary=state.protagonist_growth.commit_award_xp(
		Registry.xp_floor_for_level(3))
	check(bool(awarded.accepted),"fixture reaches its first stat-point gate")
	state.protagonist_growth=awarded.state
	var start_time:int=session.sim.world.world_time
	var spent:Dictionary=session.spend_growth_stat_point("MIGHT")
	check(bool(spent.get("accepted",false)) and spent.time_cost==0 \
		and session.protagonist_growth_build().stats.MIGHT==6,
		"session spends a stat point without consuming world time")
	check_eq(session.sim.world.world_time,start_time,"stat allocation is a zero-time build decision")
	var before:Dictionary=session.sim.snapshot()
	var duplicate:Dictionary=session.spend_growth_stat_point("MIGHT")
	check(not bool(duplicate.get("accepted",false)) \
		and session.sim.snapshot()==before,"overspend rejection is an atomic no-op")

	var legacy_source=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
	var wire:Dictionary=JSON.parse_string(legacy_source.save_session_json())
	wire.snapshot.party_encounter.schema_version=10
	wire.snapshot.party_encounter.erase("protagonist_growth")
	var migrated=Session.new(1,2,Session.SOLO_FIXTURE_SCENARIO_ID)
	var migrated_result:Dictionary=migrated.load_session_json(JSON.stringify(wire))
	check(bool(migrated_result.get("accepted",false)),"schema 10 save migrates at the hard-cut boundary")
	if bool(migrated_result.get("accepted",false)):
		var growth=migrated.sim.world.party_encounter.protagonist_growth
		check_eq([growth.species_id,growth.xp_total,growth.unlocked_mutation_ids],
			["human",0,[]],"hard cut starts old expeditions from the species baseline")
	return finish()
