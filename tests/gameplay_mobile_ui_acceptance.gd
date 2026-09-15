extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Shell=preload("res://playtest/party_encounter_sandbox.gd")
const Summary=preload("res://playtest/meaningful_event_summary.gd")
var failures:Array[String]=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func run()->void:
	var history={"groups":[{"step_index":2,"rows":[
		{"type":"combat.physical_damage","message":"칼날이 고블린의 팔을 베었다."},
		{"type":"combat.physical_damage","message":"칼날이 고블린의 팔을 베었다."},
		{"type":"status.applied","message":"출혈 · 팔 기능 저하"},
		{"type":"enemy.awareness_changed","message":"고블린이 뒤로 물러난다."}]},
		{"step_index":1,"rows":[{"type":"entity.died","message":"이전 전투"}]}]}
	var summary:String=Summary.summarize(history,func(row):return row.message,func(_s):return false)
	check(summary=="칼날이 고블린의 팔을 베었다.\n출혈 · 팔 기능 저하\n고블린이 뒤로 물러난다.","action consequence reaction, unique newest turn")
	history.groups.append({"step_index":3,"rows":[{"type":"item.picked_up","message":"물약을 주웠다."}]})
	check(Summary.summarize(history,func(row):return row.message,func(_s):return false)=="물약을 주웠다.","new loot replaces old combat")
	check(Summary.summarize(history,func(row):return row.message,func(_s):return false,"휴식 중").begins_with("휴식 중\n"),"rest progress remains visible")
	var portrait=preload("res://playtest/compact_party_portrait.gd").new()
	portrait.actor={"life_state":"DOWNED","readiness":"전투불능 · 9턴","stress_band_label":"평온"}
	check(portrait.mobile_condition_text()=="전투불능 · 9턴","downed timer takes priority over mood")
	portrait.free()
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var ui=Shell.new();ui.initialize_for_headless_test(session,true)
	root.add_child(ui);ui.set_process(false)
	var snapshot:Dictionary=session.sim.snapshot()
	for dimensions in [Vector2i(320,640),Vector2i(390,844),Vector2i(450,800)]:
		root.size=dimensions;ui._product_skills_open=false;ui._refresh()
		for i in range(5):await process_frame
		ui._refresh()
		for i in range(3):await process_frame
		check(not ui.hero_skill_row.visible,"skills collapsed by default")
		check(not ui.build_label.visible,"build stamp cannot obscure dock labels")
		check(ui.grid.size.y>=dimensions.y*0.5,"map dominates "+str(dimensions))
		check(ui.event_label.max_lines_visible==3,"three event lines")
		var rect:Rect2=ui.get_global_rect()
		for button in ui.combat_action_dock.get_children():
			if button is Button and button.is_visible_in_tree():
				check(button.size.x>=44 and button.size.y>=44,"44px touch target "+button.name)
				check(rect.encloses(button.get_global_rect()),"dock fits "+str(dimensions)+" "+button.name)
		ui._activate_product_control("ProductSkills");ui._refresh()
		for i in range(3):await process_frame
		check(ui.hero_skill_row.visible and ui.hero_skill_row.get_child_count()>0,"touch opens equipped skills")
		check(rect.encloses(ui.hero_skill_row.get_global_rect()),"skills fit viewport")
		ui._activate_product_control("ProductSkills");ui._refresh()
		for i in range(3):await process_frame
		if "--capture" in OS.get_cmdline_user_args():
			ui.event_label.text="칼날이 고블린의 팔을 베었다.\n출혈 · 팔 기능 저하\n고블린이 뒤로 물러난다."
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/gameplay-mobile-%d.png"%dimensions.x)
	check(session.sim.snapshot()==snapshot,"layout and skills drawer never advance simulation")
	# Projection fixture only: make an existing enemy visible to test dock policy.
	var status:Dictionary=session.party_status();var enemy:int=session.sim.world.party_encounter.enemy_ids[0]
	status.visible_enemy_ids=[enemy];status.enemies_in_view=[enemy]
	ui._sync_product_control_state(status)
	check(ui.product_attack_button.visible and not ui.product_auto_button.visible,"combat exposes attack instead of explore")
	status.visible_enemy_ids=[];status.enemies_in_view=[];ui._sync_product_control_state(status)
	check(not ui.product_attack_button.visible and ui.product_auto_button.visible,"exploration exposes explore")
	ui.queue_free();await process_frame
	print("GAMEPLAY MOBILE UI: ","PASS" if failures.is_empty() else "FAIL",failures)
	quit(0 if failures.is_empty() else 1)
