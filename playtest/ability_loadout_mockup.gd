extends VBoxContainer

## Presentation-only experiment. No command, save, inventory or combat mutation.
const PixelSkin=preload("res://playtest/dark_pixel_ui_skin.gd")
var actor_id:=-1
var slots:Array=[]
var drafts:Dictionary={}
var owned:Array=[]
var selected_slot:=0
var slot_grid:GridContainer
var summary:Label
var picker:VBoxContainer
var mode_button:Button

func _ready()->void:
	name="AbilityLoadoutMockup"
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",8)
	var title:=Label.new();title.text="이능 장착 · 6칸";add_child(title)
	var help:=Label.new();help.text="레이아웃 목업 · 변경은 전투에 적용되거나 저장되지 않습니다.\n칸 선택 → 보유 이능 선택 → 액티브/패시브 전환"
	help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;help.add_theme_font_size_override("font_size",11);add_child(help)
	summary=Label.new();add_child(summary)
	slot_grid=GridContainer.new();slot_grid.name="AbilitySlots";slot_grid.columns=2
	slot_grid.add_theme_constant_override("h_separation",6);slot_grid.add_theme_constant_override("v_separation",6);add_child(slot_grid)
	for i in range(6):
		var button:=Button.new();button.name="AbilitySlot%d"%i
		button.custom_minimum_size=Vector2(0,68);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.clip_text=true;button.pressed.connect(_select.bind(i));slot_grid.add_child(button)
	var actions:=HBoxContainer.new();add_child(actions)
	mode_button=Button.new();mode_button.text="운용 전환";mode_button.custom_minimum_size.y=44
	mode_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;mode_button.pressed.connect(_toggle_mode);actions.add_child(mode_button);PixelSkin.apply_action_button(mode_button)
	var remove:=Button.new();remove.text="해제";remove.custom_minimum_size.y=44;remove.pressed.connect(func():slots[selected_slot]={};_refresh())
	actions.add_child(remove);PixelSkin.apply_action_button(remove)
	var label:=Label.new();label.text="보유 이능 · 미리보기용";add_child(label)
	picker=VBoxContainer.new();add_child(picker)
	if not slots.is_empty():_refresh()

func configure(id:int,rows:Array)->void:
	actor_id=id;owned=[]
	for row in rows:
		owned.append({"id":str(row.skill_id),"label":str(row.label),"mode":"ACTIVE"})
	# Deliberately marked examples: they are not granted to the character.
	owned.append({"id":"MOCK_REGEN","label":"재생 · 예시","mode":"PASSIVE"})
	owned.append({"id":"MOCK_INSULATE","label":"절연 · 예시","mode":"PASSIVE"})
	if not drafts.has(id):
		var initial:Array=[]
		for i in range(6):initial.append(owned[i].duplicate(true) if i<mini(rows.size(),3) else {})
		drafts[id]=initial
	slots=drafts[id];selected_slot=0
	if slot_grid!=null:_refresh()

func _select(index:int)->void:
	selected_slot=index;_refresh()

func _active_count()->int:
	var count:=0
	for row in slots:
		if row.get("mode","")=="ACTIVE":count+=1
	return count

func _equip(row:Dictionary)->void:
	for i in range(slots.size()):
		if i!=selected_slot and slots[i].get("id","")==row.id:return
	var value:=row.duplicate(true)
	if value.mode=="ACTIVE" and _active_count()>=3 and slots[selected_slot].get("mode","")!="ACTIVE":value.mode="PASSIVE"
	slots[selected_slot]=value;_refresh()

func _toggle_mode()->void:
	if slots[selected_slot].is_empty():return
	if slots[selected_slot].mode=="PASSIVE" and _active_count()>=3:return
	slots[selected_slot].mode="PASSIVE" if slots[selected_slot].mode=="ACTIVE" else "ACTIVE"
	_refresh()

func _refresh()->void:
	var active:=_active_count();var equipped:=0
	for i in range(6):
		var row:Dictionary=slots[i];var button:=slot_grid.get_child(i) as Button
		if not row.is_empty():equipped+=1
		button.text="%d  + 빈 슬롯"%(i+1) if row.is_empty() else "%d  %s\n%s"%[i+1,row.label,"액티브" if row.mode=="ACTIVE" else "패시브"]
		PixelSkin.apply_action_button(button,PixelSkin.BRASS if i==selected_slot else PixelSkin.CYAN)
	summary.text="장착 %d / 6    액티브 %d / 3    패시브 %d"%[equipped,active,equipped-active]
	mode_button.disabled=slots[selected_slot].is_empty()
	for child in picker.get_children():picker.remove_child(child);child.queue_free()
	for row in owned:
		var button:=Button.new();button.text=str(row.label);button.custom_minimum_size.y=44
		for i in range(6):
			if i!=selected_slot and slots[i].get("id","")==row.id:button.disabled=true
		button.pressed.connect(_equip.bind(row));picker.add_child(button);PixelSkin.apply_action_button(button)
