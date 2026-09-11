extends AcceptDialog

signal changed
const Growth=preload("res://game/rebuilt/progression.gd")
const Gear=preload("res://game/rebuilt/equipment.gd")
var world
var member:OptionButton
var summary:Label
var progress:ProgressBar
var cards:Array[Label]=[]
var invest_buttons:Array[Button]=[]
var gear_text:Label
var equipment:OptionButton
var equip_button:Button
var ability_text:Label
var bind_button:Button
var confirm:ConfirmationDialog
var pending:Dictionary={}

func _ready()->void:
	title="캐릭터 성장";get_ok_button().text="닫기"
	var column:=VBoxContainer.new();add_child(column)
	member=OptionButton.new();member.custom_minimum_size.y=42;column.add_child(member)
	member.item_selected.connect(func(_index):refresh())
	var tabs:=TabContainer.new();tabs.custom_minimum_size=Vector2(370,440);column.add_child(tabs)
	var training:=VBoxContainer.new();training.name="숙련";tabs.add_child(training)
	summary=Label.new();training.add_child(summary)
	progress=ProgressBar.new();progress.custom_minimum_size.y=12;progress.show_percentage=false;training.add_child(progress)
	for i in range(Growth.IDS.size()):
		var row:=HBoxContainer.new();row.custom_minimum_size.y=77;training.add_child(row)
		var info:=Label.new();info.size_flags_horizontal=Control.SIZE_EXPAND_FILL;info.add_theme_font_size_override("font_size",14);row.add_child(info);cards.append(info)
		var button:=Button.new();button.text="+1";button.custom_minimum_size=Vector2(56,52);row.add_child(button)
		button.pressed.connect(func():preview_invest(i));invest_buttons.append(button)
	var note:=Label.new();note.text="레벨업마다 1점 · 전투 밖 투자\n미리보기 후 확정 · 현재 재분배 미지원";note.add_theme_font_size_override("font_size",13);training.add_child(note)
	var gear:=VBoxContainer.new();gear.name="장비";tabs.add_child(gear)
	gear_text=Label.new();gear_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;gear_text.custom_minimum_size.y=120;gear.add_child(gear_text)
	equipment=OptionButton.new();equipment.custom_minimum_size.y=44;gear.add_child(equipment)
	equip_button=Button.new();equip_button.text="장착 · 행동 시간 100";equip_button.custom_minimum_size.y=44;gear.add_child(equip_button)
	equip_button.pressed.connect(func():
		if world.submit("EQUIP",equipment.selected):changed.emit()
		refresh())
	var abilities:=VBoxContainer.new();abilities.name="이능";tabs.add_child(abilities)
	ability_text=Label.new();ability_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;ability_text.custom_minimum_size.y=170;abilities.add_child(ability_text)
	bind_button=Button.new();bind_button.text="화염탄 정수 결속";bind_button.custom_minimum_size.y=44;abilities.add_child(bind_button)
	bind_button.pressed.connect(func():
		pending={"kind":"bind"}
		confirm.dialog_text="정수 1개를 소비하고 결속 1칸을 사용합니다.\n현재 해제할 수 없습니다. 결속할까요?"
		confirm.popup_centered(Vector2i(340,180)))
	confirm=ConfirmationDialog.new();add_child(confirm)
	confirm.confirmed.connect(commit_pending)
	confirm.canceled.connect(func():pending.clear())
	close_requested.connect(func():pending.clear())

func selected_actor()->Dictionary:
	return world.actors[member.get_selected_id()]

func open(p_world)->void:
	world=p_world;pending.clear();member.clear()
	member.add_item("나",0)
	for ally in world.companions():member.add_item("동료" if ally.hp>0 else "동료 · 사망",ally.id)
	refresh();popup_centered(Vector2i(400,540))

