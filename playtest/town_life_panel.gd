extends VBoxContainer
## Compact public-town navigation. The map and resident cards share the same
## observer DTO; map locations never become dungeon entity coordinates.
signal command_requested(operation:Dictionary)
signal facility_requested(id:String)
signal resident_requested(id:int)
const PixelSkin=preload("res://playtest/dark_pixel_ui_skin.gd")
const Map=preload("res://playtest/base_settlement_view.gd")
var _view:Dictionary={}
var _filter:="ADVENTURERS"
var camera=preload("res://playtest/base_map_camera.gd").new()

func present(view:Dictionary)->void:
	_view=view.duplicate(true)
	for child in get_children():remove_child(child);child.queue_free()
	add_theme_constant_override("separation",6)
	_text("%s · %d골드"%[str(view.stage),int(view.gold)],"TownLifeTitle",17)
	_text("원정 %d/%d인 · 물자를 가져온 원정 %d회"%[view.active_count,view.field_limit,view.completed_returns],"TownLifeProgress")
	var map=Map.new();map.name="PublicTownMap";map.camera=camera
	map.building_selected.connect(func(id:String):facility_requested.emit(
		{"LODGE":"INN","STORAGE":"HOUSE","GATE":"GATE"}.get(id,id)))
	add_child(map);map.present(view,"LODGE")
	var nav:=GridContainer.new();nav.name="TownLifeNavigation";nav.columns=3
	nav.add_theme_constant_override("h_separation",4);nav.add_theme_constant_override("v_separation",4);add_child(nav)
	for entry in [["INN","여관·동료"],["MARKET","시장"],["CLINIC","치유소"],
		["ARMORY","장비"],["HOUSE","내 거점"],["GATE","던전 출발"]]:
		var id:=str(entry[0]);var button:=_button(nav,str(entry[1]),"TownNav"+id)
		button.pressed.connect(func():facility_requested.emit(id))
	if int(view.reward_gold)>0:
		var reward:=_button(self,"물자 조사 보상 받기 · %d골드"%int(view.reward_gold),"TownClaimReward")
		reward.pressed.connect(func():command_requested.emit({"action":"CLAIM"}))
	if not bool(view.house_owned):
		_text("다음 목표 · 첫 동료와 두 차례 물자 원정 후 작은 집 구입","TownLifeObjective")
		var house:=_button(self,"탐험대의 집 구입 · %d골드"%int(view.house_cost),"TownAcquireHouse")
		house.disabled=not bool(view.can_acquire);house.tooltip_text=str(view.house_reason)
		house.pressed.connect(func():command_requested.emit({"action":"ACQUIRE"}))
		if not view.can_acquire:_text(str(view.house_reason),"TownHouseReason")
	_text("마을 사람들 · %d명"%view.residents.size(),"TownResidentTitle",16)
	var filters:=HBoxContainer.new();filters.name="TownResidentFilters";add_child(filters)
	for entry in [["ADVENTURERS","모험가"],["COMPANY","탐험대"],["CITIZENS","주민"]]:
		var key:=str(entry[0]);var button:=_button(filters,str(entry[1]),"TownFilter"+key)
		button.toggle_mode=true;button.button_pressed=_filter==key
		button.pressed.connect(func():_filter=key;call_deferred("present",_view))
	for resident in view.residents:
		if _filter=="COMPANY" and not resident.joined:continue
		if _filter=="CITIZENS" and resident.adventurer:continue
		if _filter=="ADVENTURERS" and (resident.joined or not resident.adventurer):continue
		_resident(resident)

func _resident(row:Dictionary)->void:
	var id:=int(row.entity_id)
	var card:=VBoxContainer.new();card.name="TownResident%d"%id
	card.add_theme_constant_override("separation",4);add_child(card)
	var name_button:=_button(card,"%s · %s · %s"%[row.display_name,
		"원정 편성" if row.active else ("탐험대 대기" if row.joined else row.occupation),row.location],"TownInspect%d"%id)
	name_button.pressed.connect(func():resident_requested.emit(id))
	var health:=ProgressBar.new();health.max_value=row.max_health;health.value=row.health
	health.show_percentage=false;health.custom_minimum_size.y=8;health.mouse_filter=Control.MOUSE_FILTER_IGNORE;card.add_child(health)
	var activity:=Label.new();activity.text=str(row.activity);activity.add_theme_font_size_override("font_size",13);card.add_child(activity)
	var actions:=GridContainer.new();actions.columns=2;actions.add_theme_constant_override("h_separation",4);card.add_child(actions)
	if not row.joined:
		_action(actions,"이야기 나누기","TALK",id,bool(row.can_talk))
		if row.adventurer:_action(actions,"동행 제안","JOIN",id,bool(row.can_join))
		if row.adventurer and not row.can_join:
			var reason:=Label.new();reason.text=str(row.join_reason)
			reason.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;reason.add_theme_font_size_override("font_size",12);card.add_child(reason)
	else:
		if row.can_reserve:_action(actions,"마을에서 대기","RESERVE",id,true)
		elif not row.active:_action(actions,"원정에 편성","ASSIGN",id,bool(row.can_assign))
		_action(actions,"여관 휴식 · 15G","REST",id,bool(row.can_rest))
		if row.can_talk:_action(actions,"이야기 나누기","TALK",id,true)

func _action(parent:Control,title:String,action:String,id:int,available:bool)->void:
	var button:=_button(parent,title,"Town%s%d"%[action,id]);button.disabled=not available
	button.pressed.connect(func():command_requested.emit({"action":action,"entity_id":str(id)}))

func _button(parent:Control,title:String,id:String)->Button:
	var button:=Button.new();button.name=id;button.text=title
	button.custom_minimum_size=Vector2(0,48);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size",14)
	button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	PixelSkin.apply_action_button(button,PixelSkin.CYAN);parent.add_child(button);return button

func _text(value:String,id:String,font_size:int=14)->void:
	var label:=Label.new();label.name=id;label.text=value
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.add_theme_font_size_override("font_size",font_size);add_child(label)
