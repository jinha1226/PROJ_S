extends SceneTree

const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Session=preload("res://playtest/party_playtest_session.gd")

var failures:Array[String]=[]

func _init()->void:
	call_deferred("_run")

func _run()->void:
	for viewport_size in [Vector2(360,640),Vector2(450,800)]:
		root.size=Vector2i(int(viewport_size.x),int(viewport_size.y))
		await process_frame
		await _check_product_zoom(viewport_size)
	await _check_legacy_and_fresh_defaults()
	if failures.is_empty():
		print("PASS product zoom smoke: 360x640, 450x800")
		quit(0)
	else:
		for failure in failures:printerr("FAIL ",failure)
		quit(1)

func _check_product_zoom(viewport_size:Vector2)->void:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var sandbox=Sandbox.new();sandbox.name="ProductZoomProbe";sandbox.size=viewport_size
	sandbox.initialize_for_headless_test(session,false)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);sandbox.size=viewport_size
	root.add_child(sandbox);await process_frame;await process_frame
	_check(sandbox.grid.visible_cell_count==13,"%s fresh product zoom is not 13 (about 1.15x)"%viewport_size)
	_check(is_equal_approx(sandbox._product_zoom_scale(13),15.0/13.0),
		"%s default product zoom is not derived from the 15-cell reference"%viewport_size)
	_check(sandbox.grid_zoom_controls.is_visible_in_tree(),
		"%s product zoom controls are hidden"%viewport_size)
	var map_rect:Rect2=sandbox.grid.get_global_rect()
	var out_rect:Rect2=sandbox.grid_zoom_out_button.get_global_rect()
	var in_rect:Rect2=sandbox.grid_zoom_in_button.get_global_rect()
	_check(out_rect.size.x>=44.0 and out_rect.size.y>=44.0 \
		and in_rect.size.x>=44.0 and in_rect.size.y>=44.0,
		"%s zoom hit rect is below 44px"%viewport_size)
	_check(map_rect.encloses(out_rect) and map_rect.encloses(in_rect) \
		and not out_rect.intersects(in_rect),
		"%s zoom controls overlap or leave the map"%viewport_size)
	_check(sandbox.grid_zoom_controls.mouse_filter==Control.MOUSE_FILTER_IGNORE \
		and sandbox.grid_zoom_out_button.mouse_filter==Control.MOUSE_FILTER_STOP \
		and sandbox.grid_zoom_in_button.mouse_filter==Control.MOUSE_FILTER_STOP \
		and sandbox.grid_zoom_controls.z_index>sandbox.grid.melee_vfx.z_index,
		"%s zoom overlay input/layer contract"%viewport_size)

	var route_started:=_start_long_route(session)
	_check(route_started,"%s could not prepare retained route"%viewport_size)
	var route_before:Dictionary=session.exploration_route_state()
	var snapshot_before:Dictionary=session.sim.snapshot()
	var journal_before:Array=session.command_journal.duplicate(true)
	var emitted_cells:Array=[]
	sandbox.grid.world_cell_pressed.connect(func(position):emitted_cells.append(position))
	await _touch(out_rect.get_center(),61)
	_check(sandbox.grid.visible_cell_count==15 and sandbox._product_zoom_cell_count==15,
		"%s [-] did not zoom out exactly one step"%viewport_size)
	_check(session.sim.snapshot()==snapshot_before and session.command_journal==journal_before,
		"%s zoom changed canonical world/journal"%viewport_size)
	_check(session.exploration_route_state()==route_before,
		"%s zoom touch cancelled or changed active route"%viewport_size)
	_check(emitted_cells.is_empty(),"%s zoom touch leaked to an underlying map cell"%viewport_size)
	await _touch(sandbox.grid_zoom_in_button.get_global_rect().get_center(),62)
	_check(sandbox.grid.visible_cell_count==13,"%s [+] did not restore the 1.15x view"%viewport_size)

	for count in [9,11,13,15,19,21,23,25]:
		sandbox._product_zoom_cell_count=count;sandbox._apply_product_zoom_surface()
		_check(sandbox.grid.visible_cell_count==count,
			"%s camera did not apply %d cells"%[viewport_size,count])
		var cell_size:Vector2=sandbox.grid.grid_rect().size/float(count)
		_check(cell_size.x>=14.0 and cell_size.y>=14.0,
			"%s %d-cell glyph surface fell below the mobile readability floor"%[viewport_size,count])
		var status:Dictionary=session.party_status()
		var hero:=Vector2i(int(status.protagonist_position[0]),int(status.protagonist_position[1]))
		_check(sandbox.grid.world_to_pixel_center(hero).distance_to(
			sandbox.grid.grid_rect().get_center())<0.01,
			"%s %d-cell hero is not centered"%[viewport_size,count])
		var bounds:Rect2i=sandbox.grid.view_bounds()
		var world_bounds:=Rect2i(Vector2i.ZERO,sandbox.grid.world_grid_size)
		var clipped:=bounds.intersection(world_bounds)
		for world_position in [clipped.position,clipped.end-Vector2i.ONE]:
			var pixel:Vector2=sandbox.grid.world_to_pixel_center(world_position)
			_check(sandbox.grid.pixel_to_world_cell(pixel)==world_position,
				"%s %d-cell mapping failed at %s"%[viewport_size,count,world_position])
		if not world_bounds.has_point(bounds.position):
			var padding:Dictionary=sandbox.grid.void_padding_draw_spec(bounds.position)
			_check(bool(padding.get("visible",false)) \
				and sandbox.grid.pixel_to_world_cell((padding.rect as Rect2).get_center())==Vector2i(-1,-1),
				"%s %d-cell edge padding accepted input"%[viewport_size,count])
		for row in sandbox.grid._cells.values():
			var state:=str(row.get("visibility_state","UNSEEN"))
			if state=="MEMORY":
				_check(row.get("actors",[]).is_empty() and str(row.get("feature_id",""))=="" \
					and int(row.get("fire_intensity",0))==0 and int(row.get("wetness",0))==0,
					"%s %d-cell MEMORY leak"%[viewport_size,count])
			elif state=="UNSEEN":
				_check(str(row.get("terrain_id",""))=="unknown" \
					and row.get("actors",[]).is_empty(),
					"%s %d-cell UNSEEN leak"%[viewport_size,count])

	sandbox._product_zoom_cell_count=25
	var zoom_started_usec:=Time.get_ticks_usec();sandbox._apply_product_zoom_surface()
	var zoom_apply_msec:float=float(Time.get_ticks_usec()-zoom_started_usec)/1000.0
	print("ZOOM PERF %s 25-cell apply %.2f ms"%[viewport_size,zoom_apply_msec])
	_check(zoom_apply_msec<250.0,
		"%s 25-cell projection exceeded 250ms (%.2fms)"%[viewport_size,zoom_apply_msec])
	var stable_snapshot:Dictionary=session.sim.snapshot()
	var stable_journal:Array=session.command_journal.duplicate(true)
	var exploration_refresh_started_usec:=Time.get_ticks_usec()
	sandbox._refresh_continuous_exploration_surface(session.party_status())
	var exploration_refresh_msec:float=float(
		Time.get_ticks_usec()-exploration_refresh_started_usec)/1000.0
	_check(sandbox.grid.visible_cell_count==25 and session.sim.snapshot()==stable_snapshot \
		and session.command_journal==stable_journal,
		"%s stable exploration refresh reset zoom or mutated authority"%viewport_size)
	var combat_refresh_started_usec:=Time.get_ticks_usec()
	sandbox._refresh_direct_solo_combat_surface(session.party_status())
	var combat_refresh_msec:float=float(
		Time.get_ticks_usec()-combat_refresh_started_usec)/1000.0
	print("ZOOM PERF %s refresh exploration %.2f ms combat %.2f ms"%[
		viewport_size,exploration_refresh_msec,combat_refresh_msec])
	_check(exploration_refresh_msec<250.0 and combat_refresh_msec<250.0,
		"%s 25-cell refresh exceeded 250ms (%.2f/%.2fms)"%[
			viewport_size,exploration_refresh_msec,combat_refresh_msec])
	_check(sandbox.grid.visible_cell_count==25 and session.sim.snapshot()==stable_snapshot \
		and session.command_journal==stable_journal,
		"%s direct solo refresh reset zoom or mutated authority"%viewport_size)
	_check(sandbox.grid_zoom_out_button.disabled and not sandbox.grid_zoom_in_button.disabled,
		"%s 25-cell boundary state"%viewport_size)
	sandbox._on_product_zoom_step(1)
	_check(sandbox.grid.visible_cell_count==25,"%s zoom-out exceeded 25"%viewport_size)
	sandbox._product_zoom_cell_count=9;sandbox._apply_product_zoom_surface()
	_check(sandbox.grid_zoom_in_button.disabled and not sandbox.grid_zoom_out_button.disabled,
		"%s 9-cell boundary state"%viewport_size)
	sandbox._on_product_zoom_step(-1)
	_check(sandbox.grid.visible_cell_count==9,"%s zoom-in exceeded 9"%viewport_size)
	sandbox._product_zoom_cell_count=25;sandbox._apply_product_zoom_surface()
	sandbox._refresh();await process_frame
	_check(sandbox.grid.visible_cell_count==25,"%s full refresh reset zoom"%viewport_size)
	# Zoom belongs exclusively to the uncovered game grid. Every product front
	# surface hides the overlay immediately and restores the same camera step.
	sandbox._open_hero_detail_tab("STATUS");await process_frame
	_check_zoom_hidden(sandbox,out_rect.get_center(),viewport_size,"status")
	sandbox._select_member_detail_tab("SKILL");await process_frame
	_check_zoom_hidden(sandbox,out_rect.get_center(),viewport_size,"skill")
	sandbox._select_member_detail_tab("ITEM");await process_frame
	_check_zoom_hidden(sandbox,out_rect.get_center(),viewport_size,"equipment/item")
	sandbox._close_member_detail();await process_frame
	_check_zoom_restored(sandbox,viewport_size,"detail close")
	sandbox._toggle_record_modal();await process_frame
	_check_zoom_hidden(sandbox,out_rect.get_center(),viewport_size,"record")
	sandbox._close_record_modal("TEST");await process_frame
	_check_zoom_restored(sandbox,viewport_size,"record close")
	sandbox._toggle_map_overlay();await process_frame
	_check_zoom_hidden(sandbox,out_rect.get_center(),viewport_size,"map")
	var overlay_layout:Dictionary=sandbox.map_overlay.layout_spec(viewport_size)
	_check(int(overlay_layout.get("world_width",0))==96 \
			and int(overlay_layout.get("world_height",0))==96,
		"%s map overlay did not ingest the full 96x96 discovered-map DTO"%viewport_size)
	sandbox.map_overlay.close("TEST");await process_frame
	_check_zoom_restored(sandbox,viewport_size,"map close")
	# The successful product restart handlers call this presentation reset after
	# replacing canonical state. The user's zoom preference must survive it.
	sandbox._reset_run_ui_transients();sandbox._refresh();await process_frame
	_check(sandbox.grid.visible_cell_count==25,"%s restart reset presentation zoom"%viewport_size)
	sandbox.queue_free();await process_frame

