extends "res://tests/test_case.gd"

const Session=preload("res://playtest/party_playtest_session.gd")
const Command=preload("res://sim/sim_command.gd")
const WorldState=preload("res://sim/world_state.gd")
const VisualMap=preload("res://playtest/party_visual_test_map.gd")


func test_product_patrol_is_tick_driven_visible_deterministic_and_replay_exact()->bool:
	var left=Session.new(44,20260828,"SOLO_COMBAT_V1")
	var right=Session.new(44,20260828,"SOLO_COMBAT_V1")
	var left_state=left.sim.world.party_encounter
	var enemy_id:=int(left_state.enemy_ids[0])
	var initial_position:Vector2i=left.sim.world.entities[enemy_id].position
	var pure_snapshot:Dictionary=left.sim.snapshot()
	for index in range(12):
		left.party_status();left.observe_party_world();left.recent_event_log()
	check_eq(left.sim.snapshot(),pure_snapshot,"refresh surfaces never advance patrol")
	var left_result:Dictionary=left.commit_exploration(
		Command.wait(left_state.protagonist_id))
	var right_result:Dictionary=right.commit_exploration(
		Command.wait(right.sim.world.party_encounter.protagonist_id))
	check(left_result.accepted and right_result.accepted,"successful waits own actor cadence")
	var moved_position:Vector2i=left.sim.world.entities[enemy_id].position
	check(moved_position!=initial_position,"distant product monster scouts one cell")
	check_eq(right.sim.snapshot(),left.sim.snapshot(),"same seed and command produce exact patrol")
	var enemy_leaves:Array=[]
	for event_id in left_result.event_ids:
		var event=left.sim.world.event_by_id(int(event_id))
		if event!=null and int(event.actor_id)==enemy_id \
				and str(event.type) in ["action.move","action.hold","action.melee_attack"]:
			enemy_leaves.append(event)
	check_eq(enemy_leaves.size(),1,"enemy acts at most once in one actor cadence")
	check_eq(str(enemy_leaves[0].type),"action.move","product patrol emits canonical move")
	var observed_position:=Vector2i(-1,-1)
	for cell in left.observe_party_world().cells:
		for actor in cell.actors:
			if int(actor.entity_id)==enemy_id:
				observed_position=Vector2i(int(actor.logical_position[0]),
					int(actor.logical_position[1]))
	check_eq(observed_position,moved_position,"visible monster DTO follows authority")
	var important_text:=JSON.stringify(left.recent_event_log(12))
	check(not "정찰했다" in important_text and not "action.move" in important_text,
		"routine monster scouting stays out of the important-event log")
	check_eq(left.sim.world.world_state_error(),"","patrol world remains canonical")
	var encoded:=left.save_session_json();var restored=Session.new(9,10)
	check(restored.load_session_json(encoded).accepted,"patrol save journal replays")
	check_eq(restored.sim.snapshot(),left.sim.snapshot(),"patrol save restore exact")
	var round_trip=WorldState.from_snapshot(left.sim.snapshot())
	check(round_trip!=null,"patrol snapshot restores directly")
	if round_trip!=null:check_eq(round_trip.snapshot(),left.sim.snapshot(),
		"direct patrol snapshot round trip exact")
	var tampered:Dictionary=left.sim.snapshot().duplicate(true)
	for event in tampered.events:
		if str(event.type)=="action.move" and str(event.actor_id)==str(enemy_id):
			event.data.from_position=[0,0]
			break
	check(not WorldState.snapshot_restore_error(tampered).is_empty(),
		"forged pre-contact patrol history is rejected")
	return finish()


