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
	if failures.is_empty():
		print("PASS base progress UI smoke: 360/390 portrait, DUO return/town/depart, actions and cache marker")
		quit(0)
	else:
		for failure in failures:printerr("FAIL ",failure)
		quit(1)


func _check_panel(viewport_width:int)->void:
	var scroll:=ScrollContainer.new();scroll.name="BaseSmokeScroll"
	scroll.position=Vector2(12,12);scroll.size=Vector2(viewport_width-24,616)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;root.add_child(scroll)
	var panel=BasePanel.new();panel.name="BaseSmokePanel";panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(panel);panel.present(_overview(),false)
	await process_frame;await process_frame
	_check(panel.size.x<=float(viewport_width-24)+0.1,
		"%dpx town panel overflowed horizontally (%.1f)"%[viewport_width,panel.size.x])
	for button_value in panel.find_children("*","Button",true,false):
		var button:=button_value as Button
		_check(button.size.y>=48.0,"%dpx %s touch target below 48px"%[viewport_width,button.name])
	var storage:=panel.find_child("BaseFacilityUpgradeSTORAGE",true,false) as Button
	var lodge:=panel.find_child("BaseFacilityUpgradeLODGE",true,false) as Button
	var clinic:=panel.find_child("BaseFacilityUpgradeCLINIC",true,false) as Button
	_check(storage!=null and not storage.disabled,"%dpx affordable storage upgrade disabled"%viewport_width)
	_check(lodge!=null and lodge.disabled,"%dpx unaffordable lodge upgrade enabled"%viewport_width)
	_check(clinic!=null and clinic.disabled,"%dpx max-level clinic upgrade enabled"%viewport_width)
	_check(panel.find_child("BaseFacilityReasonLODGE",true,false)!=null,
		"%dpx disabled upgrade omitted visible reason"%viewport_width)
	var stock:=panel.find_child("BaseStock",true,false) as Label
	var carried:=panel.find_child("BaseCarried",true,false) as Label
	_check(stock!=null and "안전" in stock.text and "/8" not in stock.text,
		"%dpx secured stock is not clearly unbounded/safe"%viewport_width)
	_check(carried!=null and "손실 위험" in carried.text and "3/8" in carried.text,
		"%dpx carried haul risk/capacity missing"%viewport_width)
	var upgrade_ids:Array[String]=[];var service_ids:Array[String]=[];var sells:Array=[]
	panel.upgrade_requested.connect(func(id:String):upgrade_ids.append(id))
	panel.service_requested.connect(func(id:String):service_ids.append(id))
	panel.sell_requested.connect(func(id:String,amount:int):sells.append([id,amount]))
	storage.pressed.emit();(panel.find_child("BaseFacilityServiceLODGE",true,false) as Button).pressed.emit()
	(panel.find_child("BaseTradeSellTIMBER",true,false) as Button).pressed.emit()
	_check(upgrade_ids==["STORAGE"],"%dpx upgrade signal payload/once contract"%viewport_width)
	_check(service_ids==["LODGE"],"%dpx service signal payload/once contract"%viewport_width)
	_check(sells==[["TIMBER",1]],"%dpx sell signal explicit amount contract"%viewport_width)
	panel.present(_overview(),true);await process_frame
	_check(panel.find_child("BaseFacilityServiceLODGE",true,false)==null,
		"%dpx dungeon preview exposed town service"%viewport_width)
	var preview_upgrade:=panel.find_child("BaseFacilityUpgradeSTORAGE",true,false) as Button
	var base_return:=panel.find_child("BaseReturn",true,false) as Button
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
	for old_tab in ["TownFacilityCLINIC","TownFacilitySHRINE","TownFacilityMARKET",
			"TownFacilityARMORY","TownFacilityGATE"]:
		_check(sandbox.find_child(old_tab,true,false)!=null,"town lost existing service %s"%old_tab)
	var town_base=sandbox.find_child("TownBaseProgress",true,false)
	if town_base!=null:town_base.service_requested.emit("LODGE")
	await process_frame;await process_frame
	_check(sandbox.town_facility_id=="SHRINE" \
		and sandbox.find_child("TownShrineTitle",true,false)!=null,
		"lodge service signal did not open shrine")
	(sandbox.find_child("TownFacilityGATE",true,false) as Button).pressed.emit()
	await process_frame;await process_frame
	var depart:=sandbox.find_child("TownDepart",true,false) as Button
	_check(depart!=null and not depart.disabled,"town gate/departure became unreachable")
	if depart!=null and not depart.disabled:depart.pressed.emit()
	await process_frame;await process_frame
	_check(str(session.party_status().get("view_mode",""))=="EXPLORATION",
		"town departure did not restore two-character exploration")
	sandbox.queue_free();await process_frame


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
		"return_reason":"활성화된 거점 포탈이나 입구에서만 귀환할 수 있습니다."}


func _check(condition:bool,message:String)->void:
	if not condition:failures.append(message)
