extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Shell=preload("res://playtest/party_encounter_sandbox.gd")
const Mystery=preload("res://sim/mystery_consumables.gd")
const Inventory=preload("res://sim/inventory_state.gd")
const Item=preload("res://sim/item_instance.gd")
var failures:Array[String]=[]
func _init():run.call_deferred()
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	root.size=Vector2i(390,844)
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.town_life_command({"action":"START"}).accepted,"start")
	check(s.depart_town().accepted,"depart")
	var w=s.sim.world;var hero:int=w.party_control_actor_id();var inv=w.inventory_of(hero)
	var items:Array=inv.backpack.duplicate()
	for id in ["POTION_MYSTERY_HEAL","POTION_MYSTERY_MANA","SCROLL_MYSTERY_HEAL","SCROLL_MYSTERY_MANA"]:items.append(Item.new("UI_"+id,id,2))
	items.append(Item.new("UI_POISON","POTION_MYSTERY_POISON",2))
	w.item_state.inventory_rows[hero]=Inventory.new(items,inv.equipped)
	var ui=Shell.new();ui.initialize_for_headless_test(s,false);root.add_child(ui);ui.set_process(false)
	ui._open_hero_detail_tab("ITEM")
	for id in ["POTION_MYSTERY_HEAL","POTION_MYSTERY_MANA","SCROLL_MYSTERY_HEAL","SCROLL_MYSTERY_MANA"]:
		ui._on_item_row_selected("UI_"+id,"")
		var row:Dictionary=s.protagonist_inventory().backpack_rows.filter(func(r):return r.definition_id==id)[0]
		check(ui._item_stats_text(row).contains("미감정"),"hidden stats")
		check(not ui._item_description_text(row).contains("회복"),"hidden description")
		check(ui.member_item_use_button.visible and not ui.member_item_use_button.disabled,"usable unidentified")
		check(ui.member_item_use_button.text==("읽기" if id.begins_with("SCROLL") else "마시기"),"correct action verb")
	for i in range(6):await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/mystery-items-mobile.png")
	check(s.use_inventory_item("UI_SCROLL_MYSTERY_MANA").accepted,"identify from UI selection")
	ui._refresh();ui._on_item_row_selected("UI_SCROLL_MYSTERY_MANA","")
	var row:Dictionary=s.protagonist_inventory().backpack_rows.filter(func(r):return r.definition_id=="SCROLL_MYSTERY_MANA")[0]
	check(row.identified and ui._item_stats_text(row).contains("MP +10"),"identified effect revealed")
	check(s.use_inventory_item("UI_POISON").accepted,"discover poison")
	ui._refresh();ui._on_item_row_selected("UI_POISON","")
	check(ui.member_item_use_button.visible,"known utility usable")
	check(ui.consumable_status_label.text.contains("독"),"poison duration shown")
	var before:Dictionary=s.sim.snapshot()
	ui._on_item_use_selected()
	var picker=ui.find_child("ConsumableTargetPicker",true,false)
	check(picker!=null,"target picker opens")
	for i in range(5):await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/consumable-target-mobile.png")
	if picker!=null:picker.hide()
	await process_frame
	check(s.sim.snapshot()==before,"cancel picker consumes nothing")
	ui.queue_free();await process_frame
	print("MYSTERY ITEMS UI ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
