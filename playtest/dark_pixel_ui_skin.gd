class_name DarkPixelUISkin
extends RefCounted

## Image-backed nine-slice ironwork. Layout, text and input remain native controls.
const FrameTexture=preload("res://assets/ui/dark_fantasy_v1/iron_frame.png")
static var _runtime_frame:Texture2D

static func frame_texture()->Texture2D:
	if _runtime_frame==null:
		var pixels:Image=FrameTexture.get_image()
		pixels.resize(48,48,Image.INTERPOLATE_NEAREST)
		_runtime_frame=ImageTexture.create_from_image(pixels)
	return _runtime_frame

const CANVAS:=Color("#15191d")
const FOLIO:=Color("#20252a")
const SECTION:=Color("#292f34")
const SLOT_EMPTY:=Color("#070b0c")
const SLOT_FILLED:=Color("#11191b")
const SLOT_EQUIPPED:=Color("#1a1912")
const IRON_EDGE:=Color("#424b4c")
const IRON_LIGHT:=Color("#697071")
const IRON_SHADOW:=Color("#161b1c")
const BONE:=Color("#d0c8b4")
const BONE_DIM:=Color("#817d72")
const BRASS:=Color("#c6a34c")
const BRASS_DARK:=Color("#65522a")
const CYAN:=Color("#4d8f98")
const BLOOD:=Color("#9f4544")
const JADE:=Color("#5f8a66")

const VISUAL_FAMILY:="DARK_FANTASY_PIXEL_9SLICE"
# Shared Korean/Latin pixel face, imported without antialiasing or subpixels.
const PixelFont:FontFile=preload("res://assets/fonts/Galmuri14.ttf")


static func configure_theme(theme:Theme)->void:
	theme.default_font=PixelFont
	theme.set_color("font_color","Label",BONE)
	theme.set_color("font_shadow_color","Label",Color("#000000a0"))
	theme.set_constant("shadow_offset_x","Label",1)
	theme.set_constant("shadow_offset_y","Label",1)
	for type_name in ["Button","MenuButton"]:
		theme.set_color("font_color",type_name,BONE)
		theme.set_color("font_hover_color",type_name,Color("#eee4cb"))
		theme.set_color("font_pressed_color",type_name,Color.WHITE)
		theme.set_color("font_disabled_color",type_name,BONE_DIM.darkened(0.35))
		theme.set_stylebox("normal",type_name,
			panel_surface(Color("#0e1416"),IRON_EDGE,4,1))
		theme.set_stylebox("hover",type_name,
			panel_surface(Color("#182023"),CYAN.darkened(0.15),4,2))
		theme.set_stylebox("pressed",type_name,
			panel_surface(BRASS_DARK.darkened(0.22),BRASS,4,2))
		theme.set_stylebox("focus",type_name,
			panel_surface(Color("#182023"),BRASS_DARK,4,1))
		theme.set_stylebox("disabled",type_name,
			panel_surface(Color("#080b0c"),IRON_SHADOW,4,1))
	theme.set_stylebox("panel","PanelContainer",section_surface(4))
	theme.set_stylebox("panel","PopupMenu",panel_surface(FOLIO,IRON_EDGE,8,2))
	theme.set_stylebox("hover","PopupMenu",panel_surface(SECTION,BRASS,4,2))
	theme.set_color("font_color","PopupMenu",BONE)
	theme.set_color("font_hover_color","PopupMenu",Color("#fff0c9"))
	theme.set_color("font_disabled_color","PopupMenu",BONE_DIM)
	theme.set_constant("v_separation","PopupMenu",10)
	theme.set_stylebox("panel","TooltipPanel",panel_surface(FOLIO,BRASS_DARK,8,1))
	theme.set_color("font_color","TooltipLabel",BONE)
	theme.set_stylebox("background","ProgressBar",
		panel_surface(SLOT_EMPTY,IRON_SHADOW,0,1))
	theme.set_stylebox("fill","ProgressBar",
		panel_surface(CYAN,IRON_EDGE,0,0))


static func panel_surface(fill:Color=FOLIO,border:Color=IRON_EDGE,
		margin:int=8,border_width:int=2)->StyleBox:
	# Gauges and explicit unframed fills stay solid for accurate proportional fill.
	if border_width==0:
		var flat:=StyleBoxFlat.new();flat.bg_color=fill;flat.anti_aliasing=false
		flat.set_content_margin_all(float(margin));return flat
	var style:=StyleBoxTexture.new()
	style.texture=frame_texture()
	var cut:=8.0
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		style.set_texture_margin(side,cut)
		style.set_expand_margin(side,0)
	style.axis_stretch_horizontal=StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical=StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.modulate_color=Color(border.r*1.3+0.28,border.g*1.3+0.28,border.b*1.3+0.28,1)
	style.draw_center=fill.a>0
	style.set_content_margin_all(float(margin))
	return style


