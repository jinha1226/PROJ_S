class_name BaseProgressPanel
extends VBoxContainer

signal upgrade_requested(facility_id:String)
signal service_requested(facility_id:String)
signal building_selected(building_id:String)
signal resident_requested(entity_id:int)
signal construction_confirm_requested(type_id:String,tile_origin:Vector2i)
signal work_cancel_requested
signal production_requested(action:String,recipe_id:String)
signal rest_requested(entity_id:int)
signal return_requested
signal sell_requested(resource_id:String,amount:int)

const DarkPixelSkin=preload("res://playtest/dark_pixel_ui_skin.gd")
const BaseSettlementViewScript=preload("res://playtest/base_settlement_view.gd")
const TOUCH_TARGET:=48
const FONT_BODY:=14
const FONT_SMALL:=12

var _overview:Dictionary={}
var _read_only:=false
var _selected_id:="STORAGE"
var _build_assessment_provider:Callable
var _placement_active:=false
var _placement_type:=""
var _placement_origin:=Vector2i.ZERO
var _placement_assessment:Dictionary={}
var _confirm_pending:=false
var _map_camera=preload("res://playtest/base_map_camera.gd").new()


func _ready()->void:
	add_theme_constant_override("separation",6)
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if get_child_count()==0:_rebuild()


func present(overview:Dictionary,read_only:bool=false,selected_id:String="STORAGE")->void:
	_overview=overview.duplicate(true)
	_read_only=read_only
	_selected_id=selected_id if selected_id in ["STORAGE","LODGE","CLINIC",
		"MARKET","ARMORY","GATE"] else "STORAGE"
	_confirm_pending=false;_placement_active=false;_placement_type=""
	_placement_assessment={}
	_rebuild()


func overview()->Dictionary:
	return _overview.duplicate(true)


func configure_build_assessment(provider:Callable)->void:
	_build_assessment_provider=provider

func configure_camera(value)->void:
	_map_camera=value


func apply_placement_assessment(result:Dictionary)->void:
	_confirm_pending=false;_placement_assessment=result.duplicate(true);call_deferred("_rebuild")


func _rebuild()->void:
	for child in get_children():
		remove_child(child);child.free()
	if _overview.is_empty() or not bool(_overview.get("enabled",false)):
		_add_text("거점 정보가 아직 열리지 않았습니다.","BaseUnavailable",FONT_BODY,true)
		return
	if not bool(_overview.get("private_home_owned",true)):
		_add_text("여관 생활 · 아직 개인 거점이 없습니다","InnStorageTitle",16,true)
		_add_resource_ledger()
		_add_text("물자는 여관 보관소에 맡깁니다. 마을에서 동료를 만나고 탐험대의 집을 구하세요.","InnStorageHint",FONT_BODY,true)
		if _read_only:_add_return_action()
		return
	var title:=_add_text("작은 거점 · 건물을 눌러 확인","BaseProgressTitle",16,true)
	DarkPixelSkin.apply_heading(title,DarkPixelSkin.BRASS)
	_add_resource_ledger()
	var settlement=BaseSettlementViewScript.new();settlement.name="BaseSettlementMap"
	settlement.camera=_map_camera
	settlement.building_selected.connect(_on_settlement_building_selected)
	settlement.tile_pressed.connect(_on_placement_tile)
	settlement.tile_dragged.connect(_on_placement_tile)
	add_child(settlement);settlement.present(_overview,_selected_id)
	settlement.set_placement_mode(_placement_active)
	if _placement_active and not _placement_type.is_empty():
		settlement.set_placement_ghost(_placement_ghost())
	_add_last_return()
	_add_work_status()
	if _placement_active:_add_construction_editor()
	else:
		if not _read_only:_add_build_entry()
		_add_section_heading("선택 · %s"%_building_label(_selected_id),"BaseSelectionHeading")
		var facility:=_facility_by_id(_selected_id)
		if not facility.is_empty():_add_facility(facility)
		else:_add_landmark_detail(_selected_id)
		_add_production()
		if _selected_id=="LODGE":_add_rest()
		if _selected_id=="STORAGE":_add_trade_rows()
	var residents:Variant=_overview.get("residents",[])
	var resident_count:int=residents.size() if residents is Array else 0
	_add_section_heading("거주자 · 현재 %d인"%resident_count,"BaseResidentsHeading")
	if residents is Array:
		for index in range(residents.size()):
			if residents[index] is Dictionary:_add_resident(residents[index])
	if _read_only:_add_return_action()


