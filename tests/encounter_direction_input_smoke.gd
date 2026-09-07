extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
func _init()->void:call_deferred("run")
func run()->void:
	var session=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
	var ui=Sandbox.new();ui.initialize_for_headless_test(session,true);root.add_child(ui)
	await process_frame
	ui._on_product_direction(Vector2i.RIGHT);await process_frame
	var status:Dictionary=session.party_status()
	if status.safe_phase!="ENGAGED":printerr("fixture did not enter combat");quit(1);return
	var hero:int=status.protagonist_id
	var before:Vector2i=session.sim.world.entities[hero].position
	# Stale inspection must not become the origin/owner of the next movement.
	ui.selected_member_id=999
	ui._on_product_direction(Vector2i.LEFT);await process_frame;await process_frame
	var ok:bool=session.sim.world.entities[hero].position==before+Vector2i.LEFT and ui.selected_member_id==hero
	ui.queue_free();await process_frame
	print("Encounter direction input: ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
