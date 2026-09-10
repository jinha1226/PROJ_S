extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL ",message)
func run()->void:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var ui=Sandbox.new();ui.size=Vector2(390,800)
	ui.initialize_for_headless_test(session,true)
	root.add_child(ui);ui.set_process(false)
	for i in range(3):await process_frame
	var before:Dictionary=session.sim.snapshot()
	for i in range(100):ui._tick_autonomous_battle(0.1)
	check(session.sim.snapshot()==before,"ten seconds without input do not advance world")
	check(session.party_status().view_mode=="EXPLORATION","single exploration surface")
	check(ui.product_tactics_button!=null and not ui.product_tactics_button.disabled,"orders enabled outside encounters")
	ui._on_product_tactics()
	for i in range(ui.product_tactics_popup.item_count):
		check(not ui.product_tactics_popup.is_item_disabled(i),"order menu is available")
	ui.product_tactics_popup.hide()
	ui._on_product_tactic_selected(13)
	check(session.FieldRules.formation(session.sim.world)=="WEDGE","formation menu applies wedge")
	var hero:int=session.sim.world.party_control_actor_id()
	var allies:Array=session.sim.world.party_encounter.active_party_member_ids.duplicate();allies.erase(hero)
	ui._on_actor(allies[0])
	check(session.sim.world.party_control_actor_id()==allies[0],"map companion tap changes control")
	ui._on_compact_member_card_pressed(hero,"hero")
	check(session.sim.world.party_control_actor_id()==hero,"portrait tap changes control back")
	var time_before:int=session.sim.world.world_time
	ui._on_product_tactic_selected(3)
	check(session.sim.world.world_time==time_before+100,"cease attack spends one turn")
	time_before=session.sim.world.world_time
	ui._on_product_wait_guard()
	check(session.sim.world.world_time==time_before+100,"wait button spends exactly one turn")
	check(ui.find_child("BattleTimelineBar",true,false)==null,"no realtime battle timeline")
	ui.queue_free();await process_frame
	print("FIELD UI: ","PASS" if failures.is_empty() else "FAIL", " ",failures)
	quit(0 if failures.is_empty() else 1)
