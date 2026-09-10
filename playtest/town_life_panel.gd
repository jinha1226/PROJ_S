extends VBoxContainer
## Hub and inn are separate screens; only the selected resident has actions.
signal command_requested(operation:Dictionary)
signal facility_requested(id:String)
signal resident_requested(id:int)
const UI=preload("res://playtest/town_ui_widgets.gd")
const Map=preload("res://playtest/base_settlement_view.gd")
var _view:Dictionary={}
var state:Dictionary={"filter":"ADVENTURERS","resident":-1}
var screen:="BASE"
var camera=preload("res://playtest/base_map_camera.gd").new()

func present(view:Dictionary)->void:
	_view=view.duplicate(true)
	for child in get_children():remove_child(child);child.queue_free()
	add_theme_constant_override("separation",10)
	if screen in ["INN","GUILD","SHRINE"]:_inn()
	else:_hub()

func _hub()->void:
	UI.heading(self,"마을 광장","여관에 머무는 중" if not _view.house_owned else "탐험대의 집에서 생활 중")
	var map:=Map.new();map.name="PublicTownMap";map.camera=camera
	map.minimum_map_height=clampi(int(get_viewport_rect().size.y)-440-(58 if int(_view.reward_gold)>0 else 0),160,360)
	map.fit_map_height=true
	map.resident_selected.connect(func(id:int):resident_requested.emit(id))
	map.building_selected.connect(func(id:String):
		if id=="STORAGE":facility_requested.emit("STORAGE")
		else:facility_requested.emit({"LODGE":"INN"}.get(id,id)))
	add_child(map);map.present(_view,"")
	var caption:=HBoxContainer.new();add_child(caption)
	UI.label(caption,"마을 사람 %d명"%_view.residents.size(),12,UI.MUTED)
	var hint:=UI.label(caption,"건물을 눌러 방문",12,UI.MUTED)
	hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	var nav:=GridContainer.new();nav.name="TownLifeNavigation";nav.columns=5
	nav.add_theme_constant_override("h_separation",8);nav.add_theme_constant_override("v_separation",8);add_child(nav)
	for entry in [["INN","여관"],["GUILD","길드"],["MARKET","시장"],["CLINIC","치유소"],["HOUSE","내 거점"]]:
		var id:=str(entry[0]);var b:=UI.shortcut(nav,str(entry[1]),"TownNav"+id,id)
		b.pressed.connect(func():facility_requested.emit(id))
	var line:=HBoxContainer.new();line.add_theme_constant_override("separation",8);add_child(line)
	var names:Array[String]=[]
	for row in _view.residents:
		if row.active:names.append(str(row.display_name))
	var info:=VBoxContainer.new();info.size_flags_horizontal=Control.SIZE_EXPAND_FILL;line.add_child(info)
	UI.label(info,"원정대  %d / %d"%[_view.active_count,_view.field_limit],14)
	UI.label(info," · ".join(names),12,UI.MUTED)
	var gear:=UI.button(line,"장비","TownNavARMORY");gear.size_flags_horizontal=Control.SIZE_FILL;gear.custom_minimum_size.x=64
	gear.pressed.connect(func():facility_requested.emit("ARMORY"))
	if int(_view.reward_gold)>0:
		var reward:=UI.button(self,"원정 보상 받기    +%d G"%int(_view.reward_gold),"TownClaimReward")
		reward.pressed.connect(func():command_requested.emit({"action":"CLAIM"}))
	var gate:=UI.button(self,"원정 준비  →","TownNavGATE",true);gate.custom_minimum_size.y=54
	gate.pressed.connect(func():facility_requested.emit("GATE"))