func _on_settlement_building_selected(building_id:String)->void:
	_selected_id=building_id
	building_selected.emit(building_id)
	# The selected hit target is emitting this signal. Rebuild after its dispatch
	# completes so a facility tap cannot free its own Button mid-gesture.
	call_deferred("_rebuild_after_selection")


func _rebuild_after_selection()->void:
	if is_instance_valid(self) and is_inside_tree():_rebuild()


func _add_build_entry()->void:
	if not (_overview.get("work",{}) as Dictionary).is_empty():return
	var options:=_build_options()
	if options.is_empty():return
	var button:=_button("건설","BaseConstructionOpen")
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button.pressed.connect(_open_construction_editor);add_child(button)


func _add_work_status()->void:
	var work:Dictionary=_overview.get("work",{})
	if work.is_empty():return
	var title:="회복 물약 · 제조 중" if str(work.action)=="PRODUCE" else "%s · 주민 작업 중"%_building_label(str(work.type_id))
	if str(work.action)=="REST":title="숙소 · 휴식 중"
	_add_text(title,"BaseWorkTitle",FONT_BODY,true)
	var progress:=ProgressBar.new();progress.name="BaseWorkProgress"
	progress.max_value=float(work.required);progress.value=float(work.progress)
	progress.custom_minimum_size.y=18;add_child(progress)
	var cancel:=_button("작업 취소 · 재료 반환","BaseWorkCancel")
	if str(work.action)=="REST":cancel.text="휴식 취소 · 골드 반환"
	cancel.pressed.connect(func():work_cancel_requested.emit());add_child(cancel)


func _add_rest()->void:
	_add_section_heading("휴식 · 보유 %d골드"%int(_overview.get("gold",0)),"BaseRestHeading")
	for resident in _overview.get("rest",[]):
		var id:=int(resident.entity_id)
		_add_text("%s · 긴장 %d%% → %d%%"%[str(resident.label),roundi(float(resident.stress)/10),
			roundi(float(resident.stress_after)/10)],"BaseRestStatus%d"%id,FONT_BODY,true)
		if int(resident.emotion)>0:
			_add_text("%s %d%% → %d%%"%[str(resident.emotion_label),ceili(float(resident.emotion)/10),
				ceili(float(resident.emotion_after)/10)],"BaseRestEmotion%d"%id,FONT_SMALL,true)
		var bar:=ProgressBar.new();bar.name="BaseRestStress%d"%id
		bar.max_value=1000;bar.value=int(resident.stress);bar.show_percentage=false
		bar.custom_minimum_size.y=8;bar.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(bar)
		var rest:=_button("휴식 · %d골드"%int(resident.cost),"BaseRest%d"%id)
		rest.disabled=_read_only or not bool(resident.can_rest)
		rest.tooltip_text=str(resident.message)
		rest.pressed.connect(func():rest_requested.emit(id));add_child(rest)
		if not bool(resident.can_rest):_add_text(str(resident.message),"BaseRestReason%d"%id,FONT_SMALL,true)


func _add_production()->void:
	for recipe in _overview.get("production",[]):
		if str(recipe.facility_id)!=_selected_id:continue
		_add_section_heading("제조 · %s"%str(recipe.label),"BaseProductionHeading")
		_add_text("비용 %s · 완성품 %d/%d"%[_resource_text(recipe.cost),int(recipe.ready),
			int(recipe.stock_limit)],"BaseProductionStock",FONT_SMALL,true)
		var buttons:=HBoxContainer.new();buttons.add_theme_constant_override("separation",4);add_child(buttons)
		var produce:=_button("1개 제조","BaseProduce%s"%str(recipe.recipe_id))
		produce.disabled=_read_only or not bool(recipe.can_produce)
		produce.tooltip_text=str(recipe.message)
		produce.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		produce.pressed.connect(func():production_requested.emit("PRODUCE",str(recipe.recipe_id)))
		buttons.add_child(produce)
		var claim:=_button("가방으로 1개","BaseClaim%s"%str(recipe.recipe_id))
		claim.disabled=_read_only or not bool(recipe.can_claim)
		claim.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		claim.pressed.connect(func():production_requested.emit("CLAIM",str(recipe.recipe_id)))
		buttons.add_child(claim)
		if not bool(recipe.can_produce):_add_text(str(recipe.message),"BaseProductionReason",FONT_SMALL,true)


