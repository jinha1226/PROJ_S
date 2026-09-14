extends SceneTree
const Fixture=preload("res://tests/round_combat_fixture.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
var failures:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func run()->void:
	var s=Fixture.create();s.scenario_id=s.DUO_SCENARIO_ID
	var ui=Sandbox.new()
	ui.size=Vector2(390,844);ui.initialize_for_headless_test(s,true);root.add_child(ui);ui.set_process(false)
	ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	for viewport_size in [Vector2i(360,800),Vector2i(390,844)]:
		root.size=viewport_size;ui.size=Vector2(viewport_size)
		ui._request_refresh()
		for i in range(4):await process_frame
		check(ui.round_order_bar!=null and ui.round_order_bar.visible,"round order visible "+str(viewport_size))
		check(not ui.battle_enemy_strip.visible,"duplicate enemy list hidden")
		check(ui.product_rest_button.text=="[진행]" and not ui.product_rest_button.disabled,"round confirm button available")
		check(ui.round_order_bar.line.get_child_count()==s.round_status().order.size(),"all planned actors listed")
	var w=s.sim.world;var before:int=w.world_time
	var revision:int=w.party_encounter.round_combat.plan_revision
	ui._focus_battle_enemy(w.party_encounter.enemy_ids[0])
	check(w.party_encounter.round_combat.plan_revision==revision,"enemy inspection does not rewrite ally plan")
	var companion:int=w.party_encounter.active_party_member_ids[1]
	ui._select_member(companion,"동료")
	check(s.round_status().selected_actor_id==companion,"portrait selects companion plan")
	ui._on_product_wait_guard()
	check(w.world_time==before,"editing does not advance time")
	check(w.party_encounter.round_combat.plans[str(companion)].source=="USER","wait edits companion plan")
	ui._on_product_rest()
	check(s.sim.world.world_time==before+100 or s.round_status().phase=="INTERRUPTED","progress executes round or pauses safely")
	ui.queue_free();await process_frame
	print("ROUND UI: ",failures)
	quit(0 if failures.is_empty() else 1)
