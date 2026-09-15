extends SceneTree

const Session=preload("res://playtest/party_playtest_session.gd")
const Shell=preload("res://playtest/party_encounter_sandbox.gd")
const Items=preload("res://sim/world_item_operations.gd")

var failures:Array[String]=[]

func _init()->void:
	run.call_deferred()

func check(ok:bool,label:String)->void:
	if not ok:
		failures.append(label)
		printerr("FAIL ",label)

func find_button_with_text(node:Node,needle:String)->Button:
	for child in node.get_children():
		if child is Button and str(child.text).contains(needle):return child
		var nested:=find_button_with_text(child,needle)
		if nested!=null:return nested
	return null

func run()->void:
	root.size=Vector2i(390,844)
	var s=Session.new(44,20260828,Session.REGRESSION_SCENARIO_ID)
	var w=s.sim.world
	var party=w.party_encounter
	var hero:int=w.party_control_actor_id()
	var companion:int=party.party_member_ids[1]
	if companion not in party.active_party_member_ids:party.active_party_member_ids.append(companion)
	party.member(companion).presence="GROUPED"
	if not w.occupies_tile(companion):w.combatant_states[companion].life_state="ACTIVE"
	var grant:Dictionary=Items.commit_grant(w,hero,"POTION_HEALING",2,w.entities[hero].position,"RECIPIENT_UI_TEST")
	var item_id:String=str(grant.get("instance_id",""))
	check(not item_id.is_empty(),"healing potion fixture granted")
	var ui=Shell.new()
	ui.initialize_for_headless_test(s,false)
	root.add_child(ui)
	ui.set_process(false)
	ui._open_member_detail(hero,"ITEM")
	ui._on_item_row_selected(item_id,"")
	var hero_hp:int=w.entities[hero].health
	var quantity:int=w.inventory_of(hero).item(item_id).quantity
	ui._on_item_use_selected()
	var picker=ui.find_child("ConsumableTargetPicker",true,false)
	check(picker!=null,"recipient picker opens from item use")
	if picker!=null:
		var companion_button:=find_button_with_text(picker,str(w.entities[companion].display_name))
		check(companion_button!=null,"companion appears as recipient")
		if companion_button!=null:companion_button.pressed.emit()
	await process_frame
	w=s.sim.world
	party=w.party_encounter
	check(ui.notice_text.contains("체력이 가득"),"selected full-health companion is evaluated")
	check(w.entities[hero].health==hero_hp,"hero is unchanged when companion selected")
	var remaining=w.inventory_of(hero).item(item_id)
	check(remaining!=null and remaining.quantity==quantity,"refused companion potion is not consumed")
	var before_cancel:Variant=s.sim.snapshot()
	ui.member_item_selected_id=item_id
	ui._on_item_use_selected()
	picker=ui.find_child("ConsumableTargetPicker",true,false)
	check(picker!=null,"recipient picker reopens")
	if picker!=null:picker.hide()
	await process_frame
	check(s.sim.snapshot()==before_cancel,"cancel preserves party state and item")
	w=s.sim.world
	party=w.party_encounter
	grant=Items.commit_grant(w,hero,"ESSENCE_PREDATOR_NERVE",1,w.entities[hero].position,"RECIPIENT_ABILITY_UI_TEST")
	var essence_id:String=str(grant.get("instance_id",""))
	ui._refresh()
	ui._on_item_row_selected(essence_id,"")
	check(ui.member_item_use_button.visible,"special part is usable in item detail")
	check(ui.member_item_use_button.text=="먹기","special part uses eat action")
	check(ui.member_item_popover_body.text.contains("패시브") and ui.member_item_popover_body.text.contains("액티브"),"special part previews acquired ability")
	ui.member_item_use_button.pressed.emit()
	picker=ui.find_child("ConsumableTargetPicker",true,false)
	check(picker!=null,"special-part recipient picker opens")
	if picker!=null:
		var essence_button:=find_button_with_text(picker,str(w.entities[companion].display_name))
		check(essence_button!=null,"companion appears for special part")
		if essence_button!=null:essence_button.pressed.emit()
	await process_frame
	check("PREDATOR_NERVE" in party.member(companion).bound_ability_ids,"selected companion receives special-part ability")
	check("PREDATOR_NERVE" not in party.member(hero).bound_ability_ids,"hero does not receive companion's special part")
	check(preload("res://sim/party_bag_rules.gd").owner(w,essence_id)==-1,"special part consumed once")
	ui.queue_free()
	await process_frame
	print("PARTY CONSUMABLE RECIPIENT UI: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
