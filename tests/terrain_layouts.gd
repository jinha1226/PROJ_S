extends SceneTree
const Session = preload("res://expedition/session.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	for seed in range(100):
		var s = Session.new(seed,true,true); s.depart()
		var layouts := {}
		for row in s.rooms:
			layouts[row.layout] = true
			check(row.tiles.size() == 100,"100 cells per room")
			var seen := {Vector2i.ZERO:true}; var queue := [Vector2i.ZERO]; var cursor := 0
			while cursor < queue.size():
				var point: Vector2i = queue[cursor]; cursor += 1
				for direction in s.CARDINALS:
					var next: Vector2i = point+direction
					if not s.inside(next) or seen.has(next) or row.tiles[next.y*10+next.x].terrain == "wall": continue
					seen[next] = true; queue.append(next)
			check(seen.size() == row.tiles.filter(func(c): return c.terrain != "wall").size(),"all walkable terrain connected")
			for pad in [Vector2i(0,4),Vector2i(9,4),Vector2i(4,0),Vector2i(4,9),Vector2i(5,4),Vector2i(4,4)]:
				check(seen.has(pad),"door boss and objective reachable")
			s.room = row.id; s.enter_room()
			for actor in s.party+s.enemies:
				check(s.inside(actor.pos) and s.tile(actor.pos).terrain != "wall","spawn on walkable tile")
		check(layouts.size() == 4,"all four layouts appear per expedition")
	var s = Session.new(14,true,true); s.depart()
	s.party[0].pos = Vector2i(8,8); s.party[1].pos = Vector2i(1,1); s.enemies[0].pos = Vector2i(8,7)
	for c in s.tiles: c.terrain = "stone"
	check(Vector2i(9,9) in s.movement_cells(0),"new edge supports eight-way movement")
	s.party[0].learned_abilities.append("BOMB"); s.party[0].equipped_abilities[0] = "BOMB"
	check(Vector2i(9,9) in s.Abilities.cells(s,s.party[0],"BOMB",Vector2i(9,8)),"ability AoE covers new edge")
	var art = preload("res://expedition/mobile_art.gd")
	var floor_tile = art.terrain({"terrain":"stone"},Vector2i(1,2))
	check(floor_tile.atlas == art.Masonry.SHEET,"stone uses the masonry atlas")
	check(art.terrain({"terrain":"wall"},Vector2i(1,2)).atlas == art.Masonry.SHEET,"walls use matching masonry")
	check(art.terrain({"terrain":"stone"},Vector2i(1,2)).region == floor_tile.region,"paving is stable across redraws")
	for mask in range(16):
		var walls := {Vector2i.ZERO:true}
		for direction in range(4):
			if not (mask & (1 << direction)): walls[art.Masonry.DIRECTIONS[direction]] = true
		check(art.Masonry.exposed(Vector2i.ZERO,func(p): return walls.has(p)) == mask,"wall junction resolves every cardinal combination")
	# Every adjacent wall pair must share the same coping profile at its seam.
	# Covers straight runs, concave/convex corners, ends and T/cross junctions.
	for mask in range(1024):
		var walls := {Vector2i(1,1):true,Vector2i(2,1):true}
		var bit := 0
		for y in range(3):
			for x in range(4):
				var p := Vector2i(x,y)
				if walls.has(p): continue
				if mask & (1 << bit): walls[p] = true
				bit += 1
		var solid := func(p): return walls.has(p)
		var left: Array = art.Masonry.contour_parts(Vector2i(1,1),solid)
		var right: Array = art.Masonry.contour_parts(Vector2i(2,1),solid)
		for sample in [0.01,0.12,0.30,0.50,0.70,0.88,0.99]:
			var lhs: bool = left.any(func(r): return r.has_point(Vector2(0.999,sample)))
			var rhs: bool = right.any(func(r): return r.has_point(Vector2(0.001,sample)))
			check(lhs == rhs,"coping continues across horizontal wall seams")
		var rotated := {}
		for p in walls: rotated[Vector2i(p.y,p.x)] = true
		var solid_rotated := func(p): return rotated.has(p)
		var upper: Array = art.Masonry.contour_parts(Vector2i(1,1),solid_rotated)
		var lower: Array = art.Masonry.contour_parts(Vector2i(1,2),solid_rotated)
		for sample in [0.01,0.12,0.30,0.50,0.70,0.88,0.99]:
			check(upper.any(func(r): return r.has_point(Vector2(sample,0.999))) == lower.any(func(r): return r.has_point(Vector2(sample,0.001))),"coping continues across vertical wall seams")
	print("Terrain layouts: %d failures; 100 seeds / 900 rooms" % failures)
	quit(1 if failures else 0)
