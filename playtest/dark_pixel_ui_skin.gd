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

const VISUAL_FAMILY:="DARK_PIXEL_DUNGEON_UI"


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
	var style:=section_surface() if kind=="SECTION" else panel_surface()
	panel.add_theme_stylebox_override("panel",style)
	panel.set_meta("visual_family",VISUAL_FAMILY)
	panel.set_meta("pixel_material","BLACK_IRON")
	panel.set_meta("skin_kind",kind)


static func apply_heading(label:Label,accent:Color=BRASS)->void:
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

