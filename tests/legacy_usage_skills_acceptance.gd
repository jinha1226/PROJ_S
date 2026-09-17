extends SceneTree
const Session = preload("res://playtest/party_playtest_session.gd")
const Action = preload("res://sim/party_action_command.gd")
const Usage = preload("res://sim/usage_skill_rules.gd")
const Sandbox = preload("res://playtest/party_encounter_sandbox.gd")
var failures:Array[String] = []
var checks := 0
func _init()->void:call_deferred("run")
func check(ok:bool, message:String)->void:
	checks += 1
	if not ok:failures.append(message);printerr("FAIL ", message)
func run()->void:
	for seed in [44, 45, 46]:
		print("USAGE sequence seed ",seed)
		var job:String="MAGE" if seed==45 else "RANGER" if seed==46 else "FIGHTER"
		var session = Session.new(seed, 20260828, Session.DUO_SCENARIO_ID)
		check(not Usage.enabled(session.sim.world), "old fixture keeps old rules")
		check(session.reset_party(seed,20260828,Session.DUO_SCENARIO_ID,{},true,"human",true,true,true,false,false,false,false,true,job), "usage initialization")
		var world = session.sim.world
		var hero:int = world.party_control_actor_id()
		check(Usage.enabled(world), "new game enables usage rules")
		check(world.world_state_error().is_empty(), "initial canonical state validates")
		var totals:Dictionary = Usage.totals(world)
		check(Usage.starting_job(world)==job,"starting background preserved")
		if job!="FIGHTER":
			check(session.equip_inventory_item("LEGACY_MAIN_HAND","MAIN_HAND").accepted,"background does not lock weapon choice")
		var before:Dictionary = session.sim.snapshot()
		check(not session.set_training_mode("SWORD","FOCUS").accepted, "manual XP focus removed")
		check(not session.spend_mastery_point("MAGIC").accepted, "manual mastery allocation removed")
		check(session.sim.snapshot() == before, "training UI cannot mutate world")
		check(not session.strike_enemy(-1).accepted, "invalid attack rejected")
		check(Usage.totals(world) == totals and session.sim.snapshot() == before, "invalid attack has no cost or training")
		for id in world.party_encounter.enemy_ids:
			for skill in world.party_encounter.member(hero).active_skill_ids():session.active_skill_assessment(hero,skill,id)
		check(session.sim.snapshot() == before and Usage.totals(world) == totals, "target assessments are pure")
		check(session.commit_field_action(Action.hold(hero)).accepted, "wait commits")
		check(Usage.totals(world) == totals, "safe wait does not train")
		var attacks := 0
		var spells := 0
		for turn in range(65):
			world = session.sim.world
			if world.party_encounter.safe_phase == "PARTY_DEFEATED":break
			var best:Dictionary = {}
			var target := -1
			for enemy_id in world.party_encounter.enemy_ids:
				if not world.is_autonomous_target(enemy_id):continue
				var ep:Vector2i = world.entities[enemy_id].position
				var hp:Vector2i = world.entities[hero].position
				if maxi(absi(ep.x-hp.x),absi(ep.y-hp.y))<=1:target=enemy_id;break
				for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
					var path:Dictionary = session.sim.pathfinder.find_path(hero,ep+direction)
					if path.get("found",false) and path.path.size()>1 and (best.is_empty() or path.path.size()<best.path.size()):best=path
			var result:Dictionary
			if target>0:
				var position:Vector2i = world.entities[hero].position
				if "FIREBOLT" in world.party_encounter.member(hero).active_skill_ids() and spells<2 and session.active_skill_assessment(hero,"FIREBOLT",target).get("accepted",false):
					result = session.strike_with_skill("FIREBOLT",target)
					spells += int(result.accepted)
					check(world.entities[hero].position == position, "spell does not move hero")
				else:
					result = session.strike_enemy(target)
					attacks += int(result.accepted)
			elif not best.is_empty():result=session.commit_field_action(Action.move_to(hero,best.path[1]))
			else:break
			check(result.accepted, "action %d seed %d: %s" % [turn,seed,str(result.get("reason",""))])
			if not result.accepted:break
			var error:String = world.world_state_error()
			check(error.is_empty(), "historical combat validates after training: "+error)
			if not error.is_empty():break
			if attacks>=3:break
		check(attacks>0, "real weapon attacks exercised")
		check(int(Usage.totals(world).SWORD)>int(totals.SWORD), "actual sword usage grows sword")
		if spells>0:check(int(Usage.totals(world).FIRE)>int(totals.FIRE), "actual casts grow fire school")
		var saved:String = session.save_session_json()
		var loaded = Session.new()
		var restored:Dictionary = loaded.load_session_json(saved)
		check(restored.accepted, "session save replay: "+str(restored.get("reason","")))
		if restored.accepted:
			check(loaded.sim.snapshot()==session.sim.snapshot(), "save/load preserves entire legacy state")
			check(Usage.totals(loaded.sim.world)==Usage.totals(world), "save/load preserves training")
		var ui = Sandbox.new()
		ui.initialize_for_headless_test(session,true)
		root.add_child(ui);ui.set_process(false)
		for i in range(3):await process_frame
		ui._update_progression_window(session.protagonist_progression())
		check(ui.member_progression_skill_rows.size()==14, "all design skills plus legacy unarmed in UI")
		check(ui.member_skill_help.text.contains("실제 전투"), "usage UI explains automatic training")
		for id in Usage.IDS:check((ui.member_progression_skill_rows[id].title as Button).disabled, "no focus allocation: "+id)
		ui.queue_free();await process_frame
	print("LEGACY USAGE SKILLS: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
