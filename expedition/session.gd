extends RefCounted
## Expedition host: persistent actors; room-local terrain, enemies and intent.
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
const Memory = preload("res://sim/party_memory_state.gd")
const Body = preload("res://game/rebuilt/body_bridge.gd")
const TurnCore = preload("res://sim/turn_engine.gd")
const ElementRules = preload("res://sim/environment_rules.gd")
const Injury = preload("res://sim/body_injury_system.gd")
const Dungeon = preload("res://expedition/dungeon_map.gd")
const DIRECTIONS = [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]
var rooms: Array = []
var seed_value := 731
var phase := "TOWN"
var room := 0
var party: Array = []
var enemies: Array = []
var tiles: Array = []
var visited: Array = []
var log_lines: Array[String] = []
var food := 9
var torches := 3
var light := 90
var loot := 0
var bank := 0
var serial := 0
var world_time := 0
var round_number := 0
var expedition_number := 0
var selected := 0
var intents: Array = []
var hunger := 0
var supplies: Array = [2,2,1,1,1,3]
const SUPPLY_NAMES = ["치유 물약","정신 안정제","활력 물약","화염 두루마리","물 두루마리","붕대"]

func _init(p_seed: int = 731) -> void:
	seed_value = p_seed
	for i in range(3):
		party.append(make_actor(i, ["아린", "브란", "세라"][i], false))
	message("부상과 기억은 원정을 마쳐도 남습니다. 준비되면 출정하세요.")

func make_actor(id: int, actor_name: String, enemy: bool) -> Dictionary:
	var actor := {"id":id, "name":actor_name, "enemy":enemy,
		"pos":Vector2i.ZERO, "hp":28 if enemy else 55, "max_hp":28 if enemy else 55,
		"stress":0, "condition":"평온", "ap":2,
		"body":Body.create(id, seed_value, enemy),
		"profile":Hexaco.generated(seed_value, id + 1), "memory":Memory.new()}
	Body.sync(actor)
	return actor

func message(value: String) -> void:
	log_lines.append(value)
	if log_lines.size() > 40: log_lines.pop_front()

func alive() -> Array:
	return party.filter(func(a): return a.hp > 0)

func depart() -> bool:
	if phase != "TOWN" or alive().is_empty(): return false
	expedition_number += 1
	food = 27; torches = 5; light = 90; loot = 0; hunger = 0
	supplies = [2,2,1,1,1,3]
	rooms = Dungeon.generate(seed_value + expedition_number * 7919)
	room = 0; visited = [0]
	enter_room()
	message("원정 %d · 폐허의 수문장을 처치하고 귀환하세요." % expedition_number)
	return true

func can_travel(destination: int) -> bool:
	return phase == "EXPLORE" and not rooms.is_empty() and destination in rooms[room].links

func travel(destination: int) -> bool:
	if not can_travel(destination): return false
	world_time += 100
	light = maxi(0, light - 18)
	var required := alive().size()
	var hungry := food < required
	hunger = clampi(hunger + (25 if hungry else 4),0,100)
	food = maxi(0, food - required)
	for actor in alive(): stress(actor, (12 if hungry else 3) + (9 if light < 35 else 0))
	var previous := room
	room = destination
	if room not in visited: visited.append(room)
	message("복도 통과 · 식량 -%d / 횃불 밝기 %d%s" % [required, light, " · 굶주림" if hungry else ""])
	enter_room(previous)
	return true

func enter_room(previous: int = -1) -> void:
	var row: Dictionary = rooms[room]
	tiles = row.tiles
	enemies = row.enemies
	intents = []
	phase = "EXPLORE"
	var spawn := Vector2i(1,2)
	if previous == room + 1: spawn = Vector2i(6,2)
	elif previous == room - 3: spawn = Vector2i(1,1)
	elif previous == room + 3: spawn = Vector2i(1,6)
	for i in range(party.size()):
		party[i].pos = spawn + (Vector2i(i,0) if previous in [room-3,room+3] else Vector2i(0,i))
	if row.kind in ["battle","boss"] and not row.cleared: start_battle()

func doors() -> Dictionary:
	var result: Dictionary = {}
	if rooms.is_empty(): return result
	for destination in rooms[room].links:
		var delta: int = destination - room
		var point: Vector2i = {1:Vector2i(7,4),-1:Vector2i(0,4),3:Vector2i(4,7),-3:Vector2i(4,0)}[delta]
		result[point] = destination
	return result

