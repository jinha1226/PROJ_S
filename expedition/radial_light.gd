extends RefCounted
## Adapted from ../playtest/party_grid_view.gd radial_darkness_sample/mesh.
## Shared polar vertices and a cached mesh avoid rebuilding on VFX frames.
var cache_key: Array = []
var mesh: ArrayMesh
var builds := 0

static func darkness(distance_cells: float, radius: float) -> float:
	var ratio := clampf((distance_cells-0.65)/maxf(0.001,radius-0.65+0.5),0,1)
	return lerpf(0.0,0.97,ratio*ratio*(3.0-2.0*ratio))

func get_mesh(center: Vector2, viewport: Vector2, tile_size: float, radius: float, strength: float = 1.0) -> ArrayMesh:
	var key: Array = [center,viewport,tile_size,radius,strength]
	if mesh != null and key == cache_key: return mesh
	cache_key = key; builds += 1
	var extent := 0.0
	for corner in [Vector2.ZERO,viewport,Vector2(viewport.x,0),Vector2(0,viewport.y)]: extent = maxf(extent,center.distance_to(corner))
	var vertices := PackedVector3Array([Vector3(center.x,center.y,0)])
	var colors := PackedColorArray([Color(0,0,0,0)])
	var indices := PackedInt32Array()
	const RINGS := 32
	const SEGMENTS := 64
	for ring in range(1,RINGS+1):
		var distance := extent*ring/RINGS
		for segment in range(SEGMENTS):
			var angle := TAU*segment/SEGMENTS
			var p := center+Vector2(cos(angle),sin(angle))*distance
			vertices.append(Vector3(p.x,p.y,0)); colors.append(Color(0,0,0,darkness(distance/tile_size,radius)*strength))
	for ring in range(RINGS):
		for segment in range(SEGMENTS):
			var outer := 1+ring*SEGMENTS+segment
			var next := 1+ring*SEGMENTS+(segment+1)%SEGMENTS
			if ring == 0: indices.append_array(PackedInt32Array([0,next,outer]))
			else:
				var inner := outer-SEGMENTS; var inner_next := next-SEGMENTS
				indices.append_array(PackedInt32Array([inner,next,outer,inner,inner_next,next]))
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_COLOR] = colors; arrays[Mesh.ARRAY_INDEX] = indices
	mesh = ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
