extends RefCounted
## Expedition host: persistent actors; room-local terrain, enemies and intent.
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
const Memory = preload("res://sim/party_memory_state.gd")
const Body = preload("res://game/rebuilt/body_bridge.gd")
const TurnCore = preload("res://sim/turn_engine.gd")
const ElementRules = preload("res://sim/environment_rules.gd")
const Injury = preload("res://sim/body_injury_system.gd")
const Dungeon = preload("res://expedition/dungeon_map.gd")
var BOARD_SIDE := Dungeon.ROOM_SIDE
const Floor = preload("res://expedition/continuous_floor.gd")
var floor_mode := false
var floor_state
const BossTrial = preload("res://expedition/boss_trial.gd")
var boss_trial := false
const Tactics = preload("res://expedition/tactical_action_selector.gd")
const Rules = preload("res://expedition/tactic_rules.gd")
const Abilities = preload("res://expedition/abilities.gd")
const Growth = preload("res://expedition/growth.gd")
var essences: Dictionary = {}
var party_command := "FOLLOW"
var formation := "NONE"
var command_target := -1
var companions := false
var resolving_companions := false
const CARDINALS = [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]
const DIRECTIONS = [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN, Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]
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
var effects: Array = []
var hunger := 0
var supplies: Array = [2,2,1,1,1,3]
const Curios = preload("res://expedition/curios.gd")
var exploration_tools: Dictionary = {"KEY":2,"SHOVEL":2}
const Objective = preload("res://expedition/expedition_objective.gd")
## Continuous-floor expedition lifecycle. objective/result are per expedition;
## snapshot holds the persistent state restored on defeat.
var objective: Dictionary = {}
var snapshot: Dictionary = {}
var result: Dictionary = {}
const SUPPLY_NAMES = ["치유 물약","정신 안정제","활력 물약","화염 두루마리","물 두루마리","붕대"]
## Town provisioning for the continuous floor: funds buy the kit, the minimum
## is granted in town; remaining paid/found goods cash out on a safe return.
const STARTING_FUNDS := 45
const MIN_KIT := {"food":12,"torches":2,"supplies":[1,0,0,0,0,1],"tools":{"KEY":1,"SHOVEL":1}}
const SHOP = [{"id":"food","name":"식량","price":1},{"id":"torch","name":"횃불","price":4},
	{"id":"supply:0","name":"치유 물약","price":8},{"id":"supply:1","name":"정신 안정제","price":6},{"id":"supply:2","name":"활력 물약","price":6},
	{"id":"supply:3","name":"화염 두루마리","price":5},{"id":"supply:4","name":"물 두루마리","price":4},{"id":"supply:5","name":"붕대","price":3},
	{"id":"tool:KEY","name":"열쇠","price":6},{"id":"tool:SHOVEL","name":"삽","price":5}]
var purchases: Dictionary = {}
const PROVISION_SELL_PERCENT := 10
const ABANDON_STRESS := 20
## Free provisions are consumed first and never sold for gold.
var free_provisions: Dictionary = {}

## Experiment rules: the defaults reproduce shipped behaviour byte for byte.
const DEFAULT_RULES := {"solo_actions":1,"solo_max_members":0}
var rules_config: Dictionary = DEFAULT_RULES.duplicate()

func _init(p_seed: int = 731, p_boss_trial: bool = false, p_companions: bool = false, p_floor: bool = false, p_party_size: int = 0) -> void:
	seed_value = p_seed
	boss_trial = p_boss_trial
	companions = (p_party_size > 1) if p_party_size > 0 else (p_companions and boss_trial)
	floor_mode = p_floor
	if floor_mode:
		floor_state = Floor.new(); BOARD_SIDE = floor_state.size
		bank = STARTING_FUNDS; food = 0; torches = 0; supplies = [0,0,0,0,0,0]; exploration_tools = {"KEY":0,"SHOVEL":0}
		top_up_kit()
	var count: int = clampi(p_party_size,1,3) if p_party_size > 0 else (2 if companions else 1 if boss_trial else 3)
	for i in range(count):
		party.append(make_actor(i, ["아린", "브란", "세라"][i], false))
	message("부상과 기억은 원정을 마쳐도 남습니다. 준비되면 출정하세요.")

func make_actor(id: int, actor_name: String, enemy: bool) -> Dictionary:
	var actor := {"id":id, "name":actor_name, "enemy":enemy,
		"tactics":{"PUSH":"PROTECT","GUARD":"LOW_HP"},"priority":"PUSH","last_action":"대기",
		"rules":Rules.defaults(),
		"basic_target":Rules.BASIC_TARGET_DEFAULT,
		"reservation":{},
		"learned_abilities":["PUSH","GUARD"],"equipped_abilities":["PUSH","GUARD"],"cooldowns":{},"iron_guard":false,
		"growth":Growth.create(),
		"pos":Vector2i.ZERO, "hp":28 if enemy else 55, "max_hp":28 if enemy else 55,
		"stress":0, "condition":"평온", "ap":2,
		"body":Body.create(id, seed_value, enemy),
		"profile":Hexaco.generated(seed_value, id + 1), "memory":Memory.new()}
	Body.sync(actor)
	return actor

func message(value: String) -> void:
	log_lines.append(value)

## Persistent memories are landmarks, not a transcript of ordinary hits.
func remember_important(actor: Dictionary, kind: String, subject: int, instigator: int, salience: int) -> void:
	actor.memory.records = actor.memory.records.filter(func(record): return int(record.salience) >= 700)
	var key := "%d/%s" % [expedition_number,kind]
	if kind != "SELF_HARM": key += "/%d" % subject
	var recorded: Dictionary = actor.get("important_memories",{})
	if recorded.has(key): return
	if actor.memory.remember(kind,serial,world_time,subject,instigator,salience):
		recorded[key] = true; actor.important_memories = recorded

func alive() -> Array:
	return party.filter(func(a): return a.hp > 0)

