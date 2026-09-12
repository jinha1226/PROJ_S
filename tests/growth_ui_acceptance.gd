extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Shell=preload("res://playtest/party_encounter_sandbox.gd")
var errors:Array[String]=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("FAIL ",label)
func run()->void:
	root.size=Vector2i(390,844)
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var ui=Shell.new();ui.initialize_for_headless_test(session,false);root.add_child(ui);ui.set_process(false)
	ui.show_species_picker_for_new_run();ui._commit_species_picker("human");ui._refresh()
	ui._open_hero_detail_tab("SKILL")
	for i in range(6):await process_frame
	var mastery=ui.mastery_panel;var abilities=ui.member_ability_window
	check(mastery.visible and abilities.visible,"both sections on same page")
	var grid=mastery.get_node("MasteryGrid")
	check(grid.columns==2 and grid.get_child_count()==4,"2x2 mastery")
	check(abilities.slot_grid.columns==6,"six-slot ability strip")
	for row in mastery.rows.values():check(row.button.size.x>=44 and row.button.size.y>=44,"touch target")
	check(grid.get_child(0).position.y==grid.get_child(1).position.y,"first row aligned")
	check(grid.get_child(2).position.y>grid.get_child(0).position.y,"second row below")
	check(mastery.get_global_rect().end.x<=ui.size.x,"mastery fits mobile width")
	check(abilities.slot_grid.get_global_rect().end.x<=ui.size.x,"slots fit mobile width")
	var before:Dictionary=session.sim.snapshot()
	# UI-only fixture exercises a not-yet-implemented essence without granting it.
	var items:Array=[{"instance_id":"PREVIEW_ONLY","label":"포식 신경","quantity":1,
		"effect_preview":{"label":"포식 신경","planned":true,"passive":"다친 적에게 근접 추가 피해","active":"약점을 노리는 일격"}}]
	abilities.update_rows(session.ability_binding_rows(session.sim.world.party_control_actor_id()),items)
	abilities._select_item("PREVIEW_ONLY")
	check(abilities.mode_rows.get_child_count()==2,"both mode descriptions")
	check(abilities.picker.get_child(0).get_child(1).disabled,"unimplemented absorption disabled")
	abilities._bind_item("PREVIEW_ONLY")
	check(abilities.pending_instance_id.is_empty(),"cannot consume planned essence")
	check(before==session.sim.snapshot(),"UI observation never mutates simulation")
	for i in range(5):await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/growth-ui-mobile.png")
	root.size=Vector2i(360,740)
	for i in range(5):await process_frame
	check(abilities.slot_grid.get_global_rect().end.x<=ui.size.x,"slots fit smaller mobile")
	ui.queue_free();await process_frame
	print("GROWTH UI: ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
