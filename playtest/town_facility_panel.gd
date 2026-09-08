extends VBoxContainer
## Service presentation and selection only; commands use the existing session API.
signal action_requested(operation:Dictionary)
signal resident_requested(id:int)
const UI=preload("res://playtest/town_ui_widgets.gd")
var session
var life:Dictionary={}
var state:Dictionary={}
var screen:="MARKET"

func present()->void:
	for child in get_children():remove_child(child);child.queue_free()
	add_theme_constant_override("separation",10)
	match screen:
		"MARKET":_market()
		"CLINIC":_clinic()
		"ARMORY":_armory()
		"GATE":_gate()
		"HOUSE":_house()

func _request(parent:Node,title:String,id:String,operation:Dictionary,available:bool=true,primary:bool=false)->Button:
	var b:=UI.button(parent,title,id,primary);b.disabled=not available
	b.pressed.connect(func():action_requested.emit(operation));return b

func _market()->void:
	UI.heading(self,"시장","원정에 필요한 물자를 준비하세요")
	var tabs:=HBoxContainer.new();add_child(tabs)
	for entry in [["BUY","구입"],["SELL","물자 판매"]]:
		var key:=str(entry[0]);var b:=UI.button(tabs,str(entry[1]),"TownMarketTab"+key,state.get("trade","BUY")==key)
		b.pressed.connect(func():state.trade=key;call_deferred("present"))
	if state.get("trade","BUY")=="SELL":
		for row in session.base_overview().trade:
			var box:=UI.surface(self)
			UI.label(box,str(row.label),17)
			UI.label(box,"보관 중 %d개"%int(row.stock),13,UI.MUTED)
			_request(box,"1개 판매   +%d G"%int(row.unit_price),"TownSell"+str(row.resource_id),
				{"action":"SELL","resource_id":str(row.resource_id)},bool(row.can_sell))
		return
	for row in session.town_market_stock():
		var box:=UI.surface(self)
		var line:=HBoxContainer.new();line.add_theme_constant_override("separation",8);box.add_child(line)
		var title:=VBoxContainer.new();title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;line.add_child(title)
		UI.label(title,str(row.label),16);UI.label(title,"재고 %d"%int(row.remaining),12,UI.MUTED)
		var buy:=_request(line,"%d G · 구입"%int(row.price),"TownMarketBuy"+str(row.definition_id),
			{"action":"BUY","definition_id":str(row.definition_id)},bool(row.can_buy))
		buy.custom_minimum_size.x=112;buy.size_flags_horizontal=Control.SIZE_FILL
		if not row.can_buy:UI.label(box,str(row.message),12,UI.MUTED)

func _clinic()->void:
	UI.heading(self,"치유소","체력과 일반 상처를 회복합니다 · 절단 부위는 유지")
	for row in life.residents:
		if not row.joined:continue
		var id:=int(row.entity_id);var box:=UI.surface(self)
		var line:=HBoxContainer.new();line.add_theme_constant_override("separation",10);box.add_child(line)
		UI.portrait(line,id)
		var info:=VBoxContainer.new();info.size_flags_horizontal=Control.SIZE_EXPAND_FILL;line.add_child(info)
		UI.label(info,str(row.display_name),17)
		UI.label(info,"체력  %d / %d"%[row.health,row.max_health],13,UI.MUTED)
		var assessment:Dictionary=session.town_clinic_assessment(id)
		_request(box,"치료   %d G"%int(session.TOWN_CLINIC_COST),"TownClinicTreat%d"%id,
			{"action":"TREAT","entity_id":id},bool(assessment.get("accepted",false)),true)
		if not assessment.get("accepted",false):UI.label(box,str(assessment.get("message","치료가 필요하지 않습니다")),12,UI.MUTED)

