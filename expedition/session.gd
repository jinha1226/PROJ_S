extends RefCounted
## Expedition host: persistent actors; room-local terrain, enemies and intent.
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
const Memory = preload("res://sim/party_memory_state.gd")
const Body = preload("res://game/rebuilt/body_bridge.gd")
const TurnCore = preload("res://sim/turn_engine.gd")
const ElementRules = preload("res://sim/environment_rules.gd")
const Injury = preload("res://sim/body_injury_system.gd")
const DIRECTIONS = [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]
const ROOMS = [
	{"name":"폐허 입구", "kind":"entry", "next":[1,2]},
	{"name":"불탄 병영", "kind":"battle", "next":[3]},
	{"name":"잊힌 납골당", "kind":"curio", "next":[3]},
	{"name":"꺼진 야영지", "kind":"camp", "next":[4,5]},
	{"name":"침수된 무기고", "kind":"battle", "next":[6]},
	{"name":"희생의 제단", "kind":"curio", "next":[6]},
	{"name":"수문장의 방", "kind":"boss", "next":[]},
]
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
var used_camp := false
var intents: Array = []

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
	food = 9; torches = 3; light = 90; loot = 0
	room = 0; visited = [0]; used_camp = false
	phase = "EXPLORE"; enemies.clear(); intents.clear(); tiles.clear()
	message("원정 %d · 폐허의 수문장을 처치하고 귀환하세요." % expedition_number)
	return true

func travel(destination: int) -> bool:
	if phase != "EXPLORE" or destination not in ROOMS[room].next: return false
	world_time += 100
	light = maxi(0, light - 18)
	var required := alive().size()
	var hungry := food < required
	food = maxi(0, food - required)
	for actor in alive(): stress(actor, (12 if hungry else 3) + (9 if light < 35 else 0))
	room = destination; visited.append(room); used_camp = false
	message("복도 통과 · 식량 -%d / 횃불 밝기 %d%s" % [required, light, " · 굶주림" if hungry else ""])
	match ROOMS[room].kind:
		"battle", "boss": start_battle()
		"curio": phase = "EVENT"
		_: phase = "EXPLORE"
	return true

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
	if phase != "EXPLORE" or ROOMS[room].kind != "camp" or used_camp or food < alive().size(): return false
	food -= alive().size(); used_camp = true; world_time += 100
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
	message("%s의 돌봄 · 체력과 혈액 회복, 스트레스 감소. 부위 손상은 남습니다." % helper.name)
	return true

func event_choice(search: bool) -> bool:
	if phase != "EVENT": return false
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
	else: message("유물에 손대지 않고 지나갑니다.")
	phase = "EXPLORE" if not alive().is_empty() else "DEFEAT"
	return true

func start_battle() -> void:
	phase = "BATTLE"; round_number = 1; enemies.clear(); intents.clear(); tiles.clear()
	for y in range(8):
		for x in range(8):
			var terrain := "stone"
			if y == 3: terrain = "wood"
			if x == 5: terrain = "water" if room == 4 else "metal"
			if Vector2i(x,y) in [Vector2i(3,2), Vector2i(3,5)]: terrain = "wall"
			tiles.append({"terrain":terrain, "fire":0, "wet":70 if terrain == "water" else 0})
	for i in range(party.size()):
		party[i].pos = Vector2i(1, 2 + i)
		party[i].ap = action_budget(party[i])
	for i in range(3 if ROOMS[room].kind == "boss" else 2):
		var enemy := make_actor(100 + room * 10 + i, "수문장" if i == 2 else "망령", true)
		enemy.pos = Vector2i(6, 2 + i * 2)
		if i == 2: enemy.hp = 44; enemy.max_hp = 44
		enemies.append(enemy)
	selected = party.find(alive()[0])
	plan_enemies()
	message("%s · 붉은 칸은 적의 다음 공격 위치입니다." % ROOMS[room].name)

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
		loot += 35 if ROOMS[room].kind != "boss" else 100
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
	loot = 0; phase = "TOWN"; intents.clear(); enemies.clear(); tiles.clear()
	return true

func rest_town() -> bool:
	if phase != "TOWN" or bank < 20 or alive().is_empty(): return false
	bank -= 20
	for actor in alive():
		stress(actor, -40); actor.hp = mini(actor.max_hp, actor.hp + 20); Body.heal(actor)
	message("요양 · 자금 20 소비. 기억과 부위 손상은 유지됩니다.")
	return true
