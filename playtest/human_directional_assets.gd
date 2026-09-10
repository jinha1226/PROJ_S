extends RefCounted
const NAMES:=["s","sw","w","nw","n","ne","e","se"]
const DIRECTIONS:=[Vector2i(0,1),Vector2i(-1,1),Vector2i(-1,0),Vector2i(-1,-1),Vector2i(0,-1),Vector2i(1,-1),Vector2i(1,0),Vector2i(1,1)]
const FRAMES:=[preload("res://assets/pixel24_v3/human_8way/s.png"),preload("res://assets/pixel24_v3/human_8way/sw.png"),preload("res://assets/pixel24_v3/human_8way/w.png"),preload("res://assets/pixel24_v3/human_8way/nw.png"),preload("res://assets/pixel24_v3/human_8way/n.png"),preload("res://assets/pixel24_v3/human_8way/ne.png"),preload("res://assets/pixel24_v3/human_8way/e.png"),preload("res://assets/pixel24_v3/human_8way/se.png")]
static var _equipment_cache:Dictionary={}
static func index(facing:Variant)->int:
	var direction:=Vector2i(0,1)
	if facing is Array and facing.size()==2:direction=Vector2i(signi(int(facing[0])),signi(int(facing[1])))
	elif facing is Vector2i or facing is Vector2:direction=Vector2i(signi(int(facing.x)),signi(int(facing.y)))
	return maxi(0,DIRECTIONS.find(direction))

static func equipment(texture:Texture2D,direction_index:int,armor:bool=false)->Texture2D:
	if texture==null or direction_index==0:return texture
	var key:="%s/%d/%s"%[texture.resource_path,direction_index,armor]
	if _equipment_cache.has(key):return _equipment_cache[key]
	var source:=texture.get_image()
	var result:=Image.create(24,24,false,Image.FORMAT_RGBA8)
	var direction:Vector2i=DIRECTIONS[direction_index]
	# Discrete paper-doll projection: keep native pixels and canonical handedness.
	var squeeze:=0.65 if direction.y==0 else 0.85 if direction.x!=0 else 1.0
	for y in range(24):
		for x in range(24):
			var color:=source.get_pixel(x,y)
			if color.a<0.5:continue
			var px:=int(round((x-11.5)*squeeze+11.5))
			if direction.y<0:px=23-px
			var py:=y-1 if direction.y<0 and not armor else y
			if py>=0 and py<24:result.set_pixel(px,py,color)
	var rendered:=ImageTexture.create_from_image(result)
	_equipment_cache[key]=rendered
	return rendered
