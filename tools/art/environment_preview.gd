extends Control
const Art = preload("res://expedition/art/environment_art.gd")
const Walls = preload("res://expedition/art/masonry_tiles.gd")
const FONT = preload("res://assets/fonts/NanumSquareR.ttf")
const MAP = ["##########","#........#","#..##....#","#..##....#","#........#","#.....#..#","#........#","####..####"]
const TITLES = ["침수 지하묘지","폐광","불탄 성채","얼어붙은 유적"]

func _ready() -> void:
	get_window().content_scale_size = Vector2i(1280,920)
	get_window().size = Vector2i(1280,920)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()

func label_at(text: String, point: Vector2, font_size: int = 18) -> void:
	draw_string(FONT,point,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color("d5cbb8"))

func draw_room(theme: String, start: Vector2, index: int) -> void:
	var material := Art.material(theme)
	var solid := func(p): return p.x < 0 or p.y < 0 or p.x >= 10 or p.y >= 8 or MAP[p.y][p.x] == "#"
	var cells: Array = []
	var water: String = ["water_shallow","mud","burning_cracks","ice"][index]
	for y in range(8):
		for x in range(10):
			var p := Vector2i(x,y); var rect := Rect2(start+Vector2(p)*28,Vector2.ONE*28)
			if solid.call(p):
				draw_rect(rect,Color("090c10")); cells.append({"point":p,"rect":rect,"tint":Color.WHITE})
			else:
				draw_texture_rect(material.floor_a if (x+y)%5 else material.floor_b,rect,false)
				if x in [6,7,8] and y in [2,3]: draw_texture_rect(Art.terrain_texture(water),rect,false)
				Walls.paint_floor_shadow(self,rect,p,solid)
	Walls.paint_walls(self,cells,solid,material)
	for placement in [["torch_lit",Vector2(1,0)],["torch_lit",Vector2(8,0)],["crates",Vector2(1,3)],["rubble",Vector2(4,5)],["brazier_lit",Vector2(7,5)]]:
		Art.paint_object(self,placement[0],Rect2(start+placement[1]*28,Vector2.ONE*28))

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("121519"))
	label_at("환경 에셋 v1 · 동일 벽 구조 / 네 가지 재질",Vector2(24,34),24)
	var themes: Array = Art.catalog.themes.keys()
	for i in range(themes.size()):
		label_at(TITLES[i],Vector2(24+i*312,74))
		draw_room(themes[i],Vector2(24+i*312,114),i)
	label_at("오브젝트 16종 · 투명 배경",Vector2(24,380),22)
	var objects: Array = Art.catalog.objects.keys()
	for i in range(objects.size()):
		var position := Vector2(24+(i%8)*156,402+(i/8)*112)
		Art.paint_object(self,objects[i],Rect2(position,Vector2.ONE*80))
		label_at(objects[i],position+Vector2(0,99),13)
	label_at("특수지형 16종 · 정적 텍스처",Vector2(24,668),22)
	var terrain: Array = Art.catalog.terrain.keys()
	for i in range(terrain.size()):
		var position := Vector2(24+(i%8)*156,686+(i/8)*110)
		draw_texture_rect(Art.terrain_texture(terrain[i]),Rect2(position,Vector2.ONE*72),false)
		label_at(terrain[i],position+Vector2(0,92),13)
