extends "res://tests/battle_timeline_acceptance.gd"

const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")

func _run()->void:
	await _mobile(360,640)
	await _mobile(390,844)
	_measure_history()
	for failure in failures:printerr("FAIL ",failure)
	print("PASS timeline integration" if failures.is_empty() else "FAIL timeline integration: %d"%failures.size())
	quit(0 if failures.is_empty() else 1)

func _touch(position:Vector2,pressed:bool,index:int=0)->void:
	var event:=InputEventScreenTouch.new();event.index=index;event.position=position;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()

func _mobile(width:int,height:int)->void:
	root.size=Vector2i(width,height);root.content_scale_size=Vector2i(width,height)
	var session=_new_engaged_duo()
	if session==null:return
	var ui:=Sandbox.new();ui.initialize_for_headless_test(session,true);ui.battle_mode="AUTO";root.add_child(ui)
	ui.set_process(false)
	await process_frame;await process_frame
	var bar=ui.battle_timeline_bar
	_check(bar.visible,"timeline shown during battle")
	_check_eq(bar.size.y,48.0,"bar height 48")
	_check(bar.get_global_rect().position.y>=ui.phase_panel.get_global_rect().end.y,"bar below HUD")
	_check(absf(bar.get_global_rect().position.y-ui.grid.get_global_rect().position.y)<0.5 \
		and bar.get_global_rect().end.y<=ui.grid.get_global_rect().end.y,"bar floats over the map's top edge")
	_check(ui.cards.get_global_rect().end.y<=height+0.5,"cards fit %dx%d screen"%[width,height])
	for product_hud in [false,true]:
		ui._apply_product_root_order(product_hud)
		_check_eq(ui.root_layout.get_child(ui.root_layout.get_child_count()-1),ui.bottom_navigation,
			"bottom navigation stays last in both layout modes")
	await process_frame
	var spec:Dictionary=bar.current_layout()
	_check(not spec.items.is_empty(),"visible timeline has entries")
	if spec.items.is_empty():ui.queue_free();await process_frame;return
	for a in range(spec.items.size()):
		for b in range(a+1,spec.items.size()):
			_check(not spec.items[a].touch.intersects(spec.items[b].touch),"distinct hit targets never overlap")
	var item:Dictionary=spec.items[0]
	var point:Vector2=bar.get_global_rect().position+item.touch.get_center()
	var time_before:int=session.sim.world.world_time
	var journal_before:int=session.command_journal.size()
	_touch(point,true);await process_frame
	_check(ui._battle_presentation_blocked(),"held timeline blocks battle")
	ui._tick_autonomous_battle(2)
	_check_eq(session.sim.world.world_time,time_before,"held timeline costs no time")
	_touch(point,false);await process_frame;await process_frame
	var controller=ui.battle_timeline_controller
	if item.entity_ids.size()>1:
		_check(controller.group_open,"group opens modal")
		_check(ui._battle_presentation_blocked(),"group keeps battle paused")
		var row:=ui.find_child("TimelineMember%d"%int(item.entity_ids[0]),true,false) as Button
		_check(row!=null and row.size.y>=48,"group button is finger sized")
		if row!=null:
			var target:=row.get_global_rect().get_center()
			_touch(target,true);await process_frame
			_touch(target,false);await process_frame;await process_frame
		_check(not controller.group_open,"real touch selects member and closes group")
	_check(ui.grid.actor_emphasis_active(int(item.entity_ids[0])),"timeline tap highlights map actor")
	_check_eq(session.command_journal.size(),journal_before,"info touch leaves journal unchanged")
	_check_eq(session.sim.world.world_time,time_before,"info touch leaves time unchanged")
	# Capture and cancel release beyond the bar; do not strand the shared hold.
	_touch(point,true);await process_frame
	_touch(Vector2(2,height-10),false);await process_frame
	_check(not controller.pointer_held and not controller.group_open,"outside release cancels and unblocks")
	# Multi-touch is cancellation, never a different actor selection.
	_touch(point,true);await process_frame
	_touch(point,true,1);_touch(point,false,1);_touch(point,false);await process_frame
	_check(not controller.pointer_held and not controller.group_open,"second finger cancels group tap")
	# Valid skill state is needed: fake mode strings are intentionally cleared by refresh.
	var companion:int=session.sim.world.party_encounter.party_member_ids[1]
	ui._on_manual_skill_selected(companion,"FIREBOLT","화염탄")
	await process_frame;await process_frame
	_check(not bar.taps_enabled(),"skill targeting disables upper taps")
	_touch(point,true);await process_frame;_touch(point,false);await process_frame
	_check(not controller.group_open,"targeting touch cannot open a group")
	_check_eq(session.command_journal.size(),journal_before,"targeting upper tap cannot cast")
	ui._cancel_battle_targeting();await process_frame;await process_frame
	# A real commit flashes roots once; refresh or load must not replay them.
	var plan:Dictionary=session.prepare_autonomous_party_turn()
	_check(plan.get("commit_ready",false),"auto plan accepted")
	var result:Dictionary=session.commit_turn()
	ui._record_result(result,true);ui._request_refresh()
	await process_frame;await process_frame
	_check(not bar._flash_until.is_empty(),"actual committed action highlights timeline")
	var flashes:Dictionary=bar._flash_until.duplicate()
	ui._refresh();await process_frame
	# A full refresh may outlive the short 180ms flash on a loaded CI host.
	# Expiry is valid; extending or recreating a deadline is not.
	_check_flash_deadlines(bar._flash_until,flashes,"refresh")
	controller.record_result(result);controller.sync()
	_check_flash_deadlines(bar._flash_until,flashes,"duplicate result")
	var t0:=Time.get_ticks_usec();session.battle_timeline_state();var query:=Time.get_ticks_usec()-t0
	t0=Time.get_ticks_usec();Bar.layout_spec(session.battle_timeline_state(),width);var layout:=Time.get_ticks_usec()-t0
	print("TIMELINE %dpx: cached query=%dus layout+query=%dus events=%d"%[width,query,layout,session.sim.world.events.size()])
	ui.battle_loot_panel.show();ui._refresh();await process_frame
	_check(not bar.visible,"loot hides timeline")
	ui.battle_loot_panel.hide();ui._refresh();await process_frame
	_check(bar.visible,"return restores timeline")
	ui.queue_free();await process_frame

