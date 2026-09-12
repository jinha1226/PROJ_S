extends Control
## Discrete, event-driven pixel silhouettes; no animation/process loop.
var kind:String="FOOD"
var level:int=-1
var lit:bool=false
func configure(value:float,is_lit:bool=true)->void:
	var next:=clampi(ceili(clampf(value,0.0,1.0)*4),0,4)
	if next==level and lit==is_lit:return
	level=next;lit=is_lit;queue_redraw()
func _draw()->void:
	var origin:=(size-Vector2(20,20))*0.5
	if kind=="FOOD":
		draw_rect(Rect2(origin+Vector2(0,16),Vector2(20,3)),Color("766b58"))
		for i in range(4):
			var color:=Color("d4a45c") if i<level else Color("38332e")
			draw_rect(Rect2(origin+Vector2(1+i*5,5),Vector2(4,11)),color)
			if i<level:draw_rect(Rect2(origin+Vector2(2+i*5,7),Vector2(2,3)),Color("f1ce89"))
	else:
		draw_rect(Rect2(origin+Vector2(8,10),Vector2(4,10)),Color("92613b"))
		draw_rect(Rect2(origin+Vector2(5,9),Vector2(10,4)),Color("706353"))
		if lit and level>0:
			var height:=float(2+level*2)
			draw_rect(Rect2(origin+Vector2(5,11-height),Vector2(10,height)),Color("d87335"))
			draw_rect(Rect2(origin+Vector2(8,11-height),Vector2(4,height)),Color("ffd984"))
