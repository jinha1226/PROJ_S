extends SceneTree
const Shell=preload("res://playtest/party_encounter_sandbox.gd")
class Session extends "res://playtest/party_playtest_session.gd":
	var fail_response:=false
	func _advance_item_action_time()->Dictionary:
		if fail_response:return {"accepted":false,"reason":"injected_failure"}
		return super._advance_item_action_time()
var errors:Array[String]=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("FAIL ",label)
func settle()->void:
	for i in range(6):await process_frame
func run()->void:
	root.size=Vector2i(390,844)
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var ui=Shell.new();ui.initialize_for_headless_test(s,false);root.add_child(ui);ui.set_process(false)
	ui.show_species_picker_for_new_run();ui._commit_species_picker("human");ui._refresh()
	var hero:int=s.sim.world.party_control_actor_id()
	check(s.drop_inventory_item("START_HAND_AXE_001").get("accepted",false),"canonical drop fixture")
	var before:Dictionary=s.sim.snapshot();var journal:Array=s.command_journal.duplicate(true)
	s.fail_response=true
	check(not s.pickup_ground_item("START_HAND_AXE_001").accepted,"failed response rejected")
	check(s.sim.snapshot()==before and s.command_journal==journal,"failed pickup restores complete state")
	s.fail_response=false
	var started:=Time.get_ticks_usec();var pickup:Dictionary=s.pickup_ground_item("START_HAND_AXE_001")
	print("PICKUP_USEC=",Time.get_ticks_usec()-started," events=",s.sim.world.events.size())
	check(pickup.accepted,"pickup accepted")
	before=s.sim.snapshot()
	check(not s.pickup_ground_item("START_HAND_AXE_001").accepted,"duplicate pickup rejected")
	check(s.sim.snapshot()==before,"rejected pickup is non-mutating")
	started=Time.get_ticks_usec()
	check(s.sim.world.world_state_error().is_empty(),"full post-pickup audit")
	print("FULL_AUDIT_USEC=",Time.get_ticks_usec()-started)
	var restored=Session.new();check(restored.load_session_json(s.save_session_json()).accepted,"save reload")
	check(restored.sim.snapshot()==s.sim.snapshot(),"pickup replay exact")
	ui._open_hero_detail_tab("STATUS");await settle()
	var card=ui.member_status_window.find_child("StatusCombatGrid",true,false).get_child(0)
	check(card.get_meta("stat_help","").contains("최종 공격력"),"attack calculation explanation")
	var point:Vector2=card.get_global_rect().get_center()
	var press:=InputEventScreenTouch.new();press.index=0;press.pressed=true;press.position=point
	root.push_input(press,true)
	await create_timer(0.60).timeout
	check(ui.stat_help.popup.visible,"long hold opens explanation")
	ui.stat_help.popup.hide()
	var scroll_before:int=ui.member_detail_scroll.scroll_vertical
	root.push_input(press,true)
	var drag:=InputEventScreenDrag.new();drag.index=0;drag.position=point-Vector2(0,70)
	root.push_input(drag,true)
	check(ui.member_detail_scroll.scroll_vertical>scroll_before,"drag over combat card scrolls")
	check(ui.stat_help.timer.is_stopped(),"drag cancels hold")
	ui.stat_help._cancel()
	var lines:Array=ui.body_status_lines(s.inspect_party_member(hero).body_state)
	check(lines.size()>=7 and not str(lines[0]).contains("의식"),"body values have independent rows")
	# Obtain a canonical injury, never mutate HP behind the event journal.
	ui._close_member_detail()
	for i in range(160):
		var world=s.sim.world
		if world.entities[hero].health<world.entities[hero].max_health:break
		var goals:Array[Vector2i]=[]
		for id in world.party_encounter.enemy_ids:
			if not world.is_autonomous_target(id):continue
			for d in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:goals.append(world.entities[id].position+d)
		var route:Dictionary=s.sim.pathfinder.find_path_to_any(hero,goals)
		var action=preload("res://sim/party_action_command.gd")
		var intent=action.move_to(hero,route.path[1]) if route.get("found",false) and route.path.size()>1 else action.hold(hero)
		if not s.commit_field_action(intent).accepted:break
	check(s.sim.world.entities[hero].health<s.sim.world.entities[hero].max_health,"canonical injury")
	ui._open_hero_detail_tab("ITEM");await settle()
	check(ui.detail_hp.value==s.sim.world.entities[hero].health,"ITEM header HP")
	var used:Dictionary=s.use_inventory_item("START_POTION_001")
	check(used.accepted,"potion accepted: "+str(used.get("reason","")))
	ui._refresh_open_member_detail()
	check(ui.detail_hp.value==s.sim.world.entities[hero].health,"potion updates open header immediately")
	ui._open_hero_detail_tab("SKILL");await settle()
	check(ui.detail_hp.is_visible_in_tree() and ui.detail_mp.is_visible_in_tree(),"SKILL shared vitals")
	check(ui.detail_mp.value==s.sim.world.party_encounter.member(hero).energy,"header MP authority")
	ui.queue_free();await process_frame
	print("CHARACTER INTERACTION / PICKUP: ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