func update_work(overview:Dictionary)->void:
	# Keep active touch targets and camera alive during automatic work ticks.
	_overview=overview.duplicate(true)
	var map:=find_child("BaseSettlementMap",true,false)
	if map!=null:map.present(_overview,_selected_id)
	var progress:=find_child("BaseWorkProgress",true,false) as ProgressBar
	if progress!=null:progress.value=float((_overview.get("work",{}) as Dictionary).get("progress",0))


func _open_construction_editor()->void:
	_placement_active=true;_placement_type="";_placement_assessment={};call_deferred("_rebuild")


func _add_construction_editor()->void:
	_add_section_heading("건설 · 빈 땅에 시설 배치","BaseConstructionHeading")
	if _placement_type.is_empty():
		for option in _build_options():
			var type_id:=str(option.get("type_id",""))
			var choose:=_button("%s · %s"%[str(option.get("label",_building_label(type_id))),
				"비용 %s"%_resource_text(option.get("cost",{}))],"BaseBuildOption%s"%type_id)
			choose.disabled=not bool(option.get("can_build",false))
			choose.tooltip_text=str(option.get("message",""))
			choose.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			choose.pressed.connect(_choose_build_option.bind(type_id));add_child(choose)
	else:
		var option:=_build_option(_placement_type)
		_add_text("%s · 비용 %s"%[str(option.get("label",_building_label(_placement_type))),
			_resource_text(option.get("cost",{}))],"BaseBuildChoice",FONT_BODY,true)
		var message:=str(_placement_assessment.get("message","빈 타일을 누르거나 끌어 위치를 정하세요."))
		var feedback:=_add_text(message,"BasePlacementFeedback",FONT_SMALL,true)
		feedback.add_theme_color_override("font_color",DarkPixelSkin.JADE \
			if bool(_placement_assessment.get("accepted",false)) else DarkPixelSkin.BLOOD)
		var actions:=HBoxContainer.new();actions.name="BasePlacementActions"
		actions.add_theme_constant_override("separation",4);add_child(actions)
		var cancel:=_button("취소","BasePlacementCancel")
		cancel.pressed.connect(_cancel_construction);actions.add_child(cancel)
		var confirm:=_button("확정","BasePlacementConfirm")
		confirm.disabled=not bool(_placement_assessment.get("accepted",false))
		confirm.tooltip_text=message;confirm.pressed.connect(_confirm_construction)
		actions.add_child(confirm)


func _choose_build_option(type_id:String)->void:
	_placement_type=type_id;_placement_origin=_first_buildable_tile()
	_assess_placement();call_deferred("_rebuild")


func _on_placement_tile(position:Vector2i)->void:
	if not _placement_active or _placement_type.is_empty() or _confirm_pending:return
	_placement_origin=position;_assess_placement()
	var settlement:=find_child("BaseSettlementMap",true,false)
	if settlement!=null:settlement.set_placement_ghost(_placement_ghost())
	var feedback:=find_child("BasePlacementFeedback",true,false) as Label
	if feedback!=null:
		feedback.text=str(_placement_assessment.get("message",""))
		feedback.add_theme_color_override("font_color",DarkPixelSkin.JADE \
			if bool(_placement_assessment.get("accepted",false)) else DarkPixelSkin.BLOOD)
	var confirm:=find_child("BasePlacementConfirm",true,false) as Button
	if confirm!=null:
		confirm.disabled=not bool(_placement_assessment.get("accepted",false))
		confirm.tooltip_text=str(_placement_assessment.get("message",""))


func _assess_placement()->void:
	if not _build_assessment_provider.is_valid():
		_placement_assessment={"accepted":false,"message":"배치 검사를 사용할 수 없습니다."};return
	var result:Variant=_build_assessment_provider.call(_placement_type,_placement_origin)
	_placement_assessment=result.duplicate(true) if result is Dictionary else {
		"accepted":false,"message":"배치 검사를 완료하지 못했습니다."}


