extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const SkillRow=preload("res://playtest/portrait_skill_row.gd")
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL ",message)
func run()->void:
	root.size=Vector2i(390,800)
	root.content_scale_size=Vector2i(390,800)
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var ui=Sandbox.new();ui.size=Vector2(390,800)
	ui.initialize_for_headless_test(session,true);root.add_child(ui);ui.set_process(false)
	for i in range(3):await process_frame
	var members:Array=session.party_cards()
	check(ui.hero_skill_row.get_child_count()==1,"one shared skill row")
	check(ui.product_tactics_button.get_theme_stylebox("normal") is StyleBoxTexture,"game buttons use image nine-slice")
	check(ui.product_tactics_button.get_theme_stylebox("normal").texture.get_size()==Vector2(48,48),"UI texture is cached on a 24px multiple")
	for member in members:
		var id:int=member.entity_id
		var before_time:int=session.sim.world.world_time
		ui._on_compact_member_card_pressed(id,str(member.display_name))
		for i in range(3):await process_frame
		check(session.sim.world.party_control_actor_id()==id,"portrait switches skill bar owner")
		check(session.sim.world.world_time==before_time,"switching skill bar costs no time")
		check(ui.hero_skill_row.get_child_count()==1,"switch replaces shared row without duplicating it")
		var pair=ui.hero_skill_row.get_node_or_null("PortraitSkills%d"%id)
		check(pair!=null,"shared bar belongs to selected actor: %d"%id)
		if pair==null:continue
		check(pair.get_child_count()==(4 if session.active_skill_rows(id).size()>3 else 3),"three slots plus overflow navigation when needed")
		var portrait=ui.cards.find_child("MemberCard%d"%id,true,false)
		check(absf(pair.global_position.x-ui.hero_skill_row.global_position.x)<2,"shared row aligns with full-width container")
		check(pair.get_global_rect().end.x<=root.size.x,"shared row fits viewport")
		check(pair.global_position.y+pair.size.y<=portrait.global_position.y+1,"skills sit above portrait")
		var expected:Array=session.sim.world.party_encounter.member(id).active_skill_ids()
		var shown:Array=[]
		for button in pair.get_children():
			if button.name.begins_with("ActorSkillPage_"):continue
			if button is Button:
				check(int(button.get_meta("actor_id"))==id,"skill belongs to selected actor")
				shown.append(str(button.get_meta("skill_id")))
			else:check(button.mouse_filter==Control.MOUSE_FILTER_IGNORE,"empty slot does not capture input")
		check(shown==expected.slice(0,3),"shared bar contains only equipped skills")
	var empty=SkillRow.new();empty.configure(999,[],-1,"")
	check(empty.get_child_count()==2,"no skills retains two empty slots")
	for child in empty.get_children():check(not child is Button,"empty slot has no clickable substitute")
	empty.free()
	var field_empty=SkillRow.new();field_empty.slot_count=3;field_empty.configure(999,[],-1,"")
	check(field_empty.get_child_count()==3,"empty shared bar retains three slots")
	for child in field_empty.get_children():check(not child is Button,"empty shared slot has no fake skill")
	field_empty.free()
	var healer:=-1
	for member in members:
		if "MEND" in session.sim.world.party_encounter.member(int(member.entity_id)).active_skill_ids():healer=int(member.entity_id)
	check(healer>0,"fixture has companion skill")
	if healer>0:
		var start:int=session.sim.world.world_time
		ui._on_manual_skill_selected(healer,"MEND","치유")
		check(ui._battle_target_actor_id==healer,"companion button targets its owner")
		check(session.sim.world.party_control_actor_id()==healer,"skill selects caster for direct control")
		check(session.sim.world.world_time==start,"target selection costs no time")
		ui._commit_battle_target(healer)
		check(session.sim.world.world_time==start,"invalid full-health heal does not consume time")
		ui._cancel_battle_targeting()
		var target:=-1
		for turn in range(30):
			var best:Dictionary={}
			for enemy_id in session.sim.world.party_encounter.enemy_ids:
				if not session.sim.world.is_autonomous_target(enemy_id):continue
				if session.FieldTurns.assess(session.sim,preload("res://sim/party_action_command.gd").skill(healer,"FIREBOLT",enemy_id)).accepted:
					target=enemy_id;break
				for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
					var path:Dictionary=session.sim.pathfinder.find_path(healer,session.sim.world.entities[enemy_id].position+direction)
					if path.get("found",false) and path.path.size()>1 and (best.is_empty() or path.path.size()<best.path.size()):best=path
			if target>0 or best.is_empty():break
			var moved:Dictionary=session.commit_field_action(preload("res://sim/party_action_command.gd").move_to(healer,best.path[1]))
			if not moved.accepted:break
		check(target>0,"natural exploration reaches a skill target")
		if target>0:
			start=session.sim.world.world_time
			ui._on_manual_skill_selected(healer,"FIREBOLT","화염탄")
			ui._commit_battle_target(target)
			check(session.sim.world.world_time>start,"confirmed companion skill consumes action time")
		check(session.sim.world.world_state_error().is_empty(),"skill world validates: "+session.sim.world.world_state_error())
	if "--capture" in OS.get_cmdline_user_args():
		ui._refresh()
		for i in range(3):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/living-world-dark-ui.png")
	ui.queue_free();await process_frame
	print("PORTRAIT SKILLS: ","PASS" if failures.is_empty() else "FAIL"," ",failures)
	quit(0 if failures.is_empty() else 1)
