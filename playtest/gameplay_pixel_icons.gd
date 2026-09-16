extends RefCounted
const SHEET=preload("res://assets/ui/fantasy_pawns_v1/icons.png")
const INDEX:={"attack":0,"wait":1,"explore":2,"tactics":3,"bag":4,"food":5,"noise":6,"menu":7,
	"stealth":8,"suspicious":9,"detected":10,"strike":11,"shield":12,"heal":13,"fire":14,"ability":15}
static var cache:Dictionary={}
static func monochrome_texture(key:String)->Texture2D:
	var cache_key:="monochrome_"+key
	if cache.has(cache_key):return cache[cache_key]
	var image:=texture(key).get_image()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var source:=image.get_pixel(x,y)
			var brightness:=source.r*0.299+source.g*0.587+source.b*0.114
			# Dark contour/details become cutouts, keeping clock hands and compass needles legible.
			var alpha:=source.a*clampf((brightness-0.07)/0.08,0.0,1.0)
			image.set_pixel(x,y,Color(0.82,0.84,0.86,alpha))
	var result:=ImageTexture.create_from_image(image)
	cache[cache_key]=result
	return result
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
