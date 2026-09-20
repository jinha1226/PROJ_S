extends RefCounted
## Expedition host: persistent actors; room-local terrain, enemies and intent.
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
const Memory = preload("res://sim/party_memory_state.gd")
const Body = preload("res://game/rebuilt/body_bridge.gd")
const TurnCore = preload("res://sim/turn_engine.gd")
const ElementRules = preload("res://sim/environment_rules.gd")
const Injury = preload("res://sim/body_injury_system.gd")
const Dungeon = preload("res://expedition/dungeon_map.gd")
const BossTrial = preload("res://expedition/boss_trial.gd")
var boss_trial := false
const Tactics = preload("res://expedition/tactical_action_selector.gd")
const Rules = preload("res://expedition/tactic_rules.gd")
const Abilities = preload("res://expedition/abilities.gd")
const Growth = preload("res://expedition/growth.gd")
var essences: Dictionary = {}
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
const SUPPLY_NAMES = ["치유 물약","정신 안정제","활력 물약","화염 두루마리","물 두루마리","붕대"]

func _init(p_seed: int = 731, p_boss_trial: bool = false, p_companions: bool = false) -> void:
	seed_value = p_seed
	boss_trial = p_boss_trial
	companions = p_companions and boss_trial
	for i in range(2 if companions else 1 if boss_trial else 3):
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
	if log_lines.size() > 40: log_lines.pop_front()

func alive() -> Array:
	return party.filter(func(a): return a.hp > 0)

func depart() -> bool:
	if phase != "TOWN" or alive().is_empty(): return false
	expedition_number += 1
	food = 27; torches = 5; light = 90; loot = 0; hunger = 0
	supplies = [2,2,1,1,1,3]
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
		message(BossTrial.HINTS[rooms[room].pattern]); return
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

func action_budget(actor: Dictionary) -> int:
	if boss_trial: return 1
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

func auto_attack() -> bool:
	if phase != "BATTLE": return false
	var actor: Dictionary = party[selected]
	if actor.hp <= 0 or actor.ap <= 0: return false
	var targets: Array = enemies.filter(func(e): return e.hp > 0)
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
		var route := TurnCore.path(8,8,actor.pos,goals,func(a,b): return can_step(a,b) and Tactics.danger(self,b) == 0,func(_p): return 100)
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
				if boss_trial and victim.get("charging",false):
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
	if phase == "BATTLE": end_round()

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
		if Growth.gain(actor,100 if boss_trial else 25) > 0: message(actor.name+" · 레벨 %d! 숙련 포인트 획득" % actor.growth.level)
	var id: String = enemy.get("essence_id","")
	if not Abilities.DEFINITIONS.has(id): return
	if Hexaco.sample(seed_value,expedition_number*10000+room*100+enemy.id,"essence",100) >= Abilities.DROP_PERCENT: return
	essences[id] = int(essences.get(id,0))+1
	message("이능 전리품 · "+Abilities.DEFINITIONS[id].item+" → 공용 가방")

func spend_growth(index: int, id: String, stat: bool = false) -> bool:
	if phase not in ["TOWN","EXPLORE"] or index < 0 or index >= party.size() or party[index].hp <= 0: return false
	return Growth.spend(party[index],id,stat)

func reset_rules(index: int) -> void:
	var actor: Dictionary = party[index]
	actor.rules = Rules.defaults(); actor.basic_target = Rules.BASIC_TARGET_DEFAULT
	for id in actor.learned_abilities:
		if Abilities.DEFINITIONS.has(id): actor.rules.append(Rules.make_rule(id,"SELF" if Abilities.DEFINITIONS[id].target == "SELF" else "NEAREST","DANGER" if id == "IRON_HIDE" else "ALWAYS"))

func consume_essence(index: int, id: String) -> bool:
	if phase not in ["TOWN","EXPLORE"] or index < 0 or index >= party.size() or not Abilities.DEFINITIONS.has(id): return false
	var actor: Dictionary = party[index]
	if actor.hp <= 0 or essences.get(id,0) <= 0 or id in actor.learned_abilities: return false
	actor.learned_abilities.append(id); essences[id] -= 1
	actor.rules.append(Rules.make_rule(id,"SELF" if Abilities.DEFINITIONS[id].target == "SELF" else "NEAREST","DANGER" if id == "IRON_HIDE" else "ALWAYS"))
	message(actor.name+" · "+Abilities.DEFINITIONS[id].name+" 습득! 이능 탭에서 장착하세요.")
	return true

