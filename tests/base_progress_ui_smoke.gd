extends SceneTree

const BasePanel=preload("res://playtest/base_progress_panel.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Session=preload("res://playtest/party_playtest_session.gd")

var failures:Array[String]=[]


func _init()->void:
	call_deferred("_run")


func _run()->void:
	for viewport_width in [360,390]:
		root.size=Vector2i(viewport_width,640)
		await process_frame
		await _check_panel(viewport_width)
	_check_cache_marker_contract()
	await _check_duo_sandbox_flow()
	await _check_species_confirm_base_first()
	if failures.is_empty():
		print("PASS base progress UI smoke: 360/390 portrait, direct build, DUO return/town/depart, actions and cache marker")
		quit(0)
	else:
		for failure in failures:printerr("FAIL ",failure)
		quit(1)


func _check_panel(viewport_width:int)->void:
	var scroll:=ScrollContainer.new();scroll.name="BaseSmokeScroll"
	scroll.position=Vector2(12,12);scroll.size=Vector2(viewport_width-24,616)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;root.add_child(scroll)
	var panel=BasePanel.new();panel.name="BaseSmokePanel";panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panel.configure_build_assessment(func(type_id:String,origin:Vector2i):
		return {"accepted":origin==Vector2i(6,6),"type_id":type_id,
			"tile_origin":[origin.x,origin.y],"footprint":[3,3],
			"message":"건설 가능" if origin==Vector2i(6,6) else "다른 시설과 겹칩니다."})
	scroll.add_child(panel);panel.present(_overview(),false)
	await process_frame;await process_frame
	_check(panel.size.x<=float(viewport_width-24)+0.1,
		"%dpx town panel overflowed horizontally (%.1f)"%[viewport_width,panel.size.x])
	for button_value in panel.find_children("*","Button",true,false):
		var button:=button_value as Button
		_check(button.size.y>=48.0,"%dpx %s touch target below 48px"%[viewport_width,button.name])
	var storage:=panel.find_child("BaseFacilityUpgradeSTORAGE",true,false) as Button
	_check(storage!=null and not storage.disabled,"%dpx affordable storage upgrade disabled"%viewport_width)
	_check(panel.find_child("BaseFacilityUpgradeLODGE",true,false)==null \
		and panel.find_child("BaseFacilityUpgradeCLINIC",true,false)==null,
		"%dpx map-first panel rendered unselected facility cards"%viewport_width)
	var settlement=panel.find_child("BaseSettlementMap",true,false)
	_check(settlement!=null and settlement.size.y>=300.0,
		"%dpx settlement map is not visually dominant"%viewport_width)
	if settlement!=null:
		for building_id in ["STORAGE","LODGE","GATE"]:
			var hit:=settlement.find_child("SettlementHit%s"%building_id,true,false) as Button
			_check(hit!=null and hit.size.x>=48.0 and hit.size.y>=48.0,
				"%dpx %s landmark target below 48px"%[viewport_width,building_id])
	var upgrade_ids:Array[String]=[];var service_ids:Array[String]=[];var sells:Array=[]
	panel.upgrade_requested.connect(func(id:String):upgrade_ids.append(id))
	panel.service_requested.connect(func(id:String):service_ids.append(id))
	panel.sell_requested.connect(func(id:String,amount:int):sells.append([id,amount]))
	storage.pressed.emit();(panel.find_child("BaseTradeSellTIMBER",true,false) as Button).pressed.emit()
	(settlement.find_child("SettlementHitLODGE",true,false) as Button).pressed.emit()
	await process_frame
	var lodge:=panel.find_child("BaseFacilityUpgradeLODGE",true,false) as Button
	_check(lodge!=null and lodge.disabled,"%dpx unaffordable lodge upgrade enabled"%viewport_width)
	_check(panel.find_child("BaseFacilityReasonLODGE",true,false)!=null,
		"%dpx disabled upgrade omitted visible reason"%viewport_width)
	(panel.find_child("BaseFacilityServiceLODGE",true,false) as Button).pressed.emit()
	var stock:=panel.find_child("BaseStock",true,false) as Label
	var carried:=panel.find_child("BaseCarried",true,false) as Label
	_check(stock!=null and "안전" in stock.text and "/8" not in stock.text,
		"%dpx secured stock is not clearly unbounded/safe"%viewport_width)
	_check(carried==null,"%dpx town ledger wasted space on empty haul risk"%viewport_width)
	_check(upgrade_ids==["STORAGE"],"%dpx upgrade signal payload/once contract"%viewport_width)
	_check(service_ids==["LODGE"],"%dpx service signal payload/once contract"%viewport_width)
	_check(sells==[["TIMBER",1]],"%dpx sell signal explicit amount contract"%viewport_width)
	panel.present(_overview(),false,"STORAGE");await process_frame
	var construction:Array=[]
	panel.construction_confirm_requested.connect(func(id:String,origin:Vector2i):
		construction.append([id,origin]))
	(panel.find_child("BaseConstructionOpen",true,false) as Button).pressed.emit();await process_frame
	(panel.find_child("BaseBuildOptionCLINIC",true,false) as Button).pressed.emit();await process_frame
	var invalid_confirm:=panel.find_child("BasePlacementConfirm",true,false) as Button
	_check(invalid_confirm!=null and invalid_confirm.disabled \
		and "겹칩니다" in (panel.find_child("BasePlacementFeedback",true,false) as Label).text,
		"%dpx invalid ghost omitted red/blocked confirmation state"%viewport_width)
	settlement=panel.find_child("BaseSettlementMap",true,false)
	settlement.tile_pressed.emit(Vector2i(6,6));await process_frame
	var confirm:=panel.find_child("BasePlacementConfirm",true,false) as Button
	_check(confirm!=null and not confirm.disabled,"%dpx valid tile did not enable explicit confirm"%viewport_width)
	confirm.pressed.emit();confirm.pressed.emit()
	_check(construction==[["CLINIC",Vector2i(6,6)]],
		"%dpx construction confirm was missing or duplicated"%viewport_width)
	var dungeon_overview:=_overview();dungeon_overview["phase"]="DUNGEON"
	panel.present(dungeon_overview,true);await process_frame
	_check(panel.find_child("BaseFacilityServiceLODGE",true,false)==null,
		"%dpx dungeon preview exposed town service"%viewport_width)
	var preview_upgrade:=panel.find_child("BaseFacilityUpgradeSTORAGE",true,false) as Button
	var base_return:=panel.find_child("BaseReturn",true,false) as Button
	carried=panel.find_child("BaseCarried",true,false) as Label
	_check(carried!=null and "손실 위험" in carried.text and "3/8" in carried.text,
		"%dpx dungeon carried haul risk/capacity missing"%viewport_width)
	_check(preview_upgrade!=null and preview_upgrade.disabled,
		"%dpx dungeon preview allowed upgrade"%viewport_width)
	_check(base_return!=null and base_return.disabled and base_return.size.y>=48.0,
		"%dpx unavailable safe return state/target incorrect"%viewport_width)
	scroll.queue_free();await process_frame


func _check_cache_marker_contract()->void:
	var observation:={"cells":[
		{"visibility_state":"VISIBLE","resource_cache":{"available":true}},
		{"visibility_state":"MEMORY","resource_cache":{"available":true}},
		{"visibility_state":"VISIBLE","resource_cache":{"available":false}},
	]}
	var sandbox=Sandbox.new();sandbox._decorate_visible_resource_caches(observation)
	_check(str(observation.cells[0].get("ground_item_glyph",""))=="*",
		"visible cache omitted material marker")
	_check(not observation.cells[1].has("ground_item_glyph"),
		"remembered cache leaked a live marker")
	_check(not observation.cells[2].has("ground_item_glyph"),
		"depleted cache retained a marker")
	sandbox.free()


func _check_duo_sandbox_flow()->void:
	root.size=Vector2i(360,640)
	var session=Session.new(44,20260908,Session.DUO_SCENARIO_ID)
	var sandbox=Sandbox.new();sandbox.name="BaseIntegrationSandbox";sandbox.size=Vector2(360,640)
	sandbox.initialize_for_headless_test(session,false)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);sandbox.size=Vector2(360,640)
	root.add_child(sandbox);await process_frame;await process_frame
	_check(str(session.party_status().get("view_mode",""))=="EXPLORATION",
		"default DUO did not start in direct exploration")
	sandbox._open_base_modal();await process_frame
	_check(sandbox.base_modal.visible and sandbox.grid.modal_open,
		"dungeon base preview did not claim modal input")
	var return_button:=sandbox.base_preview.find_child("BaseReturn",true,false) as Button
	_check(return_button!=null and not return_button.disabled,
		"entry base preview did not offer safe return")
	var expedition_before:=int(session.expedition_cycle_status().get("expedition_index",-1))
	if return_button!=null and not return_button.disabled:return_button.pressed.emit()
	await process_frame;await process_frame
	_check(str(session.party_status().get("view_mode",""))=="TOWN" \
		and int(session.expedition_cycle_status().get("expedition_index",-1))==expedition_before,
		"safe return did not enter town exactly once")
	_check(not sandbox.base_modal.visible and not sandbox.grid.modal_open,
		"safe return left a click-blocking preview open")
	_check(sandbox.town_facility_id=="BASE" \
		and sandbox.find_child("TownBaseProgress",true,false)!=null,
		"town did not foreground base progression")
	_check(sandbox.find_child("TownGuildHallStations",true,false)==null,
		"DUO base retained the old six-button town grid above the map")
	var town_base=sandbox.find_child("TownBaseProgress",true,false)
	var town_map=town_base.find_child("BaseSettlementMap",true,false) if town_base!=null else null
	_check(not sandbox.cards.visible,"base screen still reserved the 160px party-card strip")
	_check(town_map!=null and town_map.get_global_rect().end.y \
		<=sandbox.info_scroll.get_global_rect().end.y+1.0,
		"settlement map is not visible above the 360x640 fold")
	# Build the first missing facility through the production editor. Previewing
	# invalid/valid tiles is pure; double confirmation must still emit one build.
	var build_open:=town_base.find_child("BaseConstructionOpen",true,false) as Button
	_check(build_open!=null,"new camp omitted the construction entry")
	if build_open!=null:build_open.pressed.emit()
	await process_frame
	var clinic_option:=town_base.find_child("BaseBuildOptionCLINIC",true,false) as Button
	_check(clinic_option!=null and not clinic_option.disabled,"starter clinic is not selectable")
	if clinic_option!=null:clinic_option.pressed.emit()
	await process_frame
	var legal_origin:=_legal_build_origin(session,"CLINIC")
	town_map=town_base.find_child("BaseSettlementMap",true,false)
	if town_map!=null:town_map.tile_pressed.emit(legal_origin)
	await process_frame
	var before_buildings:=_building_count(session.base_overview(),"CLINIC")
	var build_confirm:=town_base.find_child("BasePlacementConfirm",true,false) as Button
	_check(build_confirm!=null and not build_confirm.disabled,
		"canonical legal clinic tile did not enable confirm")
	if build_confirm!=null:
		build_confirm.pressed.emit();build_confirm.pressed.emit()
	await process_frame;await process_frame
	_check(_building_count(session.base_overview(),"CLINIC")==before_buildings+1,
		"explicit clinic confirmation did not commit exactly once")
	_check(sandbox.selected_base_building_id=="CLINIC",
		"freshly built clinic was not selected after refresh")
	town_base=sandbox.find_child("TownBaseProgress",true,false)
	town_map=town_base.find_child("BaseSettlementMap",true,false) if town_base!=null else null
	var selection_events:Array[String]=[]
	if town_base!=null:town_base.building_selected.connect(
		func(id:String):selection_events.append(id))
	if town_map!=null:
		var lodge_hit:=town_map.find_child("SettlementHitLODGE",true,false) as Button
		await _pointer_click(lodge_hit.get_global_rect().get_center())
	_check(sandbox.selected_base_building_id=="LODGE" \
		and bool((town_base.find_child("BaseSettlementMap",true,false)).building_visual_state(
			"LODGE").get("selected",false)),"building selection did not persist/render")
	_check(selection_events==["LODGE"],"settlement touch emitted duplicate building selection")
	var lodge_service:=town_base.find_child("BaseFacilityServiceLODGE",true,false) as Button
	if lodge_service!=null:lodge_service.pressed.emit()
	await process_frame;await process_frame
	_check(sandbox.town_facility_id=="SHRINE" \
		and sandbox.find_child("TownShrineTitle",true,false)!=null,
		"lodge service signal did not open shrine")
	var back:=sandbox.find_child("TownBaseMapBack",true,false) as Button
	_check(back!=null and back.size.y>=48.0,"service screen omitted clear map-back action")
	if back!=null:back.pressed.emit()
	await process_frame;await process_frame
	town_base=sandbox.find_child("TownBaseProgress",true,false)
	town_map=town_base.find_child("BaseSettlementMap",true,false) if town_base!=null else null
	_check(town_map!=null and bool(town_map.building_visual_state("LODGE").get("selected",false)),
		"map-back reset selected building")
	if town_map!=null:
		var gate_hit:=town_map.find_child("SettlementHitGATE",true,false) as Button
		await _pointer_click(gate_hit.get_global_rect().get_center())
	await process_frame
	var depart:=sandbox.find_child("TownDepart",true,false) as Button
	_check(depart!=null and not depart.disabled,"town gate/departure became unreachable")
	if depart!=null and not depart.disabled:depart.pressed.emit()
	await process_frame;await process_frame
	_check(str(session.party_status().get("view_mode",""))=="EXPLORATION",
		"town departure did not restore two-character exploration")
	sandbox.queue_free();await process_frame


