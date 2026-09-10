extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Field=preload("res://sim/systems/field_turn_system.gd")
const Action=preload("res://sim/party_action_command.gd")
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL ",message)
func run()->void:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var world=session.sim.world;var party=world.party_encounter
	var hero=world.entities[party.protagonist_id]
	var enemy:int=party.enemy_ids[0]
	var placed:=false
	for direction in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
		var p:Vector2i=hero.position+direction
		if not world.in_bounds(p) or not world._terrain_is_passable(p) or world.blocking_entity_at(p)!=null:continue
		world.entities[enemy].position=p;placed=true;break
	check(placed,"adjacent enemy fixture")
	world._occupancy_index_ready=false
	for id in party.active_party_member_ids:world.entities[id].health=1
	party.enemy_awareness(enemy).awareness_state="HUNTING"
	party.enemy_awareness(enemy).suspicion=1000
	var saw_loss:=false
	for turn in range(30):
		if not session.field_turns_active():break
		var result=Field.step(session.sim,Action.hold(world.party_control_actor_id()))
		check(result.accepted,"incapacitation settles: "+str(result.reason))
		if not result.accepted:break
		var error:String=world.world_state_error()
		check(error.is_empty(),"incapacitation world validates: "+error)
		if not error.is_empty():break
		for event in result.events:
			if event.type in ["entity.downed","entity.died"] and event.target_id in party.active_party_member_ids:
				saw_loss=true
		if party.safe_phase=="PARTY_DEFEATED":break
	check(saw_loss,"fixture exercises party incapacitation")
	print("FIELD LIFECYCLE: ","PASS" if failures.is_empty() else "FAIL", " ",failures)
	quit(0 if failures.is_empty() else 1)
