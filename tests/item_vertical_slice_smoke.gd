extends SceneTree

const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
const TerrainRegistry=preload("res://sim/terrain_registry.gd")

var failures:Array[String]=[]

func _init()->void:call_deferred("_run")

func _run()->void:
	for viewport_size in [Vector2(360,640),Vector2(450,800)]:await _check_viewport(viewport_size)
	if failures.is_empty():print("PASS item vertical slice UI/touch smoke")
	else:
		for failure in failures:print("FAIL item vertical slice UI/touch smoke -- ",failure)
	quit(1 if not failures.is_empty() else 0)

func _check_viewport(viewport_size:Vector2)->void:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var state=session.sim.world.party_encounter
	var hero=session.sim.world.entities[state.protagonist_id]
	var destination:=_safe_adjacent(session,hero.position)
	_assert(destination!=Vector2i(-1,-1),"%s lacks adjacent item fixture"%viewport_size)
	if destination==Vector2i(-1,-1):return
	state.ground_items.rows[0].position=destination;state.ground_items._sort_rows()
	_assert(session.sim.world.world_state_error().is_empty(),"%s item fixture invalid"%viewport_size)
	var sandbox=Sandbox.new();root.add_child(sandbox);sandbox.size=viewport_size
	sandbox.initialize_for_headless_test(session,true);await process_frame;await process_frame
	sandbox.skill_nav_button.pressed.emit();await process_frame;await process_frame
	sandbox._close_member_detail();sandbox.equipment_nav_button.pressed.emit();await process_frame
	sandbox._close_member_detail();sandbox.person_nav_button.pressed.emit();await process_frame;await process_frame
	sandbox._select_member_detail_tab("SKILL");await process_frame;await process_frame
	sandbox._toggle_weapon_mastery_category();await process_frame
	sandbox._select_member_detail_tab("ITEM");await process_frame;await process_frame
	var scroll:ScrollContainer=sandbox.member_detail_scroll
	var bar:VScrollBar=scroll.get_v_scroll_bar()
	_assert(bar.max_value>bar.page,
		"%s ITEM ledger cannot scroll max/page=%s/%s content=%s root=%s root_min=%s item_min=%s"%[
			viewport_size,bar.max_value,bar.page,sandbox.member_item_window.size,
			scroll.get_child(0).size,scroll.get_child(0).custom_minimum_size,
			sandbox.member_item_window.get_combined_minimum_size()])
	scroll.scroll_vertical=0;await process_frame
	var drag_origin:Vector2=(sandbox.member_item_equipment_rows.get_child(0) as Control) \
		.get_global_rect().get_center()
	_push_touch(drag_origin,true,31);await process_frame
	for step in range(1,6):
		var drag:=InputEventScreenDrag.new();drag.index=31
		drag.position=drag_origin+Vector2(0,-36*step);drag.relative=Vector2(0,-36)
		root.push_input(drag,true);await process_frame
	_push_touch(drag_origin+Vector2(0,-180),false,31);await process_frame;await process_frame
	_assert(scroll.scroll_vertical>0,"%s real ScreenTouch drag did not scroll ITEM ledger"%viewport_size)
	scroll.scroll_vertical=int(bar.max_value-bar.page);await process_frame;await process_frame
	var action_rect:Rect2=sandbox.member_item_action_row.get_global_rect()
	_assert(scroll.get_global_rect().intersection(action_rect).size.y>=43.9,
		"%s ITEM bottom actions remain unreachable at max scroll: %s"%[viewport_size,action_rect])
	_assert(sandbox.member_item_equipment_rows.get_child_count()==5 \
		and sandbox.member_item_backpack_rows.get_child_count()==12,
		"%s item ledger is not 5 equipment + 12 bag rows"%viewport_size)
	var bag_text:=""
	for child in sandbox.member_item_backpack_rows.get_children():bag_text+=str(child.text)
	_assert("단검" not in bag_text and "회복 물약" in bag_text,
		"%s equipped sword is duplicated in bag or potion is absent"%viewport_size)
	_assert(sandbox.find_child("ItemDiscard",true,false)==null \
		and sandbox.member_item_drop_button.custom_minimum_size.y>=44,
		"%s exposes DISCARD or loses 44px DROP"%viewport_size)
	sandbox._close_member_detail();await process_frame
	var time_before:=int(session.sim.world.world_time)
	sandbox.grid.world_cell_pressed.emit(destination);await process_frame
	_assert(state.ground_items.item("GROUND_START_SHIELD")==null \
		and state.protagonist_inventory.item("GROUND_START_SHIELD")!=null,
		"%s one ground-cell touch did not move then pick up"%viewport_size)
	_assert(int(session.sim.world.world_time)==time_before+200,
		"%s adjacent move+pickup did not consume exact 100+100 time"%viewport_size)
	_assert("확인" in sandbox.action_feedback_text and "주웠습니다" in sandbox.action_feedback_text,
		"%s one-touch pickup lacks confirmation feedback"%viewport_size)
	sandbox.queue_free();await process_frame

func _safe_adjacent(session,origin:Vector2i)->Vector2i:
	for direction in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
		var position:Vector2i=origin+direction
		if not session.sim.world.in_bounds(position) \
				or not session.sim.world.occupying_entities_at(position).is_empty():continue
		var definition:Dictionary=TerrainRegistry.definition(
			str(session.sim.world.tile_at(position).terrain))
		if bool(definition.get("passable",false)):return position
	return Vector2i(-1,-1)

func _assert(condition:bool,message:String)->void:
	if not condition:failures.append(message)

func _push_touch(position:Vector2,pressed:bool,index:int)->void:
	var touch:=InputEventScreenTouch.new();touch.index=index;touch.pressed=pressed
	touch.position=position;root.push_input(touch,true)