static func section_surface(margin:int=7)->StyleBox:
	return panel_surface(SECTION,IRON_SHADOW,margin,1)


static func apply_panel(panel:PanelContainer,kind:String="FOLIO")->void:
	var style:=panel_surface()
	if kind=="SECTION":style=section_surface()
	elif kind=="COMPACT":style=panel_surface(SECTION,IRON_SHADOW,2,1)
	panel.add_theme_stylebox_override("panel",style)
	panel.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	panel.set_meta("visual_family",VISUAL_FAMILY)
	panel.set_meta("pixel_material","BLACK_IRON")
	panel.set_meta("skin_kind",kind)


static func apply_heading(label:Label,accent:Color=BRASS)->void:
	label.add_theme_font_override("font",PixelFont)
	label.add_theme_color_override("font_color",accent)
	label.add_theme_constant_override("outline_size",1)
	label.add_theme_color_override("font_outline_color",CANVAS)
	label.set_meta("visual_family",VISUAL_FAMILY)


static func apply_action_button(button:Button,accent:Color=BRASS,
		danger:bool=false)->void:
	button.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var tone:=BLOOD if danger else accent
	var normal:=panel_surface(tone.darkened(0.67),tone.darkened(0.15),4,2)
	var hover:=panel_surface(Color("#1a2224"),tone.darkened(0.18),4,2)
	var pressed:=panel_surface(tone.darkened(0.55),tone,4,2)
	var disabled:=panel_surface(Color("#090c0d"),IRON_SHADOW,4,1)
	button.add_theme_stylebox_override("normal",normal)
	button.add_theme_stylebox_override("hover",hover)
	button.add_theme_stylebox_override("pressed",pressed)
	button.add_theme_stylebox_override("focus",hover)
	button.add_theme_stylebox_override("disabled",disabled)
	button.add_theme_color_override("font_color",BONE)
	button.add_theme_color_override("font_hover_color",Color("#eee4cb"))
	button.add_theme_color_override("font_pressed_color",Color.WHITE)
	button.add_theme_color_override("font_disabled_color",BONE_DIM.darkened(0.35))
	button.add_theme_constant_override("outline_size",0)
	button.set_meta("visual_family",VISUAL_FAMILY)
	button.set_meta("pixel_material","BLACK_IRON_BUTTON")
	button.set_meta("danger_action",danger)


static func apply_tab_button(button:Button,selected:bool=false)->void:
	var normal_fill:=BRASS_DARK.darkened(0.38) if selected else SLOT_EMPTY
	var normal_edge:=BRASS if selected else IRON_EDGE
	var normal:=panel_surface(normal_fill,normal_edge,4,2 if selected else 1)
	var hover:=panel_surface(Color("#1a2224"),BRASS_DARK,4,2)
	var pressed:=panel_surface(BRASS_DARK.darkened(0.20),BRASS,4,2)
	button.add_theme_stylebox_override("normal",normal)
	button.add_theme_stylebox_override("hover",hover)
	button.add_theme_stylebox_override("pressed",pressed)
	button.add_theme_stylebox_override("focus",normal)
	button.add_theme_stylebox_override("disabled",panel_surface(
		Color("#080b0c"),IRON_SHADOW,4,1))
	button.add_theme_color_override("font_color",BRASS if selected else BONE_DIM)
	button.add_theme_color_override("font_hover_color",BONE)
	button.add_theme_color_override("font_pressed_color",Color.WHITE)
	button.set_meta("visual_family",VISUAL_FAMILY)
	button.set_meta("pixel_material","IRON_TAB")
	button.set_meta("selected_tab",selected)


static func apply_progress(bar:ProgressBar,accent:Color=CYAN,low:bool=false)->void:
	bar.add_theme_stylebox_override("background",
		panel_surface(SLOT_EMPTY,IRON_SHADOW,0,1))
	bar.add_theme_stylebox_override("fill",
		panel_surface(BLOOD if low else accent,IRON_EDGE,0,0))
	bar.set_meta("visual_family",VISUAL_FAMILY)
	bar.set_meta("pixel_material","RECESSED_GAUGE")
