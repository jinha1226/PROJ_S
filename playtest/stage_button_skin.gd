extends RefCounted
## Shared 64px, nearest-filtered 9-slice skin. Resources are built once, not per turn.
const SOURCE = preload("res://assets/ui/stage_metal_v1/frame.png")
static var _texture: ImageTexture
static var _boxes: Dictionary = {}

static func box(state: String) -> StyleBoxTexture:
	if _boxes.has(state):
		return _boxes[state]
	if _texture == null:
		var pixels := SOURCE.get_image()
		pixels.resize(64, 64, Image.INTERPOLATE_NEAREST)
		_texture = ImageTexture.create_from_image(pixels)
	var result := StyleBoxTexture.new()
	result.texture = _texture
	for edge in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		result.set_texture_margin(edge, 8)
		result.set_content_margin(edge, 8)
	result.modulate_color = {
		"normal": Color("#a3b6c7"),
		"selected": Color("#72edff"),
		"pressed": Color("#4995ae"),
		"disabled": Color("#59636f"),
	}.get(state, Color.WHITE)
	_boxes[state] = result
	return result

static func apply(button: Button, accent: bool = false, touch_down: bool = false) -> void:
	var key := Vector2i(int(accent), int(touch_down))
	if button.get_meta("stage_skin_state", Vector2i(-1, -1)) == key:
		return
	button.set_meta("stage_skin_state", key)
	button.flat = false
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.add_theme_stylebox_override("normal", box("pressed" if touch_down else ("selected" if accent else "normal")))
	button.add_theme_stylebox_override("hover", box("pressed" if touch_down else "selected"))
	button.add_theme_stylebox_override("pressed", box("pressed"))
	button.add_theme_stylebox_override("hover_pressed", box("pressed"))
	button.add_theme_stylebox_override("disabled", box("disabled"))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color("#e3f3f7") if accent else Color("#c6d5df"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color("#a8e5ef"))
	button.add_theme_color_override("font_disabled_color", Color("#77848f"))
