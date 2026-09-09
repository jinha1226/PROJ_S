extends SceneTree
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(value:bool,message:String)->void:
	if not value:failures.append(message);printerr("FAIL ",message)
func settle()->void:
	for i in range(6):await process_frame
func click_button(button:Button)->void:
	var center:=button.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=center;root.push_input(motion,true)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT
		event.position=center;event.pressed=pressed;root.push_input(event,true)
		await process_frame
	await settle()
func run()->void:
	root.size=Vector2i(360,800)
	root.content_scale_size=Vector2i(360,800)
	var ui=Sandbox.new();ui.set_personality_entropy_source_for_headless_test(func():return 20260828)
	root.add_child(ui);await settle();ui._commit_species_picker("human");await settle()
	for dimensions in [Vector2i(320,640),Vector2i(360,800),Vector2i(430,932)]:
		root.size=dimensions;root.content_scale_size=dimensions;await settle()
		ui._on_town_facility_selected("BASE");await settle()
		var gate:=ui.find_child("TownNavGATE",true,false) as Button
		check(gate!=null,"hub has expedition CTA")
		if gate!=null:
			print("HUB ",dimensions," CTA=",gate.get_global_rect()," scroll=",ui.info_scroll.size)
			check(gate.get_global_rect().end.y<=dimensions.y,"hub departure fits without scrolling at "+str(dimensions))
		for id in ["INN","MARKET","CLINIC","HOUSE"]:
			var b:=ui.find_child("TownNav"+id,true,false) as Button
			check(b!=null and b.size.x>=48 and b.size.y>=48,"shortcut touch target "+id)
			if b!=null:check(b.get_global_rect().end.x<=dimensions.x,"shortcut fits width")
		check(ui.find_child("TownResidentDetail",true,false)==null,"hub does not dump resident actions")
		check(ui.find_child("SelectedMemberDetail",true,false)==null,"no combat inspector in town")
	root.size=Vector2i(360,800);root.content_scale_size=Vector2i(360,800);await settle()
	await click_button(ui.find_child("TownNavMARKET",true,false) as Button)
	check(ui.town_facility_id=="MARKET","pointer reaches facility shortcut through its icon and label")
	ui._on_town_facility_selected("INN");await settle()
	var panel=ui.find_child("TownLifePanel",true,false)
	check(panel!=null and panel.screen=="INN","inn is a separate screen")
	var id:=int(ui.town_ui_state.resident)
	var talk:=ui.find_child("TownTALK%d"%id,true,false) as Button
	check(talk!=null and not talk.disabled,"selected resident can talk")
	if talk!=null:talk.pressed.emit();await settle()
	check(int(ui.town_ui_state.resident)==id,"talk refresh retains selected resident")
	talk=ui.find_child("TownTALK%d"%id,true,false) as Button
	check(talk!=null and talk.disabled,"talk feedback reflects committed state")
	check(ui.find_children("TownResidentDetail","",true,false).size()==1,"one resident action card only")
	var filter:=ui.find_child("TownFilterCITIZENS",true,false) as Button
	check(filter==null,"civic residents live at workplaces, not the inn roster")
	for screen in ["CLINIC","ARMORY","HOUSE","GATE","STORAGE","MARKET"]:
		ui._on_town_facility_selected(screen);await settle()
		check(ui.find_child("TownFacilityPanel",true,false)!=null,"dedicated service "+screen)
		check(ui.deck.get_global_rect().end.x<=361,"service width "+screen)
		var back:=ui.find_child("TownLifeBack",true,false) as Button
		check(back!=null and back.size.y>=48,"consistent back target")
	var stock:Array=ui.session.town_market_stock()
	var price:=0
	for item in stock:
		if item.definition_id=="POTION_HEALING":price=int(item.price)
	var gold:int=ui.session.town_gold()
	var buy:=ui.find_child("TownMarketBuyPOTION_HEALING",true,false) as Button
	check(buy!=null and not buy.disabled,"market purchase available")
	if buy!=null:await click_button(buy)
	check(ui.session.town_gold()==gold-price,"new card purchases through canonical market")
	var sell:=ui.find_child("TownMarketTabSELL",true,false) as Button
	sell.pressed.emit();await settle()
	check(ui.find_child("TownSellTIMBER",true,false)!=null,"sale tab has real resource actions")
	check(ui.find_child("TownMarketBuyPOTION_HEALING",true,false)==null,"buy and sell do not crowd one screen")
	ui._on_town_facility_selected("BASE");await settle()
	var map=ui.find_child("PublicTownMap",true,false)
	map.building_selected.emit("LODGE");await settle()
	check(ui.town_facility_id=="INN","map and shortcut use same facility navigation")
	ui._on_town_facility_selected("BASE");await settle()
	map=ui.find_child("PublicTownMap",true,false);map.building_selected.emit("STORAGE");await settle()
	check(ui.town_facility_id=="STORAGE","public storage has its own workplace and stock")
	check(ui.session.sim.world.world_state_error().is_empty(),"UI actions preserve canonical state")
	ui.queue_free();await process_frame
	print("TOWN_NAVIGATION_ACCEPTANCE ","PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
