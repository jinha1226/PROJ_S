extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Action=preload("res://sim/party_action_command.gd")
var failures:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	root.size=Vector2i(390,800)
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",false)
	var hero:int=session.sim.world.party_control_actor_id()
	for step in range(100):
		if not session.party_status().get("visible_enemy_ids",[]).is_empty():break
		var goals:Array[Vector2i]=[]
		for id in session.sim.world.party_encounter.enemy_ids:
			if not session.sim.world.is_autonomous_target(id):continue
			for direction in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
				goals.append(session.sim.world.entities[id].position+direction)
		var path:Dictionary=session.sim.pathfinder.find_path_to_any(hero,goals)
		if not path.get("found",false) or path.path.size()<2:break
		if not session.commit_field_action(Action.move_to(hero,path.path[1])).accepted:break
	var ids:Array=session.party_status().get("visible_enemy_ids",[])
	check(not ids.is_empty(),"visible enemy fixture")
	if ids.is_empty():quit(1);return
	var target:int=ids[0]
	var ui=Sandbox.new();ui.size=Vector2(390,800)
	ui.initialize_for_headless_test(session,true);root.add_child(ui);ui.set_process(false)
	for i in range(4):await process_frame
	ui.battle_enemy_strip.sync(ui)
	var card=ui.battle_enemy_strip.row.get_node_or_null("EnemyPortrait%d"%target)
	check(card!=null,"enemy card exists")
	if card==null:quit(1);return
	# Exercise marker rendering while the target is visible. Issuing an order
	# advances the field turn and may legitimately move that enemy out of sight.
	ui.grid.set_party_focus({"command_id":"ATTACK_TARGET","target_id":target,"event_id":123})
	var marker:Dictionary=ui.grid.party_focus_draw_spec()
	check(marker.visible,"visible target has marker")
	if marker.visible:
		check(ui.grid.party_focus_draw_spec(ui.grid._party_focus_pulse_until+1).pulse==0.0,"pulse settles")
	ui.grid.set_party_focus({})
	var journal:int=session.command_journal.size()
	var position:Vector2=card.get_global_rect().get_center()
	for pressed in [true,false]:
		var event=InputEventScreenTouch.new();event.index=0;event.pressed=pressed;event.position=position
		event.canceled=not pressed;root.push_input(event,true)
	check(session.command_journal.size()==journal,"cancelled touch issues no command")
	var down=InputEventScreenTouch.new();down.index=0;down.pressed=true;down.position=position
	root.push_input(down,true)
	var drag=InputEventScreenDrag.new();drag.index=0;drag.position=position+Vector2(20,0);drag.relative=Vector2(20,0)
	root.push_input(drag,true)
	var up=InputEventScreenTouch.new();up.index=0;up.position=position+Vector2(20,0)
	root.push_input(up,true)
	check(session.command_journal.size()==journal,"scroll gesture issues no command")
	for pressed in [true,false]:
		var event=InputEventScreenTouch.new();event.index=0;event.pressed=pressed;event.position=position
		root.push_input(event,true)
	ui._request_refresh()
	for i in range(4):await process_frame
	ui._flush_pending_visual_effects()
	check(session.command_journal.size()==journal+1,"one card activation commits one command")
	check(session.command_journal[-1].kind=="party_command","card does not issue player melee")
	check(session.party_status().party_command.target_id==target,"party targets card enemy")
	check(ui.grid.party_focus_id==target,"persistent map target")
	check(ui.battle_enemy_strip.party_focus_id==target,"persistent card target")
	var snapshot:Dictionary=session.sim.snapshot()
	var spec:Dictionary=ui.grid.party_focus_draw_spec()
	if ui.grid._actor_by_id(target).is_empty():check(not spec.visible,"unseen target has no map marker")
	check(session.sim.snapshot()==snapshot,"marker queries do not mutate world")
	ui.grid.set_selection(hero,target)
	if not ui.grid._actor_by_id(target).is_empty():
		check(ui.grid.selection_overlay_draw_specs().any(func(row):return row.kind=="TARGET" and row.entity_id==target),"personal target marker")
	var loaded=Session.new()
	check(loaded.load_session_json(session.save_session_json()).accepted,"command save loads")
	check(loaded.sim.snapshot()==session.sim.snapshot(),"command replays exactly")
	check(session.issue_party_command("FOLLOW").accepted,"follow replaces focus")
	ui._flush_pending_visual_effects()
	check(ui.grid.party_focus_id==-1 and ui.battle_enemy_strip.party_focus_id==-1,"replacement clears markers")
	ui.queue_free();await process_frame
	print("PARTY FOCUS CARD: ",failures)
	quit(0 if failures.is_empty() else 1)
