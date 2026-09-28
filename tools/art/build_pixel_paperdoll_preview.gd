extends SceneTree
## Non-destructive style study. Rasterise the existing 64-unit SVGs at a
## deliberately small logical resolution, snap to their authored colours, and
## upscale with nearest-neighbour to the game's unchanged 192x192 canvas.
const SIDE := 192
const SAMPLES := [
	{"name":"human","source":"res://assets/sprites-v1/actors/svg/human.svg","original":"res://assets/sprites-v1/actors/human.png","folder":"actors"},
	{"name":"goblin","source":"res://assets/sprites-v1/monsters/svg/goblin.svg","original":"res://assets/sprites-v1/monsters/goblin.png","folder":"monsters"},
	{"name":"sword","source":"res://assets/items-v1/gear/weapons/svg/sword.svg","original":"res://assets/items-v1/gear/weapons/sword.png","folder":"weapons"},
]
const OUT := "res://docs/art/pixel-paperdoll-v1"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var preview := Image.create(SIDE*3,SIDE*3,false,Image.FORMAT_RGBA8)
	preview.fill(Color("292b33"))
	var poses := Image.create(256*3,256,false,Image.FORMAT_RGBA8)
	poses.fill(Color("292b33"))
	var heroes: Array[Image] = []
	var swords: Array[Image] = []
	for column in range(SAMPLES.size()):
		var job: Dictionary = SAMPLES[column]
		var original := Image.load_from_file(str(job.original))
		if column == 0: heroes.append(original)
		if column == 2: swords.append(original)
		preview.blend_rect(original,Rect2i(Vector2i.ZERO,Vector2i(SIDE,SIDE)),Vector2i(column*SIDE,0))
		for row in range(2):
			var grid: int = 48 if row == 0 else 32
			var image := render(str(job.source),grid)
			var file_name := "%s-%s-%d.png" % [str(job.folder),str(job.name),grid]
			image.save_png(OUT+"/"+file_name)
			if column == 0: heroes.append(image)
			if column == 2: swords.append(image)
			preview.blend_rect(image,Rect2i(Vector2i.ZERO,Vector2i(SIDE,SIDE)),Vector2i(column*SIDE,(row+1)*SIDE))
	for i in range(3):
		var pose := pose_with_weapon(heroes[i],swords[i])
		poses.blit_rect(pose,Rect2i(Vector2i.ZERO,Vector2i(256,256)),Vector2i(i*256,0))
	preview.save_png(OUT+"/comparison.png")
	poses.save_png(OUT+"/weapon-alignment.png")
	print("Pixel paperdoll preview saved: "+OUT+"/comparison.png")
	quit()

func render(path: String, grid: int) -> Image:
	var svg: String = FileAccess.get_file_as_string(path)
	var image := Image.new()
	if image.load_svg_from_string(svg,float(grid)/64.0) != OK:
		push_error("Could not rasterise "+path)
		return Image.create(SIDE,SIDE,false,Image.FORMAT_RGBA8)
	image.convert(Image.FORMAT_RGBA8)
	var palette := authored_colours(svg)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x,y)
			if pixel.a < 0.5:
				image.set_pixel(x,y,Color.TRANSPARENT)
				continue
			var nearest: Color = palette[0]
			var distance := 1.0e10
			for colour in palette:
				var delta := pixel.r-colour.r
				var green := pixel.g-colour.g
				var blue := pixel.b-colour.b
				var score := delta*delta+green*green+blue*blue
				if score < distance:
					nearest = colour; distance = score
			image.set_pixel(x,y,Color(nearest.r,nearest.g,nearest.b,1))
	image.resize(SIDE,SIDE,Image.INTERPOLATE_NEAREST)
	return image

func pose_with_weapon(actor_image: Image, weapon_image: Image) -> Image:
	var result := Image.create(256,256,false,Image.FORMAT_RGBA8)
	result.fill(Color("292b33"))
	result.blend_rect(actor_image,Rect2i(Vector2i.ZERO,Vector2i(SIDE,SIDE)),Vector2i(32,32))
	# Mirror MobileArt.weapon_layer's grip and rotation in sprite-local pixels.
	var hand := Vector2(32,32)+Vector2.ONE*SIDE*Vector2(0.70,0.68)
	var extent := SIDE*0.64
	var grip := Vector2(0.28,0.72)
	for y in range(256):
		for x in range(256):
			var local := (Vector2(x+0.5,y+0.5)-hand).rotated(PI/6.0)
			var uv := local/extent+grip
			if uv.x < 0.0 or uv.x >= 1.0 or uv.y < 0.0 or uv.y >= 1.0: continue
			var source := weapon_image.get_pixel(clampi(int(uv.x*SIDE),0,SIDE-1),clampi(int(uv.y*SIDE),0,SIDE-1))
			if source.a > 0.5: result.set_pixel(x,y,source)
	return result

func authored_colours(svg: String) -> Array[Color]:
	var result: Array[Color] = []
	var pattern := RegEx.new()
	pattern.compile("(?:fill|stroke)=\"(#[0-9a-fA-F]{6})\"")
	for match_result in pattern.search_all(svg):
		var colour := Color(match_result.get_string(1))
		if colour not in result: result.append(colour)
	if result.is_empty(): result.append(Color.BLACK)
	return result
