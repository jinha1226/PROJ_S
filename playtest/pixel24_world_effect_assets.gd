extends RefCounted
const FEATURES=preload("res://assets/pixel24_v4/features.png")
const PROPS=preload("res://assets/pixel24_v4/props.png")
const CELLS:={"STAIRS_DOWN":0,"STAIRS_UP":1,"PORTAL_DORMANT":2,"PORTAL":3,
	"CAMP":4,"TORCH":5,"BLOOD":6,"BONES":7,"OIL":8,"ICE":9,
	"STEAM":10,"SMOKE":11,"GAS":12,"ELECTRIC":13,"LOOT":14,"CHEST":15,
	"DOOR":16,"WELL":17,"RELIC":18,"WET":19,"FIRE":20,"ASH":21,"WIND":22,"IMPACT":23}
const FEATURE_IDS:={"run_entry":"STAIRS_UP","run_exit_locked":"PORTAL_DORMANT",
	"run_exit_open":"STAIRS_DOWN","anchor_portal_inactive":"PORTAL_DORMANT",
	"anchor_portal_active":"PORTAL","floor_transition_portal_locked":"PORTAL_DORMANT",
	"floor_transition_portal":"STAIRS_DOWN","open_door":"DOOR","landmark_camp":"CAMP",
	"landmark_relic":"RELIC","landmark_well":"WELL"}
static func draw_icon(canvas:CanvasItem,kind:String,rect:Rect2,modulate:Color=Color.WHITE)->void:
	if not CELLS.has(kind):return
	var index:int=CELLS[kind]
	var texture:Texture2D=FEATURES if index<16 else PROPS
	index%=16
	canvas.draw_texture_rect_region(texture,rect,Rect2((index%4)*24,(index/4)*24,24,24),modulate)
