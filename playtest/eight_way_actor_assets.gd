extends RefCounted
const Human=preload("res://playtest/human_directional_assets.gd")
const ATLASES:={
	"elf":preload("res://assets/pixel24_v4/actors/elf/atlas.png"),
	"dwarf":preload("res://assets/pixel24_v4/actors/dwarf/atlas.png"),
	"orc":preload("res://assets/pixel24_v4/actors/orc/atlas.png"),
	"beastkin":preload("res://assets/pixel24_v4/actors/beastkin/atlas.png"),
	"kobold":preload("res://assets/pixel24_v4/actors/kobold/atlas.png"),
	"slime":preload("res://assets/pixel24_v4/actors/slime/atlas.png"),
	"beetle":preload("res://assets/pixel24_v4/actors/beetle/atlas.png"),
}
static var _frames:Dictionary={}
static func supports(species:String)->bool:
	return species=="human" or ATLASES.has(species)
static func texture(species:String,facing:Variant)->Texture2D:
	var index:=Human.index(facing)
	if species=="human":return Human.FRAMES[index]
	if not ATLASES.has(species):return null
	var key:="%s/%d"%[species,index]
	if not _frames.has(key):
		var frame:=AtlasTexture.new();frame.atlas=ATLASES[species]
		frame.region=Rect2(index*24,0,24,24);frame.filter_clip=true
		_frames[key]=frame
	return _frames[key]
