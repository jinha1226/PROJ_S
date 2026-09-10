extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Art=preload("res://playtest/human_directional_assets.gd")
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func settle()->void:
	for i in range(4):await process_frame
func touch(position:Vector2,pressed:bool)->void:
	var event:=InputEventScreenTouch.new();event.index=0;event.position=position;event.pressed=pressed
	root.push_input(event,true)
func tap(button:Control)->void:
	var center:=button.get_global_rect().get_center()
	touch(center,true);await process_frame;touch(center,false);await settle()
func mouse(position:Vector2,pressed:bool)->void:
	var motion:=InputEventMouseMotion.new();motion.position=position;root.push_input(motion,true)
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT
	event.position=position;event.pressed=pressed;root.push_input(event,true)
func run()->void:
	root.size=Vector2i(390,800);root.content_scale_size=Vector2i(390,800);root.gui_embed_subwindows=true
	for index in range(8):
		check(Art.FRAMES[index].get_size()==Vector2(24,24),"native24 frame %d"%index)
		check(Art.index(Art.DIRECTIONS[index])==index,"eight direction mapping %d"%index)
	check(Art.FRAMES[0].get_image().get_data()==load("res://assets/pixel24_v3/runtime/actors/base/human.png").get_image().get_data(),"south preserves original pixels")
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var ui=Sandbox.new();ui.initialize_for_headless_test(session,false);root.add_child(ui);ui.set_process(false)
	await settle()
	var hero:int=session.sim.world.party_control_actor_id()
	var ally:int=session.sim.world.party_encounter.active_party_member_ids[1]
	var before:Dictionary=session.sim.snapshot()
	var intents:Array=session.turn_intent_overlays()
	check(not intents.is_empty(),"field provides companion intent")
	check(before==session.sim.snapshot(),"intent preview does not mutate world")
	await tap(ui.product_tactics_button)
	check(ui.product_tactics_popup.visible,"actual touchscreen tactics release opens menu")
	ui.product_tactics_popup.hide();await settle()
	await tap(ui.cards.find_child("MemberCard%d"%ally,true,false))
	check(session.sim.world.party_control_actor_id()==ally,"portrait short tap selects companion")
	check(not ui.member_detail_modal.visible,"short tap does not inspect")
	check(ui.cards.find_child("MemberCard%d"%ally,true,false).selected,"controlled portrait highlighted")
	check(ui.grid.selected_actor_id==ally,"map selection follows controlled companion")
	var controlled:=false
	for spec in ui.grid.selection_overlay_draw_specs():
		if spec.kind=="CONTROLLED" and spec.entity_id==ally:controlled=true
	check(controlled,"map actually draws control highlight")
	var card=ui.cards.find_child("MemberCard%d"%hero,true,false)
	var center:Vector2=card.get_global_rect().get_center()
	touch(center,true);await create_timer(0.6).timeout;ui._tick_portrait_long_press()
	check(ui.member_detail_modal.visible and ui.member_detail_entity_id==hero,"held touchscreen opens correct status")
	touch(center,false);await settle()
	check(session.sim.world.party_control_actor_id()==ally,"long press release does not switch control")
	ui._close_member_detail();await settle()
	check(ui._product_touch_index==-1,"inspection gesture releases touch ownership")
	ui._product_ignore_mouse_until_msec=-1
	center=ui.cards.find_child("MemberCard%d"%hero,true,false).get_global_rect().get_center()
	mouse(center,true);mouse(center,false);await settle()
	check(session.sim.world.party_control_actor_id()==hero,"actual mouse portrait click selects hero")
	center=ui.cards.find_child("MemberCard%d"%ally,true,false).get_global_rect().get_center()
	mouse(center,true);await create_timer(0.6).timeout;ui._tick_portrait_long_press()
	check(ui.member_detail_modal.visible and ui.member_detail_entity_id==ally,"held mouse opens status")
	mouse(center,false);ui._close_member_detail();await settle()
	check(session.sim.world.party_control_actor_id()==hero,"mouse long press does not switch")
	center=ui.cards.find_child("MemberCard%d"%ally,true,false).get_global_rect().get_center()
	touch(center,true)
	var drag:=InputEventScreenDrag.new();drag.index=0;drag.position=center+Vector2(25,0);root.push_input(drag,true)
	touch(center,false);await settle()
	check(session.sim.world.party_control_actor_id()==hero,"portrait drag cancels short tap")
	var button=ui.hero_skill_row.find_child("ActorSkill_%d_MEND"%ally,true,false)
	await tap(button)
	check(ui._battle_target_actor_id==ally and ui._battle_target_mode=="ACTIVE_SKILL","actual skill tap enters target selection")
	check(session.sim.world.party_control_actor_id()==ally,"skill tap selects caster")
	ui._cancel_battle_targeting();await settle()
	check(not ui.hero_skill_row.find_child("ActorSkill_%d_MEND"%ally,true,false).disabled,"cancel restores skill availability")
	for row in session.party_cards():
		check(row.has("energy") and row.has("max_energy") and row.has("stress"),"portrait stats available")
	check(session.sim.world.world_time==int(before.world_time),"all UI gestures cost no simulation time")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/living-world-field-controls.png")
	ui.queue_free();await process_frame
	print("FIELD POINTER / ART: ","PASS" if failures.is_empty() else "FAIL"," ",failures)
	quit(0 if failures.is_empty() else 1)
