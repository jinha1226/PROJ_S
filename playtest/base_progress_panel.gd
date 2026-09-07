class_name BaseProgressPanel
extends VBoxContainer

signal upgrade_requested(facility_id:String)
signal service_requested(facility_id:String)
signal return_requested
signal sell_requested(resource_id:String,amount:int)

const DarkPixelSkin=preload("res://playtest/dark_pixel_ui_skin.gd")
const TOUCH_TARGET:=48
const FONT_BODY:=14
const FONT_SMALL:=12

var _overview:Dictionary={}
var _read_only:=false


func _ready()->void:
	add_theme_constant_override("separation",6)
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if get_child_count()==0:_rebuild()


func present(overview:Dictionary,read_only:bool=false)->void:
	_overview=overview.duplicate(true)
	_read_only=read_only
	_rebuild()


func overview()->Dictionary:
	return _overview.duplicate(true)


func _rebuild()->void:
	for child in get_children():
		remove_child(child);child.free()
	if _overview.is_empty() or not bool(_overview.get("enabled",false)):
		_add_text("거점 정보가 아직 열리지 않았습니다.","BaseUnavailable",FONT_BODY,true)
		return
	var title:=_add_text("작은 거점 · 성장 현황","BaseProgressTitle",18,true)
	DarkPixelSkin.apply_heading(title,DarkPixelSkin.BRASS)
	_add_resource_ledger()
	_add_last_return()
	_add_section_heading("시설 · 고정 3곳","BaseFacilitiesHeading")
	var facilities:Variant=_overview.get("facilities",[])
	if facilities is Array:
		for value in facilities:
			if value is Dictionary:_add_facility(value)
	var residents:Variant=_overview.get("residents",[])
	var resident_count:=mini(2,residents.size()) if residents is Array else 0
	_add_section_heading("거주자 · 현재 %d인"%resident_count,"BaseResidentsHeading")
	if residents is Array:
		for index in range(mini(2,residents.size())):
			if residents[index] is Dictionary:_add_resident(residents[index])
	_add_trade_rows()
	if _read_only:_add_return_action()


func _add_resource_ledger()->void:
	var panel:=_section("BaseResourceLedger")
	var stack:=VBoxContainer.new();stack.add_theme_constant_override("separation",2);panel.add_child(stack)
	var stock:Dictionary=_overview.get("stock",{}) if _overview.get("stock",{}) is Dictionary else {}
	var carried:Dictionary=_overview.get("carried",{}) if _overview.get("carried",{}) is Dictionary else {}
	var capacity_value:Variant=_overview.get("capacity",0)
	var capacity:=int(capacity_value.get("total",0)) if capacity_value is Dictionary else int(capacity_value)
	var bank:=_new_label("보관 자원 (안전) · 합계 %d\n%s"%[
		_resource_total(stock),_resource_text(stock)],
		"BaseStock",FONT_BODY)
	bank.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;stack.add_child(bank)
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
	if not _read_only:
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
	var panel:=_section("BaseResident%d"%int(resident.get("entity_id",-1)))
	var stack:=VBoxContainer.new();stack.add_theme_constant_override("separation",2);panel.add_child(stack)
	var health:=int(resident.get("health",0));var maximum:=maxi(1,int(resident.get("max_health",1)))
	var activity:=str(resident.get("activity","대기"))
	activity={"IDLE":"대기","RESTING":"휴식","RECOVERING":"회복","AT_BASE":"거점 대기"}.get(
		activity.to_upper(),activity)
	var label:=_new_label("%s · %s"%[str(resident.get("display_name","거주자")),
		activity],"BaseResidentSummary",FONT_BODY)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;stack.add_child(label)
	var gauge:=ProgressBar.new();gauge.name="BaseResidentHealth"
	gauge.custom_minimum_size=Vector2(1,22);gauge.max_value=maximum;gauge.value=health
	gauge.show_percentage=false;gauge.tooltip_text="체력 %d/%d"%[health,maximum]
	DarkPixelSkin.apply_progress(gauge,DarkPixelSkin.JADE,float(health)/float(maximum)<=0.35)
	stack.add_child(gauge)
	var hp:=_new_label("체력 %d/%d"%[health,maximum],"BaseResidentHealthText",FONT_SMALL)
	hp.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;stack.add_child(hp)


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

