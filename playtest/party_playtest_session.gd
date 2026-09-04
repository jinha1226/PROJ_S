class_name PartyPlaytestSession
extends RefCounted

const SimulatorScript = preload("res://sim/simulator.gd")
const CommandScript = preload("res://sim/sim_command.gd")
const PartyStateScript = preload("res://sim/party_encounter_state.gd")
const MemberScript = preload("res://sim/party_member_state.gd")
const ActionScript = preload("res://sim/party_action_command.gd")
const RequestScript = preload("res://sim/party_turn_request.gd")
const PartyHexacoScript = preload("res://sim/dungeon_population/hexaco_profile.gd")
const WorldStateScript = preload("res://sim/world_state.gd")
const Int64CodecScript = preload("res://sim/int64_codec.gd")
const TerrainRegistryScript = preload("res://sim/terrain_registry.gd")
const MovementSystemScript = preload("res://sim/systems/movement_system.gd")
const AffinityRegistryScript = preload("res://sim/species_hazard_affinity_registry.gd")
const ExplorationRouteScript = preload("res://playtest/party_exploration_route.gd")
const AutoExploreScript = preload("res://playtest/party_auto_explore.gd")
const VisualTestMapScript = preload("res://playtest/party_visual_test_map.gd")
const ProgressionRegistryScript=preload("res://sim/progression_registry.gd")
const ProgressionScript=preload("res://sim/protagonist_progression.gd")
const CombatProfileRegistryScript=preload("res://sim/combat_profile_registry.gd")
const WeaponRegistryScript=preload("res://sim/weapon_registry.gd")
const WeaponAttackRulesScript=preload("res://sim/weapon_attack_rules.gd")
const ActorStatRulesScript=preload("res://sim/actor_stat_rules.gd")
const CombatDefenseRulesScript=preload("res://sim/combat_defense_rules.gd")
const BodyFunctionRulesScript=preload("res://sim/body_function_rules.gd")
const PartyMoraleModelScript=preload("res://sim/party_morale_model.gd")
const EnemyAwarenessScript=preload("res://sim/enemy_awareness_state.gd")
const EnemyPerceptionRegistryScript=preload("res://sim/enemy_perception_registry.gd")
const EnemySquadBlackboardScript=preload("res://sim/enemy_squad_blackboard.gd")
const InventoryScript=preload("res://sim/inventory_state.gd")
const AmmoPoolScript=preload("res://sim/ammo_pool_state.gd")
const WeaponRuntimeScript=preload("res://sim/weapon_runtime_state.gd")
const GroundItemScript=preload("res://sim/ground_item_state.gd")
const ItemScript=preload("res://sim/item_instance.gd")
const ItemRegistryScript=preload("res://sim/item_registry.gd")
const ItemOperationsScript=preload("res://sim/world_item_operations.gd")
const RecoveryRulesScript=preload("res://sim/exploration_recovery_rules.gd")
const DeterministicDungeonMapScript=preload("res://playtest/deterministic_dungeon_map.gd")
const OpeningEventStateScript=preload("res://sim/opening_event_state.gd")
const OpeningHexacoScript=preload("res://sim/dungeon_population/hexaco_profile.gd")
const GrowthBuildStateScript=preload("res://sim/growth_build_state.gd")
const GrowthBuildRegistryScript=preload("res://sim/growth_build_registry.gd")
const GrowthBuildCalculatorScript=preload("res://sim/growth_build_calculator.gd")
const ContentDatabaseScript=preload("res://sim/content_database.gd")
const PartyCommandScript=preload("res://sim/party_exception_command.gd")
const AsciiStyleScript=preload("res://playtest/ascii_visual_style.gd")

const SESSION_FORMAT_VERSION := 5
const PRESENTATION_SCHEMA_VERSION := 1
const SAVE_PATH := "user://living_world_party_encounter_v3.json"
const DEFAULT_WORLD_SEED := 44
const DEFAULT_PERSONALITY_SEED := 20260828
const REGRESSION_SCENARIO_ID := "REGRESSION_V1"
const SHOWCASE_SCENARIO_ID := "SHOWCASE_V1"
const SOLO_COMBAT_SCENARIO_ID := "SOLO_COMBAT_V1"
const SOLO_FIXTURE_SCENARIO_ID := "SOLO_FIXTURE_V1"
const NEW_EXPEDITION_FACET_MIN := 100
const NEW_EXPEDITION_FACET_MAX := 899
const NEW_EXPEDITION_MIN_PROFILE_DISTANCE := 700
const NEW_EXPEDITION_SEED_LIMIT := 2147483646
const EXILE_WORLD_INTERVAL := 100
const EXILE_ENCOUNTER_STEP_DELAY := 5
const ACTIVE_PARTY_LIMIT := PartyStateScript.MAX_ACTIVE_PARTY_SIZE
const RESCUE_TIME_COST := 100
const RESCUE_AID_MAGNITUDE := 70
const RECRUITMENT_OFFER_TIME_COST := 100
const RECRUITMENT_RULESET_ID := "species-dominant-rescue-recruitment-v1"
const ITEM_ACTION_TIME_COST := 100
const OPENING_HEXACO_SLOT := 9242026
const OPENING_NPC_MAX_HEALTH := 90
const MAX_VISIBLE_HAZARD_DETOUR_STEPS := 4
# Product camera steps are a presentation contract shared with the sandbox.
# Keep the complete sequence here so adding a zoom level cannot leave the UI
# observer at a smaller, silently truncated capacity.
const PRODUCT_ZOOM_REFERENCE_CELL_COUNT := 15
# The visual target's 1.15x framing maps to 15 / 13 = 1.154x while retaining
# an odd cell count, so the protagonist remains centered on an exact grid cell.
# Nine cells gives the existing [+] control two closer steps beyond that target.
const PRODUCT_ZOOM_CELL_COUNTS := [9,11,13,15,17,19,21,23,25]
const PRODUCT_ZOOM_DEFAULT_CELL_COUNT := 13
const MAX_UI_VIEW_CELL_COUNT := PRODUCT_ZOOM_CELL_COUNTS[-1]
const HEXACO_LABELS := {
	"H":["실리적","원칙적"], "E":["대담함","섬세함"],
	"X":["과묵함","사교적"], "A":["직선적","온화함"],
	"C":["즉흥적","신중함"], "O":["현실적","탐구적"]}
const PARTY_MORALE_TRIGGER_PRESENTATION := {
	"SELF_DAMAGE":{"kind":"DISTRESS","label_ko":"직접 피해"},
	"SELF_DOWNED":{"kind":"DISTRESS","label_ko":"자신이 쓰러짐"},
	"ALLY_DOWNED":{"kind":"DISTRESS","label_ko":"동료가 쓰러짐"},
	"ALLY_DIED":{"kind":"DISTRESS","label_ko":"동료를 잃음"},
	"ENEMY_DIED":{"kind":"RELIEF","label_ko":"적을 쓰러뜨림"},
	"OVERRIDE_STRESS":{"kind":"DISTRESS","label_ko":"강제 지시 부담"},
	"ALLY_FEAR_CONTAGION":{"kind":"CONTAGION","label_ko":"가까운 동료의 공포"},
	"SAFE_RECOVERY":{"kind":"RECOVERY","label_ko":"안전한 곳에서 진정"},
}

var sim
var world_seed := DEFAULT_WORLD_SEED
var personality_seed := DEFAULT_PERSONALITY_SEED
var scenario_id := REGRESSION_SCENARIO_ID
var player_species_id := "human"
var command_journal: Array[Dictionary] = []
var _deployment_plan: Dictionary = {}
var _protagonist_draft = null
var _overrides: Dictionary = {}
var _draft_fingerprint := ""
var _exploration_route = null
var _auto_explore = null
var _protagonist_placeholder := false
var _map_layout: Dictionary = {}
var _opening_blood_positions:Array[Vector2i]=[]
# Presentation-only fog memory acceleration. Canonical events remain the sole
# authority: this cache is never serialized and is discarded whenever its
# world/history/topology identity no longer matches.
var _explored_presentation_cache: Dictionary = {}
var _presentation_topology_cache:Dictionary={}
# LOS is a pure function of the bootstrap-only topology, scenario and hero
# cell. AUTO asks it for the same post-hop cell while checking its stop gate
# and while refreshing the surface; keep that presentation work step-keyed and
# detached from canonical world state.
var _presentation_visibility_cache:Dictionary={}

func _combatant_status_ids(entity_id: int) -> Array[String]:
	var result: Array[String] = []
	if sim == null or sim.world == null: return result
	var combatant = sim.world.combatant_states.get(entity_id)
	if combatant == null: return result
	for row in combatant.status_rows: result.append(str(row.status_id))
	result.sort()
	return result

func _init(p_world_seed: int = DEFAULT_WORLD_SEED,
		p_personality_seed: int = DEFAULT_PERSONALITY_SEED,
		p_scenario_id: String = REGRESSION_SCENARIO_ID,
		p_player_species_id: String = "human") -> void:
	reset_party(p_world_seed, p_personality_seed, p_scenario_id, {}, true,
		p_player_species_id)


static func new_expedition_personality_seed(entropy_seed: int,
		avoid_seed: int = -1) -> int:
	# This function is deliberately pure. The UI supplies entropy once at the
	# new-expedition boundary; constructor, save/load, refresh and replay never
	# consult Time or an RNG. Existing explicit seeds remain byte-reproducible.
	var normalized := entropy_seed % NEW_EXPEDITION_SEED_LIMIT
	if normalized < 0: normalized += NEW_EXPEDITION_SEED_LIMIT
	for attempt in range(4096):
		var candidate := 1 + (normalized + attempt * 104729) % NEW_EXPEDITION_SEED_LIMIT
		if candidate == avoid_seed: continue
		if _new_expedition_seed_is_suitable(candidate): return candidate
	# The search space is intentionally generous; retain a deterministic fallback
	# rather than introducing a second nondeterministic draw if rules evolve.
	return 1 + (normalized + 4096 * 104729) % NEW_EXPEDITION_SEED_LIMIT


static func personality_style(profile) -> Dictionary:
	return {} if profile == null else profile.style_summary()


static func _hexaco_facet_rows(profile) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if profile == null: return rows
	for facet_id in PartyHexacoScript.FACETS:
		rows.append({"facet_id":facet_id,"base_value":int(profile.value(facet_id))})
	return rows


static func _new_expedition_seed_is_suitable(candidate_seed: int) -> bool:
	var profiles: Array = [PartyHexacoScript.generated(candidate_seed,2),
		PartyHexacoScript.generated(candidate_seed,3)]
	for profile in profiles:
		if profile == null: return false
		for facet_id in PartyHexacoScript.FACETS:
			var value := int(profile.value(facet_id))
			if value < NEW_EXPEDITION_FACET_MIN or value > NEW_EXPEDITION_FACET_MAX:
				return false
	var distance := 0
	for facet_id in PartyHexacoScript.FACETS:
		distance += absi(int(profiles[0].value(facet_id))-int(profiles[1].value(facet_id)))
	return distance >= NEW_EXPEDITION_MIN_PROFILE_DISTANCE

func reset_party(p_world_seed: int, p_personality_seed: int,
		p_scenario_id: String = REGRESSION_SCENARIO_ID,
		product_layout_override:Dictionary={},
		bootstrap_opening_event:bool=true,
		p_player_species_id:String="human") -> bool:
	if not ContentDatabaseScript.validation_error().is_empty():return false
	if not GrowthBuildRegistryScript.has_species(p_player_species_id):return false
	if not VisualTestMapScript.has_scenario(p_scenario_id): return false
	var product_dungeon := VisualTestMapScript.uses_product_dungeon(p_scenario_id)
	var map_layout: Dictionary = (product_layout_override.duplicate(true) \
		if product_dungeon and not product_layout_override.is_empty() \
		else (VisualTestMapScript.product_dungeon(p_world_seed) if product_dungeon else {}))
	if product_dungeon and map_layout.is_empty(): return false
	var world_width := int(map_layout.get("width", 15))
	var world_height := int(map_layout.get("height", 15))
	var candidate = SimulatorScript.create(world_width, world_height, p_world_seed)
	if candidate == null: return false
	var showcase := p_scenario_id == SHOWCASE_SCENARIO_ID
	var solo := p_scenario_id in [SOLO_COMBAT_SCENARIO_ID,
		SOLO_FIXTURE_SCENARIO_ID]
	var showcase_layout:=VisualTestMapScript.uses_showcase_layout(p_scenario_id)
	if showcase_layout and not VisualTestMapScript.apply_showcase_terrain(candidate.world): return false
	if showcase_layout and not VisualTestMapScript.apply_showcase_hazards(candidate.world): return false
	if product_dungeon and not VisualTestMapScript.apply_product_dungeon_terrain(
			candidate.world, map_layout): return false
	if product_dungeon and not VisualTestMapScript.apply_product_dungeon_hazards(
			candidate.world, map_layout): return false
	var hero_position: Vector2i = map_layout.get("hero_position",
		VisualTestMapScript.HERO_POSITION if showcase_layout else Vector2i(7,7))
	var narae_position := Vector2i(1,12) if showcase_layout else Vector2i(6,7)
	var miru_position := Vector2i(2,11) if showcase_layout else Vector2i(7,6)
	var generated_enemies: Array = map_layout.get("enemy_positions", [])
	var enemy_position: Vector2i = generated_enemies[0] if not generated_enemies.is_empty() \
		else (VisualTestMapScript.ENEMY_POSITION if showcase_layout else Vector2i(11,7))
	var hero_tags := ["party_member", "weapon_loadout"] if solo else ["party_member"]
	var protagonist = candidate.world.add_entity("hero", "주인공", hero_position, 120,
		hero_tags, p_player_species_id, "party")
	var narae = candidate.world.add_entity("companion", "나래", narae_position, 95,
		["party_member"], "human", "party") if not solo else null
	var miru = candidate.world.add_entity("companion", "미루", miru_position, 105,
		["party_member"], "goblin", "party") if not solo else null
	var candidate_dwarf = candidate.world.add_entity("companion", "보린", Vector2i(1,13), 110,
		["party_member", "recruitable"], "dwarf", "party") if showcase else null
	var candidate_beastkin = candidate.world.add_entity("companion", "세라", Vector2i(2,13), 90,
		["recruitable", "rescue_npc"], "beastkin", "neutral") if showcase else null
	var enemy_roster:Array=map_layout.get("enemy_roster",[]).duplicate(true)
	if enemy_roster.is_empty():
		for generated_position in generated_enemies:
			enemy_roster.append({"position":generated_position,"species_id":"goblin"})
	if enemy_roster.is_empty():enemy_roster=[{"position":enemy_position,"species_id":"goblin"}]
	var enemies:Array=[]
	for enemy_row_value in enemy_roster:
		var enemy_row:Dictionary=enemy_row_value
		var enemy_profile:Dictionary=EnemyPerceptionRegistryScript.profile(
			str(enemy_row.get("species_id","goblin")))
		if enemy_profile.is_empty():return false
		var spawn_position:Vector2i=enemy_row.get("position",Vector2i(-1,-1))
		var spawned=candidate.world.add_entity(str(enemy_profile.entity_kind),
			str(enemy_profile.display_name),spawn_position,int(enemy_profile.max_health),
			["party_enemy"],str(enemy_profile.species_id),"enemy",
			"GOBLIN_MELEE_V1" if str(enemy_profile.species_id)=="goblin" else "")
		if spawned==null:return false
		enemies.append(spawned)
	var opening_state = null
	var opening_blood_positions:Array[Vector2i]=[]
	var opening_enabled := p_scenario_id == SOLO_COMBAT_SCENARIO_ID \
		and bootstrap_opening_event
	if opening_enabled:
		var anchors: Dictionary = DeterministicDungeonMapScript.opening_event_anchors(
			map_layout, p_world_seed)
		if anchors.is_empty(): return false
		var opening_entity = candidate.world.add_entity("companion",
			"부상당한 여행자", anchors.spawn_position, OPENING_NPC_MAX_HEALTH,
			["opening_event_npc"], "elf", "neutral")
		if opening_entity == null: return false
		opening_entity.health = maxi(1, int((opening_entity.max_health + 4) / 5))
		var profile = OpeningHexacoScript.generated(p_world_seed, OPENING_HEXACO_SLOT)
		opening_state = OpeningEventStateScript.new(opening_entity.id, profile,
			anchors.spawn_position, anchors.convergence_band, anchors.convergence_goal)
		opening_blood_positions=_opening_blood_trail(anchors)
		var discovery = candidate.world.emit_event("opening.npc_discovered", -1,
			opening_entity.id, opening_entity.position, 0, -1,
			{"schema_version":1, "state":"WOUNDED", "non_hostile":true,
				"position":[opening_entity.position.x, opening_entity.position.y],
				"hexaco_slot":OPENING_HEXACO_SLOT,
				"hexaco_profile":profile.to_dict(),
				"convergence_goal":[anchors.convergence_goal.x,
					anchors.convergence_goal.y]})
		if discovery == null: return false
	if protagonist == null or enemies.is_empty() or (not solo and (narae == null or miru == null)) \
			or (showcase and (candidate_dwarf == null or candidate_beastkin == null)):
		return false
	_configure_party_species_relations(candidate)
	# The rescue story is authoritative event history, but it deliberately does
	# not impersonate combat DOWNED. The world NPC stays ACTIVE and occupies its
	# canonical cell until an accepted offer converts the same entity to GROUPED.
	if showcase and not _bootstrap_rescue_candidate(candidate,
			candidate_beastkin.id):
		return false
	var state = PartyStateScript.new(); state.protagonist_id = protagonist.id
	state.opening_event = opening_state
	state.party_member_ids.append(protagonist.id)
	if not solo:state.party_member_ids.append_array([narae.id, miru.id])
	if showcase: state.party_member_ids.append(candidate_dwarf.id)
	for enemy_entity in enemies:state.enemy_ids.append(enemy_entity.id)
	if VisualTestMapScript.uses_los_fov(p_scenario_id):
		# Product-map objectives stay traversable even while monsters patrol. This
		# reservation is authoritative state so save/load and journal replay do not
		# need presentation-only map knowledge to reproduce patrol choices.
		var manifest := VisualTestMapScript.run_manifest(p_scenario_id, map_layout)
		var reserved_values: Array = [
			Vector2i(int(manifest.exit.position[0]), int(manifest.exit.position[1])),
			Vector2i(int(manifest.entry.position[0]), int(manifest.entry.position[1])),
		]
		reserved_values.append_array(map_layout.get("door_positions", []))
		# Preserve the three historical reservation cells for v1/v2 SOLO saves.
		# They are inert on generated walls but keep schema migration exact.
		reserved_values.append_array([VisualTestMapScript.EXIT_POSITION,
			VisualTestMapScript.OPEN_DOOR_POSITION, VisualTestMapScript.ENTRY_POSITION])
		for reserved_position in reserved_values:
			if candidate.world.in_bounds(reserved_position) \
					and reserved_position not in state.patrol_reserved_positions:
				state.patrol_reserved_positions.append(reserved_position)
		var gateway_values: Array = map_layout.get("door_positions", []).duplicate()
		if showcase_layout:
			gateway_values.append(VisualTestMapScript.OPEN_DOOR_POSITION)
		for gateway_position in gateway_values:
			if candidate.world.in_bounds(gateway_position) \
					and gateway_position not in state.diagonal_gateway_positions:
				state.diagonal_gateway_positions.append(gateway_position)
	state.active_party_member_ids.clear()
	state.active_party_member_ids.append(protagonist.id)
	if not solo:state.active_party_member_ids.append_array([narae.id, miru.id])
	state.group_anchor = protagonist.position
	state.party_detection_radius = 3 if VisualTestMapScript.uses_los_fov(p_scenario_id) \
		else 4; state.enemy_detection_radius = 3
	state.member_rows[protagonist.id] = MemberScript.new(protagonist.id, 0, "PROTAGONIST", "DEPLOYED", null)
	if not solo:
		state.member_rows[narae.id] = MemberScript.new(narae.id, 1, "COMPANION", "GROUPED", PartyHexacoScript.generated(p_personality_seed, narae.id))
		state.member_rows[miru.id] = MemberScript.new(miru.id, 2, "COMPANION", "GROUPED", PartyHexacoScript.generated(p_personality_seed, miru.id))
	if showcase:
		state.member_rows[candidate_dwarf.id] = MemberScript.new(candidate_dwarf.id, 3,
			"COMPANION", "RECRUITABLE", PartyHexacoScript.generated(p_personality_seed, candidate_dwarf.id))
	for enemy_entity in enemies:
		state.enemy_busy_rows[enemy_entity.id]=0
		state.enemy_awareness_rows[enemy_entity.id]=EnemyAwarenessScript.new(
			enemy_entity.id,enemy_entity.position)
	# The same starting instances, quantities and slots as before, now owned by the
	# canonical world item state instead of the party encounter.
	candidate.world.item_state.inventory_rows[protagonist.id]=InventoryScript.new([
		ItemScript.new("LEGACY_MAIN_HAND",ItemRegistryScript.weapon_definition_id("SHORT_SWORD")),
		ItemScript.new("START_HAND_AXE_001",ItemRegistryScript.weapon_definition_id("HAND_AXE")),
		ItemScript.new("START_MACE_001",ItemRegistryScript.weapon_definition_id("MACE")),
		ItemScript.new("START_SPEAR_001",ItemRegistryScript.weapon_definition_id("SPEAR")),
		ItemScript.new("START_BOW_001",ItemRegistryScript.weapon_definition_id("BOW")),
		ItemScript.new("START_CROSSBOW_001",ItemRegistryScript.weapon_definition_id("CROSSBOW")),
		ItemScript.new("START_POTION_001","POTION_HEALING",3)],
		{"MAIN_HAND":"LEGACY_MAIN_HAND"})
	# The historical start loadout, now stated once: 12 arrows, 6 bolts and an
	# unloaded crossbow instance. The equipped MAIN_HAND item is the weapon.
	candidate.world.item_state.ammo_pool_rows[protagonist.id]=AmmoPoolScript.new(12,6)
	candidate.world.item_state.weapon_runtime_rows["START_CROSSBOW_001"]=WeaponRuntimeScript.new(
		"START_CROSSBOW_001",false)
	state.protagonist_progression.training_modes=ProgressionRegistryScript.initial_training_modes("SWORD")
	state.protagonist_growth=GrowthBuildStateScript.new(str(protagonist.species_id))
	candidate.world.item_state.ground_items=GroundItemScript.new(_initial_ground_item_rows(
		candidate,hero_position,map_layout) if product_dungeon else [])
	if not solo:
		narae.position = state.group_anchor; miru.position = state.group_anchor
	candidate.world.party_encounter = state
	candidate.world.warm_rollback_memento_static_tiles()
	if not candidate.world.world_state_error().is_empty(): return false
	sim = candidate; world_seed = p_world_seed; personality_seed = p_personality_seed
	player_species_id=p_player_species_id
	scenario_id = p_scenario_id
	_map_layout = map_layout.duplicate(true)
	_opening_blood_positions=opening_blood_positions.duplicate()
	_invalidate_explored_presentation_cache()
	_presentation_topology_cache.clear()
	_presentation_visibility_cache.clear()
	_warm_product_topology_presentation_cache()
	command_journal.clear(); _clear_draft(); _deployment_plan.clear()
	if _exploration_route == null: _exploration_route = ExplorationRouteScript.new(self)
	else: _exploration_route.clear()
	if _auto_explore == null: _auto_explore = AutoExploreScript.new(self)
	else: _auto_explore.clear()
	return true


static func _opening_blood_trail(anchors:Dictionary)->Array[Vector2i]:
	# A sparse punctuation trail leads from the entrance route to the side alcove.
	# It is regenerated from the seeded map and remains presentation-only, so old
	# saves keep their exact canonical wire.
	var result:Array[Vector2i]=[]
	var path:Variant=anchors.get("entry_exit_path",[])
	var last_index:=int(anchors.get("spawn_route_index",-1))
	if path is Array and last_index>0:
		for index in range(1,mini(last_index,path.size()-1)+1):
			if index%2==1 or index==last_index:
				var position:Variant=path[index]
				if position is Vector2i and position not in result:result.append(position)
	var spawn:Variant=anchors.get("spawn_position",Vector2i(-1,-1))
	if spawn is Vector2i and spawn not in result:result.append(spawn)
	return result


func is_solo_combat()->bool:
	return scenario_id in [SOLO_COMBAT_SCENARIO_ID, SOLO_FIXTURE_SCENARIO_ID]


func _initial_ground_item_rows(candidate,hero_position:Vector2i,
		map_layout:Dictionary)->Array:
	var blocked:Array=map_layout.get("door_positions",[]).duplicate()
	blocked.append(map_layout.get("entry_position",Vector2i(-1,-1)))
	blocked.append(map_layout.get("exit_position",Vector2i(-1,-1)))
	var candidates:Array[Vector2i]=[]
	for y in range(maxi(0,hero_position.y-5),mini(candidate.world.height,hero_position.y+6)):
		for x in range(maxi(0,hero_position.x-5),mini(candidate.world.width,hero_position.x+6)):
			var position:=Vector2i(x,y)
			var distance:=maxi(absi(position.x-hero_position.x),absi(position.y-hero_position.y))
			if distance<2 or position in blocked or not candidate.world.occupying_entities_at(position).is_empty():continue
			var tile=candidate.world.tile_at(position)
			var terrain:=TerrainRegistryScript.definition(str(tile.terrain))
			if terrain.is_empty() or not bool(terrain.get("passable",false)) \
					or int(tile.fire)>0 or int(tile.wetness)>0:continue
			candidates.append(position)
	candidates.sort_custom(func(a:Vector2i,b:Vector2i):
		var da:=maxi(absi(a.x-hero_position.x),absi(a.y-hero_position.y))
		var db:=maxi(absi(b.x-hero_position.x),absi(b.y-hero_position.y))
		return da<db if da!=db else (a.y<b.y if a.y!=b.y else a.x<b.x))
	if candidates.size()<2:return []
	return [{"position":[candidates[0].x,candidates[0].y],
		"item":ItemScript.new("GROUND_START_SHIELD","SHIELD_WOOD").to_dict()},
		{"position":[candidates[1].x,candidates[1].y],
		"item":ItemScript.new("GROUND_START_PADDED","ARMOR_PADDED").to_dict()}]


func protagonist_progression()->Dictionary:
	if sim==null or sim.world==null or sim.world.party_encounter==null \
			or sim.world.party_encounter.protagonist_progression==null:
		return {"schema_version":1,"available":false}.duplicate(true)
	var progression=sim.world.party_encounter.protagonist_progression
	var level:=ProgressionRegistryScript.level_for_xp(progression.xp_total)
	var floor_xp:=ProgressionRegistryScript.xp_floor_for_level(level)
	var next_total:=ProgressionRegistryScript.xp_floor_for_level(level+1)
	var state=sim.world.party_encounter
	var equipment := protagonist_equipment()
	var combat_stats:=_member_combat_stats(state.protagonist_id)
	var skills:Array=[]
	for skill_id in ProgressionRegistryScript.SKILL_IDS:
		var definition:=ProgressionRegistryScript.definition(skill_id)
		var training_total:=int(progression.skill_training[skill_id])
		var rank:=ProgressionRegistryScript.skill_rank(training_total)
		var training_floor:=ProgressionRegistryScript.training_floor_for_rank(rank)
		var next_training:=ProgressionRegistryScript.training_floor_for_rank(rank+1)
		var accuracy_bonus:=ProgressionRegistryScript.proficiency_accuracy_bonus_milli(rank)
		var damage_bonus:=ProgressionRegistryScript.proficiency_damage_bonus(rank)
		var mode:=str(progression.training_modes[skill_id])
		var effect_label:="명중 +%d · 피해 +%d"%[
			accuracy_bonus,damage_bonus]
		skills.append({"skill_id":skill_id,"label":str(definition.label),"rank":rank,
			"training_total":training_total,"training_current":training_total-training_floor,
			"training_required":next_training-training_floor,
			"training_mode":mode,"training_mode_label":ProgressionRegistryScript.mode_label(mode),
			"raw_weight":int(ProgressionRegistryScript.MODE_WEIGHTS[mode]),
			"effect_label":effect_label,
			"next_milestone":{"rank":int(definition.milestone_rank),
				"label":str(definition.milestone_label),"implemented":false}})
	return {"schema_version":ProgressionRegistryScript.SCHEMA_VERSION,"available":true,
		"ruleset_id":ProgressionRegistryScript.RULESET_ID,"level":level,
		"xp_total":int(progression.xp_total),"xp_current":int(progression.xp_total)-floor_xp,
		"xp_required":next_total-floor_xp,"current_level_floor":floor_xp,
		"next_level_threshold":next_total,
		"combat_stats":combat_stats,
		"equipment":equipment,
		"skills":skills}.duplicate(true)


func protagonist_growth_build()->Dictionary:
	if sim==null or sim.world==null or sim.world.party_encounter==null:
		return {"schema_version":1,"available":false,"reason":"session_not_initialized"}.duplicate(true)
	var state=sim.world.party_encounter
	var growth_inventory=sim.world.inventory_of(state.protagonist_id)
	if state.protagonist_growth==null or growth_inventory==null:
		return {"schema_version":1,"available":false,"reason":"growth_state_missing"}.duplicate(true)
	var equipped_items:Dictionary={}
	for slot in GrowthBuildCalculatorScript.EQUIPMENT_SLOTS:
		var item=growth_inventory.equipped_item(slot)
		if item!=null:equipped_items[slot]=item
	var projection:Dictionary=GrowthBuildCalculatorScript.calculate(
		state.protagonist_growth,equipped_items)
	if not bool(projection.get("accepted",false)):
		return {"schema_version":1,"available":false,
			"reason":str(projection.get("reason","growth_projection_failed"))}.duplicate(true)
	var build:Dictionary=projection.build.duplicate(true)
	var species_definition:Dictionary=GrowthBuildRegistryScript.species_definition(
		str(state.protagonist_growth.species_id))
	var branch_rows:Array=[]
	for branch in species_definition.get("branches",[]):
		var branch_id:=str(branch.get("branch_id",""))
		branch_rows.append({"branch_id":branch_id,"label":str(branch.get("label","")),
			"rank":int(state.protagonist_growth.species_branch_ranks.get(branch_id,0)),
			"max_rank":int(branch.get("ranks",[]).size()),
			"rank_effects":branch.get("ranks",[]).duplicate(true)})
	var mutation_rows:Array=[]
	for mutation_id in GrowthBuildRegistryScript.mutation_ids():
		var definition:Dictionary=GrowthBuildRegistryScript.mutation_definition(mutation_id)
		mutation_rows.append({"mutation_id":mutation_id,"label":str(definition.get("label","")),
			"monster_family_id":str(definition.get("monster_family_id","")),
			"unlocked":mutation_id in state.protagonist_growth.unlocked_mutation_ids,
			"equipped_slot":state.protagonist_growth.equipped_mutation_ids.find(mutation_id),
			"effect":definition.get("effect",{}).duplicate(true)})
	build["schema_version"]=1;build["available"]=true;build["reason"]="ok"
	build["stat_allocations"]=state.protagonist_growth.stat_allocations.duplicate(true)
	build["species_fixed_trait"]=species_definition.get("fixed_trait",{}).duplicate(true)
	build["species_branch_rows"]=branch_rows
	build["unlocked_mutation_ids"]=state.protagonist_growth.unlocked_mutation_ids.duplicate()
	build["mutation_rows"]=mutation_rows
	return build.duplicate(true)


func spend_growth_stat_point(stat_id:String)->Dictionary:
	return _commit_growth_point("SPEND_STAT_POINT",stat_id)


func spend_species_trait_point(branch_id:String)->Dictionary:
	return _commit_growth_point("SPEND_SPECIES_POINT",branch_id)


func _commit_growth_point(action:String,target_id:String)->Dictionary:
	if sim==null or sim.world==null or sim.world.party_encounter==null:
		return _rejection_dto("session_not_initialized")
	var state=sim.world.party_encounter
	if _run_is_complete() or state.safe_phase=="PARTY_DEFEATED":
		return _rejection_dto("run_complete")
	if not sim.world.is_settled() or _protagonist_draft!=null:
		return _rejection_dto("world_not_settled")
	var preview:Dictionary=state.protagonist_growth.commit_spend_stat_point(target_id) \
		if action=="SPEND_STAT_POINT" \
		else state.protagonist_growth.commit_spend_species_point(target_id)
	if not bool(preview.get("accepted",false)):
		return _rejection_dto(str(preview.get("reason","growth_point_failed")))
	var before:Dictionary=sim.snapshot()
	if before.is_empty():return _rejection_dto("snapshot_unavailable")
	state.protagonist_growth=preview.state
	var hero=sim.world.entities.get(state.protagonist_id)
	var event_type:="growth.stat_spent" if action=="SPEND_STAT_POINT" \
		else "growth.species_point_spent"
	var event=sim.world.emit_event(event_type,state.protagonist_id,state.protagonist_id,
		hero.position,1,-1,{"schema_version":1,"ruleset_id":GrowthBuildRegistryScript.RULESET_ID,
			"target_id":target_id})
	state.revision+=1
	var state_error:String=sim.world.world_state_error()
	if event==null or not state_error.is_empty():
		sim=SimulatorScript.from_snapshot(before)
		return _rejection_dto(state_error if not state_error.is_empty() else "growth_event_failed")
	command_journal.append({"kind":"growth","operation":{"action":action,
		"target_id":target_id,"slot_index":-1,"mutation_id":""}})
	return _feedback_dto({"accepted":true,"reason":"ok","event_id":event.id,
		"time_cost":0,"growth_build":protagonist_growth_build()})


func swap_mutation_trace(slot_index:int,mutation_id:String)->Dictionary:
	if sim==null or sim.world==null or sim.world.party_encounter==null:
		return _rejection_dto("session_not_initialized")
	var state=sim.world.party_encounter
	if _run_is_complete() or state.safe_phase=="PARTY_DEFEATED":
		return _rejection_dto("run_complete")
	if not sim.world.is_settled() or _protagonist_draft!=null:
		return _rejection_dto("world_not_settled")
	var preview:Dictionary=state.protagonist_growth.commit_mutation_swap(
		slot_index,mutation_id,state.safe_phase)
	if not bool(preview.get("accepted",false)):
		return _rejection_dto(str(preview.get("reason","mutation_swap_failed")))
	var before:Dictionary=sim.snapshot()
	if before.is_empty():return _rejection_dto("snapshot_unavailable")
	var journal_size_before:=command_journal.size()
	var advanced:Dictionary=_advance_item_action_time()
	if not bool(advanced.get("accepted",false)):
		sim=SimulatorScript.from_snapshot(before);return _rejection_dto("mutation_swap_time_failed")
	while command_journal.size()>journal_size_before:command_journal.pop_back()
	state=sim.world.party_encounter
	var committed:Dictionary=state.protagonist_growth.commit_mutation_swap(
		slot_index,mutation_id,state.safe_phase)
	if not bool(committed.get("accepted",false)):
		sim=SimulatorScript.from_snapshot(before)
		return _rejection_dto(str(committed.get("reason","mutation_swap_failed")))
	state.protagonist_growth=committed.state
	var hero=sim.world.entities.get(state.protagonist_id)
	var event=sim.world.emit_event("growth.mutation_swapped",state.protagonist_id,
		state.protagonist_id,hero.position,0,-1,{"schema_version":1,
			"ruleset_id":GrowthBuildRegistryScript.RULESET_ID,"slot_index":slot_index,
			"mutation_id":mutation_id,"time_cost":int(committed.time_cost)})
	state.revision+=1
	var state_error:String=sim.world.world_state_error()
	if event==null or not state_error.is_empty():
		sim=SimulatorScript.from_snapshot(before)
		return _rejection_dto(state_error if not state_error.is_empty() else "growth_event_failed")
	command_journal.append({"kind":"growth","operation":{"action":"SWAP_MUTATION",
		"target_id":"","slot_index":slot_index,"mutation_id":mutation_id}})
	return _feedback_dto({"accepted":true,"reason":"ok","event_id":event.id,
		"time_cost":int(committed.time_cost),"growth_build":protagonist_growth_build()})


func protagonist_equipment()->Dictionary:
	if sim==null or sim.world==null or sim.world.party_encounter==null:
		return {"schema_version":1,"available":false}.duplicate(true)
	var state=sim.world.party_encounter
	var ammo=sim.world.item_state.ammo_pool(state.protagonist_id)
	if ammo==null:return {"schema_version":1,"available":false}.duplicate(true)
	var weapon=WeaponRegistryScript.definition(
		ItemOperationsScript.equipped_weapon_id(sim.world,state.protagonist_id))
	if weapon==null:return {"schema_version":1,"available":false}.duplicate(true)
	var rank:int=state.protagonist_progression.rank(weapon.proficiency_id)
	var combatant=sim.world.combatant_states.get(state.protagonist_id)
	var profile:=CombatProfileRegistryScript.profile(combatant.combat_profile_id) if combatant!=null else {}
	var spec:=WeaponAttackRulesScript.build_attack_spec(weapon.weapon_id,rank,
		int(profile.get("power",0)),int(profile.get("accuracy_milli",0)),0,0,
		ActorStatRulesScript.for_entity(sim.world,state.protagonist_id))
	return {"schema_version":1,"available":true,"weapon_id":weapon.weapon_id,
		"weapon_label":weapon.label,"proficiency_id":weapon.proficiency_id,
		"proficiency_rank":rank,"attack_form":weapon.attack_form,"trait_id":weapon.trait_id,
		"range_min":weapon.range_min,"range_max":weapon.range_max,
		"attack_time":weapon.attack_time,"raw_damage":int(spec.get("raw_damage",0)),
		"accuracy_bonus_milli":ProgressionRegistryScript.proficiency_accuracy_bonus_milli(rank),
		"damage_bonus":ProgressionRegistryScript.proficiency_damage_bonus(rank),
		"ammo_kind":weapon.ammo_kind,"ammo_cost":weapon.ammo_cost,
		"arrows":ammo.amount("ARROW"),"bolts":ammo.amount("BOLT"),
		"reload_required":weapon.reload_required,
		"loaded":ItemOperationsScript.weapon_is_loaded(sim.world,state.protagonist_id),
		"can_reload":weapon.reload_required \
			and not ItemOperationsScript.weapon_is_loaded(sim.world,state.protagonist_id) \
			and ammo.amount(str(weapon.ammo_kind))>=int(weapon.ammo_cost),
		"reload_time":int(weapon.reload_time),
		"can_attack":ItemOperationsScript.attack_error(sim.world,state.protagonist_id).is_empty(),
		"attack_block_reason":ItemOperationsScript.attack_error(sim.world,state.protagonist_id),
		"combat_summary":_member_combat_stats(state.protagonist_id),
		"combat_modifiers":sim.world.equipment_modifiers(
			state.protagonist_id)}.duplicate(true)


func protagonist_inventory()->Dictionary:
	if sim==null or sim.world==null or sim.world.party_encounter==null:
		return {"schema_version":1,"available":false}.duplicate(true)
	var state=sim.world.party_encounter
	var inventory=sim.world.inventory_of(state.protagonist_id)
	if inventory==null:return {"schema_version":1,"available":false}.duplicate(true)
	var slot_rows:Array=[]
	for slot in preload("res://sim/item_definition.gd").EQUIPMENT_SLOTS:
		var instance_id:=str(inventory.equipped.get(slot,""))
		slot_rows.append(_item_presentation_row(inventory.item(instance_id),slot,true))
	var backpack_rows:Array=[]
	for item in inventory.unequipped_items():
		backpack_rows.append(_item_presentation_row(item,"",false))
	return {"schema_version":1,"available":true,"capacity":InventoryScript.BACKPACK_CAPACITY,
		"used_backpack_slots":inventory.used_backpack_slots(),
		"equipment_slots":slot_rows,"backpack_rows":backpack_rows,
		"equipment_bonuses":inventory.equipment_bonuses(),
		"combat_modifiers":inventory.combat_modifier_dto()}.duplicate(true)


func opening_event_status() -> Dictionary:
	if sim == null or sim.world == null or sim.world.party_encounter == null \
			or sim.world.party_encounter.opening_event == null:
		return {"schema_version":1, "available":false}.duplicate(true)
	var state = sim.world.party_encounter
	var opening = state.opening_event
	var hero = sim.world.entities.get(state.protagonist_id)
	var npc = sim.world.entities.get(opening.npc_entity_id)
	var hero_life = sim.world.combatant_states.get(state.protagonist_id)
	var npc_life = sim.world.combatant_states.get(opening.npc_entity_id)
	if hero == null or npc == null or hero_life == null or npc_life == null:
		return {"schema_version":1, "available":false}.duplicate(true)
	var adjacent := maxi(absi(hero.position.x - npc.position.x),
		absi(hero.position.y - npc.position.y)) == 1
	var can_interact: bool = opening.choice == "PENDING" and adjacent \
		and hero_life.life_state == "ACTIVE" and npc_life.life_state == "ACTIVE" \
		and not _run_is_complete()
	var give_preview: Dictionary = sim.opening_event.preview_choice("GIVE_POTION") \
		if can_interact else {"accepted":false}
	var relation: Dictionary = sim.relationships.effective_relation(
		opening.npc_entity_id, state.protagonist_id)
	var personality_style: Dictionary = opening.hexaco_profile.style_summary()
	var reencountered:bool=int(opening.reencounter_event_id)>0
	var recruitment:=recruitment_assessment(int(opening.npc_entity_id)) \
		if reencountered and state.member(int(opening.npc_entity_id))==null else {}
	return {"schema_version":1, "available":true,
		"npc_entity_id":opening.npc_entity_id,
		"display_name":str(npc.display_name), "choice":str(opening.choice),
		"current_behavior":str(opening.current_behavior),
		"life_state":str(npc_life.life_state), "health":int(npc.health),
		"max_health":int(npc.max_health),
		"position":[npc.position.x, npc.position.y],
		"spawn_position":[opening.spawn_position.x, opening.spawn_position.y],
		"convergence_goal":[opening.convergence_goal.x, opening.convergence_goal.y],
		"hexaco_profile":opening.hexaco_profile.to_dict(),
		"personality_style":personality_style,
		"scene_summary":("던전 안쪽에서 여행자와 다시 만났습니다. 이제 동행을 제안할 수 있습니다.\n성격 인상 · %s" \
			%str(personality_style.get("label","알 수 없는 인물"))) if reencountered \
			else ("입구에서 이어진 피 묻은 흔적 끝에 여행자가 벽에 기대 숨을 몰아쉬고 있습니다.\n성격 인상 · %s" \
			%str(personality_style.get("label", "알 수 없는 인물"))),
		"choice_prompt":"영입 가능성을 확인하고 동행을 제안하세요." if reencountered \
			else "회복 물약을 건넬지, 돕지 않고 떠날지 결정하세요.",
		"adjacent":adjacent,
		"can_interact":can_interact,
		"give_enabled":can_interact and bool(give_preview.get("accepted", false)),
		"pass_enabled":can_interact,
		"gratitude":int(relation.get("gratitude", 0)),
		"trust":int(relation.get("trust", 0)),
		"species_base_trust":int(relation.get("species_base", {}).get("base_trust", 0)),
		"choice_event_id":opening.choice_event_id,
		"reencountered":reencountered,
		"reencounter_event_id":opening.reencounter_event_id,
		"recruitment":recruitment.duplicate(true),
		"recruitment_probability_percent":int(recruitment.get("probability_percent",0)),
		"can_recruit":bool(recruitment.get("accepted",false))}.duplicate(true)


func commit_opening_event_choice(choice_action: String) -> Dictionary:
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return _rejection_dto("session_not_initialized")
	var preview: Dictionary = sim.opening_event.preview_choice(choice_action)
	if not bool(preview.get("accepted", false)):
		return _rejection_dto(str(preview.get("reason", "opening_choice_failed")))
	if not sim.world.is_settled() or _protagonist_draft != null:
		return _rejection_dto("world_not_settled")
	var rollback_memento:Variant=sim.capture_rollback_memento()
	if not rollback_memento is Dictionary:return _rejection_dto("snapshot_unavailable")
	var event_start: int = sim.world.events.size()
	var journal_size_before := command_journal.size()
	var advance: Dictionary = _advance_item_action_time()
	if not bool(advance.get("accepted", false)):
		if not _rollback_session_transaction(rollback_memento,journal_size_before):
			return _rejection_dto("rollback_restore_failed")
		return _rejection_dto("opening_choice_time_failed")
	while command_journal.size() > journal_size_before: command_journal.pop_back()
	var committed: Dictionary = sim.opening_event.commit_preflighted_choice(preview)
	if not bool(committed.get("accepted", false)):
		if not _rollback_session_transaction(rollback_memento,journal_size_before):
			return _rejection_dto("rollback_restore_failed")
		return _rejection_dto(str(committed.get("reason", "opening_choice_failed")))
	var state_error: String = sim.world.world_state_error()
	if not state_error.is_empty():
		if not _rollback_session_transaction(rollback_memento,journal_size_before):
			return _rejection_dto("rollback_restore_failed")
		return _rejection_dto(state_error)
	_clear_draft(); _deployment_plan.clear(); _invalidate_explored_presentation_cache()
	command_journal.append({"kind":"opening", "operation":{
		"action":choice_action}})
	var event_ids: Array = []
	for index in range(event_start, sim.world.events.size()):
		event_ids.append(sim.world.events[index].id)
	return _feedback_dto({"accepted":true, "reason":"ok",
		"choice":str(committed.choice), "event_ids":event_ids,
		"time_cost":int(committed.time_cost),
		"healed_amount":int(committed.healed_amount),
		"opening_event":opening_event_status(),
		"inventory":protagonist_inventory()})


func ground_items_at_protagonist()->Array[Dictionary]:
	var rows:Array[Dictionary]=[]
	if sim==null or sim.world==null or sim.world.party_encounter==null:return rows
	var state=sim.world.party_encounter
	var hero=sim.world.entities.get(state.protagonist_id)
	if hero==null:return rows
	for ground_row in sim.world.item_state.ground_items.rows:
		if ground_row.position==hero.position:
			rows.append(_item_presentation_row(ground_row.item,"",false))
	return rows.duplicate(true)


func visible_ground_items_at(position:Vector2i)->Array[Dictionary]:
	var rows:Array[Dictionary]=[]
	var context:=_party_observation_context()
	if context.is_empty() or not context.visible.has(_position_key(position)):return rows
	for ground_row in sim.world.item_state.ground_items.rows:
		if ground_row.position==position:
			rows.append(_item_presentation_row(ground_row.item,"",false))
	return rows.duplicate(true)


func pickup_ground_item(instance_id:String)->Dictionary:
	return _commit_item_operation("PICKUP",instance_id,"")


func equip_inventory_item(instance_id:String,slot:String)->Dictionary:
	return _commit_item_operation("EQUIP",instance_id,slot)


func unequip_inventory_slot(slot:String)->Dictionary:
	return _commit_item_operation("UNEQUIP","",slot)


func drop_inventory_item(instance_id:String)->Dictionary:
	return _commit_item_operation("DROP",instance_id,"")


func discard_inventory_item(instance_id:String)->Dictionary:
	return _commit_item_operation("DISCARD",instance_id,"")


func use_inventory_item(instance_id:String)->Dictionary:
	if sim==null or sim.world==null or sim.world.party_encounter==null:
		return _rejection_dto("session_not_initialized")
	var state=sim.world.party_encounter
	if state.safe_phase=="PARTY_DEFEATED" or _run_is_complete():return _rejection_dto("run_complete")
	if not sim.world.is_settled() or _protagonist_draft!=null:return _rejection_dto("world_not_settled")
	var hero=sim.world.entities.get(state.protagonist_id)
	var combatant=sim.world.combatant_states.get(state.protagonist_id)
	if hero==null or combatant==null:return _rejection_dto("item_actor_missing")
	if str(combatant.life_state)!="ACTIVE":return _rejection_dto("item_user_unavailable")
	if int(hero.health)>=int(hero.max_health):return _rejection_dto("item_heal_not_needed")
	var preview:Dictionary=ItemOperationsScript.preview_use(
		sim.world,state.protagonist_id,instance_id)
	if not bool(preview.get("accepted",false)):return _rejection_dto(str(preview.get("reason","item_operation_failed")))
	if str(preview.get("use_kind",""))!="HEALING":return _rejection_dto("item_use_unimplemented")
	var rollback_memento:Variant=sim.capture_rollback_memento()
	if not rollback_memento is Dictionary:return _rejection_dto("snapshot_unavailable")
	var event_start:int=sim.world.events.size()
	var journal_size_before:=command_journal.size()
	var advance:Dictionary=_advance_item_action_time()
	if not bool(advance.get("accepted",false)):
		if not _rollback_session_transaction(rollback_memento,journal_size_before):
			return _rejection_dto("rollback_restore_failed")
		return _rejection_dto("item_time_step_failed")
	while command_journal.size()>journal_size_before:command_journal.pop_back()
	state=sim.world.party_encounter;hero=sim.world.entities.get(state.protagonist_id)
	combatant=sim.world.combatant_states.get(state.protagonist_id)
	if hero==null or combatant==null or str(combatant.life_state)!="ACTIVE":
		if not _rollback_session_transaction(rollback_memento,journal_size_before):
			return _rejection_dto("rollback_restore_failed")
		return _rejection_dto("item_user_unavailable")
	if int(hero.health)>=int(hero.max_health):
		if not _rollback_session_transaction(rollback_memento,journal_size_before):
			return _rejection_dto("rollback_restore_failed")
		return _rejection_dto("item_heal_not_needed")
	var consumed:Dictionary=ItemOperationsScript.commit_use(
		sim.world,state.protagonist_id,instance_id,hero.position,ITEM_ACTION_TIME_COST)
	if not bool(consumed.get("accepted",false)):
		if not _rollback_session_transaction(rollback_memento,journal_size_before):
			return _rejection_dto("rollback_restore_failed")
		return _rejection_dto(str(consumed.get("reason","item_operation_failed")))
	var used=sim.world.event_by_id(int(consumed.event_id))
	if used==null:
		if not _rollback_session_transaction(rollback_memento,journal_size_before):
			return _rejection_dto("rollback_restore_failed")
		return _rejection_dto("item_event_failed")
	var healed:=mini(ItemRegistryScript.HEALING_POTION_RESTORE,int(hero.max_health)-int(hero.health))
	hero.health+=healed
	var restored=sim.world.emit_event("health.restored",state.protagonist_id,state.protagonist_id,
		hero.position,healed,used.id,{"schema_version":1,"ruleset_id":"healing-potion-v1",
			"kind":"POTION","health_after":int(hero.health)})
	state.revision+=1
	var state_error:String=sim.world.world_state_error()
	if restored==null or not state_error.is_empty():
		if not _rollback_session_transaction(rollback_memento,journal_size_before):
			return _rejection_dto("rollback_restore_failed")
		return _rejection_dto(state_error if not state_error.is_empty() else "item_event_failed")
	_clear_draft();_deployment_plan.clear();_invalidate_explored_presentation_cache()
	command_journal.append({"kind":"item","operation":{"action":"USE","instance_id":instance_id,"slot":""}})
	var event_ids:Array=[]
	for index in range(event_start,sim.world.events.size()):event_ids.append(sim.world.events[index].id)
	var healing_vfx:=_visual_effect_row(restored,"FLOATING_AMOUNT","heal",0,
		"healing",healed,"+%d" % healed)
	return _feedback_dto({"accepted":true,"reason":"ok","event_ids":event_ids,
		"time_cost":ITEM_ACTION_TIME_COST,"healed_amount":healed,"current_hp":int(hero.health),
		"inventory":protagonist_inventory(),"visual_effects":[healing_vfx]})


func _commit_item_operation(action:String,instance_id:String,slot:String)->Dictionary:
	if sim==null or sim.world==null or sim.world.party_encounter==null:
		return _rejection_dto("session_not_initialized")
	var state=sim.world.party_encounter
	if state.safe_phase=="PARTY_DEFEATED" or _run_is_complete():
		return _rejection_dto("run_complete")
	if not sim.world.is_settled() or _protagonist_draft!=null:
		return _rejection_dto("world_not_settled")
	var hero=sim.world.entities.get(state.protagonist_id)
	if hero==null or sim.world.item_state.inventory(state.protagonist_id)==null:
		return _rejection_dto("item_actor_missing")
	var hero_id:int=state.protagonist_id
	var preview:Dictionary
	match action:
		"PICKUP":preview=ItemOperationsScript.preview_pickup(sim.world,hero_id,
			instance_id,hero.position)
		"EQUIP":preview=ItemOperationsScript.preview_equip(sim.world,hero_id,instance_id,slot)
		"UNEQUIP":preview=ItemOperationsScript.preview_unequip(sim.world,hero_id,slot)
		"DROP":preview=ItemOperationsScript.preview_drop(sim.world,hero_id,
			instance_id,hero.position)
		"DISCARD":preview=ItemOperationsScript.preview_discard(sim.world,hero_id,instance_id)
		_:return _rejection_dto("unknown_item_operation")
	if not bool(preview.get("accepted",false)):
		return _rejection_dto(str(preview.get("reason","item_operation_failed")))
	var rollback_memento:Variant=sim.capture_rollback_memento()
	if not rollback_memento is Dictionary:return _rejection_dto("snapshot_unavailable")
	var journal_size_before:=command_journal.size()
	var step_result:Dictionary=_advance_item_action_time()
	if not bool(step_result.get("accepted",false)):
		if not _rollback_session_transaction(rollback_memento,journal_size_before):
			return _rejection_dto("rollback_restore_failed")
		return _rejection_dto("item_time_step_failed")
	while command_journal.size()>journal_size_before:command_journal.pop_back()
	state=sim.world.party_encounter;hero=sim.world.entities.get(state.protagonist_id)
	hero_id=state.protagonist_id
	var result:Dictionary
	match action:
		"PICKUP":result=ItemOperationsScript.commit_pickup(sim.world,hero_id,instance_id,
			hero.position,ITEM_ACTION_TIME_COST)
		"EQUIP":result=ItemOperationsScript.commit_equip(sim.world,hero_id,instance_id,slot,
			hero.position,ITEM_ACTION_TIME_COST)
		"UNEQUIP":result=ItemOperationsScript.commit_unequip(sim.world,hero_id,slot,
			hero.position,ITEM_ACTION_TIME_COST)
		"DROP":result=ItemOperationsScript.commit_drop(sim.world,hero_id,instance_id,
			hero.position,ITEM_ACTION_TIME_COST)
		"DISCARD":result=ItemOperationsScript.commit_discard(sim.world,hero_id,instance_id,
			hero.position,ITEM_ACTION_TIME_COST)
	if not bool(result.get("accepted",false)):
		if not _rollback_session_transaction(rollback_memento,journal_size_before):
			return _rejection_dto("rollback_restore_failed")
		return _rejection_dto(str(result.get("reason","item_operation_failed")))
	var event=sim.world.event_by_id(int(result.event_id))
	state.revision+=1
	var state_error:String=sim.world.world_state_error()
	if event==null or not state_error.is_empty():
		if not _rollback_session_transaction(rollback_memento,journal_size_before):
			return _rejection_dto("rollback_restore_failed")
		return _rejection_dto(state_error if not state_error.is_empty() else "item_event_failed")
	_clear_draft();_deployment_plan.clear();_invalidate_explored_presentation_cache()
	command_journal.append({"kind":"item","operation":{"action":action,
		"instance_id":instance_id,"slot":slot}})
	return _feedback_dto({"accepted":true,"reason":"ok","event_id":event.id,
		"time_cost":ITEM_ACTION_TIME_COST,"inventory":protagonist_inventory()})


func _rollback_session_transaction(rollback_memento:Variant,
		journal_size_before:int)->bool:
	# Restore the existing simulator in place. Assigning the result of a failed
	# snapshot decode used to replace `sim` with null, after which every equipment
	# action misleadingly reported that the whole session was uninitialized.
	while command_journal.size()>journal_size_before:command_journal.pop_back()
	return sim!=null and sim.restore_rollback_memento(rollback_memento)


func _advance_item_action_time()->Dictionary:
	var state=sim.world.party_encounter
	if state.safe_phase=="CONTACT" and is_solo_combat():
		var prepared:Dictionary=enter_solo_combat()
		if not bool(prepared.get("accepted",false)):return prepared
		state=sim.world.party_encounter
	if state.safe_phase=="ENGAGED":
		# Item use replaces the protagonist's action while the ordinary party-turn
		# resolver advances enemies/companions. HOLD is the existing no-movement
		# canonical time action and retains its ordinary short guard projection.
		var hero_id:=int(state.protagonist_id)
		var advanced:Dictionary=commit_direct_solo_action(hero_id,"HOLD") \
			if is_solo_combat() else _commit_item_time_party_turn(hero_id)
		return advanced
	var rollback_memento:Variant=sim.capture_rollback_memento()
	if not rollback_memento is Dictionary:return {"accepted":false,"reason":"snapshot_unavailable"}
	var event_start:int=sim.world.events.size()
	var result=sim.step(CommandScript.wait_for(ITEM_ACTION_TIME_COST,state.protagonist_id),
		rollback_memento)
	if result.accepted:
		var recovery:=_apply_safe_exploration_recovery(event_start)
		if not bool(recovery.accepted):
			if not sim.restore_rollback_memento(rollback_memento):
				return {"accepted":false,"reason":"rollback_restore_failed"}
			return {"accepted":false,"reason":str(recovery.reason)}
		_advance_exile_world()
	return {"accepted":bool(result.accepted),"reason":str(result.reason)}


func _apply_safe_exploration_recovery(event_start:int)->Dictionary:
	# This is invoked after every canonical session time action. The mutable
	# counter lives in PartyEncounterState, so save/load and journal replay follow
	# exactly the same safe-turn cadence without trusting wall-clock presentation.
	# Every caller owns the transaction snapshot/memento from before its complete
	# time action. Recovery therefore reports failure to that outer owner instead
	# of taking a second full-world snapshot after the step has already succeeded.
	if sim==null or sim.world==null or sim.world.party_encounter==null:return {"accepted":true}
	var state=sim.world.party_encounter
	var hero=sim.world.entities.get(state.protagonist_id)
	var combatant=sim.world.combatant_states.get(state.protagonist_id)
	if hero==null or combatant==null:return {"accepted":true}
	for index in range(maxi(0,event_start),sim.world.events.size()):
		var event=sim.world.events[index]
		if int(event.target_id)==state.protagonist_id and str(event.type).begins_with("combat.") \
				and str(event.type).ends_with("_damage") and int(event.magnitude)>0:
			state.last_protagonist_damage_step=sim.world.step_index
			state.safe_recovery_turns=0
			state.revision+=1
			return _finalize_safe_recovery({})
	var exposure_risk:=0
	if sim.world.is_environment_exposed(state.protagonist_id):
		var evaluated=sim.evaluate_exposure_for_entity(state.protagonist_id,hero.position)
		if evaluated!=null and evaluated.evaluation!=null:exposure_risk=int(evaluated.evaluation.total_risk)
	if not RecoveryRulesScript.is_safe_to_recover(sim.world,state,hero,combatant,exposure_risk):
		if state.safe_recovery_turns!=0:
			state.safe_recovery_turns=0;state.revision+=1
		return _finalize_safe_recovery({})
	state.safe_recovery_turns+=1
	state.revision+=1
	if not RecoveryRulesScript.heal_due(state.safe_recovery_turns):return _finalize_safe_recovery({})
	var healed:=mini(RecoveryRulesScript.HEAL_PER_PULSE,int(hero.max_health)-int(hero.health))
	if healed<=0:return _finalize_safe_recovery({})
	hero.health+=healed
	var event=sim.world.emit_event("health.restored",state.protagonist_id,state.protagonist_id,
		hero.position,healed,-1,{"schema_version":1,"ruleset_id":RecoveryRulesScript.RULESET_ID,
			"kind":"AUTO","safe_turn_count":state.safe_recovery_turns,"health_after":int(hero.health)})
	if event==null:
		return {"accepted":false,"reason":"safe_recovery_event_failed"}
	return _finalize_safe_recovery({"event_id":event.id,"healed_amount":healed,
		"safe_turn_count":state.safe_recovery_turns,"event":event})


func _finalize_safe_recovery(details:Dictionary)->Dictionary:
	var recovery_error:=_safe_recovery_postcondition_error(details)
	if not recovery_error.is_empty():
		return {"accepted":false,"reason":recovery_error}
	var result:Dictionary={"accepted":true};result.merge(details,true)
	return result


func _safe_recovery_postcondition_error(details:Dictionary)->String:
	# Simulator.step has just completed the full world-state validator. Recovery
	# owns only this party row, the protagonist HP, and optionally one final
	# health.restored leaf, so validate that narrow mutation envelope instead of
	# re-scanning the immutable world/event history a second time every hop.
	if sim==null or sim.world==null or sim.world._active_step_index!=-1 \
			or not sim.world.is_settled() or sim.world.party_encounter==null:
		return "safe_recovery_world_not_settled"
	var state=sim.world.party_encounter
	var hero=sim.world.entities.get(state.protagonist_id)
	var combatant=sim.world.combatant_states.get(state.protagonist_id)
	if hero==null or combatant==null or int(hero.health)<0 \
			or int(hero.health)>int(hero.max_health) \
			or int(state.safe_recovery_turns)<0 \
			or int(state.last_protagonist_damage_step)<-1 \
			or int(state.last_protagonist_damage_step)>int(sim.world.step_index):
		return "safe_recovery_projection_invalid"
	# Simulator.step has already validated the complete party state immediately
	# before this recovery tail. Recovery mutates only the counters above and,
	# optionally, protagonist HP plus one event; serializing and re-validating the
	# entire inventory/progression/roster here made every AUTO hop pay twice.
	if details.has("event_id"):
		var event=sim.world.event_by_id(int(details.event_id))
		if event==null or event!=sim.world.events.back() \
				or event.type!="health.restored" or event.actor_id!=state.protagonist_id \
				or event.target_id!=state.protagonist_id or event.cause_id!=-1 \
				or event.position!=hero.position or event.magnitude!=int(details.healed_amount) \
				or event.data!={"schema_version":1,"ruleset_id":RecoveryRulesScript.RULESET_ID,
					"kind":"AUTO","safe_turn_count":int(details.safe_turn_count),
					"health_after":int(hero.health)}:
			return "safe_recovery_event_invalid"
	return ""


func _commit_item_time_party_turn(hero_id:int)->Dictionary:
	var started:Dictionary=begin_turn(ActionScript.hold(hero_id))
	if not bool(started.get("accepted",false)):return started
	return commit_turn()


func _item_presentation_row(item,slot:String,equipped:bool)->Dictionary:
	if item==null:return {"slot":slot,"equipped":equipped,"empty":true}.duplicate(true)
	var definition=ItemRegistryScript.definition(item.definition_id)
	var requirements:Dictionary=definition.requirements.duplicate(true)
	var stats:=ActorStatRulesScript.baseline_stats()
	if sim!=null and sim.world!=null and sim.world.party_encounter!=null:
		stats=ActorStatRulesScript.for_entity(sim.world,
			int(sim.world.party_encounter.protagonist_id))
	var requirement_parts:Array[String]=[]
	for stat_id in ActorStatRulesScript.STAT_IDS:
		var required:=int(requirements.get(stat_id,0))
		if required>0:requirement_parts.append("%s %d"%[stat_id,required])
	var requirements_met:=ActorStatRulesScript.requirements_error(
		stats,requirements).is_empty()
	var glyph:="*"
	match str(definition.category):
		"WEAPON":glyph=")"
		"ARMOR":glyph="["
		"ACCESSORY":glyph="="
		"CONSUMABLE":glyph="?" if item.definition_id.begins_with("SCROLL") else "!"
	var result:={"slot":slot,"equipped":equipped,"empty":false,
		"instance_id":item.instance_id,"definition_id":item.definition_id,
		"label":definition.label,"category":definition.category,"glyph":glyph,
		"quantity":item.quantity,"rarity":item.rarity,
		"equip_slots":definition.equip_slots.duplicate(),"placeholder":definition.placeholder,
		"bonuses":definition.bonuses.duplicate(true),
		"requirements":requirements,"requirements_met":requirements_met,
		"requirement_text":" · ".join(requirement_parts),
		"current_stats":stats.duplicate(true),
		"use_kind":str(definition.use_kind),"usable":str(definition.use_kind)!="NONE",
		"heal_amount":ItemRegistryScript.HEALING_POTION_RESTORE \
			if str(definition.use_kind)=="HEALING" else 0,
		"compact_stat_text":""}
	if str(definition.category)=="WEAPON":
		var weapon=WeaponRegistryScript.definition(str(definition.weapon_id))
		if weapon!=null:
			var state=sim.world.party_encounter
			var rank:int=state.protagonist_progression.rank(str(weapon.proficiency_id))
			var combatant=sim.world.combatant_states.get(state.protagonist_id)
			var profile:=CombatProfileRegistryScript.profile(combatant.combat_profile_id) \
				if combatant!=null else {}
			var attack:=WeaponAttackRulesScript.build_attack_spec(weapon.weapon_id,rank,
				int(profile.get("power",0)),int(profile.get("accuracy_milli",0)),0,0,stats)
			result.merge({"weapon_id":str(weapon.weapon_id),
				"raw_damage":int(attack.get("raw_damage",weapon.base_damage)),
				"hit_chance_milli":int(attack.get("hit_chance_milli",500)),
				"accuracy_milli":int(weapon.accuracy_milli),
				"armor_penetration_flat":int(weapon.armor_penetration_flat),
				"range_min":int(weapon.range_min),"range_max":int(weapon.range_max),
				"attack_time":int(weapon.attack_time),"ammo_kind":str(weapon.ammo_kind),
				"ammo_cost":int(weapon.ammo_cost),
				"reload_required":bool(weapon.reload_required),
				"reload_time":int(weapon.reload_time),
				"compact_stat_text":"공격 %d"%int(attack.get("raw_damage",weapon.base_damage))},true)
	else:
		var parts:Array[String]=[]
		if int(definition.bonuses.get("armor_flat",0))!=0:
			parts.append("방어 %+d"%int(definition.bonuses.armor_flat))
		if int(definition.bonuses.get("parry_milli",0))!=0:
			parts.append("막기 %+d"%int(definition.bonuses.parry_milli))
		if int(definition.bonuses.get("dodge_milli",0))!=0:
			parts.append("회피 %+d"%int(definition.bonuses.dodge_milli))
		if str(definition.use_kind)=="HEALING":
			parts.append("회복 +%d"%ItemRegistryScript.HEALING_POTION_RESTORE)
		result["compact_stat_text"]=" · ".join(parts)
	return result.duplicate(true)


func equip_protagonist_weapon(weapon_id:String)->Dictionary:
	if sim==null or sim.world==null or sim.world.party_encounter==null:
		return _rejection_dto("session_not_initialized")
	if not WeaponRegistryScript.has(weapon_id):return _rejection_dto("unknown_weapon")
	if not sim.world.is_settled():return _rejection_dto("world_not_settled")
	if _protagonist_draft!=null:return _rejection_dto("turn_draft_active")
	var hero_id:int=sim.world.party_encounter.protagonist_id
	for event in sim.world.events:
		if event.type=="action.melee_attack" and event.actor_id==hero_id:
			return _rejection_dto("weapon_locked_after_first_attack")
	var before:Dictionary=sim.snapshot()
	if ItemOperationsScript.equipped_weapon_id(sim.world,hero_id)==weapon_id:
		return _rejection_dto("weapon_unchanged")
	# Legacy journal facade: it re-forges the historical MAIN_HAND instance instead
	# of moving a real item, so it edits a clone of the canonical row and swaps it
	# back through the same revision/validation gate the transactions use.
	var next=sim.world.item_state.clone()
	var inventory=next.inventory(hero_id)
	var main_id:=str(inventory.equipped.get("MAIN_HAND",""))
	if main_id.is_empty():main_id="LEGACY_MAIN_HAND"
	for index in range(inventory.backpack.size()-1,-1,-1):
		if inventory.backpack[index].instance_id==main_id:inventory.backpack.remove_at(index)
	inventory.backpack.append(ItemScript.new(main_id,
		ItemRegistryScript.weapon_definition_id(weapon_id)))
	inventory.equipped.MAIN_HAND=main_id
	if ItemRegistryScript.is_two_handed(ItemRegistryScript.weapon_definition_id(weapon_id)):
		inventory.equipped.OFF_HAND=""
	inventory._sort_backpack()
	ItemOperationsScript.reconcile_weapon_runtime_rows(next)
	next.revision=sim.world.item_state.revision+1
	sim.world.item_state=next
	sim.world.party_encounter.revision+=1
	var state_error:String=sim.world.world_state_error()
	if not state_error.is_empty():
		sim=SimulatorScript.from_snapshot(before);return _rejection_dto(state_error)
	command_journal.append({"kind":"equipment","operation":{
		"action":"EQUIP","weapon_id":weapon_id}})
	return _feedback_dto({"accepted":true,"reason":"ok","equipment":protagonist_equipment()})


func reload_protagonist_weapon()->Dictionary:
	if sim==null or sim.world==null or sim.world.party_encounter==null:
		return _rejection_dto("session_not_initialized")
	if not sim.world.is_settled():return _rejection_dto("world_not_settled")
	# The product combat screen may keep a replaceable HOLD placeholder ready for
	# party planning. Reload is itself the player's explicit choice, so discard
	# only that placeholder; never overwrite a real staged action.
	if _protagonist_draft!=null and _protagonist_placeholder:_clear_draft()
	if _protagonist_draft!=null:return _rejection_dto("turn_draft_active")
	var before:Dictionary=sim.snapshot()
	var reload_result:Dictionary=ItemOperationsScript.commit_reload(
		sim.world,sim.world.party_encounter.protagonist_id)
	if not bool(reload_result.get("accepted",false)):
		return _rejection_dto(str(reload_result.get("reason","reload_failed")))
	sim.world.party_encounter.revision+=1
	var state_error:String=sim.world.world_state_error()
	if not state_error.is_empty():
		sim=SimulatorScript.from_snapshot(before);return _rejection_dto(state_error)
	command_journal.append({"kind":"equipment","operation":{
		"action":"RELOAD","weapon_id":str(reload_result.weapon_id)}})
	return _feedback_dto({"accepted":true,"reason":"ok","reload_time":int(reload_result.reload_time),
		"equipment":protagonist_equipment()})


func _replay_legacy_training_focus(skill_id:String)->Dictionary:
	# Schema-2 journal compatibility. Product UI uses set_training_mode so each
	# proficiency remains independently configurable.
	if sim==null or sim.world==null or sim.world.party_encounter==null:
		return _rejection_dto("session_not_initialized")
	if skill_id not in ProgressionRegistryScript.SKILL_IDS:
		return _rejection_dto("unknown_progression_skill")
	var state=sim.world.party_encounter
	var modes:=ProgressionRegistryScript.DEFAULT_MODES.duplicate(true)
	for id in ProgressionRegistryScript.SKILL_IDS:
		modes[id]="FOCUS" if id==skill_id else "NORMAL"
	if modes==state.protagonist_progression.training_modes:
		return _rejection_dto("training_focus_unchanged")
	if not sim.world.is_settled():return _rejection_dto("world_not_settled")
	var before:Dictionary=sim.snapshot()
	var focus_rows:Array=[]
	var legacy_preset:=ProgressionRegistryScript.focus_preset(skill_id)
	for id in ProgressionRegistryScript.SKILL_IDS:
		focus_rows.append({"skill_id":id,"weight":int(legacy_preset[id])})
	var hero=sim.world.entities[state.protagonist_id]
	var event=sim.world.emit_event("progression.focus_changed",state.protagonist_id,-1,
		hero.position,0,-1,{"schema_version":1,"skill_id":skill_id,"focus":focus_rows})
	if event==null:
		sim=SimulatorScript.from_snapshot(before);return _rejection_dto("training_focus_failed")
	state.protagonist_progression.training_modes=modes
	state.revision+=1
	var state_error:String=sim.world.world_state_error()
	if not state_error.is_empty():
		sim=SimulatorScript.from_snapshot(before);return _rejection_dto(state_error)
	_clear_draft();_deployment_plan.clear()
	command_journal.append({"kind":"progression","operation":{
		"action":"SET_TRAINING_FOCUS","skill_id":skill_id}})
	return _feedback_dto({"accepted":true,"reason":"ok","event_id":event.id,
		"progression":protagonist_progression()})


func set_training_mode(skill_id:String,mode:String)->Dictionary:
	if sim==null or sim.world==null or sim.world.party_encounter==null:
		return _rejection_dto("session_not_initialized")
	if skill_id not in ProgressionRegistryScript.SKILL_IDS:
		return _rejection_dto("unknown_progression_skill")
	if mode not in ProgressionRegistryScript.TRAINING_MODES:
		return _rejection_dto("unknown_training_mode")
	var state=sim.world.party_encounter
	if str(state.protagonist_progression.training_modes.get(skill_id,""))==mode:
		return _rejection_dto("training_mode_unchanged")
	if not sim.world.is_settled():return _rejection_dto("world_not_settled")
	var before:Dictionary=sim.snapshot()
	var modes:Dictionary=state.protagonist_progression.training_modes.duplicate(true)
	modes[skill_id]=mode
	var mode_rows:Array=[]
	for id in ProgressionRegistryScript.SKILL_IDS:
		mode_rows.append({"skill_id":id,"mode":str(modes[id])})
	var hero=sim.world.entities[state.protagonist_id]
	var event=sim.world.emit_event("progression.focus_changed",state.protagonist_id,-1,
		hero.position,0,-1,{"schema_version":2,"skill_id":skill_id,"mode":mode,
			"training_modes":mode_rows})
	if event==null or not state.protagonist_progression.set_training_mode(skill_id,mode):
		sim=SimulatorScript.from_snapshot(before);return _rejection_dto("training_mode_failed")
	state.revision+=1
	var state_error:String=sim.world.world_state_error()
	if not state_error.is_empty():
		sim=SimulatorScript.from_snapshot(before);return _rejection_dto(state_error)
	_clear_draft();_deployment_plan.clear()
	command_journal.append({"kind":"progression","operation":{
		"action":"SET_TRAINING_MODE","skill_id":skill_id,"mode":mode}})
	return _feedback_dto({"accepted":true,"reason":"ok","event_id":event.id,
		"progression":protagonist_progression()})


func _configure_party_species_relations(candidate) -> void:
	# The candidate is the observer in a recruitment decision.  Personal aid is
	# deliberately bounded by RelationshipSystem, so these priors remain the
	# dominant baseline even after a dramatic rescue.
	candidate.world.species_relations.set_relation("human", "human", 35, 0, 0)
	candidate.world.species_relations.set_relation("dwarf", "human", 25, 5, 0)
	candidate.world.species_relations.set_relation("beastkin", "human", -30, 25, 45)
	candidate.world.species_relations.set_relation("goblin", "human", -60, 35, 75)


func _bootstrap_rescue_candidate(candidate, target_id: int) -> bool:
	if candidate == null or candidate.world == null \
			or not candidate.world.entities.has(target_id):
		return false
	var target = candidate.world.entities[target_id]
	target.health = maxi(1, int((target.max_health + 4) / 5))
	var rng_before: int = candidate.world.rng.state
	var discovered = candidate.world.emit_event("party.rescue_discovered", -1,
		target_id, target.position, 0, -1,
		{"schema_version":1, "state":"COLLAPSED_STORY", "non_hostile":true,
			"position":[target.position.x,target.position.y], "personality_slot":3})
	return discovered != null and candidate.world.rng.state == rng_before \
		and str(candidate.world.combatant_states[target_id].life_state) == "ACTIVE"

func party_status() -> Dictionary:
	if sim == null or sim.world.party_encounter == null: return {"ok": false, "reason": "session_not_initialized"}
	var state = sim.world.party_encounter; var view_mode: String = {"GROUPED":"EXPLORATION", "GROUPED_COMPLETE":"EXPLORATION",
		"CONTACT":"ENCOUNTER_PREVIEW", "ENGAGED":"COMBAT", "REGROUP_READY":"REGROUP", "PARTY_DEFEATED":"COMBAT"}[state.safe_phase]
	var visible_enemy_ids: Array = []
	if state.safe_phase not in ["GROUPED", "GROUPED_COMPLETE"]:
		for enemy_id in state.enemy_ids:
			if sim.world.is_unresolved_enemy(enemy_id): visible_enemy_ids.append(enemy_id)
	var protagonist_position: Vector2i = sim.world.entities[state.protagonist_id].position
	return {"ok": true, "safe_phase": state.safe_phase, "view_mode": view_mode, "terminal": state.safe_phase == "PARTY_DEFEATED",
		"contact_kind": state.contact_kind, "formation_id": state.formation_id, "anchor": [state.group_anchor.x,state.group_anchor.y],
		"facing": [state.facing.x,state.facing.y], "step_index": sim.world.step_index, "world_time": sim.world.world_time,
		"protagonist_id": state.protagonist_id, "party_member_ids": state.active_party_member_ids.duplicate(),
		"roster_member_ids": state.party_member_ids.duplicate(),
		"rescue_candidate_ids":rescue_candidate_ids(),
		"recruitable_member_ids":_member_ids_with_presence("RECRUITABLE"),
		"exiled_member_ids":_member_ids_with_presence("EXILED"),
		"visible_enemy_ids": visible_enemy_ids,
		"party_command":PartyCommandScript.effective(sim.world,state),
		"contact_warning":_latest_party_contact_warning(),
		"protagonist_position": [protagonist_position.x, protagonist_position.y],
			"snapshot_version": sim.world.SNAPSHOT_VERSION, "ruleset_version": sim.world.RULESET_VERSION,
			"session_format_version": SESSION_FORMAT_VERSION, "scenario_id": scenario_id}.duplicate(true)


func party_command_assessment(command_id:String,target_id:int=-1)->Dictionary:
	if _run_is_complete():return _rejection_dto("run_complete")
	if sim==null or sim.world==null or sim.world.party_encounter==null:
		return _rejection_dto("session_not_initialized")
	var state=sim.world.party_encounter
	if state.safe_phase!="ENGAGED" or not sim.world.is_settled():
		return _rejection_dto("party_command_phase_required")
	if command_id not in PartyCommandScript.COMMAND_IDS:
		return _rejection_dto("unknown_party_command")
	if command_id=="ATTACK_TARGET":
		if target_id not in state.enemy_ids or not sim.world.entities.has(target_id) \
				or not sim.world.is_autonomous_target(target_id):
			return _rejection_dto("party_command_target_invalid")
	elif target_id!=-1:
		return _rejection_dto("party_command_target_invalid")
	return _feedback_dto({"accepted":true,"reason":"ok",
		"command_id":command_id,"command_label":PartyCommandScript.label_ko(command_id),
		"target_id":target_id})


func issue_party_command(command_id:String,target_id:int=-1,
		append_journal:bool=true)->Dictionary:
	var assessment:=party_command_assessment(command_id,target_id)
	if not bool(assessment.get("accepted",false)):return assessment
	var rollback:Dictionary=sim.snapshot()
	var state=sim.world.party_encounter
	var hero_id:=int(state.protagonist_id)
	var hero_position:Vector2i=sim.world.entities[hero_id].position
	var event=sim.world.emit_event("party.command_issued",hero_id,target_id,
		hero_position,0,-1,PartyCommandScript.event_data(command_id,target_id))
	state.revision+=1
	var semantic_error:String=sim.world.world_state_error()
	if event==null or not semantic_error.is_empty():
		var restored=SimulatorScript.from_snapshot(rollback)
		if restored!=null:sim=restored
		return _rejection_dto("party_command_commit_failed")
	_clear_draft()
	if append_journal:
		command_journal.append({"kind":"party_command","operation":{
			"command_id":command_id,"target_id":str(target_id)}})
	return _feedback_dto({"accepted":true,"reason":"ok",
		"command_id":command_id,"command_label":PartyCommandScript.label_ko(command_id),
		"target_id":target_id,"event_id":int(event.id),
		"party_command":PartyCommandScript.effective(sim.world,state)})


func _latest_party_contact_warning() -> Dictionary:
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return {"available":false}
	for event_index in range(sim.world.events.size()-1,-1,-1):
		var event=sim.world.events[event_index]
		if event.type=="party.regroup_completed":break
		if event.type!="party.contact_reported":continue
		var direction:Array=event.data.get("direction",[])
		return {"available":true,"event_id":int(event.id),
			"spotter_id":int(event.actor_id),"spotter_name":_event_entity_name(event.actor_id),
			"enemy_id":int(event.target_id),"direction":direction.duplicate(true),
			"direction_label":_direction_label(direction),
			"message":_event_message(event)}.duplicate(true)
	return {"available":false}


func party_morale_observation() -> Dictionary:
	var empty := {"schema_version":1,"ruleset_id":PartyMoraleModelScript.RULESET_ID,
		"available":false,"sampled_step_index":-1,"sampled_world_time":-1,
		"panic_enter_threshold":PartyMoraleModelScript.PANIC_ENTER,
		"panic_exit_threshold":PartyMoraleModelScript.PANIC_EXIT,
		"members":[]}
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return empty.duplicate(true)
	var state = sim.world.party_encounter
	var latest_by_actor: Dictionary = {}
	for event in sim.world.events:
		if event.type == "party.morale_changed" \
				and event.actor_id in state.active_party_member_ids:
			latest_by_actor[event.actor_id] = event
	var member_ids: Array = state.active_party_member_ids.duplicate()
	member_ids.sort_custom(func(a,b):
		var member_a=state.member(int(a));var member_b=state.member(int(b))
		return int(member_a.roster_slot)<int(member_b.roster_slot) \
			if int(member_a.roster_slot)!=int(member_b.roster_slot) else int(a)<int(b))
	var rows: Array[Dictionary] = []
	for member_id_value in member_ids:
		var member_id := int(member_id_value)
		var member = state.member(member_id)
		var entity = sim.world.entities.get(member_id)
		if member == null or entity == null:
			continue
		var latest_change: Variant = null
		if latest_by_actor.has(member_id):
			var event = latest_by_actor[member_id]
			var cause_rows: Array[Dictionary] = []
			for trigger_value in event.data.get("trigger_codes",[]):
				var trigger_code := str(trigger_value)
				var presentation: Dictionary = PARTY_MORALE_TRIGGER_PRESENTATION.get(
					trigger_code,{"kind":"DISTRESS","label_ko":"긴장 변화"})
				cause_rows.append({"code":trigger_code,"kind":str(presentation.kind),
					"label_ko":str(presentation.label_ko)})
			latest_change = {"event_id":int(event.id),"step_index":int(event.step_index),
				"world_time":int(event.world_time),
				"stress_before":int(event.data.stress_before),
				"stress_after":int(event.data.stress_after),
				"net_delta":int(event.data.stress_after)-int(event.data.stress_before),
				"direct_delta":int(event.data.direct_delta),
				"contagion_delta":int(event.data.contagion_delta),
				"recovery_delta":int(event.data.recovery_delta),
				"source_event_count":event.data.get("source_event_ids",[]).size(),
				"causes":cause_rows}
		rows.append({"entity_id":member_id,"display_name":str(entity.display_name),
			"role":str(member.role),"presence":str(member.presence),
			"stress":int(member.stress),"mode":str(member.mental_mode),
			"mode_label":"공황" if member.mental_mode=="PANIC" else "평정",
			"latest_change":latest_change})
	return {"schema_version":1,"ruleset_id":PartyMoraleModelScript.RULESET_ID,
		"available":true,"sampled_step_index":int(sim.world.step_index),
		"sampled_world_time":int(sim.world.world_time),
		"panic_enter_threshold":PartyMoraleModelScript.PANIC_ENTER,
		"panic_exit_threshold":PartyMoraleModelScript.PANIC_EXIT,
		"members":rows}.duplicate(true)


func presentation_state() -> Dictionary:
	if sim == null or sim.world.party_encounter == null:
		return {"schema_version": PRESENTATION_SCHEMA_VERSION, "phase_id": "UNINITIALIZED",
			"mode": "UNAVAILABLE", "terminal": false, "combat_style_active": false,
			"banner": {"visible": true, "key": "session_unavailable",
				"title": "세션을 준비할 수 없습니다.", "subtitle": "", "tone": "ERROR"},
			"grid_style": {"style_id": "DEFAULT", "tint_hex": "#ffffff",
				"border_hex": "#617183", "vignette": false}}.duplicate(true)
	var status := party_status()
	var phase_id := str(status.safe_phase)
	var mode := "EXPLORATION"
	var banner := {"visible": true, "key": "exploration", "title": "탐험",
		"subtitle": "주인공이 홀로 던전을 탐색합니다." if is_solo_combat() \
		else "파티가 한 무리로 이동합니다.", "tone": "CALM"}
	var grid_style := {"style_id": "EXPLORATION", "tint_hex": "#ffffff",
		"border_hex": "#617183", "vignette": false}
	match phase_id:
		"CONTACT":
			mode = "ENCOUNTER"
			banner = {"visible": true, "key": "encounter_contact", "title": "조우",
				"subtitle": "단독 전투를 시작합니다." if is_solo_combat() \
				else "전투 대형을 선택하세요.", "tone": "WARNING"}
			grid_style = {"style_id": "ENCOUNTER", "tint_hex": "#fff2d6",
				"border_hex": "#e8b95c", "vignette": true}
		"ENGAGED":
			mode = "COMBAT"
			banner = {"visible": true, "key": "combat_active", "title": "전투 중",
				"subtitle": "주인공의 행동을 선택하세요." if is_solo_combat() \
				else "파티 행동을 계획하고 한꺼번에 확정하세요.", "tone": "COMBAT"}
			grid_style = {"style_id": "COMBAT", "tint_hex": "#ffe4dc",
				"border_hex": "#ff776d", "vignette": true}
		"REGROUP_READY":
			mode = "REGROUP"
			banner = {"visible": true, "key": "combat_victory", "title": "승리",
				"subtitle": "전투가 끝나 탐험으로 돌아갑니다." if is_solo_combat() \
				else "파티가 자동으로 재집결합니다.", "tone": "VICTORY"}
			grid_style = {"style_id": "REGROUP", "tint_hex": "#e5fff0",
				"border_hex": "#62d98b", "vignette": false}
		"GROUPED_COMPLETE":
			mode = "EXPLORATION"
			banner = {"visible": true, "key": "combat_victory_complete",
				"title":"승리 · 탐험 재개" if is_solo_combat() else "승리 · 자동 재집결",
				"subtitle":"출구를 찾으세요." if is_solo_combat() else "탐험 재개", "tone": "VICTORY"}
			grid_style = {"style_id": "VICTORY", "tint_hex": "#e5fff0",
				"border_hex": "#62d98b", "vignette": true}
		"PARTY_DEFEATED":
			mode = "DEFEAT"
			banner = {"visible": true, "key": "party_defeated", "title": "패배",
				"subtitle": "주인공이 쓰러져 더 행동할 수 없습니다.", "tone": "DEFEAT"}
			grid_style = {"style_id": "DEFEAT", "tint_hex": "#d5c6cf",
				"border_hex": "#8f5367", "vignette": true}
	return {"schema_version": PRESENTATION_SCHEMA_VERSION, "phase_id": phase_id,
		"mode": mode, "terminal": bool(status.terminal),
		"combat_style_active": phase_id in ["ENGAGED", "PARTY_DEFEATED"],
		"banner": banner, "grid_style": grid_style}.duplicate(true)


func run_progress() -> Dictionary:
	var unavailable := {"schema_version":VisualTestMapScript.RUN_MANIFEST_SCHEMA_VERSION,
		"available":false, "scenario_id":scenario_id, "objective_id":"",
		"run_state":"UNAVAILABLE", "entry_position":[], "exit_position":[],
		"encounter_cleared":false,
		"reward":{"reward_id":"", "amount":0, "granted":false},
		"exit":{"feature_id":"", "open":false},
		"complete":false, "terminal":false}
	var manifest: Dictionary = VisualTestMapScript.run_manifest(scenario_id, _map_layout)
	if manifest.is_empty() or sim == null or sim.world == null \
			or sim.world.party_encounter == null:
		return unavailable.duplicate(true)
	var state = sim.world.party_encounter
	var hero = sim.world.entities.get(state.protagonist_id)
	if hero == null:
		return unavailable.duplicate(true)
	var encounter_cleared: bool = state.safe_phase in ["REGROUP_READY", "GROUPED_COMPLETE"]
	var exit_position := Vector2i(int(manifest.exit.position[0]),
		int(manifest.exit.position[1]))
	var complete: bool = state.safe_phase == "GROUPED_COMPLETE" \
		and hero.position == exit_position
	var terminal: bool = complete or state.safe_phase == "PARTY_DEFEATED"
	var run_state := "EXPLORE"
	if state.safe_phase == "PARTY_DEFEATED": run_state = "DEFEATED"
	elif complete: run_state = "COMPLETE"
	elif encounter_cleared: run_state = "EXIT_OPEN"
	elif state.safe_phase in ["CONTACT", "ENGAGED", "REGROUP_READY"]:
		run_state = "ENCOUNTER"
	return {"schema_version":int(manifest.schema_version), "available":true,
		"scenario_id":str(manifest.scenario_id),
		"objective_id":str(manifest.objective_id), "run_state":run_state,
		"entry_position":manifest.entry.position.duplicate(true),
		"exit_position":manifest.exit.position.duplicate(true),
		"encounter_cleared":encounter_cleared,
		"reward":{"reward_id":str(manifest.reward.reward_id),
			"amount":int(manifest.reward.amount) if encounter_cleared else 0,
			"granted":encounter_cleared},
		"exit":{"feature_id":str(manifest.exit.open_feature_id) if encounter_cleared \
			else str(manifest.exit.locked_feature_id), "open":encounter_cleared},
		"complete":complete, "terminal":terminal}.duplicate(true)


func restart_same_run() -> Dictionary:
	var progress := run_progress()
	if not bool(progress.available):
		return _rejection_dto("run_restart_unavailable")
	if str(progress.run_state) not in ["COMPLETE", "DEFEATED"]:
		return _rejection_dto("run_restart_not_ready")
	var frozen_world_seed := world_seed
	var frozen_personality_seed := personality_seed
	var frozen_scenario_id := scenario_id
	var frozen_species_id := player_species_id
	if not reset_party(frozen_world_seed, frozen_personality_seed,
			frozen_scenario_id,{},true,frozen_species_id):
		return _rejection_dto("run_restart_failed")
	return _feedback_dto({"accepted":true, "reason":"ok",
		"world_seed":str(world_seed), "personality_seed":str(personality_seed),
		"scenario_id":scenario_id, "run_progress":run_progress()})


func start_new_run_with_species(species_id:String)->Dictionary:
	if not GrowthBuildRegistryScript.has_species(species_id):
		return _rejection_dto("unknown_player_species")
	if not reset_party(world_seed,personality_seed,scenario_id,{},true,species_id):
		return _rejection_dto("player_species_reset_failed")
	return _feedback_dto({"accepted":true,"reason":"ok",
		"player_species_id":player_species_id,"run_progress":run_progress()})


func restart_with_personality_seed(p_personality_seed: int) -> Dictionary:
	var progress := run_progress()
	if not bool(progress.available):
		return _rejection_dto("run_restart_unavailable")
	if str(progress.run_state) not in ["COMPLETE", "DEFEATED"]:
		return _rejection_dto("run_restart_not_ready")
	if p_personality_seed == personality_seed:
		return _rejection_dto("personality_seed_unchanged")
	var frozen_world_seed := world_seed
	var frozen_scenario_id := scenario_id
	var frozen_species_id := player_species_id
	if not reset_party(frozen_world_seed, p_personality_seed, frozen_scenario_id,
			{},true,frozen_species_id):
		return _rejection_dto("run_restart_failed")
	return _feedback_dto({"accepted":true, "reason":"ok",
		"world_seed":str(world_seed), "personality_seed":str(personality_seed),
		"scenario_id":scenario_id, "run_progress":run_progress()})


func party_personality_summary() -> Dictionary:
	var rows: Array = []
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return {"schema_version":2,"personality_seed":str(personality_seed),
			"companion_rows":rows}.duplicate(true)
	var state = sim.world.party_encounter
	for member_id_value in state.party_member_ids:
		var member_id := int(member_id_value)
		var member = state.member(member_id)
		if member == null or member.role != "COMPANION" \
				or member.personality_profile == null \
				or not sim.world.entities.has(member_id):
			continue
		var style := personality_style(member.personality_profile)
		rows.append({"actor_id":member_id,"roster_slot":int(member.roster_slot),
			"display_name":str(sim.world.entities[member_id].display_name),
			"style_label":str(style.get("label","")),
			"primary_facet":str(style.get("primary_facet","")),
			"secondary_facet":str(style.get("secondary_facet","")),
			"facet_rows":_hexaco_facet_rows(member.personality_profile)})
	for candidate_id_value in rescue_candidate_ids():
		var candidate_id := int(candidate_id_value)
		var profile = _rescue_personality_profile(candidate_id)
		if profile == null or not sim.world.entities.has(candidate_id): continue
		var style := personality_style(profile)
		rows.append({"actor_id":candidate_id,"roster_slot":63,
			"display_name":str(sim.world.entities[candidate_id].display_name),
			"style_label":str(style.get("label","")),
			"primary_facet":str(style.get("primary_facet","")),
			"secondary_facet":str(style.get("secondary_facet","")),
			"facet_rows":_hexaco_facet_rows(profile)})
	rows.sort_custom(func(a:Dictionary,b:Dictionary):
		return int(a.roster_slot)<int(b.roster_slot) if int(a.roster_slot)!=int(b.roster_slot) \
			else int(a.actor_id)<int(b.actor_id))
	return {"schema_version":2,"personality_seed":str(personality_seed),
		"companion_rows":rows}.duplicate(true)

func observe_party_world() -> Dictionary:
	var context:=_party_observation_context()
	if context.is_empty():return {}
	var bounds:=Rect2i(Vector2i.ZERO,Vector2i(sim.world.width,sim.world.height))
	# Keep the established public contract fully detached. Callers and tests may
	# freely mutate this 48x48 DTO without touching either authority or cache.
	return _party_rich_observation(context,bounds,Vector2i.ZERO).duplicate(true)


func observe_party_ui(cell_count:int=15,include_minimap:bool=true)->Dictionary:
	var context:=_party_observation_context()
	if context.is_empty():return {"grid":{},"minimap":{}}
	var count:=clampi(cell_count,1,MAX_UI_VIEW_CELL_COUNT)
	var hero_position:Vector2i=context.hero_position
	# A legacy world that already fits inside the requested surface may widen its
	# camera to keep actors at opposite edges visible. Materialize that complete
	# world; larger product maps retain a bounded hero-centered UI DTO.
	var full_world_fits:bool=sim.world.width<=count and sim.world.height<=count
	var viewport_origin:=Vector2i.ZERO if full_world_fits \
		else hero_position-Vector2i(count/2,count/2)
	var viewport_bounds:=Rect2i(viewport_origin,
		Vector2i(sim.world.width,sim.world.height) if full_world_fits \
		else Vector2i(count,count))
	return {"grid":_party_rich_observation(context,viewport_bounds,viewport_origin,
		count*count),
		# The product HUD keeps its minimap closed during ordinary movement and
		# combat. Let those hot paths omit the full explored-world projection;
		# callers that render or test the minimap retain the default contract.
		"minimap":_party_minimap_observation(context) if include_minimap else {}}


func _party_observation_context()->Dictionary:
	var status := party_status()
	if not bool(status.get("ok",false)):return {}
	var progress := run_progress()
	# The SHOWCASE is a visual test: a distant monster is deliberately visible
	# before its detection radius is crossed. REGRESSION keeps the legacy reveal.
	var hide_enemies: bool = scenario_id == REGRESSION_SCENARIO_ID \
		and str(status.safe_phase) in ["GROUPED", "GROUPED_COMPLETE"]
	var hero_position := Vector2i(int(status.protagonist_position[0]),
		int(status.protagonist_position[1]))
	var visible: Dictionary = _presentation_visible_cells(hero_position)
	# The controlled actor is always a valid presentation anchor. Keep this
	# explicit so grouped followers can safely fall back to the hero cell even if
	# a future LOS implementation accidentally omits its origin.
	visible[_position_key(hero_position)] = true
	var explored:Dictionary=_explored_cells_from_hero_history(int(status.protagonist_id),
		hero_position)
	var visited:Dictionary=(_explored_presentation_cache.get("visited",{}) as Dictionary) \
		.duplicate(true)
	var follower_positions := _grouped_follower_display_positions(visible)
	var ground_items_by_cell:Dictionary={}
	for ground_row in sim.world.item_state.ground_items.rows:
		var ground_key:=_position_key(ground_row.position)
		if not ground_items_by_cell.has(ground_key):ground_items_by_cell[ground_key]=[]
		ground_items_by_cell[ground_key].append(_item_presentation_row(ground_row.item,"",false))
	var monster_blood_by_cell:Dictionary={}
	var enemy_ids:Array=sim.world.party_encounter.enemy_ids
	for event in sim.world.events:
		if str(event.type)!="entity.died" or int(event.target_id) not in enemy_ids:continue
		if sim.world.in_bounds(event.position):
			monster_blood_by_cell[_position_key(event.position)]=true
	var followers_by_cell: Dictionary = {}
	for member_id_value in follower_positions:
		var member_id := int(member_id_value)
		var follower_position: Vector2i = follower_positions[member_id]
		var follower_key := _position_key(follower_position)
		if not followers_by_cell.has(follower_key): followers_by_cell[follower_key] = []
		followers_by_cell[follower_key].append(member_id)
	return {"status":status,"progress":progress,"hide_enemies":hide_enemies,
		"hero_id":int(status.protagonist_id),"hero_position":hero_position,
		"visible":visible,"explored":explored,"visited":visited,
		"followers_by_cell":followers_by_cell,
		"ground_items_by_cell":ground_items_by_cell,
		"monster_blood_by_cell":monster_blood_by_cell}


func _wall_borders_visible_floor(position:Vector2i,visible:Dictionary)->bool:
	# True when this wall touches (orthogonally or diagonally) a currently visible
	# non-wall cell, i.e. it forms the visible boundary of the player's view.
	for direction in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),
			Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]:
		var neighbor:Vector2i=position+direction
		if not sim.world.in_bounds(neighbor):continue
		if not visible.has(_position_key(neighbor)):continue
		if str(sim.world.tile_at(neighbor).terrain)!="wall":return true
	return false


func _party_rich_observation(context:Dictionary,bounds:Rect2i,
		grid_origin:Vector2i,mapping_capacity:int=225)->Dictionary:
	var status:Dictionary=context.status
	var progress:Dictionary=context.progress
	var visible:Dictionary=context.visible
	var explored:Dictionary=context.explored
	var followers_by_cell:Dictionary=context.followers_by_cell
	var ground_items_by_cell:Dictionary=context.ground_items_by_cell
	var monster_blood_by_cell:Dictionary=context.monster_blood_by_cell
	var hide_enemies:=bool(context.hide_enemies)
	var cells: Array = []
	var minimum:=Vector2i(maxi(0,bounds.position.x),maxi(0,bounds.position.y))
	var maximum:=Vector2i(mini(sim.world.width,bounds.end.x),
		mini(sim.world.height,bounds.end.y))
	for y in range(minimum.y,maximum.y):
		for x in range(minimum.x,maximum.x):
			var position := Vector2i(x,y)
			var position_key:=_position_key(position)
			var visibility_state := "VISIBLE" if visible.has(position_key) else (
				"MEMORY" if explored.has(position_key) else "UNSEEN")
			# A wall that encloses the field of view is itself seen. Strict cell LOS
			# leaves such border walls UNSEEN, which rendered as black gaps in the
			# very walls the player stands beside (worst on diagonals). Promote a
			# wall bordering any currently visible floor to VISIBLE so the room's
			# walls read as solid. This is presentation only: gameplay FOV and the
			# auto-explore fog snapshot build their own cell sets and are untouched.
			if visibility_state != "VISIBLE" \
					and str(sim.world.tile_at(position).terrain) == "wall" \
					and _wall_borders_visible_floor(position, visible):
				visibility_state = "VISIBLE"
			if visibility_state == "UNSEEN":
				cells.append({"position":[x,y], "terrain_id":"unknown", "feature_id":"",
					"visibility_state":"UNSEEN", "fire_intensity":0, "wetness":0,
					"effective_conductivity":0, "ground_mark_id":"",
					"presentation_material_id":"",
					"actors":[],"ground_items":[]})
				continue
			var tile = sim.world.tile_at(position)
			var presentation_material_id:=_presentation_material_at(position)
			if visibility_state=="MEMORY":
				# Remember only stable terrain. Features, hazards, actors and all live
				# decision data remain unavailable outside the current field of view.
				cells.append({"position":[x,y],"terrain_id":str(tile.terrain),
					"feature_id":"","ground_mark_id":"blood_pool" \
						if monster_blood_by_cell.has(position_key) else (
							"blood" if position in _opening_blood_positions else ""),
					"presentation_material_id":presentation_material_id,
					"visibility_state":"MEMORY","fire_intensity":0,
					"wetness":0,"effective_conductivity":0,"actors":[],"ground_items":[]})
				continue
			var actors: Array = []
			for entity in sim.world.occupying_entities_at(position):
				var is_enemy: bool = entity.id in sim.world.party_encounter.enemy_ids
				if is_enemy and hide_enemies: continue
				actors.append(_actor_observation(entity, position, position, ""))
			# DEAD actors intentionally do not occupy a tile. The opening NPC corpse
			# remains observable from its same authoritative entity and position.
			var opening = sim.world.party_encounter.opening_event
			if opening != null and sim.world.entities.has(opening.npc_entity_id):
				var opening_entity = sim.world.entities[opening.npc_entity_id]
				var opening_life = sim.world.combatant_states.get(opening.npc_entity_id)
				if opening_entity.position == position and opening_life != null \
						and opening_life.life_state == "DEAD":
					actors.append(_actor_observation(opening_entity, position,
						position, "OPENING_NPC"))
			for member_id_value in followers_by_cell.get(_position_key(position), []):
				var member_id := int(member_id_value)
				if sim.world.entities.has(member_id):
					actors.append(_actor_observation(sim.world.entities[member_id],
						sim.world.party_encounter.group_anchor, position, "FOLLOWER"))
			actors.sort_custom(func(a: Dictionary, b: Dictionary):
				return int(a.roster_slot) < int(b.roster_slot) \
					if int(a.roster_slot) != int(b.roster_slot) \
					else int(a.entity_id) < int(b.entity_id))
			cells.append({"position":[x,y], "terrain_id":str(tile.terrain),
				"feature_id":_run_feature_id_at(position, progress),
				"ground_mark_id":"blood_pool" if monster_blood_by_cell.has(position_key) \
					else ("blood" if position in _opening_blood_positions else ""),
				"presentation_material_id":presentation_material_id,
				"visibility_state":"VISIBLE", "fire_intensity":int(tile.fire),
				"wetness":int(tile.wetness),
				"effective_conductivity":int(tile.effective_conductivity()), "actors":actors,
				"ground_items":ground_items_by_cell.get(position_key,[]).duplicate(true)})
	var los_radius:=VisualTestMapScript.uses_los_fov(scenario_id)
	return {"width": sim.world.width, "height": sim.world.height, "cells": cells,
		"phase":status, "grid_mapping": {"origin": [grid_origin.x,grid_origin.y],
			"cell_count":mini(maxi(1,mapping_capacity),bounds.size.x*bounds.size.y)},
		"visibility":{"mode":"LOS_RADIUS" if los_radius else "FULL",
			"radius":VisualTestMapScript.SHOWCASE_FOV_RADIUS if los_radius else 15,
			"memory_supported":true}}


func _presentation_material_at(position:Vector2i)->String:
	if not VisualTestMapScript.uses_product_dungeon(scenario_id):return ""
	return DeterministicDungeonMapScript.presentation_material_at(_map_layout,position)


func _party_minimap_observation(context:Dictionary)->Dictionary:
	var visible:Dictionary=context.visible
	var explored:Dictionary=context.explored
	var progress:Dictionary=context.progress
	var markers:Dictionary={}
	var exit_key:=""
	var exit_position_value:Variant=progress.get("exit_position",[])
	if bool(progress.get("available",false)) and exit_position_value is Array \
			and exit_position_value.size()==2:
		exit_key=_position_key(Vector2i(int(exit_position_value[0]),int(exit_position_value[1])))
	var hero_id:=int(context.hero_id)
	if sim.world.entities.has(hero_id):
		var hero_position:Vector2i=sim.world.entities[hero_id].position
		if visible.has(_position_key(hero_position)):
			markers[_position_key(hero_position)]="HERO"
	if not bool(context.hide_enemies):
		for enemy_id_value in sim.world.party_encounter.enemy_ids:
			var enemy_id:=int(enemy_id_value)
			if not sim.world.entities.has(enemy_id) or not sim.world.occupies_tile(enemy_id):continue
			var enemy_position:Vector2i=sim.world.entities[enemy_id].position
			var enemy_key:=_position_key(enemy_position)
			if visible.has(enemy_key) and not markers.has(enemy_key):markers[enemy_key]="ENEMY"
	var known_keys:Dictionary={}
	for key_value in explored:known_keys[str(key_value)]=true
	for key_value in visible:known_keys[str(key_value)]=true
	var known_positions:Array[Vector2i]=[]
	for key_value in known_keys:
		var parts:=str(key_value).split(":")
		if parts.size()!=2:continue
		var position:=Vector2i(int(parts[0]),int(parts[1]))
		if sim.world.in_bounds(position):known_positions.append(position)
	known_positions.sort_custom(func(a:Vector2i,b:Vector2i):
		return a.y<b.y if a.y!=b.y else a.x<b.x)
	var cells:Array=[]
	for position in known_positions:
		var key:=_position_key(position)
		var state:="VISIBLE" if visible.has(key) else "MEMORY"
		# EXIT is static discovered cartography, not live feature authority. Actor
		# markers still win on a currently visible shared cell; MEMORY can retain
		# only this static marker and never enemy/target/hazard information.
		var marker:=str(markers.get(key,"")) if state=="VISIBLE" else ""
		if marker.is_empty() and key==exit_key:marker="EXIT"
		cells.append({"position":[position.x,position.y],"visibility_state":state,
			"terrain_id":str(sim.world.tile_at(position).terrain),"marker":marker})
	return {"schema_version":1,"width":sim.world.width,"height":sim.world.height,
		"cells":cells}


func _explored_cells_from_hero_history(hero_id:int,current_position:Vector2i)->Dictionary:
	if sim==null or sim.world==null:return {}
	var event_count:int=sim.world.events.size()
	var topology_fingerprint:=_presentation_topology_fingerprint()
	var cache_valid:=int(_explored_presentation_cache.get("world_instance_id",-1)) \
			==int(sim.world.get_instance_id()) \
		and str(_explored_presentation_cache.get("scenario_id",""))==scenario_id \
		and int(_explored_presentation_cache.get("hero_id",-1))==hero_id \
		and int(_explored_presentation_cache.get("topology_fingerprint",-1)) \
			==topology_fingerprint
	var scanned_count:=int(_explored_presentation_cache.get("scanned_event_count",0))
	if cache_valid:
		cache_valid=scanned_count>=0 and scanned_count<=event_count
	if cache_valid and scanned_count>0:
		var prefix_event=sim.world.events[scanned_count-1]
		cache_valid=int(prefix_event.id)==int(
			_explored_presentation_cache.get("boundary_event_id",-1)) \
			and _presentation_event_boundary_signature(prefix_event)==str(
				_explored_presentation_cache.get("boundary_event_signature",""))
	if not cache_valid:
		_explored_presentation_cache={"world_instance_id":int(sim.world.get_instance_id()),
			"scenario_id":scenario_id,"hero_id":hero_id,
			"topology_fingerprint":topology_fingerprint,"scanned_event_count":0,
			"boundary_event_id":-1,"boundary_event_signature":"",
			"visited":{},"explored":{}}
		scanned_count=0
	for index in range(scanned_count,event_count):
		var event=sim.world.events[index]
		if str(event.type)!="action.move" or int(event.actor_id)!=hero_id:continue
		_cache_explored_position(event.data.get("from_position",[]))
		_cache_explored_position(event.data.get("to_position",[]))
	_cache_explored_origin(current_position)
	_explored_presentation_cache["scanned_event_count"]=event_count
	if event_count>0:
		var tail_event=sim.world.events[event_count-1]
		_explored_presentation_cache["boundary_event_id"]=int(tail_event.id)
		_explored_presentation_cache["boundary_event_signature"]= \
			_presentation_event_boundary_signature(tail_event)
	else:
		_explored_presentation_cache["boundary_event_id"]=-1
		_explored_presentation_cache["boundary_event_signature"]=""
	return (_explored_presentation_cache.get("explored",{}) as Dictionary).duplicate()


func _cache_explored_position(value:Variant)->void:
	if value is Array and value.size()==2:
		_cache_explored_origin(Vector2i(int(value[0]),int(value[1])))


func _cache_explored_origin(origin:Vector2i)->void:
	if not sim.world.in_bounds(origin):return
	var visited:Dictionary=_explored_presentation_cache.get("visited",{})
	var origin_key:=_position_key(origin)
	if visited.has(origin_key):return
	visited[origin_key]=true
	var explored:Dictionary=_explored_presentation_cache.get("explored",{})
	var historical_visible:Dictionary=_presentation_visible_cells(origin)
	for key in historical_visible:explored[str(key)]=true
	_explored_presentation_cache["visited"]=visited
	_explored_presentation_cache["explored"]=explored


func _presentation_event_boundary_signature(event)->String:
	return "%d:%s:%d"%[int(event.id),str(event.type),int(event.actor_id)]


func _presentation_topology_fingerprint()->int:
	# Product dungeon terrain is bootstrap-only: once its initial environment
	# events exist, `bootstrap_set_terrain` cannot mutate it. Reuse the verified
	# topology value for the same live world instead of rescanning all 96x96 tiles
	# on every AUTO/route hop. Small fixture worlds keep the per-call regression
	# check used by topology-mutation tests; reset/load already clears this cache.
	if sim.world.width*sim.world.height>MAX_UI_VIEW_CELL_COUNT*MAX_UI_VIEW_CELL_COUNT \
			and int(_presentation_topology_cache.get("world_instance_id",-1)) \
			==int(sim.world.get_instance_id()) \
			and str(_presentation_topology_cache.get("scenario_id",""))==scenario_id \
			and _presentation_topology_cache.has("topology_fingerprint"):
		return int(_presentation_topology_cache.topology_fingerprint)
	return _scan_presentation_topology_fingerprint()


func _presentation_visible_cells(origin:Vector2i)->Dictionary:
	if sim==null or sim.world==null:return {}
	var key:="%d:%s:%d:%d"%[int(sim.world.get_instance_id()),scenario_id,
		origin.x,origin.y]
	var cached:Variant=_presentation_visibility_cache.get(key)
	if cached is Dictionary:return (cached as Dictionary).duplicate()
	var visible:Dictionary=VisualTestMapScript.visible_cells(sim.world,origin,scenario_id)
	_presentation_visibility_cache[key]=visible
	return visible.duplicate()


func _scan_presentation_topology_fingerprint()->int:
	var fingerprint:=posmod(sim.world.width*131+sim.world.height,2147483647)
	for y in range(sim.world.height):
		for x in range(sim.world.width):
			fingerprint=posmod(fingerprint*33+str(
				sim.world.tile_at(Vector2i(x,y)).terrain).hash(),2147483647)
	return fingerprint


func _warm_product_topology_presentation_cache()->void:
	if sim==null or sim.world==null \
			or sim.world.width*sim.world.height<=MAX_UI_VIEW_CELL_COUNT*MAX_UI_VIEW_CELL_COUNT:
		return
	_presentation_topology_cache={
		"world_instance_id":int(sim.world.get_instance_id()),
		"scenario_id":scenario_id,
		"topology_fingerprint":_scan_presentation_topology_fingerprint(),
	}


func _invalidate_explored_presentation_cache()->void:
	_explored_presentation_cache.clear()


func _grouped_follower_display_positions(presentation_visible: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return result
	var state = sim.world.party_encounter
	var anchor: Vector2i = state.group_anchor
	var facing: Vector2i = state.facing
	if facing not in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		facing = Vector2i.RIGHT
	var used := {_position_key(anchor):true}
	# Presentation followers should avoid every authoritative occupant when a
	# distinct visible cell exists. Their logical position and occupancy remain
	# the grouped anchor; this set is only a renderer-placement constraint.
	for entity_id_value in sim.world.entities:
		var entity_id := int(entity_id_value)
		if sim.world.occupies_tile(entity_id):
			used[_position_key(sim.world.entities[entity_id].position)] = true
	var follower_ids: Array = []
	for member_id_value in state.party_member_ids:
		var member_id := int(member_id_value)
		var member = state.member(member_id)
		if member_id != state.protagonist_id and member != null \
				and member.presence == "GROUPED" and sim.world.occupies_tile(member_id):
			follower_ids.append(member_id)
	follower_ids.sort_custom(func(a, b):
		var member_a = state.member(int(a)); var member_b = state.member(int(b))
		return int(member_a.roster_slot) < int(member_b.roster_slot) \
			if int(member_a.roster_slot) != int(member_b.roster_slot) else int(a) < int(b))
	var adjacent_offsets := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT,
		Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)]
	for follower_index in range(follower_ids.size()):
		var candidates: Array[Vector2i] = [anchor - facing * (follower_index + 1)]
		for offset in adjacent_offsets:
			var fallback: Vector2i = anchor + offset
			if fallback not in candidates: candidates.append(fallback)
		for candidate in candidates:
			var key := _position_key(candidate)
			if not sim.world.in_bounds(candidate) or used.has(key): continue
			if not presentation_visible.is_empty() and not presentation_visible.has(key): continue
			var terrain := TerrainRegistryScript.definition(str(sim.world.tile_at(candidate).terrain))
			if terrain.is_empty() or not bool(terrain.get("passable", false)): continue
			result[int(follower_ids[follower_index])] = candidate
			used[key] = true
			break
		# Visibility is more important than separation. At tight corners there may
		# be no free visible floor, so overlap the hero presentation instead of
		# silently dropping a party member from the observation DTO.
		if not result.has(int(follower_ids[follower_index])):
			result[int(follower_ids[follower_index])] = anchor
	return result


func _actor_observation(entity, logical_position: Vector2i,
		display_position: Vector2i, display_role_override: String) -> Dictionary:
	var member = sim.world.party_member_state(entity.id)
	var is_enemy: bool = entity.id in sim.world.party_encounter.enemy_ids
	var combatant = sim.world.combatant_states.get(entity.id)
	var actor_facing := _actor_facing(entity.id, is_enemy)
	var display_role := display_role_override
	if display_role.is_empty():
		display_role = "ENEMY" if is_enemy else ("PROTAGONIST" \
			if member != null and member.role == "PROTAGONIST" else ("COMPANION" \
			if member != null else "ACTOR"))
	var dto := {"entity_id":entity.id, "display_name":entity.display_name,
		"kind":str(entity.kind), "species_id":str(entity.species_id),
		"health":entity.health, "max_health":entity.max_health,
		"life_state":str(combatant.life_state) if combatant != null else "DEAD",
		"status_ids":_combatant_status_ids(entity.id),
		"guarded":combatant != null and combatant.life_state == "ACTIVE" \
			and sim.world.world_time < combatant.guarded_until,
		"facing":[actor_facing.x, actor_facing.y],
		"logical_position":[logical_position.x, logical_position.y],
		"display_position":[display_position.x, display_position.y],
		"display_role":display_role,
		"is_protagonist":member != null and member.role == "PROTAGONIST",
		"roster_slot":member.roster_slot if member != null else 99,
		"faction_id":entity.faction_id,
		"presence":member.presence if member != null else "DEPLOYED",
		"is_enemy":is_enemy,
		"sprite_frame":0 if member != null and member.role == "PROTAGONIST" \
			else (4 if member != null else 5)}
	if member != null and member.role == "PROTAGONIST":
		dto["equipment_visual"]=_protagonist_equipment_visual()
	if is_enemy:
		# This helper is called only while materializing a currently VISIBLE cell.
		# MEMORY and UNSEEN rows never contain actors, so awareness authority cannot
		# leak through fog-of-war.
		var threat:=_enemy_threat(entity.id)
		dto["threat_id"]=str(threat.get("threat_id","EVEN"))
		dto["threat_label"]=str(threat.get("threat_label","대등"))
		var awareness=sim.world.party_encounter.enemy_awareness(entity.id)
		var perception_profile:Dictionary=EnemyPerceptionRegistryScript.profile(
			str(entity.species_id))
		if awareness!=null and not perception_profile.is_empty():
			dto["awareness_state"]=str(awareness.awareness_state)
			dto["suspicion"]=int(awareness.suspicion)
			dto["sight_range"]=int(perception_profile.sight_range)
			dto["perception"]=int(perception_profile.perception)
			dto["last_known_position"]=[awareness.last_known_target_position.x,
				awareness.last_known_target_position.y]
	if member == null and _rescue_discovery_event_for(entity.id) != null:
		var story_state := rescue_story_state(entity.id)
		dto["display_role"] = "RESCUE_NPC"
		dto["presence"] = "WORLD_NPC"
		dto["story_state"] = story_state
		dto["authoritative_life_state"] = str(combatant.life_state) \
			if combatant != null else "DEAD"
		# DOWNED is a presentation pose only. Combat life remains ACTIVE and all
		# occupancy/hit authority continues to use the canonical world entity.
		dto["life_state"] = "DOWNED" if story_state == "COLLAPSED_STORY" else "ACTIVE"
	var opening = sim.world.party_encounter.opening_event
	if opening != null and int(opening.npc_entity_id) == int(entity.id) and member==null:
		dto["display_role"] = "OPENING_NPC"
		dto["presence"] = "WORLD_NPC"
		dto["opening_choice"] = str(opening.choice)
		dto["opening_behavior"] = str(opening.current_behavior)
		dto["is_corpse"] = combatant != null and combatant.life_state == "DEAD"
	return dto


func _protagonist_equipment_visual()->Dictionary:
	if sim==null or sim.world==null or sim.world.party_encounter==null:
		return {"weapon_id":"UNARMED_STRIKE","weapon_definition_id":"",
			"armor_definition_id":"","off_hand_definition_id":""}.duplicate(true)
	var state=sim.world.party_encounter
	var inventory=sim.world.inventory_of(state.protagonist_id)
	if inventory==null:
		return {"weapon_id":ItemOperationsScript.equipped_weapon_id(
			sim.world,state.protagonist_id),"weapon_definition_id":"",
			"armor_definition_id":"","off_hand_definition_id":""}.duplicate(true)
	var main=inventory.equipped_item("MAIN_HAND")
	var armor=inventory.equipped_item("ARMOR")
	var off_hand=inventory.equipped_item("OFF_HAND")
	return {
		"weapon_id":ItemOperationsScript.equipped_weapon_id(sim.world,state.protagonist_id),
		"weapon_definition_id":str(main.definition_id) if main!=null else "",
		"armor_definition_id":str(armor.definition_id) if armor!=null else "",
		"off_hand_definition_id":str(off_hand.definition_id) if off_hand!=null else "",
	}.duplicate(true)

func party_cards() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []; var state = sim.world.party_encounter
	var preview: Dictionary = current_turn_preview() if _protagonist_draft != null else {}
	var preview_by_actor: Dictionary = {}
	for actor_row in preview.get("actor_rows", []): preview_by_actor[int(actor_row.actor_id)] = actor_row
	for member_id in state.active_party_member_ids:
		var member = state.member(member_id); var entity = sim.world.entities[member_id]
		var logical: Vector2i = entity.position if member.presence == "DEPLOYED" else (state.group_anchor if member.presence == "GROUPED" else Vector2i(-1,-1))
		var exposure := {"applicable": false, "sampled_step_index": sim.world.step_index, "sampled_world_time": sim.world.world_time,
			"position": [-1,-1], "fire_score": 0, "water_score": 0, "electric_score": 0, "poison_score": 0, "total_risk": 0}
		if member.presence in ["DEPLOYED", "GROUPED"] and sim.world.is_environment_exposed(member_id):
			var evaluated = sim.evaluate_exposure_for_entity(member_id, logical); var wire: Dictionary = evaluated.evaluation.to_dict()
			exposure = {"applicable": true, "sampled_step_index": int(wire.sampled_step_index), "sampled_world_time": int(wire.sampled_world_time),
				"position": wire.position, "fire_score": wire.fire_score, "water_score": wire.water_score, "electric_score": wire.electric_score,
				"poison_score": wire.poison_score, "total_risk": wire.total_risk}
		var expected_action = null if _protagonist_placeholder \
				and member.role == "PROTAGONIST" \
			else _action_presentation(preview_by_actor.get(member_id, null))
		var readiness := "행동 준비" if member.busy_until <= sim.world.world_time else "행동 중"
		var emotion := _emotion_presentation(member, entity)
		var override_state := "PENDING"
		if expected_action != null: override_state = str(expected_action.source)
		elif member.role == "PROTAGONIST":
			override_state = "PENDING" if _protagonist_placeholder else "DIRECT"
		var progression:=protagonist_progression() if member.role=="PROTAGONIST" else {}
		rows.append({"entity_id": member_id, "roster_slot": member.roster_slot, "role": member.role,
			"display_name": entity.display_name, "health": entity.health, "max_health": entity.max_health, "alive": sim.world.occupies_tile(member_id),
			"species_id":str(entity.species_id),
			"status_ids": _combatant_status_ids(member_id), "presence": member.presence, "logical_position": [logical.x,logical.y],
			"element_exposure": exposure, "stress": member.stress, "readiness": readiness,
			"emotion": emotion, "override_state": override_state,"progression":progression,
			"expected_action": expected_action})
	return rows.duplicate(true)

func available_companion_ids() -> Array:
	var ids: Array = []
	if sim == null or sim.world.party_encounter == null: return ids
	var state = sim.world.party_encounter
	for member_id in state.active_party_member_ids:
		if member_id != state.protagonist_id and sim.world.is_autonomous_target(member_id): ids.append(member_id)
	return ids.duplicate()


func rescue_candidate_ids() -> Array:
	var ids: Array = []
	if sim == null or sim.world == null: return ids
	for event in sim.world.events:
		if event.type != "party.rescue_discovered" or event.target_id <= 0 \
				or event.target_id in ids or not sim.world.entities.has(event.target_id):
			continue
		if rescue_story_state(event.target_id) not in ["JOINED","HOSTILE"]:
			ids.append(event.target_id)
	ids.sort()
	return ids.duplicate()


func is_rescue_candidate(entity_id: int) -> bool:
	return entity_id in rescue_candidate_ids()


func rescue_story_state(entity_id: int) -> String:
	var discovery = _rescue_discovery_event_for(entity_id)
	if discovery == null: return ""
	if _npc_assault_event_for(entity_id) != null: return "HOSTILE"
	var outcome = _recruitment_outcome_event_for(entity_id)
	if outcome != null:
		return "JOINED" if outcome.type == "party.recruitment_accepted" else "REJECTED"
	if _rescue_event_for(entity_id) != null: return "OFFER_READY"
	return str(discovery.data.get("state", "COLLAPSED_STORY"))


func rescue_assessment(entity_id: int) -> Dictionary:
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return _rejection_dto("session_not_initialized")
	var state = sim.world.party_encounter
	if state.safe_phase not in ["GROUPED", "GROUPED_COMPLETE"] or _run_is_complete():
		return _rejection_dto("party_roster_unsafe_phase")
	var discovery = _rescue_discovery_event_for(entity_id)
	var entity = sim.world.entities.get(entity_id)
	var combatant = sim.world.combatant_states.get(entity_id)
	if discovery == null or entity == null or combatant == null \
			or not entity.tags.has("rescue_npc") \
			or not bool(discovery.data.get("non_hostile", false)):
		return _rejection_dto("rescue_candidate_not_recruitable")
	if rescue_story_state(entity_id) != "COLLAPSED_STORY":
		return _rejection_dto("rescue_already_completed")
	if str(combatant.life_state) != "ACTIVE":
		return _rejection_dto("rescue_candidate_unavailable")
	var hero = sim.world.entities.get(state.protagonist_id)
	if hero == null or maxi(absi(hero.position.x-entity.position.x),
			absi(hero.position.y-entity.position.y)) > 1:
		return _rejection_dto("rescue_candidate_too_far")
	return _feedback_dto({"accepted":true,"reason":"ok","entity_id":entity_id,
		"story_state":"COLLAPSED_STORY","result_state":"OFFER_READY",
		"life_state":"DOWNED","authoritative_life_state":"ACTIVE",
		"time_cost":RESCUE_TIME_COST,"consumes_time":true,
		"message_ko":"한 턴을 들여 상처를 안정화합니다."})


func stabilize_recruit_candidate(entity_id: int) -> Dictionary:
	var assessment := rescue_assessment(entity_id)
	if not bool(assessment.get("accepted", false)): return assessment
	var rollback_value: Variant = sim.snapshot()
	if not rollback_value is Dictionary:
		return _rejection_dto("party_snapshot_unavailable")
	var rollback: Dictionary = rollback_value
	var state = sim.world.party_encounter
	var hero_id: int = int(state.protagonist_id)
	var result = sim.step(CommandScript.wait_for(RESCUE_TIME_COST, hero_id))
	if not result.accepted or not sim.world.entities.has(entity_id) \
			or str(sim.world.combatant_states[entity_id].life_state) != "ACTIVE" \
			or rescue_story_state(entity_id) != "COLLAPSED_STORY":
		_restore_roster_rollback(rollback)
		return _rejection_dto("rescue_stabilization_failed")
	_advance_exile_world()
	var entity = sim.world.entities[entity_id]
	var rescued = sim.world.emit_event("party.npc_stabilized", hero_id, entity_id,
		entity.position, 0, -1, {"schema_version":1,
			"previous_state":"COLLAPSED_STORY", "state":"OFFER_READY",
			"time_cost":RESCUE_TIME_COST})
	if rescued == null or not sim.relationships.record_aid(entity_id, hero_id,
			rescued.id, RESCUE_AID_MAGNITUDE):
		_restore_roster_rollback(rollback)
		return _rejection_dto("rescue_stabilization_failed")
	state = sim.world.party_encounter
	state.revision += 1
	if not sim.world.world_state_error().is_empty():
		_restore_roster_rollback(rollback)
		return _rejection_dto("rescue_stabilization_failed")
	_clear_draft(); _deployment_plan.clear()
	if _exploration_route != null: _exploration_route.clear()
	command_journal.append({"kind":"roster","operation":{
		"action":"STABILIZE","entity_id":str(entity_id)}})
	return _feedback_dto({"accepted":true,"reason":"ok","entity_id":entity_id,
		"life_state":"ACTIVE","story_state":"OFFER_READY",
		"consumes_time":true,"step_index":int(result.processed_step_index),
		"start_time":int(result.start_time),"end_time":int(result.end_time),
		"time_cost":RESCUE_TIME_COST,"event_ids":[rescued.id],
		"recruitment":recruitment_assessment(entity_id)})


func recruitment_assessment(entity_id: int) -> Dictionary:
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return _rejection_dto("session_not_initialized")
	if _is_opening_recruitment_candidate(entity_id):
		return _opening_recruitment_assessment(entity_id)
	var state = sim.world.party_encounter
	var discovery = _rescue_discovery_event_for(entity_id)
	var entity = sim.world.entities.get(entity_id)
	var combatant = sim.world.combatant_states.get(entity_id)
	if discovery == null or entity == null or combatant == null:
		return _rejection_dto("companion_not_recruitable")
	var prior_outcome = _recruitment_outcome_event_for(entity_id)
	if prior_outcome != null:
		return _feedback_dto({"accepted":false,"reason":"recruitment_already_resolved",
			"entity_id":entity_id,"resolved":true,
			"joined":str(prior_outcome.type)=="party.recruitment_accepted",
			"probability_milli":int(prior_outcome.data.get("probability_milli",0)),
			"probability_percent":int((int(prior_outcome.data.get("probability_milli",0))+5)/10),
			"roll_milli":int(prior_outcome.data.get("roll_milli",-1)),
			"reasons":prior_outcome.data.get("reasons",[]).duplicate(true)})
	var rescue_event = _rescue_event_for(entity_id)
	if rescue_event == null or rescue_story_state(entity_id) != "OFFER_READY":
		return _rejection_dto("recruitment_requires_rescue")
	var relation: Dictionary = sim.relationships.effective_relation(entity_id,
		state.protagonist_id)
	var species_base: Dictionary = relation.get("species_base",{})
	var personal: Dictionary = relation.get("personal",{})
	# Species prior is intentionally the dominant single term. Personal history
	# can soften it, but one rescue never makes inherited hostility disappear.
	var species_term := int(species_base.get("base_trust",0))*5 \
		- int(species_base.get("base_hostility",0))*5 \
		- int(species_base.get("base_fear",0))*3
	var affection_term := int(personal.get("trust_delta",0))*3 \
		- maxi(0,int(personal.get("fear_delta",0)))*2 \
		- int(personal.get("grievance",0))*2
	var memory_term := int(personal.get("gratitude",0))
	var profile = _rescue_personality_profile(entity_id)
	var personality_term := 0
	if profile != null:
		personality_term = clampi(int((profile.value("H")-500)/7) \
			+ int((profile.value("A")-500)/10), -140, 140)
	var hp_percent := int(entity.health*100/maxi(1,entity.max_health))
	var survival_term := clampi((100-hp_percent)*2,0,180)
	var rescue_term := 180
	var has_vacancy: bool = state.active_party_member_ids.size() < ACTIVE_PARTY_LIMIT
	var vacancy_term := 40 if has_vacancy else 0
	var probability := clampi(500+species_term+affection_term+memory_term \
		+personality_term+survival_term+rescue_term+vacancy_term,50,950)
	var reasons: Array[Dictionary] = _recruitment_reason_rows(species_base,
		relation, personality_term, survival_term, rescue_term, vacancy_term)
	var hero = sim.world.entities.get(state.protagonist_id)
	var adjacent: bool = hero != null and maxi(absi(hero.position.x-entity.position.x),
		absi(hero.position.y-entity.position.y)) <= 1
	var legal: bool = has_vacancy and adjacent \
		and str(combatant.life_state)=="ACTIVE" \
		and state.safe_phase in ["GROUPED","GROUPED_COMPLETE"] \
		and not _run_is_complete()
	var reason := "ok"
	if not has_vacancy: reason = "party_full"
	elif not adjacent: reason = "recruitment_candidate_too_far"
	elif str(combatant.life_state)!="ACTIVE": reason = "companion_unavailable"
	elif state.safe_phase not in ["GROUPED","GROUPED_COMPLETE"] or _run_is_complete():
		reason = "party_roster_unsafe_phase"
	var key := "%s|world=%d|personality=%d|candidate=%d|rescue=%d" % [
		RECRUITMENT_RULESET_ID,world_seed,personality_seed,entity_id,int(rescue_event.id)]
	# A blocked offer exposes its probability and reasons, but consumes neither
	# the keyed roll nor a judgment event. Opening a vacancy reveals the stable roll.
	var roll := _stable_roll_milli(key) if legal else -1
	return _feedback_dto({"accepted":legal,"reason":reason,"entity_id":entity_id,
		"resolved":false,"joined":false,"probability_milli":probability,
		"probability_percent":int((probability+5)/10),"roll_milli":roll,
		"would_accept":legal and roll<probability,"ruleset_id":RECRUITMENT_RULESET_ID,
		"key_hash":key.sha256_text() if legal else "","reasons":reasons,
		"terms":{"species_prior":species_term,"affection":affection_term,
			"personal_memory":memory_term,"personality":personality_term,
			"survival_threat":survival_term,"rescued":rescue_term,
			"vacancy":vacancy_term}})


func is_opening_recruitment_candidate(entity_id:int)->bool:
	return _is_opening_recruitment_candidate(entity_id)


func _is_opening_recruitment_candidate(entity_id:int)->bool:
	if sim==null or sim.world==null or sim.world.party_encounter==null:return false
	var opening=sim.world.party_encounter.opening_event
	return opening!=null and int(opening.npc_entity_id)==entity_id \
		and int(opening.reencounter_event_id)>0 \
		and entity_id not in sim.world.party_encounter.enemy_ids


func npc_attack_assessment(entity_id:int)->Dictionary:
	if sim==null or sim.world==null or sim.world.party_encounter==null:
		return _rejection_dto("session_not_initialized")
	var state=sim.world.party_encounter
	var entity=sim.world.entities.get(entity_id)
	var combatant=sim.world.combatant_states.get(entity_id)
	var opening=state.opening_event
	var opening_npc:=opening!=null and int(opening.npc_entity_id)==entity_id \
		and int(opening.reencounter_event_id)>0
	var rescue_npc:=_rescue_discovery_event_for(entity_id)!=null
	if entity==null or combatant==null or not opening_npc and not rescue_npc \
			or state.member(entity_id)!=null or entity_id in state.enemy_ids:
		return _rejection_dto("npc_not_attackable")
	if _npc_assault_event_for(entity_id)!=null:
		return _rejection_dto("npc_already_hostile")
	if str(combatant.life_state)!="ACTIVE" \
			or rescue_npc and rescue_story_state(entity_id)=="COLLAPSED_STORY":
		return _rejection_dto("npc_attack_target_unavailable")
	if state.safe_phase not in ["GROUPED","GROUPED_COMPLETE"] or _run_is_complete():
		return _rejection_dto("npc_attack_unsafe_phase")
	# Enemy membership is a floor-wide canonical set. Extending it after a victory
	# would rewrite what that old victory meant, so that edge remains unavailable.
	for event in sim.world.events:
		if event.type=="party.victory":return _rejection_dto("npc_attack_after_victory")
	var hero=sim.world.entities.get(state.protagonist_id)
	if hero==null or maxi(absi(hero.position.x-entity.position.x),
			absi(hero.position.y-entity.position.y))!=1:
		return _rejection_dto("npc_attack_target_too_far")
	return _feedback_dto({"accepted":true,"reason":"ok","entity_id":entity_id,
		"target_name":str(entity.display_name),"adjacent":true,
		"consequence":"HOSTILE","consumes_time":false})


func assault_npc(entity_id:int)->Dictionary:
	var assessment:=npc_attack_assessment(entity_id)
	if not bool(assessment.get("accepted",false)):return assessment
	var rollback_value:Variant=sim.snapshot()
	if not rollback_value is Dictionary:return _rejection_dto("party_snapshot_unavailable")
	var rollback:Dictionary=rollback_value
	var state=sim.world.party_encounter
	var hero_id:=int(state.protagonist_id)
	var hero=sim.world.entities[hero_id]
	var npc=sim.world.entities[entity_id]
	var assault=sim.world.emit_event("party.npc_assaulted",hero_id,entity_id,
		npc.position,0,-1,{"schema_version":1,"ruleset_id":"npc-assault-v1",
			"previous_disposition":"NEUTRAL","disposition":"HOSTILE"})
	if assault==null:
		_restore_roster_rollback(rollback);return _rejection_dto("npc_assault_failed")
	state.enemy_ids.append(entity_id);state.enemy_ids.sort()
	state.enemy_busy_rows[entity_id]=int(sim.world.world_time)
	var awareness=EnemyAwarenessScript.new(entity_id,npc.position)
	awareness.awareness_state="HUNTING";awareness.suspicion=1000
	awareness.last_known_target_position=hero.position
	awareness.last_seen_step=int(sim.world.step_index)
	awareness.last_seen_time=int(sim.world.world_time)
	state.enemy_awareness_rows[entity_id]=awareness
	state.revision+=1
	# Adjacent assault always creates ordinary contact; the next input enters the
	# existing deployment/combat pipeline and the NPC can retaliate there.
	if not sim.party_coordinator._detect_contact(sim.world.step_index,-1,
			sim.world.world_time,{}):
		_restore_roster_rollback(rollback);return _rejection_dto("npc_assault_failed")
	var state_error:String=sim.world.world_state_error()
	if not state_error.is_empty():
		_restore_roster_rollback(rollback);return _rejection_dto(state_error)
	_clear_draft();_deployment_plan.clear()
	if _exploration_route!=null:_exploration_route.clear()
	if _auto_explore!=null:_auto_explore.cancel("npc_assaulted")
	command_journal.append({"kind":"npc_assault","operation":{"entity_id":str(entity_id)}})
	return _feedback_dto({"accepted":true,"reason":"ok","entity_id":entity_id,
		"target_name":str(npc.display_name),"event_id":int(assault.id),
		"consequence":"HOSTILE","contact":true,"consumes_time":false})


func _opening_recruitment_assessment(entity_id:int)->Dictionary:
	var state=sim.world.party_encounter;var opening=state.opening_event
	var entity=sim.world.entities.get(entity_id)
	var combatant=sim.world.combatant_states.get(entity_id)
	if opening==null or entity==null or combatant==null:
		return _rejection_dto("companion_not_recruitable")
	var prior_outcome=_recruitment_outcome_event_for(entity_id)
	if prior_outcome!=null:
		return _feedback_dto({"accepted":false,"reason":"recruitment_already_resolved",
			"entity_id":entity_id,"resolved":true,
			"joined":str(prior_outcome.type)=="party.recruitment_accepted",
			"probability_milli":int(prior_outcome.data.get("probability_milli",0)),
			"probability_percent":int((int(prior_outcome.data.get("probability_milli",0))+5)/10),
			"roll_milli":int(prior_outcome.data.get("roll_milli",-1)),
			"reasons":prior_outcome.data.get("reasons",[]).duplicate(true)})
	var relation:Dictionary=sim.relationships.effective_relation(entity_id,state.protagonist_id)
	var species_base:Dictionary=relation.get("species_base",{})
	var species_term:=int(species_base.get("base_trust",0))*4 \
		-int(species_base.get("base_hostility",0))*4 \
		-int(species_base.get("base_fear",0))*2
	var gratitude_term:=int(relation.get("gratitude",0))*3
	var profile=opening.hexaco_profile;var personality_term:=clampi(
		int((profile.value("H")-500)/8)+int((profile.value("A")-500)/10) \
		+int((profile.value("X")-500)/14),-160,160)
	var help_term:=220 if str(opening.choice)=="GAVE_POTION" else -120
	var has_vacancy:bool=state.active_party_member_ids.size()<ACTIVE_PARTY_LIMIT
	var vacancy_term:=40 if has_vacancy else 0
	var probability:=clampi(320+species_term+gratitude_term+personality_term \
		+help_term+vacancy_term,50,950)
	var reasons:Array[Dictionary]=[]
	if str(opening.choice)=="GAVE_POTION":
		reasons.append({"code":"RESCUED","label":"처음 만났을 때 건넨 물약을 기억합니다.","tone":"POSITIVE"})
	else:reasons.append({"code":"PASSED_BY","label":"처음 만났을 때 외면한 일을 기억합니다.","tone":"NEGATIVE"})
	if gratitude_term>0:
		reasons.append({"code":"PERSONAL_AFFECTION","label":"개인적인 감사가 남아 있습니다.","tone":"POSITIVE"})
	if personality_term>=40:
		reasons.append({"code":"OPEN_PERSONALITY","label":"낯선 동행을 받아들이는 성향입니다.","tone":"POSITIVE"})
	elif personality_term<=-40:
		reasons.append({"code":"GUARDED_PERSONALITY","label":"쉽게 마음을 열지 않는 성향입니다.","tone":"CAUTION"})
	if has_vacancy:
		reasons.append({"code":"PARTY_VACANCY","label":"파티에 함께할 빈자리가 있습니다.","tone":"POSITIVE"})
	var hero=sim.world.entities.get(state.protagonist_id)
	var adjacent:=hero!=null and maxi(absi(hero.position.x-entity.position.x),
		absi(hero.position.y-entity.position.y))<=1
	var legal:bool=has_vacancy and adjacent and str(combatant.life_state)=="ACTIVE" \
		and state.safe_phase in ["GROUPED","GROUPED_COMPLETE"] and not _run_is_complete()
	var reason:="ok"
	if not has_vacancy:reason="party_full"
	elif not adjacent:reason="recruitment_candidate_too_far"
	elif str(combatant.life_state)!="ACTIVE":reason="companion_unavailable"
	elif state.safe_phase not in ["GROUPED","GROUPED_COMPLETE"] or _run_is_complete():
		reason="party_roster_unsafe_phase"
	var key:="opening-recruit-v1|world=%d|personality=%d|candidate=%d|reencounter=%d"%[
		world_seed,personality_seed,entity_id,int(opening.reencounter_event_id)]
	var roll:=_stable_roll_milli(key) if legal else -1
	return _feedback_dto({"accepted":legal,"reason":reason,"entity_id":entity_id,
		"resolved":false,"joined":false,"probability_milli":probability,
		"probability_percent":int((probability+5)/10),"roll_milli":roll,
		"would_accept":legal and roll<probability,"ruleset_id":"opening-recruit-v1",
		"key_hash":key.sha256_text() if legal else "","reasons":reasons,
		"terms":{"species_prior":species_term,"personal_memory":gratitude_term,
			"personality":personality_term,"first_encounter":help_term,
			"vacancy":vacancy_term}})


func offer_recruitment(entity_id: int) -> Dictionary:
	var assessment := recruitment_assessment(entity_id)
	if not bool(assessment.get("accepted",false)): return assessment
	var rollback_value: Variant = sim.snapshot()
	if not rollback_value is Dictionary:
		return _rejection_dto("party_snapshot_unavailable")
	var rollback: Dictionary = rollback_value
	var hero_id: int = int(sim.world.party_encounter.protagonist_id)
	var result = sim.step(CommandScript.wait_for(RECRUITMENT_OFFER_TIME_COST,hero_id))
	if not result.accepted: return _rejection_dto(str(result.reason))
	_advance_exile_world()
	var joined := bool(assessment.would_accept)
	var event_type := "party.recruitment_accepted" if joined \
		else "party.recruitment_refused"
	var reason_codes: Array[String] = []
	for row in assessment.reasons: reason_codes.append(str(row.get("code","")))
	var decision = sim.world.emit_event(event_type, entity_id, hero_id,
		sim.world.entities[entity_id].position,
		int(assessment.probability_milli), -1, {"schema_version":1,
			"ruleset_id":str(assessment.get("ruleset_id",RECRUITMENT_RULESET_ID)),
			"probability_milli":int(assessment.probability_milli),
			"roll_milli":int(assessment.roll_milli),"accepted":joined,
			"reason_codes":reason_codes,
			"reasons":assessment.reasons.duplicate(true)})
	if decision == null:
		_restore_roster_rollback(rollback)
		return _rejection_dto("recruitment_resolution_failed")
	if joined:
		if not _prepare_rescue_candidate_for_roster(entity_id):
			_restore_roster_rollback(rollback)
			return _rejection_dto("recruitment_resolution_failed")
		var roster_result := _apply_roster_change("RECRUIT",entity_id,false,rollback)
		if not bool(roster_result.get("accepted",false)):
			_restore_roster_rollback(rollback)
			return _rejection_dto("recruitment_resolution_failed")
	else:
		sim.world.party_encounter.revision += 1
	if not sim.world.world_state_error().is_empty():
		_restore_roster_rollback(rollback)
		return _rejection_dto("recruitment_resolution_failed")
	_clear_draft(); _deployment_plan.clear()
	if _exploration_route != null: _exploration_route.clear()
	command_journal.append({"kind":"roster","operation":{
		"action":"OFFER_RECRUIT","entity_id":str(entity_id)}})
	return _feedback_dto({"accepted":true,"reason":"ok","resolved":true,
		"entity_id":entity_id,"joined":joined,
		"probability_milli":int(assessment.probability_milli),
		"probability_percent":int(assessment.probability_percent),
		"roll_milli":int(assessment.roll_milli),
		"reasons":assessment.reasons.duplicate(true),"consumes_time":true,
		"step_index":int(result.processed_step_index),
		"start_time":int(result.start_time),"end_time":int(result.end_time),
		"time_cost":RECRUITMENT_OFFER_TIME_COST,"event_ids":[decision.id]})


func _recruitment_reason_rows(species_base: Dictionary, relation: Dictionary,
		personality_term: int, survival_term: int, rescue_term: int,
		vacancy_term: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var base_trust := int(species_base.get("base_trust",0))
	var base_hostility := int(species_base.get("base_hostility",0))
	if base_trust>=15 and base_hostility<30:
		rows.append({"code":"SPECIES_AFFINITY","label":"종족 사이 기본 호감이 있습니다.","tone":"POSITIVE"})
	elif base_trust<=-20 or base_hostility>=45:
		rows.append({"code":"SPECIES_DISTRUST","label":"종족 사이 뿌리 깊은 경계가 있습니다.","tone":"NEGATIVE"})
	else:
		rows.append({"code":"SPECIES_WARY","label":"종족 차이 때문에 아직 조심스럽습니다.","tone":"CAUTION"})
	if rescue_term>0:
		rows.append({"code":"RESCUED","label":"당신이 목숨을 구해 준 일을 기억합니다.","tone":"POSITIVE"})
	if int(relation.get("gratitude",0))>=50 or int(relation.get("trust",0))>=25:
		rows.append({"code":"PERSONAL_AFFECTION","label":"개인적인 감사와 호감이 큽니다.","tone":"POSITIVE"})
	elif int(relation.get("hostility",0))>=45 or int(relation.get("trust",0))<0:
		rows.append({"code":"PERSONAL_WARY","label":"개인적으로도 아직 완전히 믿지 못합니다.","tone":"NEGATIVE"})
	if survival_term>=120:
		rows.append({"code":"SURVIVAL_THREAT","label":"부상이 심해 안전한 동행이 절실합니다.","tone":"POSITIVE"})
	if personality_term>=40:
		rows.append({"code":"OPEN_PERSONALITY","label":"도움을 받아들이는 성향입니다.","tone":"POSITIVE"})
	elif personality_term<=-40:
		rows.append({"code":"GUARDED_PERSONALITY","label":"쉽게 마음을 열지 않는 성향입니다.","tone":"CAUTION"})
	if vacancy_term>0:
		rows.append({"code":"PARTY_VACANCY","label":"파티에 함께할 빈자리가 있습니다.","tone":"POSITIVE"})
	return rows


static func _stable_roll_milli(key: String) -> int:
	var digest: PackedByteArray = key.sha256_buffer()
	var value := ((int(digest[0])&0x7f)<<24)|(int(digest[1])<<16) \
		|(int(digest[2])<<8)|int(digest[3])
	return value%1000


func _rescue_discovery_event_for(entity_id: int):
	if sim == null or sim.world == null: return null
	for event in sim.world.events:
		if event.type == "party.rescue_discovered" and event.target_id == entity_id:
			return event
	return null


func _rescue_event_for(entity_id: int):
	if sim == null or sim.world == null: return null
	for index in range(sim.world.events.size()-1,-1,-1):
		var event = sim.world.events[index]
		if event.type=="party.npc_stabilized" and event.target_id==entity_id:
			return event
	return null


func _npc_assault_event_for(entity_id:int):
	if sim==null or sim.world==null:return null
	for index in range(sim.world.events.size()-1,-1,-1):
		var event=sim.world.events[index]
		if event.type=="party.npc_assaulted" and event.target_id==entity_id:
			return event
	return null


func _rescue_personality_profile(entity_id: int):
	var discovery = _rescue_discovery_event_for(entity_id)
	if discovery == null: return null
	return PartyHexacoScript.generated(personality_seed, entity_id)


func _prepare_rescue_candidate_for_roster(entity_id: int) -> bool:
	if sim == null or sim.world == null or sim.world.party_encounter == null \
			or (_rescue_discovery_event_for(entity_id) == null \
			and not _is_opening_recruitment_candidate(entity_id)) \
			or not sim.world.entities.has(entity_id):
		return false
	var state = sim.world.party_encounter
	if state.member(entity_id) != null \
			or state.active_party_member_ids.size() >= ACTIVE_PARTY_LIMIT:
		return false
	var profile = sim.world.party_encounter.opening_event.hexaco_profile \
		if _is_opening_recruitment_candidate(entity_id) \
		else _rescue_personality_profile(entity_id)
	if profile == null: return false
	state.party_member_ids.append(entity_id)
	state.party_member_ids.sort()
	state.member_rows[entity_id] = MemberScript.new(entity_id, 0,
		"COMPANION", "RECRUITABLE", profile)
	state.member_rows[entity_id].busy_until = sim.world.world_time
	for roster_index in range(state.party_member_ids.size()):
		state.member_rows[state.party_member_ids[roster_index]].roster_slot = roster_index
	return true


func _recruitment_outcome_event_for(entity_id: int):
	if sim == null or sim.world == null: return null
	for index in range(sim.world.events.size()-1,-1,-1):
		var event = sim.world.events[index]
		if event.type in ["party.recruitment_accepted","party.recruitment_refused"] \
				and event.actor_id==entity_id:
			return event
	return null


func _restore_roster_rollback(snapshot: Dictionary) -> void:
	var restored = SimulatorScript.from_snapshot(snapshot)
	if restored != null: sim = restored


func roster_change_assessment(operation: String, entity_id: int) -> Dictionary:
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return _rejection_dto("session_not_initialized")
	var state = sim.world.party_encounter
	if state.safe_phase not in ["GROUPED", "GROUPED_COMPLETE"] or _run_is_complete():
		return _rejection_dto("party_roster_unsafe_phase")
	var member = state.member(entity_id)
	if member == null or not sim.world.entities.has(entity_id):
		return _rejection_dto("party_member_not_found")
	if operation == "DISMISS":
		if entity_id == state.protagonist_id: return _rejection_dto("protagonist_dismiss_forbidden")
		if entity_id not in state.active_party_member_ids: return _rejection_dto("companion_not_active")
		if member.role != "COMPANION" or sim.world.combatant_states[entity_id].life_state != "ACTIVE":
			return _rejection_dto("companion_unavailable")
	elif operation == "RECRUIT":
		if entity_id in state.active_party_member_ids or entity_id not in state.party_member_ids \
				or member.role != "COMPANION" or member.presence != "RECRUITABLE":
			return _rejection_dto("companion_not_recruitable")
		if state.active_party_member_ids.size() >= ACTIVE_PARTY_LIMIT: return _rejection_dto("party_full")
		if sim.world.combatant_states[entity_id].life_state != "ACTIVE": return _rejection_dto("companion_unavailable")
	else:
		return _rejection_dto("invalid_roster_operation")
	return _feedback_dto({"accepted":true,"reason":"ok","operation":operation,
		"entity_id":entity_id,"active_party_member_ids":state.active_party_member_ids.duplicate(true)})


func recruitable_companions() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if sim == null or sim.world == null or sim.world.party_encounter == null: return rows
	var state = sim.world.party_encounter
	for entity_id in state.party_member_ids:
		if entity_id in state.active_party_member_ids: continue
		var member = state.member(entity_id); var entity = sim.world.entities.get(entity_id)
		if member == null or entity == null or member.presence != "RECRUITABLE": continue
		var style := personality_style(member.personality_profile)
		var assessment := roster_change_assessment("RECRUIT", entity_id)
		rows.append({"entity_id":entity_id,"roster_slot":int(member.roster_slot),
			"display_name":str(entity.display_name),"presence":str(member.presence),
			"health":int(entity.health),"max_health":int(entity.max_health),
			"life_state":"ACTIVE","authoritative_life_state":"ACTIVE",
			"status_ids":_combatant_status_ids(entity_id),
			"style_label":str(style.get("label","동료")),
			"rescue_state":"AVAILABLE","can_stabilize":false,"stabilization":{},
			"decision_available":false,"recruitment":{},
			"can_recruit":bool(assessment.get("accepted",false)),
			"reason":str(assessment.get("reason","ok")),
			"message":str(assessment.get("message",""))})
	for entity_id_value in rescue_candidate_ids():
		var entity_id := int(entity_id_value)
		var entity = sim.world.entities[entity_id]
		var story_state := rescue_story_state(entity_id)
		var rescue := rescue_assessment(entity_id) if story_state=="COLLAPSED_STORY" else {}
		var recruitment := recruitment_assessment(entity_id) \
			if story_state in ["OFFER_READY","REJECTED"] else {}
		var profile = _rescue_personality_profile(entity_id)
		var style := personality_style(profile)
		rows.append({"entity_id":entity_id,"roster_slot":63,
			"display_name":str(entity.display_name),"presence":"WORLD_NPC",
			"health":int(entity.health),"max_health":int(entity.max_health),
			"life_state":"DOWNED" if story_state=="COLLAPSED_STORY" else "ACTIVE",
			"authoritative_life_state":str(sim.world.combatant_states[entity_id].life_state),
			"status_ids":_combatant_status_ids(entity_id),
			"style_label":str(style.get("label","동료")),
			"rescue_state":story_state,"can_stabilize":bool(rescue.get("accepted",false)),
			"stabilization":rescue.duplicate(true),
			"decision_available":story_state in ["OFFER_READY","REJECTED"],
			"recruitment":recruitment.duplicate(true),
			"can_recruit":bool(recruitment.get("accepted",false)),
			"reason":str(recruitment.get("reason",rescue.get("reason","ok"))),
			"message":str(recruitment.get("message",rescue.get("message","")))})
	rows.sort_custom(func(a:Dictionary,b:Dictionary):
		return int(a.roster_slot)<int(b.roster_slot) if int(a.roster_slot)!=int(b.roster_slot) \
			else int(a.entity_id)<int(b.entity_id))
	return rows.duplicate(true)


func exile_story_records() -> Array:
	if sim==null or sim.world==null or sim.world.party_encounter==null:return []
	return sim.world.party_encounter.exile_records.duplicate(true)


func _exile_record_for_member(entity_id:int):
	for record in sim.world.party_encounter.exile_records:
		if int(str(record.former_member_id))==entity_id:return record.duplicate(true)
	return null


func dismiss_companion(entity_id: int) -> Dictionary:
	return _apply_roster_change("DISMISS", entity_id)


func recruit_companion(entity_id: int) -> Dictionary:
	if _rescue_discovery_event_for(entity_id)!=null:
		return _rejection_dto("recruitment_already_resolved") \
			if _recruitment_outcome_event_for(entity_id)!=null \
			else _rejection_dto("recruitment_offer_required")
	return _apply_roster_change("RECRUIT", entity_id)


func _apply_roster_change(operation: String, entity_id: int,
		append_journal: bool = true,rollback_override:Dictionary={}) -> Dictionary:
	var assessment := roster_change_assessment(operation, entity_id)
	if not bool(assessment.get("accepted",false)): return assessment
	var rollback: Dictionary = rollback_override.duplicate(true) \
		if not rollback_override.is_empty() else sim.snapshot()
	if rollback.is_empty():return _rejection_dto("party_snapshot_unavailable")
	var state = sim.world.party_encounter
	var exile_condition: Dictionary = _exile_condition(entity_id) if operation=="DISMISS" else {}
	if operation=="DISMISS" and not bool(exile_condition.get("valid",false)):
		return _rejection_dto("party_roster_change_failed")
	if operation == "DISMISS":
		state.active_party_member_ids.erase(entity_id)
		state.member(entity_id).presence = "EXILED"
		# Exile is permanent and removes the tombstone from every future lifecycle
		# target. Status history remains in the immutable event stream, while the
		# no-longer-observable entity keeps no live status row.
		sim.world.combatant_states[entity_id].status_rows.clear()
	else:
		state.active_party_member_ids.append(entity_id); state.active_party_member_ids.sort()
		state.member(entity_id).presence = "GROUPED"
		sim.world.entities[entity_id].position = state.group_anchor
	var event_type := "party.companion_dismissed" if operation == "DISMISS" \
		else "party.companion_recruited"
	var event_data:={"operation":operation}
	if operation=="DISMISS":
		event_data["condition_band"]=str(exile_condition.condition_band)
		event_data["resentment_delta"]=int(exile_condition.resentment_delta)
	var event = sim.world.emit_event(event_type, state.protagonist_id, entity_id,
		state.group_anchor, 0, -1, event_data)
	if event!=null and operation=="DISMISS":
		if not sim.relationships.record_harm(entity_id,state.protagonist_id,event.id,
				int(exile_condition.resentment_delta)):
			event=null
		else:
			state.exile_records.append(_new_exile_record(entity_id,event.id,exile_condition))
	state.revision += 1
	var roster_world_error:String=sim.world.world_state_error()
	if event == null or not roster_world_error.is_empty():
		var restored = SimulatorScript.from_snapshot(rollback)
		if restored != null: sim = restored
		return _rejection_dto("party_roster_change_failed")
	_clear_draft(); _deployment_plan.clear()
	if _exploration_route != null: _exploration_route.clear()
	if append_journal:
		command_journal.append({"kind":"roster","operation":{
			"action":operation,"entity_id":str(entity_id)}})
	return _feedback_dto({"accepted":true,"reason":"ok","operation":operation,
		"entity_id":entity_id,"active_party_member_ids":state.active_party_member_ids.duplicate(true),
		"recruitable_member_ids":_member_ids_with_presence("RECRUITABLE"),
		"exiled_member_ids":_member_ids_with_presence("EXILED")})


func _exile_condition(entity_id:int)->Dictionary:
	if sim.world.step_index>9223372036854775807-EXILE_ENCOUNTER_STEP_DELAY:return {"valid":false}
	var entity=sim.world.entities[entity_id];var member=sim.world.party_encounter.member(entity_id)
	var status_effects:Array=[]
	for status in sim.world.combatant_states[entity_id].status_rows:
		var remaining:=clampi(int((status.expires_at-status.next_tick_at)/EXILE_WORLD_INTERVAL)+1,1,16)
		status_effects.append({"status_id":str(status.status_id),"remaining_ticks":remaining,
			"tick_damage":3 if str(status.status_id)=="BLEEDING" else 2})
	status_effects.sort_custom(func(a:Dictionary,b:Dictionary):return str(a.status_id)<str(b.status_id))
	var harmful_status:=not status_effects.is_empty()
	var hp_percent:=int(entity.health*100/maxi(1,entity.max_health));var band:="STRAINED"
	if hp_percent>=70 and member.stress<350 and not harmful_status:band="HEALTHY"
	elif hp_percent<=30 or member.stress>=750 or harmful_status:band="ENDANGERED"
	var relation:Dictionary=sim.relationships.effective_relation(entity_id,
		sim.world.party_encounter.protagonist_id)
	var resilience:=PartyMoraleModelScript.morale_resilience(member.personality_profile)
	var vulnerability:=(100-hp_percent)+int(member.stress/10)+(45 if harmful_status else 0)
	var resentment_delta:=clampi(15+int(vulnerability/2)+int(relation.get("grievance",0)/4)-int(resilience/50),10,100)
	var fear_delta:=clampi(int((100-hp_percent)/2)+int(member.stress/20)+(20 if harmful_status else 0),5,100)
	return {"valid":true,"condition_band":band,"resentment_delta":resentment_delta,
		"fear_delta":fear_delta,"hp_percent":hp_percent,"stress":int(member.stress),
		"harmful_status":harmful_status,"status_effects":status_effects}


func _new_exile_record(entity_id:int,dismissal_event_id:int,condition:Dictionary)->Dictionary:
	var entity=sim.world.entities[entity_id];var member=sim.world.party_encounter.member(entity_id)
	var style:=personality_style(member.personality_profile)
	var profile_wire:Dictionary=member.personality_profile.to_dict()
	var relation:Dictionary=sim.relationships.effective_relation(entity_id,
		sim.world.party_encounter.protagonist_id)
	return {"schema_version":2,"former_member_id":str(entity_id),
		"display_name":str(entity.display_name),"species_id":str(entity.species_id),
		"personality_summary":{"style_label":str(style.get("label","")),
			"profile_hash":JSON.stringify(profile_wire).sha256_text(),
			"H":int(member.personality_profile.value("H")),
			"E":int(member.personality_profile.value("E")),
			"X":int(member.personality_profile.value("X")),
			"A":int(member.personality_profile.value("A")),
			"C":int(member.personality_profile.value("C")),
			"O":int(member.personality_profile.value("O"))},
		"dismissed_world_time":str(sim.world.world_time),
		"dismissed_step_index":str(sim.world.step_index),"dismissal_event_id":str(dismissal_event_id),
		"condition_snapshot":{"condition_band":str(condition.condition_band),"hp":int(entity.health),
			"hp_percent":int(condition.hp_percent),"stress":int(condition.stress),
			"harmful_status":bool(condition.harmful_status)},
		"emotion_modifiers":{"resentment_delta":int(condition.resentment_delta),
			"fear_delta":int(condition.fear_delta)},
		"relationship_snapshot":{"trust":int(relation.get("trust",0)),"fear":int(relation.get("fear",0)),
			"hostility":int(relation.get("hostility",0)),"gratitude":int(relation.get("gratitude",0)),
			"grievance":int(relation.get("grievance",0))},
		"current_hp":int(entity.health),"max_hp":int(entity.max_health),
		"alive":sim.world.combatant_states[entity_id].life_state == "ACTIVE",
		"initial_status_effects":condition.status_effects.duplicate(true),
		"status_effects":condition.status_effects.duplicate(true),"location_id":"OFFSCREEN_WILDERNESS",
		"initial_safety":{"HEALTHY":400,"STRAINED":250,"ENDANGERED":100}[str(condition.condition_band)],
		"safety":{"HEALTHY":400,"STRAINED":250,"ENDANGERED":100}[str(condition.condition_band)],
		"current_behavior":"SEEK_SAFETY","last_world_time":str(sim.world.world_time),
		"last_world_step":str(sim.world.step_index),
		"encounter_eligible_after_step":str(sim.world.step_index+EXILE_ENCOUNTER_STEP_DELAY)}


func _advance_exile_world()->void:
	var state=sim.world.party_encounter
	for index in range(state.exile_records.size()):
		var record:Dictionary=state.exile_records[index]
		if not bool(record.alive):continue
		var next_tick:=int(str(record.last_world_time))+EXILE_WORLD_INTERVAL
		var processed:=false
		while next_tick<=sim.world.world_time and bool(record.alive):
			processed=true
			var hp_before:=int(record.current_hp);var behavior:="SEEK_SAFETY"
			var status_rows:Array=record.status_effects.duplicate(true);var remaining:Array=[];var expired:Array=[]
			if not status_rows.is_empty():
				behavior="SELF_TREAT" if int(record.personality_summary.C)>=450 \
					or int(record.safety)>=400 else "SEEK_SAFETY"
				for status in status_rows:
					record.current_hp=maxi(0,int(record.current_hp)-int(status.tick_damage))
					var duration_cost:=2 if behavior=="SELF_TREAT" else 1
					status.remaining_ticks=int(status.remaining_ticks)-duration_cost
					if int(status.remaining_ticks)>0 and int(record.current_hp)>0:remaining.append(status)
					else:expired.append(str(status.status_id))
				record.status_effects=remaining
			else:
				behavior="RECOVER"
				var recovery:=3 if int(record.safety)>=500 else 1
				record.current_hp=mini(int(record.max_hp),int(record.current_hp)+recovery)
			record.safety=mini(1000,int(record.safety)+150)
			record.alive=int(record.current_hp)>0
			record.current_behavior=behavior if bool(record.alive) else "DEAD"
			var tick=sim.world.emit_event("party.exile_world_tick",-1,
				int(str(record.former_member_id)),Vector2i(-1,-1),maxi(0,hp_before-int(record.current_hp)),
				int(str(record.dismissal_event_id)),{"behavior":str(record.current_behavior),
					"alive":bool(record.alive),"expired_status_ids":expired,
					"hp_after":int(record.current_hp),"hp_before":hp_before,
					"safety_after":int(record.safety),
					"scheduled_world_time":str(next_tick),
					"status_effects_after":record.status_effects.duplicate(true)})
			if tick==null:return
			if not bool(record.alive):
				record.status_effects=[]
				if sim.world.emit_event("party.exile_died",-1,int(str(record.former_member_id)),
						Vector2i(-1,-1),0,tick.id,{"reason":"OFFSCREEN_CONDITION"})==null:return
			next_tick+=EXILE_WORLD_INTERVAL
		if processed:
			record.last_world_time=str(sim.world.world_time);record.last_world_step=str(sim.world.step_index)
			state.exile_records[index]=record;state.revision+=1


func exile_encounter_evaluation(entity_id:int)->Dictionary:
	var record=_exile_record_for_member(entity_id)
	if record==null:return {"eligible":false,"reason":"exile_record_not_found"}
	if not bool(record.alive):return {"eligible":false,"reason":"exile_actor_dead","action":"NONE"}
	if sim.world.step_index<int(str(record.encounter_eligible_after_step)):
		return {"eligible":false,"reason":"exile_encounter_too_early","action":"NONE"}
	var hostility:=clampi(int(record.relationship_snapshot.hostility) \
		+int(record.emotion_modifiers.resentment_delta/5),0,100)
	var fear:=clampi(int(record.relationship_snapshot.fear)+int(record.emotion_modifiers.fear_delta),0,100)
	var action:="HOSTILE" if hostility>=60 and fear<85 else ("AVOID" if fear>=60 else "DIALOGUE")
	return {"eligible":true,"reason":"ok","action":action,"hostility":hostility,"fear":fear,
		"former_member_id":entity_id,"identity":{"display_name":record.display_name,
			"species_id":record.species_id,"personality_summary":record.personality_summary.duplicate(true)}}.duplicate(true)


func _member_ids_with_presence(presence: String) -> Array:
	var ids: Array = []
	if sim == null or sim.world == null or sim.world.party_encounter == null: return ids
	var state = sim.world.party_encounter
	for entity_id in state.party_member_ids:
		if state.member(entity_id).presence == presence: ids.append(entity_id)
	return ids

func deployment_draft() -> Dictionary:
	if _deployment_plan.is_empty():
		return _feedback_dto({"has_preview": false, "accepted": false,
			"reason": "deployment_preview_required", "preset_id": "NONE",
			"companion_ids": [], "placements": []}, null, null, {"action_type": "DEPLOY"})
	return _feedback_dto({"has_preview": true, "accepted": bool(_deployment_plan.get("accepted", false)),
		"reason": str(_deployment_plan.get("reason", "invalid_deployment_plan")),
		"preset_id": str(_deployment_plan.get("preset_id", "NONE")),
		"companion_ids": _deployment_plan.get("companion_ids", []).duplicate(true),
		"placements": _deployment_plan.get("placements", []).duplicate(true)}, null, null,
		{"action_type": "DEPLOY"})

func enemy_targets() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var status := party_status()
	for enemy_id in status.get("visible_enemy_ids", []):
		var entity = sim.world.entities[int(enemy_id)]
		var threat:=_enemy_threat(entity.id)
		rows.append({"entity_id": entity.id, "display_name": entity.display_name, "health": entity.health,
			"max_health": entity.max_health, "alive": sim.world.is_unresolved_enemy(enemy_id),
			"level":int(threat.level),"threat_id":str(threat.threat_id),
			"threat_label":str(threat.threat_label),"position": [entity.position.x, entity.position.y]})
	return rows.duplicate(true)


func tab_attack_assessment() -> Dictionary:
	# DCSS-style Tab authority: inspect only currently visible enemies, then
	# choose exactly one ordinary action. Holding/repeating the UI command is what
	# advances multiple turns; this assessment never creates an uninterruptible
	# combat macro or a new journal format.
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return _rejection_dto("session_not_initialized")
	if not is_solo_combat(): return _rejection_dto("tab_attack_solo_only")
	var status := party_status()
	if bool(status.get("terminal", false)) or _run_is_complete():
		return _rejection_dto("run_complete")
	var state = sim.world.party_encounter
	var hero = sim.world.entities.get(state.protagonist_id)
	if hero == null: return _rejection_dto("item_actor_missing")
	var visible := _presentation_visible_cells(hero.position)
	var enemy_ids: Array[int] = []
	for enemy_id_value in state.enemy_ids:
		var enemy_id := int(enemy_id_value)
		var enemy = sim.world.entities.get(enemy_id)
		if enemy != null and sim.world.is_unresolved_enemy(enemy_id) \
				and visible.has(_position_key(enemy.position)):
			enemy_ids.append(enemy_id)
	enemy_ids.sort()
	if enemy_ids.is_empty(): return _rejection_dto("tab_attack_no_visible_enemy")
	var phase := str(status.get("safe_phase", ""))
	if phase == "CONTACT":
		var contact_target := _nearest_tab_enemy(hero.position, enemy_ids)
		return _feedback_dto({"accepted":true,"reason":"ok",
			"tab_action":"ENTER_COMBAT","target_id":contact_target,
			"target_name":_name(contact_target),"destination":[]})
	if phase == "ENGAGED":
		var equipment:=protagonist_equipment()
		var attack_block_reason:=str(equipment.get("attack_block_reason",""))
		if attack_block_reason in ["reload_required","ammo_empty"]:
			return _rejection_dto(attack_block_reason)
		# Test nearest candidates first. The former full preview built damage,
		# schedule and integrity data here, then rebuilt it during the immediate
		# commit. This legality-only seam preserves target selection while keeping
		# the expensive authoritative preview single-shot.
		enemy_ids.sort_custom(func(a:int,b:int):
			var enemy_a=sim.world.entities.get(a);var enemy_b=sim.world.entities.get(b)
			var distance_a:=maxi(absi(enemy_a.position.x-hero.position.x),
				absi(enemy_a.position.y-hero.position.y))
			var distance_b:=maxi(absi(enemy_b.position.x-hero.position.x),
				absi(enemy_b.position.y-hero.position.y))
			return distance_a<distance_b if distance_a!=distance_b else a<b)
		for enemy_id in enemy_ids:
			var request = RequestScript.new(ActionScript.melee(state.protagonist_id,
				enemy_id), [])
			if sim.direct_solo_party_action_error(request).is_empty():
				return _feedback_dto({"accepted":true,"reason":"ok",
					"tab_action":"ATTACK","target_id":enemy_id,
					"target_name":_name(enemy_id),"destination":[]})
	elif phase not in ["GROUPED", "GROUPED_COMPLETE"]:
		return _rejection_dto("tab_attack_phase_unavailable")
	var approach := _nearest_tab_approach(state.protagonist_id, enemy_ids,
		phase == "ENGAGED")
	if approach.is_empty(): return _rejection_dto("tab_attack_no_path")
	return _feedback_dto({"accepted":true,"reason":"ok",
		"tab_action":"APPROACH","target_id":int(approach.target_id),
		"target_name":_name(int(approach.target_id)),
		"destination":[int(approach.destination.x),int(approach.destination.y)],
		"path_steps":int(approach.steps),"path_cost":int(approach.cost)})


func _nearest_tab_enemy(origin:Vector2i, enemy_ids:Array[int])->int:
	var best_id := -1
	var best_distance := 2147483647
	for enemy_id in enemy_ids:
		var enemy = sim.world.entities.get(enemy_id)
		if enemy == null: continue
		var distance := maxi(absi(enemy.position.x-origin.x),
			absi(enemy.position.y-origin.y))
		if distance < best_distance or distance == best_distance \
				and (best_id < 0 or enemy_id < best_id):
			best_distance = distance; best_id = enemy_id
	return best_id


func _nearest_tab_approach(actor_id:int, enemy_ids:Array[int], combat:bool)->Dictionary:
	var best: Dictionary = {}
	for enemy_id in enemy_ids:
		var enemy = sim.world.entities.get(enemy_id)
		if enemy == null: continue
		var goals: Array[Vector2i] = []
		for direction in MovementSystemScript.MOVE_DIRECTIONS_8:
			var goal: Vector2i = enemy.position + direction
			if not sim.world.in_bounds(goal) \
					or sim.world.blocking_entity_at(goal, actor_id) != null:
				continue
			var terrain: Dictionary = TerrainRegistryScript.definition(
				str(sim.world.tile_at(goal).terrain))
			if not terrain.is_empty() and bool(terrain.get("passable", false)):
				goals.append(goal)
		var route: Dictionary = {}
		if combat:
			route = sim.party_coordinator.pathfinder.find_path_to_any(actor_id, goals)
		else:
			route = find_exploration_path_to_any(actor_id, goals)
		if not bool(route.get("found", false)) or int(route.get("steps", 0)) < 1:
			continue
		var path: Array = route.get("path", [])
		if path.size() < 2 or not path[1] is Vector2i: continue
		var row := {"target_id":enemy_id,"destination":path[1],
			"steps":int(route.get("steps", 0)),"cost":int(route.get("total_cost", 0))}
		if best.is_empty() or _tab_approach_less(row, best): best = row
	return best.duplicate(true)


func _tab_approach_less(a:Dictionary,b:Dictionary)->bool:
	for key in ["steps","cost","target_id"]:
		if int(a[key]) != int(b[key]): return int(a[key]) < int(b[key])
	var ap:Vector2i=a.destination;var bp:Vector2i=b.destination
	return ap.y < bp.y if ap.y != bp.y else ap.x < bp.x


func inspect_enemy(entity_id:int)->Dictionary:
	if sim==null or sim.world==null or sim.world.party_encounter==null \
			or entity_id not in sim.world.party_encounter.enemy_ids \
			or not sim.world.entities.has(entity_id):return _rejection_dto("enemy_not_found")
	var entity=sim.world.entities[entity_id]
	var profile=sim.world.combatant_states[entity_id]
	var combat_profile=load("res://sim/combat_profile_registry.gd").profile(profile.combat_profile_id)
	var threat:=_enemy_threat(entity_id)
	return _feedback_dto({"accepted":true,"reason":"ok","schema_version":1,
		"entity_id":entity_id,"display_name":str(entity.display_name),
		"health":int(entity.health),"max_health":int(entity.max_health),
		"life_state":str(profile.life_state),"level":int(threat.level),
		"threat_id":str(threat.threat_id),"threat_label":str(threat.threat_label),
		"capability_score":int(threat.enemy_score),
		"base_power":int(combat_profile.get("power",0)),
		"armor_flat":int(combat_profile.get("armor_flat",0)),
		"level_derivation":"canonical combat profile and maximum health"})


func _enemy_threat(entity_id:int)->Dictionary:
	var state=sim.world.party_encounter
	var enemy=sim.world.entities[entity_id];var hero=sim.world.entities[state.protagonist_id]
	var enemy_score:=_combat_capability_score(entity_id,true)
	var hero_score:=maxi(1,_combat_capability_score(state.protagonist_id,false))
	var ratio:=int(enemy_score*100/hero_score)
	var threat_id:="TRIVIAL" if ratio<50 else ("EVEN" if ratio<=85 else (
		"DANGEROUS" if ratio<=120 else "LETHAL"))
	return {"level":1+maxi(0,enemy_score-200)/100,"threat_id":threat_id,
		"threat_label":{"TRIVIAL":"하찮음","EVEN":"대등","DANGEROUS":"위험",
			"LETHAL":"치명적"}[threat_id],"enemy_score":enemy_score,
		"hero_score":hero_score,"enemy_hp":int(enemy.health),"hero_hp":int(hero.health)}


func _combat_capability_score(entity_id:int,use_max_health:bool)->int:
	var entity=sim.world.entities[entity_id]
	var combatant=sim.world.combatant_states[entity_id]
	var profile=load("res://sim/combat_profile_registry.gd").profile(combatant.combat_profile_id)
	var power:=int(profile.get("power",0))
	if entity_id==sim.world.party_encounter.protagonist_id:
		power+=ProgressionRegistryScript.melee_power_bonus(
			sim.world.party_encounter.protagonist_progression.rank("MELEE"))
	return power*4+int(profile.get("accuracy_milli",0))/20 \
		+int(profile.get("evasion_milli",0))/20+int(profile.get("armor_flat",0))*10 \
		+(int(entity.max_health) if use_max_health else int(entity.health))

func commit_exploration_direction(direction: Vector2i) -> Dictionary:
	if direction not in [Vector2i.ZERO, Vector2i.UP, Vector2i(1,-1), Vector2i.RIGHT, Vector2i(1,1),
			Vector2i.DOWN, Vector2i(-1,1), Vector2i.LEFT, Vector2i(-1,-1)]:
		return _rejection_dto("invalid_exploration_direction", null, null,
			{"action_type": "MOVE", "direction": [direction.x, direction.y]})
	var status := party_status()
	if not bool(status.get("ok", false)): return _rejection_dto(str(status.get("reason", "session_not_initialized")))
	if str(status.get("view_mode",""))!="EXPLORATION":
		return _rejection_dto("exploration_phase_required")
	var hero_id := int(status.protagonist_id)
	var command = CommandScript.wait(hero_id) if direction == Vector2i.ZERO else CommandScript.move_to(
		hero_id, Vector2i(int(status.protagonist_position[0]), int(status.protagonist_position[1])) + direction)
	return commit_exploration(command,true)


func select_movement_destination(actor_id: int, destination_value: Variant) -> Dictionary:
	# One mutating facade for a map-cell tap. Exploration starts the canonical
	# route and commits exactly its first hop; combat directly replaces the
	# actor's pending action without creating a second placement preview.
	if _auto_explore != null and bool(_auto_explore.state().get("running", false)):
		_auto_explore.cancel("auto_explore_user_command")
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return _rejection_dto("session_not_initialized")
	var parsed := _inspection_position(destination_value)
	if not bool(parsed.get("ok", false)):
		return _rejection_dto("invalid_party_destination", null, null,
			{"actor_id":actor_id,"action_type":"MOVE","destination":[]})
	var destination: Vector2i = parsed.position
	var status := party_status()
	if str(status.get("view_mode", "")) == "EXPLORATION":
		if actor_id != int(status.get("protagonist_id", -1)):
			return _rejection_dto("move_requires_actor", null, null,
				{"actor_id":actor_id,"action_type":"MOVE",
					"destination":[destination.x,destination.y]})
		if bool(exploration_route_state().get("active", false)):
			cancel_exploration_route()
		var route := preview_exploration_route(destination)
		if not bool(route.get("accepted", false)): return route
		return start_exploration_route(destination, str(route.get("plan_hash", "")))
	if str(status.get("view_mode", "")) == "COMBAT":
		return set_actor_action(actor_id, "MOVE", [destination.x, destination.y])
	return _rejection_dto("invalid_party_action", null, null,
		{"actor_id":actor_id,"action_type":"MOVE",
			"destination":[destination.x,destination.y]})


func find_exploration_path(actor_id: int, goal: Vector2i) -> Dictionary:
	# First preserve the exact deterministic shortest/fastest route. Risk only
	# participates when that route crosses a currently visible hazard. The risk
	# pass is bounded so avoiding one tile can never invent a map-wide detour.
	var visible := _exploration_visible_cells()
	var shortest := _search_exploration_path(actor_id, goal, visible, false, -1)
	if not bool(shortest.get("found", false)):
		return shortest.duplicate(true)
	if int(shortest.get("max_total_risk", 0)) <= 0:
		shortest["routing_policy"] = "SHORTEST_HAZARD_FREE"
		shortest["hazard_free"] = true
		shortest["risk_weighted"] = false
		return shortest.duplicate(true)
	var shortest_steps := int(shortest.get("steps", 0))
	var detour_allowance := mini(MAX_VISIBLE_HAZARD_DETOUR_STEPS,
		maxi(2, shortest_steps / 2 + 1))
	var weighted := _search_exploration_path(actor_id, goal, visible, true,
		shortest_steps + detour_allowance)
	if not bool(weighted.get("found", false)):
		weighted = shortest
	weighted["routing_policy"] = "VISIBLE_AFFINITY_RISK_WEIGHTED"
	weighted["hazard_free"] = int(weighted.get("max_total_risk", 0)) <= 0
	weighted["risk_weighted"] = true
	weighted["shortest_steps"] = shortest_steps
	weighted["detour_limit_steps"] = shortest_steps + detour_allowance
	return weighted.duplicate(true)


func find_exploration_path_to_any(actor_id:int,goals:Array[Vector2i])->Dictionary:
	# Tab approaches any attack-adjacent tile. One multi-goal search preserves the
	# same bounded visible-hazard policy while avoiding eight scans of the map.
	var visible:=_exploration_visible_cells()
	var shortest:=_search_exploration_path_to_any(actor_id,goals,visible,false,-1)
	if not bool(shortest.get("found",false)):return shortest.duplicate(true)
	if int(shortest.get("max_total_risk",0))<=0:
		shortest["routing_policy"]="SHORTEST_HAZARD_FREE"
		shortest["hazard_free"]=true;shortest["risk_weighted"]=false
		return shortest.duplicate(true)
	var shortest_steps:=int(shortest.get("steps",0))
	var detour_allowance:=mini(MAX_VISIBLE_HAZARD_DETOUR_STEPS,
		maxi(2,shortest_steps/2+1))
	var weighted:=_search_exploration_path_to_any(actor_id,goals,visible,true,
		shortest_steps+detour_allowance)
	if not bool(weighted.get("found",false)):weighted=shortest
	weighted["routing_policy"]="VISIBLE_AFFINITY_RISK_WEIGHTED"
	weighted["hazard_free"]=int(weighted.get("max_total_risk",0))<=0
	weighted["risk_weighted"]=true;weighted["shortest_steps"]=shortest_steps
	weighted["detour_limit_steps"]=shortest_steps+detour_allowance
	return weighted.duplicate(true)


func _search_exploration_path_to_any(actor_id:int,goals:Array[Vector2i],
		visible:Dictionary,risk_weighted:bool,maximum_steps:int)->Dictionary:
	if not sim.world.entities.has(actor_id) \
			or not sim.world.can_act(actor_id,sim.world.world_time):
		return _exploration_path_failure("actor_not_found")
	var goal_set:Dictionary={}
	for goal in goals:
		if not sim.world.in_bounds(goal):continue
		if sim.world.blocking_entity_at(goal,actor_id)!=null:continue
		var definition:Dictionary=TerrainRegistryScript.definition(
			sim.world.tile_at(goal).terrain)
		if not definition.is_empty() and bool(definition.get("passable",false)):
			goal_set[_position_key(goal)]=true
	if goal_set.is_empty():return _exploration_path_failure("path_unreachable")
	var start:Vector2i=sim.world.entities[actor_id].position
	if goal_set.has(_position_key(start)):
		return {"found":true,"reason":"already_there","path":[start],
			"total_cost":0,"steps":0,"total_risk":0,"max_total_risk":0}
	var start_key:=_position_key(start)+("@0" if risk_weighted else "")
	var open:Array[Dictionary]=[{"position":start,"risk":0,"max_risk":0,
		"steps":0,"cost":0,"sequence":0,"state_key":start_key,"path":[start]}]
	var sequence:=1;var best:Dictionary={start_key:[0,0,0,0]}
	while not open.is_empty():
		open.sort_custom(func(a:Dictionary,b:Dictionary):
			return _exploration_open_less(a,b,risk_weighted))
		var node:Dictionary=open.pop_front();var position:Vector2i=node.position
		var known:Array=best.get(str(node.state_key),[])
		var signature:Array=[int(node.max_risk),int(node.risk),
			int(node.steps),int(node.cost)]
		if known!=signature:continue
		if goal_set.has(_position_key(position)):
			var route_risk:=int(node.risk);var route_max_risk:=int(node.max_risk)
			if not risk_weighted:
				route_risk=0;route_max_risk=0
				for path_index in range(1,node.path.size()):
					var path_risk:=_exploration_step_risk(node.path[path_index],visible)
					route_risk+=path_risk;route_max_risk=maxi(route_max_risk,path_risk)
			return {"found":true,"reason":"ok","path":node.path.duplicate(),
				"total_cost":int(node.cost),"steps":int(node.steps),
				"total_risk":route_risk,"max_total_risk":route_max_risk}
		for direction in MovementSystemScript.MOVE_DIRECTIONS_8:
			var next:Vector2i=position+direction
			if not _exploration_step_is_legal(actor_id,position,next):continue
			var candidate_steps:=int(node.steps)+1
			if maximum_steps>=0 and candidate_steps>maximum_steps:continue
			# Risk does not affect the first pass ordering. Evaluate only the final
			# shortest path, then run the bounded weighted pass if it is hazardous.
			var step_risk:=_exploration_step_risk(next,visible) if risk_weighted else 0
			var definition:Dictionary=TerrainRegistryScript.definition(
				sim.world.tile_at(next).terrain)
			var candidate_key:=_position_key(next)+("@%d"%candidate_steps \
				if risk_weighted else "")
			var candidate_path:Array=node.path.duplicate();candidate_path.append(next)
			var candidate:={"position":next,"risk":int(node.risk)+step_risk,
				"max_risk":maxi(int(node.max_risk),step_risk),"steps":candidate_steps,
				"cost":int(node.cost)+int(definition.move_time_cost),
				"sequence":sequence,"state_key":candidate_key,"path":candidate_path}
			sequence+=1
			var old:Array=best.get(candidate_key,[])
			if not old.is_empty() and not _exploration_score_less(candidate,old,
					risk_weighted):continue
			best[candidate_key]=[int(candidate.max_risk),int(candidate.risk),
				int(candidate.steps),int(candidate.cost)]
			open.append(candidate)
	return _exploration_path_failure("path_unreachable")


func _search_exploration_path(actor_id: int, goal: Vector2i,
		visible: Dictionary, risk_weighted: bool, maximum_steps: int) -> Dictionary:
	if not sim.world.entities.has(actor_id) or not sim.world.can_act(actor_id, sim.world.world_time):
		return _exploration_path_failure("actor_not_found")
	if not sim.world.in_bounds(goal): return _exploration_path_failure("out_of_bounds")
	var start: Vector2i = sim.world.entities[actor_id].position
	if start == goal:
		return {"found":true,"reason":"already_there","path":[start],
			"total_cost":0,"steps":0,"total_risk":0,"max_total_risk":0}
	if sim.world.blocking_entity_at(goal, actor_id) != null:
		return _exploration_path_failure("occupied")
	var goal_definition: Dictionary = TerrainRegistryScript.definition(sim.world.tile_at(goal).terrain)
	if goal_definition.is_empty() or not bool(goal_definition.get("passable", false)):
		return _exploration_path_failure("path_unreachable")
	var start_key := _position_key(start) + ("@0" if risk_weighted else "")
	var open: Array[Dictionary] = [{"position":start,"risk":0,"max_risk":0,
		"steps":0,"cost":0,"sequence":0,"state_key":start_key,"path":[start]}]
	var sequence := 1
	var best: Dictionary = {start_key:[0,0,0,0]}
	while not open.is_empty():
		open.sort_custom(func(a:Dictionary,b:Dictionary):
			return _exploration_open_less(a,b,risk_weighted))
		var node: Dictionary = open.pop_front()
		var position: Vector2i = node.position
		var known: Array = best.get(str(node.state_key), [])
		var signature: Array = [int(node.max_risk),int(node.risk),
			int(node.steps),int(node.cost)]
		if known != signature: continue
		if position == goal:
			var route_risk:=int(node.risk);var route_max_risk:=int(node.max_risk)
			if not risk_weighted:
				route_risk=0;route_max_risk=0
				for path_index in range(1,node.path.size()):
					var path_risk:=_exploration_step_risk(node.path[path_index],visible)
					route_risk+=path_risk;route_max_risk=maxi(route_max_risk,path_risk)
			return {"found":true,"reason":"ok","path":node.path.duplicate(),
				"total_cost":int(node.cost),"steps":int(node.steps),
				"total_risk":route_risk,"max_total_risk":route_max_risk}
		for direction in MovementSystemScript.MOVE_DIRECTIONS_8:
			var next: Vector2i = position + direction
			if not _exploration_step_is_legal(actor_id, position, next): continue
			var candidate_steps := int(node.steps) + 1
			if maximum_steps >= 0 and candidate_steps > maximum_steps: continue
			var step_risk := _exploration_step_risk(next, visible) if risk_weighted else 0
			var definition: Dictionary = TerrainRegistryScript.definition(sim.world.tile_at(next).terrain)
			var candidate_key := _position_key(next) + ("@%d" % candidate_steps \
				if risk_weighted else "")
			var candidate_path:Array = node.path.duplicate();candidate_path.append(next)
			var candidate := {"position":next,"risk":int(node.risk)+step_risk,
				"max_risk":maxi(int(node.max_risk), step_risk),"steps":candidate_steps,
				"cost":int(node.cost)+int(definition.move_time_cost),"sequence":sequence,
				"state_key":candidate_key,"path":candidate_path}
			sequence += 1
			var old: Array = best.get(candidate_key, [])
			if not old.is_empty() and not _exploration_score_less(candidate, old,
					risk_weighted):continue
			best[candidate_key] = [int(candidate.max_risk),int(candidate.risk),
				int(candidate.steps),int(candidate.cost)]
			open.append(candidate)
	return _exploration_path_failure("path_unreachable")


func _exploration_score_less(candidate: Dictionary, old: Array,
		risk_weighted: bool) -> bool:
	var candidate_keys := [int(candidate.max_risk),int(candidate.risk),
		int(candidate.steps),int(candidate.cost)]
	var order := [0,1,2,3] if risk_weighted else [2,3]
	for index in order:
		if candidate_keys[index] != int(old[index]):
			return candidate_keys[index] < int(old[index])
	return false


func _exploration_open_less(a: Dictionary, b: Dictionary,
		risk_weighted: bool) -> bool:
	var order := ["max_risk","risk","steps","cost"] if risk_weighted \
		else ["steps","cost"]
	for key in order:
		if int(a[key]) != int(b[key]):return int(a[key]) < int(b[key])
	var a_position: Vector2i = a.position;var b_position: Vector2i = b.position
	if a_position.y != b_position.y:return a_position.y < b_position.y
	if a_position.x != b_position.x:return a_position.x < b_position.x
	return int(a.sequence) < int(b.sequence)


func _exploration_step_is_legal(actor_id: int, from: Vector2i,
		to: Vector2i) -> bool:
	if not sim.world.in_bounds(to):return false
	var definition: Dictionary = TerrainRegistryScript.definition(sim.world.tile_at(to).terrain)
	if definition.is_empty() or not bool(definition.get("passable", false)) \
			or int(definition.get("occupancy_capacity", 0)) < 1 \
			or sim.world.blocking_entity_at(to, actor_id) != null:return false
	var delta := to-from
	if delta.x != 0 and delta.y != 0:
		if not sim.world.diagonal_step_terrain_allowed(from,to):return false
	return true


func exploration_route_risk_rows(position: Vector2i) -> Array[Dictionary]:
	return _exploration_risk_rows(position, _exploration_visible_cells()).duplicate(true)


func _exploration_visible_cells() -> Dictionary:
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return {}
	var state = sim.world.party_encounter
	var hero = sim.world.entities.get(int(state.protagonist_id))
	if hero == null: return {}
	return _presentation_visible_cells(hero.position)


func _exploration_step_risk(position: Vector2i, visible: Dictionary) -> int:
	var party_max := 0
	for row in _exploration_risk_rows(position, visible):
		party_max = maxi(party_max, int(row.total))
	return party_max


func _exploration_risk_rows(position: Vector2i,
		visible: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var state = sim.world.party_encounter
	var member_ids: Array = state.party_member_ids.duplicate()
	member_ids.sort_custom(func(a, b):
		var member_a = state.member(int(a)); var member_b = state.member(int(b))
		return int(member_a.roster_slot) < int(member_b.roster_slot) \
			if int(member_a.roster_slot) != int(member_b.roster_slot) else int(a) < int(b))
	var is_visible := visible.has(_position_key(position))
	for member_id_value in member_ids:
		var member_id := int(member_id_value);var member = state.member(member_id)
		var entity = sim.world.entities.get(member_id)
		if member == null or (member.presence != "GROUPED" and member_id != state.protagonist_id) \
				or entity == null or not sim.world.is_environment_exposed(member_id):continue
		var wire := {"fire_score":0,"water_score":0,"electric_score":0,
			"poison_score":0,"total_risk":0}
		if is_visible:
			var evaluated = sim.evaluate_exposure_for_entity(member_id, position)
			if evaluated != null and evaluated.evaluation != null:
				wire = evaluated.evaluation.to_dict()
		rows.append({"entity_id":member_id,"display_name":str(entity.display_name),
			"role":str(member.role),"species_id":str(entity.species_id),
			"fire":int(wire.fire_score),"water":int(wire.water_score),
			"electric":int(wire.electric_score),"poison":int(wire.poison_score),
			"total":int(wire.total_risk)})
	return rows


func _exploration_path_failure(reason: String) -> Dictionary:
	return {"found":false,"reason":reason,"path":[],"total_cost":-1,
		"steps":0,"total_risk":0,"max_total_risk":0,"routing_policy":"UNAVAILABLE",
		"hazard_free":false,"risk_weighted":false}

func set_actor_action(actor_id: int, action_type: String, destination: Array = [], target_id: int = -1) -> Dictionary:
	if _run_is_complete(): return _rejection_dto("run_complete")
	if sim == null or sim.world.party_encounter == null: return _rejection_dto("session_not_initialized")
	var action = _make_action(actor_id, action_type, destination, target_id)
	if action == null:
		return _rejection_dto("invalid_party_destination" if action_type == "MOVE" else "invalid_party_action",
			null, null, {"actor_id": actor_id, "action_type": action_type,
				"destination": destination.duplicate(true), "target_id": target_id})
	var state = sim.world.party_encounter
	return begin_turn(action) if actor_id == state.protagonist_id else override_companion(actor_id, action)


func commit_direct_solo_action(actor_id:int,action_type:String,
		destination:Array=[],target_id:int=-1)->Dictionary:
	# Product solo input is already the complete trusted request. The simulator
	# validates/freezes it once and then uses the same rollback, event, schedule and
	# semantic-validation commit tail as the externally supplied plan path.
	if not is_solo_combat() or sim==null or sim.world==null \
			or sim.world.party_encounter==null:
		return _rejection_dto("direct_solo_action_required")
	var state=sim.world.party_encounter
	if state.safe_phase!="ENGAGED" or state.active_party_member_ids!=[state.protagonist_id] \
			or actor_id!=state.protagonist_id:
		return _rejection_dto("direct_solo_action_required")
	var action=_make_action(actor_id,action_type,destination,target_id)
	if action==null:
		return _rejection_dto("invalid_party_destination" if action_type=="MOVE" \
			else "invalid_party_action")
	_exploration_route.cancel_for_direct_command()
	var copied_action=_canonical_action_copy(action)
	if copied_action==null:return _rejection_dto("invalid_party_action")
	var request=RequestScript.new(copied_action,[])
	# The settled world was fully audited at reset/load/restore. Check the mutable
	# cross-ledger health authority before taking the lightweight rollback image;
	# the commit tail validates all surfaces touched by this live turn.
	if not sim.world.runtime_party_health_error().is_empty():
		return _rejection_dto("party_snapshot_unavailable")
	var rollback_memento:Variant=sim.capture_rollback_memento(false)
	if not rollback_memento is Dictionary:return _rejection_dto("party_snapshot_unavailable")
	var event_start:int=sim.world.events.size()
	var result=sim.step_direct_solo_party_turn(request,rollback_memento)
	if result.accepted:
		var recovery:=_apply_safe_exploration_recovery(event_start)
		if not bool(recovery.accepted):
			if not sim.restore_rollback_memento(rollback_memento):
				return _rejection_dto("rollback_restore_failed")
			return _rejection_dto(str(recovery.reason))
		if recovery.get("event")!=null:result.events.append(recovery.event)
		_advance_exile_world()
		command_journal.append({"kind":"party_turn",
			"request":request.to_dict().duplicate(true)})
		_clear_draft()
	return _result_dto(result,null,request)


func preview_actor_action(actor_id: int, action_type: String, destination: Array = [],
		target_id: int = -1) -> Dictionary:
	# UI hover/tap preview must not mutate the pending direct action or overrides.
	if _run_is_complete(): return _rejection_dto("run_complete")
	if sim == null or sim.world.party_encounter == null:
		return _rejection_dto("session_not_initialized")
	var action = _make_action(actor_id, action_type, destination, target_id)
	if action == null:
		return _rejection_dto("invalid_party_destination" if action_type == "MOVE" else "invalid_party_action",
			null, null, {"actor_id": actor_id, "action_type": action_type,
				"destination": destination.duplicate(true), "target_id": target_id})
	var state = sim.world.party_encounter
	var direct = action if actor_id == state.protagonist_id else _protagonist_draft
	if direct == null:
		return _rejection_dto("turn_draft_required", action)
	var overrides: Array = []
	var ids: Array = _overrides.keys()
	if actor_id != state.protagonist_id and not ids.has(actor_id): ids.append(actor_id)
	ids.sort()
	for id in ids:
		overrides.append({"actor_id": id,
			"action": action if int(id) == actor_id else _overrides[id]})
	var request = RequestScript.new(direct, overrides)
	var preview: Dictionary = sim.preview_party_turn(request).to_dict().duplicate(true)
	preview["selected_action_preview"] = _actor_row_presentation(
		preview.get("actor_rows", []), actor_id)
	return _feedback_dto(preview, action, request)


func enemy_intent_forecasts() -> Array[Dictionary]:
	# Forecasts are a presentation-only view of the exact selector used by the
	# next enemy batch. They deliberately say "현재 예상": a committed player
	# move may change the authoritative positions before that batch is evaluated.
	var rows: Array[Dictionary] = []
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return rows
	var state = sim.world.party_encounter
	if state.safe_phase != "ENGAGED": return rows
	var hero = sim.world.entities.get(state.protagonist_id)
	if hero == null: return rows
	var visible: Dictionary = _presentation_visible_cells(hero.position)
	var squad_board: Dictionary = EnemySquadBlackboardScript.build(sim.world)
	for enemy_id_value in state.enemy_ids:
		var enemy_id := int(enemy_id_value)
		var enemy = sim.world.entities.get(enemy_id)
		if enemy == null or not visible.has(_position_key(enemy.position)): continue
		var forecast: Dictionary = sim.party_coordinator.forecast_enemy_action(
			enemy_id, squad_board)
		if not bool(forecast.get("accepted", false)): continue
		var target_id := int(forecast.target_id)
		var target = sim.world.entities.get(target_id)
		if target == null or not visible.has(_position_key(target.position)): continue
		var action_type := str(forecast.action_type)
		var headline := "%s → %s 공격" % [_name(enemy_id), _name(target_id)]
		var claimed_target_id := int(squad_board.get("claims", {}).get(enemy_id, -1))
		var is_squad_focus := target_id == int(squad_board.get("focus_target_id", -1))
		var target_role := "주인공" if is_solo_combat() else (
			"분대 집중 표적" if is_squad_focus else (
				"분대 담당 표적" if claimed_target_id == target_id else "가장 가까운 파티원"))
		var reason := "%s이 공격 범위 안에 있습니다."%target_role
		if action_type == "MOVE":
			headline = "%s → %s 접근" % [_name(enemy_id), _name(target_id)]
			reason = "%s을 향해 한 칸 움직입니다."%target_role
		elif action_type == "HOLD":
			headline = "%s · 방어" % _name(enemy_id)
			reason = "접근할 길이 막혀 자리를 지키며 방어합니다."
		rows.append({"schema_version":1, "source":"ENEMY_FORECAST",
			"source_label":"적 현재 예상", "source_color":"#ff756b",
			"line_style":"DASHED_THIN", "marker_style":"CIRCLE",
			"actor_id":enemy_id, "actor_name":_name(enemy_id),
			"target_id":target_id, "target_name":_name(target_id),
			"type":action_type, "type_label":{"HOLD":"방어", "MOVE":"이동",
				"MELEE":"공격"}.get(action_type, "방어"),
			"from_position":forecast.from_position.duplicate(true),
			"destination":forecast.destination.duplicate(true),
			"target_position":[target.position.x, target.position.y],
			"headline":headline, "reason":reason,
			"forecast_basis":"CURRENT_AUTHORITATIVE_STATE"})
	rows.sort_custom(func(a:Dictionary,b:Dictionary):
		return int(a.actor_id) < int(b.actor_id))
	return rows.duplicate(true)


func enemy_squad_tactics() -> Dictionary:
	var empty := {"schema_version":1, "available":false,
		"focus_target_id":-1, "focus_target_name":"", "claims":[]}
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return empty.duplicate(true)
	var state = sim.world.party_encounter
	if state.safe_phase != "ENGAGED" or not sim.world.entities.has(state.protagonist_id):
		return empty.duplicate(true)
	var hero = sim.world.entities[state.protagonist_id]
	var visible: Dictionary = _presentation_visible_cells(hero.position)
	var board: Dictionary = EnemySquadBlackboardScript.build(sim.world)
	var claims: Array[Dictionary] = []
	var enemy_ids: Array = board.get("claims", {}).keys()
	enemy_ids.sort()
	for enemy_id_value in enemy_ids:
		var enemy_id := int(enemy_id_value)
		var target_id := int(board.claims[enemy_id])
		var enemy = sim.world.entities.get(enemy_id)
		var target = sim.world.entities.get(target_id)
		if enemy == null or target == null \
				or not visible.has(_position_key(enemy.position)) \
				or not visible.has(_position_key(target.position)):
			continue
		var is_focus := target_id == int(board.focus_target_id)
		claims.append({"enemy_id":enemy_id, "enemy_name":_name(enemy_id),
			"target_id":target_id, "target_name":_name(target_id),
			"is_focus":is_focus, "basis_code":"SQUAD_CLAIM",
			"explanation":"분대 집중 표적을 담당합니다." if is_focus \
				else "분대가 나눈 담당 표적을 추적합니다."})
	if claims.is_empty():
		return empty.duplicate(true)
	var visible_focus_id := -1
	for row in claims:
		if bool(row.is_focus):
			visible_focus_id = int(row.target_id)
			break
	return {"schema_version":1, "available":true,
		"focus_target_id":visible_focus_id,
		"focus_target_name":_name(visible_focus_id) if visible_focus_id > 0 else "",
		"claims":claims}.duplicate(true)


func companion_decision_explanations() -> Dictionary:
	if sim == null or sim.world == null or sim.world.party_encounter == null \
			or _protagonist_draft == null:
		return {"schema_version": 1, "accepted": false,
			"reason": "no_drafted_turn", "companions": []}
	var raw: Dictionary = sim.party_coordinator.explain_companion_turn(
		_pending_turn_request())
	var companions: Array = []
	for row in raw.get("companions", []):
		var candidates: Array = []
		for candidate in row.candidates:
			var terms: Array = candidate.considerations.duplicate(true)
			terms.sort_custom(func(a: Dictionary, b: Dictionary):
				var a_magnitude := absi(int(a.contribution))
				var b_magnitude := absi(int(b.contribution))
				return a_magnitude > b_magnitude if a_magnitude != b_magnitude \
					else str(a.consideration_id) < str(b.consideration_id))
			var top: Array = []
			for term in terms.slice(0, 3):
				top.append({"label": _consideration_label(str(term.consideration_id)),
					"value": int(term.contribution)})
			candidates.append({
				"action_id": str(candidate.action_id),
				"label": _party_action_label(str(candidate.action_id)),
				"legal": bool(candidate.legal),
				"score": int(candidate.score),
				"top_terms": top,
			})
		var actor_id := int(row.actor_id)
		companions.append({
			"actor_id": actor_id,
			"name": str(sim.world.entities[actor_id].display_name),
			"selected_action_id": str(row.selected_action_id),
			"command_id":str(row.get("command_id","FOLLOW")),
			"mode": str(row.mode),
			"reason_text": _companion_reason_text(row),
			"candidates": candidates,
		})
	return {"schema_version": 1, "accepted": bool(raw.accepted),
		"reason": str(raw.reason), "companions": companions}.duplicate(true)


func turn_intent_overlays() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if _protagonist_draft == null: return rows
	var explanation_by_actor: Dictionary = {}
	var explanations := companion_decision_explanations()
	for explanation in explanations.get("companions", []):
		explanation_by_actor[int(explanation.actor_id)] = str(explanation.reason_text)
	for card in party_cards():
		if not card.expected_action is Dictionary: continue
		var action: Dictionary = card.expected_action
		var role := str(card.role)
		var resolution_note := str(action.get("resolution_note", ""))
		rows.append({"actor_id": int(card.entity_id), "actor_name": str(card.display_name),
			"role":role, "roster_slot":int(card.roster_slot),
			"from_position": card.logical_position.duplicate(true), "source": str(action.source),
			"source_label": str(action.source_label), "source_color": str(action.source_color),
			"line_style": _overlay_line_style(str(action.source)),
			"marker_style": _overlay_marker_style(str(action.source)),
			"type": str(action.type), "type_label": str(action.type_label),
			"destination": action.destination.duplicate(true), "target_id": int(action.target_id),
			"target_position": action.target_position.duplicate(true), "reason": str(action.reason),
			"reason_text": str(explanation_by_actor.get(int(card.entity_id), "")) \
				if role == "COMPANION" else "",
			"attack_preview":action.get("attack_preview", null).duplicate(true) \
				if action.get("attack_preview", null) is Dictionary else null,
			"resolution_note":resolution_note,
			"speech_headline":_companion_speech_headline(str(action.type),
				str(action.source), resolution_note) if role == "COMPANION" else "",
			"speech_reason_summary":_companion_speech_reason_summary(str(action.type),
				str(action.source), resolution_note) if role == "COMPANION" else "",
			"automatic_suggestion": _overlay_suggestion(action.get("automatic_suggestion", null),
				card.logical_position) if str(action.source) == "OVERRIDE" else null})
	return rows.duplicate(true)


func companion_speech_bubbles() -> Array[Dictionary]:
	# This is a detached presentation projection of the current preview. It never
	# participates in save/load, replay, RNG, or authoritative simulation state.
	var bubbles: Array[Dictionary] = []
	for intent in turn_intent_overlays():
		if str(intent.get("role", "")) != "COMPANION": continue
		bubbles.append({"schema_version":1,
			"actor_id":int(intent.actor_id), "actor_name":str(intent.actor_name),
			"roster_slot":int(intent.roster_slot), "role":"COMPANION",
			"from_position":intent.from_position.duplicate(true),
			"source":str(intent.source), "action_type":str(intent.type),
			"headline":str(intent.speech_headline), "reason":str(intent.reason),
			"reason_summary":str(intent.speech_reason_summary),
			"resolution_note":str(intent.resolution_note)})
	bubbles.sort_custom(func(a:Dictionary,b:Dictionary):
		return int(a.roster_slot) < int(b.roster_slot) \
			if int(a.roster_slot) != int(b.roster_slot) \
			else int(a.actor_id) < int(b.actor_id))
	return bubbles.duplicate(true)


func world_speech_bubbles() -> Array[Dictionary]:
	# A single presentation channel feeds the map. Combat callouts and story
	# dialogue remain projections only: no timer, dialogue text, or layout state is
	# serialized into the deterministic simulation.
	var rows:Array[Dictionary]=[]
	for speech in companion_speech_bubbles():
		var row:Dictionary=speech.duplicate(true)
		row["bubble_id"]="intent:%d:%s:%s"%[int(row.get("actor_id",-1)),
			str(row.get("source","SUGGESTED")),str(row.get("action_type","HOLD"))]
		row["speaker_name"]=str(row.get("actor_name","동료"))
		row["text"]=str(row.get("headline","방어할게."))
		row["dialogue_kind"]="COMPANION_CALLOUT"
		row["tone"]="OVERRIDE" if str(row.get("source",""))=="OVERRIDE" else "COMPANION"
		row["priority"]=40
		rows.append(row)
	var opening:=opening_event_status()
	if bool(opening.get("available",false)) and bool(opening.get("adjacent",false)) \
			and str(opening.get("life_state","ACTIVE"))=="ACTIVE":
		var choice:=str(opening.get("choice","PENDING"))
		var dialogue:String=str({
			"PENDING":"잠깐… 회복 물약이 있다면 부탁해요.",
			"GAVE_POTION":"고마워요… 이 은혜는 잊지 않을게요.",
			"PASSED":"…알겠어요. 조심해서 가요.",
		}.get(choice,""))
		if not dialogue.is_empty():
			rows.append({"schema_version":1,
				"bubble_id":"opening:%s:%s"%[choice,str(opening.get("choice_event_id",-1))],
				"actor_id":int(opening.get("npc_entity_id",-1)),
				"speaker_name":str(opening.get("display_name","부상당한 여행자")),
				"text":dialogue,"dialogue_kind":"STORY_DIALOGUE",
				"tone":"IMPORTANT","priority":100})
	rows.sort_custom(func(a:Dictionary,b:Dictionary):
		if int(a.get("priority",0))!=int(b.get("priority",0)):
			return int(a.get("priority",0))>int(b.get("priority",0))
		return int(a.get("actor_id",-1))<int(b.get("actor_id",-1)))
	return rows.duplicate(true)


func _companion_speech_headline(action_type: String, source: String,
		resolution_note: String) -> String:
	if action_type == "MELEE": return "공격할게."
	if action_type == "MOVE": return "이동할게."
	if source == "OVERRIDE" or resolution_note == "destination_conflict_suggested_hold":
		return "방어할게."
	return "방어할게."


func _companion_speech_reason_summary(action_type: String, source: String,
		resolution_note: String) -> String:
	if source == "OVERRIDE": return "지시를 따라서"
	if resolution_note == "destination_conflict_suggested_hold": return "길이 겹쳐서"
	if action_type == "MELEE": return "적이 가까워서"
	if action_type == "MOVE": return "길이 열려서"
	return "피해를 줄이려고"


func _party_action_label(action_id: String) -> String:
	return {"ENGAGE":"공격", "PROTECT":"엄호", "RETREAT":"후퇴",
		"HOLD":"대기"}.get(action_id, action_id)


func _consideration_label(consideration_id: String) -> String:
	return {
		"party_engage.attack_drive":"공격 충동",
		"party_engage.claim":"담당 표적",
		"party_engage.focus":"집중 표적",
		"party_engage.threat":"체감 위협",
		"party_engage.hp_loss":"자신의 부상",
		"party_engage.emotionality":"정서성(E)",
		"party_engage.agreeableness":"원만성(A)",
		"party_engage.extraversion":"외향성(X)",
		"party_engage.stress":"스트레스",
		"party_protect.ally_targeted":"아군 위협",
		"party_protect.ally_hp_loss":"아군 부상",
		"party_protect.trust":"아군 신뢰",
		"party_protect.honesty":"정직-겸손(H)",
		"party_protect.emotionality":"정서성(E)",
		"party_protect.agreeableness":"원만성(A)",
		"party_protect.panic":"공황 압력",
		"party_protect.hp_loss":"자신의 부상",
		"party_retreat.threat":"체감 위협",
		"party_retreat.hp_loss":"자신의 부상",
		"party_retreat.stress":"스트레스",
		"party_retreat.engaged":"근접한 적",
		"party_retreat.outnumbered":"수적 열세",
		"party_retreat.emotionality":"정서성(E)",
		"party_retreat.conscientiousness":"성실성(C)",
		"party_hold.conscientiousness":"성실성(C)",
		"party_hold.emotionality":"정서성(E)",
		"party_hold.threat":"체감 위협",
		"party_hold.engaged":"근접한 적",
	}.get(consideration_id, consideration_id)


func _companion_reason_text(row: Dictionary) -> String:
	var action_id := str(row.get("selected_action_id", "HOLD"))
	var prefix := "공황 · " if str(row.get("mode", "NORMAL")) == "PANIC" else ""
	var command_id:=str(row.get("command_id","FOLLOW"))
	if command_id in ["RETREAT","STOP_ATTACK","HOLD_POSITION"]:
		return "%s예외 명령 · %s"%[prefix,PartyCommandScript.label_ko(command_id)]
	var selected: Dictionary = {}
	for candidate in row.get("candidates", []):
		if str(candidate.action_id) == action_id:
			selected = candidate
			break
	if selected.is_empty():
		return "%s%s 선택" % [prefix, _party_action_label(action_id)]
	var terms: Array = selected.get("considerations", []).duplicate(true)
	terms.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_magnitude := absi(int(a.contribution))
		var b_magnitude := absi(int(b.contribution))
		return a_magnitude > b_magnitude if a_magnitude != b_magnitude \
			else str(a.consideration_id) < str(b.consideration_id))
	var reasons: Array[String] = []
	for term in terms.slice(0, 2):
		var contribution := int(term.contribution)
		reasons.append("%s %s%d" % [_consideration_label(str(term.consideration_id)),
			"+" if contribution >= 0 else "", contribution])
	if reasons.is_empty():
		return "%s%s 선택" % [prefix, _party_action_label(action_id)]
	return "%s%s · %s" % [prefix, _party_action_label(action_id), ", ".join(reasons)]


func turn_summary_lines() -> Array[String]:
	var lines: Array[String] = []
	for row in turn_intent_overlays():
		var detail := str(row.type_label)
		if row.type == "MOVE": detail += " (%d,%d)" % [int(row.destination[0]), int(row.destination[1])]
		elif row.type == "MELEE":
			detail += " %s" % _name(int(row.target_id))
			var attack_preview:Variant=row.get("attack_preview",null)
			if attack_preview is Dictionary:
				detail += " · 명중 %d%% · 적중 시 %d 피해" % [
					int(attack_preview.get("hit_chance_percent",0)),
					int(attack_preview.get("damage_on_hit",0))]
		var line := "%s · %s: %s" % [str(row.actor_name), str(row.source_label), detail]
		if row.automatic_suggestion is Dictionary:
			line += " / 원래 제안: %s" % _overlay_action_text(row.automatic_suggestion)
		line += " — %s" % str(row.reason)
		if str(row.get("role", "")) == "COMPANION" \
				and not str(row.get("reason_text", "")).is_empty():
			line += "  이유 · %s" % str(row.reason_text)
		lines.append(line)
	return lines

func _overlay_suggestion(value: Variant, from_position: Array) -> Variant:
	if not value is Dictionary: return null
	var target_position := [-1,-1]
	var target_id := int(value.get("target_id",-1))
	if target_id > 0 and sim.world.entities.has(target_id):
		target_position = [sim.world.entities[target_id].position.x,sim.world.entities[target_id].position.y]
	return {"source":"SUGGESTED","source_label":"원래 자동 제안","source_color":"#75c8ff",
		"line_style":"DASHED_THIN","marker_style":"CIRCLE",
		"type":str(value.get("type","HOLD")),"type_label":str(value.get("type_label","대기")),
		"from_position":from_position.duplicate(true),"destination":value.get("destination",[-1,-1]).duplicate(true),
		"target_id":target_id,"target_name":str(value.get("target_name","")),
		"target_position":target_position}.duplicate(true)

func _overlay_action_text(action: Dictionary) -> String:
	if str(action.type)=="MOVE":return "이동 (%d,%d)"%[int(action.destination[0]),int(action.destination[1])]
	if str(action.type)=="MELEE":return "공격 %s"%str(action.get("target_name","적"))
	return "방어"

func _overlay_line_style(source: String) -> String:
	return {"OVERRIDE":"SOLID_THICK","DIRECT":"SOLID","SUGGESTED":"DASHED_THIN"}.get(source,"SOLID")

func _overlay_marker_style(source: String) -> String:
	return {"OVERRIDE":"SQUARE","DIRECT":"DIAMOND","SUGGESTED":"CIRCLE"}.get(source,"CIRCLE")

func preview_exploration(command) -> Dictionary:
	if _run_is_complete(): return _rejection_dto("run_complete")
	if _command_targets_locked_exit(command):
		return _rejection_dto("exit_locked", null, null,
			_exploration_context(command))
	if party_status().view_mode != "EXPLORATION": return _rejection_dto("exploration_phase_required")
	if command == null or command.actor_id != sim.world.party_encounter.protagonist_id:
		return _rejection_dto("protagonist_command_required")
	var context := _exploration_context(command)
	if int(command.type) not in [int(CommandScript.Type.WAIT), int(CommandScript.Type.MOVE)]:
		return _rejection_dto("invalid_exploration_action", null, null, context)
	var preview = sim.preview(command)
	return _feedback_dto({"accepted": preview.accepted, "reason": preview.reason,
		"time_cost": preview.time_cost}, null, null, context)


func preview_exploration_route(goal: Variant) -> Dictionary:
	if _run_is_complete(): return _rejection_dto("run_complete")
	if _position_is_locked_exit(goal):
		return _rejection_dto("exit_locked", null, null,
			{"action_type":"ROUTE", "destination":_position_wire_value(goal)})
	return _exploration_route.preview(goal)


func exploration_companion_follow_plan(route_value: Dictionary = {}) -> Dictionary:
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return {"schema_version":1, "accepted":false,
			"reason":"session_not_initialized", "path":[], "companion_rows":[]}
	var route: Dictionary = route_value.duplicate(true) if not route_value.is_empty() \
		else _exploration_route.state()
	var path: Variant = route.get("path", [])
	if not bool(route.get("accepted", false)) or not path is Array or path.size() < 2:
		return {"schema_version":1, "accepted":false,
			"reason":str(route.get("reason", "route_preview_required")),
			"path":[], "companion_rows":[]}.duplicate(true)
	var state = sim.world.party_encounter
	var rows: Array = []
	var completed_steps := clampi(int(route.get("completed_steps", 0)), 0, path.size() - 1)
	var next_index := mini(path.size() - 1, completed_steps + 1)
	for member_id in state.party_member_ids:
		if member_id == state.protagonist_id: continue
		var member = state.member(member_id)
		if member == null or member.presence != "GROUPED" \
				or not sim.world.is_environment_exposed(member_id): continue
		var maxima := {"fire":0, "water":0, "electric":0, "poison":0, "total":0}
		for step in route.get("steps", []):
			if not step is Dictionary: continue
			for risk in step.get("member_risk_ceilings", []):
				if not risk is Dictionary or int(risk.get("entity_id", -1)) != member_id:
					continue
				for component in maxima.keys():
					maxima[component] = maxi(int(maxima[component]), int(risk.get(component, 0)))
		var entity = sim.world.entities[member_id]
		rows.append({"entity_id":member_id, "display_name":str(entity.display_name),
			"roster_slot":int(member.roster_slot), "species_id":str(entity.species_id),
			"source":"SUGGESTED", "mode":"FOLLOW_ROUTE",
			"from_position":path[completed_steps].duplicate(true),
			"next_position":path[next_index].duplicate(true),
			"goal":path[-1].duplicate(true), "path":path.duplicate(true),
			"component_maxima":maxima.duplicate(true),
			"max_total_risk":int(maxima.total)})
	rows.sort_custom(func(a:Dictionary,b:Dictionary):
		return int(a.roster_slot) < int(b.roster_slot) if int(a.roster_slot) != int(b.roster_slot) \
			else int(a.entity_id) < int(b.entity_id))
	return {"schema_version":1, "accepted":true, "reason":"ok",
		"path":path.duplicate(true), "completed_steps":completed_steps,
		"next_position":path[next_index].duplicate(true),
		"companion_rows":rows}.duplicate(true)


func exploration_route_draft() -> Dictionary:
	return _exploration_route.draft()


func exploration_route_state() -> Dictionary:
	return _exploration_route.state()


func start_auto_explore() -> Dictionary:
	if _auto_explore == null:
		_auto_explore = AutoExploreScript.new(self)
	if bool(_auto_explore.state().get("running", false)):
		return _auto_explore.start()
	var route_state: Dictionary = exploration_route_state()
	if bool(route_state.get("active", false)) \
			or bool(route_state.get("has_preview", false)):
		cancel_exploration_route()
	return _auto_explore.start()


func continue_auto_explore() -> Dictionary:
	if _auto_explore == null:
		_auto_explore = AutoExploreScript.new(self)
	return _auto_explore.continue_auto()


func cancel_auto_explore(reason: String = "auto_explore_cancelled") -> Dictionary:
	if _auto_explore == null:
		_auto_explore = AutoExploreScript.new(self)
	return _auto_explore.cancel(reason)


func auto_explore_state() -> Dictionary:
	if _auto_explore == null:
		_auto_explore = AutoExploreScript.new(self)
	return _auto_explore.state()


func _commit_auto_explore_one(destination: Vector2i) -> Dictionary:
	# AUTO has already selected one adjacent, visible, fog-safe destination. Commit
	# it through the same canonical one-cell seam used by route continuation, but
	# avoid building and revalidating a throwaway one-step route plan around every
	# hop. The ordinary exploration journal/replay authority remains unchanged.
	if _auto_explore == null or not bool(_auto_explore.state().get("running", false)):
		return _rejection_dto("auto_explore_not_active")
	var status := party_status()
	if not bool(status.get("ok", false)):
		return _rejection_dto(str(status.get("reason", "session_not_initialized")))
	var hero_id := int(status.get("protagonist_id", -1))
	var current := Vector2i(int(status.protagonist_position[0]),
		int(status.protagonist_position[1]))
	var delta := destination - current
	if delta == Vector2i.ZERO or maxi(absi(delta.x), absi(delta.y)) != 1:
		return _rejection_dto("invalid_party_destination", null, null,
			{"actor_id":hero_id, "action_type":"MOVE",
				"destination":[destination.x, destination.y]})
	if _position_is_locked_exit(destination):
		return _rejection_dto("exit_locked", null, null,
			{"actor_id":hero_id, "action_type":"MOVE",
				"destination":[destination.x, destination.y]})
	var command = CommandScript.move_to(hero_id, destination)
	# AUTO has already checked this single adjacent cell against its fresh
	# fog-safe snapshot. Simulator.step still performs the sole authoritative
	# command assessment/plan; skip only the otherwise identical presentation
	# preview that ordinary taps need before their commit.
	return _commit_exploration_one(command, false, true)


func _auto_explore_fog_snapshot() -> Dictionary:
	var context := _party_observation_context()
	if context.is_empty():
		return {}
	var status: Dictionary = context.status
	var visible: Dictionary = context.visible
	var explored: Dictionary = context.explored
	var visited: Dictionary = context.visited
	var progress: Dictionary = context.progress
	var state = sim.world.party_encounter
	var hero_id := int(status.protagonist_id)
	var cells: Dictionary = {}
	var hazards: Dictionary = {}
	var visible_enemy_keys: Dictionary = {}
	if not bool(context.hide_enemies):
		for enemy_id_value in state.enemy_ids:
			var enemy_id := int(enemy_id_value)
			if not sim.world.is_unresolved_enemy(enemy_id):
				continue
			var enemy = sim.world.entities.get(enemy_id)
			if enemy == null or not visible.has(_position_key(enemy.position)):
				continue
			visible_enemy_keys["ENEMY:%d" % enemy_id] = true
	var known_keys: Dictionary = {}
	for key_value in explored: known_keys[str(key_value)] = true
	for key_value in visible: known_keys[str(key_value)] = true
	var known_positions: Array[Vector2i] = []
	for key_value in known_keys:
		var parts := str(key_value).split(":")
		if parts.size() == 2:
			known_positions.append(Vector2i(int(parts[0]), int(parts[1])))
	known_positions.sort_custom(func(a:Vector2i,b:Vector2i):
		return a.y < b.y if a.y != b.y else a.x < b.x)
	for position in known_positions:
			var x := position.x
			var y := position.y
			var key := _position_key(position)
			var is_visible := visible.has(key)
			var terrain_id := str(sim.world.tile_at(position).terrain)
			var definition: Dictionary = TerrainRegistryScript.definition(terrain_id)
			var risk := _exploration_step_risk(position, visible) if is_visible else 0
			var occupied := false
			var objective_blocked := false
			if is_visible:
				occupied = sim.world.blocking_entity_at(position, hero_id) != null
				var feature_id := _run_feature_id_at(position, progress)
				objective_blocked = feature_id == "run_exit_locked"
			if risk > AutoExploreScript.AFFINITY_SAFE_RISK_THRESHOLD:
				hazards[key] = risk
			cells[key] = {"position":[x, y],
				"visibility_state":"VISIBLE" if is_visible else "MEMORY",
				"terrain_id":terrain_id,
				"passable":not definition.is_empty() \
					and bool(definition.get("passable", false)) \
					and int(definition.get("occupancy_capacity", 0)) >= 1,
				"move_time_cost":int(definition.get("move_time_cost", 0)),
				"diagonal_gateway":sim.world.is_diagonal_gateway(position),
				"occupied":occupied, "risk":risk,
				"objective_blocked":objective_blocked}
	return {"schema_version":1, "width":sim.world.width,
		"height":sim.world.height, "step_index":int(status.step_index),
		"safe_phase":str(status.safe_phase), "view_mode":str(status.view_mode),
		"terminal":bool(status.terminal) or bool(progress.get("terminal", false)),
		"hero_position":status.protagonist_position.duplicate(true),
		"cells":cells, "visible":visible, "visited":visited, "hazards":hazards,
		"opening_interaction":bool(opening_event_status().get("can_interact",false)),
		"visible_enemy_keys":visible_enemy_keys}


func _auto_explore_stop_snapshot() -> Dictionary:
	# Post-commit AUTO safety gate. This intentionally exposes only state allowed
	# to stop the macro; route planning still uses the full fog snapshot on every
	# next hop, so hazards and topology are never read from stale data.
	var status := party_status()
	if not bool(status.get("ok",false)):
		return {}
	var progress := run_progress()
	var state = sim.world.party_encounter
	var hero_position := Vector2i(int(status.protagonist_position[0]),
		int(status.protagonist_position[1]))
	var visible: Dictionary = _presentation_visible_cells(hero_position)
	visible[_position_key(hero_position)] = true
	var hide_enemies: bool = scenario_id == REGRESSION_SCENARIO_ID \
		and str(status.safe_phase) in ["GROUPED", "GROUPED_COMPLETE"]
	var visible_enemy_keys: Dictionary = {}
	if not hide_enemies:
		for enemy_id_value in state.enemy_ids:
			var enemy_id := int(enemy_id_value)
			if not sim.world.is_unresolved_enemy(enemy_id):
				continue
			var enemy = sim.world.entities.get(enemy_id)
			if enemy != null and visible.has(_position_key(enemy.position)):
				visible_enemy_keys["ENEMY:%d" % enemy_id] = true
	return {"schema_version":1, "step_index":int(status.step_index),
		"safe_phase":str(status.safe_phase), "view_mode":str(status.view_mode),
		"terminal":bool(status.terminal) or bool(progress.get("terminal", false)),
		"opening_interaction":bool(opening_event_status().get("can_interact",false)),
		"visible_enemy_keys":visible_enemy_keys}.duplicate(true)


func start_exploration_route(goal: Variant, plan_hash: String) -> Dictionary:
	if _run_is_complete(): return _rejection_dto("run_complete")
	if _position_is_locked_exit(goal):
		return _rejection_dto("exit_locked", null, null,
			{"action_type":"ROUTE", "destination":_position_wire_value(goal)})
	var result: Dictionary = _exploration_route.start(goal, plan_hash)
	if _run_is_complete(): _clear_run_completion_transients()
	return result


func continue_exploration_route() -> Dictionary:
	if _run_is_complete(): return _rejection_dto("run_complete")
	var result: Dictionary = _exploration_route.continue_route()
	if _run_is_complete(): _clear_run_completion_transients()
	return result


func cancel_exploration_route() -> Dictionary:
	return _exploration_route.cancel()


func commit_exploration(command,prevalidated_one_step:bool=false) -> Dictionary:
	if _run_is_complete(): return _rejection_dto("run_complete")
	if _auto_explore != null and bool(_auto_explore.state().get("running", false)):
		_auto_explore.cancel("auto_explore_user_command")
	if _command_targets_locked_exit(command):
		return _rejection_dto("exit_locked", null, null,
			_exploration_context(command))
	_exploration_route.cancel_for_direct_command()
	var result: Dictionary = _commit_exploration_one(command,false,prevalidated_one_step)
	if _run_is_complete(): _clear_run_completion_transients()
	return result


func _commit_exploration_one(command, preserve_route: bool,
		prevalidated_auto_hop: bool = false) -> Dictionary:
	if not prevalidated_auto_hop:
		var preview := preview_exploration(command)
		if not preview.accepted: return preview
	elif not sim.world.runtime_party_health_error().is_empty():
		return _rejection_dto("snapshot_unavailable")
	# This transaction always validates the post-step world in its recovery tail.
	# Capture a settled rollback image without paying that full history scan twice.
	var rollback_memento:Variant=sim.capture_rollback_memento(false)
	if not rollback_memento is Dictionary:return _rejection_dto("snapshot_unavailable")
	var event_start:int=sim.world.events.size()
	var result = sim.step(command,rollback_memento)
	if result.accepted:
		var recovery:=_apply_safe_exploration_recovery(event_start)
		if not bool(recovery.accepted):
			if not sim.restore_rollback_memento(rollback_memento):
				return _rejection_dto("rollback_restore_failed")
			return _rejection_dto(str(recovery.reason))
		if recovery.get("event")!=null:result.events.append(recovery.event)
		_advance_exile_world()
		command_journal.append({"kind":"exploration", "command":command.to_dict()})
	_clear_draft()
	if not preserve_route: _exploration_route.cancel_for_direct_command()
	var dto:Dictionary=_result_dto(result,null,null,_exploration_context(command))
	if bool(result.accepted) and command!=null \
			and int(command.type)==int(CommandScript.Type.MOVE):
		var ground_items:Array[Dictionary]=ground_items_at_protagonist()
		if not ground_items.is_empty():
			var labels:Array[String]=[]
			for item in ground_items:
				var label:=str(item.get("label",item.get("definition_id","아이템")))
				if not label.is_empty() and label not in labels:labels.append(label)
			dto["ground_items_here"]=ground_items.duplicate(true)
			dto["ground_item_notice"]="바닥 아이템 · %s · [줍기]로 획득" \
				% ", ".join(labels)
	return dto.duplicate(true)

func preview_deployment(preset_id: String, companion_ids: Array) -> Dictionary:
	if _run_is_complete(): return _rejection_dto("run_complete")
	_deployment_plan = sim.preview_deployment(preset_id, companion_ids)
	var dto: Dictionary = deployment_draft()
	dto.erase("has_preview")
	return dto.duplicate(true)


func enter_solo_combat() -> Dictionary:
	# SOLO_COMBAT_V1 still uses the canonical deployment step and journal entry;
	# it only fixes the legal companion selection to the authoritative empty set.
	if not is_solo_combat():return _rejection_dto("invalid_companion_ids")
	var state=sim.world.party_encounter if sim!=null and sim.world!=null else null
	if state==null or state.party_member_ids!=[state.protagonist_id] \
			or state.active_party_member_ids!=[state.protagonist_id]:
		return _rejection_dto("invalid_companion_ids")
	_exploration_route.cancel_for_direct_command()
	var result=sim.deploy_solo_party()
	if result.accepted:
		_advance_exile_world()
		command_journal.append({"kind":"deployment",
			"request":{"preset_id":"LINE","companion_ids":[]}})
		_deployment_plan.clear()
	return _result_dto(result)

func commit_deployment() -> Dictionary:
	if _run_is_complete(): return _rejection_dto("run_complete")
	_exploration_route.cancel_for_direct_command()
	if _deployment_plan.is_empty(): return _rejection_dto("deployment_preview_required")
	var request = {"preset_id": _deployment_plan.get("preset_id", ""), "companion_ids": _deployment_plan.get("companion_ids", []).duplicate()}
	var result = sim.deploy_party(_deployment_plan)
	if result.accepted:
		_advance_exile_world()
		var wire_ids: Array = []; for companion_id in request.companion_ids: wire_ids.append(str(companion_id))
		command_journal.append({"kind":"deployment", "request":{"preset_id":str(request.preset_id), "companion_ids":wire_ids}})
		_deployment_plan.clear()
	return _result_dto(result)

func begin_turn(protagonist_action) -> Dictionary:
	if _run_is_complete(): return _rejection_dto("run_complete")
	_exploration_route.cancel_for_direct_command()
	var copied_action = _canonical_action_copy(protagonist_action)
	if copied_action == null: return _rejection_dto("invalid_party_action")
	var previous_action = _protagonist_draft
	var previous_overrides := _overrides.duplicate()
	var previous_fingerprint := _draft_fingerprint
	var previous_placeholder := _protagonist_placeholder
	_protagonist_draft = copied_action; _overrides.clear()
	_protagonist_placeholder = false
	_draft_fingerprint = JSON.stringify(sim.snapshot()).sha256_text()
	var preview := current_turn_preview()
	if not bool(preview.get("accepted", false)):
		_protagonist_draft = previous_action; _overrides = previous_overrides
		_draft_fingerprint = previous_fingerprint
		_protagonist_placeholder = previous_placeholder
	return preview


func prepare_auto_combat_plan() -> Dictionary:
	if _run_is_complete(): return _auto_planning_empty("run_complete")
	_exploration_route.cancel_for_direct_command()
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return _auto_planning_empty("session_not_initialized")
	var state = sim.world.party_encounter
	if state.safe_phase != "ENGAGED" or not sim.world.is_settled():
		return _auto_planning_empty("party_turn_phase_required")
	if _protagonist_draft != null:
		if _draft_fingerprint == JSON.stringify(sim.snapshot()).sha256_text():
			return auto_combat_planning_state()
		_clear_draft()
	_protagonist_draft = ActionScript.hold(state.protagonist_id)
	_overrides.clear()
	_protagonist_placeholder = true
	_draft_fingerprint = JSON.stringify(sim.snapshot()).sha256_text()
	return auto_combat_planning_state()


func auto_combat_planning_state() -> Dictionary:
	if _run_is_complete(): return _auto_planning_empty("run_complete")
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return _auto_planning_empty("session_not_initialized")
	if _protagonist_draft == null:
		return _auto_planning_empty("turn_draft_required")
	var preview: Dictionary = current_turn_preview()
	if _protagonist_draft == null:
		return _auto_planning_empty(str(preview.get("reason", "stale_turn_draft")))
	var accepted := bool(preview.get("accepted", false))
	var override_ids: Array = _overrides.keys(); override_ids.sort()
	return {"schema_version":1, "active":true, "accepted":accepted,
		"reason":str(preview.get("reason", "ok")),
		"placeholder":_protagonist_placeholder,
		"protagonist_action_selected":not _protagonist_placeholder,
		"commit_ready":accepted and not _protagonist_placeholder,
		"plan_hash":str(preview.get("plan_hash", "")),
		"overridden_companion_ids":override_ids.duplicate(),
		"preview":preview.duplicate(true)}.duplicate(true)


func replace_auto_combat_protagonist_action(protagonist_action) -> Dictionary:
	if _run_is_complete(): return _auto_planning_empty("run_complete")
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return _auto_planning_empty("session_not_initialized")
	var state = sim.world.party_encounter
	if state.safe_phase != "ENGAGED" or not sim.world.is_settled():
		return _auto_planning_empty("party_turn_phase_required")
	var copied_action = _canonical_action_copy(protagonist_action)
	if copied_action == null or copied_action.actor_id != state.protagonist_id:
		return _auto_planning_empty("protagonist_action_required")
	var previous_action = _protagonist_draft
	var previous_overrides := _overrides.duplicate()
	var previous_fingerprint := _draft_fingerprint
	var previous_placeholder := _protagonist_placeholder
	_protagonist_draft = copied_action
	_protagonist_placeholder = false
	_draft_fingerprint = JSON.stringify(sim.snapshot()).sha256_text()
	var preview := current_turn_preview()
	if not bool(preview.get("accepted", false)):
		_protagonist_draft = previous_action; _overrides = previous_overrides
		_draft_fingerprint = previous_fingerprint
		_protagonist_placeholder = previous_placeholder
		var rejected := auto_combat_planning_state()
		rejected["accepted"] = false
		rejected["reason"] = str(preview.get("reason", "invalid_party_action"))
		rejected["rejected_preview"] = preview.duplicate(true)
		return rejected.duplicate(true)
	return auto_combat_planning_state()


func _auto_planning_empty(reason: String) -> Dictionary:
	return {"schema_version":1, "active":false, "accepted":false,
		"reason":reason, "placeholder":false,
		"protagonist_action_selected":false, "commit_ready":false,
		"plan_hash":"", "overridden_companion_ids":[], "preview":{}}.duplicate(true)

func override_companion(entity_id: int, action) -> Dictionary:
	if _run_is_complete(): return _rejection_dto("run_complete")
	if _protagonist_draft == null:
		return _rejection_dto("turn_draft_required", action, null, {"actor_id": entity_id})
	var copied_action = _canonical_action_copy(action)
	if copied_action == null or copied_action.actor_id != entity_id:
		return _rejection_dto("override_actor_mismatch", copied_action, null, {"actor_id": entity_id})
	var had_previous := _overrides.has(entity_id); var previous = _overrides.get(entity_id)
	_overrides[entity_id] = copied_action
	var candidate_request = _pending_turn_request()
	var preview := current_turn_preview()
	if not bool(preview.get("accepted", false)):
		preview = _feedback_dto(preview, copied_action, candidate_request)
		if had_previous: _overrides[entity_id] = previous
		else: _overrides.erase(entity_id)
	return preview

func clear_companion_override(entity_id: int) -> Dictionary:
	if _run_is_complete(): return _rejection_dto("run_complete")
	if _protagonist_draft == null:
		return _rejection_dto("turn_draft_required", null, null,
			{"actor_id": entity_id, "action_type": "CLEAR_OVERRIDE"})
	_overrides.erase(entity_id); return current_turn_preview()

func current_turn_preview() -> Dictionary:
	if _run_is_complete(): return _rejection_dto("run_complete")
	if _protagonist_draft == null: return _rejection_dto("turn_draft_required")
	if _draft_fingerprint != JSON.stringify(sim.snapshot()).sha256_text(): _clear_draft(); return _rejection_dto("stale_turn_draft")
	var request = _pending_turn_request()
	var preview: Dictionary = sim.preview_party_turn(request).to_dict().duplicate(true)
	return _feedback_dto(preview, _protagonist_draft, request)

func commit_turn() -> Dictionary:
	if _run_is_complete(): return _rejection_dto("run_complete")
	_exploration_route.cancel_for_direct_command()
	if _protagonist_placeholder:
		return _rejection_dto("protagonist_action_required")
	var preview := current_turn_preview()
	return _commit_turn_from_preview(preview)


func _commit_turn_from_preview(preview:Dictionary)->Dictionary:
	if not bool(preview.get("accepted",false)): return preview
	var request = RequestScript.from_dict(preview.canonical_request)
	var plan_data := preview.duplicate(true)
	for facade_key in ["message", "reason_code", "reason_details", "visual_effect_schema_version",
			"visual_effects"]:
		plan_data.erase(facade_key)
	var plan = load("res://sim/party_turn_plan.gd").new(plan_data)
	var rollback_memento:Variant=sim.capture_rollback_memento()
	if not rollback_memento is Dictionary:return _rejection_dto("snapshot_unavailable")
	var event_start:int=sim.world.events.size();var result=sim.step_party_turn(plan)
	if result.accepted:
		var recovery:=_apply_safe_exploration_recovery(event_start)
		if not bool(recovery.accepted):
			if not sim.restore_rollback_memento(rollback_memento):
				return _rejection_dto("rollback_restore_failed")
			return _rejection_dto(str(recovery.reason))
		if recovery.get("event")!=null:result.events.append(recovery.event)
		_advance_exile_world()
		command_journal.append({"kind":"party_turn", "request":preview.canonical_request.duplicate(true)})
	if result.accepted: _clear_draft()
	return _result_dto(result, null, request)


func inspect_tile(position_value: Variant, viewer_id: int = -1) -> Dictionary:
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return _rejection_dto("session_not_initialized", null, null,
			{"action_type":"INSPECT_TILE"})
	var parsed := _inspection_position(position_value)
	if not bool(parsed.get("ok", false)):
		return _rejection_dto("invalid_tile_position", null, null,
			{"action_type":"INSPECT_TILE"})
	var position: Vector2i = parsed.position
	if not sim.world.in_bounds(position):
		return _rejection_dto("inspect_tile_out_of_bounds", null, null,
			{"action_type":"INSPECT_TILE", "position":[position.x,position.y]})
	var resolved_viewer := viewer_id
	if resolved_viewer == -1:
		resolved_viewer = int(sim.world.party_encounter.protagonist_id)
	if not sim.world.entities.has(resolved_viewer):
		return _rejection_dto("inspect_viewer_not_found", null, null,
			{"action_type":"INSPECT_TILE", "position":[position.x,position.y],
				"viewer_id":resolved_viewer})
	var viewer = sim.world.entities[resolved_viewer]
	if not sim.world.can_act(resolved_viewer, sim.world.world_time):
		return _rejection_dto("inspect_viewer_dead", null, null,
			{"action_type":"INSPECT_TILE", "position":[position.x,position.y],
				"viewer_id":resolved_viewer})
	var assessment = sim.assess_destination(resolved_viewer, position)
	if assessment == null or assessment.sample == null \
			or assessment.affinity == null or assessment.evaluation == null:
		return _rejection_dto("tile_inspection_unavailable", null, null,
			{"action_type":"INSPECT_TILE", "position":[position.x,position.y],
				"viewer_id":resolved_viewer})
	var sample: Dictionary = assessment.sample.to_dict()
	var affinity: Dictionary = assessment.affinity.to_dict()
	var evaluation: Dictionary = assessment.evaluation.to_dict()
	var definition: Dictionary = TerrainRegistryScript.definition(str(sample.terrain_id))
	var occupants: Array = []
	for entity in sim.world.occupying_entities_at(position):
		var member = sim.world.party_member_state(entity.id)
		occupants.append({"entity_id":entity.id,"display_name":str(entity.display_name),
			"health":entity.health,"max_health":entity.max_health,"alive":sim.world.occupies_tile(entity.id),
			"kind":str(entity.kind),"species_id":str(entity.species_id),
			"faction_id":str(entity.faction_id),"tags":entity.tags.duplicate(),
			"role":str(member.role) if member != null else "",
			"presence":str(member.presence) if member != null else "",
			"roster_slot":int(member.roster_slot) if member != null else -1})
	var dto := {"schema_version":PRESENTATION_SCHEMA_VERSION,"accepted":true,"reason":"ok",
		"position":[position.x,position.y],"terrain_id":str(sample.terrain_id),
		"terrain_label":_terrain_label(str(sample.terrain_id)),
		"presentation_key":str(definition.get("presentation_key", "")),
		"passable":bool(sample.passable),"move_time_cost":int(sample.move_time_cost),
		"speed_tier":str(assessment.speed_tier),"occupants":occupants,
		"traversal":assessment.traversal.to_dict() if assessment.traversal != null else null,
		"sample":sample,"provenance":{"sampled_step_index":int(sample.sampled_step_index),
			"sampled_world_time":int(sample.sampled_world_time),
			"after_event_id":int(sample.after_event_id),
			"next_environment_time":int(sample.next_environment_time),
			"source_event_ids":_int_array(sample.source_event_ids),
			"fire_source_event_id":int(sample.fire_source_event_id),
			"wetness_source_event_id":int(sample.wetness_source_event_id)},
		"viewer":{"entity_id":resolved_viewer,"display_name":str(viewer.display_name),
			"species_id":str(viewer.species_id)},"affinity":affinity,
		"risk":{"species_id":str(evaluation.species_id),
			"fire":int(evaluation.fire_score),"water":int(evaluation.water_score),
			"electric":int(evaluation.electric_score),"poison":int(evaluation.poison_score),
			"total":int(evaluation.total_risk)}}
	return _feedback_dto(dto, null, null, {"action_type":"INSPECT_TILE",
		"position":[position.x,position.y],"viewer_id":resolved_viewer})


func _member_combat_stats(entity_id:int)->Dictionary:
	if sim==null or sim.world==null or not sim.world.entities.has(entity_id):return {}
	var combatant=sim.world.combatant_states.get(entity_id)
	var profile:=CombatProfileRegistryScript.profile(str(combatant.combat_profile_id)) \
		if combatant!=null else {}
	var modifier_dto:Dictionary=sim.world.equipment_modifiers(entity_id)
	var bonuses:Dictionary=modifier_dto.get("totals",{}) \
		if modifier_dto.get("totals",{}) is Dictionary else {}
	var defense:=CombatDefenseRulesScript.build_snapshot(
		int(profile.get("evasion_milli",0)),int(profile.get("armor_flat",0)),bonuses)
	var weapon=WeaponRegistryScript.definition(
		ItemOperationsScript.equipped_weapon_id(sim.world,entity_id))
	var rank:=0
	var state=sim.world.party_encounter
	if weapon!=null and state!=null and int(state.protagonist_id)==entity_id \
			and state.protagonist_progression!=null:
		rank=state.protagonist_progression.rank(str(weapon.proficiency_id))
	var spec:Dictionary={}
	if weapon!=null:
		spec=WeaponAttackRulesScript.build_attack_spec(str(weapon.weapon_id),rank,
			int(profile.get("power",0)),int(profile.get("accuracy_milli",0)),0,0,
			ActorStatRulesScript.for_entity(sim.world,entity_id))
	return {"attack_power":int(spec.get("raw_damage",profile.get("power",0))),
		"armor_flat":int(defense.get("effective_armor_flat",profile.get("armor_flat",0))),
		"base_armor_flat":int(defense.get("base_armor_flat",profile.get("armor_flat",0))),
		"evasion_milli":int(defense.get("effective_evasion_milli",profile.get("evasion_milli",0))),
		"base_evasion_milli":int(defense.get("base_evasion_milli",profile.get("evasion_milli",0))),
		"dodge_milli":int(defense.get("dodge_milli",0)),
		"parry_milli":int(defense.get("parry_milli",0)),
		"accuracy_milli":int(profile.get("accuracy_milli",0)) \
			+int(spec.get("proficiency_accuracy_milli",0)),
		"guard_reduction_milli":250,"guard_duration":200}.duplicate(true)


func _member_equipment_summary(entity_id:int)->Dictionary:
	if sim==null or sim.world==null or not sim.world.entities.has(entity_id):
		return {"available":false}.duplicate(true)
	var inventory=sim.world.inventory_of(entity_id)
	if inventory==null:return {"available":false}.duplicate(true)
	var slot_labels:Dictionary={"MAIN_HAND":"무기","OFF_HAND":"보조",
		"ARMOR":"방어구","ACCESSORY":"장신구"}
	var rows:Array=[]
	var named:Dictionary={"MAIN_HAND":"","OFF_HAND":"","ARMOR":"","ACCESSORY":""}
	for slot in ["MAIN_HAND","OFF_HAND","ARMOR","ACCESSORY"]:
		var item=inventory.equipped_item(slot)
		if item==null:continue
		var definition=ItemRegistryScript.definition(str(item.definition_id))
		if definition==null:continue
		var parts:Array[String]=[]
		for bonus_key in ["armor_flat","dodge_milli","parry_milli"]:
			var amount:=int(definition.bonuses.get(bonus_key,0))
			if amount==0:continue
			parts.append("%s %+d"%[{"armor_flat":"방어","dodge_milli":"회피",
				"parry_milli":"막기"}[bonus_key],amount])
		var row:={"slot":slot,"slot_label":str(slot_labels[slot]),
			"definition_id":str(item.definition_id),"label":str(definition.label),
			"stat_text":" · ".join(parts)}
		rows.append(row);named[slot]=str(definition.label)
	var natural_weapon:=false
	if str(named.MAIN_HAND).is_empty():
		var weapon=WeaponRegistryScript.definition(
			ItemOperationsScript.equipped_weapon_id(sim.world,entity_id))
		if weapon!=null:
			named.MAIN_HAND=str(weapon.label);natural_weapon=true
	var combat_stats:=_member_combat_stats(entity_id)
	return {"available":true,"weapon_label":str(named.MAIN_HAND) \
			if not str(named.MAIN_HAND).is_empty() else "없음",
		"off_hand_label":str(named.OFF_HAND) if not str(named.OFF_HAND).is_empty() else "없음",
		"armor_label":str(named.ARMOR) if not str(named.ARMOR).is_empty() else "없음",
		"accessory_label":str(named.ACCESSORY) if not str(named.ACCESSORY).is_empty() else "없음",
		"natural_weapon":natural_weapon,"equipped_rows":rows,
		"combat_stats":combat_stats}.duplicate(true)


func _member_body_presentation(entity_id:int)->Dictionary:
	if sim==null or sim.world==null:return {"available":false}
	var body=sim.world.body_states.get(entity_id)
	if body==null or not body.has_method("validation_error") \
			or not body.validation_error().is_empty():return {"available":false}
	var part_rows:Array=[]
	for part_value in body.parts:
		var part:Dictionary=part_value
		var minimum_integrity:=1000
		for layer_value in part.get("layers",[]):
			if layer_value is Dictionary:
				minimum_integrity=mini(minimum_integrity,int(layer_value.get("integrity",1000)))
		part_rows.append({"part_id":str(part.get("part_id","")),
			"condition":str(part.get("condition","FUNCTIONAL")),
			"integrity_milli":minimum_integrity})
	return {"available":true,"blood":int(body.current_blood),
		"blood_capacity":int(body.body_scalars.get("blood_capacity",0)),
		"shock":int(body.shock),"consciousness":int(body.consciousness),
		"wound_count":body.wounds.size(),"parts":part_rows,
		"function":BodyFunctionRulesScript.appraisal(body)}.duplicate(true)


func _affinity_toward_protagonist(entity_id:int)->Dictionary:
	if sim==null or sim.world==null or sim.world.party_encounter==null \
			or entity_id==int(sim.world.party_encounter.protagonist_id):return {}
	var relation:Dictionary=sim.relationships.effective_relation(entity_id,
		int(sim.world.party_encounter.protagonist_id))
	if relation.is_empty():return {}
	# This is a presentation score only. Canonical recruitment continues to use
	# its explicit species, memory, personality and keyed-roll terms.
	var score:=clampi(50+int(int(relation.get("trust",0))/2)
		-int(int(relation.get("fear",0))/3)-int(int(relation.get("hostility",0))/2)
		+int(int(relation.get("gratitude",0))/2)-int(int(relation.get("grievance",0))/2),0,100)
	var label:="매우 높음" if score>=75 else ("높음" if score>=60 else (
		"보통" if score>=40 else ("낮음" if score>=25 else "경계")))
	return {"score":score,"label":label,"trust":int(relation.get("trust",0)),
		"fear":int(relation.get("fear",0)),"hostility":int(relation.get("hostility",0)),
		"gratitude":int(relation.get("gratitude",0)),
		"grievance":int(relation.get("grievance",0)),
		"disposition":str(relation.get("disposition","NEUTRAL"))}.duplicate(true)


func inspect_party_member(entity_id: int) -> Dictionary:
	if sim == null or sim.world == null or sim.world.party_encounter == null:
		return _rejection_dto("session_not_initialized", null, null,
			{"action_type":"INSPECT_MEMBER","actor_id":entity_id})
	var state = sim.world.party_encounter
	var member = state.member(entity_id)
	if member == null and (_rescue_discovery_event_for(entity_id) != null \
			or _is_opening_recruitment_candidate(entity_id)):
		return _inspect_rescue_candidate(entity_id)
	if member == null or not sim.world.entities.has(entity_id):
		return _rejection_dto("party_member_not_found", null, null,
			{"action_type":"INSPECT_MEMBER","actor_id":entity_id})
	var entity = sim.world.entities[entity_id]
	var combatant = sim.world.combatant_states.get(entity_id)
	var life_state := str(combatant.life_state) if combatant != null else "DEAD"
	var logical: Vector2i = entity.position if member.presence == "DEPLOYED" else (
		state.group_anchor if member.presence == "GROUPED" else Vector2i(-1,-1))
	var full_exposure := {"applicable":false,"position":[logical.x,logical.y],
		"sample":null,"affinity":null,"risk":null}
	var compact_exposure := {"applicable":false,"sampled_step_index":sim.world.step_index,
		"sampled_world_time":sim.world.world_time,"position":[-1,-1],"fire_score":0,
		"water_score":0,"electric_score":0,"poison_score":0,"total_risk":0}
	if member.presence in ["DEPLOYED","GROUPED"] and sim.world.is_environment_exposed(entity_id):
		var evaluated = sim.evaluate_exposure_for_entity(entity_id, logical)
		if evaluated != null:
			var sample_wire: Dictionary = evaluated.sample.to_dict()
			var affinity_wire: Dictionary = evaluated.affinity.to_dict()
			var risk_wire: Dictionary = evaluated.evaluation.to_dict()
			full_exposure = {"applicable":true,"position":[logical.x,logical.y],
				"sample":sample_wire,"affinity":affinity_wire,
				"risk":{"species_id":str(risk_wire.species_id),
					"fire":int(risk_wire.fire_score),"water":int(risk_wire.water_score),
					"electric":int(risk_wire.electric_score),"poison":int(risk_wire.poison_score),
					"total":int(risk_wire.total_risk)}}
			compact_exposure = {"applicable":true,"sampled_step_index":int(risk_wire.sampled_step_index),
				"sampled_world_time":int(risk_wire.sampled_world_time),"position":risk_wire.position,
				"fire_score":int(risk_wire.fire_score),"water_score":int(risk_wire.water_score),
				"electric_score":int(risk_wire.electric_score),"poison_score":int(risk_wire.poison_score),
				"total_risk":int(risk_wire.total_risk)}
	var expected_action: Variant = _pure_expected_action(entity_id)
	var readiness := "행동 준비" if member.busy_until <= sim.world.world_time else "행동 중"
	var emotion := _emotion_presentation(member, entity)
	var personality_profile = null
	var personality_facets: Array = []
	var personality_style_dto: Dictionary = {}
	if member.personality_profile != null:
		personality_profile = member.personality_profile.to_dict()
		personality_style_dto = personality_style(member.personality_profile)
		for row in _hexaco_facet_rows(member.personality_profile):
			var labels: Array = HEXACO_LABELS.get(str(row.facet_id), ["낮음","높음"])
			personality_facets.append({"facet_id":str(row.facet_id),"value":int(row.base_value),
				"low_label":str(labels[0]),"high_label":str(labels[1])})
	var relation_rows: Array = []
	var relation_ids: Array = state.party_member_ids.duplicate()
	relation_ids.sort_custom(func(a,b):
		var member_a=state.member(int(a));var member_b=state.member(int(b))
		return int(member_a.roster_slot)<int(member_b.roster_slot) \
			if int(member_a.roster_slot)!=int(member_b.roster_slot) else int(a)<int(b))
	for subject_id_value in relation_ids:
		var subject_id := int(subject_id_value)
		if subject_id == entity_id or not sim.world.entities.has(subject_id): continue
		var relation: Dictionary = sim.relationships.effective_relation(entity_id,subject_id)
		relation_rows.append({"subject_id":subject_id,
			"subject_name":str(sim.world.entities[subject_id].display_name),
			"subject_species_id":str(sim.world.entities[subject_id].species_id),
			"trust":int(relation.get("trust",0)),"fear":int(relation.get("fear",0)),
			"hostility":int(relation.get("hostility",0)),
			"gratitude":int(relation.get("gratitude",0)),
			"grievance":int(relation.get("grievance",0)),
			"disposition":str(relation.get("disposition","NEUTRAL")),
			"species_base":relation.get("species_base",{}).duplicate(true),
			"personal":relation.get("personal",{}).duplicate(true)})
	var override_state := "PENDING"
	if expected_action is Dictionary: override_state = str(expected_action.source)
	elif member.role == "PROTAGONIST": override_state = "DIRECT"
	var dto := {"schema_version":PRESENTATION_SCHEMA_VERSION,"accepted":true,"reason":"ok",
		"entity_id":entity_id,"roster_slot":int(member.roster_slot),"role":str(member.role),
		"display_name":str(entity.display_name),"health":int(entity.health),
		"max_health":int(entity.max_health),"alive":sim.world.occupies_tile(entity_id),
		"kind":str(entity.kind),"tags":entity.tags.duplicate(),"species_id":str(entity.species_id),
		"faction_id":str(entity.faction_id),"status_ids":_combatant_status_ids(entity_id),
		"life_state":life_state,
		"presence":str(member.presence),"active_party_member":entity_id in state.active_party_member_ids,
		"recruitable_member":member.presence == "RECRUITABLE",
		"exiled_member":member.presence == "EXILED",
		"logical_position":[logical.x,logical.y],
		"busy_until":int(member.busy_until),
		"remaining_time":maxi(0,int(member.busy_until)-int(sim.world.world_time)),
		"stress":int(member.stress),"readiness":readiness,"emotion":emotion,
		"override_state":override_state,"expected_action":expected_action,
		"element_exposure":compact_exposure,"current_exposure":full_exposure,
		"core_stats":ActorStatRulesScript.for_entity(sim.world,entity_id),
		"combat_stats":_member_combat_stats(entity_id),
		"equipment_summary":_member_equipment_summary(entity_id),
		"body_state":_member_body_presentation(entity_id),
		"personality_profile":personality_profile,"personality_available":personality_profile != null,
		"personality_facets":personality_facets,"personality_style":personality_style_dto,
		"personality_note":"주인공은 생성형 성격 프로필을 사용하지 않습니다." \
			if personality_profile == null else "%s · 결정론적 성격 프로필" \
				% str(personality_style_dto.get("label","균형 잡힌 성향")),
		"species_affinity":AffinityRegistryScript.affinity_for(entity.species_id).to_dict(),
		"affinity_toward_protagonist":_affinity_toward_protagonist(entity_id),
		"relation_rows":relation_rows,"exile_record":_exile_record_for_member(entity_id),
		"rescue_assessment":rescue_assessment(entity_id) \
			if member.presence=="RECRUITABLE" and life_state=="DOWNED" else {},
		"attack_assessment":npc_attack_assessment(entity_id) \
			if member.presence=="RECRUITABLE" else {},
		"progression":protagonist_progression() if member.role=="PROTAGONIST" else {},
		"growth_build":protagonist_growth_build() if member.role=="PROTAGONIST" else {},
		"recruitment_assessment":recruitment_assessment(entity_id) \
			if member.presence=="RECRUITABLE" and _rescue_event_for(entity_id)!=null else {}}
	return _feedback_dto(dto, null, null,
		{"action_type":"INSPECT_MEMBER","actor_id":entity_id})


func _inspect_rescue_candidate(entity_id: int) -> Dictionary:
	if not sim.world.entities.has(entity_id):
		return _rejection_dto("party_member_not_found")
	var entity = sim.world.entities[entity_id]
	var opening_candidate:=_is_opening_recruitment_candidate(entity_id)
	var story_state := "OFFER_READY" if opening_candidate else rescue_story_state(entity_id)
	var profile = sim.world.party_encounter.opening_event.hexaco_profile \
		if opening_candidate else _rescue_personality_profile(entity_id)
	var facets: Array = []
	if profile != null:
		for row in _hexaco_facet_rows(profile):
			var labels: Array = HEXACO_LABELS.get(str(row.facet_id),
				["낮음","높음"])
			facets.append({"facet_id":str(row.facet_id),"value":int(row.base_value),
				"low_label":str(labels[0]),"high_label":str(labels[1])})
	var relation_rows: Array = []
	var hero_id := int(sim.world.party_encounter.protagonist_id)
	var relation: Dictionary = sim.relationships.effective_relation(entity_id,hero_id)
	if sim.world.entities.has(hero_id):
		relation_rows.append({"subject_id":hero_id,
			"subject_name":str(sim.world.entities[hero_id].display_name),
			"subject_species_id":str(sim.world.entities[hero_id].species_id),
			"trust":int(relation.get("trust",0)),"fear":int(relation.get("fear",0)),
			"hostility":int(relation.get("hostility",0)),
			"gratitude":int(relation.get("gratitude",0)),
			"grievance":int(relation.get("grievance",0)),
			"disposition":str(relation.get("disposition","NEUTRAL")),
			"species_base":relation.get("species_base",{}).duplicate(true),
			"personal":relation.get("personal",{}).duplicate(true)})
	var position: Vector2i = entity.position
	var style := personality_style(profile)
	var collapsed := story_state == "COLLAPSED_STORY"
	var dto := {"schema_version":PRESENTATION_SCHEMA_VERSION,"accepted":true,"reason":"ok",
		"entity_id":entity_id,"roster_slot":63,"role":"COMPANION",
		"display_name":str(entity.display_name),"health":int(entity.health),
		"max_health":int(entity.max_health),"alive":true,"kind":str(entity.kind),
		"tags":entity.tags.duplicate(),"species_id":str(entity.species_id),
		"faction_id":str(entity.faction_id),"status_ids":_combatant_status_ids(entity_id),
		"life_state":"DOWNED" if collapsed else "ACTIVE",
		"authoritative_life_state":str(sim.world.combatant_states[entity_id].life_state),
		"rescue_story_state":story_state,"presence":"WORLD_NPC",
		"active_party_member":false,"recruitable_member":true,"exiled_member":false,
		"logical_position":[position.x,position.y],"busy_until":int(sim.world.world_time),
		"remaining_time":0,"stress":0,
		"readiness":"도움 필요" if collapsed else (
			"재회 · 영입 대화 가능" if opening_candidate else "대화 가능"),
		"emotion":{"icon":"!" if collapsed else "●",
			"label":"쓰러짐" if collapsed else "안정됨",
			"reason":"심한 상처로 움직이지 못합니다." if collapsed \
				else "상처를 안정화해 대화할 수 있습니다.","health_percent":
				int(entity.health*100/maxi(1,entity.max_health))},
		"override_state":"PENDING","expected_action":null,
		"element_exposure":{"applicable":false},"current_exposure":{"applicable":false},
		"core_stats":ActorStatRulesScript.for_entity(sim.world,entity_id),
		"combat_stats":_member_combat_stats(entity_id),
		"equipment_summary":_member_equipment_summary(entity_id),
		"body_state":_member_body_presentation(entity_id),
		"personality_profile":profile.to_dict() if profile != null else null,
		"personality_available":profile != null,"personality_facets":facets,
		"personality_style":style,
		"personality_note":"%s · 결정론적 HEXACO 프로필"%str(style.get("label","동료")),
		"species_affinity":AffinityRegistryScript.affinity_for(entity.species_id).to_dict(),
		"affinity_toward_protagonist":_affinity_toward_protagonist(entity_id),
		"relation_rows":relation_rows,"exile_record":null,
		"rescue_assessment":rescue_assessment(entity_id) if collapsed else {},
		"attack_assessment":npc_attack_assessment(entity_id),
		"opening_reencounter":opening_candidate,
		"recruitment_assessment":recruitment_assessment(entity_id) \
			if story_state in ["OFFER_READY","REJECTED"] else {}}
	return _feedback_dto(dto, null, null,
		{"action_type":"INSPECT_MEMBER","actor_id":entity_id})


func combat_log(turn_limit: int = 8, row_limit: int = 80) -> Dictionary:
	var checked_turn_limit := clampi(turn_limit,0,64)
	var checked_row_limit := clampi(row_limit,0,500)
	var important_events:Array=[]
	for event in sim.world.events:
		if _is_important_log_event(event):important_events.append(event)
	var selected_steps: Array = []
	if checked_turn_limit > 0 and checked_row_limit > 0:
		for index in range(important_events.size()-1,-1,-1):
			var step_index := int(important_events[index].step_index)
			if not selected_steps.has(step_index):
				selected_steps.append(step_index)
				if selected_steps.size() >= checked_turn_limit: break
	selected_steps.sort()
	var selected_events: Array = []
	for event in important_events:
		if selected_steps.has(int(event.step_index)): selected_events.append(event)
	if selected_events.size() > checked_row_limit:
		selected_events = selected_events.slice(selected_events.size()-checked_row_limit)
	var groups_by_step: Dictionary = {}
	var ordered_steps: Array = []
	for event in selected_events:
		var step_index := int(event.step_index)
		if not groups_by_step.has(step_index):
			groups_by_step[step_index]={"step_index":step_index,"start_time":int(event.world_time),
				"end_time":int(event.world_time),"rows":[]}
			ordered_steps.append(step_index)
		var group: Dictionary = groups_by_step[step_index]
		group.end_time = int(event.world_time)
		group.rows.append(_combat_event_row(event))
		groups_by_step[step_index]=group
	var groups: Array = []
	for step_index in ordered_steps: groups.append(groups_by_step[step_index])
	return {"schema_version":PRESENTATION_SCHEMA_VERSION,"turn_limit":checked_turn_limit,
		"row_limit":checked_row_limit,"group_count":groups.size(),
		"row_count":selected_events.size(),"groups":groups}.duplicate(true)


func recent_event_log(limit: int = 24) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var important_events:Array=[]
	for event in sim.world.events:
		if _is_important_log_event(event):important_events.append(event)
	var start := maxi(0,important_events.size()-clampi(limit,0,100))
	for index in range(start,important_events.size()):
		var event=important_events[index]
		rows.append({"event_id":event.id,"step_index":event.step_index,
			"world_time":event.world_time,"message":_event_message(event)})
	return rows.duplicate(true)


func _is_important_log_event(event)->bool:
	var event_type:=str(event.type)
	if event_type in ["encounter.detected","encounter.party_ambush","encounter.enemy_ambush",
			"party.contact_reported",
			"party.command_issued","party.npc_assaulted",
			"action.melee_attack","combat.attack_missed","combat.attack_parried","entity.downed",
			"entity.recovered","entity.died","party.victory","party.rescue_discovered",
			"party.npc_stabilized","party.recruitment_accepted",
			"party.recruitment_refused","party.companion_recruited",
			"party.companion_dismissed","party.exile_died","status.applied",
			"status.expired","item.picked_up","item.equipped","item.unequipped",
			"item.dropped","item.discarded","item.used","health.restored",
			"progression.enemy_reward","opening.npc_discovered",
			"opening.choice_committed","opening.potion_given",
			"opening.health_restored","opening.reencountered",
			"relationship.gratitude_recorded","growth.enemy_reward",
			"growth.stat_spent","growth.species_point_spent",
			"growth.mutation_swapped"]:
		return true
	return event_type.begins_with("combat.") and event_type.ends_with("_damage")

func save_session_json() -> String:
	return JSON.stringify({"session_format_version":SESSION_FORMAT_VERSION,
		"scenario_id":scenario_id,"player_species_id":player_species_id,
		"world_seed":str(world_seed),
		"personality_seed":str(personality_seed),"snapshot":sim.snapshot(),
		"journal":command_journal.duplicate(true)})

func load_session_json(encoded: String) -> Dictionary:
	var decoded = JSON.parse_string(encoded)
	if not decoded is Dictionary:
		return _rejection_dto("invalid_party_session")
	var top_keys: Array = decoded.keys(); top_keys.sort()
	if top_keys != ["journal", "personality_seed", "player_species_id", "scenario_id", "session_format_version", "snapshot", "world_seed"] \
			or not _integer(decoded.get("session_format_version")) \
			or int(decoded.session_format_version) != SESSION_FORMAT_VERSION \
			or not decoded.get("scenario_id") is String \
			or not decoded.get("player_species_id") is String \
			or not GrowthBuildRegistryScript.has_species(str(decoded.player_species_id)) \
			or not VisualTestMapScript.has_scenario(str(decoded.scenario_id)) \
			or not decoded.get("snapshot") is Dictionary \
			or not Int64CodecScript.is_canonical(decoded.get("world_seed")) \
			or not Int64CodecScript.is_canonical(decoded.get("personality_seed")) \
			or not decoded.get("journal") is Array or decoded.journal.size() > 10000:
		return _rejection_dto("invalid_party_session_wire")
	if int(decoded.snapshot.get("snapshot_version",0))!=WorldStateScript.SNAPSHOT_VERSION:
		return _rejection_dto("unsupported_snapshot_version")
	# Raw hard-cut preflight: reject old nested growth/party schemas and species
	# before any numeric normalization or object construction can reinterpret them.
	var raw_party:Variant=decoded.snapshot.get("party_encounter")
	if not raw_party is Dictionary \
			or int(raw_party.get("schema_version",0))!=PartyStateScript.SCHEMA_VERSION \
			or not raw_party.get("protagonist_growth") is Dictionary \
			or int(raw_party.protagonist_growth.get("schema_version",0)) \
				!=GrowthBuildStateScript.SCHEMA_VERSION \
			or str(raw_party.protagonist_growth.get("species_id","")) \
				!=str(decoded.player_species_id):
		return _rejection_dto("unsupported_player_species_snapshot")
	var journal_error := _journal_wire_error(decoded.journal)
	if not journal_error.is_empty(): return _rejection_dto(journal_error)
	_normalize_item_json_numbers(decoded.snapshot.get("party_encounter",{}))
	_normalize_world_item_json_numbers(decoded.snapshot.get("item_state"))
	var source_party_schema:=int(decoded.snapshot.party_encounter.get("schema_version",1))
	# Some migration tests intentionally downgrade a current snapshot. The v15
	# marker distinguishes that fixture from a real pre-HEXACO save, whose old
	# journal cannot be replayed under the new personality semantics.
	var source_has_hexaco_marker: bool = decoded.snapshot.party_encounter.has(
		"legacy_journal_origin")
	var legacy_personality_origin: bool = source_party_schema \
		< PartyStateScript.HEXACO_SCHEMA_VERSION and not source_has_hexaco_marker
	if source_party_schema < PartyStateScript.HEXACO_SCHEMA_VERSION:
		decoded.snapshot.party_encounter.erase("legacy_journal_origin")
	var legacy_opening_replay := source_party_schema \
		< PartyStateScript.OPENING_EVENT_SCHEMA_VERSION \
		or decoded.snapshot.party_encounter.get("opening_event") == null
	var source_progression_row:Dictionary=decoded.snapshot.party_encounter.get(
		"protagonist_progression",{})
	var source_progression_schema:int=int(source_progression_row.get("schema_version",0))
	# v1-v3 were victory-reward runs. A migrated v5 snapshot retains the same
	# explicit origin bit, so replay must begin from that historical baseline.
	var legacy_progression_replay:bool=source_party_schema<PartyStateScript.PROGRESSION_SCHEMA_VERSION \
		or source_progression_schema<ProgressionRegistryScript.SCHEMA_VERSION \
		or bool(source_progression_row.get("legacy_reward_origin",false))
	var legacy_progression_modes:Dictionary={"SWORD":"NORMAL","AXE":"NORMAL",
		"BLUNT":"NORMAL","SPEAR":"NORMAL","RANGED":"NORMAL","UNARMED":"NORMAL"}
	if not source_progression_row.is_empty():
		var parsed_legacy_progression=ProgressionScript.from_dict(source_progression_row)
		if parsed_legacy_progression!=null:
			legacy_progression_modes=parsed_legacy_progression.training_modes.duplicate(true)
	if source_party_schema<PartyStateScript.ITEM_SCHEMA_VERSION:
		decoded.snapshot.party_encounter.erase("protagonist_inventory")
		decoded.snapshot.party_encounter.erase("ground_items")
	if source_party_schema<PartyStateScript.OPENING_EVENT_SCHEMA_VERSION:
		decoded.snapshot.party_encounter.erase("opening_event")
	if source_party_schema<PartyStateScript.GROWTH_BUILD_SCHEMA_VERSION:
		# Growth v1 intentionally uses a hard cut: old expeditions start from the
		# species baseline and do not infer allocations or traces from old history.
		decoded.snapshot.party_encounter.erase("protagonist_growth")
	if source_party_schema<PartyStateScript.AWARENESS_SCHEMA_VERSION \
			and decoded.snapshot.party_encounter.has("enemy_awareness_rows"):
		decoded.snapshot.party_encounter.erase("enemy_awareness_rows")
	if source_party_schema<PartyStateScript.LOADOUT_SCHEMA_VERSION \
			and decoded.snapshot.party_encounter.has("protagonist_loadout"):
		# A v1-v4 row has no loadout field at all. v5-v12 rows keep theirs so the
		# historical wire stays exact; v13 dropped the duplicate weapon authority
		# and PartyEncounterState.from_dict discards the legacy value.
		decoded.snapshot.party_encounter.erase("protagonist_loadout")
	if source_party_schema<PartyStateScript.DIAGONAL_GATEWAY_SCHEMA_VERSION \
			and decoded.snapshot.party_encounter.has("diagonal_gateway_positions"):
		decoded.snapshot.party_encounter.erase("diagonal_gateway_positions")
	if source_party_schema<PartyStateScript.PROGRESSION_SCHEMA_VERSION \
			and decoded.snapshot.party_encounter.has("protagonist_progression"):
		# Compatibility fixtures downgrade a current wire by removing fields at the
		# historical boundary. Legacy state is rebuilt from canonical events below;
		# final journal-to-snapshot equality remains the tamper gate.
		decoded.snapshot.party_encounter.erase("protagonist_progression")
	if source_party_schema<PartyStateScript.PATROL_SCHEMA_VERSION \
			and decoded.snapshot.party_encounter.has("patrol_reserved_positions") \
			and decoded.snapshot.party_encounter.patrol_reserved_positions==[]:
		# Some callers build a legacy fixture by downgrading the version/current
		# snapshot and removing the fields known at that historical boundary.
		decoded.snapshot.party_encounter.erase("patrol_reserved_positions")
	var parsed_world_seed := Int64CodecScript.parse(decoded.world_seed,"world seed")
	var parsed_personality_seed := Int64CodecScript.parse(decoded.personality_seed,"personality seed")
	var parsed_scenario_id := str(decoded.scenario_id)
	var parsed_player_species_id:=str(decoded.player_species_id)
	if source_party_schema < PartyStateScript.HEXACO_SCHEMA_VERSION:
		var legacy_party_error := PartyStateScript.wire_error(
			decoded.snapshot.party_encounter, int(decoded.snapshot.width),
			int(decoded.snapshot.height))
		if not legacy_party_error.is_empty():
			return _rejection_dto(legacy_party_error)
		var migrated_party = PartyStateScript.from_dict(decoded.snapshot.party_encounter)
		if migrated_party == null or not _migrate_party_hexaco_state(migrated_party,
				parsed_personality_seed, legacy_personality_origin):
			return _rejection_dto("party_hexaco_migration_failed")
		decoded.snapshot.party_encounter = migrated_party.to_dict()
		if legacy_progression_replay:
			# The outer party wire must already be v15 so companion rows validate as
			# HEXACO. Keep only the nested progression wire at its last pre-v5
			# boundary: WorldState then rebuilds the historical reward ledger from
			# canonical events exactly as it did before the personality migration.
			var compatibility_progression = ProgressionScript.new()
			compatibility_progression.training_modes = \
				legacy_progression_modes.duplicate(true)
			var compatibility_progression_wire: Dictionary = \
				compatibility_progression.to_dict()
			compatibility_progression_wire.schema_version = \
				ProgressionScript.DEATH_SCHEMA_VERSION
			compatibility_progression_wire.erase("legacy_reward_origin")
			decoded.snapshot.party_encounter.protagonist_progression = \
				compatibility_progression_wire
	var replay_layout:Dictionary={}
	if VisualTestMapScript.uses_product_dungeon(parsed_scenario_id):
		var current_layout:=VisualTestMapScript.product_dungeon(parsed_world_seed)
		var previous_layout:=VisualTestMapScript.previous_product_dungeon(
			parsed_world_seed)
		var legacy_layout:=VisualTestMapScript.legacy_product_dungeon(parsed_world_seed)
		# Detect before strict restoration, which may normalize input rows in place.
		# Product terrain itself is immutable during play.
		if _snapshot_terrain_matches_layout(decoded.snapshot,legacy_layout):
			replay_layout=legacy_layout
		elif _snapshot_terrain_matches_layout(decoded.snapshot,previous_layout):
			replay_layout=previous_layout
		else:
			replay_layout=current_layout
	var restored = SimulatorScript.from_snapshot(decoded.snapshot)
	if restored == null or restored.world.party_encounter == null:
		var restore_reason := WorldStateScript.snapshot_restore_error(decoded.snapshot)
		return _rejection_dto(restore_reason if not restore_reason.is_empty() else "invalid_party_snapshot")
	if source_party_schema<PartyStateScript.AWARENESS_SCHEMA_VERSION:
		for enemy_id_value in restored.world.party_encounter.enemy_ids:
			var enemy_id:=int(enemy_id_value)
			var awareness=restored.world.party_encounter.enemy_awareness(enemy_id)
			if awareness!=null and restored.world.entities.has(enemy_id):
				awareness.home_position=restored.world.entities[enemy_id].position
	if source_party_schema<PartyStateScript.PATROL_SCHEMA_VERSION \
			and VisualTestMapScript.uses_los_fov(parsed_scenario_id):
		# v1/v2 saves predate patrol reservations. Reconstruct presentation-map
		# objectives once at the checked migration boundary before replay compare.
		var migrated_layout := replay_layout if VisualTestMapScript.uses_product_dungeon(
			parsed_scenario_id) else {}
		var migrated_manifest := VisualTestMapScript.run_manifest(
			parsed_scenario_id, migrated_layout)
		var migrated_positions: Array = [
			Vector2i(int(migrated_manifest.exit.position[0]),
				int(migrated_manifest.exit.position[1])),
			Vector2i(int(migrated_manifest.entry.position[0]),
				int(migrated_manifest.entry.position[1])),
		]
		migrated_positions.append_array(migrated_layout.get("door_positions", []))
		migrated_positions.append_array([VisualTestMapScript.EXIT_POSITION,
			VisualTestMapScript.OPEN_DOOR_POSITION, VisualTestMapScript.ENTRY_POSITION])
		for migrated_position in migrated_positions:
			if restored.world.in_bounds(migrated_position) and migrated_position \
					not in restored.world.party_encounter.patrol_reserved_positions:
				restored.world.party_encounter.patrol_reserved_positions.append(
					migrated_position)
	if source_party_schema<PartyStateScript.DIAGONAL_GATEWAY_SCHEMA_VERSION \
			and VisualTestMapScript.uses_los_fov(parsed_scenario_id):
		var gateway_layout := replay_layout if VisualTestMapScript.uses_product_dungeon(
			parsed_scenario_id) else {}
		var migrated_gateways: Array = gateway_layout.get("door_positions", []).duplicate()
		if VisualTestMapScript.uses_showcase_layout(parsed_scenario_id):
			migrated_gateways.append(VisualTestMapScript.OPEN_DOOR_POSITION)
		for migrated_gateway in migrated_gateways:
			if restored.world.in_bounds(migrated_gateway) \
					and migrated_gateway not in restored.world.party_encounter.diagonal_gateway_positions:
				restored.world.party_encounter.diagonal_gateway_positions.append(migrated_gateway)
	var replay = load("res://playtest/party_playtest_session.gd").new(
		parsed_world_seed, parsed_personality_seed, parsed_scenario_id,
		parsed_player_species_id)
	if not replay_layout.is_empty() and not replay.reset_party(parsed_world_seed,
			parsed_personality_seed,parsed_scenario_id,replay_layout,
			not legacy_opening_replay,parsed_player_species_id):
		return _rejection_dto("party_layout_replay_failed")
	if restored.world.party_encounter.legacy_journal_origin:
		return _install_restored_session(restored, decoded, parsed_world_seed,
			parsed_personality_seed, parsed_scenario_id, replay._map_layout)
	# Items are world authority from snapshot v7 on. A nested party version says
	# nothing about them any more, so replay keeps the canonical world item state.
	if legacy_progression_replay:
		var legacy_progression=replay.sim.world.party_encounter.protagonist_progression
		legacy_progression.legacy_reward_origin=true
		legacy_progression.training_modes=legacy_progression_modes.duplicate(true)
	for row in decoded.journal:
		var replay_result:Dictionary={"accepted":false}
		match str(row.kind):
			"opening":
				replay_result = replay.commit_opening_event_choice(
					str(row.operation.action))
			"growth":
				var growth_operation:Dictionary=row.operation
				match str(growth_operation.action):
					"SPEND_STAT_POINT":
						replay_result=replay.spend_growth_stat_point(
							str(growth_operation.target_id))
					"SPEND_SPECIES_POINT":
						replay_result=replay.spend_species_trait_point(
							str(growth_operation.target_id))
					"SWAP_MUTATION":
						replay_result=replay.swap_mutation_trace(
							int(growth_operation.slot_index),str(growth_operation.mutation_id))
			"equipment":
				var operation:Dictionary=row.operation
				replay_result=replay.equip_protagonist_weapon(str(operation.weapon_id)) \
					if str(operation.action)=="EQUIP" else replay.reload_protagonist_weapon()
			"progression":
				var progression_operation:Dictionary=row.operation
				replay_result=replay.set_training_mode(str(progression_operation.skill_id),
					str(progression_operation.mode)) \
					if str(progression_operation.action)=="SET_TRAINING_MODE" \
					else replay._replay_legacy_training_focus(str(progression_operation.skill_id))
			"item":
				var item_operation:Dictionary=row.operation
				match str(item_operation.action):
					"PICKUP":replay_result=replay.pickup_ground_item(str(item_operation.instance_id))
					"EQUIP":replay_result=replay.equip_inventory_item(str(item_operation.instance_id),str(item_operation.slot))
					"UNEQUIP":replay_result=replay.unequip_inventory_slot(str(item_operation.slot))
					"DROP":replay_result=replay.drop_inventory_item(str(item_operation.instance_id))
					"DISCARD":replay_result=replay.discard_inventory_item(str(item_operation.instance_id))
					"USE":replay_result=replay.use_inventory_item(str(item_operation.instance_id))
			"exploration":
				var command=CommandScript.from_dict(row.command)
				replay_result=replay.commit_exploration(command)
			"deployment":
				var request:Dictionary=row.request; var companion_ids: Array = []
				for value in request.companion_ids: companion_ids.append(Int64CodecScript.parse(value, "deployment companion"))
				replay.preview_deployment(str(request.preset_id), companion_ids); replay_result=replay.commit_deployment()
			"roster":
				var operation: Dictionary = row.operation
				var entity_id := Int64CodecScript.parse(operation.entity_id,"roster member")
				match str(operation.action):
					"DISMISS": replay_result = replay.dismiss_companion(entity_id)
					"RECRUIT": replay_result = replay.recruit_companion(entity_id)
					"STABILIZE": replay_result = replay.stabilize_recruit_candidate(entity_id)
					"OFFER_RECRUIT": replay_result = replay.offer_recruitment(entity_id)
			"npc_assault":
				var operation:Dictionary=row.operation
				replay_result=replay.assault_npc(Int64CodecScript.parse(
					operation.entity_id,"assaulted npc"))
			"party_command":
				var operation:Dictionary=row.operation
				replay_result=replay.issue_party_command(str(operation.command_id),
					Int64CodecScript.parse(operation.target_id,"party command target"))
			"party_turn":
				var request:Dictionary=row.request; var direct=ActionScript.from_dict(request.protagonist_action)
				replay.begin_turn(direct)
				for override in request.overrides:
					var action=ActionScript.from_dict(override.action)
					replay.override_companion(Int64CodecScript.parse(override.actor_id,"override actor"),action)
				replay_result=replay.commit_turn()
		if not bool(replay_result.get("accepted",false)):return _rejection_dto("party_journal_replay_failed")
	if replay.sim.snapshot()!=restored.snapshot():return _rejection_dto("party_journal_snapshot_mismatch")
	return _install_restored_session(restored, decoded, parsed_world_seed,
		parsed_personality_seed, parsed_scenario_id, replay._map_layout)


func _migrate_party_hexaco(world, stored_personality_seed: int,
		legacy_origin: bool = true) -> bool:
	if world == null or world.party_encounter == null: return false
	var state = world.party_encounter
	if not _migrate_party_hexaco_state(state, stored_personality_seed, legacy_origin):
		return false
	return world.world_state_error().is_empty()


func _migrate_party_hexaco_state(state, stored_personality_seed: int,
		legacy_origin: bool) -> bool:
	if state == null: return false
	for member_id_value in state.party_member_ids:
		var member_id := int(member_id_value)
		var member = state.member(member_id)
		if member == null: return false
		member.personality_profile = null if member.role == "PROTAGONIST" else \
			PartyHexacoScript.generated(stored_personality_seed, member_id)
	for index in range(state.exile_records.size()):
		var record: Dictionary = state.exile_records[index]
		var former_id := Int64CodecScript.parse(record.former_member_id,
			"former party member")
		var profile = PartyHexacoScript.generated(stored_personality_seed, former_id)
		var style: Dictionary = profile.style_summary()
		var profile_wire: Dictionary = profile.to_dict()
		record.schema_version = 2
		record.personality_summary = {"style_label":str(style.label),
			"profile_hash":JSON.stringify(profile_wire).sha256_text(),
			"H":profile.value("H"),"E":profile.value("E"),"X":profile.value("X"),
			"A":profile.value("A"),"C":profile.value("C"),"O":profile.value("O")}
		state.exile_records[index] = record
	state.schema_version = PartyStateScript.SCHEMA_VERSION
	state.legacy_journal_origin = legacy_origin
	return true


func _install_restored_session(restored, decoded: Dictionary,
		parsed_world_seed: int, parsed_personality_seed: int,
		parsed_scenario_id: String, restored_layout: Dictionary) -> Dictionary:
	sim = restored; world_seed = parsed_world_seed; personality_seed = parsed_personality_seed
	scenario_id = parsed_scenario_id;player_species_id=str(decoded.player_species_id)
	_map_layout = restored_layout.duplicate(true)
	command_journal.clear()
	for row in decoded.journal: command_journal.append(row.duplicate(true))
	_deployment_plan.clear(); _clear_draft(); _exploration_route.clear()
	if _auto_explore == null: _auto_explore = AutoExploreScript.new(self)
	else: _auto_explore.clear()
	_invalidate_explored_presentation_cache()
	_presentation_topology_cache.clear()
	_presentation_visibility_cache.clear()
	_warm_product_topology_presentation_cache()
	return _feedback_dto({"accepted":true,"reason":"ok"})

func _snapshot_terrain_matches_layout(snapshot:Dictionary,layout:Dictionary)->bool:
	var tiles:Variant=snapshot.get("tiles",[]);var terrain:Variant=layout.get("terrain",[])
	if not tiles is Array or not terrain is Array or tiles.size()!=terrain.size():return false
	for index in range(tiles.size()):
		if not tiles[index] is Dictionary \
				or str(tiles[index].get("terrain",""))!=str(terrain[index]):return false
	return true


func _normalize_item_json_numbers(party_row:Variant)->void:
	# JSON has no integer token type in Godot's generic decoder. Restore only the
	# checked item integer fields at this transport boundary; direct wire APIs stay
	# strict and non-integral/tampered values remain untouched and fail validation.
	if not party_row is Dictionary:return
	for key in ["protagonist_inventory","ground_items"]:
		var root:Variant=party_row.get(key)
		if not root is Dictionary:continue
		if root.get("schema_version") is float and root.schema_version==floor(root.schema_version):
			root.schema_version=int(root.schema_version)
		if key=="protagonist_inventory":
			if root.get("backpack_capacity") is float \
					and root.backpack_capacity==floor(root.backpack_capacity):
				root.backpack_capacity=int(root.backpack_capacity)
			for item_row in root.get("backpack",[]):_normalize_item_instance_json_numbers(item_row)
		else:
			for ground_row in root.get("rows",[]):
				if ground_row is Dictionary:
					for index in range(2):
						if ground_row.get("position") is Array and ground_row.position.size()==2 \
								and ground_row.position[index] is float \
								and ground_row.position[index]==floor(ground_row.position[index]):
							ground_row.position[index]=int(ground_row.position[index])
					_normalize_item_instance_json_numbers(ground_row.get("item"))


func _normalize_world_item_json_numbers(item_state_row:Variant)->void:
	# Same JSON transport boundary as the party rows above, now for the canonical
	# world item authority. Only the checked integer fields are restored.
	if not item_state_row is Dictionary:return
	_normalize_integer_field(item_state_row,"schema_version")
	for row in item_state_row.get("inventory_rows",[]):
		if not row is Dictionary:continue
		var inventory:Variant=row.get("inventory")
		if not inventory is Dictionary:continue
		_normalize_integer_field(inventory,"schema_version")
		_normalize_integer_field(inventory,"backpack_capacity")
		for item_row in inventory.get("backpack",[]):_normalize_item_instance_json_numbers(item_row)
	for row in item_state_row.get("ammo_pool_rows",[]):
		if not row is Dictionary:continue
		var ammo_pool:Variant=row.get("ammo_pool")
		if not ammo_pool is Dictionary:continue
		_normalize_integer_field(ammo_pool,"schema_version")
		for ammo_row in ammo_pool.get("ammo_pools",[]):
			if ammo_row is Dictionary:_normalize_integer_field(ammo_row,"amount")
	for row in item_state_row.get("weapon_runtime_rows",[]):
		if row is Dictionary:_normalize_integer_field(row,"schema_version")
	var ground:Variant=item_state_row.get("ground_items")
	if ground is Dictionary:
		_normalize_integer_field(ground,"schema_version")
		for ground_row in ground.get("rows",[]):
			if not ground_row is Dictionary:continue
			for index in range(2):
				if ground_row.get("position") is Array and ground_row.position.size()==2 \
						and ground_row.position[index] is float \
						and ground_row.position[index]==floor(ground_row.position[index]):
					ground_row.position[index]=int(ground_row.position[index])
			_normalize_item_instance_json_numbers(ground_row.get("item"))


func _normalize_integer_field(row:Dictionary,key:String)->void:
	if row.get(key) is float and row[key]==floor(row[key]):row[key]=int(row[key])


func _normalize_item_instance_json_numbers(item_row:Variant)->void:
	if not item_row is Dictionary:return
	for key in ["schema_version","quantity"]:
		if item_row.get(key) is float and item_row[key]==floor(item_row[key]):
			item_row[key]=int(item_row[key])

func _journal_wire_error(journal: Array) -> String:
	for row in journal:
		if not row is Dictionary: return "invalid_party_journal"
		var keys: Array = row.keys(); keys.sort()
		match str(row.get("kind", "")):
			"opening":
				if keys != ["kind", "operation"] \
						or not row.get("operation") is Dictionary:
					return "invalid_opening_journal"
				var opening_keys: Array = row.operation.keys(); opening_keys.sort()
				if opening_keys != ["action"] \
						or row.operation.get("action") not in ["GIVE_POTION", "PASS"]:
					return "invalid_opening_journal"
			"growth":
				if keys!=["kind","operation"] or not row.get("operation") is Dictionary:
					return "invalid_growth_journal"
				var growth_keys:Array=row.operation.keys();growth_keys.sort()
				if growth_keys!=["action","mutation_id","slot_index","target_id"] \
						or not row.operation.action is String \
						or str(row.operation.action) not in ["SPEND_STAT_POINT",
							"SPEND_SPECIES_POINT","SWAP_MUTATION"] \
						or not row.operation.target_id is String \
						or not row.operation.mutation_id is String \
						or not _integer(row.operation.slot_index):
					return "invalid_growth_journal"
				var growth_action:=str(row.operation.action)
				if growth_action=="SPEND_STAT_POINT" \
						and (str(row.operation.target_id) not in GrowthBuildRegistryScript.STAT_IDS \
						or int(row.operation.slot_index)!=-1 \
						or not str(row.operation.mutation_id).is_empty()):
					return "invalid_growth_journal"
				if growth_action=="SPEND_SPECIES_POINT" \
						and (str(row.operation.target_id).is_empty() \
						or int(row.operation.slot_index)!=-1 \
						or not str(row.operation.mutation_id).is_empty()):
					return "invalid_growth_journal"
				if growth_action=="SWAP_MUTATION" \
						and (not str(row.operation.target_id).is_empty() \
						or int(row.operation.slot_index)<0 \
						or int(row.operation.slot_index)>=GrowthBuildRegistryScript.MUTATION_SLOT_COUNT \
						or (not str(row.operation.mutation_id).is_empty() \
						and str(row.operation.mutation_id) not in GrowthBuildRegistryScript.mutation_ids())):
					return "invalid_growth_journal"
			"item":
				if keys!=["kind","operation"] or not row.get("operation") is Dictionary:
					return "invalid_item_journal"
				var item_keys:Array=row.operation.keys();item_keys.sort()
				if item_keys!=["action","instance_id","slot"] \
						or not row.operation.action is String \
					or str(row.operation.action) not in ["PICKUP","EQUIP","UNEQUIP","DROP","DISCARD","USE"] \
						or not row.operation.instance_id is String or not row.operation.slot is String:
					return "invalid_item_journal"
			"equipment":
				if keys!=["kind","operation"] or not row.get("operation") is Dictionary:
					return "invalid_equipment_journal"
				var equipment_keys:Array=row.operation.keys();equipment_keys.sort()
				if equipment_keys!=["action","weapon_id"] \
						or row.operation.action not in ["EQUIP","RELOAD"] \
						or not WeaponRegistryScript.has(str(row.operation.weapon_id)):
					return "invalid_equipment_journal"
			"progression":
				if keys != ["kind","operation"] or not row.get("operation") is Dictionary:
					return "invalid_progression_journal"
				var operation_keys:Array=row.operation.keys();operation_keys.sort()
				var legacy_operation:bool=operation_keys==["action","skill_id"] \
					and row.operation.action=="SET_TRAINING_FOCUS"
				var mode_operation:bool=operation_keys==["action","mode","skill_id"] \
					and row.operation.action=="SET_TRAINING_MODE" \
					and row.operation.mode in ProgressionRegistryScript.TRAINING_MODES
				if (not legacy_operation and not mode_operation) \
						or row.operation.skill_id not in ProgressionRegistryScript.SKILL_IDS:
					return "invalid_progression_journal"
			"exploration":
				if keys != ["command", "kind"] or not row.get("command") is Dictionary: return "invalid_exploration_journal"
				var command_keys: Array = row.command.keys(); command_keys.sort()
				if command_keys != ["actor_id", "position", "power", "type", "wait_duration_time_units"] \
						or not CommandScript.command_wire_error(row.command).is_empty() \
						or int(row.command.type) not in [int(CommandScript.Type.WAIT), int(CommandScript.Type.MOVE)]:
					return "invalid_exploration_journal"
			"deployment":
				if keys != ["kind", "request"] or not row.get("request") is Dictionary: return "invalid_deployment_journal"
				var request_keys: Array = row.request.keys(); request_keys.sort()
				if request_keys != ["companion_ids", "preset_id"] or row.request.get("preset_id") not in ["WEDGE", "LINE", "COLUMN"] \
						or not row.request.get("companion_ids") is Array or row.request.companion_ids.size() > 2:
					return "invalid_deployment_journal"
				var previous_id := 0
				for value in row.request.companion_ids:
					if not Int64CodecScript.is_canonical(value): return "invalid_deployment_journal"
					var parsed := Int64CodecScript.parse(value, "deployment companion")
					if parsed <= previous_id: return "invalid_deployment_journal"
					previous_id = parsed
			"roster":
				if keys != ["kind", "operation"] or not row.get("operation") is Dictionary:
					return "invalid_roster_journal"
				var operation_keys: Array = row.operation.keys(); operation_keys.sort()
				if operation_keys != ["action", "entity_id"] \
						or row.operation.get("action") not in ["DISMISS", "RECRUIT",
							"STABILIZE", "OFFER_RECRUIT"] \
						or not Int64CodecScript.is_canonical(row.operation.get("entity_id")) \
						or Int64CodecScript.parse(row.operation.entity_id,"roster member") <= 0:
					return "invalid_roster_journal"
			"npc_assault":
				if keys!=["kind","operation"] or not row.get("operation") is Dictionary:
					return "invalid_npc_assault_journal"
				var assault_keys:Array=row.operation.keys();assault_keys.sort()
				if assault_keys!=["entity_id"] \
						or not Int64CodecScript.is_canonical(row.operation.get("entity_id")) \
						or Int64CodecScript.parse(row.operation.entity_id,"assaulted npc")<=0:
					return "invalid_npc_assault_journal"
			"party_command":
				if keys!=["kind","operation"] or not row.get("operation") is Dictionary:
					return "invalid_party_command_journal"
				var command_keys:Array=row.operation.keys();command_keys.sort()
				if command_keys!=["command_id","target_id"] \
						or row.operation.get("command_id") not in PartyCommandScript.COMMAND_IDS \
						or not Int64CodecScript.is_canonical(row.operation.get("target_id")):
					return "invalid_party_command_journal"
				var command_target:=Int64CodecScript.parse(row.operation.target_id,
					"party command target")
				if (str(row.operation.command_id)=="ATTACK_TARGET" and command_target<=0) \
						or (str(row.operation.command_id)!="ATTACK_TARGET" and command_target!=-1):
					return "invalid_party_command_journal"
			"party_turn":
				if keys != ["kind", "request"]: return "invalid_party_turn_journal"
				var request_error := RequestScript.wire_error(row.get("request"))
				if not request_error.is_empty(): return request_error
			_: return "unknown_party_journal_kind"
	return ""

func _integer(value: Variant) -> bool:
	return value is int or (value is float and value == floor(value))

func _canonical_action_copy(action: Variant):
	if action == null or not action is PartyActionCommand:
		return null
	return ActionScript.from_dict(action.to_dict())

func _make_action(actor_id: int, action_type: String, destination: Array, target_id: int):
	match action_type:
		"HOLD": return ActionScript.hold(actor_id)
		"MOVE":
			if destination.size() != 2 or not destination[0] is int or not destination[1] is int:
				return null
			return ActionScript.move_to(actor_id, Vector2i(int(destination[0]), int(destination[1])))
		"MELEE": return ActionScript.melee(actor_id, target_id)
	return null

func _clear_draft() -> void:
	_protagonist_draft = null; _overrides.clear(); _draft_fingerprint = ""
	_protagonist_placeholder = false


func _pending_turn_request():
	var rows: Array = []
	var ids: Array = _overrides.keys()
	ids.sort()
	for id in ids:
		rows.append({"actor_id":id,"action":_overrides[id]})
	return RequestScript.new(_protagonist_draft, rows)

func _result_dto(result, action: Variant = null, request: Variant = null,
		context: Dictionary = {}) -> Dictionary:
	var ids: Array = []
	for event in result.events:
		ids.append(event.id)
	var dto := {"accepted":result.accepted,"reason":result.reason,
		"consumes_time":result.consumes_time,"step_index":result.processed_step_index,
		"start_time":result.start_time,"end_time":result.end_time,"time_cost":result.time_cost,
		"event_ids":ids,"visual_effects":_visual_effects_from_result(result)}
	return _feedback_dto(dto, action, request, context)


func _rejection_dto(reason: String, action: Variant = null, request: Variant = null,
		context: Dictionary = {}) -> Dictionary:
	return _feedback_dto({"accepted": false, "reason": reason}, action, request, context)


func _feedback_dto(value: Dictionary, action: Variant = null, request: Variant = null,
		context: Dictionary = {}) -> Dictionary:
	var dto := value.duplicate(true)
	var reason := str(dto.get("reason", "invalid_party_action"))
	var details := _reason_details(reason, action, request, context)
	dto["reason"] = reason
	dto["reason_code"] = reason
	dto["reason_details"] = details
	dto["message"] = reason_message(reason, details)
	dto["visual_effect_schema_version"] = PRESENTATION_SCHEMA_VERSION
	if not dto.get("visual_effects") is Array:
		dto["visual_effects"] = []
	return dto.duplicate(true)


func _exploration_context(command) -> Dictionary:
	if command == null:
		return {}
	var action_type := "MOVE" if int(command.type) == int(CommandScript.Type.MOVE) else "HOLD"
	return {"actor_id": int(command.actor_id), "action_type": action_type,
		"destination": [command.position.x, command.position.y] if action_type == "MOVE" else [-1,-1]}


func _run_feature_id_at(position: Vector2i, progress: Dictionary) -> String:
	if bool(progress.get("available", false)):
		var exit_position: Variant = progress.get("exit_position", [])
		if exit_position is Array and exit_position.size() == 2 \
				and position == Vector2i(int(exit_position[0]), int(exit_position[1])):
			return str(progress.get("exit", {}).get("feature_id", ""))
		var entry_position: Variant = progress.get("entry_position", [])
		if entry_position is Array and entry_position.size() == 2 \
				and position == Vector2i(int(entry_position[0]), int(entry_position[1])):
			return "run_entry"
	return VisualTestMapScript.feature_id_at(scenario_id, position, _map_layout)


func _run_is_complete() -> bool:
	var progress := run_progress()
	return bool(progress.get("available", false)) and bool(progress.get("complete", false))


func _position_is_locked_exit(value: Variant) -> bool:
	var progress := run_progress()
	if not bool(progress.get("available", false)) \
			or bool(progress.get("exit", {}).get("open", false)):
		return false
	var parsed := _inspection_position(value)
	var exit_position: Variant = progress.get("exit_position", [])
	return bool(parsed.get("ok", false)) and exit_position is Array \
		and exit_position.size() == 2 and parsed.position == Vector2i(
			int(exit_position[0]), int(exit_position[1]))


func _command_targets_locked_exit(command: Variant) -> bool:
	return command != null and command is SimCommand \
		and int(command.type) == int(CommandScript.Type.MOVE) \
		and _position_is_locked_exit(command.position)


func _position_wire_value(value: Variant) -> Array:
	var parsed := _inspection_position(value)
	return [parsed.position.x, parsed.position.y] if bool(parsed.get("ok", false)) else []


func _clear_run_completion_transients() -> void:
	_deployment_plan.clear()
	_clear_draft()
	if _exploration_route != null: _exploration_route.clear()
	if _auto_explore != null: _auto_explore.clear()


func _inspection_position(value: Variant) -> Dictionary:
	if value is Vector2i:
		return {"ok":true,"position":value}
	if value is Array and value.size() == 2 and value[0] is int and value[1] is int:
		return {"ok":true,"position":Vector2i(int(value[0]),int(value[1]))}
	return {"ok":false,"position":Vector2i(-1,-1)}


func _int_array(values: Array) -> Array:
	var result: Array = []
	for value in values: result.append(int(value))
	return result


func _terrain_label(terrain_id: String) -> String:
	return {"floor":"바닥","stone_floor":"돌바닥","wood_floor":"나무바닥",
		"metal":"금속 바닥","rubble":"잔해","shallow_water":"얕은 물",
		"wall":"벽"}.get(terrain_id,terrain_id)


func _pure_expected_action(entity_id: int) -> Variant:
	if _protagonist_draft == null \
			or _draft_fingerprint != JSON.stringify(sim.snapshot()).sha256_text():
		return null
	var preview: Dictionary = sim.preview_party_turn(_pending_turn_request()).to_dict().duplicate(true)
	for row in preview.get("actor_rows", []):
		if int(row.get("actor_id",-1)) == entity_id:
			return _action_presentation(row)
	return null


func _combat_event_row(event) -> Dictionary:
	var event_type := str(event.type)
	var damage_type := str(event.data.get("damage_type", ""))
	var cause_type := ""
	if int(event.cause_id) > 0:
		var cause = sim.world.event_by_id(int(event.cause_id))
		if cause != null: cause_type = str(cause.type)
	return {"event_id":int(event.id),"type":event_type,
		"step_index":int(event.step_index),"world_time":int(event.world_time),
		"actor_id":int(event.actor_id),"actor_name":_event_entity_name(int(event.actor_id)),
		"target_id":int(event.target_id),"target_name":_event_entity_name(int(event.target_id)),
		"instigator_id":int(event.instigator_id),
		"instigator_name":_event_entity_name(int(event.instigator_id)),
		"position":[event.position.x,event.position.y],"magnitude":int(event.magnitude),
		"damage_type":damage_type,"cause_id":int(event.cause_id),"cause_type":cause_type,
		"category":_event_category(event_type),"tone":_event_tone(event_type),
		"data":event.data.duplicate(true),"message":_event_message(event)}


func _event_entity_name(entity_id: int) -> String:
	return str(sim.world.entities[entity_id].display_name) \
		if entity_id > 0 and sim.world.entities.has(entity_id) else ""


func _event_category(event_type: String) -> String:
	if event_type == "entity.died": return "DEATH"
	if event_type.begins_with("combat."): return "DAMAGE"
	if event_type.begins_with("action.") or event_type == "party.override_committed": return "ACTION"
	if event_type=="party.command_issued":return "COMMAND"
	if event_type.begins_with("encounter.") or event_type == "party.contact_reported" \
			or event_type == "party.deployment_completed" \
			or event_type == "party.member_deployed": return "ENCOUNTER"
	if event_type=="party.npc_assaulted":return "ACTION"
	if event_type.begins_with("party.victory") or event_type.begins_with("party.regroup") \
			or event_type == "party.member_regrouped": return "OUTCOME"
	if event_type.begins_with("environment."): return "ENVIRONMENT"
	return "WORLD"


func _event_tone(event_type: String) -> String:
	if event_type == "entity.died": return "DEFEAT"
	if event_type.begins_with("combat."): return "DANGER"
	if event_type == "party.victory" or event_type.begins_with("party.regroup") \
			or event_type == "party.member_regrouped": return "VICTORY"
	if event_type.begins_with("encounter.") or event_type == "party.contact_reported":
		return "WARNING"
	if event_type=="party.npc_assaulted":return "DANGER"
	if event_type.begins_with("action."): return "ACTION"
	if event_type=="party.command_issued":return "COMMAND"
	return "INFO"


func _reason_details(reason: String, action: Variant, request: Variant,
		context: Dictionary) -> Dictionary:
	if reason == "ok":
		return {}
	var details := context.duplicate(true)
	details["category"] = _reason_category(reason)
	if action is PartyActionCommand:
		details["actor_id"] = int(action.actor_id)
		details["action_type"] = str(action.type)
		details["destination"] = [action.destination.x, action.destination.y]
		details["target_id"] = int(action.target_id)
	var actor_id := int(details.get("actor_id", -1))
	if sim != null and sim.world != null and actor_id > 0:
		if sim.world.entities.has(actor_id):
			var entity = sim.world.entities[actor_id]
			details["actor_name"] = str(entity.display_name)
			details["alive"] = bool(sim.world.occupies_tile(entity.id))
			details["from_position"] = [entity.position.x, entity.position.y]
		var state = sim.world.party_encounter
		var member = state.member(actor_id) if state != null else null
		if member != null:
			details["presence"] = str(member.presence)
			details["busy_until"] = int(member.busy_until)
			details["remaining_time"] = maxi(0, int(member.busy_until) - int(sim.world.world_time))
			details["is_deployed"] = str(member.presence) == "DEPLOYED"
	var destination: Variant = details.get("destination", null)
	if str(details.get("action_type", "")) == "MOVE" and destination is Array \
			and destination.size() == 2 and actor_id > 0 and sim != null \
			and sim.world != null and sim.world.entities.has(actor_id):
		var assessment = sim.assess_move(actor_id, Vector2i(int(destination[0]), int(destination[1])))
		var assessment_dto: Dictionary = assessment.to_dict()
		details["movement_assessment"] = assessment_dto
		details["terrain_id"] = str(assessment_dto.terrain_id)
		details["blocking_entity_ids"] = assessment_dto.blocking_entity_ids.duplicate()
		var blocker_names: Array[String] = []
		for blocker_id in assessment_dto.blocking_entity_ids:
			blocker_names.append(_name(int(blocker_id)))
		details["blocking_entity_names"] = blocker_names
		details["sampled_world_time"] = int(assessment_dto.sampled_world_time)
	if reason == "destination_conflict":
		var conflict := _destination_conflict_details(request)
		for key in conflict:
			details[key] = conflict[key]
	return details.duplicate(true)


func _destination_conflict_details(request: Variant) -> Dictionary:
	if request == null or not request is PartyTurnRequest:
		return {}
	var direct_actions: Array = []
	if request.protagonist_action != null:
		direct_actions.append(request.protagonist_action)
	for row in request.overrides:
		if row is Dictionary and row.get("action") != null:
			direct_actions.append(row.action)
	var grouped: Dictionary = {}
	for action in direct_actions:
		if action == null or str(action.type) != "MOVE":
			continue
		var key := "%d:%d" % [action.destination.x, action.destination.y]
		if not grouped.has(key):
			grouped[key] = []
		grouped[key].append(action)
	var keys: Array = grouped.keys()
	keys.sort()
	for key in keys:
		var contenders: Array = grouped[key]
		if contenders.size() < 2:
			continue
		var ids: Array[int] = []
		var names: Array[String] = []
		for contender in contenders:
			ids.append(int(contender.actor_id))
		ids.sort()
		for id in ids:
			names.append(_name(id))
		var position := str(key).split(":")
		return {"conflict_destination": [int(position[0]), int(position[1])],
			"conflicting_actor_ids": ids, "conflicting_actor_names": names}
	return {}


func _reason_category(reason: String) -> String:
	if reason in ["exit_locked", "run_complete", "run_restart_unavailable",
			"run_restart_not_ready", "run_restart_failed"]:
		return "RUN"
	if reason.begins_with("route_") or reason == "invalid_route_goal":
		return "ROUTE"
	if reason.begins_with("inspect_") or reason.ends_with("_inspection_unavailable") \
			or reason in ["invalid_tile_position","party_member_not_found"]:
		return "INSPECTION"
	if reason.begins_with("move_") or reason == "destination_conflict":
		return "MOVEMENT"
	if reason in ["turn_draft_required", "party_actor_busy", "party_actor_unavailable",
			"override_actor_not_deployed", "override_actor_mismatch", "melee_not_legal"]:
		return "PARTY_ACTION"
	if "deployment" in reason or reason in ["unknown_formation", "invalid_companion_ids",
			"too_many_deployed_party"]:
		return "DEPLOYMENT"
	if "overflow" in reason or reason == "schedule_budget_exceeded":
		return "CAPACITY"
	if "session" in reason or "journal" in reason or "snapshot" in reason:
		return "SESSION"
	return "REQUEST"


func _visual_effects_from_result(result) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if result == null or not bool(result.accepted):
		return rows
	var order := 0
	for event in result.events:
		var event_type := str(event.type)
		if event_type == "action.melee_attack":
			if str(event.data.get("outcome","")) in ["HIT","FINISHER"]:
				var melee_row:=_melee_vfx_row(event,order)
				if not melee_row.is_empty():rows.append(melee_row);order+=1
		elif event_type == "combat.attack_missed":
			var miss_row:=_visual_effect_row(event,"MISS","miss",order,
				"physical",0,"빗나감")
			# Result leaves use actor_id=-1. Recover the canonical action cause and
			# freeze its historical pair so refresh timing/occupancy cannot erase the
			# attacker's presentation-only whole-character bump.
			var attack=sim.world.event_by_id(int(event.cause_id)) if sim!=null \
				and sim.world!=null else null
			if attack!=null and str(attack.type)=="action.melee_attack":
				var history:Dictionary=sim.world._entity_position_at_event(
					int(attack.actor_id),int(attack.id))
				if bool(history.get("ok",false)):
					var attacker_position:Vector2i=history.position
					var target_position:Vector2i=attack.position
					miss_row["actor_id"]=int(attack.actor_id)
					miss_row["target_id"]=int(attack.target_id)
					miss_row["attacker_grid_pos"]=[attacker_position.x,attacker_position.y]
					miss_row["target_grid_pos"]=[target_position.x,target_position.y]
			rows.append(miss_row)
			order += 1
		elif event_type.begins_with("combat.") and event_type.ends_with("_damage"):
			var damage_type := str(event.data.get("damage_type", "physical"))
			var cause=sim.world.event_by_id(int(event.cause_id)) if sim!=null \
				and sim.world!=null else null
			if cause==null or str(cause.type)!="action.melee_attack":
				rows.append(_visual_effect_row(event, "HIT_FLASH", "hit_flash", order,
					damage_type, int(event.magnitude), ""))
				order += 1
			rows.append(_visual_effect_row(event, "FLOATING_AMOUNT", "floating_amount", order,
				damage_type, int(event.magnitude), "-%d" % int(event.magnitude)))
			order += 1
		elif event_type=="entity.died" and sim!=null and sim.world!=null \
				and sim.world.party_encounter!=null \
				and int(event.target_id) in sim.world.party_encounter.enemy_ids:
			# Keep death as a short-lived presentation event, but carry the defeated
			# monster's own glyph instead of leaving an X-shaped corpse marker.
			rows.append(_visual_effect_row(event,"DEATH","death",order,
				"physical",0,_death_burst_glyph(int(event.target_id))))
			order+=1
		elif event_type == "health.restored":
			rows.append(_visual_effect_row(event,"FLOATING_AMOUNT","heal",order,
				"healing",int(event.magnitude),"+%d" % int(event.magnitude)))
			order += 1
	return rows.duplicate(true)


func _death_burst_glyph(entity_id:int)->String:
	if sim==null or sim.world==null:return "*"
	var entity=sim.world.entities.get(entity_id)
	if entity==null:return "*"
	var identity:=AsciiStyleScript.monster_identity_spec({
		"species_id":str(entity.species_id),"species_name":str(entity.display_name)})
	var glyph:=str(identity.get("glyph","*"))
	return glyph if not glyph.is_empty() else "*"


func _melee_vfx_row(event,order:int)->Dictionary:
	if sim==null or sim.world==null or event==null:return {}
	var history:Dictionary=sim.world._entity_position_at_event(int(event.actor_id),int(event.id))
	if not bool(history.get("ok",false)):return {}
	var attacker:Vector2i=history.position
	var target:Vector2i=event.position
	var delta:=target-attacker
	if attacker==target or maxi(absi(delta.x),absi(delta.y))!=1:return {}
	return {"effect_id":"%d:melee_vfx"%int(event.id),"event_id":int(event.id),
		"order":order,"kind":"MELEE_VFX","source_event_type":str(event.type),
		"step_index":int(event.step_index),"world_time":int(event.world_time),
		"actor_id":int(event.actor_id),"target_id":int(event.target_id),
		"instigator_id":int(event.instigator_id),"cause_id":int(event.cause_id),
		"world_position":[target.x,target.y],"magnitude":int(event.magnitude),"text":"",
		"attacker_grid_pos":[attacker.x,attacker.y],
		"target_grid_pos":[target.x,target.y]}.duplicate(true)


func _visual_effect_row(event, kind: String, suffix: String, order: int,
		damage_type: String, magnitude: int, text: String) -> Dictionary:
	var attack_form:="SLASH"
	if event.type=="action.melee_attack" and sim!=null and sim.world!=null \
			and sim.world.party_encounter!=null \
			and event.actor_id==sim.world.party_encounter.protagonist_id:
		var weapon=WeaponRegistryScript.definition(ItemOperationsScript.equipped_weapon_id(
			sim.world,sim.world.party_encounter.protagonist_id))
		if weapon!=null:attack_form=str(weapon.attack_form)
	return {"effect_id":"%d:%s" % [int(event.id),suffix], "event_id":int(event.id),
		"order":order, "kind":kind, "source_event_type":str(event.type),
		"step_index":int(event.step_index), "world_time":int(event.world_time),
		"actor_id":int(event.actor_id), "target_id":int(event.target_id),
		"instigator_id":int(event.instigator_id), "cause_id":int(event.cause_id),
		"world_position":[event.position.x,event.position.y], "damage_type":damage_type,
		"attack_form":attack_form,
		"magnitude":magnitude, "text":text}.duplicate(true)


func _actor_row_presentation(rows: Variant, actor_id: int) -> Variant:
	if not rows is Array: return null
	for row in rows:
		if row is Dictionary and int(row.get("actor_id", -1)) == actor_id:
			return _action_presentation(row)
	return null

func _action_presentation(row: Variant) -> Variant:
	if not row is Dictionary or not row.get("action") is Dictionary:
		return null
	var action: Dictionary = row.action
	var source := str(row.get("source", "SUGGESTED"))
	var source_label: String = {"DIRECT":"직접 예정", "OVERRIDE":"개별 덮어쓰기", "SUGGESTED":"자동 제안"}.get(source, "자동 제안")
	var source_color: String = {"DIRECT":"#ffd467", "OVERRIDE":"#ff9f68", "SUGGESTED":"#75c8ff"}.get(source, "#75c8ff")
	var action_type := str(action.get("type", "HOLD"))
	var target_id := Int64CodecScript.parse(action.get("target_id", "-1"), "presentation target")
	var destination: Array = action.get("destination", [-1,-1]).duplicate(true)
	var action_text := "방어"
	var target_name := ""
	var actor_id := int(row.get("actor_id", -1))
	var target_position := [-1, -1]
	var guard_percent:=25
	if sim!=null and sim.world!=null and sim.world.party_encounter!=null \
			and actor_id==sim.world.party_encounter.protagonist_id:
		guard_percent=int(ProgressionRegistryScript.guard_reduction_milli(
			sim.world.party_encounter.protagonist_progression.rank("GUARD"))/10)
	var reason := "200 시간 동안 물리 피해를 %d%% 줄이는 방어 자세를 취합니다."%guard_percent
	var attack_preview = null
	if action_type == "MOVE": action_text = "이동 (%d,%d)" % [int(destination[0]), int(destination[1])]
	elif action_type == "MELEE":
		target_name = _name(target_id)
		action_text = "%s 공격" % target_name
		target_position = [sim.world.entities[target_id].position.x, sim.world.entities[target_id].position.y] \
			if sim.world.entities.has(target_id) else [-1, -1]
		var assessment:Variant=row.get("combat_assessment",null)
		if assessment is Dictionary:
			attack_preview = {"schema_version":1,
				"hit_chance_percent":int((int(assessment.get("hit_chance_milli",0))+5)/10),
				"damage_on_hit":int(assessment.get("normal_final_damage",0)),
				"bleed_chance_percent":int((int(assessment.get("bleed_chance_milli",0))+5)/10),
				"target_guarded":bool(assessment.get("guarded",false)),
				"guard_reduction":int(assessment.get("guard_reduction",0)),
				"weapon_id":str(assessment.get("weapon_id","")),
				"attack_form":str(assessment.get("attack_form","SLASH")),
				"attack_time":int(assessment.get("attack_time",100)),
				"range_max":int(assessment.get("range_max",1)),
				"trait_id":str(assessment.get("trait_id","NONE")),
				"secondary_damage_milli":int(assessment.get("secondary_damage_milli",0)),
				"stun_chance_percent":int((int(assessment.get("stun_chance_milli",0))+5)/10)}
	if action_type == "MOVE":
		reason = "목표에 접근할 길을 골랐습니다." if source == "SUGGESTED" else "선택한 칸으로 이동합니다."
	elif action_type == "MELEE":
		var equipment:=protagonist_equipment() if actor_id==sim.world.party_encounter.protagonist_id else {}
		reason = "%s · 사거리 %d · 공격시간 %d. 명중 판정 뒤 피해량은 고정됩니다."%[
			str(equipment.get("weapon_label","무기")),int(equipment.get("range_max",1)),
			int(equipment.get("attack_time",100))] if not equipment.is_empty() \
			else "인접한 적을 공격합니다. 명중 판정 뒤 피해량은 고정됩니다."
	elif source == "SUGGESTED":
		reason = "위험과 거리를 보고 방어 자세를 취합니다."
	if source == "OVERRIDE": reason = "자동 제안 대신 개별 지시를 따릅니다."
	var resolution_note := str(row.get("resolution_note", ""))
	if resolution_note == "destination_conflict_suggested_hold":
		reason = "이동 경로가 충돌해 이번 턴에는 자리를 지킵니다."
	var automatic_suggestion = null
	if row.get("suggestion") is Dictionary:
		var suggested: Dictionary = row.suggestion
		var suggested_type := str(suggested.get("type", "HOLD"))
		var suggested_destination: Array = suggested.get("destination", [-1, -1]).duplicate(true)
		var suggested_target := Int64CodecScript.parse(suggested.get("target_id", "-1"), "suggestion target")
		automatic_suggestion = {"type": suggested_type,
			"type_label": {"HOLD":"방어", "MOVE":"이동", "MELEE":"공격"}.get(suggested_type, "방어"),
			"destination": suggested_destination, "target_id": suggested_target,
			"target_name": _name(suggested_target) if suggested_target > 0 else ""}
	if source != "OVERRIDE": automatic_suggestion = null
	return {"source": source, "source_label": source_label, "source_color": source_color,
		"type": action_type, "type_label": {"HOLD":"방어", "MOVE":"이동", "MELEE":"공격"}.get(action_type, "방어"),
		"actor_id": actor_id, "destination": destination, "target_id": target_id,
		"target_name": target_name, "target_position": target_position, "reason": reason,
		"text": "%s · %s" % [source_label, action_text], "overridden": bool(row.get("overridden", false)),
		"automatic_suggestion": automatic_suggestion,
		"attack_preview":attack_preview,
		"resolution_note": resolution_note}.duplicate(true)

func _emotion_presentation(member, entity) -> Dictionary:
	var health_percent: int = int(entity.health * 100 / maxi(1, entity.max_health))
	var emotionality := 500
	var conscientiousness := 500
	if member.personality_profile != null:
		emotionality = member.personality_profile.value("E")
		conscientiousness = member.personality_profile.value("C")
	var label := "침착"; var icon := "●"; var reason := "건강과 긴장이 안정적입니다."
	if health_percent <= 30 or member.stress >= 750:
		if emotionality <= 400 and conscientiousness >= 450:
			label = "용기를 냄"; icon = "◆"; reason = "생존 위협 속에서 대담한 본성이 드러납니다."
		else:
			label = "겁먹음"; icon = "!"; reason = "낮은 체력과 높은 긴장으로 생존 본능이 앞섭니다."
	elif member.stress >= 350 or health_percent <= 60:
		label = "긴장"; icon = "▲"; reason = "위험이 커져 경계하고 있습니다."
	return {"icon":icon, "label":label, "reason":reason,
		"health_percent":health_percent}.duplicate(true)

func reason_message(reason: String, details: Dictionary = {}) -> String:
	if reason == "party_actor_busy":
		var remaining := int(details.get("remaining_time", 0))
		return "선택한 파티원은 아직 행동 중입니다. (%d 시간 남음)" % remaining \
			if remaining > 0 else "선택한 파티원은 아직 행동 중입니다."
	if reason == "party_actor_unavailable":
		if not bool(details.get("alive", true)) or str(details.get("presence", "")) == "DEFEATED":
			return "선택한 파티원은 쓰러져 행동할 수 없습니다."
		return "선택한 파티원은 지금 행동할 수 없습니다."
	var mapped: Dictionary = {
			"ok":"준비되었습니다.", "deployment_preview_required":"먼저 대형을 선택하세요.",
			"exit_locked":"적을 쓰러뜨리면 출구가 열립니다.",
			"run_complete":"이미 원정을 완료했습니다. 같은 원정을 다시 시작할 수 있습니다.",
			"run_restart_unavailable":"이 시나리오는 다시 시작할 원정이 없습니다.",
			"run_restart_not_ready":"원정을 완료하거나 실패한 뒤 다시 시작할 수 있습니다.",
			"run_restart_failed":"같은 원정을 다시 준비하지 못했습니다.",
			"personality_seed_unchanged":"새 성격을 만들려면 다른 성격 시드가 필요합니다.",
			"inventory_backpack_full":"가방 12칸이 가득 찼습니다.",
			"equipment_slot_occupied":"그 장비 칸은 이미 사용 중입니다. 먼저 장비를 해제하세요.",
			"two_handed_offhand_conflict":"활과 쇠뇌는 양손을 사용해 방패와 함께 장착할 수 없습니다.",
			"item_requirements_not_met":"필요 능력치가 부족해 장착할 수 없습니다. 아이템 행의 STR/DEX/INT 요구치를 확인하세요.",
			"equipped_item_locked":"장착 중인 아이템은 먼저 해제해야 합니다.",
			"reload_required":"쇠뇌가 장전되지 않았습니다. 전투 조작의 [RELOAD]를 누르세요.",
			"ammo_empty":"필요한 화살이나 볼트가 없습니다.",
			"ground_item_missing":"바닥에 더 이상 그 아이템이 없습니다.",
			"ground_item_not_at_actor":"아이템이 있는 칸으로 이동해야 주울 수 있습니다.",
			"item_use_unimplemented":"이 아이템의 사용 효과는 아직 준비되지 않았습니다.",
			"item_heal_not_needed":"체력이 가득 차 있어 회복 물약을 아꼈습니다.",
			"item_user_unavailable":"쓰러진 상태에서는 물약을 사용할 수 없습니다.",
			"item_operation_unsafe_phase":"안전한 탐험 상태에서만 장비와 가방을 정리할 수 있습니다.",
		"deployment_phase_required":"지금은 배치할 수 없습니다.", "unknown_formation":"알 수 없는 대형입니다.",
		"invalid_companion_ids":"동료 선택이 올바르지 않습니다.", "too_many_deployed_party":"한 전투에 배치할 수 있는 파티원 수를 넘었습니다.",
		"deployment_space_unavailable":"동료가 설 수 있는 빈 칸이 부족합니다.",
		"stale_deployment_plan":"세계가 바뀌었습니다. 대형을 다시 선택하세요.",
		"deployment_plan_mismatch":"변경되거나 손상된 배치 계획은 확정할 수 없습니다.",
		"turn_draft_required":"동료를 지시하려면 먼저 주인공 행동을 선택하세요.",
		"stale_turn_draft":"세계가 바뀌어 행동을 다시 지정해야 합니다.",
		"party_turn_phase_required":"지금은 파티 턴을 확정할 수 없습니다.",
		"party_command_phase_required":"전투 중 행동 경계에서만 파티 명령을 바꿀 수 있습니다.",
		"unknown_party_command":"지원하지 않는 파티 명령입니다.",
		"party_command_target_invalid":"공격 대상으로 지정할 수 있는 활동 중인 적이 아닙니다.",
		"party_command_commit_failed":"파티 명령을 적용하지 못해 이전 상태로 돌아갔습니다.",
		"protagonist_action_required":"주인공 행동이 필요합니다.",
		"override_actor_not_deployed":"이번 전투에 배치되지 않은 예비 동료입니다.",
		"override_actor_mismatch":"선택한 동료와 지시 대상이 다릅니다.",
		"duplicate_or_unsorted_override":"동료별 지시는 한 번씩만 지정할 수 있습니다.",
		"melee_not_legal":"인접한 살아 있는 적만 공격할 수 있습니다.",
		"move_requires_actor":"이동할 파티원을 먼저 선택하세요.",
		"actor_not_found":"선택한 파티원을 찾을 수 없습니다.",
		"actor_dead":"쓰러진 파티원은 이동할 수 없습니다.",
		"move_not_adjacent":"인접한 8방향 한 칸으로만 이동할 수 있습니다.",
		"move_out_of_bounds":"지도 밖으로 이동할 수 없습니다.",
		"move_destination_occupied":"다른 인물이 그 칸을 점유하고 있습니다.",
		"move_terrain_blocked":"벽 또는 통과할 수 없는 지형입니다.",
		"move_diagonal_flank_blocked":"벽 모서리를 가로질러 대각선으로 이동할 수 없습니다.",
		"move_diagonal_flank_occupied":"다른 인물이 막은 모서리를 가로질러 대각선으로 이동할 수 없습니다.",
		"destination_conflict":"두 개 이상의 직접 이동 지시가 같은 칸을 요구합니다.",
		"party_plan_mismatch":"변경되거나 손상된 파티 계획은 확정할 수 없습니다.",
		"stale_party_plan":"세계가 바뀌어 턴을 다시 계획해야 합니다.",
		"regroup_not_ready":"아직 재집결할 수 없습니다.",
		"protagonist_dead":"주인공이 쓰러져 재집결할 수 없습니다.",
		"exploration_phase_required":"지금은 탐험 이동을 할 수 없습니다.",
		"protagonist_command_required":"주인공만 탐험 이동을 지시할 수 있습니다.",
		"invalid_exploration_direction":"올바른 방향을 선택하세요.",
		"invalid_exploration_action":"탐험에서는 이동하거나 대기할 수 있습니다.",
		"invalid_route_goal":"목적지 좌표가 올바르지 않습니다.",
		"route_preview_required":"먼저 먼 목적지의 경로를 확인하세요.",
		"route_not_active":"진행 중인 장거리 이동이 없습니다.",
		"route_already_active":"이미 장거리 이동을 진행하고 있습니다.",
		"route_plan_mismatch":"변경되거나 손상된 경로 계획은 시작할 수 없습니다.",
		"route_stale":"세계가 바뀌어 장거리 이동을 멈췄습니다. 경로를 다시 확인하세요.",
		"route_exploration_phase_required":"전투나 조우 중에는 장거리 이동을 할 수 없습니다.",
		"route_goal_out_of_bounds":"지도 밖을 장거리 목적지로 선택할 수 없습니다.",
		"route_actor_dead":"주인공이 쓰러져 장거리 이동을 계속할 수 없습니다.",
		"route_already_at_goal":"이미 선택한 목적지에 있습니다.",
		"route_unavailable":"목적지까지 안전하게 이어지는 경로가 없습니다.",
		"route_destination_unavailable":"경로의 다음 칸을 확인할 수 없어 이동을 멈췄습니다.",
		"route_path_changed":"지형이나 장애물이 바뀌어 장거리 이동을 멈췄습니다.",
		"route_position_changed":"현재 위치가 계획과 달라 장거리 이동을 멈췄습니다.",
		"route_party_changed":"이동 중인 파티 구성이 바뀌어 장거리 이동을 멈췄습니다.",
		"route_hazard_increased":"미리 본 경로보다 위험이 커져 이동을 멈췄습니다.",
		"route_step_rejected":"다음 한 칸을 이동할 수 없어 장거리 이동을 멈췄습니다.",
		"route_contact":"적과 조우해 장거리 이동을 즉시 멈췄습니다.",
		"route_party_defeated":"파티가 쓰러져 장거리 이동을 즉시 멈췄습니다.",
		"route_completed":"목적지에 도착했습니다.",
		"route_cancelled":"장거리 이동을 취소했습니다.",
		"invalid_tile_position":"확인할 타일 좌표가 올바르지 않습니다.",
		"inspect_tile_out_of_bounds":"지도 밖의 타일은 확인할 수 없습니다.",
		"inspect_viewer_not_found":"타일 위험을 판단할 인물을 찾을 수 없습니다.",
		"inspect_viewer_dead":"쓰러진 인물의 기준으로 타일 위험을 판단할 수 없습니다.",
		"tile_inspection_unavailable":"현재 타일 정보를 확인할 수 없습니다.",
		"party_member_not_found":"선택한 파티원의 상세 정보를 찾을 수 없습니다.",
		"party_roster_unsafe_phase":"지금은 파티 편성을 바꿀 수 없습니다.",
		"protagonist_dismiss_forbidden":"주인공은 추방할 수 없습니다.",
		"companion_not_active":"현재 파티에 없는 동료입니다.",
		"companion_not_recruitable":"영입 후보가 아니거나 이미 떠난 인물입니다.",
		"companion_unavailable":"현재 영입하거나 추방할 수 없는 동료입니다.",
		"party_full":"파티가 가득 찼습니다.",
		"rescue_candidate_not_recruitable":"도울 수 있는 비적대 영입 후보가 아닙니다.",
		"rescue_candidate_unavailable":"이 인물은 현재 구조할 수 없는 상태입니다.",
		"rescue_candidate_too_far":"쓰러진 인물 옆으로 이동해야 안정화할 수 있습니다.",
		"rescue_already_completed":"이미 상처를 안정화했습니다.",
		"rescue_stabilization_failed":"안정화가 취소되어 이전 상태로 돌아갔습니다.",
		"recruitment_requires_rescue":"먼저 쓰러진 인물을 도와 안정화해야 합니다.",
		"recruitment_candidate_too_far":"영입을 제안하려면 그 인물 곁에 있어야 합니다.",
		"recruitment_offer_required":"구조한 인물에게는 수락 가능성을 확인한 뒤 영입을 제안하세요.",
		"recruitment_already_resolved":"이 영입 제안의 답은 이미 정해졌습니다.",
		"recruitment_resolution_failed":"영입 제안이 취소되어 이전 상태로 돌아갔습니다.",
		"npc_not_attackable":"이 인물은 공격 대상으로 지정할 수 없습니다.",
		"npc_already_hostile":"이미 적대 중인 인물입니다.",
		"npc_attack_target_unavailable":"쓰러졌거나 행동할 수 없는 인물은 지금 공격할 수 없습니다.",
		"npc_attack_target_too_far":"공격하려면 그 인물 바로 옆에 있어야 합니다.",
		"npc_attack_unsafe_phase":"다른 조우가 진행 중이라 이 인물을 공격할 수 없습니다.",
		"npc_attack_after_victory":"이번 층의 전투가 끝난 뒤에는 중립 인물을 공격할 수 없습니다.",
		"npc_assault_failed":"적대 전환이 취소되어 이전 상태로 돌아갔습니다.",
		"invalid_roster_operation":"지원하지 않는 편성 변경입니다.",
		"party_roster_change_failed":"편성 변경이 취소되어 이전 상태로 돌아갔습니다.",
		"invalid_party_action":"지원하지 않는 행동입니다.",
		"invalid_party_destination":"이동 위치가 올바르지 않습니다.",
		"melee_target_required":"공격할 적을 선택하세요.",
		"move_destination_required":"이동할 칸을 선택하세요.",
		"party_target_forbidden":"이 행동에는 공격 대상을 지정할 수 없습니다.",
		"party_destination_forbidden":"이 행동에는 이동 칸을 지정할 수 없습니다.",
		"party_turn_failed":"파티 턴이 취소되어 이전 상태로 돌아갔습니다.",
		"actor_tick_failed":"세계 처리에 실패해 이전 상태로 돌아갔습니다.",
		"party_schedule_mismatch":"세계 처리 순서가 바뀌어 파티 턴을 취소했습니다.",
		"party_turn_semantic_failure":"파티 턴을 안전하게 완료하지 못해 이전 상태로 돌아갔습니다.",
		"party_snapshot_unavailable":"안전한 복원 지점을 만들 수 없어 행동을 취소했습니다.",
		"schedule_budget_exceeded":"한 번에 처리할 세계 변화가 너무 많습니다. 더 짧은 행동을 선택하세요.",
		"step_index_overflow":"더 이상 턴 기록을 추가할 수 없습니다.",
		"time_overflow":"더 이상 세계 시간을 진행할 수 없습니다.",
		"event_id_overflow":"더 이상 사건 기록을 추가할 수 없습니다.",
		"party_journal_replay_failed":"저장 기록을 재생할 수 없습니다.",
		"party_journal_snapshot_mismatch":"저장 기록과 스냅샷이 일치하지 않습니다.",
		"opening_event_unavailable":"이 원정에는 첫 고정 이벤트가 없습니다.",
		"opening_choice_already_committed":"이미 선택을 마쳤습니다.",
		"unknown_opening_choice":"알 수 없는 선택입니다.",
		"opening_actor_missing":"부상당한 여행자를 찾을 수 없습니다.",
		"opening_actor_unavailable":"지금은 여행자와 상호작용할 수 없습니다.",
		"opening_npc_not_adjacent":"여행자에게 인접해야 합니다.",
		"opening_healing_potion_missing":"건넬 회복 물약이 없습니다.",
		"tab_attack_solo_only":"자동 공격은 단독 원정에서만 사용할 수 있습니다.",
		"tab_attack_no_visible_enemy":"시야 안에 공격할 적이 없습니다.",
		"tab_attack_no_path":"적에게 다가갈 수 있는 길이 없습니다.",
		"tab_attack_phase_unavailable":"지금은 자동 공격을 사용할 수 없습니다.",
		"invalid_party_session":"저장 데이터 형식이 올바르지 않습니다.",
		"invalid_party_session_wire":"저장 데이터가 정규 형식이 아닙니다.",
		"session_not_initialized":"세션이 준비되지 않았습니다."
	}
	if mapped.has(reason):
		return str(mapped[reason])
	if reason.begins_with("invalid_") or reason.begins_with("noncanonical_") \
			or reason.begins_with("duplicate_or_unsorted_") or reason.begins_with("unknown_"):
		return "요청 또는 저장 데이터 형식이 올바르지 않습니다."
	if reason.ends_with("_failed") or reason.ends_with("_failure"):
		return "처리에 실패해 이전 상태로 안전하게 돌아갔습니다."
	return "요청을 처리할 수 없습니다. 상태를 확인하고 다시 시도하세요."

func _event_message(event) -> String:
	var actor := _name(event.actor_id); var target := _name(event.target_id)
	match event.type:
		"opening.npc_discovered":return "입구 안쪽으로 피 묻은 발자국이 이어진다."
		"party.npc_assaulted":return "%s을(를) 공격해 적대 관계가 되었다."%target
		"opening.choice_committed":
			return "주인공이 회복 물약을 건네기로 했다." \
				if str(event.data.get("choice",""))=="GAVE_POTION" \
				else "주인공이 여행자를 돕지 않기로 했다."
		"opening.potion_given":return "%s %s 회복 물약을 건넸다."%[_subject(actor),_object(target)]
		"opening.health_restored":return "%s 체력을 %d 회복했다."%[_subject(target),int(event.magnitude)]
		"opening.reencountered":return "던전 안쪽에서 %s 다시 마주쳤다."%_object(target)
		"relationship.gratitude_recorded":return "%s 도움을 고마운 기억으로 남겼다."%_subject(actor)
		"item.picked_up":return "%s %s 주웠다."%[_subject(actor),_object(_item_label_for_event(event))]
		"item.equipped":return "%s %s 장착했다."%[_subject(actor),_object(_item_label_for_event(event))]
		"item.unequipped":return "%s %s 해제했다."%[_subject(actor),_object(_item_label_for_event(event))]
		"item.dropped":return "%s %s 바닥에 내려놓았다."%[_subject(actor),_object(_item_label_for_event(event))]
		"item.discarded":return "%s %s 영구히 폐기했다."%[_subject(actor),_object(_item_label_for_event(event))]
		"item.used":return "%s 회복 물약을 마셨다." % _subject(actor)
		"health.restored":
			return "%s 체력을 %d 회복했다." % [_subject(target),int(event.magnitude)] \
				if str(event.data.get("kind",""))=="POTION" \
				else "%s 안전을 되찾아 체력을 %d 회복했다." % [_subject(target),int(event.magnitude)]
		"progression.enemy_reward":return "%s 처치 · 경험치 +%d · 숙련 풀 +%d" % [
			_subject(target),int(event.data.get("character_xp",0)),int(event.data.get("mastery_pool",0))]
		"growth.enemy_reward":
			var level_up:=_growth_level_up_suffix(event)
			return ("%s 이능 흔적을 얻었다 · %s · 성장 경험치 +%d"%[
				_subject(actor),str(event.data.get("mutation_id","")),int(event.magnitude)] \
				if bool(event.data.get("mutation_acquired",false)) \
				else "%s 성장 경험치 +%d"%[_subject(actor),int(event.magnitude)])+level_up
		"growth.stat_spent":return "%s 기본 능력을 단련했다."%_subject(actor)
		"growth.species_point_spent":return "%s 종족 특성을 발전시켰다."%_subject(actor)
		"growth.mutation_swapped":return "%s 이능 조합을 바꾸었다."%_subject(actor)
		"party.rescue_discovered": return "%s 심하게 다친 채 쓰러져 있다." % _subject(target)
		"party.contact_reported":
			return "%s %s에서 적을 발견해 파티에 경고했다." % [
				_subject(actor),_direction_label(event.data.get("direction",[]))]
		"party.command_issued":
			var command_id:=str(event.data.get("command_id",""))
			return "파티 명령 · %s%s"%[PartyCommandScript.label_ko(command_id),
				" · %s"%_object(target) if command_id=="ATTACK_TARGET" else ""]
		"party.npc_stabilized": return "%s %s 상처를 안정화해 목숨을 구했다." % [_subject(actor),_possessive(target)]
		"party.recruitment_accepted":
			return "%s 영입 제안을 받아들였다. (수락 %d%% · 판정 %d)" % [
				_subject(actor),int((event.data.get("probability_milli",0)+5)/10),
				int(event.data.get("roll_milli",-1))]
		"party.recruitment_refused":
			return "%s 영입 제안을 거절했다. (수락 %d%% · 판정 %d)" % [
				_subject(actor),int((event.data.get("probability_milli",0)+5)/10),
				int(event.data.get("roll_milli",-1))]
		"relationship.aid_recorded": return "%s 구조받은 일을 고마운 기억으로 남겼다." % _subject(actor)
		"encounter.detected": return "고블린과 주인공이 서로를 발견했다." if is_solo_combat() else "고블린과 파티가 서로를 발견했다."
		"encounter.party_ambush": return "주인공이 고블린보다 먼저 기척을 알아챘다." if is_solo_combat() else "파티가 고블린보다 먼저 기척을 알아챘다."
		"encounter.enemy_ambush": return "고블린이 숨어 있던 곳에서 주인공을 덮쳤다." if is_solo_combat() else "고블린이 숨어 있던 곳에서 파티를 덮쳤다."
		"party.member_deployed": return "%s 대형에 자리를 잡았다." % _subject(actor)
		"party.deployment_completed": return "주인공이 전투 태세를 갖췄다." if is_solo_combat() else "파티가 전투 대형을 갖췄다."
		"action.move":
			if _is_enemy_patrol_event(event):
				return "%s 주변을 정찰했다."%_subject(actor)
			return "%s (%d,%d)로 움직였다." % [_subject(actor),event.position.x,event.position.y]
		"action.melee_attack": return "%s %s 공격했다." % [_subject(actor),_object(target)]
		"combat.attack_missed":
			var attacker_id:=int(event.instigator_id)
			if attacker_id<=0 and int(event.cause_id)>0:
				var attack=sim.world.event_by_id(int(event.cause_id))
				if attack!=null and str(attack.type)=="action.melee_attack":
					attacker_id=int(attack.actor_id)
			if attacker_id > 0:
				return "%s 공격이 %s에게 빗나갔다." % [
					_possessive(_name(attacker_id)), target]
			return "%s 향한 공격이 빗나갔다." % _object(target)
		"combat.attack_parried":
			var defender_id := int(event.target_id)
			return "%s 공격을 막아냈다." % _subject(_name(defender_id))
		"party.override_committed": return "%s 지시한 행동으로 계획을 바꿨다." % _topic(actor)
		"party.victory": return "마지막 적이 쓰러졌다. 다시 탐험할 수 있다." if is_solo_combat() else "마지막 적이 쓰러졌다. 파티가 즉시 한곳으로 모이기 시작했다."
		"party.regroup_started": return "주인공이 전투 태세를 풀었다." if is_solo_combat() else "주인공이 동료들을 불러 모았다."
		"party.member_regrouped": return "%s 주인공 곁으로 돌아왔다." % _subject(actor)
		"party.regroup_completed": return "전투가 끝났다. 주인공이 탐험을 다시 시작한다." if is_solo_combat() else "전투가 끝났다. 파티가 자동으로 재집결해 다시 한 무리로 탐험을 시작한다."
		"party.companion_dismissed":
			if str(event.data.get("condition_band",""))=="ENDANGERED":
				return "%s 부상당한 채 버려져 깊은 원한을 품었다."%_subject(target)
			if str(event.data.get("condition_band",""))=="STRAINED":
				return "%s 힘겨운 상태에서 추방되어 원한을 품었다."%_subject(target)
			return "%s 파티에서 영구히 추방되어 원망을 품었다."%_subject(target)
		"party.companion_recruited": return "%s 파티에 새로 합류했다." % _subject(target)
		"party.exile_world_tick":
			if str(event.data.get("behavior",""))=="SELF_TREAT":return "%s 홀로 상처를 돌보며 버텼다."%_subject(target)
			if str(event.data.get("behavior",""))=="RECOVER":return "%s 안전한 곳에서 몸을 추슬렀다."%_subject(target)
			return "%s 살아남기 위해 안전한 곳을 찾았다."%_subject(target)
		"party.exile_died": return "%s 홀로 버티지 못하고 숨졌다."%_subject(target)
		"entity.downed": return "%s 치명상을 입고 쓰러졌다."%_subject(target)
		"entity.recovered": return "%s 다시 일어섰다."%_subject(target)
		"status.applied": return "%s %s 상태에 걸렸다."%[
			_subject(target),_status_label(str(event.data.get("status_id","상태 이상")))]
		"status.expired": return "%s %s 상태에서 회복했다."%[
			_subject(target),_status_label(str(event.data.get("status_id","상태 이상")))]
		"action.hold":
			if _is_enemy_patrol_event(event):return "%s 자리를 지키며 경계했다."%_subject(actor)
			return "%s 방어 자세를 취했다." % _subject(actor)
		"entity.died":
			if int(event.instigator_id) > 0:
				return "%s 공격으로 %s 쓰러졌다." % [
					_possessive(_name(event.instigator_id)),_subject(target)]
			return "환경 영향으로 %s 쓰러졌다." % _subject(target)
	if str(event.type).begins_with("combat.") and str(event.type).ends_with("_damage"):
		if int(event.instigator_id) > 0:
			return "%s 공격으로 %s %d 피해를 입었다." % [
				_possessive(_name(event.instigator_id)),_subject(target),int(event.magnitude)]
		var hazard_label: String = {"fire":"불길","electric":"감전","water":"물",
			"poison":"독","physical":"환경 충격"}.get(str(event.data.get("damage_type","")),"환경 영향")
		return "%s 때문에 %s %d 피해를 입었다." % [hazard_label,_subject(target),int(event.magnitude)]
	# Unknown events have no narrative projection. Important-event facades use
	# an explicit allowlist, so returning an empty string cannot manufacture log
	# noise or expose an unsupported event type.
	return ""


func _item_label_for_event(event)->String:
	var instance_id:=str(event.data.get("instance_id",""))
	if instance_id.is_empty() or sim==null or sim.world==null:return "아이템"
	for inventory in sim.world.item_state.inventory_rows.values():
		var item=inventory.item(instance_id)
		if item!=null:
			var definition=ItemRegistryScript.definition(str(item.definition_id))
			return str(definition.label) if definition!=null else "아이템"
	for ground_row in sim.world.item_state.ground_items.rows:
		if str(ground_row.item.instance_id)==instance_id:
			var definition=ItemRegistryScript.definition(str(ground_row.item.definition_id))
			return str(definition.label) if definition!=null else "아이템"
	for historical in sim.world.events:
		if int(historical.id)>int(event.id):break
		if str(historical.data.get("instance_id",""))!=instance_id:continue
		var definition_id:=str(historical.data.get("definition_id",""))
		var definition=ItemRegistryScript.definition(definition_id)
		if definition!=null:return str(definition.label)
	return "아이템"


func _growth_level_up_suffix(event)->String:
	var current_level:=int(event.data.get("level",1));var previous_level:=1
	for historical in sim.world.events:
		if int(historical.id)>=int(event.id):break
		if str(historical.type)=="growth.enemy_reward" \
				and int(historical.actor_id)==int(event.actor_id):
			previous_level=int(historical.data.get("level",previous_level))
	return " · 레벨 %d 달성!"%current_level if current_level>previous_level else ""


func _direction_label(value:Variant)->String:
	if not value is Array or value.size()!=2:return "알 수 없는 방향"
	var direction:=Vector2i(int(value[0]),int(value[1]))
	return {Vector2i.UP:"북쪽",Vector2i.DOWN:"남쪽",Vector2i.LEFT:"서쪽",
		Vector2i.RIGHT:"동쪽"}.get(direction,"북동쪽" \
		if direction.x>0 and direction.y<0 else ("남동쪽" \
		if direction.x>0 and direction.y>0 else ("북서쪽" \
		if direction.x<0 and direction.y<0 else ("남서쪽" \
		if direction.x<0 and direction.y>0 else "가까운 곳"))))

func _status_label(status_id:String)->String:
	return {"BLEEDING":"출혈","POISONED":"중독","BURNING":"화상",
		"SHOCKED":"감전"}.get(status_id,status_id.to_lower())

func _is_enemy_patrol_event(event)->bool:
	if sim==null or sim.world==null or sim.world.party_encounter==null \
			or int(event.actor_id) not in sim.world.party_encounter.enemy_ids:
		return false
	for candidate in sim.world.events:
		if str(candidate.type) in ["encounter.detected","encounter.party_ambush",
				"encounter.enemy_ambush"]:
			return int(event.id)<int(candidate.id)
	return true

func _name(entity_id: int) -> String: return str(sim.world.entities[entity_id].display_name) if entity_id > 0 and sim.world.entities.has(entity_id) else "대상"
func _position_key(position:Vector2i)->String:return "%d:%d"%[position.x,position.y]
func _actor_facing(entity_id:int,is_enemy:bool)->Vector2i:
	var state=sim.world.party_encounter
	var facing:Vector2i=state.facing if state!=null else Vector2i.RIGHT
	return -facing if is_enemy else facing
func _subject(value:String)->String: return value + ("이" if _has_final(value) else "가")
func _object(value:String)->String: return value + ("을" if _has_final(value) else "를")
func _topic(value:String)->String: return value + ("은" if _has_final(value) else "는")
func _possessive(value:String)->String: return value + ("의")
func _has_final(value:String)->bool:
	if value.is_empty(): return false
	var code := value.unicode_at(value.length()-1); return code >= 0xAC00 and code <= 0xD7A3 and (code-0xAC00)%28 != 0
