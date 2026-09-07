extends SceneTree

const Fixtures=preload("res://tests/test_party_companion_suggest.gd")
const Action=preload("res://sim/party_action_command.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
var failures:Array[String]=[]

func _init()->void:call_deferred("_run")
func check(value:bool,message:String)->void:
	if not value:failures.append(message)

func _run()->void:
	var session=Fixtures.new()._engaged()
	var state=session.sim.world.party_encounter
	var hero:int=state.protagonist_id
	var companion:int=state.active_party_member_ids[1]
	var before_time:int=session.sim.world.world_time
	var before_journal:int=session.command_journal.size()
	check(session.reserve_companion_action(companion,"HOLD").accepted,"reserve")
	check(session.sim.world.world_time==before_time and session.command_journal.size()==before_journal,"reservation spends no turn")
	check(session.begin_turn(Action.hold(hero)).accepted,"hero draft preserves reservation")
	var preview:Dictionary=session.current_turn_preview()
	var found:=false
	for row in preview.actor_rows:
		if int(row.actor_id)==companion:found=str(row.source)=="OVERRIDE" and str(row.action.type)=="HOLD"
	check(found,"reserved action replaces AI")
	check(session.has_companion_order(companion),"preview does not consume")
	check(session.commit_turn().accepted,"commit")
	check(not session.has_companion_order(companion),"one shot consumed")
	session.reserve_companion_action(companion,"HOLD")
	session.cancel_companion_order(companion)
	check(not session.has_companion_order(companion),"cancel")
	# Busy actors retain orders through planning instead of gaining extra actions.
	session=Fixtures.new()._engaged();state=session.sim.world.party_encounter
	hero=state.protagonist_id;companion=state.active_party_member_ids[1]
	state.member(companion).busy_until=session.sim.world.world_time+1000
	session.reserve_companion_action(companion,"HOLD")
	var resolution:Dictionary=session.companion_orders.resolve(session,Action.hold(hero),{})
	check(not resolution.overrides.has(companion) and not resolution.consumed.has(companion),"busy reservation waits")
	state.member(companion).busy_until=session.sim.world.world_time
	session.reserve_companion_action(companion,"MELEE",[],999999)
	check(session.begin_turn(Action.hold(hero)).accepted,"invalid target does not block hero")
	preview=session.current_turn_preview();found=false
	for row in preview.actor_rows:
		if int(row.actor_id)==companion:found=str(row.source)=="OVERRIDE" and str(row.action.type)=="HOLD"
	check(found,"invalid target holds, never retargets")
	var result:Dictionary=session.commit_turn()
	check(result.accepted and result.has("companion_order_notice"),"invalid reservation explains cancellation")
	check(not session.has_companion_order(companion),"invalid reservation cleared")
	# Real UI entry/exit leaves world time untouched.
	session=Fixtures.new()._engaged();state=session.sim.world.party_encounter
	companion=state.active_party_member_ids[1]
	root.size=Vector2i(360,640)
	var sandbox=Sandbox.new();sandbox.size=Vector2(360,640)
	sandbox.initialize_for_headless_test(session);root.add_child(sandbox)
	await process_frame;await process_frame
	sandbox._open_member_detail(companion)
	check(sandbox.member_order_button.visible,"detail entry available")
	before_time=session.sim.world.world_time
	sandbox._begin_companion_order_edit()
	await process_frame
	check(sandbox.companion_order_editor.visible,"editor visible")
	sandbox.companion_order_editor._select("HOLD")
	sandbox.companion_order_editor._select("CONFIRM")
	await process_frame
	check(session.sim.world.world_time==before_time,"UI only reserves")
	check(session.has_companion_order(companion),"UI reservation connected")
	check(not sandbox.companion_order_editor.visible,"editor returns to automatic mode")
	sandbox.queue_free();await process_frame
	for failure in failures:printerr(failure)
	print("Companion one-shot orders: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)
