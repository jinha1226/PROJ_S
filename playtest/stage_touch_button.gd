extends Button
signal held
var _finger:=-1
var _origin:=Vector2.ZERO
var _cancelled:=false
var _held:=false
var _serial:=0
func _gui_input(event:InputEvent)->void:
	if event is InputEventScreenTouch:
		if disabled:return
		if event.pressed and _finger<0:
			_finger=event.index;_origin=event.position;_cancelled=false;_held=false;_serial+=1
			var serial:=_serial
			get_tree().create_timer(0.55).timeout.connect(func():
				if serial==_serial and _finger>=0 and not _cancelled:_held=true;held.emit())
		elif not event.pressed and event.index==_finger:
			_finger=-1;_serial+=1
			if not _cancelled and not _held and not event.canceled and Rect2(Vector2.ZERO,size).has_point(event.position):pressed.emit()
		accept_event()
	elif event is InputEventScreenDrag and event.index==_finger:
		if event.position.distance_to(_origin)>12:_cancelled=true
		accept_event()
	elif event is InputEventMouseButton and event.device==InputEvent.DEVICE_ID_EMULATION:accept_event()