func _check_species_confirm_base_first()->void:
	root.size=Vector2i(360,640)
	var session=Session.new(51,20260909,Session.DUO_SCENARIO_ID)
	var sandbox=Sandbox.new();sandbox.size=Vector2(360,640)
	sandbox.initialize_for_headless_test(session,false)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);sandbox.size=Vector2(360,640)
	root.add_child(sandbox);await process_frame
	sandbox.show_species_picker_for_new_run();await process_frame
	sandbox._commit_species_picker("human");await process_frame;await process_frame
	_check(str(session.party_status().get("view_mode",""))=="TOWN" \
		and str(session.base_overview().get("phase",""))=="TOWN",
		"explicit species-confirmed DUO new game did not canonically return base-first")
	_check(sandbox.town_facility_id=="BASE" \
		and sandbox.find_child("TownBaseProgress",true,false)!=null,
		"species-confirmed new camp did not open its settlement map")
	sandbox.queue_free();await process_frame


func _pointer_click(position:Vector2)->void:
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT
	press.button_mask=MOUSE_BUTTON_MASK_LEFT;press.pressed=true;press.position=position
	press.global_position=position
	root.push_input(press,true);await process_frame
	var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT
	release.button_mask=0;release.pressed=false;release.position=position
	release.global_position=position
	root.push_input(release,true);await process_frame


