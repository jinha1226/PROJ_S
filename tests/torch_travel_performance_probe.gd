extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Shell=preload("res://playtest/party_encounter_sandbox.gd")
const Ops=preload("res://sim/world_item_operations.gd")
const Torch=preload("res://sim/torch_rules.gd")
const Perf=preload("res://sim/perf_probe.gd")
var failed:=false
func _init()->void:run.call_deferred()
func run()->void:
	root.size=Vector2i(390,844)
	for lit in [false,true]:
		var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
		var world=session.sim.world;var hero:int=world.party_control_actor_id()
		var grant:Dictionary=Ops.commit_grant(world,hero,"TORCH",1,world.entities[hero].position,"TORCH_PERF")
		if not grant.get("accepted",false) or not session.equip_inventory_item(str(grant.instance_id),"OFF_HAND").accepted:
			printerr("fixture equip failed");quit(1);return
		if not session.ignite_torch(str(grant.instance_id)).accepted:
			printerr("fixture ignition failed");quit(1);return
		if not lit and not session.extinguish_torch(str(grant.instance_id)).accepted:
			printerr("fixture extinguish failed");quit(1);return
		var ui=Shell.new();ui.initialize_for_headless_test(session,false);root.add_child(ui);ui.set_process(false)
		for i in range(4):await process_frame
		Perf.reset();Perf.enabled=true
		var elapsed:=0;var accepted_moves:=0
		for i in range(6):
			var before:Vector2i=world.entities[hero].position
			var start:=Time.get_ticks_usec()
			ui._on_explore(Vector2i.RIGHT if i%2==0 else Vector2i.LEFT)
			elapsed+=Time.get_ticks_usec()-start
			if world.entities[hero].position!=before:accepted_moves+=1
			await process_frame
		Perf.enabled=false
		var error:String=world.world_state_error()
		failed=failed or not error.is_empty() or accepted_moves!=6
		print("TORCH_TRAVEL lit=",lit," moves=",accepted_moves," command_total_us=",elapsed,
			" mean_us=",elapsed/6," still_lit=",Torch.equipped_torch_state(world,hero).lit," error=",error)
		print(Perf.report())
		# Equipment visual cache must honor fuel/time even without inventory edits.
		var saved_time:int=world.world_time
		if lit:
			world.world_time+=Torch.FUEL_DURATION
			if session._entity_equipment_visual(hero).off_hand_torch_lit:
				failed=true;printerr("expired cached visual is still lit")
			world.world_time=saved_time
		ui.queue_free();await process_frame
	quit(1 if failed else 0)
