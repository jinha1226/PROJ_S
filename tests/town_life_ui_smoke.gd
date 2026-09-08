extends SceneTree
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL ",message)
func run()->void:
	root.size=Vector2i(360,800)
	var ui=Sandbox.new();ui.set_personality_entropy_source_for_headless_test(func():return 20260828)
	root.add_child(ui)
	await process_frame;await process_frame
	check(ui.session.town_life_enabled(),"real new-game flow starts town life")
	if ui.session.sim==null:quit(1);return
	check(ui.session.sim.world.party_encounter.active_party_member_ids.size()==1,"real UI starts solo")
	check(not ui.grid.visible and not ui.cards.visible,"town does not reserve dungeon/card space")
	var panel=ui.find_child("TownLifePanel",true,false)
	check(panel!=null,"inn panel mounted")
	var map=ui.find_child("PublicTownMap",true,false)
	check(map!=null,"finished public town is visible")
	if map!=null:check(map._overview.residents.size()==16,"sixteen residents visible on town map")
	var market:=ui.find_child("TownNavMARKET",true,false) as Button
	check(market!=null and market.size.y>=48,"market touch target")
	if market!=null:market.pressed.emit()
	await process_frame;await process_frame
	check(ui.find_child("TownMarketBuyPOTION_HEALING",true,false)!=null,"public market works without owning clinic/market")
	ui._on_town_facility_selected("INN");await process_frame;await process_frame
	var filters:=ui.find_child("TownFilterCITIZENS",true,false) as Button
	if filters!=null:filters.pressed.emit()
	await process_frame;await process_frame
	check(ui.find_child("TownResidentFilters",true,false)!=null,"resident category survives interaction")
	ui._on_town_facility_selected("GATE");await process_frame;await process_frame
	var depart:=ui.find_child("TownDepart",true,false) as Button
	check(depart!=null and not depart.disabled,"solo departure available")
	if depart!=null:depart.pressed.emit()
	await process_frame;await process_frame
	check(ui.session.sim.world.party_encounter.expedition_cycle.phase=="DUNGEON","real UI departs")
	var visitors:Array=preload("res://sim/town_population_rules.gd").locations(ui.session.sim.world)
	check(visitors.size()==8,"dungeon NPC population appears")
	if not visitors.is_empty():
		var id:=int(visitors[0].entity_id)
		ui._on_actor(id);await process_frame;await process_frame
		check(ui.member_detail_modal.visible,"neutral actor opens information")
		check(ui.member_detail_candidate_action.text=="식량 1개 나누기","visitor action replaces obsolete recruitment UI")
		check(not ui.member_detail_attack.visible,"neutral visitor is not an attack command")
	ui._on_product_menu_id(1);await process_frame;await process_frame
	check(ui.session.town_life_enabled(),"new game menu preserves inn progression entry point")
	check(ui.session.sim.world.party_encounter.expedition_cycle.phase=="TOWN","new game returns to town")
	check(ui.session.sim.world.party_encounter.active_party_member_ids.size()==1,"new game starts solo")
	ui.queue_free();await process_frame
	print("TOWN_LIFE_UI_SMOKE ","PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
