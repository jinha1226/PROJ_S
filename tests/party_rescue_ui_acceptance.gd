extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL ",message)
func run()->void:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	session.enable_party_rescue()
	var ui=Sandbox.new();ui.initialize_for_headless_test(session,true)
	root.add_child(ui);ui.set_process(false)
	var w=session.sim.world;var hero:int=w.party_encounter.protagonist_id
	# Presentation-only fixture; mechanics and causal history have separate tests.
	w.entities[hero].health=0
	w.combatant_states[hero].life_state="DOWNED";w.combatant_states[hero].downed_resolve_at=1000
	for width in [450,320]:
		root.size=Vector2i(width,800);ui.size=Vector2(width,800)
		ui._refresh_rescue_panel()
		for i in range(3):await process_frame
		check(ui.rescue_panel.visible,"downed panel visible")
		check(ui.rescue_panel.position.x+ui.rescue_panel.size.x<=width,"rescue panel fits width "+str(width))
		check(w.party_control_actor_id()!=hero,"living companion controls downed protagonist")
		for child in ui.rescue_panel.rows.get_children():
			if child is Button:check(child.size.y>=44,"touch target at least 44 pixels")
	var time_before:int=w.world_time
	for i in range(100):ui._tick_autonomous_battle(0.1)
	check(w.world_time==time_before,"downed render time never advances grace")
	ui.queue_free();await process_frame
	print("PARTY RESCUE UI: ","PASS" if failures.is_empty() else "FAIL",failures)
	quit(0 if failures.is_empty() else 1)