func _check_zoom_hidden(sandbox,old_button_center:Vector2,viewport_size:Vector2,
		label:String)->void:
	var before_count:int=int(sandbox._product_zoom_cell_count)
	var press:=InputEventScreenTouch.new();press.index=91;press.pressed=true
	press.position=old_button_center
	var intercepted:bool=sandbox._handle_product_zoom_touch(press)
	_check(not sandbox.grid_zoom_controls.visible \
			and not sandbox.grid_zoom_controls.is_visible_in_tree() \
			and not sandbox._product_zoom_control_has_point(old_button_center) \
			and not intercepted and sandbox._product_zoom_touch_index==-1 \
			and sandbox._product_zoom_cell_count==before_count \
			and sandbox.grid.modal_open,
		"%s %s surface exposes/intercepts grid zoom"%[viewport_size,label])

func _check_zoom_restored(sandbox,viewport_size:Vector2,label:String)->void:
	_check(sandbox.grid_zoom_controls.is_visible_in_tree() \
			and sandbox._product_zoom_cell_count==25 \
			and sandbox.grid.visible_cell_count==25 and not sandbox.grid.modal_open,
		"%s %s did not restore preserved 25-cell zoom"%[viewport_size,label])

func _start_long_route(session)->bool:
	var status:Dictionary=session.party_status()
	var origin:=Vector2i(int(status.protagonist_position[0]),int(status.protagonist_position[1]))
	var enemy_positions:Array[Vector2i]=[]
	for enemy_id_value in session.sim.world.party_encounter.enemy_ids:
		var enemy=session.sim.world.entities.get(int(enemy_id_value))
		if enemy!=null:enemy_positions.append(enemy.position)
	var best_goal:=Vector2i(-1,-1);var best_clearance:=-1
	for y in range(maxi(0,origin.y-10),mini(session.sim.world.height,origin.y+11)):
		for x in range(maxi(0,origin.x-10),mini(session.sim.world.width,origin.x+11)):
			var goal:=Vector2i(x,y)
			if maxi(absi(goal.x-origin.x),absi(goal.y-origin.y))<3:continue
			var preview:Dictionary=session.preview_exploration_route(goal)
			if not bool(preview.get("accepted",false)) or int(preview.get("total_steps",0))<3:continue
			var path:Array=preview.get("path",[])
			if path.size()<2:continue
			var first_step:=Vector2i(int(path[1][0]),int(path[1][1]))
			var clearance:=100000
			for enemy_position in enemy_positions:
				clearance=mini(clearance,maxi(absi(first_step.x-enemy_position.x),
					absi(first_step.y-enemy_position.y)))
			if clearance>best_clearance:
				best_clearance=clearance;best_goal=goal
	if best_goal==Vector2i(-1,-1):return false
	var chosen:Dictionary=session.preview_exploration_route(best_goal)
	var started:Dictionary=session.start_exploration_route(best_goal,
		str(chosen.get("plan_hash","")))
	return bool(started.get("active",false))

func _check_legacy_and_fresh_defaults()->void:
	var legacy=Sandbox.new();legacy.initialize_for_headless_test(Session.new(),false)
	_check(not legacy.grid_zoom_controls.visible and legacy._current_grid_view_cell_count()==15 \
		and legacy.grid.visible_cell_count==15,"legacy/non-product camera changed from 15")
	legacy._on_product_zoom_step(1)
	_check(legacy.grid.visible_cell_count==15,"legacy/non-product accepted product zoom")
	legacy.free()
	var fresh=Sandbox.new();fresh.initialize_for_headless_test(
		Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID),false)
	_check(fresh._product_zoom_cell_count==13 and fresh.grid.visible_cell_count==13,
		"new sandbox did not reset to the default 1.15x view")
	fresh.free()

func _touch(position:Vector2,index:int)->void:
	var press:=InputEventScreenTouch.new();press.index=index;press.pressed=true;press.position=position
	root.push_input(press,true);await process_frame
	var release:=InputEventScreenTouch.new();release.index=index;release.pressed=false;release.position=position
	root.push_input(release,true);await process_frame;await process_frame

func _check(condition:bool,message:String)->void:
	if not condition:failures.append(message)
