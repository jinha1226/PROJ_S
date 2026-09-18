extends RefCounted

## Short-room tactical prototype: Into-the-Breach-style enemy telegraphs with
## Darkest-Dungeon-style persistent HP/stress pressure.
const SIZE := Vector2i(7, 7)
const MAX_TURNS := 5
const DIRS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

var turn := 1
var phase := "PLAYER"
var selected_hero_id := 1
var actors: Array[Dictionary] = []
var walls: Dictionary = {}
var intents: Array[Dictionary] = []
var events: Array[Dictionary] = []

func _init() -> void:
	for x in range(SIZE.x):
		walls[Vector2i(x, 0)] = true
		walls[Vector2i(x, SIZE.y - 1)] = true
	for y in range(SIZE.y):
		walls[Vector2i(0, y)] = true
		walls[Vector2i(SIZE.x - 1, y)] = true
	walls[Vector2i(3, 3)] = true
	actors = [
		hero(1, "기사", Vector2i(2, 5), 12, 3, 35),
		hero(2, "도적", Vector2i(3, 5), 8, 2, 20),
		hero(3, "성직자", Vector2i(4, 5), 9, 2, 62),
		enemy(101, "가시괴물", Vector2i(2, 1), 6, 3),
		enemy(102, "광신도", Vector2i(4, 1), 5, 2),
		enemy(103, "사냥개", Vector2i(5, 2), 4, 2),
	]
	begin_player_turn()

func hero(id:int, name:String, pos:Vector2i, hp:int, power:int, stress:int) -> Dictionary:
	return {"id":id, "name":name, "team":"HERO", "position":pos, "hp":hp, "max_hp":hp,
		"power":power, "stress":stress, "acted":false}

func enemy(id:int, name:String, pos:Vector2i, hp:int, power:int) -> Dictionary:
	return {"id":id, "name":name, "team":"ENEMY", "position":pos, "hp":hp, "max_hp":hp,
		"power":power, "stress":0, "acted":false}

func actor_by_id(id:int) -> Dictionary:
	for actor in actors:
		if int(actor.id) == id: return actor
	return {}

func actor_at(cell:Vector2i) -> Dictionary:
	for actor in actors:
		if int(actor.hp) > 0 and actor.position == cell: return actor
	return {}

func living(team:String) -> Array[Dictionary]:
	var result:Array[Dictionary] = []
	for actor in actors:
		if actor.team == team and int(actor.hp) > 0: result.append(actor)
	return result

func terminal() -> String:
	if living("HERO").is_empty(): return "DEFEAT"
	if living("ENEMY").is_empty(): return "VICTORY"
	if turn > MAX_TURNS: return "SURVIVED"
	return ""

func begin_player_turn() -> void:
	phase = "PLAYER"
	for actor in actors:
		if actor.team == "HERO": actor.acted = false
	build_intents()

func build_intents() -> void:
	intents.clear()
	var heroes := living("HERO")
	for foe in living("ENEMY"):
		if heroes.is_empty(): break
		var target:Dictionary = heroes[0]
		var best := 999
		for candidate in heroes:
			var distance:int = manhattan(foe.position, candidate.position)
			if distance < best or (distance == best and int(candidate.id) < int(target.id)):
				best = distance
				target = candidate
		var delta:Vector2i = target.position - foe.position
		if best == 1:
			intents.append({"enemy_id":foe.id, "kind":"ATTACK", "target_id":target.id,
				"target_cell":target.position, "amount":foe.power})
		elif foe.name == "광신도" and best <= 4:
			intents.append({"enemy_id":foe.id, "kind":"STRESS", "target_id":target.id,
				"target_cell":target.position, "amount":18})
		else:
			var step := step_toward(foe.position, target.position)
			intents.append({"enemy_id":foe.id, "kind":"MOVE", "target_id":target.id,
				"target_cell":foe.position + step, "amount":0})