func depart() -> bool:
	if phase != "TOWN" or alive().is_empty(): return false
	for actor in party:
		actor.memory.records = actor.memory.records.filter(func(record): return int(record.salience) >= 700)
		actor.important_memories = {}
	expedition_number += 1
	light = 90; loot = 0; hunger = 0
	if floor_mode:
		purchases = {}
		result = {}; objective = {}
		snapshot = take_snapshot()
		floor_state.build(self); message("1층 진입"); return true
	food = 27; torches = 5
	supplies = [2,2,1,1,1,3]
	exploration_tools = {"KEY":2,"SHOVEL":2}
	rooms = Dungeon.generate(seed_value + expedition_number * 7919)
	if boss_trial: BossTrial.prepare(self)
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
	if previous == room + 1: spawn = Vector2i(BOARD_SIDE-2,2)
	elif previous == room - 3: spawn = Vector2i(1,1)
	elif previous == room + 3: spawn = Vector2i(1,BOARD_SIDE-2)
	for i in range(party.size()):
		party[i].pos = spawn + (Vector2i(i,0) if previous in [room-3,room+3] else Vector2i(0,i))
	if row.kind in ["battle","boss"] and not row.cleared: start_battle()

func doors() -> Dictionary:
	var result: Dictionary = {}
	if floor_mode: return result
	if rooms.is_empty(): return result
	for destination in rooms[room].links:
		var delta: int = destination - room
		var point: Vector2i = {1:Vector2i(BOARD_SIDE-1,4),-1:Vector2i(0,4),3:Vector2i(4,BOARD_SIDE-1),-3:Vector2i(4,0)}[delta]
		result[point] = destination
	return result

func stress(actor: Dictionary, amount: int) -> void:
	var trauma := int(actor.memory.strongest(["SELF_HARM", "ALLY_LOST"]).get("salience", 0)) / 200
	var change := amount
	if amount > 0: change = maxi(1, amount * (650 + actor.profile.value("E")) / 1000 + trauma)
	if amount > 0 and floor_mode and party.size() == 1: change = ceili(change*0.5)
	actor.stress = clampi(actor.stress + change, 0, 200)
	actor.condition = "붕괴" if actor.stress >= 150 else "불안" if actor.stress >= 100 else "평온"

func use_torch() -> bool:
	if (phase not in ["EXPLORE", "EVENT"] and not (floor_mode and phase == "BATTLE" and safe_management())) or torches <= 0 or light >= 100: return false
	add_stock("torch",-1); light = mini(100, light + 50)
	if floor_mode: floor_state.observe(self)
	message("새 횃불을 켰습니다. 밝기 %d" % light)
	return true

func use_food() -> bool:
	if phase != "BATTLE" or food <= 0 or alive().is_empty(): return false
	var actor: Dictionary = party[selected]
	if actor.hp <= 0 or (actor.hp >= actor.max_hp and hunger == 0): return false
	add_stock("food",-1); hunger = maxi(0,hunger-20)
	actor.hp = mini(actor.max_hp,actor.hp+5)
	message("식량 -1 · 체력 회복")
	return true

func rest_field() -> bool:
	if not floor_mode or phase != "BATTLE" or not safe_management() or food <= 0 or party[selected].ap <= 0: return false
	var actor: Dictionary = party[selected]
	if actor.hp >= actor.max_hp and actor.stress == 0 and hunger == 0: return false
	add_stock("food",-1); hunger = maxi(0,hunger-20)
	actor.hp = mini(actor.max_hp,actor.hp+10); stress(actor,-10)
	message("휴식 · 식량 -1")
	return act("WAIT",actor.pos)

func camp() -> bool:
	if phase != "EXPLORE" or rooms[room].kind != "camp" or rooms[room].used: return false
	rooms[room].used = true; rooms[room].cleared = true; world_time += 100
	var helper: Dictionary = alive()[0]
	for actor in alive():
		if actor.profile.value("A") > helper.profile.value("A"): helper = actor
	for actor in alive():
		var in_crisis: bool = actor.hp*4 <= actor.max_hp or actor.stress >= 100
		actor.hp = mini(actor.max_hp, actor.hp + 12)
		Body.heal(actor)
		stress(actor, -18 - helper.profile.value("A") / 100)
		if actor.id != helper.id and in_crisis:
			serial += 1
			remember_important(actor,"AID_RECEIVED",helper.id+1,helper.id+1,750)
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
		var route := TurnCore.path(BOARD_SIDE,BOARD_SIDE,actor.pos,[point],
			func(a,b): return can_step(a,b),func(_p): return 100)
		if not route.found: return false
		actor.pos = point
		return true
	if rooms[room].kind == "camp": return camp()
	if rooms[room].kind == "loot": return event_choice(true)
	return false

func start_battle() -> void:
	phase = "BATTLE"; round_number = 1
	for actor in party: actor.reservation = {}
	for actor in party: actor.ap = action_budget(actor); actor["guarded"] = false
	if boss_trial:
		BossTrial.spawn(self); selected = 0; plan_enemies()
		message(rooms[room].name+" · 전투 시작"); return
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
	message("%s · 적은 이동 후 공격합니다. 붉은 칸은 강력한 기술의 예고입니다." % rooms[room].name)

## Rule overrides only bite for a lone hero on the continuous floor.
func solo_rule(key: String) -> int:
	if not floor_mode or party.size() != 1: return int(DEFAULT_RULES[key])
	return int(rules_config.get(key,DEFAULT_RULES[key]))

func action_budget(actor: Dictionary) -> int:
	if boss_trial: return solo_rule("solo_actions")
	return 1 if actor.stress >= 150 else 2

func tile(point: Vector2i) -> Dictionary:
	return tiles[point.y * BOARD_SIDE + point.x]

func inside(point: Vector2i) -> bool:
	return point.x >= 0 and point.y >= 0 and point.x < BOARD_SIDE and point.y < BOARD_SIDE

func at(point: Vector2i) -> Dictionary:
	for actor in party + enemies:
		if actor.hp > 0 and actor.pos == point: return actor
	return {}

func is_free(point: Vector2i) -> bool:
	if boss_trial and rooms[room].shield and point == rooms[room].pylon: return false
	return inside(point) and tile(point).terrain != "wall" and at(point).is_empty()

