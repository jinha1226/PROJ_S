extends RefCounted
## Town-only visual vocabulary, without game rules or mutations.
const Palette=preload("res://playtest/dark_pixel_ui_skin.gd")
const Icon=preload("res://playtest/town_ui_icon.gd")
const Portrait=preload("res://playtest/fixed_front_actor_portrait.gd")
const INK:=Color("#e4decd")
const MUTED:=Color("#a4aba9")
const GOLD:=Color("#d3b57b")
const EDGE:=Color("#3b4849")
static func label(parent:Node,text:String,font_size:int=14,color:Color=INK)->Label:
	var result:=Label.new();result.text=text
	result.add_theme_font_size_override("font_size",font_size)
	result.add_theme_color_override("font_color",color)
	result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	result.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(result);return result
static func surface(parent:Node)->VBoxContainer:
	var panel:=PanelContainer.new();parent.add_child(panel)
	var style:=Palette.panel_surface(Color("#20292b"),EDGE,12,1)
	style.shadow_size=0;style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel",style)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",8)
	panel.add_child(box);return box
static func button(parent:Node,title:String,id:String,primary:bool=false)->Button:
	var b:=Button.new();b.name=id;b.text=title
	b.custom_minimum_size=Vector2(0,48);b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size",15)
	b.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	var tone:=GOLD if primary else EDGE
	for state in ["normal","hover","pressed","focus","disabled"]:
		var fill:=Color("#273335") if not primary else Color("#51442e")
		if state in ["hover","pressed"]:fill=fill.lightened(0.13)
		if state=="disabled":fill=Color("#1c2426")
		var style:=Palette.panel_surface(fill,tone if state!="disabled" else EDGE,8,1)
		style.shadow_size=0;style.set_corner_radius_all(7)
		b.add_theme_stylebox_override(state,style)
	b.add_theme_color_override("font_color",INK)
	b.add_theme_color_override("font_disabled_color",MUTED.darkened(0.25))
	parent.add_child(b);return b
static func portrait(parent:Node,id:int,side:int=48,species_id:String="human")->Control:
	var p:=Portrait.new();p.custom_minimum_size=Vector2(side,side)
	p.set_actor({"entity_id":id,"species_id":species_id});parent.add_child(p);return p
static func shortcut(parent:Node,title:String,id:String,kind:String)->Button:
	var b:=button(parent,"",id);b.custom_minimum_size.y=68;b.tooltip_text=title
	var stack:=VBoxContainer.new();stack.mouse_filter=Control.MOUSE_FILTER_IGNORE
	b.add_child(stack);stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.offset_top=7;stack.offset_bottom=-5;stack.add_theme_constant_override("separation",4)
	var icon:=Icon.new();icon.kind=kind;icon.color=GOLD
	icon.custom_minimum_size=Vector2(26,26);icon.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;stack.add_child(icon)
	var text:=label(stack,title,13);text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	return b
static func heading(parent:Node,title:String,subtitle:String="")->void:
	label(parent,title,21,GOLD)
	if not subtitle.is_empty():label(parent,subtitle,13,MUTED)

static func workplace_residents(parent:Node,residents:Array,facility_id:String,on_inspect:Callable)->void:
	var staff:Array=[]
	for row in residents:
		if not row.adventurer and str(row.get("facility_id",""))==facility_id:staff.append(row)
	if staff.is_empty():return
	var line:=HBoxContainer.new();line.name="TownWorkplaceResidents";line.add_theme_constant_override("separation",6);parent.add_child(line)
	for row in staff:
		var id:=int(row.entity_id)
		var b:=button(line,"%s · %s"%[row.display_name,row.occupation],"TownWorker%d"%id)
		b.tooltip_text="%s · 성격과 관계 보기"%row.display_name
		b.pressed.connect(on_inspect.bind(id))
