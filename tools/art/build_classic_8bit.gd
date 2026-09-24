extends SceneTree
## Convert the painted source sheets into a fixed-resolution, shared-palette
## sprite set. This deliberately produces real low-resolution PNGs; display
## controls scale them with nearest-neighbour filtering.
const SOURCE := "res://assets/8bit/"
const OUTPUT := "res://assets/8bit/classic/"
const PALETTE := [
	Color("10151d"), Color("252c37"), Color("3d4652"), Color("5d6975"),
	Color("89929a"), Color("c3c3b7"), Color("eee4cc"),
	Color("302420"), Color("543a2d"), Color("80553b"), Color("ad764d"),
	Color("dda477"), Color("f1c698"),
	Color("783037"), Color("b7413a"), Color("ed6045"),
	Color("705325"), Color("ad8435"), Color("e8bf5b"),
	Color("30472e"), Color("577345"), Color("8ca66a"),
	Color("233a59"), Color("40658c"), Color("6e9eb9"), Color("a1d4d5"),
	Color("4c355b"), Color("775889"), Color("ae81ac")
]

func _initialize() -> void:
	call_deferred("build")

func build() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var sheets := [
		["source/actors.png","actors.png",4,2,24,24,true],
		["monsters.png","monsters.png",4,2,24,24,true],
		["fire-lizard-boss.png","fire-lizard-boss.png",1,1,32,32,true],
		["mastery-icons.png","mastery-icons.png",5,2,16,16,true],
		["spell-icons.png","spell-icons.png",4,3,16,16,true],
		["equipment-icons.png","equipment-icons.png",4,3,16,16,true],
		["ruins-tiles.png","ruins-tiles.png",4,4,16,16,false],
		["mines-tiles.png","mines-tiles.png",4,4,16,16,false],
		["props.png","props.png",4,4,24,24,true],
		["start-background.png","start-background.png",1,1,160,90,false],
		["camp-background.png","camp-background.png",1,1,160,90,false]
	]
	for school in ["fire","ice","air","hex","summon"]:
		sheets.append(["spells-%s.png" % school,"spells-%s.png" % school,5,2,16,16,true])
	for entry in sheets:
		var source: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE+entry[0]))
		if source == null:
			push_error("Missing 8-bit source: "+str(entry[0])); quit(1); return
		var columns: int = entry[2]
		var rows: int = entry[3]
		var cell_w: int = entry[4]
		var cell_h: int = entry[5]
		var transparent: bool = entry[6]
		var output := Image.create_empty(columns*cell_w,rows*cell_h,false,Image.FORMAT_RGBA8)
		for index in range(columns*rows):
			var col: int = index % columns
			var row: int = index / columns
			var x0 := floori(float(col*source.get_width())/columns)
			var x1 := floori(float((col+1)*source.get_width())/columns)
			var y0 := floori(float(row*source.get_height())/rows)
			var y1 := floori(float((row+1)*source.get_height())/rows)
			var cell := source.get_region(Rect2i(x0,y0,x1-x0,y1-y0))
			cell.resize(cell_w,cell_h,Image.INTERPOLATE_LANCZOS)
			for y in range(cell_h):
				for x in range(cell_w):
					var color := cell.get_pixel(x,y)
					if transparent and color.a < 0.55:
						output.set_pixel(col*cell_w+x,row*cell_h+y,Color.TRANSPARENT)
						continue
					output.set_pixel(col*cell_w+x,row*cell_h+y,nearest_color(color))
		var path: String = OUTPUT+entry[1]
		var error := output.save_png(path)
		if error != OK:
			push_error("Cannot save "+path+": "+str(error)); quit(1); return
		print(path," ",output.get_width(),"x",output.get_height())
	quit()

func nearest_color(color: Color) -> Color:
	var best: Color = PALETTE[0]
	var best_distance := INF
	for choice in PALETTE:
		var d: float = pow(color.r-choice.r,2)+pow(color.g-choice.g,2)+pow(color.b-choice.b,2)
		if d < best_distance:
			best = choice
			best_distance = d
	return best
