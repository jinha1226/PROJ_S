extends HBoxContainer

signal finished
signal feedback(message:String)
var session
var actor_id:=-1
var action_type:=""
var destination:Array=[]
var target_id:=-1
var confirm:Button

func _init()->void:visible=false

func _ready()->void:
	custom_minimum_size.y=48
	add_theme_constant_override("separation",3)
	for entry in [["취소","CLOSE"],["이동","MOVE"],["공격","MELEE"],["대기","HOLD"],["예약","CONFIRM"]]:
		var button:=Button.new();button.text=entry[0];button.custom_minimum_size=Vector2(44,48)
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		preload("res://playtest/dark_pixel_ui_skin.gd").apply_action_button(button)
		button.pressed.connect(_select.bind(str(entry[1])))
		add_child(button)
		if entry[1]=="CONFIRM":confirm=button;confirm.disabled=true
	visible=false

func begin(value,member_id:int)->void:
	session=value;actor_id=member_id;action_type="";destination=[];target_id=-1
	confirm.disabled=true;visible=true
	feedback.emit("%s · 다음 행동 1회 지시"%str(session.inspect_party_member(actor_id).get("display_name","동료")))

func _select(kind:String)->void:
	if not visible:return
	if kind=="CLOSE":close();return
	if kind=="CONFIRM":
		var result:Dictionary=session.reserve_companion_action(actor_id,action_type,destination,target_id)
		feedback.emit(str(result.get("message","")))
		if result.get("accepted",false):close()
		return
	action_type=kind;destination=[];target_id=-1
	confirm.disabled=kind!="HOLD"
	feedback.emit("예약을 누르면 대기를 지시합니다." if kind=="HOLD" else "이동할 인접 칸을 누르세요." if kind=="MOVE" else "공격할 인접 적을 누르세요.")

func pick_cell(cell:Vector2i)->void:
	if action_type!="MOVE":return
	destination=[cell.x,cell.y];_validate()

func pick_actor(id:int)->void:
	if action_type!="MELEE":return
	target_id=id;_validate()

func _validate()->void:
	session.prepare_auto_combat_plan()
	var result:Dictionary=session.preview_actor_action(actor_id,action_type,destination,target_id)
	confirm.disabled=not result.get("accepted",false)
	feedback.emit("선택한 행동을 예약할까요?" if not confirm.disabled else str(result.get("message","지금 실행할 수 없는 행동입니다.")))

func close()->void:
	visible=false;actor_id=-1;finished.emit()
