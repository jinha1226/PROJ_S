extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Usage=preload("res://sim/usage_skill_rules.gd")
var failures:Array[String]=[]
func _init()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL ",message)
func click(point:Vector2)->void:
	var motion=InputEventMouseMotion.new();motion.position=point;Input.parse_input_event(motion)
	for pressed in [true,false]:
		var event=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		Input.parse_input_event(event)
		await process_frame
func run()->void:
	check(DisplayServer.get_name()!="headless","native display available")
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	check(session.reset_party(44,20260828,Session.DUO_SCENARIO_ID,{},true,"human",true,true,true,false,false,false,false,true,"MAGE"),"mage start")
	var ui=Sandbox.new();ui.initialize_for_headless_test(session,true);root.add_child(ui);ui.set_process(false)
	for i in range(8):await process_frame
	var hero:int=session.sim.world.party_control_actor_id()
	ui._open_member_detail(hero)
	for i in range(4):await process_frame
	await click(ui.member_detail_skill_tab.get_global_rect().get_center())
	for i in range(6):await process_frame
	check(ui.member_detail_current_tab=="SKILL","mouse opens skill tab")
	check(ui.member_skill_help.text.contains("실제 전투"),"automatic growth explanation visible")
	var before:Dictionary=session.sim.snapshot()
	await click(ui.member_progression_skill_rows.FIRE.title.get_global_rect().get_center())
	check(session.sim.snapshot()==before,"skill row click does not allocate XP or take turn")
	DirAccess.make_dir_recursive_absolute("res://docs/legacy-skills/evidence")
	await process_frame
	root.get_texture().get_image().save_png("res://docs/legacy-skills/evidence/skills-native.png")
	ui._close_member_detail()
	for i in range(3):await process_frame
	var origin:Vector2i=session.sim.world.entities[hero].position
	var target:=Vector2i(-1,-1)
	for direction in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
		var cell:Vector2i=origin+direction
		if session.sim.world.in_bounds(cell) and session.sim.world.occupying_entities_at(cell).is_empty() and session.sim.world.tile_at(cell).terrain!="wall":target=cell;break
	check(target!=Vector2i(-1,-1),"empty target available")
	ui._on_manual_skill_selected(hero,"FIREBOLT","화염탄")
	check(ui._battle_target_mode=="ACTIVE_SKILL","existing spell targeting opens")
	var training:Dictionary=Usage.totals(session.sim.world)
	var event_start:int=session.sim.world.events.size()
	var time_before:int=session.sim.world.world_time
	await click(ui.grid.global_position+ui.grid.world_to_pixel_center(target))
	for i in range(8):await process_frame
	check(session.sim.world.entities[hero].position==origin,"cast click does not move player")
	check(session.sim.world.world_time==time_before+120,"cast click costs exactly one spell action")
	check(ui._battle_target_mode.is_empty(),"successful cast leaves targeting")
	check(Usage.totals(session.sim.world)==training,"safe empty tile cast does not farm mastery")
	var roots:=0
	for index in range(event_start,session.sim.world.events.size()):
		var event=session.sim.world.events[index]
		if event.actor_id==hero and event.type in ["action.skill","action.move","action.melee_attack","ability.cast"]:roots+=1
	check(roots==1,"one map click commits one player command")
	root.get_texture().get_image().save_png("res://docs/legacy-skills/evidence/cast-native.png")
	ui.queue_free();await process_frame
	print("LEGACY USAGE GUI: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
