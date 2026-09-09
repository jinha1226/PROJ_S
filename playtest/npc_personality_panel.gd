class_name NpcPersonalityPanel
extends VBoxContainer

const DarkSkin = preload("res://playtest/dark_pixel_ui_skin.gd")

const FACET_NAMES := {
	"H":"정직·겸손", "E":"정서성", "X":"외향성",
	"A":"원만성", "C":"성실성", "O":"개방성",
}

var _detail:Dictionary={}
var _snapshot:Dictionary={}


func _ready()->void:
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	add_theme_constant_override("separation",8)
	mouse_filter=Control.MOUSE_FILTER_IGNORE


func set_detail(value:Dictionary)->void:
	_detail=value.duplicate(true)
	_rebuild()


func presentation_snapshot()->Dictionary:
	return _snapshot.duplicate(true)


func _rebuild()->void:
	for child in get_children():
		remove_child(child);child.free()
	var style:Dictionary=_detail.get("personality_style",{}) \
		if _detail.get("personality_style",{}) is Dictionary else {}
	var facets:Array=[]
	for value in _detail.get("personality_facets",[]):
		if value is Dictionary:facets.append(value.duplicate(true))
	var emotion:Dictionary=_detail.get("emotion",{}) \
		if _detail.get("emotion",{}) is Dictionary else {}
	_add_summary_card(str(style.get("label","성향 정보 없음")),facets)
	_add_emotion_card(emotion)
	_snapshot={"style_label":str(style.get("label","")),"facet_count":facets.size(),
		"shows_current_emotion":true,"contains_relationships":false,
		"uses_visual_bars":true}.duplicate(true)
	update_minimum_size()


func _add_summary_card(style_label:String,facets:Array)->void:
	var panel:=_surface("PersonalitySummary",Color("#091519"),6)
	add_child(panel)
	var stack:=VBoxContainer.new();stack.add_theme_constant_override("separation",4);panel.add_child(stack)
	stack.add_child(_label("성격 유형",12,DarkSkin.CYAN))
	var title:=_label(style_label,20,DarkSkin.BONE);title.name="PersonalityStyleLabel"
	title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_override("font",DarkSkin.PixelFont);stack.add_child(title)
	for raw in facets:
		_add_facet_row(stack,raw)


func _add_facet_row(parent:VBoxContainer,facet:Dictionary)->void:
	var value:=clampi(int(facet.get("value",500)),0,1000)
	var low:=str(facet.get("low_label","낮음"));var high:=str(facet.get("high_label","높음"))
	var facet_id:=str(facet.get("facet_id",""))
	var row:=VBoxContainer.new();row.name="PersonalityFacet%s"%facet_id
	row.add_theme_constant_override("separation",1);parent.add_child(row)
	var heading:=HBoxContainer.new();heading.add_theme_constant_override("separation",4);row.add_child(heading)
	var name_label:=_label(str(FACET_NAMES.get(facet_id,facet_id)),13,DarkSkin.BONE)
	name_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.add_child(name_label)
	var band:=_label(_facet_band(value,low,high),12,_facet_tone(value));band.name="FacetBand"
	heading.add_child(band)
	var axis:=HBoxContainer.new();axis.add_theme_constant_override("separation",5);row.add_child(axis)
	var low_label:=_label(low,10,DarkSkin.BONE_DIM);low_label.custom_minimum_size.x=44;axis.add_child(low_label)
	var bar:=ProgressBar.new();bar.name="FacetGauge";bar.min_value=0;bar.max_value=1000;bar.value=value
	bar.show_percentage=false;bar.custom_minimum_size=Vector2(0,7)
	bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL;bar.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	DarkSkin.apply_progress(bar,_facet_tone(value));axis.add_child(bar)
	var high_label:=_label(high,10,DarkSkin.BONE_DIM);high_label.custom_minimum_size.x=44
	high_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;axis.add_child(high_label)


func _add_emotion_card(emotion:Dictionary)->void:
	var panel:=_surface("CurrentEmotionCard",Color("#081216"),6);add_child(panel)
	var stack:=VBoxContainer.new();stack.add_theme_constant_override("separation",2);panel.add_child(stack)
	stack.add_child(_label("현재 감정",12,DarkSkin.CYAN))
	var title:=_label("%s  %s"%[str(emotion.get("icon","●")),str(emotion.get("label","침착"))],17,DarkSkin.BONE)
	title.name="CurrentEmotionLabel";title.add_theme_font_override("font",DarkSkin.PixelFont);stack.add_child(title)
	var reason:=_label(str(emotion.get("reason","뚜렷한 감정 변화가 없습니다.")),12,DarkSkin.BONE_DIM)
	reason.name="CurrentEmotionReason";reason.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;stack.add_child(reason)


func _surface(node_name:String,color:Color,margin:int)->PanelContainer:
	var panel:=PanelContainer.new();panel.name=node_name;panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel",DarkSkin.panel_surface(
		color,DarkSkin.IRON_SHADOW,margin,1))
	panel.set_meta("visual_family",DarkSkin.VISUAL_FAMILY);return panel


func _label(value:String,font_size:int,tone:Color)->Label:
	var result:=Label.new();result.text=value;result.mouse_filter=Control.MOUSE_FILTER_IGNORE
	result.add_theme_font_override("font",DarkSkin.PixelFont)
	result.add_theme_font_size_override("font_size",font_size)
	result.add_theme_color_override("font_color",tone);return result


func _facet_band(value:int,low:String,high:String)->String:
	if value<=300:return low
	if value>=700:return high
	return "균형"


func _facet_tone(value:int)->Color:
	return DarkSkin.BRASS if value<=300 else (DarkSkin.CYAN if value>=700 else DarkSkin.BONE_DIM)
