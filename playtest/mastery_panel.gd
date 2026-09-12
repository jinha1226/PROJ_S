extends VBoxContainer

const Growth=preload("res://game/rebuilt/progression.gd")
const PixelSkin=preload("res://playtest/dark_pixel_ui_skin.gd")
var session
var summary:Label
var progress:ProgressBar
var rows:Dictionary={}
var confirm:ConfirmationDialog
var pending:Dictionary={}
signal changed

func _ready()->void:
	name="MasteryPanel";add_theme_constant_override("separation",6)
	summary=Label.new();summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(summary)
	progress=ProgressBar.new();progress.custom_minimum_size.y=12;progress.show_percentage=false;add_child(progress)
	progress.visible=false
	var grid:=GridContainer.new();grid.name="MasteryGrid";grid.columns=2
	grid.add_theme_constant_override("h_separation",6);grid.add_theme_constant_override("v_separation",6);add_child(grid)
	for definition in Growth.DATA.axes:
		var axis:String=definition.id
		var card:=PanelContainer.new();card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel",PixelSkin.panel_surface(PixelSkin.SLOT_FILLED,PixelSkin.BRASS_DARK,6,1));grid.add_child(card)
		var stack:=VBoxContainer.new();card.add_child(stack)
		var heading:=HBoxContainer.new();stack.add_child(heading)
		var emblem:=preload("res://playtest/growth_emblem.gd").new();emblem.symbol=axis;heading.add_child(emblem)
		var title:=Label.new();title.add_theme_font_size_override("font_size",14);heading.add_child(title)
		PixelSkin.apply_heading(title)
		var row:=HBoxContainer.new();stack.add_child(row)
		var info:=Label.new();info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;info.add_theme_font_size_override("font_size",14);row.add_child(info)
		var button:=Button.new();button.text="+";button.custom_minimum_size=Vector2(44,44)
		button.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		button.pressed.connect(preview.bind(axis));row.add_child(button);PixelSkin.apply_action_button(button,PixelSkin.BRASS)
		rows[axis]={"info":info,"button":button,"title":title}
	var note:=Label.new();note.text="전투 밖에서 투자 · 재분배 불가"
	note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.add_theme_font_size_override("font_size",11);add_child(note)
	confirm=ConfirmationDialog.new();confirm.title="숙련 투자";confirm.ok_button_text="1점 투자"
	confirm.cancel_button_text="취소";confirm.get_label().autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	confirm.confirmed.connect(commit);confirm.canceled.connect(func():pending.clear());add_child(confirm)

func refresh(owner_session)->void:
	session=owner_session
	var status:Dictionary=session.mastery_status()
	if status.is_empty():return
	var registry=session.GrowthBuildRegistryScript
	var floor_xp:int=registry.xp_floor_for_level(status.level)
	var next_xp:int=registry.xp_floor_for_level(int(status.level)+1)
	summary.text="숙련 · 남은 포인트 %d"%status.points
	PixelSkin.apply_heading(summary)
	progress.min_value=floor_xp;progress.max_value=maxi(floor_xp+1,next_xp);progress.value=status.xp
	var safety:Dictionary=session._auto_explore_stop_snapshot()
	var safe:bool=safety.get("visible_enemy_keys",{}).is_empty() and str(safety.get("safe_phase","")) in ["GROUPED","GROUPED_COMPLETE"]
	if not safe:summary.text+=" · 전투 중"
	for definition in Growth.DATA.axes:
		var axis:String=definition.id;var rank:int=status.ranks[axis]
		var per_rank:int=Growth.DATA.defense_per_rank_milli if axis=="DEFENSE" else Growth.DATA.attack_per_rank_milli
		rows[axis].title.text="%s %d/%d"%[definition.label,rank,status.max_rank]
		rows[axis].info.text="%s\n+%d%%"%[
			"방어·회피·막기" if axis=="DEFENSE" else "공격·이능 효과",rank*per_rank/10]
		rows[axis].button.disabled=status.points<1 or rank>=status.max_rank or not safe
		rows[axis].button.tooltip_text="전투 중에는 투자할 수 없습니다." if not safe else \
			("숙련 포인트가 없습니다." if status.points<1 else ("최대 숙련입니다." if rank>=status.max_rank else "1점 투자"))

func preview(axis:String)->void:
	var status:Dictionary=session.mastery_status()
	pending={"axis":axis,"rank":status.ranks[axis],"points":status.points}
	var per_rank:int=Growth.DATA.defense_per_rank_milli if axis=="DEFENSE" else Growth.DATA.attack_per_rank_milli
	var multiplier:=1000+int(pending.rank)*per_rank
	confirm.dialog_text="1점을 투자할까요?\n효과 ×%.2f → ×%.2f\n%s\n현재 재분배할 수 없습니다."%[multiplier/1000.0,(multiplier+per_rank)/1000.0,
		"보호·회피·막기 수치 강화 (정수 반올림)" if axis=="DEFENSE" else "해당 계열 공격·이능 효과 강화"]
	confirm.popup_centered(Vector2i(mini(330,int(get_viewport_rect().size.x)-24),190))

func commit()->void:
	var action:=pending.duplicate();pending.clear()
	if action.is_empty():return
	var status:Dictionary=session.mastery_status()
	if status.points!=action.points or status.ranks[action.axis]!=action.rank:return
	var result:Dictionary=session.spend_mastery_point(action.axis)
	refresh(session)
	if result.accepted:changed.emit()
	else:summary.text+="\n지금은 투자할 수 없습니다. 안전한 곳에서 시도하세요."
