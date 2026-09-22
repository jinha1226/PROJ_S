extends Control
const Tiles = preload("res://expedition/masonry_tiles.gd")
const FONT = preload("res://assets/fonts/NanumSquareR.ttf")
const MAPS = [
	["##########","#........#","#........#","#........#","#........#","#........#","####..####","####..####"],
	["##########","#..#######","#..#######","#..#######","#.......##","#.......##","######..##","######..##"],
	["##########","#........#","#..##....#","#..##....#","#........#","#....#...#","#........#","##########"]
]
func _ready() -> void:
	get_window().content_scale_size = Vector2i(1024,760)
	get_window().size = Vector2i(1024,760)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("101215"))
	draw_string(FONT,Vector2(24,34),"벽·바닥 타일 v2",HORIZONTAL_ALIGNMENT_LEFT,-1,24,Color("d4c5a8"))
	for i in range(4): draw_texture_rect(Tiles.tile(i),Rect2(24+i*60,54,56,56),false)
	for i in range(4): draw_texture_rect(Tiles.wall_tile(i),Rect2(294+i*90,54,80,80),false)
	var titles := ["방 / 출입구","꺾인 복도","기둥 / 안쪽 모서리"]
	for example in range(3):
		var start := Vector2(24+example*330,170)
		draw_string(FONT,start-Vector2(0,16),titles[example],HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("c5beb0"))
		var layout: Array = MAPS[example]
		var wall := func(p: Vector2i): return p.x < 0 or p.y < 0 or p.x >= 10 or p.y >= 8 or layout[p.y][p.x] == "#"
		for y in range(8):
			for x in range(10):
				var point := Vector2i(x,y); var rect := Rect2(start+Vector2(point)*30,Vector2.ONE*30)
				if wall.call(point): Tiles.paint_wall(self,rect,point,wall)
				else:
					draw_texture_rect(Tiles.floor_tile(point),rect,false)
					Tiles.paint_floor_shadow(self,rect,point,wall)
	draw_string(FONT,Vector2(24,456),"확대 보기 · 같은 타일과 연결 규칙",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("c5beb0"))
	var room: Array = MAPS[2]
	var wall := func(p: Vector2i): return p.x < 0 or p.y < 0 or p.x >= 10 or p.y >= 8 or room[p.y][p.x] == "#"
	for y in range(4):
		for x in range(10):
			var point := Vector2i(x,y); var rect := Rect2(Vector2(24,478)+Vector2(point)*64,Vector2.ONE*64)
			if wall.call(point): Tiles.paint_wall(self,rect,point,wall)
			else:
				draw_texture_rect(Tiles.floor_tile(point),rect,false)
				Tiles.paint_floor_shadow(self,rect,point,wall)
