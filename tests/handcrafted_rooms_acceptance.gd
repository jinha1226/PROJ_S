extends SceneTree
const Rooms = preload("res://sim/handcrafted_room_templates.gd")
const Generator = preload("res://sim/nine_room_generator.gd")
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func _init() -> void:
	for template in Rooms.CONTENT.templates:
		check(template.rows.size() == 8, "height")
		var open: Dictionary = {}
		for y in range(8):
			check(template.rows[y].length() == 8, "width")
			for x in range(8):
				check(Rooms.CONTENT.legend.has(template.rows[y][x]), "legend")
				if template.rows[y][x] != "#": open[Vector2i(x,y)] = true
		check(open.size() >= 40, "walkable count")
		var seen: Dictionary = {Vector2i(3,3): true}
		var todo: Array[Vector2i] = [Vector2i(3,3)]
		for p in todo:
			for d in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var next: Vector2i = p + d
				if open.has(next) and not seen.has(next):
					seen[next] = true
					todo.append(next)
		check(seen.size() == open.size(), "all floor connected")
		var occupied: Dictionary = {}
		for cell in template.enemy_cells:
			var p := Vector2i(cell[0],cell[1])
			check(open.has(p) and not occupied.has(p), "enemy spawn")
			occupied[p] = true
		for entry in [Vector2i(3,0), Vector2i(7,3), Vector2i(3,7), Vector2i(0,3)]:
			check(seen.has(entry), "exit reachable")
			var safe_count := 0
			for p in open:
				if absi(p.x-entry.x)+absi(p.y-entry.y) <= 2 and template.rows[p.y][p.x] == "." and not occupied.has(p):
					safe_count += 1
			check(safe_count >= 3, "three safe arrival cells")
			for p in occupied:
				check(absi(p.x-entry.x)+absi(p.y-entry.y) > 2, "spawn outside arrival zone")
	for seed in range(20):
		for floor_index in [1,2]:
			var generated := Generator.generate(seed,floor_index)
			var ids: Dictionary = {}
			for room in generated.rooms:
				if room.role == "COMBAT": ids[room.template_id] = true
			check(ids.size() == (4 if floor_index==1 else 3), "four authored first-floor combats / three second-floor templates")
	for failure in failures: printerr(failure)
	print("HANDCRAFTED_ROOMS ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
