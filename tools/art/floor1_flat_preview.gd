extends Control
const Art = preload("res://expedition/art/floor1_art.gd")
const Actors = preload("res://expedition/art/mobile_art.gd")
const Walls = preload("res://expedition/art/masonry_tiles.gd")
const FONT = preload("res://assets/fonts/NanumSquareR.ttf")
const MAP = ["############","#..........#","#...##.....#","#...##.....#","#..........#","#.......#..#","#..........#","#####..#####"]

func _ready() -> void:
	get_window().content_scale_size = Vector2i(1000,820)
	get_window().size = Vector2i(1000,820)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("15191c"))
	draw_string(FONT,Vector2(28,36),"1층 · 먹선 캐릭터와 환경",HORIZONTAL_ALIGNMENT_LEFT,-1,24,Color("ded6c4"))
	var start := Vector2(44,100)
	var solid := func(p): return p.x < 0 or p.y < 0 or p.x >= 12 or p.y >= 8 or MAP[p.y][p.x] == "#"
	var walls: Array = []
	for y in range(8):
		for x in range(12):
			var p := Vector2i(x,y)
			var rect := Rect2(start+Vector2(p)*44,Vector2.ONE*44)
			if solid.call(p):
				walls.append({"point":p,"rect":rect,"tint":Color.WHITE})
			else:
				draw_texture_rect(Art.terrain({"terrain":"water" if x in [8,9,10] and y in [2,3] else "stone"},p),rect,false)
				Walls.paint_floor_shadow(self,rect,p,solid)
	Walls.paint_walls(self,walls,solid,Art.material())
	for placement in [["torch_lit",Vector2(2,0)],["torch_lit",Vector2(9,0)],["crate",Vector2(1,3)],["barrel",Vector2(2,3)],["locked_chest",Vector2(9,5)],["altar",Vector2(6,1)],["rubble",Vector2(4,5)]]:
		Art.paint_object(self,placement[0],Rect2(start+placement[1]*44,Vector2.ONE*44))
	for i in range(3):
		Actors.paint_actor(self,i,Rect2(start+Vector2(4+i,4)*44+Vector2(4,4),Vector2.ONE*36))
	var ids: Array = Art.catalog.objects.keys()
	for i in range(ids.size()):
		var pos := Vector2(28+(i%8)*120,490+(i/8)*140)
		Art.paint_object(self,ids[i],Rect2(pos,Vector2.ONE*86))
		draw_string(FONT,pos+Vector2(0,108),ids[i],HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("ded6c4"))
	for i in range(4):
		draw_texture_rect(Art.tile(["floor_a","floor_b","front","top"][i]),Rect2(Vector2(630+(i%2)*140,110+(i/2)*150),Vector2.ONE*128),false)