func _check_flash_deadlines(current:Dictionary,original:Dictionary,label:String)->void:
	for id in current:
		_check(original.has(id),"%s cannot add an action flash"%label)
		_check_eq(current[id],original.get(id),"%s never restarts action flashes"%label)

func _measure_history()->void:
	var session=_new_engaged_duo()
	if session==null:return
	var samples:=0;var both_ready:=0;var max_cold:=0;var max_cached:=0;var max_layout:=0
	for step in range(40):
		if session.sim.world.party_encounter.safe_phase!="ENGAGED":break
		var planning:Dictionary=session.prepare_autonomous_party_turn()
		if not planning.get("commit_ready",false):break
		var start:int=session.sim.world.world_time
		var result:Dictionary=session.commit_turn()
		_check(result.get("accepted",false),"history sample commits")
		var t0:=Time.get_ticks_usec();var dto:Dictionary=session.battle_timeline_state()
		max_cold=maxi(max_cold,Time.get_ticks_usec()-t0)
		t0=Time.get_ticks_usec();session.battle_timeline_state();max_cached=maxi(max_cached,Time.get_ticks_usec()-t0)
		t0=Time.get_ticks_usec();Bar.layout_spec(dto,390);max_layout=maxi(max_layout,Time.get_ticks_usec()-t0)
		var ready:=0
		for row in dto.entries:
			if row.side=="ALLY" and row.status=="READY":ready+=1
		if ready>=2:both_ready+=1
		samples+=1
		if step<8:
			var deadlines:Dictionary={}
			for row in dto.entries:deadlines[int(row.entity_id)]=[row.ready_at,row.eligible_at]
			print("TRACE %d->%d ready/eligible=%s roots=%s"%[start,session.sim.world.world_time,deadlines,dto.recent_actions.slice(-4)])
	print("PERF samples=%d both_ready=%d events=%d max_us cold=%d cached=%d layout=%d phase=%s"%[
		samples,both_ready,session.sim.world.events.size(),max_cold,max_cached,max_layout,session.sim.world.party_encounter.safe_phase])
