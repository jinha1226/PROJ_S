extends "res://tests/test_case.gd"

const Registry = preload("res://sim/growth_build_registry.gd")
const State = preload("res://sim/growth_build_state.gd")
const Session = preload("res://playtest/party_playtest_session.gd")
const Sandbox = preload("res://playtest/party_encounter_sandbox.gd")
const DropRegistry = preload("res://sim/species_drop_registry.gd")
const WorldState = preload("res://sim/world_state.gd")
const Species = preload("res://sim/species_catalog_registry.gd")
const WeaponRegistry = preload("res://sim/weapon_registry.gd")


func test_unified_catalog_owns_exact_stats_and_natural_weapon_cross_refs()->bool:
	check_eq(Species.registry_error(),"","unified species catalog validates")
	var expected:={
		"human":[{"STR":5,"DEX":5,"INT":5},"UNARMED_STRIKE"],
		"elf":[{"STR":3,"DEX":6,"INT":6},"UNARMED_STRIKE"],
		"dwarf":[{"STR":6,"DEX":4,"INT":5},"UNARMED_STRIKE"],
		"orc":[{"STR":7,"DEX":4,"INT":4},"UNARMED_STRIKE"],
		"beastkin":[{"STR":5,"DEX":7,"INT":3},"NATURAL_CLAW"],
		"generic_humanoid":[{"STR":5,"DEX":5,"INT":5},"UNARMED_STRIKE"],
		"goblin":[{"STR":4,"DEX":6,"INT":3},"UNARMED_STRIKE"],
	}
	for species_id in expected:
		var weapon_id:=Species.natural_weapon_id(species_id)
		check_eq([Species.base_stats(species_id),weapon_id],expected[species_id],
			"%s exact combat identity"%species_id)
		check(WeaponRegistry.has(weapon_id) \
			and bool(WeaponRegistry.definition(weapon_id).natural_weapon),
			"%s natural weapon cross-ref is natural"%species_id)
	return finish()


func test_player_registry_is_the_exact_five_species_contract() -> bool:
	check_eq(Registry.registry_error(), "", "growth registry validates")
	check_eq(Registry.species_ids(), ["beastkin", "dwarf", "elf", "human", "orc"],
		"player registry contains only the canonical five species")
	check_eq(Registry.picker_species_ids(), ["human", "elf", "dwarf", "orc", "beastkin"],
		"picker order is explicit and stable")
	for species_id in Registry.species_ids():
		var definition := Registry.species_definition(species_id)
		check_eq(definition.branches.size(), 2, "%s has two branches" % species_id)
		for branch in definition.branches:
			check_eq(branch.ranks.size(), 2, "%s/%s has two ranks" % [species_id,
				branch.branch_id])
		check(definition.weapon_familiarity.mode in ["ADAPTIVE", "FIXED"],
			"%s familiarity mode is explicit" % species_id)
	check_eq(Registry.species_definition("human").weapon_familiarity.mode, "ADAPTIVE",
		"human uses adaptive familiarity metadata")
	var expected:={
		"human":[["ADAPTATION","적응",["교차 훈련","빠른 재구성"]],
			["FIELDCRAFT","현장 기술",["현장 수리","자원 활용"]]],
		"elf":[["HUNTERS_EYE","사냥눈",["먼 시야","약점 관찰"]],
			["ARCANE_RESONANCE","이능 공명",["이능 감지","정밀 투사"]]],
		"dwarf":[["STONE_BODY","석체",["굳건한 자세","돌의 뼈"]],
			["ARTISAN_SENSE","장인 감각",["광맥 감지","충격 파쇄"]]],
		"orc":[["VANGUARD","선봉",["돌진 압박","전선 파괴"]],
			["RELENTLESS","불굴",["쇼크 억제","최후의 압박"]]],
		"beastkin":[["TRACKING","추적",["피냄새","끈질긴 추적"]],
			["WILD_MOBILITY","야생 기동",["험지 발놀림","사냥 도약"]]],
	}
	check_eq(Registry.picker_species_ids().map(func(species_id):
		return str(Registry.species_definition(species_id).fixed_trait.label)),
		["현장 대응","예리한 감각","치밀한 골격","강건한 근육·혈량","예민한 후각·청각"],
		"fixed trait identities are exact and non-duplicated")
	for species_id in Registry.picker_species_ids():
		var branches:Array=Registry.species_definition(species_id).branches
		for index in range(2):
			check_eq([branches[index].branch_id,branches[index].label,
				branches[index].ranks.map(func(rank):return str(rank.label))],expected[species_id][index],
				"%s branch authority is exact"%species_id)
	return finish()