func _legal_build_origin(session,type_id:String)->Vector2i:
	var settlement:Dictionary=session.base_overview().get("settlement",{})
	for value in settlement.get("tiles",[]):
		if not value is Dictionary:continue
		var raw:Variant=value.get("position",[])
		if not raw is Array or raw.size()!=2:continue
		var origin:=Vector2i(int(raw[0]),int(raw[1]))
		if bool(session.base_build_assessment(type_id,origin).get("accepted",false)):return origin
	return Vector2i(-1,-1)


func _building_count(overview:Dictionary,type_id:String)->int:
	var result:=0;var settlement:Dictionary=overview.get("settlement",{})
	for value in settlement.get("buildings",[]):
		if value is Dictionary and str(value.get("type_id",""))==type_id:result+=1
	return result


func _overview()->Dictionary:
	return {"enabled":true,"phase":"TOWN","capacity":8,
		"stock":{"TIMBER":4,"STONE":2,"HERBS":2},"carried":{"TIMBER":2,"HERBS":1},
		"facilities":[
			{"id":"STORAGE","label":"Storage","level":1,"max_level":3,
				"effect_text":"Haul capacity 8","next_effect_text":"Haul capacity 12",
				"cost":{"TIMBER":2},"can_upgrade":true,"message":"강화할 수 있습니다."},
			{"id":"LODGE","label":"Lodge","level":1,"max_level":3,
				"effect_text":"Stress recovery 300","next_effect_text":"Stress recovery 450",
				"cost":{"TIMBER":9},"can_upgrade":false,"message":"목재가 5개 부족합니다."},
			{"id":"CLINIC","label":"Clinic","level":3,"max_level":3,
				"effect_text":"Clinic cost 15","next_effect_text":"",
				"cost":{},"can_upgrade":false,"message":"최대 단계입니다."},
		],
		"residents":[
			{"entity_id":1,"display_name":"아린","health":90,"max_health":100,"activity":"IDLE"},
			{"entity_id":2,"display_name":"보라","health":36,"max_health":80,"activity":"RECOVERING"},
		],
		"trade":[{"resource_id":"TIMBER","label":"Timber","stock":4,"amount":1,
			"unit_price":2,"can_sell":true,"message":"목재 1개를 교환합니다."}],
		"last_return":{"banked":{"TIMBER":1}},"can_return":false,
		"return_reason":"활성화된 거점 포탈이나 입구에서만 귀환할 수 있습니다.",
		"settlement":_settlement()}


