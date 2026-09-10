extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Action=preload("res://sim/party_action_command.gd")
var failures:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	root.size=Vector2i(390,800);root.content_scale_size=Vector2i(390,800)
	for solo in [true,false]:
		var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",solo)
		var hero:int=session.sim.world.party_control_actor_id()
		var target:=-1
		for i in range(100):
			var assessment:Dictionary=session.tab_attack_assessment()
			if assessment.get("tab_action","")=="ATTACK":target=int(assessment.target_id);break
			var result:Dictionary
			if assessment.get("tab_action","")=="APPROACH":
				result=session.commit_field_action(Action.move_to(hero,Vector2i(assessment.destination[0],assessment.destination[1])))
			else:
				# Fixture setup may navigate unseen cells; the attack button itself
				# must only ever choose enemies in player sight.
				var goals:Array[Vector2i]=[]
				var world=session.sim.world
				for id in world.party_encounter.enemy_ids:
					if not world.is_autonomous_target(id):continue
					for direction in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
						goals.append(world.entities[id].position+direction)
				var path:Dictionary=session.sim.pathfinder.find_path_to_any(hero,goals)
				if not path.get("found",false) or path.path.size()<2:break
				result=session.commit_field_action(Action.move_to(hero,path.path[1]))
			if not result.accepted:break
		check(target>0,"naturally reach attack target solo=%s"%solo)
		if target<0:continue
		var ui=Sandbox.new();ui.size=Vector2(390,800);ui.initialize_for_headless_test(session,true);root.add_child(ui);ui.set_process(false)
		for i in range(4):await process_frame
		check(session.party_status().view_mode=="EXPLORATION","field attack does not require combat mode")
		var before:int=session.sim.world.world_time
		var journal:int=session.command_journal.size()
		var position:Vector2=ui.product_attack_button.get_global_rect().get_center()
		for pressed in [true,false]:
			var event=InputEventScreenTouch.new();event.index=0;event.pressed=pressed;event.position=position
			root.push_input(event,true)
		check(session.sim.world.world_time>before,"real attack button spends action time: "+ui.notice_text)
		check(session.command_journal.size()==journal+1,"one physical tap commits one field action")
		if session.command_journal.size()>journal:
			var row:Dictionary=session.command_journal[-1]
			check(row.kind=="field_action" and row.action.type=="MELEE","button commits melee directly")
		check(session.sim.world.world_state_error().is_empty(),"attack world validates")
		var loaded=Session.new();var restored:Dictionary=loaded.load_session_json(session.save_session_json())
		check(restored.accepted,"button action save replays: "+str(restored.get("reason","")))
		if restored.accepted:check(loaded.sim.snapshot()==session.sim.snapshot(),"button replay exact")
		ui.queue_free();await process_frame
	print("ATTACK BUTTON: ",failures)
	quit(0 if failures.is_empty() else 1)