func test_affinity_blocked_hold_reserved_features_and_move_contact_have_one_leaf()->bool:
	var goblin=_corridor_session("goblin",true)
	var goblin_state=goblin.sim.world.party_encounter
	var goblin_enemy:=int(goblin_state.enemy_ids[0])
	var goblin_origin:Vector2i=goblin.sim.world.entities[goblin_enemy].position
	var goblin_result:Dictionary=goblin.commit_exploration(
		Command.wait(goblin_state.protagonist_id))
	check(goblin_result.accepted,"risk-averse patrol cadence accepted")
	check_eq(goblin.sim.world.entities[goblin_enemy].position,goblin_origin,
		"goblin holds rather than entering harmful water")
	var guard_text:=JSON.stringify(goblin.recent_event_log(8))
	check(not "경계했다" in guard_text and not "action.hold" in guard_text,
		"blocked patrol guard stays out of the important-event log")

	var amphibian=_corridor_session("amphibian",true)
	var amphibian_state=amphibian.sim.world.party_encounter
	var amphibian_enemy:=int(amphibian_state.enemy_ids[0])
	var water_cell:Vector2i=amphibian.sim.world.entities[amphibian_enemy].position+Vector2i.RIGHT
	check(amphibian.commit_exploration(
		Command.wait(amphibian_state.protagonist_id)).accepted,
		"water-affine patrol cadence accepted")
	check_eq(amphibian.sim.world.entities[amphibian_enemy].position,water_cell,
		"amphibian affinity permits the same water cell")

	var contact=_corridor_session("goblin",false)
	var contact_state=contact.sim.world.party_encounter
	contact_state.party_detection_radius=0;contact_state.enemy_detection_radius=3
	var contact_enemy:=int(contact_state.enemy_ids[0])
	var health_before:=int(contact.sim.world.entities[contact_state.protagonist_id].health)
	var contact_result:Dictionary=contact.commit_exploration(
		Command.wait(contact_state.protagonist_id))
	check(contact_result.accepted,"patrol contact cadence accepted")
	check_eq(contact.party_status().safe_phase,"CONTACT","move rechecks contact")
	check_eq(contact.party_status().contact_kind,"ENEMY_AMBUSH",
		"fixture crosses only enemy detection radius")
	var contact_enemy_leaves:Array=[]
	for event_id in contact_result.event_ids:
		var event=contact.sim.world.event_by_id(int(event_id))
		if event!=null and int(event.actor_id)==contact_enemy \
				and str(event.type) in ["action.move","action.hold","action.melee_attack"]:
			contact_enemy_leaves.append(str(event.type))
	check_eq(contact_enemy_leaves,["action.move"],
		"moving ambusher never gets a same-tick opening attack")
	check_eq(contact.sim.world.entities[contact_state.protagonist_id].health,health_before,
		"same-tick patrol contact deals no hidden damage")
	check_eq(contact.sim.world.world_state_error(),"","post-patrol contact is canonical")

	var product=Session.new(44,20260828,"SOLO_COMBAT_V1")
	var reservations:Array[Vector2i]=product.sim.world.party_encounter.patrol_reserved_positions
	check(VisualMap.ENTRY_POSITION in reservations \
		and VisualMap.OPEN_DOOR_POSITION in reservations \
		and VisualMap.EXIT_POSITION in reservations,
		"product feature cells are authoritative patrol exclusions")
	var v2_wire:Dictionary=JSON.parse_string(product.save_session_json())
	v2_wire.snapshot.party_encounter.schema_version=2
	v2_wire.snapshot.party_encounter.erase("patrol_reserved_positions")
	var migrated=Session.new(1,2)
	check(migrated.load_session_json(JSON.stringify(v2_wire)).accepted,
		"v2 product save migrates patrol feature reservations")
	check_eq(migrated.sim.snapshot(),product.sim.snapshot(),
		"v2 product migration matches canonical v3 state")
	return finish()


func _corridor_session(species_id:String,water_only:bool):
	var session=Session.new(71,88,"SOLO_COMBAT_V1")
	var world=session.sim.world;var state=world.party_encounter
	state.party_detection_radius=0;state.enemy_detection_radius=0
	var hero_position:=Vector2i(2,3)
	world.entities[state.protagonist_id].position=hero_position;state.group_anchor=hero_position
	var enemy_id:=int(state.enemy_ids[0]);var origin:=Vector2i(6,3)
	world.entities[enemy_id].position=origin
	world.entities[enemy_id].species_id=species_id
	var open_direction:=Vector2i.RIGHT if water_only else Vector2i.LEFT
	for direction in session.sim.movement.MOVE_DIRECTIONS_8:
		var position:Vector2i=origin+direction
		if direction==open_direction:
			world.tile_at(position).terrain="shallow_water" if water_only else "stone_floor"
		else:
			world.tile_at(position).terrain="wall"
	return session
