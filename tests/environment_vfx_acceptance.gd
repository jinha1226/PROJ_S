extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Simulator=preload("res://sim/simulator.gd")
const Command=preload("res://sim/sim_command.gd")
const Vfx=preload("res://playtest/environment_vfx.gd")
const Diorama=preload("res://playtest/ascii_diorama_projection.gd")
var failures:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,message:String):
	if not ok:failures.append(message);printerr("FAIL ",message)
func run():
	var converter=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	for mode in ["ignite","extinguish","freeze","melt","condense","splash","electric","blast","rupture"]:
		var sim=Simulator.new(1,1,301)
		var command=Command.wait()
		var expected:=""
		match mode:
			"ignite":
				sim.world.bootstrap_set_terrain(Vector2i.ZERO,"wood_floor")
				command=Command.ignite(Vector2i.ZERO,80);expected="ENV_IGNITE"
			"extinguish":
				sim.world.bootstrap_set_terrain(Vector2i.ZERO,"wood_floor")
				sim.world.bootstrap_set_fire(Vector2i.ZERO,30)
				sim.world.bootstrap_set_surface(Vector2i.ZERO,"WATER",500)
				expected="ENV_EXTINGUISH"
			"freeze":
				sim.world.bootstrap_set_surface(Vector2i.ZERO,"WATER",300)
				sim.world.bootstrap_set_temperature(Vector2i.ZERO,-100);expected="ENV_FREEZE"
			"melt":
				sim.world.bootstrap_set_surface(Vector2i.ZERO,"ICE",300);expected="ENV_MELT"
			"condense":
				sim.world.bootstrap_set_atmosphere(Vector2i.ZERO,500,0,200,0,true);expected="ENV_CONDENSE"
			"splash":command=Command.pour_water(Vector2i.ZERO,50);expected="ENV_SPLASH"
			"electric":command=Command.discharge(Vector2i.ZERO,60);expected="ENV_SPARK"
			"blast", "rupture":
				sim.world.bootstrap_set_terrain(Vector2i.ZERO,"door_closed")
				sim.world.begin_step(1)
				sim.environment.explode(Vector2i.ZERO,100,-1,1,"combustion" if mode=="blast" else "rupture")
				sim.world.finish_step()
				expected="ENV_BLAST" if mode=="blast" else "ENV_RUPTURE"
		var result:Variant={"accepted":true,"events":sim.world.events} if mode in ["blast","rupture"] else sim.step(command)
		check(result.accepted,"simulation accepts "+mode)
		converter.sim=sim
		var rows:Array=converter._visual_effects_from_result(result)
		check(rows.any(func(row):return row.kind==expected),"real event maps to "+expected)
		if mode=="blast":check(rows.any(func(row):return row.kind=="ENV_DEBRIS"),"destruction creates debris")
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var ui=Sandbox.new();ui.size=Vector2(390,800);root.size=Vector2i(390,800)
	ui.initialize_for_headless_test(session,true);root.add_child(ui);ui.set_process(false)
	for i in range(3):await process_frame
	var pos:Vector2i=session.sim.world.entities[session.sim.world.party_control_actor_id()].position
	var before:Dictionary=session.sim.snapshot()
	var rows:Array=[];var id:=10000
	for kind in Vfx.STYLES:
		rows.append({"effect_id":str(id),"event_id":id,"kind":kind,"order":id,"world_position":[pos.x,pos.y]});id+=1
	check(ui.grid.play_effects(rows)==Vfx.STYLES.size(),"all reaction primitives enqueue")
	check(ui.grid.play_effects(rows)==0,"same event is never replayed")
	for effect in ui.grid._active_visual_effects:
		var spec:Dictionary=ui.grid.visual_effect_draw_spec(effect,effect.started_at_ms+200)
		check(spec.visible and spec.primitive==effect.kind and spec.duration_ms<=1000,"bounded visible primitive")
	var hidden:Dictionary={"effect_id":"hidden","event_id":20000,"kind":"ENV_BLAST","world_position":[-1,-1]}
	check(ui.grid.play_effects([hidden])==0,"hidden event never enters visible queue")
	hidden.world_position=[pos.x,pos.y]
	check(ui.grid.play_effects([hidden])==0,"later reveal does not replay hidden event")
	var duplicate:Dictionary=rows[0].duplicate();duplicate.effect_id="duplicate";duplicate.event_id=20001
	var duplicate2:Dictionary=duplicate.duplicate();duplicate2.effect_id="duplicate2";duplicate2.event_id=20002
	check(ui.grid.play_effects([duplicate,duplicate2])==1,"same-cell same-kind reactions coalesce")
	var flood:Array=[]
	for y in range(ui.grid.visible_row_count):
		for x in range(ui.grid.visible_cell_count):
			var cell:Vector2i=ui.grid.view_origin+Vector2i(x,y)
			if not ui.grid.is_world_cell_visible(cell):continue
			var event_id:int=30000+flood.size()
			flood.append({"effect_id":str(event_id),"event_id":event_id,"kind":"ENV_BLAST","world_position":[cell.x,cell.y]})
	check(flood.size()>Vfx.MAX_PER_BATCH,"fixture exceeds batch cap")
	check(ui.grid.play_effects(flood)==Vfx.MAX_PER_BATCH,"large chains are bounded")
	check(session.sim.snapshot()==before,"effects never mutate simulation or RNG")
	var hidden_surface:=Diorama.hazard_floor_spec(pos,{"visibility_state":"MEMORY","smoke_amount":900,"surface_id":"ICE","surface_amount":500})
	check(not hidden_surface.visible and hidden_surface.smoke==0 and hidden_surface.surface_id=="NONE","persistent surfaces respect fog")
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/lw-environment-vfx.png")
	ui.queue_free();await process_frame
	print("ENVIRONMENT VFX: ","PASS" if failures.is_empty() else "FAIL"," ",failures)
	quit(0 if failures.is_empty() else 1)
