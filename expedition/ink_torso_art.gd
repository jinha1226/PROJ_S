extends RefCounted
## Human prototype: body replacement, then shared head, sword and shield overlays.
## This is a visual loadout only; it does not grant equipment stats.
const PARTS = preload("res://assets/characters/ink-torso-v1/parts.png")
const Regions = preload("res://expedition/environment_art.gd")
static var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/ink-torso-v1/catalog.json"))

static func paint(canvas: CanvasItem, rect: Rect2, tint: Color = Color.WHITE, armored: bool = true, sword: bool = true, shield: bool = true) -> void:
	var scale := rect.size/Vector2(catalog.canvas[0],catalog.canvas[1])
	for layer in catalog.order:
		if layer == "sword" and not sword: continue
		if layer == "shield" and not shield: continue
		var id: String = ("armor" if armored else "cloth") if layer == "body" else str(layer)
		var part: Dictionary = catalog.parts[id]
		var target: Array = part.destination
		var destination := Rect2(rect.position+Vector2(target[0],target[1])*scale,Vector2(target[2],target[3])*scale)
		canvas.draw_texture_rect(Regions.region(PARTS,part.source,"ink-torso-v1/"+id),destination,false,tint)