func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func melee_reach(a: Vector2i, b: Vector2i) -> bool:
	if not inside(a) or not inside(b) or a == b or maxi(absi(a.x-b.x),absi(a.y-b.y)) != 1: return false
	if tile(b).terrain == "wall": return false
	if a.x != b.x and a.y != b.y:
		if tile(Vector2i(a.x,b.y)).terrain == "wall" or tile(Vector2i(b.x,a.y)).terrain == "wall": return false
	return true

func can_step(a: Vector2i, b: Vector2i) -> bool:
	return melee_reach(a,b) and is_free(b)

func combat_enemies() -> Array:
	return floor_state.threats(self) if floor_mode else enemies.filter(func(e): return e.hp > 0)

func safe_management() -> bool:
	return phase in ["TOWN","EXPLORE"] or floor_mode and phase == "BATTLE" and floor_state.safe(self)

func auto_attack() -> bool:
	if phase != "BATTLE": return false
	var actor: Dictionary = party[selected]
	if actor.hp <= 0 or actor.ap <= 0: return false
	var targets: Array = combat_enemies()
	targets.sort_custom(func(a,b):
		var av: int = a.hp if actor.basic_target == "LOWEST_HP" else distance(actor.pos,a.pos)
		var bv: int = b.hp if actor.basic_target == "LOWEST_HP" else distance(actor.pos,b.pos)
		return av < bv if av != bv else a.id < b.id)
	for enemy in targets:
		if not attack_preview(enemy.pos).is_empty(): return act("ATTACK",enemy.pos)
	var best: Array = []
	for enemy in targets:
		var goals: Array = []
		for direction in DIRECTIONS:
			var cell: Vector2i = enemy.pos+direction
			if is_free(cell) and melee_reach(cell,enemy.pos) and Tactics.danger(self,cell) == 0: goals.append(cell)
		var route := TurnCore.path(BOARD_SIDE,BOARD_SIDE,actor.pos,goals,func(a,b): return can_step(a,b) and Tactics.danger(self,b) == 0,func(_p): return 100)
		if route.found and route.path.size() > 1 and (best.is_empty() or route.path.size() < best.size()): best = route.path
	return act("MOVE",best[1]) if not best.is_empty() else false

func movement_cells(actor_index: int = -1) -> Array:
	var result: Array = []
	var actor: Dictionary = party[selected if actor_index < 0 else actor_index]
	if phase != "BATTLE" or actor.hp <= 0 or actor.ap <= 0: return result
	var frontier: Array = [actor.pos]
	var seen: Array = [actor.pos]
	for step in range(2 if not boss_trial and actor.move_factor == 100 else 1):
		var next: Array = []
		for point in frontier:
			for direction in DIRECTIONS:
				var cell: Vector2i = point + direction
				if cell not in seen and can_step(point,cell):
					seen.append(cell); result.append(cell); next.append(cell)
		frontier = next
	return result

func attack_cells(actor_index: int = -1) -> Array:
	var result: Array = []
	var actor: Dictionary = party[selected if actor_index < 0 else actor_index]
	if phase != "BATTLE" or actor.hp <= 0 or actor.ap <= 0: return result
	for direction in DIRECTIONS:
		var cell: Vector2i = actor.pos + direction
		if melee_reach(actor.pos,cell): result.append(cell)
	return result

func attack_preview(target: Vector2i, actor_index: int = -1) -> Dictionary:
	if target not in attack_cells(actor_index): return {}
	var victim := at(target)
	if victim.is_empty() or not victim.enemy: return {}
	var actor: Dictionary = party[selected if actor_index < 0 else actor_index]
	var hit := TurnCore.physical(Growth.power(actor,"MELEE",18) * actor.attack_factor / 100, 1000, 0, 2)
	var amount := int(hit.damage)
	if victim.get("guarded",false): amount = maxi(1,amount / 2)
	if boss_trial and rooms[room].shield: amount = 0
	# Basic attacks currently have no miss roll; do not advertise a fictitious chance.
	return {"actor":actor.id,"target":victim.id,"cell":target,"name":victim.name,"chance":100,"damage":amount}

func act(kind: String, target: Vector2i) -> bool:
	if phase != "BATTLE" or not inside(target): return false
	if floor_mode and not floor_state.visible.has(target): return false
	if boss_trial and kind == "PYLON":
		if not BossTrial.disable_pylon(self,target): return false
		finish_player_action(); return true
	var actor: Dictionary = party[selected]
	if actor.hp <= 0 or actor.ap <= 0: return false
	if companions and kind in Abilities.STARTERS and kind not in actor.equipped_abilities: return false
	if Abilities.DEFINITIONS.has(kind):
		if not Abilities.execute(self,actor,kind,target): return false
		actor.ap -= 1; check_battle_end(); finish_player_action(); return true
	var victim := at(target)
	match kind:
		"GUARD", "WAIT":
			if target != actor.pos: return false
			if kind == "GUARD": actor["guarded"] = true
		"MOVE":
			if target not in movement_cells(): return false
			actor.pos = target
		"ATTACK", "PUSH":
			if victim.is_empty() or not victim.enemy or not melee_reach(actor.pos,target): return false
			if kind == "ATTACK":
				var hit := TurnCore.physical(Growth.power(actor,"MELEE",18) * actor.attack_factor / 100, 1000, 0, 2)
				damage(victim, int(hit.damage), actor.id, "SLASH")
			else:
				var destination: Vector2i = target + (target - actor.pos)
				if can_step(target,destination): victim.pos = destination
				else: damage(victim, Growth.power(actor,"MELEE",8), actor.id, "IMPACT")
				intents = intents.filter(func(intent): return intent.id != victim.id)
				if floor_mode: Floor.MonsterAI.interrupt(self,victim)
				elif boss_trial and victim.get("charging",false):
					victim.charging = false; victim.fuse = 0; victim.cooldown = 6; victim.recovery = 1
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
	finish_player_action()
	return true