func refresh()->void:
	var actor:=selected_actor()
	var g:Dictionary=actor.growth
	summary.text="레벨 %d   ·   남은 숙련 포인트 %d\n%s"%[g.level,g.points,
		"최고 레벨" if g.level>=Growth.DATA.max_level else "경험치 %d / %d"%[g.xp,Growth.threshold(int(g.level)+1)]]
	progress.min_value=Growth.threshold(g.level);progress.max_value=maxi(int(progress.min_value)+1,Growth.threshold(mini(g.level+1,Growth.DATA.max_level)))
	progress.value=g.xp
	for i in range(Growth.IDS.size()):
		var axis:String=Growth.IDS[i]
		var row:Dictionary=Growth.DATA.axes[i]
		var rank:int=g.ranks[axis]
		var current:String="피해 감소 %d%%"%[Growth.reduction(actor)/10] if axis=="DEFENSE" else "효과량 ×%.2f"%[Growth.multiplier(actor,axis)/1000.0]
		cards[i].text="%s  %d/%d · %s\n%s"%[row.label,rank,Growth.DATA.max_rank,current,row.description]
		invest_buttons[i].disabled=actor.hp<=0 or g.points<1 or rank>=Growth.DATA.max_rank or not world.visible_enemies().is_empty()
	gear_text.text=Gear.description(actor)
	var choice:=equipment.selected;equipment.clear()
	for id in world.inventory:equipment.add_item(Gear.ITEMS[id].label)
	if choice>=0 and choice<equipment.item_count:equipment.select(choice)
	equip_button.disabled=actor.id!=0 or actor.hp<=0
	if actor.id!=0:gear_text.text+="\n동료 장비는 보기 전용입니다."
	var has_fire:bool="FIREBOLT" in actor.bound_abilities
	ability_text.text="결속 %d/%d · MP %d/%d\n화염탄: %s\n마법 숙련 적용 피해 %d · MP %d\n\n보관 정수 %d개\n정수는 화염탄 사용자에게 획득합니다.\n속성 전체와 다른 이능은 미연결입니다."%[
		actor.bound_abilities.size(),world.Binding.slot_limit(g.level),actor.mp,actor.max_mp,
		"사용 가능" if has_fire else "미결속",Growth.scale(actor,"MAGIC",int(Growth.DATA.actions.FIREBOLT.power)),Growth.DATA.actions.FIREBOLT.mp,world.fire_essences]
	bind_button.disabled=actor.id!=0 or actor.hp<=0 or has_fire or world.fire_essences<1

func preview_invest(index:int)->void:
	var actor:=selected_actor();var axis:String=Growth.IDS[index]
	pending={"kind":"invest","actor":actor.id,"axis":axis,"rank":actor.growth.ranks[axis],"points":actor.growth.points}
	var usage:String=Growth.DATA.axes[index].description
	if axis in ["MELEE","RANGED"]:
		var values:Dictionary=Gear.stats(actor)
		usage="현재 장비: "+Gear.ITEMS[actor.gear.weapon].label+(" · 적용" if values.skill==axis else " · 다른 계열")
	elif axis=="MAGIC":usage="화염탄 · "+("결속됨" if "FIREBOLT" in actor.bound_abilities else "미결속: 먼저 이능 획득 필요")
	confirm.dialog_text="%s 숙련에 1점을 투자할까요?\n%s\n%s\n현재 재분배 미지원"%[Growth.DATA.axes[index].label,Growth.preview(actor,axis),usage]
	confirm.popup_centered(Vector2i(350,200))

func commit_pending()->void:
	var action:=pending.duplicate();pending.clear()
	if action.is_empty():return
	var accepted:=false
	if action.kind=="bind":accepted=world.submit("BIND_FIRE")
	elif action.actor<world.actors.size():
		var actor:Dictionary=world.actors[action.actor]
		if actor.growth.points==action.points and actor.growth.ranks[action.axis]==action.rank:
			accepted=world.invest(action.actor,action.axis)
	if accepted:changed.emit()
	else:
		world.message("지금은 투자·결속할 수 없습니다.")
		changed.emit()
	refresh()