func _placement_ghost()->Dictionary:
	var option:=_build_option(_placement_type)
	return {"type_id":_placement_type,"tile_origin":[_placement_origin.x,_placement_origin.y],
		"footprint":_placement_assessment.get("footprint",option.get("footprint",[3,3])),
		"accepted":bool(_placement_assessment.get("accepted",false)),
		"message":str(_placement_assessment.get("message",""))}


func _confirm_construction()->void:
	if _confirm_pending or not bool(_placement_assessment.get("accepted",false)):return
	_confirm_pending=true
	var confirm:=find_child("BasePlacementConfirm",true,false) as Button
	if confirm!=null:confirm.disabled=true
	construction_confirm_requested.emit(_placement_type,_placement_origin)


func _cancel_construction()->void:
	if _confirm_pending:return
	_placement_active=false;_placement_type="";_placement_assessment={};call_deferred("_rebuild")


func _build_options()->Array[Dictionary]:
	var settlement:Dictionary=_overview.get("settlement",{}) \
		if _overview.get("settlement",{}) is Dictionary else {}
	var result:Array[Dictionary]=[]
	for value in settlement.get("build_options",[]):
		if value is Dictionary:result.append(value)
	return result


func _build_option(type_id:String)->Dictionary:
	for option in _build_options():
		if str(option.get("type_id",""))==type_id:return option
	return {}


func _first_buildable_tile()->Vector2i:
	var settlement:Dictionary=_overview.get("settlement",{}) \
		if _overview.get("settlement",{}) is Dictionary else {}
	for value in settlement.get("tiles",[]):
		if value is Dictionary and bool(value.get("buildable",false)) \
				and not bool(value.get("reserved",false)):
			var raw:Variant=value.get("position",[])
			if raw is Array and raw.size()==2:return Vector2i(int(raw[0]),int(raw[1]))
	return Vector2i.ZERO


func _facility_by_id(facility_id:String)->Dictionary:
	for value in _overview.get("facilities",[]):
		if value is Dictionary and str(value.get("id",""))==facility_id:
			return value
	return {}


func _add_resource_ledger()->void:
	var panel:=_section("BaseResourceLedger")
	var stack:=VBoxContainer.new();stack.add_theme_constant_override("separation",2);panel.add_child(stack)
	var stock:Dictionary=_overview.get("stock",{}) if _overview.get("stock",{}) is Dictionary else {}
	var carried:Dictionary=_overview.get("carried",{}) if _overview.get("carried",{}) is Dictionary else {}
	var capacity_value:Variant=_overview.get("capacity",0)
	var capacity:=int(capacity_value.get("total",0)) if capacity_value is Dictionary else int(capacity_value)
	var town_phase:=str(_overview.get("phase",""))=="TOWN"
	var bank:=_new_label(("보관 자원 (안전) · 합계 %d · %s" if town_phase \
		else "보관 자원 (안전) · 합계 %d\n%s")%[
		_resource_total(stock),_resource_text(stock)],
		"BaseStock",FONT_BODY)
	bank.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;stack.add_child(bank)
	if town_phase:return
	var haul:=_new_label("운반 자원 (귀환 전 손실 위험) · %d/%d\n%s"%[
		_resource_total(carried),capacity,_resource_text(carried)],"BaseCarried",FONT_BODY)
	haul.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	haul.add_theme_color_override("font_color",DarkPixelSkin.BRASS);stack.add_child(haul)


func _add_last_return()->void:
	var last_return:Variant=_overview.get("last_return",{})
	if not last_return is Dictionary or last_return.is_empty():return
	var banked:Dictionary=last_return.get("banked",{}) \
		if last_return.get("banked",{}) is Dictionary else {}
	var message:=str(last_return.get("message","")).strip_edges()
	if message.is_empty() and not banked.is_empty():
		message="최근 귀환 확보 · %s"%_resource_text(banked)
	if not message.is_empty():_add_text(message,"BaseLastReturn",FONT_SMALL,false)