func _inn()->void:
	if screen=="GUILD":
		_guild();return
	UI.heading(self,"여관","동료를 만나고 다음 원정을 준비하세요")
	UI.workplace_residents(self,_view.residents,"INN",func(id:int):resident_requested.emit(id))
	if state.get("filter") not in ["ADVENTURERS","COMPANY"]:state.filter="ADVENTURERS"
	var filters:=HBoxContainer.new();filters.name="TownResidentFilters";add_child(filters)
	for entry in [["ADVENTURERS","모험가"],["COMPANY","탐험대"]]:
		var key:=str(entry[0]);var b:=UI.button(filters,str(entry[1]),"TownFilter"+key,state.get("filter")==key)
		b.pressed.connect(func():state.filter=key;state.resident=-1;state.resident_scroll=0;call_deferred("present",_view))
	var rows:Array=[]
	for row in _view.residents:
		if not row.adventurer:continue
		if state.get("filter")=="COMPANY" and not row.joined:continue
		if state.get("filter")=="ADVENTURERS" and (row.joined or not row.adventurer):continue
		rows.append(row)
	if rows.is_empty():UI.label(self,"아직 함께하는 동료가 없습니다.",14,UI.MUTED);return
	var selected:Dictionary=rows[0]
	for row in rows:
		if int(row.entity_id)==int(state.get("resident",-1)):selected=row
	state.resident=int(selected.entity_id)
	_resident_detail(selected)
	UI.label(self,"%d명 · 이름을 누르면 상태·성격·관계 확인"%rows.size(),12,UI.MUTED)
	var scroll:=ScrollContainer.new();scroll.name="TownResidentScroll"
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y=210;add_child(scroll)
	scroll.set_deferred("scroll_vertical",int(state.get("resident_scroll",0)))
	scroll.get_v_scroll_bar().value_changed.connect(func(value:float):state.resident_scroll=int(value))
	var list:=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",6);scroll.add_child(list)
	for row in rows:
		var id:=int(row.entity_id)
		var b:=UI.button(list,"%s  ·  %s"%[row.display_name,row.occupation],"TownSelect%d"%id,id==int(state.resident))
		b.pressed.connect(func():state.resident=id;call_deferred("present",_view);resident_requested.emit(id))

func _guild()->void:
	var tutorial:Dictionary=_view.get("guild_tutorial",{}) if _view.get("guild_tutorial",{}) is Dictionary else {}
	UI.heading(self,"길드 튜토리얼","원정의 기본을 익히는 다섯 가지 선택형 의뢰")
	if not bool(tutorial.get("available",false)):
		UI.label(self,str(tutorial.get("message",tutorial.get("hint","마을에서만 확인할 수 있습니다."))),14,UI.MUTED)
		return
	UI.label(self,str(tutorial.get("hint","수락한 의뢰의 실제 행동만 기록됩니다.")),13,UI.MUTED)
	var list:=VBoxContainer.new();list.name="GuildTutorialQuestList";list.add_theme_constant_override("separation",8);add_child(list)
	for value in tutorial.get("quests",[]):
		if not value is Dictionary:continue
		var row:Dictionary=value
		var card:=UI.surface(list);card.name="GuildTutorial%s"%str(row.get("quest_id",""))
		var top:=HBoxContainer.new();top.add_theme_constant_override("separation",8);card.add_child(top)
		var title:=UI.label(top,"%s  ·  %s"%[str(row.get("title","의뢰")),str(row.get("status","AVAILABLE"))],16)
		title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		UI.label(card,str(row.get("description","")),13)
		var progress:Dictionary=row.get("progress",{}) if row.get("progress",{}) is Dictionary else {}
		var progress_text:=_guild_progress_text(row,progress)
		UI.label(card,progress_text,12,UI.MUTED)
		var actions:=HBoxContainer.new();actions.add_theme_constant_override("separation",6);card.add_child(actions)
		var quest_id:=str(row.get("quest_id",""))
		if bool(row.get("can_accept",false)):
			var accept:=UI.button(actions,"수락","GuildAccept%s"%quest_id,true)
			accept.pressed.connect(func():command_requested.emit({"action":"GUILD_TUTORIAL","quest_action":"ACCEPT","quest_id":quest_id}))
		if quest_id=="GUILD_TUTORIAL_HEAL" and bool(row.get("accepted",false)) \
				and not bool(row.get("completed",false)) and not bool(row.get("support_granted",false)):
			var support:=UI.button(actions,"지원 물약","GuildSupport%s"%quest_id)
			support.pressed.connect(func():command_requested.emit({"action":"GUILD_TUTORIAL","quest_action":"SUPPORT","quest_id":quest_id}))
		if bool(row.get("can_claim",false)):
			var claim:=UI.button(actions,"보상 받기","GuildClaim%s"%quest_id,true)
			claim.pressed.connect(func():command_requested.emit({"action":"GUILD_TUTORIAL","quest_action":"CLAIM","quest_id":quest_id}))

