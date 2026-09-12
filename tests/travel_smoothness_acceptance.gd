extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Perception=preload("res://sim/party_perception_registry.gd")
const Vision=preload("res://sim/vision_rules.gd")
const Motion=preload("res://playtest/ascii_diorama_projection.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const FieldRules=preload("res://sim/field_turn_rules.gd")
const Kernel=preload("res://sim/combat_kernel.gd")
var errors:Array[String]=[]
func check(ok:bool,label:String):
	if not ok:errors.append(label);printerr("FAIL ",label)
func _init():call_deferred("run")
func run():
	check(Sandbox.CONTINUOUS_TRAVEL_CADENCE_MSEC==90,"faster travel cadence")
	check(Sandbox.CONTINUOUS_EXPLORATION_MOTION_MSEC>Sandbox.CONTINUOUS_TRAVEL_CADENCE_MSEC,
		"AUTO motion overlaps the next hop instead of stopping between commits")
	for elapsed in [0,20,40,60,80,100,120,130]:
		var sample:Dictionary=Motion.actor_motion_sample(Vector2.ZERO,Vector2.RIGHT,elapsed,130,true)
		check(is_equal_approx(float(sample.world_position.x),float(elapsed)/130),
			"overlapping AUTO motion remains linear")
	var manual:Dictionary=Motion.actor_motion_sample(Vector2.ZERO,Vector2.RIGHT,25,100)
	check(not is_equal_approx(float(manual.world_position.x),0.25),"manual motion preserves ease")
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	if s.sim==null:check(false,"session bootstrap");quit(1);return
	check(s.turn_intent_overlays().is_empty(),"solo returns no companion predictions")
	var w=s.sim.world;var state=w.party_encounter
	var lighting:Dictionary=Vision.lighting_for_world(w)
	# The live campaign switched to the circular combat kernel in 6ca6859.
	# Compare each integration mode against its actual geometry authority, not
	# the retired directional/light-adjusted predicate for the new field mode.
	for y in range(w.height):
		for x in range(w.width):
			var target:=Vector2i(x,y);var expected:Array=[]
			for id in state.active_party_member_ids:
				var member=state.member(id)
				if member.presence not in ["GROUPED","DEPLOYED"] or not w.can_act(id,w.world_time):continue
				var origin:Vector2i=state.group_anchor if member.presence=="GROUPED" else w.entities[id].position
				if FieldRules.enabled(w):
					if Kernel.sees(origin,target,w.combat_sight_blocked):expected.append(id)
					continue
				var profile:Dictionary=Vision.profile_for_entity(w.entities[id])
				profile.base_sight_range=Perception.sight_range(w,state,id)
				profile.peripheral_range=mini(profile.peripheral_range,profile.base_sight_range)
				profile.circular_sight=true
				if Vision.observe(w,origin,target,state.facing,profile,lighting).visible:expected.append(id)
			var actual:Array=Perception.visible_party_members(w,state,target)
			expected.sort();actual.sort()
			check(actual==expected,"shared visibility unchanged at %s"%target)
	var vision_tests=load("res://tests/test_vision_rules.gd")
	for method in vision_tests.get_script_method_list():
		if not str(method.name).begins_with("test_"):continue
		var test=vision_tests.new();var result=test.call(method.name)
		check(result==true,"vision regression %s: %s"%[method.name,test.errors])
	var visual_tests=load("res://tests/test_party_ascii_visual.gd")
	for name in ["test_actor_motion_eases_draw_only_and_snaps_without_canonical_arm",
		"test_centered_protagonist_keeps_walk_pose_while_camera_tracks_the_step",
		"test_consecutive_actor_and_hero_camera_hops_retarget_current_draw_position",
		"test_hero_camera_settle_is_move_only_centered_pure_and_input_safe"]:
		var test=visual_tests.new();var result=test.call(name)
		check(result==true,"motion regression %s: %s"%[name,test.errors])
	print("TRAVEL SMOOTHNESS: ",errors);quit(0 if errors.is_empty() else 1)