func test_each_species_session_save_load_and_journal_replay_is_exact() -> bool:
	for species_id in Registry.picker_species_ids():
		var session=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID,species_id)
		check(session.sim!=null,"%s session creates"%species_id)
		if session.sim==null:continue
		var hero_id:int=session.sim.world.party_encounter.protagonist_id
		check_eq([session.player_species_id,session.sim.world.entities[hero_id].species_id,
			session.sim.world.party_encounter.protagonist_growth.species_id],
			[species_id,species_id,species_id],"%s identity reaches entity and growth"%species_id)
		var restored=Session.new(1,2,Session.SOLO_FIXTURE_SCENARIO_ID)
		var result:Dictionary=restored.load_session_json(session.save_session_json())
		check(bool(result.get("accepted",false)),"%s save loads"%species_id)
		if bool(result.get("accepted",false)):
			check_eq([restored.player_species_id,restored.sim.snapshot(),restored.command_journal],
				[species_id,session.sim.snapshot(),session.command_journal],
				"%s replay is exact"%species_id)
	return finish()


func test_picker_has_five_ordered_touch_targets_and_commits_once() -> bool:
	var session=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
	var sandbox=Sandbox.new();sandbox.size=Vector2(360,640)
	sandbox.initialize_for_headless_test(session)
	sandbox.show_species_picker_for_new_run()
	var ids:Array[String]=[]
	for child in sandbox.species_picker_buttons.get_children():
		ids.append(str(child.get_meta("species_id","")))
		check(child is Button and child.custom_minimum_size.y>=44.0,
			"picker button is a 44px touch target")
	check_eq(ids,["human","elf","dwarf","orc","beastkin"],
		"picker contains exactly five buttons in display order")
	var orc_button:=sandbox.species_picker_buttons.get_child(3) as Button
	orc_button.pressed.emit();orc_button.pressed.emit()
	check_eq([session.player_species_id,session.command_journal.size(),
		sandbox.species_picker_modal.visible],["orc",0,false],
		"one selection starts exactly one clean run and closes the modal")
	sandbox.free()
	return finish()


func test_old_growth_and_removed_species_are_rejected_but_goblin_monster_paths_remain() -> bool:
	var old_growth:Dictionary=State.new("human").to_dict();old_growth.schema_version=2
	check_eq(State.wire_error(old_growth),"unsupported_growth_build_schema",
		"old nested growth schema is rejected")
	var removed:Dictionary=State.new("human").to_dict();removed.species_id="am"+"phibian"
	check_eq(State.wire_error(removed),"unknown_growth_species",
		"removed player species state is rejected")
	check(not Registry.has_species("goblin") \
		and Registry.monster_family_for_species("goblin")=="GOBLINOID" \
		and DropRegistry.has_table("goblin"),
		"goblin stays in mutation-family and drop paths but not the player registry")
	return finish()


func test_old_session_world_party_and_growth_versions_reject_before_object_restore() -> bool:
	var source=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
	var wire:Dictionary=JSON.parse_string(source.save_session_json())
	wire.snapshot.snapshot_version=8
	check_eq(WorldState.snapshot_restore_error(wire.snapshot),"unsupported_snapshot_version",
		"v8 world wire is rejected by header preflight")
	var target=Session.new(77,88,Session.SOLO_FIXTURE_SCENARIO_ID)
	var before:Dictionary=target.sim.snapshot()
	var result:Dictionary=target.load_session_json(JSON.stringify(wire))
	check(not bool(result.get("accepted",false)) \
		and str(result.get("reason",""))=="unsupported_snapshot_version",
		"session raw preflight rejects v8 explicitly")
	check_eq(target.sim.snapshot(),before,"rejected v8 constructs no replacement world")
	var old_session:Dictionary=JSON.parse_string(source.save_session_json())
	old_session.session_format_version=4
	result=target.load_session_json(JSON.stringify(old_session))
	check(not bool(result.accepted) and result.reason=="invalid_party_session_wire",
		"session v4 rejects at outer wire preflight")
	check_eq(target.sim.snapshot(),before,"rejected session v4 replaces nothing")
	for pair in [["party",15],["growth",2]]:
		var old_nested:Dictionary=JSON.parse_string(source.save_session_json())
		if pair[0]=="party":old_nested.snapshot.party_encounter.schema_version=pair[1]
		else:old_nested.snapshot.party_encounter.protagonist_growth.schema_version=pair[1]
		result=target.load_session_json(JSON.stringify(old_nested))
		check(not bool(result.accepted) and result.reason=="unsupported_player_species_snapshot",
			"old %s schema rejects at nested raw preflight"%pair[0])
		check_eq(target.sim.snapshot(),before,"rejected %s schema replaces nothing"%pair[0])
	return finish()
