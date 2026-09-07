class_name NpcSkillPanel
extends VBoxContainer

## Read-only skill folio for companions and recruitable NPCs. Their persistent
## mastery ledger is not authoritative yet, so this surface shows only skills
## that can be derived from their real species and equipped weapon.

const DarkSkin = preload("res://playtest/dark_pixel_ui_skin.gd")

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
	var summary:Dictionary=_detail.get("skill_summary",{}) \
		if _detail.get("skill_summary",{}) is Dictionary else {}
	var skills:Array=[]
	for value in summary.get("skills",[]):
		if value is Dictionary:skills.append(value.duplicate(true))
	if skills.is_empty():
		add_child(_label("확인할 수 있는 스킬이 없습니다.",12,DarkSkin.BONE_DIM))
	else:
		for skill in skills:_add_skill_card(skill)
	_snapshot={"available":bool(summary.get("available",false)),
		"skill_count":skills.size(),"read_only":true,
		"uses_authoritative_loadout":true}.duplicate(true)
	update_minimum_size()


func _add_skill_card(skill:Dictionary)->void:
	var panel:=PanelContainer.new();panel.name="NpcSkillCard"
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	DarkSkin.apply_panel(panel,"SECTION")
	add_child(panel)
	var stack:=VBoxContainer.new();stack.add_theme_constant_override("separation",3);panel.add_child(stack)
	var heading:=HBoxContainer.new();heading.add_theme_constant_override("separation",5);stack.add_child(heading)
	var category:=_label(str(skill.get("category","스킬")),11,DarkSkin.CYAN)
	category.custom_minimum_size.x=62;heading.add_child(category)
	var title:=_label(str(skill.get("label","기술")),16,DarkSkin.BONE)
	title.name="NpcSkillName";title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("font",DarkSkin.PixelFont);heading.add_child(title)
	var trigger:=str(skill.get("trigger_label","")).strip_edges()
	if not trigger.is_empty():heading.add_child(_label(trigger,11,DarkSkin.BRASS))
	var summary:=str(skill.get("summary","")).strip_edges()
	if not summary.is_empty():
		var summary_label:=_label(summary,12,DarkSkin.BONE);summary_label.name="NpcSkillSummary"
		summary_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;stack.add_child(summary_label)
	var detail_text:=str(skill.get("detail","")).strip_edges()
	if not detail_text.is_empty():
		var detail_label:=_label(detail_text,11,DarkSkin.BONE_DIM);detail_label.name="NpcSkillDetail"
		detail_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;stack.add_child(detail_label)


func _label(value:String,font_size:int,tone:Color)->Label:
	var result:=Label.new();result.text=value;result.mouse_filter=Control.MOUSE_FILTER_IGNORE
	result.add_theme_font_override("font",DarkSkin.PixelFont)
	result.add_theme_font_size_override("font_size",font_size)
	result.add_theme_color_override("font_color",tone);return result
