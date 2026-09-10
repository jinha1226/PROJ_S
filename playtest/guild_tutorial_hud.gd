extends MenuButton
## Time-free, single-line overlay; never adds entries to the combat log.
const PixelSkin=preload("res://playtest/dark_pixel_ui_skin.gd")
var selected_id:=""
var folded:=false
var rows:Array=[]
var completed:Dictionary={}
var identity:=0
var initialized:=false
var notice:=""
var notice_until:=0
var completion_notices:=0
var help_dialog:AcceptDialog

func _ready():
	name="GuildTutorialHUD";clip_text=true;custom_minimum_size.y=44
	add_theme_font_size_override("font_size",11)
	PixelSkin.apply_action_button(self,PixelSkin.BRASS)
	get_popup().id_pressed.connect(_select)
	get_popup().about_to_popup.connect(_menu)
	help_dialog=AcceptDialog.new();help_dialog.title="길드 의뢰 안내";add_child(help_dialog)
	help_dialog.get_label().autowrap_mode=TextServer.AUTOWRAP_WORD_SMART

func present(dto:Dictionary,world_identity:int,in_dungeon:bool):
	if identity!=world_identity:
		identity=world_identity;initialized=false;completed.clear();notice="";selected_id=""
	rows=[]
	for row in dto.get("quests",[]):
		if not row.accepted:continue
		var id:String=row.quest_id
		if initialized and row.completed and not completed.get(id,false):
			notice="완료 · %s — 귀환 후 길드 보고"%str(row.title)
			if id.ends_with("INJURY"):notice=limb_names(row)+" 부상 · 초상화 길게 눌러 상태 확인"
			notice_until=Time.get_ticks_msec()+6000;completion_notices+=1
		completed[id]=row.completed
		if not row.claimed:rows.append(row)
	initialized=true
	visible=in_dungeon and not rows.is_empty()
	var chosen:Dictionary={}
	for row in rows:
		if row.quest_id==selected_id:chosen=row
	if chosen.is_empty() and not rows.is_empty():chosen=rows[0];selected_id=str(chosen.quest_id)
	if chosen.is_empty():return
	if folded:text="의뢰"
	elif not notice.is_empty() and Time.get_ticks_msec()<notice_until:text=notice
	else:text="의뢰 · %s · %s ▴"%[chosen.title,progress_text(chosen)]
	tooltip_text=str(chosen.description)+"\n"+str(chosen.hint)+"\n눌러서 의뢰 선택 / 안내 숨기기"

static func progress_text(row:Dictionary)->String:
	if str(row.quest_id).ends_with("INJURY") and row.completed:return limb_names(row)+" · 상태 확인"
	if row.completed:return "완료 · 길드 보고"
	var p:Dictionary=row.progress
	if str(row.quest_id).ends_with("MOVE"):return "%d/3 · 대각선 %s"%[p.count,"✓" if p.diagonal else "필요"]
	if str(row.quest_id).ends_with("GUARD"):return "방어 %s · 공격 %s"%["✓" if p.hold_done else "—","✓" if p.attack_done else "—"]
	if str(row.quest_id).ends_with("HEAL"):return "부상 후 물약 회복"
	if str(row.quest_id).ends_with("RETURN"):return "1층 전리품 확보 후 귀환"
	if str(row.quest_id).ends_with("BIND"):return "효과 확인 후 이능 결속"
	if str(row.quest_id).ends_with("SKILL"):return "액티브 스킬 실행"
	if str(row.quest_id).ends_with("UPGRADE"):return "마을에서 무기 재제작"
	if str(row.quest_id).ends_with("INJURY"):return "자연스러운 전투 부상 시 안내"
	if str(row.quest_id).ends_with("TREAT"):return "부상 후 치유소 · HP 물약과 별개"
	return "1층 새 전리품 줍기"

static func limb_names(row:Dictionary)->String:
	var labels:={"LEFT_ARM":"왼팔","RIGHT_ARM":"오른팔","LEFT_LEG":"왼다리","RIGHT_LEG":"오른다리"}
	var parts:Array[String]=[]
	for part in row.progress.get("injured_parts",[]):parts.append(str(labels.get(str(part),part)))
	return ", ".join(parts)

func _menu():
	var popup:=get_popup();popup.clear()
	for i in range(rows.size()):popup.add_check_item(str(rows[i].title),i);popup.set_item_checked(i,rows[i].quest_id==selected_id)
	popup.add_separator();popup.add_item("안내 펼치기" if folded else "안내 숨기기",100)
	popup.add_item("목표 · 조작 도움말",101)

func _select(id:int):
	if id==101:
		for row in rows:
			if row.quest_id==selected_id:
				help_dialog.dialog_text=str(row.title)+"\n\n"+str(row.description)+"\n\n"+str(row.hint)+"\n\n보상: "+str(row.reward_text)
				if not row.progress.get("injured_parts",[]).is_empty():help_dialog.dialog_text+="\n\n확인된 부상: "+limb_names(row)
				help_dialog.popup_centered(Vector2i(mini(320,int(get_viewport_rect().size.x)-24),260))
		return
	if id==100:folded=not folded
	elif id>=0 and id<rows.size():selected_id=str(rows[id].quest_id);folded=false
	notice=""
	anchor_right=0.0 if folded else 1.0
	offset_right=52 if folded else -4
	present({"quests":rows},identity,true)