func finish_player_action() -> void:
	if not boss_trial or phase != "BATTLE" or resolving_companions: return
	if floor_mode: floor_state.observe(self); floor_state.ambush(self)
	if phase != "BATTLE": return
	var leader := selected
	resolving_companions = true
	if companions:
		for i in range(party.size()):
			if i == leader or party[i].hp <= 0 or phase != "BATTLE": continue
			selected = i
			var choice: Dictionary = companion_choice(party[i])
			party[i].reservation = {}
			if act(choice.kind,choice.cell): party[i].last_action = choice.reason
	selected = leader
	resolving_companions = false
	if phase == "BATTLE" and party[selected].ap <= 0: end_round()

func reservation_choice(actor: Dictionary) -> Dictionary:
	var order: Dictionary = actor.reservation
	if order.is_empty() or actor.hp <= 0 or actor.ap <= 0 or phase != "BATTLE": return {}
	var cell: Vector2i = order.cell
	if order.kind in Abilities.STARTERS and order.kind not in actor.equipped_abilities: return {}
	if order.kind in ["ATTACK","PUSH","BOMB"]:
		var target: Dictionary = {}
		for enemy in enemies:
			if enemy.id == order.target_id and enemy.hp > 0: target = enemy; break
		if target.is_empty(): return {}
		if order.kind == "BOMB":
			if not Abilities.legal(self,actor,order.kind,target.pos): return {}
		elif attack_preview(target.pos,actor.id).is_empty(): return {}
		cell = target.pos
	elif order.kind == "MOVE":
		if cell not in movement_cells(actor.id): return {}
	elif order.kind in ["GUARD","WAIT"]: cell = actor.pos
	elif Abilities.DEFINITIONS.has(order.kind):
		cell = actor.pos
		if not Abilities.legal(self,actor,order.kind,cell): return {}
	else: return {}
	return {"kind":order.kind,"cell":cell,"reason":"직접 예약","reserved":true}

func reserve_action(index: int, kind: String, cell: Vector2i) -> bool:
	if not companions or phase != "BATTLE" or index < 0 or index >= party.size() or index == selected: return false
	var actor: Dictionary = party[index]
	var previous: Dictionary = actor.reservation
	actor.reservation = {"kind":kind,"cell":cell,"target_id":at(cell).get("id",-1)}
	if reservation_choice(actor).is_empty(): actor.reservation = previous; return false
	return true

func cancel_reservation(index: int) -> void:
	if index >= 0 and index < party.size(): party[index].reservation = {}

func companion_choice(actor: Dictionary) -> Dictionary:
	var reserved := reservation_choice(actor)
	if reserved.is_empty() and companions:
		if party_command == "HOLD_POSITION": return {"kind":"WAIT","cell":actor.pos,"reason":"자리 지키기"}
		if party_command == "STOP_ATTACK": return floor_state.follow(self,actor) if floor_mode else {"kind":"WAIT","cell":actor.pos,"reason":"공격 중지"}
		if party_command == "RETREAT":
			var threats: Array = combat_enemies()
			var best: Vector2i = actor.pos
			var score := -1
			for direction in DIRECTIONS:
				var cell: Vector2i = actor.pos+direction
				if not can_step(actor.pos,cell) or not is_free(cell): continue
				var nearest := 999
				for enemy in threats: nearest = mini(nearest,distance(cell,enemy.pos))
				if nearest > score: score = nearest; best = cell
			return {"kind":"WAIT" if best == actor.pos else "MOVE","cell":best,"reason":"후퇴"}
		if party_command == "ATTACK_TARGET":
			for enemy in combat_enemies():
				if enemy.id != command_target: continue
				if melee_reach(actor.pos,enemy.pos): return {"kind":"ATTACK","cell":enemy.pos,"reason":"집중 공격"}
				var goals: Array = []
				for direction in DIRECTIONS:
					if is_free(enemy.pos+direction) and melee_reach(enemy.pos+direction,enemy.pos): goals.append(enemy.pos+direction)
				var route: Dictionary = TurnCore.path(BOARD_SIDE,BOARD_SIDE,actor.pos,goals,func(a,b): return can_step(a,b) and Tactics.danger(self,b) == 0,func(_p): return 100)
				return {"kind":"MOVE","cell":route.path[1],"reason":"집중 공격 접근"} if route.found and route.path.size() > 1 else {"kind":"WAIT","cell":actor.pos,"reason":"대상 경로 없음"}
	if reserved.is_empty() and floor_mode and floor_state.safe(self): return floor_state.follow(self,actor)
	return Tactics.choose(self,actor) if reserved.is_empty() else reserved

func companion_previews() -> Array:
	var previews: Array = []
	if not companions or phase != "BATTLE": return previews
	for actor in party:
		if actor.id == selected or actor.hp <= 0 or actor.ap <= 0: continue
		var choice: Dictionary = companion_choice(actor).duplicate(true)
		choice.actor = actor.id
		previews.append(choice)
	return previews

func set_tactic(index: int, skill: String, policy: String) -> bool:
	if index < 0 or index >= party.size(): return false
	var allowed: Array = ["PROTECT","OFFENSE","MANUAL"] if skill == "PUSH" else ["DANGER","LOW_HP","MANUAL"] if skill == "GUARD" else []
	if policy not in allowed: return false
	party[index].tactics[skill] = policy
	# Compatibility for previous callers; the live editor uses common rules.
	for rule in party[index].rules:
		if rule.skill == skill:
			rule.enabled = policy != "MANUAL"
			rule.when = "CHARGING" if policy == "PROTECT" else "HP" if policy == "LOW_HP" else "DANGER" if policy == "DANGER" else "ALWAYS"
			rule.subject = "SELF"
	return true

func set_basic_target(index: int, target: String) -> bool:
	if index < 0 or index >= party.size() or target not in Rules.BASIC_TARGETS: return false
	party[index].basic_target = target
	return true

func update_rule(index: int, position: int, field: String, value: Variant) -> bool:
	if index < 0 or index >= party.size() or position < 0 or position >= party[index].rules.size(): return false
	if field not in ["enabled","target","when","subject","threshold","comparison","status"]: return false
	var updated: Dictionary = party[index].rules[position].duplicate(true)
	updated[field] = value
	if not Rules.valid(updated): return false
	party[index].rules[position] = updated
	return true

