extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Action=preload("res://sim/party_action_command.gd")
var failures:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func mouse(pos:Vector2,pressed:bool):
	var event=InputEventMouseButton.new();event.position=pos;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
	root.push_input(event,true)
func run():
	root.size=Vector2i(390,800);root.content_scale_size=Vector2i(390,800)
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var ui=Sandbox.new();ui.size=Vector2(390,800);ui.initialize_for_headless_test(session,true);root.add_child(ui)
	for i in range(4):await process_frame
	var ids:Array=session.sim.world.party_encounter.active_party_member_ids
	var card=ui.cards.find_child("MemberCard%d"%ids[1],true,false)
	var pos:Vector2=card.get_global_rect().get_center()
	mouse(pos,true);await process_frame;mouse(pos,false)
	for i in range(4):await process_frame
	check(session.sim.world.party_control_actor_id()==ids[1],"real mouse tap switches actor")
	card=ui.cards.find_child("MemberCard%d"%ids[1],true,false);pos=card.get_global_rect().get_center()
	mouse(pos,true)
	ui._refresh()
	await create_timer(0.8).timeout
	check(ui.member_detail_modal.visible,"real mouse hold survives HUD rebuild")
	mouse(pos,false)
	ui._close_member_detail()
	for i in range(4):await process_frame
	var touch=InputEventScreenTouch.new();touch.index=0;touch.position=pos;touch.pressed=true
	root.push_input(touch,true)
	await create_timer(0.8).timeout
	check(ui.member_detail_modal.visible,"real touch hold opens details")
	touch.pressed=false;root.push_input(touch,true)
	ui._close_member_detail()
	var key=InputEventKey.new();key.keycode=KEY_F1;key.pressed=true;root.push_input(key,true)
	check(session.sim.world.party_control_actor_id()==ids[0],"F1 switches without a turn")
	ui.queue_free();await process_frame
	session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var hero:int=session.sim.world.party_control_actor_id()
	var target:Vector2i=session.sim.world.entities[hero].position+Vector2i.RIGHT
	check(session.commit_field_action(Action.skill_at(hero,"FIREBALL",target)).accepted,"spend MP through real cast")
	ui=Sandbox.new();ui.size=Vector2(390,800);ui.initialize_for_headless_test(session,true);root.add_child(ui);ui.set_process(false)
	for i in range(4):await process_frame
	ui._on_product_rest()
	check(ui._product_rest_active,"full HP missing MP starts rest")
	for i in range(12):
		if ui._product_rest_active:ui._continue_product_rest(ui._product_rest_generation)
	check(session.sim.world.party_encounter.member(hero).energy==12,"MP fully recovers after safe waits at full HP")
	check(not ui._product_rest_active,"MP-only rest stops when full")
	var loaded=Session.new();var restored:Dictionary=loaded.load_session_json(session.save_session_json())
	check(restored.accepted,"MP rest replays: "+str(restored.get("reason","")))
	if restored.accepted:check(loaded.sim.snapshot()==session.sim.snapshot(),"MP rest replay exact")
	ui.queue_free();await process_frame
	print("INPUT RECOVERY: ",failures)
	quit(0 if failures.is_empty() else 1)