func _settlement()->Dictionary:
	var tiles:Array[Dictionary]=[]
	for y in range(16):
		for x in range(16):tiles.append({"position":[x,y],"terrain_id":"grass",
			"buildable":true,"reserved":false})
	return {"schema_version":1,"width":16,"height":16,"tiles":tiles,
		"buildings":[
			{"instance_id":"STORAGE","type_id":"STORAGE","label":"창고",
				"tile_origin":[1,1],"footprint":[3,3],"rotation":0,"level":1,
				"movable":false,"fixed":false,"service_available":true},
			{"instance_id":"LODGE","type_id":"LODGE","label":"숙소",
				"tile_origin":[6,1],"footprint":[3,2],"rotation":0,"level":1,
				"movable":false,"fixed":false,"service_available":true},
			{"instance_id":"GATE","type_id":"GATE","label":"원정문",
				"tile_origin":[12,12],"footprint":[3,3],"rotation":0,"level":1,
				"movable":false,"fixed":true,"service_available":true}],
		"build_options":[
			{"type_id":"CLINIC","label":"진료소","footprint":[3,3],
				"cost":{"TIMBER":3,"STONE":2,"HERBS":2},"can_build":true,"message":"건설 가능"},
			{"type_id":"MARKET","label":"시장","footprint":[3,2],
				"cost":{"TIMBER":4},"can_build":true,"message":"건설 가능"},
			{"type_id":"ARMORY","label":"대장간","footprint":[3,2],
				"cost":{"STONE":3},"can_build":true,"message":"건설 가능"}]}


func _check(condition:bool,message:String)->void:
	if not condition:failures.append(message)