func reorder_rule(index: int, position: int, direction: int) -> bool:
	if index < 0 or index >= party.size() or direction not in [-1,1]: return false
	var rows: Array = party[index].rules
	var destination := position+direction
	if position < 0 or position >= rows.size() or destination < 0 or destination >= rows.size(): return false
	var rule = rows[position]; rows[position] = rows[destination]; rows[destination] = rule
	return true

func discharge(origin: Vector2i, source: int) -> void:
	var queue: Array = [{"pos":origin, "power":18}]
	var seen: Array = [origin]
	while not queue.is_empty():
		var row: Dictionary = queue.pop_front()
		var victim := at(row.pos)
		if not victim.is_empty(): damage(victim, row.power, source, "ELECTRIC")
		if row.power <= 6 or not conductive(row.pos): continue
		for direction in CARDINALS:
			var next: Vector2i = row.pos + direction
			if inside(next) and next not in seen and conductive(next):
				seen.append(next); queue.append({"pos":next, "power":row.power - 6})
	message("방전 · 젖은 칸과 금속을 따라 전류가 흐릅니다. 아군도 피해를 받습니다.")

func conductive(point: Vector2i) -> bool:
	return tile(point).terrain in ["metal", "water"] or tile(point).wet >= 25

func roll_essence(enemy: Dictionary) -> void:
	if not enemy.enemy or enemy.hp > 0 or enemy.get("essence_rolled",false): return
	enemy.essence_rolled = true
	for actor in alive():
		if Growth.gain(actor,100 if boss_trial and not floor_mode else 25) > 0: message(actor.name+" · 레벨 %d! 숙련 포인트 획득" % actor.growth.level)
	var id: String = enemy.get("essence_id","")
	if not Abilities.DEFINITIONS.has(id): return
	var chance: int = Floor.drop_percent(light) if floor_mode else Abilities.DROP_PERCENT
	if Hexaco.sample(seed_value,expedition_number*10000+room*100+enemy.id,"essence",100) >= chance: return
	essences[id] = int(essences.get(id,0))+1
	message("이능 전리품 · "+Abilities.DEFINITIONS[id].item+" → 공용 가방")

func spend_growth(index: int, id: String, stat: bool = false) -> bool:
	if not safe_management() or index < 0 or index >= party.size() or party[index].hp <= 0: return false
	return Growth.spend(party[index],id,stat)

func reset_rules(index: int) -> void:
	var actor: Dictionary = party[index]
	actor.rules = Rules.defaults(); actor.basic_target = Rules.BASIC_TARGET_DEFAULT
	for id in actor.learned_abilities:
		if Abilities.DEFINITIONS.has(id): actor.rules.append(Rules.make_rule(id,"SELF" if Abilities.DEFINITIONS[id].target == "SELF" else "NEAREST","DANGER" if id == "IRON_HIDE" else "ALWAYS"))

func consume_essence(index: int, id: String) -> bool:
	if not safe_management() or index < 0 or index >= party.size() or not Abilities.DEFINITIONS.has(id): return false
	var actor: Dictionary = party[index]
	if actor.hp <= 0 or essences.get(id,0) <= 0 or id in actor.learned_abilities: return false
	actor.learned_abilities.append(id); essences[id] -= 1
	actor.rules.append(Rules.make_rule(id,"SELF" if Abilities.DEFINITIONS[id].target == "SELF" else "NEAREST","DANGER" if id == "IRON_HIDE" else "ALWAYS"))
	message(actor.name+" · "+Abilities.DEFINITIONS[id].name+" 습득! 이능 탭에서 장착하세요.")
	return true

func equip_ability(index: int, slot: int, id: String) -> bool:
	if not safe_management() or index < 0 or index >= party.size() or party[index].hp <= 0: return false
	return Abilities.equip(party[index],slot,id)

func enemy_attack_effect(enemy: Dictionary, cells: Array, area: bool = false) -> void:
	if cells.is_empty(): return
	effects.append({"kind":"ENEMY_ATTACK","from":enemy.pos,"cell":cells[0],
		"cells":cells.duplicate(),"area":area,"amount":0,"form":"IMPACT"})
	if effects.size() > 32: effects.pop_front()

static func subject_name(value: String) -> String:
	var last := value.unicode_at(value.length()-1) if not value.is_empty() else 0
	return value+("이" if last >= 0xAC00 and last <= 0xD7A3 and (last-0xAC00)%28 != 0 else "가")

func damage(target: Dictionary, amount: int, source: int, form: String) -> void:
	if target.hp <= 0: return
	if boss_trial and target.enemy and rooms[room].shield:
		message("보호막 · 전력탑을 먼저 파괴하세요."); return
	if target.get("iron_guard",false): amount = maxi(1,amount / 4)
	elif target.get("guarded",false): amount = maxi(1,amount / 2)
	if not target.enemy: amount = Growth.incoming(target,amount)
	# A solo floor always grants one action; collapse instead exposes the hero
	# to one extra point of damage. Calming supplies can prevent this penalty.
	if floor_mode and party.size() == 1 and not target.enemy and target.stress >= 150 and amount > 0: amount += 1
	serial += 1
	var lost := mini(int(target.hp), amount)
	var source_cell: Vector2i = target.pos
	var source_name: String = {"FIRE":"불길","ELECTRIC":"방전","POISON":"독"}.get(form,"함정")
	for actor in party + enemies:
		if actor.id == source: source_cell = actor.pos; source_name = actor.name
	var effect := {"from":source_cell,"cell":target.pos,"amount":lost,"form":form}
	effects.append(effect)
	if effects.size() > 32: effects.pop_front()
	var key := ("%d/%d/%d" % [seed_value, serial, target.id]).sha256_text()
	var plan := Injury.assess_hp_loss(target.body, form, lost, target.max_hp, key, target.id + 1)
	var injury: Dictionary = Injury._apply_plan(target.body, plan, serial)
	# Tissue wear occurs on ordinary hits too. Only a new functional injury
	# (including disabled -> severed) warrants the cinematic feedback.
	if injury.get("accepted",false) and plan.get("condition_before","") != plan.get("condition_after","") and plan.get("condition_after","") in ["DISABLED","SEVERED"]:
		effect["body_injury"] = true
		effect["part"] = Body.PART_NAMES.get(plan.get("part_id",""),"신체")
	target.hp -= lost; Body.sync(target)
	if floor_mode and target.enemy and lost > 0: Floor.MonsterAI.interrupt(self,target)
	if not target.enemy:
		var entered_crisis: bool = (target.hp+lost)*4 > target.max_hp and target.hp*4 <= target.max_hp
		if effect.get("body_injury",false) or entered_crisis:
			remember_important(target,"SELF_HARM",target.id+1,source+1,800 if target.hp <= 0 else 750)
		stress(target, 5 + lost / 2)
		if target.hp <= 0:
			for ally in alive():
				remember_important(ally,"ALLY_LOST",target.id+1,source+1,900)
				stress(ally, 22)
	message("%s %s에게 %d의 피해를 주었습니다.%s" % [subject_name(source_name),target.name,lost," "+subject_name(target.name)+" 쓰러졌습니다." if target.hp <= 0 else ""])
	if target.enemy and target.hp <= 0: roll_essence(target)

