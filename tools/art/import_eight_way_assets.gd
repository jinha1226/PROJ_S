extends SceneTree
## Deterministic export of AI-generated direction sheets, not a sprite painter.
## Preserve alpha, sample nearest-neighbor, keep the original south-facing base.
const IDS:=["elf","dwarf","orc","beastkin","goblin","kobold","slime","beetle"]
const NAMES:=["s","sw","w","nw","n","ne","e","se"]
func _init():
	for id in IDS:
		var source_path:="res://assets/pixel24_v4/source/%s.png"%id
		if not FileAccess.file_exists(source_path):continue
		var source=Image.load_from_file(source_path)
		var reference_path:="res://assets/pixel24_v3/runtime/%s/%s.png"%[
			"actors/base" if id in ["elf","dwarf","orc","beastkin"] else "monsters",id]
		var reference=Image.load_from_file(reference_path)
		var reference_bounds:=reference.get_used_rect()
		var frames:Array[Image]=[];var largest:=Vector2i.ZERO
		for index in range(8):
			var frame:=cell(source,index,4,2)
			var bounds:=solid_bounds(frame)
			if bounds.size.x<1 or bounds.size.y<1:push_error("Empty frame "+id);quit(1);return
			frames.append(frame.get_region(bounds))
			largest.x=maxi(largest.x,bounds.size.x);largest.y=maxi(largest.y,bounds.size.y)
		var scale:=minf(float(reference_bounds.size.y)/largest.y,22.0/largest.x)
		var directory:String="res://assets/pixel24_v4/actors/"+id
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		var atlas:=Image.create(192,24,false,Image.FORMAT_RGBA8)
		for index in range(8):
			var output:=Image.create(24,24,false,Image.FORMAT_RGBA8)
			var frame:=frames[index]
			frame.resize(maxi(1,roundi(frame.get_width()*scale)),maxi(1,roundi(frame.get_height()*scale)),Image.INTERPOLATE_NEAREST)
			output.blit_rect(frame,Rect2i(Vector2i.ZERO,frame.get_size()),
				Vector2i((24-frame.get_width())/2,reference_bounds.end.y-frame.get_height()))
			if index==0:output=reference.duplicate()
			if output.save_png(directory+"/"+NAMES[index]+".png")!=OK:quit(1);return
			atlas.blit_rect(output,Rect2i(0,0,24,24),Vector2i(index*24,0))
		atlas.save_png(directory+"/atlas.png")
		print("EXPORTED ",id," 8 x 24x24")
	var features_path:="res://assets/pixel24_v4/source/features.png"
	if FileAccess.file_exists(features_path):
		var sheet:=Image.load_from_file(features_path)
		var atlas:=Image.create(96,96,false,Image.FORMAT_RGBA8)
		for i in range(16):
			var frame:=cell(sheet,i,4,4)
			frame.resize(24,24,Image.INTERPOLATE_NEAREST)
			atlas.blit_rect(frame,Rect2i(0,0,24,24),Vector2i((i%4)*24,(i/4)*24))
		atlas.save_png("res://assets/pixel24_v4/features.png")
	var props_path:="res://assets/pixel24_v4/source/props.png"
	if FileAccess.file_exists(props_path):
		var sheet:=Image.load_from_file(props_path)
		var atlas:=Image.create(96,48,false,Image.FORMAT_RGBA8)
		for i in range(8):
			var frame:=cell(sheet,i,4,2)
			frame.resize(24,24,Image.INTERPOLATE_NEAREST)
			atlas.blit_rect(frame,Rect2i(0,0,24,24),Vector2i((i%4)*24,(i/4)*24))
		atlas.save_png("res://assets/pixel24_v4/props.png")
	quit()
func cell(source:Image,index:int,columns:int,rows:int)->Image:
	var x0:=roundi(float(index%columns)*source.get_width()/columns)
	var x1:=roundi(float(index%columns+1)*source.get_width()/columns)
	var y0:=roundi(float(index/columns)*source.get_height()/rows)
	var y1:=roundi(float(index/columns+1)*source.get_height()/rows)
	return source.get_region(Rect2i(x0,y0,x1-x0,y1-y0))

func solid_bounds(frame:Image)->Rect2i:
	# Generated alpha can contain almost invisible dust far outside a sprite.
	# Ignore that when measuring its silhouette; retain alpha inside the crop.
	var low:=frame.get_size();var high:=Vector2i(-1,-1)
	for y in range(frame.get_height()):
		for x in range(frame.get_width()):
			if frame.get_pixel(x,y).a<0.5:continue
			low.x=mini(low.x,x);low.y=mini(low.y,y)
			high.x=maxi(high.x,x);high.y=maxi(high.y,y)
	return Rect2i(low,high-low+Vector2i.ONE) if high.x>=0 else Rect2i()
