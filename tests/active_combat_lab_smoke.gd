extends SceneTree
const Model=preload("res://playtest/active_combat_lab_model.gd")
const Lab=preload("res://playtest/active_combat_lab.gd")
var failures:Array[String]=[]
func check(value:bool,message:String)->void:
	if not value:failures.append(message)
func _init()->void:call_deferred("_run")
func _run()->void:
	var first=Model.new(44);var second=Model.new(44)
	check(first.actors.size()==9,"4 party / 5 enemies")
	var before:Array=first.actors.duplicate(true)
	first.preview(1,"FIREBOLT",5)
	check(first.turn==0 and first.actors==before,"target preview spends nothing")
	var result:Dictionary=first.act("FIREBOLT",5)
	second.act("FIREBOLT",5)
	check(result.accepted and first.turn==1,"one hero action advances turn")
	check(first.actor(1).energy==9,"resource charged once")
	check(not first.decisions.is_empty(),"companions/enemies act automatically")
	for index in range(6):
		first.act("WAIT");second.act("WAIT")
	check(first.actors==second.actors and first.history==second.history,"deterministic replay")
	var isolated=Model.new()
	var source:Dictionary=isolated.actor(1);source.skills=["MEND","BARRIER"]
	var ally:Dictionary=isolated.actor(2)
	isolated._damage(ally,40)
	check(ally.hp==60 and ally.recoverable==20,"half damage healable")
	check(isolated._execute(source,"MEND",2,Vector2i(-1,-1)).accepted,"heal executes")
	check(ally.hp==80 and ally.recoverable==0 and source.energy==8,"heal limited/charged")
	check(not isolated._execute(source,"MEND",2,Vector2i(-1,-1)).accepted,"no infinite healing")
	check(isolated._execute(source,"BARRIER",2,Vector2i(-1,-1)).accepted,"barrier executes")
	isolated._damage(ally,12)
	check(ally.hp==80 and ally.barrier==16,"barrier absorbs damage")
	isolated._execute(ally,"WAIT",-1,Vector2i(-1,-1));isolated._execute(ally,"WAIT",-1,Vector2i(-1,-1))
	check(ally.barrier==0,"barrier expires")
	for dimensions in [Vector2i(360,640),Vector2i(450,800)]:
		root.size=dimensions
		var lab=Lab.new();root.add_child(lab)
		await process_frame;await process_frame
		check(lab.dock.get_child_count()==4,"compact default controls")
		lab._select("FIREBOLT");lab._choose_target(5)
		check(lab.model.turn==0,"UI selection is free")
		check(lab.dock.get_child_count()==2,"target mode replaces dock")
		check(lab.get_global_rect().encloses(lab.dock.get_global_rect()),"dock inside viewport")
		lab._submit("FIREBOLT",5)
		check(lab.model.turn==1 and lab.skill.is_empty(),"UI confirmation executes once")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/active-combat-%d.png"%dimensions.x)
		lab.queue_free();await process_frame
	var session=preload("res://playtest/party_playtest_session.gd").new()
	var sandbox=preload("res://playtest/party_encounter_sandbox.gd").new()
	sandbox.size=Vector2(360,640);sandbox.initialize_for_headless_test(session)
	root.add_child(sandbox);await process_frame;await process_frame
	var campaign_time:int=session.sim.world.world_time
	var journal_count:int=session.command_journal.size()
	sandbox._open_active_combat_lab();await process_frame
	var launched=sandbox.get_node("ActiveCombatLab")
	check(not sandbox.is_processing_input(),"campaign input paused")
	launched._submit("FIREBOLT",5)
	check(session.sim.world.world_time==campaign_time and session.command_journal.size()==journal_count,"lab cannot mutate campaign")
	launched.closed.emit();launched.queue_free();await process_frame
	check(sandbox.is_processing_input(),"campaign input restored")
	sandbox.queue_free();await process_frame
	for failure in failures:printerr(failure)
	print("Active combat lab: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)
