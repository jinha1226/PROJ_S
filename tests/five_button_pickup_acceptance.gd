extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Shell=preload("res://playtest/party_encounter_sandbox.gd")
const Action=preload("res://sim/party_action_command.gd")
var failures:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func settle():
	for i in range(5):await process_frame
func tap(position:Vector2):
	for pressed in [true,false]:
		var event=InputEventScreenTouch.new();event.index=0;event.pressed=pressed;event.position=position
		root.push_input(event,true)
func run():
	root.size=Vector2i(390,800)
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",false)
	var ui=Shell.new();ui.size=Vector2(390,800);ui.initialize_for_headless_test(s,true)
	root.add_child(ui);ui.set_process(false);await settle()
	for width in [360,390,450]:
		root.size=Vector2i(width,800);ui.size=Vector2(width,800);ui._refresh();await settle()
		var names:Array=[]
		for button in ui.combat_action_dock.get_children():
			if button is Button and button.visible:
				names.append(str(button.name))
				check(button.size.x>=44,"touch width %d"%width)
		check(names==["ProductAttack","ProductWaitGuard","ProductAuto","ProductTactics","ProductBag"],"five fixed controls %d"%width)
	check(ui.product_wait_guard_button.text=="[휴식]","safe area offers rest")
	check(s.drop_inventory_item("START_HAND_AXE_001").accepted,"drop axe")
	ui._refresh();await settle()
	var hero:int=s.sim.world.party_control_actor_id()
	var before:int=s.command_journal.size()
	tap(ui.grid.get_global_transform()*ui.grid.actor_visual_center(hero));await settle()
	check(s.ground_item_count_at_protagonist()==0,"own actor tap picks sole item")
	check(s.command_journal.size()==before+1,"one pickup command")
	before=s.command_journal.size();ui._on_cell(s.sim.world.entities[hero].position)
	check(s.command_journal.size()==before,"empty own tile does not wait")
	check(s.drop_inventory_item("START_HAND_AXE_001").accepted,"drop axe again")
	check(s.drop_inventory_item("START_POTION_001").accepted,"drop potion")
	before=s.command_journal.size();ui._on_actor(hero);await settle()
	check(ui.ground_pickup_menu!=null and ui.ground_pickup_menu.visible,"multiple items open choices")
	check(s.command_journal.size()==before,"opening choices spends no turn")
	ui.ground_pickup_menu.hide();ui._take_ground_pickup_choice(0);await settle()
	check(s.ground_item_count_at_protagonist()==1,"choice takes exactly one item")
	var loaded=Session.new()
	check(loaded.load_session_json(s.save_session_json()).accepted,"pickup save loads")
	check(loaded.sim.snapshot()==s.sim.snapshot(),"pickup replay exact")
	for step in range(100):
		if not s.party_status().visible_enemy_ids.is_empty():break
		var goals:Array[Vector2i]=[]
		for id in s.sim.world.party_encounter.enemy_ids:
			if not s.sim.world.is_autonomous_target(id):continue
			for direction in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:goals.append(s.sim.world.entities[id].position+direction)
		var path:Dictionary=s.sim.pathfinder.find_path_to_any(hero,goals)
		if not path.get("found",false) or path.path.size()<2:break
		if not s.commit_field_action(Action.move_to(hero,path.path[1])).accepted:break
	ui._refresh();await settle()
	check(not s.party_status().visible_enemy_ids.is_empty(),"visible enemy fixture")
	check(ui.product_wait_guard_button.text=="[대기]","enemy switches to wait")
	before=s.command_journal.size();tap(ui.product_wait_guard_button.get_global_rect().get_center());await settle()
	check(s.command_journal.size()==before+1 and s.command_journal[-1].action.type=="HOLD","wait commits one hold")
	check(not ui._product_rest_active,"enemy wait does not start rest")
	ui.queue_free();await process_frame
	print("FIVE BUTTON PICKUP: ",failures)
	quit(0 if failures.is_empty() else 1)