func _guild_progress_text(row:Dictionary,progress:Dictionary)->String:
	var status:=str(row.get("status","AVAILABLE"))
	if status=="CLAIMED":return "완료 · 보상을 받았습니다 · %s"%str(row.get("reward_text",""))
	if status=="AVAILABLE":return "권장 보상 · %s"%str(row.get("reward_text",""))
	var quest_id:=str(row.get("quest_id",""))
	if quest_id=="GUILD_TUTORIAL_MOVE":
		return "진행 %d/3 · 대각선 %s · 보상 %s"%[int(progress.get("count",0)),"완료" if bool(progress.get("diagonal",false)) else "필요",str(row.get("reward_text",""))]
	if quest_id=="GUILD_TUTORIAL_GUARD":
		return "대기 방어 %s · 유효 공격 %s · 보상 %s"%["완료" if bool(progress.get("hold_done",false)) else "필요","완료" if bool(progress.get("attack_done",false)) else "필요",str(row.get("reward_text",""))]
	return "진행 %d/1 · 보상 %s"%[int(progress.get("count",0)),str(row.get("reward_text",""))]

func _resident_detail(row:Dictionary)->void:
	var id:=int(row.entity_id)
	var card:=UI.surface(self);card.name="TownResidentDetail"
	var top:=HBoxContainer.new();top.add_theme_constant_override("separation",10);card.add_child(top)
	UI.portrait(top,id,52,str(row.get("species_id","human")))
	var text:=VBoxContainer.new();text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;top.add_child(text)
	UI.label(text,str(row.display_name),19)
	UI.label(text,"%s · %s"%[row.occupation,row.temperament],13,UI.MUTED)
	var inspect:=UI.button(top,"상태창","TownInspect%d"%id);inspect.size_flags_horizontal=Control.SIZE_FILL
	inspect.pressed.connect(func():resident_requested.emit(id))
	var hp:=ProgressBar.new();hp.max_value=row.max_health;hp.value=row.health;hp.show_percentage=false
	hp.custom_minimum_size.y=6;card.add_child(hp);UI.Palette.apply_progress(hp,UI.Palette.JADE)
	UI.label(card,"%s · %s"%[row.location,row.activity],13,UI.MUTED)
	var actions:=GridContainer.new();actions.columns=2;actions.add_theme_constant_override("h_separation",8);actions.add_theme_constant_override("v_separation",6);card.add_child(actions)
	if not row.joined:
		_action(actions,"대화" if row.can_talk else "대화 완료","TALK",id,bool(row.can_talk))
		if row.adventurer:
			_action(actions,"동행 제안","JOIN",id,bool(row.can_join),true)
			if not row.can_join:UI.label(card,str(row.join_reason),12,UI.MUTED)
	else:
		if row.can_reserve:_action(actions,"마을에 대기","RESERVE",id,true)
		elif not row.active:_action(actions,"원정에 편성","ASSIGN",id,bool(row.can_assign),true)
		_action(actions,"휴식 · 15 G","REST",id,bool(row.can_rest))
		if row.can_talk:_action(actions,"대화","TALK",id,true)

func _action(parent:Control,title:String,action:String,id:int,available:bool,primary:bool=false)->void:
	var b:=UI.button(parent,title,"Town%s%d"%[action,id],primary);b.disabled=not available
	b.pressed.connect(func():command_requested.emit({"action":action,"entity_id":str(id)}))