func stress(actor: Dictionary, amount: int) -> void:
	var trauma := int(actor.memory.strongest(["SELF_HARM", "ALLY_LOST"]).get("salience", 0)) / 200
	var change := amount
	if amount > 0: change = maxi(1, amount * (650 + actor.profile.value("E")) / 1000 + trauma)
	actor.stress = clampi(actor.stress + change, 0, 200)
	actor.condition = "붕괴" if actor.stress >= 150 else "불안" if actor.stress >= 100 else "평온"

func use_torch() -> bool:
	if phase not in ["EXPLORE", "EVENT"] or torches <= 0 or light >= 100: return false
	torches -= 1; light = mini(100, light + 50)
	message("새 횃불을 켰습니다. 밝기 %d" % light)
	return true

func camp() -> bool:
	if phase != "EXPLORE" or rooms[room].kind != "camp" or rooms[room].used: return false
	rooms[room].used = true; rooms[room].cleared = true; world_time += 100
	var helper: Dictionary = alive()[0]
	for actor in alive():
		if actor.profile.value("A") > helper.profile.value("A"): helper = actor
	for actor in alive():
		actor.hp = mini(actor.max_hp, actor.hp + 12)
		Body.heal(actor)
		stress(actor, -18 - helper.profile.value("A") / 100)
		if actor.id != helper.id:
			serial += 1
			actor.memory.remember("AID_RECEIVED", serial, world_time, helper.id + 1, helper.id + 1, 300)
	message("회복의 샘 · %s의 돌봄으로 체력과 스트레스를 회복했습니다." % helper.name)
	return true

func event_choice(search: bool) -> bool:
	if phase != "EXPLORE" or rooms[room].kind != "loot" or rooms[room].used: return false
	if not search: return false
	rooms[room].used = true; rooms[room].cleared = true
	if search:
		loot += 30
		var actor: Dictionary = party[selected] if party[selected].hp > 0 else alive()[0]
		var hazard := Hexaco.sample(seed_value, expedition_number * 10 + room, "curio", 100)
		if hazard < 50:
			damage(actor, 8, 99, "PIERCE")
			message("%s이 유물을 회수했지만 함정에 다쳤습니다. 전리품 +30" % actor.name)
		else:
			stress(actor, -8)
			message("온전한 유물을 발견했습니다. 전리품 +30")
		for member in alive(): stress(member, 4)
	phase = "EXPLORE" if not alive().is_empty() else "DEFEAT"
	return true

func interact_room(point: Vector2i) -> bool:
	if phase != "EXPLORE" or not inside(point): return false
	if doors().has(point): return travel(doors()[point])
	if point != rooms[room].feature:
		var actor: Dictionary = party[selected]
		if actor.hp <= 0 or not is_free(point): return false
		var route := TurnCore.path(8,8,actor.pos,[point],
			func(a,b): return distance(a,b) == 1 and is_free(b),func(_p): return 100)
		if not route.found: return false
		actor.pos = point
		return true
	if rooms[room].kind == "camp": return camp()
	if rooms[room].kind == "loot": return event_choice(true)
	return false

func start_battle() -> void:
	phase = "BATTLE"; round_number = 1
	for actor in party: actor.ap = action_budget(actor); actor["guarded"] = false
	if not rooms[room].started:
		rooms[room].started = true
		for i in range(3 if rooms[room].kind == "boss" else 2):
			var enemy := make_actor(100 + expedition_number * 100 + room * 10 + i, "수문장" if i == 2 else "망령", true)
			enemy.pos = Vector2i(6, 2 + i * 2)
			# Entering through the east door must not overlap enemy spawns.
			if party.any(func(a): return a.hp > 0 and a.pos == enemy.pos): enemy.pos.x = 5
			if i == 2: enemy.hp = 44; enemy.max_hp = 44
			enemies.append(enemy)
	selected = party.find(alive()[0])
	plan_enemies()
	message("%s · 붉은 칸은 적의 다음 공격 위치입니다." % rooms[room].name)

func action_budget(actor: Dictionary) -> int:
	return 1 if actor.stress >= 150 else 2

func tile(point: Vector2i) -> Dictionary:
	return tiles[point.y * 8 + point.x]

func inside(point: Vector2i) -> bool:
	return point.x >= 0 and point.y >= 0 and point.x < 8 and point.y < 8

func at(point: Vector2i) -> Dictionary:
	for actor in party + enemies:
		if actor.hp > 0 and actor.pos == point: return actor
	return {}

