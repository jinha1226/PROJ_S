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
	# Presentation fixture: modern runs no longer grant prototype role skills.
	# Give one companion a distinct bound ability to verify owner switching.
	var hero_id:int=session.sim.world.party_encounter.protagonist_id
	var companion:=-1
	for member in members:
		if int(member.entity_id)!=hero_id:
			companion=int(member.entity_id);break
	check(companion>0,"fixture has a selectable companion")
	if companion>0:
		session.sim.world.party_encounter.member(companion).bound_ability_ids.assign(["FIREBOLT"])
	ui._refresh()

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
		check(pair.get_child_count()==(7 if session.active_skill_rows(id).size()>6 else 6),"six slots plus overflow navigation when needed")
		var portrait=ui.cards.find_child("MemberCard%d"%id,true,false)
		check(absf(pair.global_position.x-ui.hero_skill_row.global_position.x)<2,"shared row aligns with full-width container")
		check(pair.get_global_rect().end.x<=root.size.x,"shared row fits viewport")
		check(pair.global_position.y>=portrait.global_position.y+portrait.size.y-1,"skills sit below portrait")
		var expected:Array=session.sim.world.party_encounter.member(id).active_skill_ids()
		var shown:Array=[]
		for button in pair.get_children():
			if button.name.begins_with("ActorSkillPage_"):continue
			if button is Button:
				check(int(button.get_meta("actor_id"))==id,"skill belongs to selected actor")
				shown.append(str(button.get_meta("skill_id")))
			else:check(button.mouse_filter==Control.MOUSE_FILTER_IGNORE,"empty slot does not capture input")
		check(shown==expected.slice(0,6),"shared bar contains only equipped skills")
	var empty=SkillRow.new();empty.configure(999,[],-1,"")
	check(empty.get_child_count()==2,"no skills retains two empty slots")
	for child in empty.get_children():check(not child is Button,"empty slot has no clickable substitute")
	empty.free()
	var field_empty=SkillRow.new();field_empty.slot_count=6;field_empty.configure(999,[],-1,"")
	check(field_empty.get_child_count()==6,"empty shared bar retains six slots")
	for child in field_empty.get_children():check(not child is Button,"empty shared slot has no fake skill")
	field_empty.free()
	if companion>0:
		ui._on_compact_member_card_pressed(companion,"")
		for i in range(3):await process_frame
		check(ui.hero_skill_row.find_child("ActorSkill_%d_FIREBOLT"%companion,true,false)!=null,"companion skill replaces hero empty slots")
		ui._on_compact_member_card_pressed(hero_id,"")
		for i in range(3):await process_frame
		check(ui.hero_skill_row.find_child("ActorSkill_%d_FIREBOLT"%companion,true,false)==null,"companion skill does not leak into hero bar")
	if "--capture" in OS.get_cmdline_user_args():
		ui._refresh()
		for i in range(3):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/living-world-dark-ui.png")
	ui.queue_free();await process_frame
	print("PORTRAIT SKILLS: ","PASS" if failures.is_empty() else "FAIL"," ",failures)
	quit(0 if failures.is_empty() else 1)
