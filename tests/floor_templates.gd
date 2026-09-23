extends SceneTree
const Templates = preload("res://expedition/floor_templates.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var ids := ["entry_camp","descent","flooded_cistern","collapsed_store","sealed_treasury","timber_gallery","boss_lair"]
	for id in ids:
		var def: Dictionary = Templates.definition(id)
		check(not def.is_empty() and def.rows.size() >= 3,"template %s exists" % id)
		var width: int = def.rows[0].length()
		check(def.rows.all(func(r): return r.length() == width),"%s rows equal length" % id)
		for y in range(def.rows.size()):
			for x in range(width):
				var edge: bool = x == 0 or y == 0 or x == width-1 or y == def.rows.size()-1
				var corner: bool = (x == 0 or x == width-1) and (y == 0 or y == def.rows.size()-1)
				var glyph: String = def.rows[y][x]
				if edge: check(glyph in ["#","+"],"%s edge is wall or door" % id)
				else: check(glyph != "+","%s door only on edge" % id)
				# A corridor cannot approach a corner door head-on, so it never opens.
				check(not (corner and glyph == "+"),"%s door never on a corner" % id)
		var parsed: Dictionary = Templates.parse(def.rows)
		check(parsed.width == width and parsed.height == def.rows.size(),"%s parsed size" % id)
		check(parsed.doors.size() >= 1,"%s has a door candidate" % id)
		check(parsed.terrain.size() == width*def.rows.size(),"%s every cell has terrain" % id)
	check(Templates.definition("nope").is_empty(),"unknown template is empty")
	var descent: Dictionary = Templates.parse(Templates.definition("descent").rows)
	check(descent.features.values().filter(func(f): return f.kind == "stairs").size() == 1,"descent has one stair")
	check(descent.anchor == Vector2i(-1,-1),"descent has no monster anchor")
	check(descent.terrain.values().any(func(v): return v == "metal"),"descent accents survive parsing")
	var lair: Dictionary = Templates.parse(Templates.definition("boss_lair").rows)
	check(lair.anchor != Vector2i(-1,-1) and lair.doors.size() == 2,"boss lair has anchor and two doors")
	check(lair.features.values().filter(func(f): return f.kind == "pylon").size() == 1,"boss lair has a pylon")
	check(lair.features.values().filter(func(f): return f.kind == "stairs").size() == 1,"boss lair has stairs")
	var treasury: Dictionary = Templates.parse(Templates.definition("sealed_treasury").rows)
	check(treasury.doors.size() == 1,"treasury has exactly one door")
	check(treasury.features.values().filter(func(f): return f.kind == "curio" and f.curio_id == "BROKEN_CHEST").size() == 1,"treasury has one broken chest")
	check(treasury.features.values().filter(func(f): return f.kind == "altar").size() == 1,"treasury has an altar")
	var entry: Dictionary = Templates.parse(Templates.definition("entry_camp").rows)
	var entry_cell: Vector2i = entry.features.keys().filter(func(p): return entry.features[p].kind == "entry")[0]
	for dx in range(1,5): check(entry.terrain.get(entry_cell+Vector2i(dx,0),"wall") != "wall","four free cells east of the entry gate")
	# Rotation: 90 degrees clockwise maps (x,y) -> (height-1-y, x).
	var rows := ["#+#","#.#","###"]
	var turned: Array = Templates.rotate(rows,1)
	check(turned == ["###","#.+","###"],"rotate once clockwise (%s)" % [turned])
	check(Templates.rotate(rows,4) == rows,"four turns is identity")
	var cistern: Dictionary = Templates.parse(Templates.rotate(Templates.definition("flooded_cistern").rows,1))
	check(cistern.width == 10 and cistern.height == 12,"rotated cistern swaps dimensions")
	check(cistern.doors.size() == 2 and cistern.anchor != Vector2i(-1,-1),"rotation keeps doors and anchor")
	# Stamp into a 16x16 board of walls.
	var terrain: Array = []; terrain.resize(256); terrain.fill("wall")
	Templates.stamp(terrain,16,Vector2i(2,3),treasury)
	check(terrain[(3+1)*16+2+1] == "stone","stamp writes interior floor at origin offset")
	check(terrain[(3+treasury.height-1)*16+2+treasury.doors[0].x] == "wall","door candidates stay wall until corridors")
	check(terrain[0] == "wall" and terrain[255] == "wall","stamp does not touch outside cells")
	print("Floor templates: %d failures" % failures); quit(1 if failures else 0)
