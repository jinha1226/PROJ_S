extends SceneTree
## Deterministic production conversion of the imagegen sheet, not a runtime resize.
const DIR:="res://assets/pixel24_v3/human_8way/"
func _init()->void:
	var source:=Image.load_from_file(DIR+"source/generated.png")
	var original:=Image.load_from_file("res://assets/pixel24_v3/runtime/actors/base/human.png")
	var palette:Array[Color]=[]
	for y in range(24):
		for x in range(24):
			var color:=original.get_pixel(x,y)
			if color.a>0.5 and color not in palette:palette.append(color)
	var names:=["s","sw","w","nw","n","ne","e","se"]
	var sheet:=Image.create(192,24,false,Image.FORMAT_RGBA8)
	for index in range(8):
		var tile:=Image.create(24,24,false,Image.FORMAT_RGBA8)
		if index==0:tile=original.duplicate()
		else:
			# Isolate the intentional sprite row, excluding peripheral alpha specks.
			var crop:=source.get_region(Rect2i(index*source.get_width()/8,190,source.get_width()/8,310))
			for y in range(crop.get_height()):
				for x in range(crop.get_width()):
					if crop.get_pixel(x,y).a<0.8:crop.set_pixel(x,y,Color.TRANSPARENT)
			crop=crop.get_region(crop.get_used_rect())
			var width:=12 if index in [2,6] else 14
			crop.resize(width,20,Image.INTERPOLATE_NEAREST)
			for y in range(20):
				for x in range(width):
					var color:=crop.get_pixel(x,y)
					if color.a<0.8:continue
					var closest:=palette[0];var distance:=INF
					for candidate in palette:
						var delta:=Vector3(color.r-candidate.r,color.g-candidate.g,color.b-candidate.b).length_squared()
						if delta<distance:distance=delta;closest=candidate
					tile.set_pixel((24-width)/2+x,3+y,closest)
		assert(tile.save_png(DIR+names[index]+".png")==OK)
		sheet.blit_rect(tile,Rect2i(0,0,24,24),Vector2i(index*24,0))
	assert(sheet.save_png(DIR+"sheet.png")==OK)
	sheet.resize(1152,144,Image.INTERPOLATE_NEAREST)
	sheet.save_png("/tmp/human-8way-native-review.png")
	print("HUMAN 8WAY IMPORT: eight native 24x24 frames; south identical to original")
	quit()