func is_free(point: Vector2i) -> bool:
	return inside(point) and tile(point).terrain != "wall" and at(point).is_empty()

func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func act(kind: String, target: Vector2i) -> bool:
	if phase != "BATTLE" or not inside(target): return false
	var actor: Dictionary = party[selected]
	if actor.hp <= 0 or actor.ap <= 0: return false
	var victim := at(target)
	match kind:
		"GUARD", "WAIT":
			if target != actor.pos: return false
			if kind == "GUARD": actor["guarded"] = true
		"MOVE":
			var move_range := 2 if actor.move_factor == 100 else 1
			var path := TurnCore.path(8, 8, actor.pos, [target],
				func(origin, point): return distance(origin, point) == 1 and is_free(point),
				func(_point): return 100, 100, move_range)
			if not path.found or target == actor.pos: return false
			actor.pos = target
		"ATTACK", "PUSH":
			if victim.is_empty() or not victim.enemy or distance(actor.pos, target) != 1: return false
			if kind == "ATTACK":
				var hit := TurnCore.physical(18 * actor.attack_factor / 100, 1000, 0, 2)
				damage(victim, int(hit.damage), actor.id, "SLASH")
			else:
				var destination: Vector2i = target + (target - actor.pos)
				if is_free(destination): victim.pos = destination
				else: damage(victim, 8, actor.id, "IMPACT")
				intents = intents.filter(func(intent): return intent.id != victim.id)
				message("밀쳐내기 · 적의 예고 공격을 취소했습니다.")
		"FIRE", "WATER", "ELECTRIC":
			if distance(actor.pos, target) > 4 or tile(target).terrain == "wall": return false
			if not preload("res://sim/combat_kernel.gd").sees(actor.pos, target,
				func(p): return tile(p).terrain == "wall"): return false
			if kind == "FIRE":
				if tile(target).terrain != "wood": return false
				tile(target).fire = mini(100, tile(target).fire + 35)
			elif kind == "WATER": tile(target).wet = mini(100, tile(target).wet + 70)
			else: discharge(target, actor.id)
		_: return false
	actor.ap -= 1
	check_battle_end()
	return true

func discharge(origin: Vector2i, source: int) -> void:
	var queue: Array = [{"pos":origin, "power":18}]
	var seen: Array = [origin]
	while not queue.is_empty():
		var row: Dictionary = queue.pop_front()
		var victim := at(row.pos)
		if not victim.is_empty(): damage(victim, row.power, source, "ELECTRIC")
		if row.power <= 6 or not conductive(row.pos): continue
		for direction in DIRECTIONS:
			var next: Vector2i = row.pos + direction
			if inside(next) and next not in seen and conductive(next):
				seen.append(next); queue.append({"pos":next, "power":row.power - 6})
	message("방전 · 젖은 칸과 금속을 따라 전류가 흐릅니다. 아군도 피해를 받습니다.")

func conductive(point: Vector2i) -> bool:
	return tile(point).terrain in ["metal", "water"] or tile(point).wet >= 25

func damage(target: Dictionary, amount: int, source: int, form: String) -> void:
	if target.hp <= 0: return
	if target.get("guarded",false): amount = maxi(1,amount / 2)
	serial += 1
	var lost := mini(int(target.hp), amount)
	var key := ("%d/%d/%d" % [seed_value, serial, target.id]).sha256_text()
	var plan := Injury.assess_hp_loss(target.body, form, lost, target.max_hp, key, target.id + 1)
	Injury._apply_plan(target.body, plan, serial)
	target.hp -= lost; Body.sync(target)
	if not target.enemy:
		target.memory.remember("SELF_HARM", serial, world_time, source + 1, source + 1, mini(1000, 180 + lost * 18))
		stress(target, 5 + lost / 2)
		if target.hp <= 0:
			for ally in alive():
				ally.memory.remember("ALLY_LOST", serial, world_time, target.id + 1, source + 1, 800)
				stress(ally, 22)
	message("%s · %d 피해%s" % [target.name, lost, " · 사망" if target.hp <= 0 else ""])

func plan_enemies() -> void:
	intents.clear()
	for enemy in enemies:
		if enemy.hp <= 0 or alive().is_empty(): continue
		var targets := alive()
		targets.sort_custom(func(a,b): return distance(enemy.pos,a.pos) < distance(enemy.pos,b.pos))
		var target: Dictionary = targets[0]
		# Cell-locked ranged intent; moving off the marked cell always dodges it.
		intents.append({"id":enemy.id, "cell":target.pos, "damage":10 if enemy.name == "수문장" else 7})

