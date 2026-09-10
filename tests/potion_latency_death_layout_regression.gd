extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Action=preload("res://sim/party_action_command.gd")
class FailingSession:
	extends "res://playtest/party_playtest_session.gd"
	var reject_response:=false
	func _advance_item_action_time()->Dictionary:
		if reject_response:return {"accepted":false,"reason":"injected_response_failure"}
		return super._advance_item_action_time()
class TerminalSandbox:
	extends "res://playtest/party_encounter_sandbox.gd"
	var completed_fixture:=false
	func _current_run_progress()->Dictionary:
		var value:Dictionary=super._current_run_progress()
		if completed_fixture:
			value["available"]=true;value["complete"]=true;value["terminal"]=true
		return value
var failures:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	root.size=Vector2i(390,800);root.content_scale_size=root.size
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	if "--living" in OS.get_cmdline_user_args():
		check(s.start_new_run_with_species("human",true,true).accepted,"living bootstrap")
		check(s.town_life_command({"action":"START"}).accepted,"town start")
		check(s.depart_town().accepted,"departure")
	var hero:int=s.sim.world.party_control_actor_id()
	for i in range(120):
		var w=s.sim.world
		if w.entities[hero].health<w.entities[hero].max_health:break
		var goals:Array[Vector2i]=[]
		for id in w.party_encounter.enemy_ids:
			if not w.is_autonomous_target(id):continue
			for d in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:goals.append(w.entities[id].position+d)
		var route:Dictionary=s.sim.pathfinder.find_path_to_any(hero,goals)
		var action=Action.move_to(hero,route.path[1]) if route.get("found",false) and route.path.size()>1 else Action.hold(hero)
		if not s.commit_field_action(action).accepted:break
	check(s.sim.world.entities[hero].health<s.sim.world.entities[hero].max_health,"canonical injury")
	var quantity:int=s.sim.world.item_state.inventory(hero).item("START_POTION_001").quantity
	var begin:=Time.get_ticks_usec()
	var potion:Dictionary=s.use_inventory_item("START_POTION_001")
	print("POTION_USE_USEC=",Time.get_ticks_usec()-begin," events=",s.sim.world.events.size())
	check(potion.get("accepted",false),"potion accepted: "+str(potion.get("reason","")))
	check(s.sim.world.item_state.inventory(hero).item("START_POTION_001").quantity==quantity-1,"consume once")
	check(int(potion.get("healed_amount",0))>0,"potion heals before response")
	check(s.sim.world.world_state_error().is_empty(),"full audit after potion")
	var restored=Session.new()
	var loaded:Dictionary=restored.load_session_json(s.save_session_json())
	check(loaded.get("accepted",false),"save/load: "+str(loaded.get("reason","")))
	if loaded.get("accepted",false):check(restored.sim.snapshot()==s.sim.snapshot(),"replay exact")
	var failed=FailingSession.new()
	var failure_loaded:Dictionary=failed.load_session_json(s.save_session_json())
	check(failure_loaded.get("accepted",false),"rollback fixture loads")
	if failure_loaded.get("accepted",false):
		for i in range(40):
			var w=failed.sim.world
			if w.entities[hero].health<w.entities[hero].max_health:break
			if not failed.commit_field_action(Action.hold(hero)).accepted:break
		var before=failed.sim.snapshot();var journal:Array=failed.command_journal.duplicate(true)
		failed.reject_response=true
		var rejected:Dictionary=failed.use_inventory_item("START_POTION_001")
		check(not rejected.accepted and rejected.reason=="injected_response_failure","response failure rejected")
		check(failed.sim.snapshot()==before and failed.command_journal==journal,"failed potion restores HP items history and time")
		check(not failed.use_inventory_item("MISSING_POTION").accepted,"invalid potion rejected")
		check(failed.sim.snapshot()==before,"invalid potion does not mutate")
	var ui=TerminalSandbox.new();ui.size=Vector2(390,800);ui.initialize_for_headless_test(s,true);root.add_child(ui);ui.set_process(false)
	for i in range(4):await process_frame
	var before_dims:Vector2i=ui._current_grid_view_dimensions()
	var before_rect:Rect2=ui.grid.get_rect()
	var zoom:int=ui._product_zoom_cell_count
	for i in range(200):
		if s.sim.world.entities[hero].health<=0:break
		var result:Dictionary=s.commit_field_action(Action.hold(hero))
		if not result.accepted:break
	check(s.sim.world.entities[hero].health<=0,"canonical death fixture")
	ui._refresh()
	for i in range(4):await process_frame
	ui._refresh()
	for i in range(4):await process_frame
	print("DEATH_LAYOUT before=",before_rect," after=",ui.grid.get_rect()," dims=",before_dims,"/",ui._current_grid_view_dimensions())
	check(before_dims==ui._current_grid_view_dimensions(),"death preserves projected cell dimensions")
	check(before_rect.size.is_equal_approx(ui.grid.get_rect().size),"death preserves map size")
	check(zoom==ui._product_zoom_cell_count,"death preserves user zoom")
	# Completed/terminal UI used to hide the skill rail and give its height to
	# the map. Exercise that presentation branch at phone and wide sizes too.
	for width in [360,390,450]:
		root.size=Vector2i(width,800);root.content_scale_size=root.size;ui.size=root.size
		ui.completed_fixture=false;ui._refresh()
		for i in range(4):await process_frame
		var dimensions:Vector2i=ui._current_grid_view_dimensions()
		var map_size:Vector2=ui.grid.size
		ui.completed_fixture=true;ui._refresh()
		for i in range(4):await process_frame
		check(ui.hero_skill_row.visible and ui.hero_skill_row.get_child_count()==0,"terminal rail reserved and inert %d"%width)
		check(ui._current_grid_view_dimensions()==dimensions,"terminal projection stable %d"%width)
		check(ui.grid.size.is_equal_approx(map_size),"terminal map size stable %d"%width)
	ui.queue_free();await process_frame
	print("POTION DEATH REGRESSION: ",failures)
	quit(0 if failures.is_empty() else 1)
