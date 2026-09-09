extends SceneTree

## Read-only diagnostic for recording explicit source-cell and keyed subject
## bounds in pixel24_manifest.json. Usage:
## godot --headless --path . --script tools/art/measure_keyed_grid.gd -- <png> 4 4


func _init()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3:
		printerr("usage: <png> <columns> <rows>");quit(2);return
	var image:=Image.load_from_file(str(args[0]))
	var columns:=int(args[1]);var rows:=int(args[2])
	if image==null or image.is_empty() or columns<=0 or rows<=0:
		printerr("invalid image or grid");quit(2);return
	image.convert(Image.FORMAT_RGBA8)
	for row in range(rows):
		for column in range(columns):
			var left:=int(floor(float(column*image.get_width())/float(columns)))
			var right:=int(floor(float((column+1)*image.get_width())/float(columns)))
			var top:=int(floor(float(row*image.get_height())/float(rows)))
			var bottom:=int(floor(float((row+1)*image.get_height())/float(rows)))
			var cell:=Rect2i(left,top,right-left,bottom-top)
			var min_x:=right;var min_y:=bottom;var max_x:=left-1;var max_y:=top-1
			for y in range(top,bottom):
				for x in range(left,right):
					var color:=image.get_pixel(x,y)
					var hue_distance:=minf(absf(color.h-5.0/6.0),
						1.0-absf(color.h-5.0/6.0))
					var keyed:=hue_distance<=0.12 and color.s>=0.72
					if not keyed:
						min_x=mini(min_x,x);min_y=mini(min_y,y)
						max_x=maxi(max_x,x);max_y=maxi(max_y,y)
			var subject:=Rect2i()
			if max_x>=min_x:subject=Rect2i(min_x,min_y,max_x-min_x+1,max_y-min_y+1)
			print("r%d c%d cell=%s subject=%s"%[row,column,cell,subject])
	quit(0)
