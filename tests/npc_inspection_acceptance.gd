extends SceneTree
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Supplies=preload("res://playtest/expedition_supply_presenter.gd")
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL ",message)
func settle()->void:
	for i in range(6):await process_frame
func run()->void:
	var list_checks=preload("res://tests/test_monster_awareness_ui.gd").new()
	list_checks.test_visible_enemy_marks_list_grouping_and_transition_pulse_are_fov_safe()
	list_checks.test_awareness_ui_fits_360_450_at_zoom_11_15_19_and_caps_five_rows()
	for error in list_checks.errors:check(false,str(error))
	root.size=Vector2i(360,800);root.content_scale_size=root.size
	var ui=Sandbox.new();ui.set_personality_entropy_source_for_headless_test(func():return 20260828)
	root.add_child(ui);await settle();ui._commit_species_picker("human");await settle()
	var session=ui.session
	var styles:Dictionary={};var profiles:Dictionary={}
	for resident in session.town_life_overview().residents:
		var id:=int(resident.entity_id)
		var detail:Dictionary=session.inspect_party_member(id)
		styles[str(detail.personality_style.get("label",""))]=true
		profiles[JSON.stringify(detail.personality_profile)]=true
		if not resident.joined:check(detail.role_label!="동료","neutral role "+str(id))
		if not resident.adventurer:
			ui._on_town_facility_selected(str(resident.facility_id));await settle()
			var worker:=ui.find_child("TownWorker%d"%id,true,false) as Button
			check(worker!=null,"worker is at "+str(resident.facility_id))
			if worker!=null:worker.pressed.emit();await settle()
			check(ui.member_detail_entity_id==id,"workplace opens correct worker")
			check(ui.member_detail_subtitle.text.contains(str(resident.occupation)),"occupation subtitle")
			ui._close_member_detail();await settle()
	check(styles.size()>4,"varied personality summaries")
	check(profiles.size()>10,"independent generated personality profiles")
	var supplies:=Supplies.rows(session)
	check(supplies.size()==2,"food and potions prepared")
	check(supplies[0].carried==2 and supplies[1].carried==3,"standby inventories excluded")
	ui._on_town_facility_selected("GATE");await settle()
	var gold:int=session.town_gold()
	for definition in ["FOOD_RATION","POTION_HEALING"]:
		var buy:=ui.find_child("TownSupplyBuy"+definition,true,false) as Button
		check(buy!=null and not buy.disabled,"supply purchase available")
		if buy!=null:buy.pressed.emit();await settle()
	check(session.town_gold()==gold-18,"canonical supply prices charged once")
	check(ui.town_facility_id=="GATE","purchase stays on expedition preparation")
	supplies=Supplies.rows(session)
	check(supplies[0].carried==3 and supplies[1].carried==4,"quantities refresh after buying")
	var replay=preload("res://playtest/party_playtest_session.gd").new()
	var loaded:Dictionary=replay.load_session_json(session.save_session_json())
	check(loaded.get("accepted",false),"supply purchases replay from save")
	if loaded.get("accepted",false):
		check(Supplies.rows(replay)==supplies,"supply ownership survives save/load")
		check(replay.town_life_overview()==session.town_life_overview(),"workplaces and personalities survive save/load")
	ui._on_town_depart(1,"SURFACE_ENTRANCE");await settle()
	var visitors:Array=preload("res://sim/town_population_rules.gd").locations(session.sim.world)
	check(visitors.size()==8,"dungeon visitors exist independently of party")
	for visitor in visitors:
		var id:=int(visitor.entity_id);var detail:Dictionary=session.inspect_party_member(id)
		var before:int=session.sim.world.world_time
		ui._open_member_detail(id,"PERSONALITY");await settle()
		check(ui.member_detail_modal.visible and ui.member_detail_entity_id==id,"inspector selects visitor "+str(id))
		check(ui.member_detail_title.text==detail.display_name,"title matches identity")
		check(ui.member_personality_window.presentation_snapshot().style_label==detail.personality_style.label,"personality matches selected identity")
		check(ui.member_detail_subtitle.text.contains("중립 모험가"),"visitor is not a companion")
		check(session.sim.world.world_time==before,"inspection does not advance simulation")
		ui.member_detail_close.pressed.emit();await settle()
		check(not ui.grid.modal_open and not ui._battle_presentation_blocked(),"close releases all input/clock locks")
		check(not ui.auto_deployment_fallback and not ui.auto_combat_fallback,"inspection does not enable manual fallback")
	# Use a small visible observation with real NPC identities to exercise list
	# hit testing independently of random spawn/FOV positions.
	var cells:Array=[]
	for index in range(3):
		var id:=int(visitors[index].entity_id);var entity=session.sim.world.entities[id]
		var p:=[8+index,8]
		cells.append({"position":p,"terrain_id":"floor","visibility_state":"VISIBLE","actors":[{
			"entity_id":id,"display_name":entity.display_name,"species_id":"human","faction_id":"neutral",
			"presence":"WORLD_NPC","position":p,"life_state":"ACTIVE","health":entity.health,"max_health":entity.max_health}]})
	ui.grid.set_observation({"width":24,"height":24,"cells":cells})
	ui.grid.set_hero_centered_view(Vector2i(9,9),15)
	var spec:Dictionary=ui.grid.monster_list_draw_spec()
	check(spec.visible and spec.rows.size()==3,"three distinct NPC list entries")
	var before_journal:int=session.command_journal.size()
	for row in spec.rows:
		var point:Vector2=Rect2(row.hit_rect).get_center()
		for pressed in [true,false]:
			var event:=InputEventScreenTouch.new();event.index=0;event.pressed=pressed
			event.position=ui.grid.get_global_transform_with_canvas()*point
			root.push_input(event,true)
		check(ui.member_detail_entity_id==int(row.entity_id),"list click selects exact NPC")
		ui._close_member_detail()
	check(session.command_journal.size()==before_journal,"list cannot fall through to a movement command")
	# A drag must cancel inspection, not activate the map beneath it.
	var point:Vector2=Rect2(spec.rows[0].hit_rect).get_center()
	ui.grid._begin_pointer_gesture("TOUCH",0,point)
	ui.grid._update_pointer_gesture(point+Vector2(30,0))
	ui.grid._finish_pointer_gesture("TOUCH",0,point+Vector2(30,0),false)
	check(not ui.member_detail_modal.visible,"drag cancels list click")
	ui.autonomous_battle_clock.paused=true
	ui._open_member_detail(int(visitors[0].entity_id));ui._close_member_detail()
	check(ui.autonomous_battle_clock.paused,"explicit pause survives inspection")
	ui.autonomous_battle_clock.paused=false
	await settle()
	var moved:=false
	for direction in [Vector2i.RIGHT,Vector2i.LEFT,Vector2i.UP,Vector2i.DOWN]:
		var result:Dictionary=session.commit_exploration_direction(direction)
		if result.get("accepted",false):moved=true;break
	check(moved,"movement accepted after closing inspector")
	check(session.sim.world.world_state_error().is_empty(),"valid canonical world after inspection and purchases")
	ui.queue_free();await process_frame
	print("NPC_INSPECTION_ACCEPTANCE ","PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
