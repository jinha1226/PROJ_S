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
func draw_map(layout: Array, start: Vector2, scale: float, rows: int = 8) -> void:
	var wall := func(p: Vector2i): return p.x < 0 or p.y < 0 or p.x >= 10 or p.y >= 8 or layout[p.y][p.x] == "#"
	var walls: Array = []
	for y in range(rows):
		for x in range(10):
			var point := Vector2i(x,y); var rect := Rect2(start+Vector2(point)*scale,Vector2.ONE*scale)
			if wall.call(point):
				draw_rect(rect,Color("090c10")); walls.append({"point":point,"rect":rect,"tint":Color.WHITE})
			else:
				draw_texture_rect(Tiles.floor_tile(point),rect,false)
				Tiles.paint_floor_shadow(self,rect,point,wall)
	Tiles.paint_walls(self,walls,wall)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("101215"))
	draw_string(FONT,Vector2(24,34),"벽 윤곽 연결 v3",HORIZONTAL_ALIGNMENT_LEFT,-1,24,Color("d4c5a8"))
	for i in range(4): draw_texture_rect(Tiles.tile(i),Rect2(24+i*60,54,56,56),false)
	var titles := ["방 / 출입구","꺾인 복도","기둥 / 안쪽 모서리"]
	for example in range(3):
		var start := Vector2(24+example*330,180)
		draw_string(FONT,start-Vector2(0,32),titles[example],HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("c5beb0"))
		draw_map(MAPS[example],start,30)
	draw_string(FONT,Vector2(24,456),"가로·세로·모서리: 동일한 윗면 윤곽",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("c5beb0"))
	draw_map(MAPS[2],Vector2(24,510),64,4)
