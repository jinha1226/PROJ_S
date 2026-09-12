extends RefCounted
const Kenney=preload("res://playtest/kenney_dungeon_assets.gd")
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
	var icons:={"STAIRS_DOWN":36,"STAIRS_UP":38,"PORTAL_DORMANT":45,"PORTAL":21,
		"CAMP":29,"TORCH":29,"BONES":121,"LOOT":90,"CHEST":89,"DOOR":45,"WELL":55,"RELIC":59,"FIRE":29}
	if icons.has(kind):
		canvas.draw_texture_rect(Kenney.texture(int(icons[kind])),rect,false,modulate)
	else:
		# Gameplay overlays stay procedural; no old generated sprite is mixed in.
		var tones:={"BLOOD":Color("#a53030"),"OIL":Color("#352b42"),"ICE":Color("#a3d5e8"),
			"WET":Color("#4f8fba"),"GAS":Color("#75a743"),"ELECTRIC":Color("#fee761"),
			"SMOKE":Color("#647d8e"),"STEAM":Color("#c0cbdc"),"ASH":Color("#394a50"),"IMPACT":Color("#fee761"),"WIND":Color("#c0cbdc")}
		var color:Color=tones.get(kind,Color.WHITE)*modulate
		for part in [Rect2(0.25,0.61,0.20,0.12),Rect2(0.46,0.54,0.27,0.16),Rect2(0.36,0.77,0.15,0.08)]:
			canvas.draw_rect(Rect2(rect.position+part.position*rect.size,part.size*rect.size),color)
