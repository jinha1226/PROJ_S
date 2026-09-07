class_name DarkPixelUISkin
extends RefCounted

## Shared code-native skin for the product UI. Raster art supplies icons and
## atmosphere; layout and interaction states stay responsive Godot controls.

const CANVAS:=Color("#030607")
const FOLIO:=Color("#080d0f")
const SECTION:=Color("#0d1416")
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

const VISUAL_FAMILY:="DARK_PIXEL_DUNGEON_UI"
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
	theme.set_stylebox("background","ProgressBar",
		panel_surface(SLOT_EMPTY,IRON_SHADOW,0,1))
	theme.set_stylebox("fill","ProgressBar",
		panel_surface(CYAN,IRON_EDGE,0,0))


static func panel_surface(fill:Color=FOLIO,border:Color=IRON_EDGE,
		margin:int=8,border_width:int=2)->StyleBoxFlat:
	var style:=StyleBoxFlat.new()
	style.bg_color=fill
	style.border_color=border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(0)
	style.set_content_margin_all(float(margin))
	style.shadow_color=Color("#000000a8")
	style.shadow_size=2
	style.shadow_offset=Vector2(2,2)
	return style


static func section_surface(margin:int=7)->StyleBoxFlat:
	return panel_surface(SECTION,IRON_SHADOW,margin,1)


static func apply_panel(panel:PanelContainer,kind:String="FOLIO")->void:
	var style:=panel_surface()
	if kind=="SECTION":style=section_surface()
	elif kind=="COMPACT":style=panel_surface(SECTION,IRON_SHADOW,2,1)
	panel.add_theme_stylebox_override("panel",style)
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
	var tone:=BLOOD if danger else accent
	var normal:=panel_surface(Color("#111719"),IRON_EDGE,4,1)
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
