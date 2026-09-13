extends VBoxContainer
const UI=preload("res://playtest/town_ui_widgets.gd")
const Campaign=preload("res://playtest/frontier_campaign.gd")
signal facility_requested(id:String)
signal depart_requested(floor_index:int,route:String)
signal command_requested(operation:Dictionary)
var session
func _ready()->void:
	var life:Dictionary=session.town_life_overview()
	UI.heading(self,"변방의 피난처","마왕의 세력이 길과 도시를 장악했다. 이곳에서 살아남을 사람들을 모으자.")
	UI.label(self,Campaign.objective(session),14,UI.GOLD)
	var map=preload("res://playtest/base_settlement_view.gd").new()
	map.minimum_map_height=160;map.fit_map_height=true
	add_child(map)
	var view:Dictionary=life.duplicate(true);view.settlement=session.base_overview().settlement
	map.present(view,"");map.building_selected.connect(func(_id):facility_requested.emit("HOUSE"))
	UI.heading(self,"지역 지도","한 지역씩 탐험하고 피난처로 돌아옵니다.")
	var route:Dictionary=session.town_departure_assessment(1,"SURFACE_ENTRANCE")
	var explore:=UI.button(self,"변방 숲길 · 물자 / 생존자 수색 →","FrontierExplore",true)
	explore.disabled=not route.get("accepted",false)
	explore.pressed.connect(func():depart_requested.emit(1,"SURFACE_ENTRANCE"))
	var mine:Dictionary=session.town_departure_assessment(2,"ANCHOR_PORTAL")
	var mine_button:=UI.button(self,"폐광 · 발견한 연결 거점으로 이동","FrontierMine")
	mine_button.disabled=not mine.get("accepted",false)
	mine_button.pressed.connect(func():depart_requested.emit(2,"ANCHOR_PORTAL"))
	if mine_button.disabled:UI.label(self,"폐광은 숲길 유적 안쪽 통로로 발견할 수 있습니다.",12,UI.MUTED)
	var home:=UI.button(self,"피난처 관리 · 건설 / 창고 / 휴식","FrontierHome")
	home.pressed.connect(func():facility_requested.emit("HOUSE"))
	UI.heading(self,"함께 사는 사람들","주민 %d명"%life.residents.size())
	for resident in life.residents:
		UI.label(self,"%s · %s"%[resident.display_name,resident.activity],14)
		if resident.is_player:continue
		var action:="RESERVE" if resident.active else "ASSIGN"
		var button:=UI.button(self,"피난처에 남기기" if resident.active else "다음 탐험에 동행", "FrontierResident%d"%resident.entity_id)
		button.disabled=not resident.can_reserve if resident.active else not resident.can_assign
		button.pressed.connect(func():command_requested.emit({"action":action,"entity_id":str(resident.entity_id)}))
