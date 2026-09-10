extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Rules=preload("res://sim/field_turn_rules.gd")
const Field=preload("res://sim/systems/field_turn_system.gd")
const Action=preload("res://sim/party_action_command.gd")
const Orders=preload("res://sim/party_exception_command.gd")
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL ",message)
func run()->void:
	# Small deterministic authored world; only timing differs between actors.
	var session=Session.new();var world=session.sim.world;var party=world.party_encounter
	world.entities[party.protagonist_id].tags.append(Rules.TAG)
	check(Rules.place_companions(session.sim),"place field companions")
	var fast:int=party.active_party_member_ids[1]
	var slow:int=party.active_party_member_ids[2]
	var enemy:int=party.enemy_ids[0]
	world.entities[fast].position=world.entities[enemy].position+Vector2i.LEFT
	world.entities[slow].position=world.entities[enemy].position+Vector2i.DOWN
	party.member(fast).action_speeds={"MOVE":200,"ATTACK":200,"CAST":100}
	party.member(slow).action_speeds={"MOVE":100,"ATTACK":75,"CAST":100}
	world._occupancy_index_ready=false
	world.emit_event("party.command_issued",party.protagonist_id,-1,
		world.entities[party.protagonist_id].position,0,-1,Orders.event_data("HOLD_POSITION",-1))
	var start:int=world.events.size()
	var result=Field.step(session.sim,Action.hold(party.protagonist_id))
	check(result.accepted,"field timing turn commits")
	var fast_times:Array=[];var slow_times:Array=[]
	for event in world.events.slice(start):
		if event.type!="action.melee_attack":continue
		if event.actor_id==fast:fast_times.append(event.world_time)
		if event.actor_id==slow:slow_times.append(event.world_time)
	check(fast_times==[0,50],"fast ally attacks twice at 0 and 50: "+str(fast_times))
	check(slow_times==[0],"slow ally attacks once: "+str(slow_times))
	check(party.member(slow).busy_until==134,"slow cooldown carries beyond the player's turn")
	check(world.world_state_error().is_empty(),"speed state validates: "+world.world_state_error())
	var snapshot:Variant=world.snapshot()
	var restored=preload("res://sim/simulator.gd").from_snapshot(snapshot) if snapshot is Dictionary else null
	check(restored!=null,"speed and remaining cooldown survive snapshot restoration")
	var moving=Session.new();world=moving.sim.world;party=world.party_encounter
	world.entities[party.protagonist_id].tags.append(Rules.TAG)
	check(Rules.place_companions(moving.sim),"place movement fixture")
	fast=party.active_party_member_ids[1]
	world.entities[fast].position=world.entities[party.protagonist_id].position+Vector2i.LEFT*3
	party.member(fast).action_speeds={"MOVE":200,"ATTACK":100,"CAST":100}
	world._occupancy_index_ready=false
	world.emit_event("party.command_issued",party.protagonist_id,-1,
		world.entities[party.protagonist_id].position,0,-1,Orders.event_data("STOP_ATTACK",-1))
	start=world.events.size()
	result=Field.step(moving.sim,Action.hold(party.protagonist_id))
	check(result.accepted,"fast movement turn commits")
	var move_times:Array=[]
	for event in world.events.slice(start):
		if event.type=="action.move" and event.actor_id==fast:move_times.append(event.world_time)
	check(move_times==[0,50],"fast ally walks two cells at 0 and 50: "+str(move_times))
	check(world.world_state_error().is_empty(),"fast movement snapshot validates: "+world.world_state_error())
	print("FIELD SPEED: ","PASS" if failures.is_empty() else "FAIL", " ",failures)
	quit(0 if failures.is_empty() else 1)
