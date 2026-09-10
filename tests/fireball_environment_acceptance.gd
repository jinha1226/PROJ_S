extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Action=preload("res://sim/party_action_command.gd")
const Diorama=preload("res://playtest/ascii_diorama_projection.gd")
var failures:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,message:String):
	if not ok:failures.append(message);printerr("FAIL ",message)
func run():
	root.size=Vector2i(390,800)
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var world=session.sim.world
	var hero:int=world.party_control_actor_id()
	var pos:Vector2i=world.entities[hero].position+Vector2i.RIGHT
	check("FIREBALL" in world.party_encounter.member(hero).active_skill_ids(),"hero gets test spell")
	var before:Dictionary=session.sim.snapshot()
	var bad:Dictionary=session.commit_field_action(Action.skill_at(hero,"FIREBALL",Vector2i(-1,-1)))
	check(not bad.accepted and session.sim.snapshot()==before,"invalid ground cast is atomic")
	# Natural floor cast must round-trip the real session journal unchanged.
	var action=Action.skill_at(hero,"FIREBALL",pos)
	check(Action.from_dict(action.to_dict())!=null,"ground action wire round-trips")
	var result:Dictionary=session.commit_field_action(action)
	check(result.accepted,"ground cast accepted: "+str(result.get("reason","")))
	check(session.sim.world.world_time==120,"cast spends time")
	check(session.sim.world.party_encounter.member(hero).energy==9,"cast spends MP")
	var loaded=Session.new()
	var restored:Dictionary=loaded.load_session_json(session.save_session_json())
	check(restored.accepted,"session save replays ground skill: "+str(restored.get("reason","")))
	if restored.accepted:check(loaded.sim.snapshot()==session.sim.snapshot(),"journal replay exact")
	var reservoir=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	# Session bootstrap has already emitted events, so create a validated
	# snapshot fixture instead of bypassing the terrain bootstrap guard.
	var reservoir_snapshot:Dictionary=reservoir.sim.snapshot()
	var tile_index:int=pos.y*reservoir.sim.world.width+pos.x
	reservoir_snapshot.tiles[tile_index].terrain="shallow_water"
	reservoir_snapshot.tiles[tile_index].base_conductivity=60
	reservoir.sim=preload("res://sim/simulator.gd").from_snapshot(reservoir_snapshot)
	check(reservoir.sim!=null,"legacy water terrain fixture")
	if reservoir.sim==null:quit(1);return
	var reservoir_cast:Dictionary=reservoir.commit_field_action(Action.skill_at(hero,"FIREBALL",pos))
	check(reservoir_cast.accepted,"old map water can be heated")
	check(reservoir.sim.world.tile_at(pos).steam_amount>0,"old map water produces steam")
	check(reservoir.sim.world.world_state_error().is_empty(),"reservoir sample provenance validates")
	# A separate water fixture tests the actual button -> empty-cell path.
	session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	check(session.sim.world.bootstrap_set_surface(pos,"WATER",500)!=null,"water fixture")
	var ui=Sandbox.new();ui.size=Vector2(390,800)
	ui.initialize_for_headless_test(session,true);root.add_child(ui);ui.set_process(false)
	for i in range(3):await process_frame
	ui._on_manual_skill_selected(hero,"FIREBALL","화염구(시험)")
	check(ui._battle_target_skill_id=="FIREBALL","button selects ground targeting")
	check(session.sim.world.world_time==0,"selection costs no time")
	ui._on_manual_skill_selected(hero,"FIREBALL","화염구(시험)")
	check(ui._battle_target_mode.is_empty() and session.sim.world.world_time==0,"second tap cancels without spending a turn")
	ui._on_manual_skill_selected(hero,"FIREBALL","화염구(시험)")
	ui._on_cell(pos)
	ui._refresh()
	check(ui._battle_target_mode.is_empty(),"successful cast clears targeting")
	check(session.sim.world.world_time==120,"UI click commits one cast")
	var tile=session.sim.world.tile_at(pos)
	check(tile.surface_amount<500 and tile.steam_amount>0,"water boils into steam")
	check(session.sim.world.world_state_error().is_empty(),"water cast world validates")
	check(ui.grid.diorama_hazard_draw_spec(pos).get("steam",0)>0,"live map receives steam state")
	check(ui.grid._active_visual_effects.any(func(row):return row.kind=="FIREBALL"),"projectile VFX queued")
	check(ui.grid._active_visual_effects.any(func(row):return row.kind=="STEAM"),"evaporation VFX queued")
	var visible:=Diorama.hazard_floor_spec(pos,{"visibility_state":"VISIBLE","steam_amount":80})
	var hidden:=Diorama.hazard_floor_spec(pos,{"visibility_state":"MEMORY","steam_amount":80})
	check(visible.visible and visible.steam==80,"persistent steam draws")
	check(not hidden.visible and hidden.steam==0,"steam never leaks through fog")
	for effect in ui.grid._active_visual_effects:
		if effect.kind not in ["FIREBALL","STEAM"]:continue
		var spec:Dictionary=ui.grid.visual_effect_draw_spec(effect,effect.started_at_ms+200)
		check(spec.primitive==effect.kind and spec.duration_ms==1000,"effect has a bounded animation")
	if "--capture" in OS.get_cmdline_user_args():
		ui._refresh()
		for effect in ui.grid._active_visual_effects:effect.started_at_ms=Time.get_ticks_msec()-200
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/lw-fireball-steam.png")
	ui.queue_free();await process_frame
	print("FIREBALL ENVIRONMENT: ","PASS" if failures.is_empty() else "FAIL"," ",failures)
	quit(0 if failures.is_empty() else 1)