func _add_facility(facility:Dictionary)->void:
	var id:=str(facility.get("id",""))
	var panel:=_section("BaseFacility%s"%id)
	var stack:=VBoxContainer.new();stack.add_theme_constant_override("separation",2);panel.add_child(stack)
	var level:=int(facility.get("level",0));var max_level:=int(facility.get("max_level",level))
	var heading:=_new_label("%s  Lv.%d/%d"%[_facility_label(id,str(facility.get("label",id))),level,max_level],
		"BaseFacilityTitle%s"%id,16)
	DarkPixelSkin.apply_heading(heading,DarkPixelSkin.CYAN);stack.add_child(heading)
	var current:=_new_label("현재 · %s"%str(facility.get("effect_text","-")),
		"BaseFacilityCurrent%s"%id,FONT_SMALL)
	current.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;stack.add_child(current)
	var next_text:=str(facility.get("next_effect_text","최대 단계")) \
		if level<max_level else "최대 단계"
	var next:=_new_label("다음 · %s"%next_text,"BaseFacilityNext%s"%id,FONT_SMALL)
	next.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;stack.add_child(next)
	var action_row:=HBoxContainer.new();action_row.add_theme_constant_override("separation",4)
	stack.add_child(action_row)
	var cost:=_new_label("비용 · %s"%_resource_text(facility.get("cost",{})),
		"BaseFacilityCost%s"%id,FONT_SMALL)
	cost.size_flags_horizontal=Control.SIZE_EXPAND_FILL;cost.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	action_row.add_child(cost)
	if not _read_only and (id=="CLINIC" or id=="LODGE" and not _overview.has("rest")):
		var service:=_button("이용","BaseFacilityService%s"%id)
		service.pressed.connect(func():service_requested.emit(id));action_row.add_child(service)
	var upgrade:=_button("강화","BaseFacilityUpgrade%s"%id)
	var can_upgrade:=bool(facility.get("can_upgrade",false)) and not _read_only
	upgrade.disabled=not can_upgrade
	upgrade.tooltip_text="마을에서만 강화할 수 있습니다." if _read_only \
		else str(facility.get("message",""))
	upgrade.pressed.connect(func():upgrade_requested.emit(id));action_row.add_child(upgrade)
	var reason:=str(facility.get("message","")).strip_edges()
	if _read_only:reason="마을에서만 강화할 수 있습니다."
	if not can_upgrade and not reason.is_empty():
		var disabled_reason:=_new_label(reason,"BaseFacilityReason%s"%id,FONT_SMALL)
		disabled_reason.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		disabled_reason.add_theme_color_override("font_color",DarkPixelSkin.BONE_DIM)
		stack.add_child(disabled_reason)


func _add_resident(resident:Dictionary)->void:
	var entity_id:=int(resident.get("entity_id",-1))
	var health:=int(resident.get("health",0));var maximum:=maxi(1,int(resident.get("max_health",1)))
	var activity:=str(resident.get("activity","대기"))
	activity={"IDLE":"대기","RESTING":"휴식","RECOVERING":"회복","AT_BASE":"거점 대기"}.get(
		activity.to_upper(),activity)
	var button:=_button("%s · 체력 %d/%d · %s"%[
		str(resident.get("display_name","거주자")),health,maximum,activity],
		"BaseResident%d"%entity_id)
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button.disabled=_read_only or entity_id<=0
	button.tooltip_text="마을에서 인물 상세 열기" if _read_only else "인물 상세 열기"
	button.pressed.connect(func():resident_requested.emit(entity_id));add_child(button)


func _add_landmark_detail(building_id:String)->void:
	var panel:=_section("BaseLandmark%s"%building_id)
	var stack:=VBoxContainer.new();stack.add_theme_constant_override("separation",4);panel.add_child(stack)
	var description:String={"MARKET":"소모품과 기본 장비를 구입합니다.",
		"ARMORY":"두 원정대원의 장비와 물품을 정리합니다.",
		"GATE":"준비를 마치고 던전 원정을 시작합니다."}.get(building_id,"거점 시설입니다.")
	var label:=_new_label(str(description),"BaseLandmarkDescription%s"%building_id,FONT_BODY)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;stack.add_child(label)
	if _read_only:
		var reason:=_new_label("마을에 귀환한 뒤 이용할 수 있습니다.",
			"BaseLandmarkReason%s"%building_id,FONT_SMALL)
		reason.add_theme_color_override("font_color",DarkPixelSkin.BONE_DIM);stack.add_child(reason)
	else:
		var open:=_button("%s 열기"%_building_label(building_id),
			"BaseLandmarkOpen%s"%building_id)
		var built:=false
		for building in (_overview.get("settlement",{}) as Dictionary).get("buildings",[]):
			if str(building.type_id)==building_id:built=true;break
		open.disabled=not built
		if not built:open.tooltip_text="공사가 완료되면 이용할 수 있습니다."
		open.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		open.pressed.connect(func():service_requested.emit(building_id));stack.add_child(open)