func end_round() -> bool:
	if phase != "BATTLE": return false
	world_time += 100
	for intent in intents:
		var victim := at(intent.cell)
		if not victim.is_empty(): damage(victim, intent.damage, intent.id, "IMPACT")
	for y in range(8):
		for x in range(8):
			var point := Vector2i(x,y)
			var cell := tile(point)
			var result := ElementRules.project_existing_fire_tick(cell.fire, cell.wet, 0, world_time)
			cell.fire = result.fire_after_decay
			cell.wet = maxi(0, result.wetness_after_suppression - ElementRules.WETNESS_DECAY_PER_ENVIRONMENT_TICK)
			var victim := at(point)
			if not victim.is_empty() and result.known_damage > 0: damage(victim, result.known_damage, 999, "FIRE")
	check_battle_end()
	if phase != "BATTLE": return true
	for enemy in enemies:
		if enemy.hp <= 0: continue
		var nearest: Dictionary = alive()[0]
		for actor in alive():
			if distance(enemy.pos, actor.pos) < distance(enemy.pos, nearest.pos): nearest = actor
		var goals: Array = []
		for direction in DIRECTIONS:
			var point: Vector2i = nearest.pos + direction
			if is_free(point): goals.append(point)
		if not goals.is_empty() and distance(enemy.pos, nearest.pos) > 1:
			var route := TurnCore.path(8,8,enemy.pos,goals,
				func(origin,point): return distance(origin,point) == 1 and is_free(point), func(_p): return 100)
			if route.found and route.path.size() > 1: enemy.pos = route.path[1]
	for actor in alive():
		actor["guarded"] = false
		stress(actor, 2 if light >= 35 else 5)
		actor.ap = action_budget(actor)
	round_number += 1
	plan_enemies()
	return true

func check_battle_end() -> void:
	if phase != "BATTLE": return
	if alive().is_empty():
		phase = "DEFEAT"; loot = 0; message("원정대가 전멸했습니다.")
	elif enemies.all(func(a): return a.hp <= 0):
		loot += 35 if rooms[room].kind != "boss" else 100
		rooms[room].cleared = true
		phase = "EXPLORE"; intents.clear()
		for actor in alive(): stress(actor, -7)
		message("전투 승리 · 전리품 %d. 부상과 기억을 안고 탐험을 계속합니다." % loot)

func retreat() -> bool:
	if phase not in ["EXPLORE", "EVENT", "BATTLE"]: return false
	var penalty := phase == "BATTLE"
	if penalty:
		loot /= 2
		for actor in alive(): stress(actor, 15)
	bank += loot
	message("귀환 · 전리품 %d 정산%s. 누적 자금 %d" % [loot, " (전투 철수 50% 손실)" if penalty else "", bank])
	loot = 0; phase = "TOWN"; intents = []; enemies = []; tiles = []
	return true

func rest_town() -> bool:
	if phase != "TOWN" or bank < 20 or alive().is_empty(): return false
	bank -= 20
	for actor in alive():
		stress(actor, -40); actor.hp = mini(actor.max_hp, actor.hp + 20); Body.heal(actor)
	message("요양 · 자금 20 소비. 기억과 부위 손상은 유지됩니다.")
	return true

func use_supply(slot: int, target: Vector2i = Vector2i(-1,-1)) -> bool:
	if phase not in ["EXPLORE","BATTLE"] or slot < 0 or slot >= supplies.size() or supplies[slot] <= 0: return false
	var actor: Dictionary = party[selected]
	if actor.hp <= 0 or phase == "BATTLE" and actor.ap <= 0: return false
	if slot in [3,4]:
		if not act("FIRE" if slot == 3 else "WATER",target): return false
	else:
		if slot in [0,5] and actor.hp >= actor.max_hp: return false
		if slot == 1 and actor.stress == 0: return false
		if slot == 2 and hunger == 0 and actor.stress == 0: return false
		match slot:
			0,5:
				actor.hp = mini(actor.max_hp,actor.hp + (20 if slot == 0 else 10)); Body.heal(actor)
			1: stress(actor,-25)
			2: hunger = maxi(0,hunger-30); stress(actor,-10)
		if phase == "BATTLE": actor.ap -= 1
	supplies[slot] -= 1
	message("%s · %s 사용" % [actor.name,SUPPLY_NAMES[slot]])
	return true