func plan_enemies() -> void:
	if floor_mode: Floor.MonsterAI.plan(self); return
	if boss_trial: BossTrial.plan(self); return
	intents.clear()
	for enemy in enemies:
		enemy["charging"] = false
		if enemy.hp <= 0 or alive().is_empty(): continue
		# Only the guardian's heavy strike is cell-locked and telegraphed.
		if enemy.name != "수문장" or round_number % 3 != 0: continue
		var targets := alive()
		targets.sort_custom(func(a,b): return distance(enemy.pos,a.pos) < distance(enemy.pos,b.pos))
		var target: Dictionary = targets[0]
		if distance(enemy.pos,target.pos) > 4 or not preload("res://sim/combat_kernel.gd").sees(enemy.pos,target.pos,func(p): return tile(p).terrain == "wall"): continue
		enemy.charging = true
		intents.append({"id":enemy.id, "cell":target.pos, "damage":16})

func enemy_attack_turn(enemy: Dictionary) -> void:
	if phase != "BATTLE" or enemy.hp <= 0 or alive().is_empty(): return
	if floor_mode: floor_state.enemy_turn(self,enemy); return
	if boss_trial: BossTrial.turn(self,enemy); return
	if enemy.get("charging",false):
		# Pushing removes the intent: interrupted charge loses the action.
		var cells: Array = []
		for intent in intents:
			if intent.id == enemy.id: cells.append(intent.cell)
		enemy_attack_effect(enemy,cells,true)
		for intent in intents:
			if intent.id != enemy.id: continue
			var victim := at(intent.cell)
			if not victim.is_empty(): damage(victim,intent.damage,enemy.id,"IMPACT")
		return
	var best_path: Array = []
	var target: Dictionary = {}
	for actor in alive():
		if melee_reach(enemy.pos,actor.pos):
			target = actor; best_path = [enemy.pos]; break
		var goals: Array = []
		for direction in DIRECTIONS:
			var point: Vector2i = actor.pos + direction
			if is_free(point) and melee_reach(point,actor.pos): goals.append(point)
		if goals.is_empty(): continue
		var route := TurnCore.path(BOARD_SIDE,BOARD_SIDE,enemy.pos,goals,
			func(origin,point): return can_step(origin,point),func(_p): return 100)
		if route.found and (best_path.is_empty() or route.path.size() < best_path.size()):
			best_path = route.path; target = actor
	if target.is_empty(): return
	# Same-turn movement and melee attack; body injuries also slow enemies.
	var steps := 2 if enemy.move_factor == 100 else 1
	enemy.pos = best_path[mini(steps,best_path.size()-1)]
	if melee_reach(enemy.pos,target.pos):
		enemy_attack_effect(enemy,[target.pos])
		damage(target,maxi(1,(10 if enemy.name == "수문장" else 7)*enemy.attack_factor/100),enemy.id,"IMPACT")

func end_round() -> bool:
	if phase != "BATTLE": return false
	world_time += 100
	for enemy in enemies:
		enemy_attack_turn(enemy)
		if alive().is_empty(): break
	if floor_mode and alive().is_empty(): check_battle_end(); return true
	for y in range(BOARD_SIDE):
		for x in range(BOARD_SIDE):
			var point := Vector2i(x,y)
			var cell := tile(point)
			if cell.fire <= 0 and cell.wet <= 0: continue
			var result := ElementRules.project_existing_fire_tick(cell.fire, cell.wet, 0, world_time)
			cell.fire = result.fire_after_decay
			cell.wet = maxi(0, result.wetness_after_suppression - ElementRules.WETNESS_DECAY_PER_ENVIRONMENT_TICK)
			if result.known_damage <= 0: continue
			var victim := at(point)
			if not victim.is_empty() and result.known_damage > 0: damage(victim, result.known_damage, 999, "FIRE")
	check_battle_end()
	if phase != "BATTLE": return true
	for actor in alive():
		actor["guarded"] = false
		actor.iron_guard = false
		for id in actor.cooldowns: actor.cooldowns[id] = maxi(0,int(actor.cooldowns[id])-1)
		if not floor_mode or not floor_state.safe(self): stress(actor, 2 if light >= 35 else 5)
		actor.ap = action_budget(actor)
	round_number += 1
	if floor_mode:
		if round_number % 4 == 0: light = maxi(0,light-1)
		if round_number % 20 == 0:
			add_stock("food",-mini(food,1))
			hunger = clampi(hunger+(5 if food == 0 else 1),0,100)
			if food == 0 or light < 35:
				for actor in alive(): stress(actor,(3 if food == 0 else 0)+(2 if light < 35 else 0))
		floor_state.observe(self); floor_state.ambush(self)
	if companions and party[selected].hp <= 0: selected = party.find(alive()[0])
	plan_enemies()
	return true