func _add_trade_rows()->void:
	var trade:Variant=_overview.get("trade",[])
	if not trade is Array or trade.is_empty() or _read_only:return
	_add_section_heading("교환 · 보관 자원 → 금화","BaseTradeHeading")
	for value in trade:
		if not value is Dictionary:continue
		var row:Dictionary=value;var resource_id:=str(row.get("resource_id",""))
		var amount:=maxi(1,int(row.get("amount",1)))
		var line:=HBoxContainer.new();line.name="BaseTrade%s"%resource_id
		line.custom_minimum_size.y=TOUCH_TARGET;line.add_theme_constant_override("separation",4)
		add_child(line)
		var label:=_new_label("%s %d개 → %d금화"%[str(row.get("label",_resource_label(resource_id))),
			amount,int(row.get("unit_price",0))*amount],"BaseTradeLabel%s"%resource_id,FONT_SMALL)
		label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		line.add_child(label)
		var sell:=_button("교환","BaseTradeSell%s"%resource_id)
		sell.disabled=not bool(row.get("can_sell",false));sell.tooltip_text=str(row.get("message",""))
		sell.pressed.connect(func():sell_requested.emit(resource_id,amount));line.add_child(sell)


func _add_return_action()->void:
	var can_return:=bool(_overview.get("can_return",false))
	var button:=_button("안전 귀환 · 운반 자원 보관","BaseReturn")
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.disabled=not can_return
	button.tooltip_text=str(_overview.get("message",_overview.get("return_reason","")))
	button.pressed.connect(func():return_requested.emit());add_child(button)
	if not can_return:
		var reason:=str(_overview.get("message",_overview.get("return_reason",""))).strip_edges()
		if not reason.is_empty():_add_text(reason,"BaseReturnReason",FONT_SMALL,false)


func _add_section_heading(text:String,node_name:String)->void:
	var label:=_add_text(text,node_name,FONT_BODY,false)
	DarkPixelSkin.apply_heading(label,DarkPixelSkin.BRASS)


func _section(node_name:String)->PanelContainer:
	var panel:=PanelContainer.new();panel.name=node_name
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	DarkPixelSkin.apply_panel(panel,"SECTION");add_child(panel);return panel


func _button(text:String,node_name:String)->Button:
	var button:=Button.new();button.name=node_name;button.text="[ %s ]"%text
	button.custom_minimum_size=Vector2(72,TOUCH_TARGET);button.add_theme_font_size_override("font_size",FONT_SMALL)
	button.focus_mode=Control.FOCUS_ALL;DarkPixelSkin.apply_action_button(button,DarkPixelSkin.CYAN)
	return button


func _add_text(text:String,node_name:String,font_size:int,centered:bool)->Label:
	var label:=_new_label(text,node_name,font_size)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	if centered:label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	add_child(label);return label


func _new_label(text:String,node_name:String,font_size:int)->Label:
	var label:=Label.new();label.name=node_name;label.text=text
	label.add_theme_font_size_override("font_size",font_size)
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return label


func _resource_total(resources:Dictionary)->int:
	var total:=0
	for value in resources.values():total+=maxi(0,int(value))
	return total


func _resource_text(value:Variant)->String:
	if not value is Dictionary or value.is_empty():return "없음"
	var resources:Dictionary=value;var keys:=resources.keys();keys.sort()
	var parts:Array[String]=[]
	for key_value in keys:
		var key:=str(key_value);parts.append("%s %d"%[_resource_label(key),int(resources[key_value])])
	return " · ".join(parts)


func _resource_label(resource_id:String)->String:
	return {"wood":"목재","timber":"목재","stone":"석재","herb":"약초","herbs":"약초"}.get(
		resource_id.to_lower(),resource_id)


func _facility_label(facility_id:String,fallback:String)->String:
	return {"STORAGE":"보관소","LODGE":"숙소","CLINIC":"진료소"}.get(
		facility_id.to_upper(),fallback)


func _building_label(building_id:String)->String:
	return {"STORAGE":"창고","LODGE":"숙소","CLINIC":"진료소",
		"MARKET":"시장","ARMORY":"대장간","GATE":"귀환 관문"}.get(
		building_id.to_upper(),building_id)
