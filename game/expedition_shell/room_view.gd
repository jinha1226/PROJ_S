extends Control
## Presentation only. Coordinates are room-local; no simulator or legacy session.
signal member_selected(index:int)
signal cell_selected(cell:Vector2i)

const Art=preload("res://playtest/handcrafted_tile_assets.gd")
const BODIES=[
	preload("res://assets/dcss-cc0/world/mon__human.png"),
	preload("res://assets/dcss-cc0/world/mon__elf.png"),
	preload("res://assets/dcss-cc0/world/mon__deep_dwarf.png")]
const PARTY_CELLS=[Vector2i(3,4),Vector2i(4,4),Vector2i(3,5)]
const SIZE=8
var selected_member:int=0
var selected_cell:=Vector2i(-1,-1)

func _ready()->void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter=Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	# Bounded asset preparation; subsequent draw calls only read cached textures.
	for column in [0,1,3]:Art.tile(0,column)
	Art.obstacle(0)
	queue_redraw()

func half_width()->float:
	return maxf(1.0,minf((size.x-32.0)/16.0,(size.y-56.0)/11.0))

func project(cell:Vector2)->Vector2:
	var h:=half_width()
	return size*0.5+Vector2((cell.x-cell.y)*h,(cell.x+cell.y-7.0)*h*0.5+12.0)

func cell_at(point:Vector2)->Vector2i:
	var p:Vector2=(point-size*0.5-Vector2(0,12))/half_width()
	return Vector2i(floori(p.y+p.x*0.5+4.0),floori(p.y-p.x*0.5+4.0))

func diamond(cell:Vector2i)->PackedVector2Array:
	var c:=project(Vector2(cell));var h:=half_width()
	return PackedVector2Array([c+Vector2(0,-h*0.5),c+Vector2(h,0),c+Vector2(0,h*0.5),c+Vector2(-h,0)])

func blocked(cell:Vector2i)->bool:
	return cell.x==0 or cell.y==0 or cell==Vector2i(5,2)

func actor_rect(index:int)->Rect2:
	var h:=half_width();var foot:=project(Vector2(PARTY_CELLS[index]))
	return Rect2(foot-Vector2(h,2*h),Vector2(2*h,2*h))

func select_member(index:int)->void:
	if index<0 or index>=PARTY_CELLS.size():return
	selected_member=index;selected_cell=PARTY_CELLS[index];queue_redraw()

func _gui_input(event:InputEvent)->void:
	var point:=Vector2.ZERO
	if event is InputEventMouseButton:
		if not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
		point=event.position
	elif event is InputEventScreenTouch:
		if not event.pressed:return
		point=event.position
	else:return
	# Hit-test actors from front to back, matching their draw order.
	for i in range(PARTY_CELLS.size()-1,-1,-1):
		if actor_rect(i).has_point(point):
			select_member(i);member_selected.emit(i);accept_event();return
	var cell:=cell_at(point)
	if cell.x>=0 and cell.x<SIZE and cell.y>=0 and cell.y<SIZE:
		selected_cell=cell;queue_redraw();cell_selected.emit(cell);accept_event()

func _draw()->void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("#10171c"))
	var h:=half_width()
	for y in range(SIZE):
		for x in range(SIZE):
			var cell:=Vector2i(x,y);var c:=project(Vector2(cell))
			# The source is an actual transparent 2:1 diamond, not a square tile.
			draw_texture_rect(Art.tile(0,Art.variant(cell,0)),Rect2(c-Vector2(h,h*0.5),Vector2(2*h,h)),false)
	if selected_cell.x>=0:draw_colored_polygon(diamond(selected_cell),Color(0.6,0.8,0.9,0.25))
	for depth in range(2*SIZE-1):
		for y in range(SIZE):
			var x:=depth-y
			if x<0 or x>=SIZE:continue
			var cell:=Vector2i(x,y);var c:=project(Vector2(cell))
			if blocked(cell):
				draw_texture_rect(Art.obstacle(0),Rect2(c-Vector2(h,1.5*h),Vector2(2*h,2*h)),false)
			var member:int=PARTY_CELLS.find(cell)
			if member>=0:
				draw_circle(c,h*0.38,Color(0,0,0,0.5))
				if member==selected_member:
					var outline:=diamond(cell);outline.append(outline[0]);draw_polyline(outline,Color("#d5b675"),2.0)
				draw_texture_rect(BODIES[member],actor_rect(member),false)
