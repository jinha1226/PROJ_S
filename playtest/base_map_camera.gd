extends RefCounted

var zoom:=1.0
var pan:=Vector2.ZERO
var contacts:Dictionary={}
var pinching:=false
var last_distance:=0.0
var last_center:=Vector2.ZERO

func clamp_pan(view)->void:
	var extent:Vector2=Vector2(view._grid_size())*view._cell_size()
	var overflow:=maxf(0,(extent.x-view.size.x)*0.5)
	pan.x=clampf(pan.x,-overflow,overflow)
	pan.y=clampf(pan.y,minf(0,view.size.y-extent.y),0)

func zoom_at(view,factor:float,anchor:Vector2)->void:
	var tile:Vector2=(anchor-view._map_origin())/view._cell_size()
	zoom=clampf(zoom*factor,1,3)
	pan+=anchor-(view._map_origin()+tile*view._cell_size())
	clamp_pan(view);view._resolve_layout();view.queue_redraw()

func handle(view,event:InputEvent)->bool:
	if event is InputEventMagnifyGesture:
		zoom_at(view,event.factor,event.position);return true
	if event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		zoom_at(view,1.15 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1/1.15,event.position)
		return true
	if event is InputEventScreenTouch:
		if event.pressed:
			contacts[event.index]=event.position
			if contacts.size()>=2:
				pinching=true;view._pointer_down=false;view._pointer_dragged=true
				var points:Array=contacts.values()
				last_distance=points[0].distance_to(points[1]);last_center=(points[0]+points[1])*0.5
				return true
		else:
			contacts.erase(event.index)
			if pinching:
				if contacts.is_empty():pinching=false
				view._pointer_down=false;return true
	elif event is InputEventScreenDrag and contacts.has(event.index):
		contacts[event.index]=event.position
		if pinching:
			if contacts.size()>=2:
				var points:Array=contacts.values()
				var center:Vector2=(points[0]+points[1])*0.5
				var distance:float=points[0].distance_to(points[1])
				pan+=center-last_center
				zoom_at(view,distance/maxf(1,last_distance),center)
				last_distance=distance;last_center=center
			return true
	return pinching
