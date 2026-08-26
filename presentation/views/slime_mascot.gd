class_name SlimeMascot
extends Control

var _elapsed: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(420.0, 360.0)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()


func _draw() -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.55)
	var bob := sin(_elapsed * 2.2) * 8.0
	center.y += bob

	var shadow := _ellipse_points(center + Vector2(0.0, 112.0), 118.0, 22.0, 28)
	draw_colored_polygon(shadow, Color("402b5c66"))

	var body := PackedVector2Array()
	var radius := 126.0
	for index: int in range(25):
		var ratio := float(index) / 24.0
		var angle := PI - ratio * PI
		body.append(center + Vector2(cos(angle) * radius, -sin(angle) * radius))
	body.append(center + Vector2(radius, 80.0))
	body.append(center + Vector2(72.0, 104.0))
	body.append(center + Vector2(22.0, 88.0))
	body.append(center + Vector2(-28.0, 106.0))
	body.append(center + Vector2(-78.0, 88.0))
	body.append(center + Vector2(-radius, 80.0))
	draw_colored_polygon(body, Color("70dfb4"))

	var highlight := _ellipse_points(center + Vector2(-52.0, -52.0), 30.0, 18.0, 20)
	draw_colored_polygon(highlight, Color("c8ffe8aa"))

	var eye_y := center.y - 5.0
	draw_circle(Vector2(center.x - 43.0, eye_y), 18.0, Color("26364a"))
	draw_circle(Vector2(center.x + 43.0, eye_y), 18.0, Color("26364a"))
	draw_circle(Vector2(center.x - 49.0, eye_y - 6.0), 5.0, Color.WHITE)
	draw_circle(Vector2(center.x + 37.0, eye_y - 6.0), 5.0, Color.WHITE)
	draw_arc(center + Vector2(0.0, 30.0), 28.0, 0.15, PI - 0.15, 24, Color("26364a"), 6.0, true)

	draw_circle(center + Vector2(138.0, -105.0), 15.0, Color("d7fff2aa"))
	draw_circle(center + Vector2(166.0, -142.0), 8.0, Color("d7fff277"))


static func _ellipse_points(center: Vector2, radius_x: float, radius_y: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index: int in range(segments):
		var angle := TAU * float(index) / float(segments)
		points.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	return points
