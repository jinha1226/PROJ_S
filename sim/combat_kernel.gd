extends RefCounted

## Shared by the live campaign and the small interactive harness.
## State and effects belong to the host; this kernel owns ordering and geometry.
const DIRECTIONS := [Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.DOWN,
	Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1)]
const SIGHT_RADIUS := 6

static func earlier(best:Dictionary, at:int, id:int, end:int, boundary:bool=false)->Dictionary:
	if at>end or at==end and not boundary:return best
	if best.is_empty() or at<int(best.at) or at==int(best.at) and id<int(best.id):
		return {"at":at,"id":id}
	return best

static func advance(end:int, choose:Callable, dispatch:Callable, limit:int=10000)->bool:
	var previous_time:=-1
	for iteration in range(limit):
		var next:Dictionary=choose.call(end)
		if next.is_empty():return true
		var at:=int(next.at)
		var id:=int(next.id)
		if at>end or at<previous_time:return false
		if not bool(dispatch.call(next)):return false
		previous_time=at
	return false

static func open_edge(origin:Vector2i,target:Vector2i,solid:Callable)->bool:
	var delta:=target-origin
	if delta not in DIRECTIONS:return false
	return not (delta.x!=0 and delta.y!=0 and
		bool(solid.call(origin+Vector2i(delta.x,0))) and bool(solid.call(origin+Vector2i(0,delta.y))))

static func sees(origin:Vector2i,target:Vector2i,solid:Callable,radius:int=SIGHT_RADIUS)->bool:
	var delta:=target-origin
	if delta.length_squared()>radius*radius:return false
	var cell:=origin
	var dx:=absi(delta.x);var dy:=absi(delta.y)
	var sx:=signi(delta.x);var sy:=signi(delta.y)
	var ix:=0;var iy:=0
	while cell!=target:
		var decision:=(1+2*ix)*dy-(1+2*iy)*dx
		var next:=cell
		if decision==0:next+=Vector2i(sx,sy);ix+=1;iy+=1
		elif decision<0:next.x+=sx;ix+=1
		else:next.y+=sy;iy+=1
		if not open_edge(cell,next,solid):return false
		cell=next
		if cell!=target and bool(solid.call(cell)):return false
	return true