func _armory()->void:
	UI.heading(self,"장비 관리","대원별 장착과 아이템 전달")
	var owners:Array=session.town_armory_rows()
	if owners.is_empty():UI.label(self,"관리할 장비가 없습니다.");return
	var selected:Dictionary=owners[0]
	var picker:=OptionButton.new();picker.name="TownEquipmentOwner";picker.custom_minimum_size.y=48;add_child(picker)
	for i in range(owners.size()):
		picker.add_item(str(owners[i].display_name),int(owners[i].entity_id))
		if int(owners[i].entity_id)==int(state.get("owner",-1)):selected=owners[i];picker.select(i)
	state.owner=int(selected.entity_id)
	picker.item_selected.connect(func(index:int):state.owner=picker.get_item_id(index);call_deferred("present"))
	UI.label(self,"가방  %d / %d"%[selected.used_backpack_slots,selected.capacity],13,UI.MUTED)
	for item in selected.items:
		var box:=UI.surface(self)
		UI.label(box,str(item.label),16)
		var owner:=int(selected.entity_id);var instance:=str(item.instance_id)
		if item.equipped:
			UI.label(box,"장착 중",12,UI.GOLD)
			var assessment:Dictionary=session.town_unequip_assessment(owner,str(item.slot))
			_request(box,"장착 해제","TownUnequip"+instance,{"action":"UNEQUIP","entity_id":owner,"slot":str(item.slot)},bool(assessment.get("accepted",false)))
		elif not item.get("equip_slots",[]).is_empty():
			var slot:=str(item.equip_slots[0]);var assessment:Dictionary=session.town_equip_assessment(owner,instance,slot)
			_request(box,"장착","TownEquip"+instance,{"action":"EQUIP","entity_id":owner,"instance_id":instance,"slot":slot},bool(assessment.get("accepted",false)))
		if owners.size()>1:
			var line:=HBoxContainer.new();line.add_theme_constant_override("separation",8);box.add_child(line)
			var target:=OptionButton.new();target.name="TownTransferTarget"+instance;target.custom_minimum_size.y=48
			target.size_flags_horizontal=Control.SIZE_EXPAND_FILL;line.add_child(target)
			for other in owners:
				if int(other.entity_id)!=owner:target.add_item(str(other.display_name),int(other.entity_id))
			var transfer:=UI.button(line,"전달","TownTransfer"+instance);transfer.size_flags_horizontal=Control.SIZE_FILL
			transfer.pressed.connect(func():action_requested.emit({"action":"TRANSFER","entity_id":owner,"target_id":target.get_selected_id(),"instance_id":instance}))

func _gate()->void:
	UI.heading(self,"원정 준비","함께 출발할 대원과 목적지를 확인하세요")
	var box:=UI.surface(self)
	UI.label(box,"출전 대원   %d / %d"%[life.active_count,life.field_limit],16,UI.GOLD)
	for row in life.residents:
		if not row.active:continue
		var line:=HBoxContainer.new();line.add_theme_constant_override("separation",10);box.add_child(line)
		UI.portrait(line,int(row.entity_id))
		var info:=VBoxContainer.new();info.size_flags_horizontal=Control.SIZE_EXPAND_FILL;line.add_child(info)
		UI.label(info,str(row.display_name),17);UI.label(info,"체력  %d / %d"%[row.health,row.max_health],13,UI.MUTED)
	_request(box,"대원 편성 바꾸기","TownGateRoster",{"action":"ROSTER"})
	UI.label(self,"출발 지점",15,UI.GOLD)
	var assessment:Dictionary=session.town_departure_assessment()
	_request(self,"1층 입구로 출발  →","TownDepart",{"action":"DEPART","floor":1,"route":"SURFACE_ENTRANCE"},bool(assessment.get("accepted",false)),true)
	if not assessment.get("accepted",false):UI.label(self,str(assessment.get("message","출발할 수 없습니다")),13,UI.MUTED)
	for value in assessment.get("available_portal_floors",[]):
		var floor_index:=int(value);var portal:Dictionary=session.town_departure_assessment(floor_index,"ANCHOR_PORTAL")
		_request(self,"%d층 포탈로 출발"%floor_index,"TownDepartPortal%d"%floor_index,
			{"action":"DEPART","floor":floor_index,"route":"ANCHOR_PORTAL"},bool(portal.get("accepted",false)))

func _house()->void:
	UI.heading(self,"탐험대의 집","함께 머물 곳에서, 더 큰 원정을 준비하세요")
	var box:=UI.surface(self)
	UI.label(box,"나만의 거점",19,UI.GOLD)
	UI.label(box,"집을 구하면 대원을 더 영입하고 시설을 지어 물자를 생산할 수 있습니다.",14,UI.MUTED)
	var count:=0
	for row in life.residents:
		if row.joined:count+=1
	for requirement in [["물자 원정",mini(int(life.completed_returns),2),2],["탐험대원",mini(count,2),2],["구입 자금",int(life.gold),int(life.house_cost)]]:
		var line:=HBoxContainer.new();box.add_child(line)
		UI.label(line,str(requirement[0]),14)
		var progress:=UI.label(line,"%d / %d"%[requirement[1],requirement[2]],14,UI.GOLD if int(requirement[1])>=int(requirement[2]) else UI.MUTED)
		progress.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	_request(self,"집 구입   %d G"%int(life.house_cost),"TownHousePurchase",{"action":"ACQUIRE"},bool(life.can_acquire),true)
	if not life.can_acquire:UI.label(self,str(life.house_reason),13,UI.MUTED)
