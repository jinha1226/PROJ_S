extends SceneTree

## Regression: closing the member detail from a single-folio tab (PERSONALITY /
## RELATIONSHIP) must not leave a stashed, still-visible content control over the
## map that swallows touches. Uses phone-like input (ScreenTouch + emulated mouse).

const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Command=preload("res://sim/sim_command.gd")
var failures:Array[String]=[]

func _init()->void:call_deferred("run")

func _tap(pos:Vector2,index:int=0)->void:
	var press:=InputEventScreenTouch.new();press.index=index;press.pressed=true;press.position=pos
	root.push_input(press,true)
	var mouse_press:=InputEventMouseButton.new();mouse_press.device=InputEvent.DEVICE_ID_EMULATION
	mouse_press.button_index=MOUSE_BUTTON_LEFT;mouse_press.pressed=true;mouse_press.position=pos;mouse_press.global_position=pos
	root.push_input(mouse_press,true)
	var release:=InputEventScreenTouch.new();release.index=index;release.pressed=false;release.position=pos
	root.push_input(release,true)
	var mouse_release:=InputEventMouseButton.new();mouse_release.device=InputEvent.DEVICE_ID_EMULATION
	mouse_release.button_index=MOUSE_BUTTON_LEFT;mouse_release.pressed=false;mouse_release.position=pos;mouse_release.global_position=pos
	root.push_input(mouse_release,true)

func _check(value:bool,message:String)->void:
	if not value:failures.append(message)

func run()->void:
	for tab in ["PERSONALITY","RELATIONSHIP","STATUS"]:
		var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
		var state=session.sim.world.party_encounter;var hero:int=state.protagonist_id
		var npc_id:int=int(state.opening_event.npc_entity_id) if state.opening_event!=null else -1
		_check(npc_id>0,"fixture has the opening NPC")
		var ui=Sandbox.new();ui.size=Vector2(390,800);ui.initialize_for_headless_test(session,true)
		ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);ui.size=Vector2(390,800);root.add_child(ui)
		for i in range(4):await process_frame
		var origin:Vector2=ui.grid.get_global_rect().position
		_tap(origin+ui.grid.world_to_pixel_center(session.sim.world.entities[npc_id].position))
		for i in range(3):await process_frame
		_check(ui.member_detail_modal.visible,"%s: tapping the NPC opens the detail modal"%tab)
		var tab_button:Button={"PERSONALITY":ui.member_detail_personality_tab,
			"RELATIONSHIP":ui.member_detail_relationship_tab,"STATUS":ui.member_detail_status_tab}[tab]
		_check(tab_button.is_visible_in_tree(),"%s: tab is offered for the NPC"%tab)
		_tap(tab_button.get_global_rect().get_center());for i in range(3):await process_frame
		_check(ui.member_detail_current_tab==tab,"%s: tab selected via touch"%tab)
		_tap(ui.member_detail_close.get_global_rect().get_center());for i in range(3):await process_frame
		_check(not ui.member_detail_modal.visible,"%s: close button hides the modal"%tab)
		var hero_pos:Vector2i=session.sim.world.entities[hero].position
		var target:Vector2i=Vector2i(-1,-1)
		for d in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			if bool(session.preview_exploration(Command.move_to(hero,hero_pos+d)).get("accepted",false)):target=hero_pos+d;break
		var tap:Vector2=origin+ui.grid.world_to_pixel_center(target)
		for control in ui.find_children("*","Control",true,false):
			if control==ui or control==ui.grid or control.is_ancestor_of(ui.grid):continue
			if control.is_visible_in_tree() and control.mouse_filter!=Control.MOUSE_FILTER_IGNORE \
					and control.get_global_rect().has_point(tap) and not ui.grid.is_ancestor_of(control):
				failures.append("%s: %s still covers the map after closing (rect %s)"%[tab,control.name,control.get_global_rect()])
		var before:int=session.sim.world.step_index
		_tap(tap);for i in range(3):await process_frame
		_check(session.sim.world.step_index==before+1,"%s: map tap after closing moves the hero (step %d -> %d)"%[tab,before,session.sim.world.step_index])
		ui.queue_free();await process_frame
	if failures.is_empty():print("PASS member detail stash regression")
	else:
		for failure in failures:printerr("FAIL ",failure)
		print("FAIL member detail stash regression: %d failures"%failures.size())
	quit(1 if not failures.is_empty() else 0)
