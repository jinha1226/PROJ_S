extends RefCounted
## Parallel 2:1 diamond grid. Never changes logical cells or movement rules.
static func half_width(viewport:Rect2,count:int)->float:
	return minf(viewport.size.x/(maxi(1,count)*1.35),viewport.size.y/maxi(1,count))

static func project(point:Vector2,viewport:Rect2,count:int)->Vector2:
	var local:=point-Vector2.ONE*(float(count)*0.5)
	var h:=half_width(viewport,count)
	return viewport.get_center()+Vector2((local.x-local.y)*h,(local.x+local.y)*h*0.5)

static func unproject(pixel:Vector2,viewport:Rect2,count:int)->Vector2:
	var p:Vector2=(pixel-viewport.get_center())/maxf(0.001,half_width(viewport,count))
	return Vector2(p.y+p.x*0.5,p.y-p.x*0.5)+Vector2.ONE*(float(count)*0.5)

static func polygon(cell:Vector2i,viewport:Rect2,count:int)->PackedVector2Array:
	var result:=PackedVector2Array()
	for corner in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
		result.append(project(Vector2(cell)+corner,viewport,count))
	return result