func step_toward(origin:Vector2i, target:Vector2i) -> Vector2i:
	var candidates:Array[Vector2i] = []
	var delta := target - origin
	if abs(delta.x) >= abs(delta.y):
		candidates.append(Vector2i(signi(delta.x), 0))
		candidates.append(Vector2i(0, signi(delta.y)))
	else:
		candidates.append(Vector2i(0, signi(delta.y)))
		candidates.append(Vector2i(signi(delta.x), 0))
	for direction in candidates + DIRS:
		if direction == Vector2i.ZERO: continue
		var cell := origin + direction
		if inside(cell) and not walls.has(cell) and actor_at(cell).is_empty(): return direction
	return Vector2i.ZERO

func select_hero(id:int) -> bool:
	var actor := actor_by_id(id)
	if actor.is_empty() or actor.team != "HERO" or actor.hp <= 0 or actor.acted: return false
	selected_hero_id = id
	return true

func act_on(cell:Vector2i) -> Dictionary:
	events.clear()
	if phase != "PLAYER" or not terminal().is_empty(): return {"accepted":false, "reason":"not_ready"}
	var hero_actor := actor_by_id(selected_hero_id)
	if hero_actor.is_empty() or hero_actor.acted or hero_actor.hp <= 0:
		return {"accepted":false, "reason":"select_ready_hero"}
	var distance := manhattan(hero_actor.position, cell)
	if distance != 1: return {"accepted":false, "reason":"adjacent_only"}
	if walls.has(cell) or not inside(cell): return {"accepted":false, "reason":"blocked"}
	var target := actor_at(cell)
	if target.is_empty():
		hero_actor.position = cell
		events.append({"kind":"move", "actor":hero_actor.id})
	elif target.team == "ENEMY":
		target.hp = maxi(0, int(target.hp) - int(hero_actor.power))
		events.append({"kind":"hit", "actor":hero_actor.id, "target":target.id, "amount":hero_actor.power})
	else:
		return {"accepted":false, "reason":"occupied"}
	hero_actor.acted = true
	build_intents()
	auto_select()
	return {"accepted":true, "events":events.duplicate(true)}

func guard_selected() -> Dictionary:
	events.clear()
	var hero_actor := actor_by_id(selected_hero_id)
	if phase != "PLAYER" or hero_actor.is_empty() or hero_actor.acted: return {"accepted":false}
	hero_actor.acted = true
	hero_actor["guard"] = true
	events.append({"kind":"guard", "actor":hero_actor.id})
	auto_select()
	return {"accepted":true, "events":events.duplicate(true)}

func auto_select() -> void:
	for actor in living("HERO"):
		if not actor.acted:
			selected_hero_id = int(actor.id)
			return

func end_turn() -> Array[Dictionary]:
	events.clear()
	if phase != "PLAYER" or not terminal().is_empty(): return events
	phase = "ENEMY"
	for intent in intents.duplicate(true):
		var foe := actor_by_id(int(intent.enemy_id))
		if foe.is_empty() or foe.hp <= 0: continue
		if intent.kind == "MOVE":
			var cell:Vector2i = intent.target_cell
			if inside(cell) and not walls.has(cell) and actor_at(cell).is_empty():
				foe.position = cell
				events.append({"kind":"enemy_move", "actor":foe.id})
		else:
			var target := actor_by_id(int(intent.target_id))
			if target.is_empty() or target.hp <= 0: continue
			if intent.kind == "ATTACK":
				var amount:int = int(intent.amount)
				if bool(target.get("guard", false)): amount = maxi(0, amount - 2)
				target.hp = maxi(0, int(target.hp) - amount)
				events.append({"kind":"enemy_hit", "actor":foe.id, "target":target.id, "amount":amount})
			elif intent.kind == "STRESS":
				target.stress = mini(100, int(target.stress) + int(intent.amount))
				events.append({"kind":"stress", "actor":foe.id, "target":target.id, "amount":intent.amount})
	for actor in actors: actor.erase("guard")
	turn += 1
	if terminal().is_empty(): begin_player_turn()
	return events.duplicate(true)

func intent_for_enemy(id:int) -> Dictionary:
	for intent in intents:
		if int(intent.enemy_id) == id: return intent
	return {}

func inside(cell:Vector2i) -> bool:
	return Rect2i(Vector2i.ZERO, SIZE).has_point(cell)

func manhattan(a:Vector2i, b:Vector2i) -> int:
	return abs(a.x-b.x) + abs(a.y-b.y)
