extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const BindingPanel=preload("res://playtest/ability_loadout_mockup.gd")
const Action=preload("res://sim/party_action_command.gd")
var errors:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:errors.append(label);printerr("FAIL ",label)
func settle():
	for i in range(3):await process_frame
func run():
	root.size=Vector2i(360,800)
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	if s.sim==null:check(false,"session bootstrap");quit(1);return
	check(s.town_life_command({"action":"START"}).accepted,"town")
	check(s.guild_tutorial_command({"action":"ACCEPT","quest_id":"GUILD_TUTORIAL_BIND"}).accepted,"accept")
	check(s.guild_tutorial_command({"action":"SUPPORT","quest_id":"GUILD_TUTORIAL_BIND"}).accepted,"support")
	var hero:int=s.sim.world.party_control_actor_id()
	var panel=BindingPanel.new();root.add_child(panel)
	panel.configure(hero,s.ability_binding_rows(hero),s.ability_binding_item_rows(hero),
		func(instance_id):return s.bind_ability_item(hero,instance_id))
	var before:Dictionary=s.sim.snapshot()
	panel.picker.get_child(0).pressed.emit()
	await settle()
	check(panel.confirmation.visible,"item click opens confirmation")
	check(s.sim.snapshot()==before,"preview does not consume or bind")
	check(panel.confirmation.size.x<=360,"confirmation fits narrow viewport")
	panel.confirmation.canceled.emit();panel.confirmation.hide()
	panel._confirm_binding()
	check(s.sim.snapshot()==before,"cancel and stale confirm do nothing")
	panel.picker.get_child(0).pressed.emit()
	panel.confirmation.confirmed.emit();panel.confirmation.hide()
	check(s.sim.world.party_encounter.member(hero).active_skill_ids().count("FIREBOLT")==1,"confirmed binding grants skill")
	before=s.sim.snapshot();panel._confirm_binding()
	check(s.sim.snapshot()==before,"double confirm is harmless")
	panel.queue_free();await settle()
	check(s.depart_town().accepted,"depart with bound skill")
	var ui=Sandbox.new();ui.initialize_for_headless_test(s,true);root.add_child(ui);ui.set_process(false)
	await settle()
	for width in [360,390,450]:
		root.size=Vector2i(width,800);root.content_scale_size=Vector2i(width,800)
		ui._skill_pages[hero]=0;ui._refresh();await settle()
		var seen:Array=[]
		var initial_time:int=s.sim.world.world_time
		for page in range(3):
			var rail=ui.hero_skill_row.get_child(0)
			check(rail.get_global_rect().end.x<=width+1,"skill rail fits %d"%width)
			for button in rail.get_children():
				if button.has_meta("skill_id"):seen.append(str(button.get_meta("skill_id")))
			var next=rail.get_node_or_null("ActorSkillPage_%d"%hero)
			check(next!=null,"overflow button exists")
			if next==null:break
			check(ui._product_control_at_position(next.get_global_rect().get_center())==str(next.name),"touch hit test finds page button")
			ui._activate_product_control(str(next.name));ui._refresh();await settle()
		check("FIREBOLT" in seen and "TEST_SPARK" in seen,"bound and last test skill reachable")
		check(s.sim.world.world_time==initial_time,"paging costs no turn")
	# Natural movement; no inventory, position, or event injection in this test.
	var target:=-1
	for turn in range(30):
		var best:Dictionary={}
		for enemy_id in s.sim.world.party_encounter.enemy_ids:
			if not s.sim.world.is_autonomous_target(enemy_id):continue
			if s.FieldTurns.assess(s.sim,Action.skill(hero,"FIREBOLT",enemy_id)).accepted:
				target=enemy_id;break
			for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var path:Dictionary=s.sim.pathfinder.find_path(hero,s.sim.world.entities[enemy_id].position+direction)
				if path.get("found",false) and path.path.size()>1 and (best.is_empty() or path.path.size()<best.path.size()):best=path
		if target>0 or best.is_empty():break
		if not s.commit_field_action(Action.move_to(hero,best.path[1])).accepted:break
	check(target>0,"natural movement reaches valid firebolt target")
	if target>0:
		var time_before:int=s.sim.world.world_time
		var energy_before:int=s.sim.world.party_encounter.member(hero).energy
		var event_start:int=s.sim.world.events.size()
		ui._on_manual_skill_selected(hero,"FIREBOLT","화염탄")
		check(s.sim.world.world_time==time_before,"target selection is free")
		ui._commit_battle_target(target)
		check(s.sim.world.world_time>time_before,"bound skill spends action time")
		check(s.sim.world.party_encounter.member(hero).energy<energy_before,"bound skill spends MP")
		check(s.sim.world.events.slice(event_start).any(func(e):return e.type=="combat.fire_damage" and e.target_id==target),"bound firebolt actually damages enemy")
	var restored=Session.new();var loaded:Dictionary=restored.load_session_json(s.save_session_json())
	check(loaded.accepted,"binding plus real cast replay: "+str(loaded.get("reason","")))
	if loaded.accepted:check(restored.sim.snapshot()==s.sim.snapshot(),"full gameplay replay matches exactly")
	ui.queue_free();await settle()
	print("ABILITY GAMEPLAY: ",errors);quit(0 if errors.is_empty() else 1)
