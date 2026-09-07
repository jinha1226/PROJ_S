class_name NpcRelationshipPanel
extends VBoxContainer

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
	var relations:Array=[]
	for value in _detail.get("relation_rows",[]):
		if value is Dictionary:relations.append(value.duplicate(true))
	var affinity:Dictionary=_detail.get("affinity_toward_protagonist",{}) \
		if _detail.get("affinity_toward_protagonist",{}) is Dictionary else {}
	var player_relation:Dictionary={};var other_relations:Array=[]
	for raw in relations:
		var relation:Dictionary=raw
		if player_relation.is_empty() and not affinity.is_empty() \
				and _same_relation_values(relation,affinity):
			player_relation=relation
		else:other_relations.append(relation)
	var card_count:=0
	# The inspected NPC's relationship toward the protagonist is always the first
	# row. The old standalone affinity line is represented only through this card.
	if not affinity.is_empty():
		_add_relationship_card(player_relation,affinity,true);card_count+=1
	for relation in other_relations:
		_add_relationship_card(relation,{},false);card_count+=1
	if affinity.is_empty() and not player_relation.is_empty():
		_add_relationship_card(player_relation,{},false);card_count+=1
	if card_count==0:add_child(_label("아직 형성된 관계가 없습니다.",12,DarkSkin.BONE_DIM))
	_snapshot={"relationship_count":card_count,"player_listed_first":not affinity.is_empty(),
		"affinity_merged_into_player_row":not affinity.is_empty(),
		"standalone_affinity_row":false,"contains_personality":false,
		"uses_visual_bars":true}.duplicate(true)
	update_minimum_size()


func _add_relationship_card(relation:Dictionary,affinity:Dictionary,is_player:bool)->void:
	var score:=int(affinity.get("score",_relationship_score(relation)))
	var disposition:=str(affinity.get("disposition",relation.get("disposition","NEUTRAL")))
	var band:=str(affinity.get("label",_relationship_band(score)))
	var panel:=PanelContainer.new();panel.name="RelationshipCard"
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	DarkSkin.apply_panel(panel,"SECTION")
	add_child(panel)
	var stack:=VBoxContainer.new();stack.add_theme_constant_override("separation",3);panel.add_child(stack)
	var head:=HBoxContainer.new();head.add_theme_constant_override("separation",5);stack.add_child(head)
	var person_name:="나" if is_player else str(relation.get("subject_name",
		relation.get("display_name","상대")))
	var name_label:=_label(person_name,15,DarkSkin.BONE)
	name_label.name="RelationshipSubjectName";name_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_override("font",DarkSkin.PixelFont);head.add_child(name_label)
	var state:=_label("%s · %s %d"%[_disposition(disposition),band,score],12,
		_relationship_tone(score))
	state.name="RelationshipSummary";head.add_child(state)
	var bar:=ProgressBar.new();bar.name="RelationshipGauge";bar.min_value=0;bar.max_value=100
	bar.value=score;bar.show_percentage=false;bar.custom_minimum_size.y=6
	DarkSkin.apply_progress(bar,_relationship_tone(score),score<25);stack.add_child(bar)
	var values:=affinity if not affinity.is_empty() else relation
	var metrics:=_label("신뢰 %d   두려움 %d   적대 %d   감사 %d   원한 %d"%[
		int(values.get("trust",0)),int(values.get("fear",0)),int(values.get("hostility",0)),
		int(values.get("gratitude",0)),int(values.get("grievance",0))],11,DarkSkin.BONE_DIM)
	metrics.name="RelationshipMetrics";metrics.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(metrics)
	var recent:Variant=relation.get("recent_reaction",{})
	if recent is Dictionary and not recent.is_empty():
		var note:=_label("최근 · %s — %s"%[str(recent.get("label","관계 변화")),
			str(recent.get("reason",""))],11,DarkSkin.BRASS)
		note.name="RelationshipRecent";note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		stack.add_child(note)


func _label(value:String,font_size:int,tone:Color)->Label:
	var result:=Label.new();result.text=value;result.mouse_filter=Control.MOUSE_FILTER_IGNORE
	result.add_theme_font_override("font",DarkSkin.PixelFont)
	result.add_theme_font_size_override("font_size",font_size)
	result.add_theme_color_override("font_color",tone);return result


func _relationship_score(row:Dictionary)->int:
	return clampi(50+int(int(row.get("trust",0))/2)-int(int(row.get("fear",0))/3)
		-int(int(row.get("hostility",0))/2)+int(int(row.get("gratitude",0))/2)
		-int(int(row.get("grievance",0))/2),0,100)


func _relationship_band(score:int)->String:
	return "매우 높음" if score>=75 else ("높음" if score>=60 else (
		"보통" if score>=40 else ("낮음" if score>=25 else "경계")))


func _relationship_tone(score:int)->Color:
	return DarkSkin.JADE if score>=60 else (DarkSkin.BLOOD if score<25 else DarkSkin.BONE)


func _same_relation_values(a:Dictionary,b:Dictionary)->bool:
	for key in ["trust","fear","hostility","gratitude","grievance"]:
		if int(a.get(key,0))!=int(b.get(key,0)):return false
	return true


func _disposition(value:String)->String:
	return {"HOSTILE":"적대","WARY":"경계","TRUSTING":"신뢰",
		"FRIENDLY":"우호","NEUTRAL":"중립"}.get(value,value)
