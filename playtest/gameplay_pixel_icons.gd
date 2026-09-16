extends RefCounted
const SHEET=preload("res://assets/ui/fantasy_pawns_v1/icons.png")
const INDEX:={"attack":0,"wait":1,"explore":2,"tactics":3,"bag":4,"food":5,"noise":6,"menu":7,
	"stealth":8,"suspicious":9,"detected":10,"strike":11,"shield":12,"heal":13,"fire":14,"ability":15}
static var cache:Dictionary={}
static func texture(key:String)->Texture2D:
	if cache.has(key):return cache[key]
	var index:int=INDEX.get(key,15)
	var cell:Vector2=SHEET.get_size()/4.0
	var atlas:=AtlasTexture.new();atlas.atlas=SHEET
	atlas.region=Rect2(Vector2(index%4,index/4)*cell,cell)
	atlas.filter_clip=true;cache[key]=atlas;return atlas
static func skill_key(id:String)->String:
	if "FIRE" in id:return "fire"
	if id in ["MEND","HEAL"]:return "heal"
	if "SHIELD" in id or "GUARD" in id:return "shield"
	if "STRIKE" in id or "BASH" in id:return "strike"
	return "ability"
