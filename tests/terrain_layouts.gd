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
	var neighbor = art.terrain({"terrain":"stone"},Vector2i(2,2))
	check(floor_tile.atlas == art.FLAGSTONE and neighbor.region.position.x == floor_tile.region.end.x,"adjacent stone tiles sample continuous paving")
	check(art.terrain({"terrain":"wall"},Vector2i(1,2)).atlas == art.FLAGSTONE,"walls use matching masonry")
	check(art.terrain({"terrain":"stone"},Vector2i(5,6)).region == floor_tile.region,"paving repeat is stable in world space")
	print("Terrain layouts: %d failures; 100 seeds / 900 rooms" % failures)
	quit(1 if failures else 0)
