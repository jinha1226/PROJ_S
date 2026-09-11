extends SceneTree

const Session=preload("res://playtest/party_playtest_session.gd")
const Action=preload("res://sim/party_action_command.gd")
const Vision=preload("res://sim/vision_rules.gd")
const FieldTurns=preload("res://sim/systems/field_turn_system.gd")
var failures:Array[String]=[]

func check(value:bool,label:String)->void:
	if not value:failures.append(label);printerr("FAIL ",label)

func _init()->void:call_deferred("run")

func run()->void:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var world=session.sim.world;var party=world.party_encounter
	var hero_id:=int(world.party_control_actor_id())
	var origin:Vector2i=world.entities[hero_id].position
	var old_facing:Vector2i=party.facing
	check(session.field_turns_active() and session.party_status().exploration_formation=="NONE",
		"fixture uses the affected free-formation field loop")
	var destination:=Vector2i(-1,-1)
	for direction_value in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT]:
		var direction:Vector2i=direction_value
		var candidate:Vector2i=origin+direction
		if session.sim.party_coordinator._action_error(
				Action.move_to(hero_id,candidate)).is_empty():
			destination=candidate;break
	check(destination!=Vector2i(-1,-1),"fixture has a legal non-initial-facing move")
	if destination==Vector2i(-1,-1):
		print("FACING FOV REFRESH: ",failures);quit(1);return
	var expected_facing:Vector2i=destination-origin
	var result:Dictionary=session.commit_field_action(Action.move_to(hero_id,destination))
	check(bool(result.get("accepted",false)),"free-formation move commits")
	check(party.facing==expected_facing and party.facing!=old_facing,
		"successful move updates authoritative facing")
	var debug:Dictionary=session.vision_debug_observation()
	check(debug.get("facing",[])==[expected_facing.x,expected_facing.y],
		"vision observation reports the new facing")
	var profile:Dictionary=Vision.profile_for_entity(world.entities[hero_id])
	var lighting:Dictionary=Vision.lighting_for_world(world,session.scenario_id)
	var differs_from_old:=false;var matches_new:=true;var matches_new_direction:=true
	var directional_lighting:Dictionary={"ambient_level":Vision.DARK_AMBIENT,"sources":[]}
	for row_value in debug.get("cells",[]):
		var row:Dictionary=row_value
		var target:=Vector2i(int(row.position[0]),int(row.position[1]))
		var new_result:Dictionary=Vision.observe(world,destination,target,
			expected_facing,profile,lighting)
		var new_directional:Dictionary=Vision.observe(world,destination,target,
			expected_facing,profile,directional_lighting)
		var old_result:Dictionary=Vision.observe(world,destination,target,
			old_facing,profile,directional_lighting)
		matches_new=matches_new and bool(row.visible)==bool(new_result.visible)
		matches_new_direction=matches_new_direction \
			and bool(row.directional)==bool(new_result.directional)
		differs_from_old=differs_from_old \
			or bool(new_directional.directional)!=bool(old_result.directional)
	check(matches_new,"every debug FOV cell uses the updated facing")
	check(matches_new_direction and differs_from_old,
		"updated facing rotates the directional sight cone")
	var observation:Dictionary=session.observe_party_world()
	check(observation.get("phase",{}).get("facing",[])==[
		expected_facing.x,expected_facing.y],"grid observation carries the new facing")
	var enemy_id:=int(party.enemy_ids[0])
	var attack_facing:Vector2i=FieldTurns.facing_for_action(world,
		Action.melee(hero_id,enemy_id),party.facing)
	var attack_delta:Vector2i=world.entities[enemy_id].position-world.entities[hero_id].position
	var expected_attack_facing:=Vector2i(signi(attack_delta.x),signi(attack_delta.y))
	check(attack_facing==expected_attack_facing,
		"melee and targeted combat actions face their target before FOV refresh")
	var diagonal_facing:=FieldTurns.facing_for_action(world,Action.move_to(hero_id,
		world.entities[hero_id].position+Vector2i(1,1)),party.facing)
	check(diagonal_facing==Vector2i(1,1),
		"diagonal movement preserves both facing axes")
	check(Vision._within_front_cone(Vector2i(1,1),Vector2i(1,0),120) \
		and not Vision._within_front_cone(Vector2i(1,1),Vector2i(-1,-1),120),
		"diagonal sight cone is normalized around its true heading")
	party.facing=Vector2i(1,1)
	check(world.world_state_error().is_empty(),"runtime accepts diagonal party facing")
	print("FACING FOV REFRESH: ",failures)
	quit(0 if failures.is_empty() else 1)
