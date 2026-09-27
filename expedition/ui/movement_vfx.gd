extends RefCounted
## Walking feedback is visual time only. Feet and the camera stay grounded.
const DUST_LIFETIME := 0.24
const DUST_SPACING := 0.55
const MAX_DUST := 32
var phases: Dictionary = {}
var weights: Dictionary = {}
var distances: Dictionary = {}
var dust: Array = []

func reset() -> void:
	phases.clear(); weights.clear(); distances.clear(); dust.clear()

func advance(delta: float, moving: Array) -> bool:
	for puff in dust: puff.age += delta
	dust = dust.filter(func(p): return float(p.age) < DUST_LIFETIME)
	for id in moving:
		weights[id] = move_toward(float(weights.get(id,0)),1.0,delta*12)
	for id in weights.keys():
		if id in moving: continue
		weights[id] = move_toward(float(weights[id]),0.0,delta*12)
		if float(weights[id]) <= 0: weights.erase(id)
	return not dust.is_empty() or not weights.is_empty()

func travel(id: int, from: Vector2, to: Vector2, dusty: bool) -> void:
	var distance := from.distance_to(to)
	if distance < 0.0001: return
	phases[id] = fposmod(float(phases.get(id,0))+distance*PI*0.5,TAU)
	distances[id] = float(distances.get(id,0))+distance
	if float(distances[id]) < DUST_SPACING: return
	distances[id] = fposmod(float(distances[id]),DUST_SPACING)
	if not dusty: return
	dust.append({"world":to,"direction":(to-from).normalized(),"age":0.0,"side":1.0 if dust.size()%2 == 0 else -1.0})
	if dust.size() > MAX_DUST: dust.pop_front()

func body_offset(id: int, half_width: float) -> Vector2:
	var lift := pow(sin(float(phases.get(id,0))),2)*float(weights.get(id,0))*clampf(half_width*0.14,1.5,3.0)
	return Vector2(0,-lift)

func paint(canvas, project: Callable, half_width: float, visible: Dictionary) -> void:
	for puff in dust:
		var point := Vector2i(floori(puff.world.x),floori(puff.world.y))
		if not visible.has(point): continue
		var t: float = float(puff.age)/DUST_LIFETIME
		var direction: Vector2 = puff.direction
		var base: Vector2 = project.call(puff.world)+Vector2(0,half_width*0.65)
		base -= direction*half_width*(0.10+t*0.35)
		var across := Vector2(-direction.y,direction.x)*float(puff.side)
		var radius := clampf(half_width*0.12,1.2,2.4)*(0.65+t)
		var color := Color(0.70,0.61,0.47,0.36*(1-t)*(1-t))
		canvas.draw_circle(base+across*radius*0.6,radius,color)
		canvas.draw_circle(base-across*radius*0.8-direction*radius,radius*0.65,Color(color,color.a*0.7))