func check_battle_end() -> void:
	if phase != "BATTLE": return
	if alive().is_empty():
		phase = "DEFEAT"; loot = 0; message("원정대가 전멸했습니다.")
		if floor_mode: finish_expedition("DEFEAT")
	elif floor_mode: return
	elif enemies.all(func(a): return a.hp <= 0):
		loot += 35 if rooms[room].kind != "boss" else 100
		rooms[room].cleared = true
		phase = "EXPLORE"; intents.clear()
		if boss_trial:
			rooms[room].shield = false
			for actor in alive(): actor.hp = actor.max_hp; Body.heal(actor); actor.stress = 0
			message("패턴 테스트 · 다음 방을 위해 체력과 부상을 회복했습니다.")
		for actor in alive(): stress(actor, -7)
		message("전투 승리 · 전리품 %d. 부상과 기억을 안고 탐험을 계속합니다." % loot)

func retreat() -> bool:
	# The continuous floor only ends at the entry (return_home) or by abandon().
	if floor_mode or phase not in ["EXPLORE", "EVENT", "BATTLE"]: return false
	var penalty: bool = phase == "BATTLE" and (not floor_mode or not floor_state.safe(self))
	if penalty:
		loot /= 2
		for actor in alive(): stress(actor, 15)
	bank += loot
	message("귀환 · 전리품 %d 정산%s. 누적 자금 %d" % [loot, " (전투 철수 50% 손실)" if penalty else "", bank])
	loot = 0; phase = "TOWN"; intents = []; enemies = []; tiles = []
	return true

func entry_position() -> Vector2i:
	if not floor_mode: return Vector2i(-1,-1)
	for p in floor_state.features:
		if floor_state.features[p].kind == "entry": return p
	return Vector2i(-1,-1)

func objective_text() -> String:
	return Objective.text(self) if floor_mode else ""

func pickup_relic() -> bool:
	return floor_mode and Objective.pickup(self)

func return_error() -> String:
	if not floor_mode or phase != "BATTLE": return "탐험 중에만 귀환할 수 있습니다."
	var actor: Dictionary = party[selected]
	if actor.hp <= 0: return "지금은 행동할 수 없습니다."
	var entry := entry_position()
	if entry.x < 0 or (actor.pos != entry and not melee_reach(actor.pos,entry)): return "입구 관문 옆으로 이동하세요."
	if not floor_state.safe(self): return "주변 적을 먼저 처리하세요."
	return ""

## Normal end of a floor expedition. No enemy turn follows; the result is
## fixed first, then the floor data is cleared.
func return_home() -> bool:
	if not return_error().is_empty(): return false
	return finish_expedition("SUCCESS" if Objective.carrying(self) else "PARTIAL")

func abandon_error() -> String:
	if not floor_mode or phase != "BATTLE" or alive().is_empty(): return "탐험 중에만 포기할 수 있습니다."
	if not floor_state.safe(self): return "적에게서 벗어난 뒤 원정을 포기할 수 있습니다."
	return ""

func abandon() -> bool:
	if not abandon_error().is_empty(): return false
	return finish_expedition("ABANDON")

func actor_snapshot(actor: Dictionary) -> Dictionary:
	var row: Dictionary = actor.duplicate(true)
	row.body = actor.body.to_dict(); row.memory = actor.memory.to_dict(); row.profile = actor.profile.to_dict()
	return row

func actor_restore(row: Dictionary) -> Dictionary:
	var actor: Dictionary = row.duplicate(true)
	actor.body = Body.State.from_dict(row.body); actor.memory = Memory.from_dict(row.memory); actor.profile = Hexaco.from_dict(row.profile)
	actor.reservation = {}; actor.cooldowns = {}; actor.iron_guard = false; actor["guarded"] = false
	Body.sync(actor)
	return actor

func take_snapshot() -> Dictionary:
	return {"party":party.map(actor_snapshot),"essences":essences.duplicate(true),"bank":bank}

func restore_snapshot() -> void:
	if snapshot.is_empty(): return
	party = snapshot.party.map(actor_restore)
	essences = snapshot.essences.duplicate(true); bank = snapshot.bank
	selected = 0

func injury_count(actor: Dictionary) -> int:
	var count := 0
	for part in actor.body.parts:
		if str(part.condition) in ["DISABLED","SEVERED"]: count += 1
	return count

## Safe returns keep gains and injuries; only defeat restores the actor snapshot.
func finish_expedition(reason: String) -> bool:
	if not floor_mode or phase not in ["BATTLE","DEFEAT"] or not result.is_empty() or snapshot.is_empty(): return false
	if reason not in ["SUCCESS","PARTIAL","ABANDON","DEFEAT"]: return false
	if reason == "ABANDON" and not abandon_error().is_empty(): return false
	if reason in ["SUCCESS","PARTIAL"]:
		if not return_error().is_empty() or (reason == "SUCCESS") != Objective.carrying(self): return false
	if reason == "DEFEAT" and not alive().is_empty(): return false
	var before: Dictionary = snapshot.party[0]
	var hero: Dictionary = party[0]
	var kept: bool = reason in ["SUCCESS","PARTIAL","ABANDON"]
	var bonus: int = Objective.RECOVERY_BONUS if reason == "SUCCESS" else 0
	var provision_value := provision_sale_value() if kept else 0
	var summary := {"reason":reason,"expedition":expedition_number,"relic":reason == "SUCCESS","loot":loot if kept else 0,"bonus":bonus,"settled":true,
		"levels":hero.growth.level-int(before.growth.level) if kept else 0,"essences":{},"abilities":[],"injuries":0,"memories":0,
		"provisions":provision_value,"remaining_stock":provision_stock(),"remaining_food":food,"remaining_light":light,
		"stress_penalty":ABANDON_STRESS if reason == "ABANDON" else 0}
	if kept:
		if reason == "ABANDON":
			for actor in alive():
				actor.stress = mini(200,actor.stress+ABANDON_STRESS)
				stress(actor,0) # Refresh condition without personality/trauma modifiers.
		for id in essences:
			var gained: int = int(essences[id])-int(snapshot.essences.get(id,0))
			if gained > 0: summary.essences[id] = gained
		for id in hero.learned_abilities:
			if id not in before.learned_abilities: summary.abilities.append(id)
		summary.injuries = injury_count(hero)-injury_count(actor_restore(before))
		summary.memories = hero.memory.records.size()-before.memory.records.size()
		bank += loot+bonus+provision_value
		objective.state = "DELIVERED" if reason == "SUCCESS" else "LOST"
		message("귀환 · 전리품 %d + 보급품 환전 %d%s. 누적 자금 %d" % [loot,provision_value," + 유물 회수 보너스 %d" % bonus if bonus > 0 else "",bank])
		if reason == "ABANDON": message("원정 포기 · 임무 보상 없음. 전리품·성장·부상 유지, 생존자 스트레스 +20.")
	else:
		restore_snapshot()
		objective.state = "LOST"
		message("패배 · 이번 출정의 획득물과 보급품을 잃었습니다. 주인공은 출정 전 상태로 복원됩니다.")
	summary.bank = bank
	result = summary
	loot = 0; phase = "TOWN"; intents = []; enemies = []; tiles = []; effects.clear()
	food = 0; torches = 0; supplies = [0,0,0,0,0,0]; exploration_tools = {"KEY":0,"SHOVEL":0}
	purchases.clear(); free_provisions.clear()
	top_up_kit()
	return true