func equip_ability(index: int, slot: int, id: String) -> bool:
	if phase not in ["TOWN","EXPLORE"] or index < 0 or index >= party.size() or party[index].hp <= 0: return false
	return Abilities.equip(party[index],slot,id)

func enemy_attack_effect(enemy: Dictionary, cells: Array, area: bool = false) -> void:
	if cells.is_empty(): return
	effects.append({"kind":"ENEMY_ATTACK","from":enemy.pos,"cell":cells[0],
		"cells":cells.duplicate(),"area":area,"amount":0,"form":"IMPACT"})
	if effects.size() > 32: effects.pop_front()

func damage(target: Dictionary, amount: int, source: int, form: String) -> void:
	if target.hp <= 0: return
	if boss_trial and target.enemy and rooms[room].shield:
		message("보호막 · 전력탑을 먼저 파괴하세요."); return
	if target.get("iron_guard",false): amount = maxi(1,amount / 4)
	elif target.get("guarded",false): amount = maxi(1,amount / 2)
	if not target.enemy: amount = Growth.incoming(target,amount)
	serial += 1
	var lost := mini(int(target.hp), amount)
	var source_cell: Vector2i = target.pos
	for actor in party + enemies:
		if actor.id == source: source_cell = actor.pos
	var effect := {"from":source_cell,"cell":target.pos,"amount":lost,"form":form}
	effects.append(effect)
	if effects.size() > 32: effects.pop_front()
	var key := ("%d/%d/%d" % [seed_value, serial, target.id]).sha256_text()
	var plan := Injury.assess_hp_loss(target.body, form, lost, target.max_hp, key, target.id + 1)
	var injury: Dictionary = Injury._apply_plan(target.body, plan, serial)
	if injury.get("accepted",false) and injury.get("mutated",false):
		effect["body_injury"] = true
		effect["part"] = Body.PART_NAMES.get(plan.get("part_id",""),"신체")
	target.hp -= lost; Body.sync(target)
	if target.enemy and target.hp <= 0: roll_essence(target)
	if not target.enemy:
		target.memory.remember("SELF_HARM", serial, world_time, source + 1, source + 1, mini(1000, 180 + lost * 18))
		stress(target, 5 + lost / 2)
		if target.hp <= 0:
			for ally in alive():
				ally.memory.remember("ALLY_LOST", serial, world_time, target.id + 1, source + 1, 800)
				stress(ally, 22)
	message("%s · %d 피해%s" % [target.name, lost, " · 사망" if target.hp <= 0 else ""])

func plan_enemies() -> void:
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
	if enemy.hp <= 0 or alive().is_empty(): return
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
		var route := TurnCore.path(8,8,enemy.pos,goals,
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
	for actor in alive():
		actor["guarded"] = false
		actor.iron_guard = false
		for id in actor.cooldowns: actor.cooldowns[id] = maxi(0,int(actor.cooldowns[id])-1)
		stress(actor, 2 if light >= 35 else 5)
		actor.ap = action_budget(actor)
	round_number += 1
	if companions and party[selected].hp <= 0: selected = party.find(alive()[0])
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
		if boss_trial:
			rooms[room].shield = false
			for actor in alive(): actor.hp = actor.max_hp; Body.heal(actor); actor.stress = 0
			message("패턴 테스트 · 다음 방을 위해 체력과 부상을 회복했습니다.")
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

func use_supply(slot: int, target: Vector2i = Vector2i(-1,-1), recipient: int = -1) -> bool:
	if phase not in ["EXPLORE","BATTLE"] or slot < 0 or slot >= supplies.size() or supplies[slot] <= 0: return false
	var user: Dictionary = party[selected]
	if recipient < -1 or recipient >= party.size(): return false
	var actor: Dictionary = party[selected if recipient == -1 else recipient]
	if actor.hp <= 0 or user.hp <= 0 or phase == "BATTLE" and user.ap <= 0: return false
	if slot in [3,4]:
		if recipient != -1: return false
		# act() advances the world once; do not advance it again below.
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
		if phase == "BATTLE": user.ap -= 1
	supplies[slot] -= 1
	message("%s · %s 사용" % [actor.name,SUPPLY_NAMES[slot]])
	if slot not in [3,4]: finish_player_action()
	return true
