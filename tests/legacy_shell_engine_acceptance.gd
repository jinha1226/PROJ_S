extends SceneTree

const Session=preload("res://playtest/party_playtest_session.gd")
const Shell=preload("res://playtest/party_encounter_sandbox.gd")
const Router=preload("res://playtest/entry_router.gd")
const Action=preload("res://sim/party_action_command.gd")
const TurnBase=preload("res://sim/turn_engine.gd")
const Queue=preload("res://sim/systems/field_actor_queue.gd")
var failures:Array[String]=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)

func reference_next(sim,end:int)->Dictionary:
	var world=sim.world;var party=world.party_encounter
	var candidates:Array=[]
	if not world.scheduled_entries.is_empty() and int(world.scheduled_entries[0].due_time)<=end:
		candidates.append([int(world.scheduled_entries[0].due_time),0])
	for id in party.active_party_member_ids:
		if id==world.party_control_actor_id() or party.member(id).presence!="DEPLOYED" or not world.can_act(id,world.world_time):continue
		var at:int=maxi(world.world_time,party.member(id).busy_until)
		if at<end:candidates.append([at,id])
	for id in sim.party_coordinator._stream_enemy_ids():
		if not world.can_act(id,world.world_time):continue
		var at:int=maxi(world.world_time,int(party.enemy_busy_rows[id]))
		if at<end:candidates.append([at,id])
	candidates.sort_custom(func(a:Array,b:Array):return a[0]<b[0] or a[0]==b[0] and a[1]<b[1])
	return {} if candidates.is_empty() else {"at":candidates[0][0],"id":candidates[0][1]}
func run()->void:
	check(Router.GAME_SCENE=="res://playtest/party_encounter_sandbox.tscn","real campaign is default, not rebuilt demo")
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var world=session.sim.world
	var hero:int=world.party_control_actor_id()
	var queue=Queue.new()
	# Same-time ordering, environmental boundary and no early protagonist action.
	var expected:Dictionary=reference_next(session.sim,100)
	check(queue.next(session.sim,100)==expected,"heap chooses same first canonical event")
	var time_before:int=world.world_time
	var wait_result:Dictionary=session.commit_field_action(Action.hold(hero))
	check(wait_result.accepted and wait_result.turn_engine==TurnBase.ENGINE_ID,"old UI session executes new engine")
	check(world.world_time==time_before+100,"one command advances one action budget")
	var next_path:Dictionary={}
	for d in TurnBase.Geometry.DIRECTIONS:
		var candidate:Dictionary=session.sim.pathfinder.find_path(hero,world.entities[hero].position+d)
		if candidate.found:next_path=candidate;break
	check(not next_path.is_empty() and next_path.engine==TurnBase.ENGINE_ID,"campaign routes use new indexed pathfinder")
	if not next_path.is_empty():
		check(session.commit_field_action(Action.move_to(hero,next_path.path[1])).accepted,"old movement command executes path")
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
	var ui=Shell.new();ui.initialize_for_headless_test(session,false);root.add_child(ui);ui.set_process(false)
	await process_frame;await process_frame
	ui._refresh();await process_frame;await process_frame
	check(ui.phase_panel.visible and ui.minimap.visible and ui.ration_label.visible and ui.torch_timer_label.visible,"original exploration HUD and supplies: "+str(ui.expedition_hud_spec()))
	check(ui.grid.get_index()<ui.event_surface.get_index() and ui.event_surface.get_index()<ui.cards.get_index(),"map then three-line log then portraits")
	check(ui.cards.get_index()==ui.event_surface.get_index()+1,"portraits immediately follow log")
	check(ui.cards.get_index()<ui.combat_action_area.get_index(),"buttons remain below portraits")
	check(ui.cards.get_child_count()==1 and ui.event_label.max_lines_visible==3,"original portrait and three-line log")
	time_before=world.world_time
	for i in range(3):await process_frame
	check(world.world_time==time_before,"rendering does not advance combat")
	var saved:String=session.save_session_json()
	var loaded=Session.new();var restored:Dictionary=loaded.load_session_json(saved)
	check(restored.accepted and loaded.sim.snapshot()==session.sim.snapshot(),"legacy UI commands persist and replay through new engine")
	ui.queue_free();await process_frame
	print("LEGACY SHELL ENGINE: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