## Free town refit: acknowledges the result and restores a survivable state.
## Distinct from the paid rest; never touches funds.
func refit() -> bool:
	if phase != "TOWN" or alive().is_empty(): return false
	result = {}
	for actor in alive():
		actor.hp = maxi(actor.hp,ceili(actor.max_hp*0.8)); actor.stress = mini(actor.stress,60)
		actor.condition = "평온"; Body.heal(actor)
	message("무료 재정비 · 최소한의 치료와 휴식. 부위 손상은 유지됩니다.")
	return true

## Count grants separately to prevent free-kit departure/return money farming.
func top_up_kit() -> void:
	if not floor_mode or phase != "TOWN": return
	var minimum := {"food":MIN_KIT.food,"torch":MIN_KIT.torches}
	for i in range(6): minimum["supply:%d" % i] = MIN_KIT.supplies[i]
	for id in MIN_KIT.tools: minimum["tool:"+id] = MIN_KIT.tools[id]
	for id in minimum:
		var granted: int = maxi(0,int(minimum[id])-stock(id))
		add_stock(id,granted)
		free_provisions[id] = int(free_provisions.get(id,0))+granted

func provision_stock() -> Dictionary:
	var remaining := {}
	for row in SHOP: remaining[row.id] = stock(row.id)
	return remaining

func provision_sale_value() -> int:
	var value := 0
	for row in SHOP:
		value += maxi(0,stock(row.id)-int(free_provisions.get(row.id,0)))*int(row.price)
	return value*PROVISION_SELL_PERCENT/100

func price(id: String) -> int:
	for row in SHOP:
		if row.id == id: return int(row.price)
	return -1

func stock(id: String) -> int:
	if id == "food": return food
	if id == "torch": return torches
	if id.begins_with("supply:"): return int(supplies[int(id.substr(7))])
	if id.begins_with("tool:"): return int(exploration_tools.get(id.substr(5),0))
	return 0

func add_stock(id: String, delta: int, free_first: bool = true) -> void:
	if delta < 0:
		var free_count: int = int(free_provisions.get(id,0))
		free_provisions[id] = maxi(0,free_count+delta) if free_first else mini(free_count,maxi(0,stock(id)+delta))
	if id == "food": food += delta
	elif id == "torch": torches += delta
	elif id.begins_with("supply:"): supplies[int(id.substr(7))] += delta
	elif id.begins_with("tool:"): exploration_tools[id.substr(5)] = int(exploration_tools.get(id.substr(5),0))+delta

func buy(id: String) -> bool:
	var cost := price(id)
	if not floor_mode or phase != "TOWN" or cost < 0 or bank < cost: return false
	bank -= cost; add_stock(id,1); purchases[id] = int(purchases.get(id,0))+1
	return true

func refund(id: String) -> bool:
	if not floor_mode or phase != "TOWN" or int(purchases.get(id,0)) <= 0 or stock(id) <= 0: return false
	bank += price(id); add_stock(id,-1,false); purchases[id] -= 1
	return true

## Darker floors pay more for what is found (continuous floor only).
func loot_scaled(amount: int) -> int:
	return amount*Floor.loot_percent(light)/100 if floor_mode else amount

func rest_town() -> bool:
	if phase != "TOWN" or bank < 20 or alive().is_empty(): return false
	bank -= 20
	for actor in alive():
		stress(actor, -40); actor.hp = mini(actor.max_hp, actor.hp + 20); Body.heal(actor)
	message("요양 · 자금 20 소비. 기억과 부위 손상은 유지됩니다.")
	return true

func use_supply(slot: int, target: Vector2i = Vector2i(-1,-1), recipient: int = -1) -> bool:
	if phase not in ["EXPLORE","BATTLE"] or slot < 0 or slot >= supplies.size() or supplies[slot] <= 0: return false
	var user: Dictionary = party[selected]
	if recipient < -1 or recipient >= party.size(): return false
	var actor: Dictionary = party[selected if recipient == -1 else recipient]
	if actor.hp <= 0 or user.hp <= 0 or phase == "BATTLE" and user.ap <= 0: return false
	if slot in [3,4]:
		if recipient != -1: return false
		# act() advances the world once; do not advance it again below.
		var id := "supply:%d" % slot
		var free_before: int = int(free_provisions.get(id,0))
		add_stock(id,-1) # Consume before an action that may end the expedition.
		if not act("FIRE" if slot == 3 else "WATER",target):
			add_stock(id,1); free_provisions[id] = free_before
			return false
	else:
		if slot in [0,5] and actor.hp >= actor.max_hp: return false
		if slot == 1 and actor.stress == 0: return false
		if slot == 2 and hunger == 0 and actor.stress == 0: return false
		match slot:
			0,5:
				actor.hp = mini(actor.max_hp,actor.hp + (20 if slot == 0 else 10)); Body.heal(actor)
			1: stress(actor,-25)
			2: hunger = maxi(0,hunger-30); stress(actor,-10)
		if phase == "BATTLE": user.ap -= 1
	if slot not in [3,4]: add_stock("supply:%d" % slot,-1)
	message("%s · %s 사용" % [actor.name,SUPPLY_NAMES[slot]])
	if slot not in [3,4]: finish_player_action()
	return true
