extends RefCounted
const CANVAS := Color("#15191d")
const VISUAL_FAMILY := "DARK_FANTASY_PIXEL_9SLICE"
static func visibility_state(row: Dictionary) -> String:
	return str(row.get("visibility_state","UNSEEN"))
