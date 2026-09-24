extends RefCounted
## Descent run host: persistent actors, floor terrain, enemies and intent.
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
const Memory = preload("res://sim/party_memory_state.gd")
const Body = preload("res://game/rebuilt/body_bridge.gd")
const TurnCore = preload("res://sim/turn_engine.gd")
const ElementRules = preload("res://sim/environment_rules.gd")
const NpcRoster = preload("res://expedition/npc_roster.gd")
const NpcAI = preload("res://expedition/npc_ai.gd")
const Recruit = preload("res://expedition/npc_recruit.gd")
var BOARD_SIDE := 64
const Floor = preload("res://expedition/continuous_floor.gd")
const Encounters = preload("res://expedition/encounter_builder.gd")
var floor_state
const Tactics = preload("res://expedition/tactical_action_selector.gd")
const Knobs = preload("res://expedition/knobs.gd")
const Stances = preload("res://expedition/stances.gd")
const Rules = preload("res://expedition/tactic_rules.gd")
const Abilities = preload("res://expedition/abilities.gd")
const IntentUI = preload("res://expedition/companion_intent_ui.gd")
const Growth = preload("res://expedition/growth.gd")
const Mastery = preload("res://expedition/mastery.gd")
const CombatStats = preload("res://expedition/combat_stats.gd")
const CombatRules = preload("res://expedition/combat_rules.gd")
const Scheduler = preload("res://expedition/scheduler.gd")
const Spells = preload("res://expedition/spells.gd")
const Passives = preload("res://expedition/passives.gd")
var parts_bag: Dictionary = {}
const STARTING_PARTS := {"PUSH":1,"GUARD":1}
var party_command := "FOLLOW"
## Marching order: party indices in the order they follow the leader. The
## leader is the first living index in the order.
var formation: Array = [0,1,2]
var command_target := -1
var companions := false
var resolving_companions := false
# Optional UI recorder; headless simulations never allocate presentation snapshots.
var presentation = null
var active_intent_event: Dictionary = {}
var intent_decision_serial := 0
var intent_preview_ids: Dictionary = {}
## Evaluation priority: the hard events first, then the soft alerts.
const AUTO_STOPS := ["BATTLE_START","BATTLE_END","DEATH","ALLY_LETHAL","HP_LOW"]
## Auto-battle state: whether the UI is advancing rounds, which events stop it,
## and what the previous round looked like so that "newly" can be judged.
## Which events stop an auto run out of the box: the three that end or change a
## battle, never the two rolling alerts — those are opt-in.
const AUTO_STOP_DEFAULTS := {"BATTLE_START":true,"ALLY_LETHAL":false,"HP_LOW":false,"DEATH":true,"BATTLE_END":true}
var auto := {"running":false,"stops":AUTO_STOP_DEFAULTS.duplicate(),
	"hp_low":30,"speed":1,"prev_threats":0,"prev_low":[],"prev_alive":0,"last_stop":{"reason":"","round":-99},"stops_log":[]}
const CARDINALS = [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]
const DIRECTIONS = [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN, Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]
var seed_value := 731
## Test hook: {actor_id: bool} forces the mistake roll. Always empty in play.
var mistake_override: Dictionary = {}
var phase := "IDLE"
var simulation_arena := false
var party: Array = []
var enemies: Array = []
## Dungeon NPCs: the run roster and the ones standing on this floor.
var roster: Array = []
var npcs: Array = []
## The npc whose offer to join is waiting on the player, or -1. (Task 5 answers it.)
var pending_offer := -1
## Combat noise this round: the cells where blows landed. NPCs hear these.
var noise: Array = []
var tiles: Array = []
var log_lines: Array[String] = []
var food := 2
var depth := 0
var score := 0
var run_stats := {"mistakes":0,"kills":0}
var serial := 0
## Everything the battle report reads, gathered while the battle runs.
## Reset when a battle starts; outside floor mode nothing resets it, so the
## rows simply accumulate for whoever asks.
var battle_stats: Dictionary = {}
var world_time := 0
var round_number := 0
var time := 0
var boundary := 100
var turn_serial := 0
var roll_serial := 0
var gear_bag: Array = []
var manual_mode := false
var selected := 0
var intents: Array = []
var effects: Array = []
## Utility selector: whether `Lookahead.predict` answers the `la_*`
## considerations. On by default; a simulation tool can turn it off to compare.
var lookahead_enabled := true
var supplies: Array = [0,0,0,0,0]
const Curios = preload("res://expedition/curios.gd")
const BossAI = preload("res://expedition/boss_ai.gd")
const SUPPLY_NAMES = ["치유 물약","정신 안정제","활력 물약","화염 두루마리","물 두루마리"]

## Experiment rules: the defaults reproduce shipped behaviour byte for byte.
const DEFAULT_RULES := {"solo_actions":1,"solo_max_members":0}
var rules_config: Dictionary = DEFAULT_RULES.duplicate()

## The kit the hero departs with: one of the ten in `combat.json.kits`, one per
## mastery axis. An unknown id is refused rather than silently swapped.
var kit_id := "sword"

static func new_run(seed: int, p_kit_id: String = "sword"):
	if CombatStats.kit(p_kit_id).is_empty(): return null
	var run = new(seed,false,false,true,1)
	run.kit_id = p_kit_id
	if not run.depart(): return null
	run.manual_mode = true
	return run

func _init(p_seed: int = 731, _p_boss_trial: bool = false, p_companions: bool = false, _p_floor: bool = true, p_party_size: int = 0) -> void:
	seed_value = p_seed
	companions = (p_party_size > 1) if p_party_size > 0 else p_companions
	floor_state = Floor.new(); BOARD_SIDE = floor_state.size
	parts_bag = STARTING_PARTS.duplicate(true)
	var count: int = clampi(p_party_size,1,3) if p_party_size > 0 else (2 if companions else 1)
	for i in range(count): party.append(make_actor(i,["아린","브란","세라"][i],false))
	formation = range(count)
	reset_battle_stats()

func make_actor(id: int, actor_name: String, enemy: bool) -> Dictionary:
	var actor := {"id":id, "name":actor_name, "enemy":enemy,
		"tactics":{"PUSH":"PROTECT","GUARD":"LOW_HP"},"priority":"PUSH","last_action":"대기",
		"rules":Rules.defaults(),
		"basic_target":Rules.BASIC_TARGET_DEFAULT,
		"reservation":{},
		"equipped_abilities":["",""],"cooldowns":{},"iron_guard":false,
		"growth":Growth.create(),"protected_by":-1,
		"gear":{"weapon":{},"armour":{},"shield":{},"ring":{}},
		"mp":18,"max_mp":18,"skill_xp":{},"usage":{},"statuses":{},"spells":[],"prepared":[],
		"level":1,"level_xp":0,"ready_at":0,
		"pos":Vector2i.ZERO, "hp":28 if enemy else 55, "max_hp":28 if enemy else 55,
		"stress":0, "condition":"평온", "ap":2,
		"body":Body.create(id, seed_value, enemy),
		"profile":Hexaco.generated(seed_value, id + 1), "memory":Memory.new()}
	actor["species_id"] = "" if enemy else "human"
	if enemy:
		actor["power"] = 7; actor["speed"] = 100; actor["ac"] = 0; actor["ev"] = 3; actor["res"] = {}
	else:
		actor.gear.weapon = {"type":"sword","enchant":0}
		actor.gear.armour = {"type":"robe","enchant":0}
	# How the member fights with whatever it carries, and who it covers.
	actor["stance"] = Stances.default_stance(actor.profile)
	actor["protect_id"] = -1
	actor["hit_and_run"] = false
	# The knobs start where this personality is comfortable, so nobody is born
	# in conflict with their own standing orders.
	actor["knobs"] = Knobs.defaults(actor.profile)
	actor["conflicted"] = false
	Body.sync(actor)
	return actor

func message(value: String) -> void:
	log_lines.append(value)

## Persistent memories are landmarks, not a transcript of ordinary hits.
func remember_important(actor: Dictionary, kind: String, subject: int, instigator: int, salience: int) -> void:
	actor.memory.records = actor.memory.records.filter(func(record): return int(record.salience) >= 700 or str(record.kind) in Memory.SOCIAL_KINDS)
	var key := "%d/%s" % [depth,kind]
	if kind != "SELF_HARM": key += "/%d" % subject
	var recorded: Dictionary = actor.get("important_memories",{})
	if recorded.has(key): return
	if actor.memory.remember(kind,serial,world_time,subject,instigator,salience):
		recorded[key] = true; actor.important_memories = recorded

## A record that is not a landmark: written as it stands, and the older ones
## left where they are. Recruitment memories are worth less than 700 and would
## not survive `remember_important`'s pruning of its own first line.
func remember_plain(actor: Dictionary, kind: String, subject: int, instigator: int, salience: int) -> void:
	var key := "plain/%d/%s/%d" % [depth,kind,subject]
	var recorded: Dictionary = actor.get("important_memories",{})
	if recorded.has(key): return
	if actor.memory.remember(kind,serial,world_time,subject,instigator,salience):
		recorded[key] = true; actor.important_memories = recorded

## Clears the report and opens one row per member. The simulator calls this
## itself at the arena, where no BATTLE_START stop event runs.
func reset_battle_stats() -> void:
	# The report is the party's own sight (T3-b), not every foe an npc dragged in.
	battle_stats = {"rounds":0,"enemies":party_enemies().size() if phase == "BATTLE" else 0,"kills":0,"members":{},
		"interrupts":0,"enemy_parts":{},"drops":{},"stops":[]}
	for actor in party:
		# A new battle starts with nothing to commit to: the utility selector's
		# `same_as_last` must not read the last battle's closing move.
		actor.last_action_kind = ""
		actor.last_action_dir = Vector2i.ZERO
		battle_stats.members[actor.id] = {"dealt":0,"taken":0,"guards":0,"covers":0,"redirected":0,
			"parts":{},"healed":0,"downed":false,"conflict":bool(actor.get("conflicted",false)),
			"mistakes":0,"role_rounds":{"in_role":0,"total":0},"explains":[]}

## The row of one member, empty for an id that is not in the party — which is
## what every tally below tests before it writes.
func member_stats(id: int) -> Dictionary:
	if not battle_stats.has("members"): reset_battle_stats()
	return battle_stats.members.get(id,{})

## An npc still on its own out there: the flag is identity, the party list is
## what decides how the game treats it.
func wanderer(actor: Dictionary) -> bool:
	return bool(actor.get("npc",false)) and not (actor in party)

func alive() -> Array:
	return party.filter(func(a): return a.hp > 0)

func on_floor() -> bool:
	return phase in ["EXPLORE","BATTLE"]

func npc_clock() -> int:
	return time if manual_mode else round_number

func npc_cooldown() -> int:
	return 2000 if manual_mode else Recruit.COOLDOWN

## Whom the party's tactics fight beside: its own survivors and every awake,
## living dungeon NPC. `alive()` stays the party alone — defeat, stress and the
## battle's end are the party's own business.
func friends() -> Array:
	return alive()+npcs.filter(func(n): return n.hp > 0 and n.awake)

## Who walked with the party this run: only those who actually joined, in
## roster order, each with the floor it joined on and whether it is still up.
func companion_rows() -> Array:
	return roster.filter(func(r): return int(r.get("joined_floor",0)) > 0).map(
		func(r): return {"name":str(r.name),"joined_floor":int(r.joined_floor),"alive":r.hp > 0 and r.state != "DEAD"})

## Sharing food, asking, and the answer to an npc's own offer.
func aid(npc: Dictionary) -> bool:
	return Recruit.aid(self,npc)

func propose(npc: Dictionary) -> Dictionary:
	return Recruit.propose(self,npc)

func recruit(npc: Dictionary) -> bool:
	return Recruit.recruit(self,npc).accepted

## An npc beside the party asks to come along. One offer stands at a time and
## the npc will not ask again for twenty rounds after an answer.
## An NPC only speaks up while the party is exploring: never into a battle.
func offer(npc: Dictionary) -> bool:
	if phase != "EXPLORE" or pending_offer >= 0 or npc.state != "MET" or npc_clock() < int(npc.get("offered_until",-99)): return false
	# A summoned creature never asks to come along: it is already the hero's.
	if bool(npc.get("summoned",false)): return false
	pending_offer = npc.id
	return true

## The player's answer to the standing offer. A refusal is remembered and
## starts the cooldown; the npc keeps standing where it is.
func answer_offer(accept: bool) -> bool:
	if pending_offer < 0: return false
	var found: Array = npcs.filter(func(n): return n.id == pending_offer)
	pending_offer = -1
	if found.is_empty(): return false
	var npc: Dictionary = found[0]
	npc.offered_until = npc_clock()+npc_cooldown()
	if not accept:
		npc.declined_until = npc_clock()+npc_cooldown()
		serial += 1
		remember_plain(npc,"DECLINED_BY_PLAYER",Recruit.hero(self),Recruit.hero(self),400)
		return true
	return Recruit.recruit(self,npc).accepted

func depart() -> bool:
	if phase != "IDLE" or alive().is_empty(): return false
	var kit: Dictionary = CombatStats.kit(kit_id)
	if kit.is_empty(): return false
	depth = 1; score = 0; run_stats = {"mistakes":0,"kills":0}
	time = 0; boundary = 100; turn_serial = 0; roll_serial = 0
	party[0].gear.weapon = {"type":str(kit.weapon),"enchant":0}
	party[0].gear.armour = {"type":"robe","enchant":0}
	party[0].skill_xp[str(kit.axis)] = 25
	var kit_spell: String = str(kit.get("spell",""))
	if not kit_spell.is_empty():
		party[0].spells = [kit_spell]
		party[0].prepared = [kit_spell]
	for actor in party:
		# A debt owed or refused outlives the run it was made in.
		actor.memory.records = actor.memory.records.filter(func(record): return int(record.salience) >= 700 or str(record.kind) in Memory.SOCIAL_KINDS)
		actor.hit_and_run = false; actor.important_memories = {}
	reset_battle_stats()
	auto.prev_threats = 0; auto.prev_low = []; auto.prev_alive = alive().size()
	auto.stops_log = []; auto.last_stop = {"reason":"","round":-99}
	floor_state.build(self)
	if roster.is_empty(): NpcRoster.generate(self)
	NpcRoster.place(self)
	message("%d층 진입" % depth); return true

func stress(actor: Dictionary, amount: int) -> void:
	var trauma := int(actor.memory.strongest(["SELF_HARM", "ALLY_LOST"]).get("salience", 0)) / 200
	var change := amount
	if amount > 0: change = maxi(1, amount * (650 + actor.profile.value("E")) / 1000 + trauma)
	# The solo run halves the hero's own stress; a dungeon NPC feels it whole.
	if amount > 0 and party.size() == 1 and not actor.get("npc",false): change = ceili(change*0.5)
	actor.stress = clampi(actor.stress + change, 0, 200)
	actor.condition = "붕괴" if actor.stress >= 150 else "불안" if actor.stress >= 100 else "평온"





func can_camp() -> String:
	if phase != "EXPLORE": return "지금은 불가"
	if not floor_state.safe(self): return "적이 보임"
	var needed: int = alive().size()
	if food < needed: return "식량 %d 필요" % needed
	return ""

func camp() -> bool:
	if not can_camp().is_empty(): return false
	auto.running = false
	food -= alive().size()
	for actor in alive():
		actor.hp = mini(actor.max_hp,actor.hp+ceili(actor.max_hp*0.5))
		stress(actor,-30)
		for id in actor.cooldowns: actor.cooldowns[id] = 0
	phase = "CAMP"; intents.clear()
	message("야영 · 식량 -%d" % alive().size()); return true

func end_camp() -> bool:
	if phase != "CAMP": return false
	phase = "EXPLORE"
	for actor in alive(): actor.ap = action_budget(actor)
	floor_state.observe(self); return true

func stairs_sealed() -> bool:
	return enemies.any(func(e): return e.get("boss",false) and e.hp > 0)

func descend() -> bool:
	if phase != "EXPLORE" or not floor_state.safe(self) or stairs_sealed(): return false
	var stairs: Vector2i = floor_state.layout.get("stairs",Vector2i(-1,-1))
	if stairs.x < 0 or not alive().any(func(a): return distance(a.pos,stairs) <= 1): return false
	depth += 1; score += 20
	for actor in party: actor.reservation = {}; actor.hit_and_run = false
	end_battle_orders(); reset_battle_stats()
	floor_state.build(self)
	if roster.is_empty(): NpcRoster.generate(self)
	NpcRoster.place(self)
	message("%d층 진입" % depth); return true

func grant_part(id: String) -> void:
	if not Abilities.DEFINITIONS.has(id): return
	parts_bag[id] = int(parts_bag.get(id,0))+1
	message(Abilities.DEFINITIONS[id].item+" 획득")

func grant_supply(slot: int) -> void:
	if slot < 0 or slot >= supplies.size(): return
	supplies[slot] += 1
	message(SUPPLY_NAMES[slot]+" 획득")

func start_battle() -> void:
	phase = "BATTLE"; round_number = 1
	for actor in party:
		actor.reservation = {}; actor.ap = action_budget(actor)
		actor["guarded"] = false; actor["protected_by"] = -1
	selected = party.find(alive()[0]); plan_enemies()

func solo_rule(key: String) -> int:
	if party.size() != 1: return int(DEFAULT_RULES[key])
	return int(rules_config.get(key,DEFAULT_RULES[key]))

func action_budget(actor: Dictionary) -> int:
	if party.size() == 1: return solo_rule("solo_actions")
	return 1 if actor.stress >= 150 else 2

func tile(point: Vector2i) -> Dictionary:
	return tiles[point.y * BOARD_SIDE + point.x]

func inside(point: Vector2i) -> bool:
	return point.x >= 0 and point.y >= 0 and point.x < BOARD_SIDE and point.y < BOARD_SIDE

func at(point: Vector2i) -> Dictionary:
	for actor in party + enemies + npcs:
		if actor.hp > 0 and actor.pos == point: return actor
	return {}

func is_free(point: Vector2i) -> bool:
	return inside(point) and tile(point).terrain != "wall" and at(point).is_empty()

func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func melee_reach(a: Vector2i, b: Vector2i) -> bool:
	if not inside(a) or not inside(b) or a == b or maxi(absi(a.x-b.x),absi(a.y-b.y)) != 1: return false
	if tile(b).terrain == "wall": return false
	if a.x != b.x and a.y != b.y:
		if tile(Vector2i(a.x,b.y)).terrain == "wall" or tile(Vector2i(b.x,a.y)).terrain == "wall": return false
	return true

func walk_reach(a: Vector2i, b: Vector2i) -> bool:
	return inside(a) and inside(b) and a != b and maxi(absi(a.x-b.x),absi(a.y-b.y)) == 1 and tile(b).terrain != "wall"

func can_step(a: Vector2i, b: Vector2i) -> bool:
	return walk_reach(a,b) and is_free(b)

func combat_enemies() -> Array:
	return floor_state.threats(self)

## The foes the party itself can see. `combat_enemies()` also counts the ones an
## awake NPC is fighting out of the party's sight; the auto-run's stop events
## must stay on the party's own eyes, so they ask for this instead.
func party_enemies() -> Array:
	return floor_state.party_threats(self)

func in_combat() -> bool:
	return phase == "BATTLE" and not floor_state.safe(self)

## The first living member in the marching order.
func leader() -> Dictionary:
	for index in formation:
		if index < party.size() and party[index].hp > 0: return party[index]
	return party[0]

func rally_point() -> Vector2i:
	return leader().pos

## Two members trade cells and places in the marching order. Only while the
## run is stopped for a battle start, once per battle.
func can_swap_formation() -> bool:
	return in_combat() and auto.last_stop.reason == "BATTLE_START" and int(auto.last_stop.round) == round_number \
		and int(auto.get("swapped_round",-1)) != round_number and alive().size() >= 2

func swap_formation(a: int, b: int) -> bool:
	if not can_swap_formation(): return false
	if a == b or a < 0 or b < 0 or a >= party.size() or b >= party.size() or party[a].hp <= 0 or party[b].hp <= 0: return false
	var pa: Vector2i = party[a].pos; party[a].pos = party[b].pos; party[b].pos = pa
	var ia: int = formation.find(a); var ib: int = formation.find(b)
	formation[ia] = b; formation[ib] = a
	auto.swapped_round = round_number
	floor_state.observe(self)
	message("%s ↔ %s 자리 교환" % [party[a].name,party[b].name])
	return true

func safe_management() -> bool:
	return phase in ["CAMP","EXPLORE"]

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
	# The index is a party slot; an npc asks by its own (1000+) id instead.
	var actor: Dictionary = party[selected] if actor_index < 0 else (party[actor_index] if actor_index < party.size() else actor_by_id(actor_index))
	if actor.is_empty() or not on_floor() or actor.hp <= 0 or actor.ap <= 0: return result
	var frontier: Array = [actor.pos]
	var seen: Array = [actor.pos]
	for step in range(1 if manual_mode else 2 if actor.move_factor == 100 else 1):
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
	# As in movement_cells: a party slot, or an npc asking by its own id.
	var actor: Dictionary = party[selected] if actor_index < 0 else (party[actor_index] if actor_index < party.size() else actor_by_id(actor_index))
	if actor.is_empty() or not on_floor() or actor.hp <= 0 or actor.ap <= 0: return result
	if manual_mode:
		var reach: int = int(CombatStats.stats(self,actor).range)
		for y in range(maxi(0,actor.pos.y-reach),mini(BOARD_SIDE,actor.pos.y+reach+1)):
			for x in range(maxi(0,actor.pos.x-reach),mini(BOARD_SIDE,actor.pos.x+reach+1)):
				var cell := Vector2i(x,y)
				if floor_state.visible.has(cell) and attack_reach(actor,cell,reach): result.append(cell)
		return result
	for direction in DIRECTIONS:
		var cell: Vector2i = actor.pos + direction
		if melee_reach(actor.pos,cell): result.append(cell)
	return result

func attack_preview(target: Vector2i, actor_index: int = -1) -> Dictionary:
	if not manual_mode:
		if target not in attack_cells(actor_index): return {}
		var old_victim := at(target)
		if old_victim.is_empty() or not old_victim.enemy: return {}
		var old_actor: Dictionary = party[selected] if actor_index < 0 else (party[actor_index] if actor_index < party.size() else actor_by_id(actor_index))
		if old_actor.is_empty(): return {}
		var old_hit := TurnCore.physical(Growth.power(old_actor,"MELEE",18) * old_actor.attack_factor / 100, 1000, 0, 2)
		var old_amount := int(old_hit.damage)
		if old_victim.get("guarded",false): old_amount = maxi(1,old_amount/2)
		if old_victim.get("shield",false): old_amount = 0
		return {"actor":old_actor.id,"target":old_victim.id,"cell":target,"name":old_victim.name,"chance":100,"damage":old_amount,"damage_min":old_amount,"damage_max":old_amount,"time":100}
	var victim := at(target)
	if victim.is_empty() or not victim.enemy: return {}
	var actor: Dictionary = party[selected] if actor_index < 0 else (party[actor_index] if actor_index < party.size() else actor_by_id(actor_index))
	if actor.is_empty(): return {}
	var offense: Dictionary = CombatStats.stats(self,actor)
	var defense: Dictionary = CombatStats.stats(self,victim)
	if not attack_reach(actor,target,int(offense.range)): return {}
	var ac: int = int(defense.ac)/2 if offense.trait == "pierce" else int(defense.ac)
	var dodge: int = clampi(int(defense.ev)*2,5,45)
	var block: int = int(defense.sh)
	return {"actor":actor.id,"target":victim.id,"cell":target,"name":victim.name,
		"chance":maxi(0,(100-dodge)*(100-block)/100),"block":block,"damage":maxi(1,int(offense.damage)-ac),
		"damage_min":maxi(1,int(offense.damage)-ac),"damage_max":int(offense.damage),"time":action_cost(actor,"ATTACK",target)}

func attack_reach(actor: Dictionary, target: Vector2i, attack_range: int) -> bool:
	if attack_range <= 1: return melee_reach(actor.pos,target)
	return distance(actor.pos,target) <= attack_range and Floor.MonsterAI.line(self,actor.pos,target,attack_range)

func act(kind: String, target: Vector2i) -> bool:
	if manual_mode: return submit(kind,target)
	return act_as(party[selected],kind,target,true)

func action_cost(actor: Dictionary, kind: String, target: Vector2i, _value: String = "") -> int:
	var cost := 100
	match kind:
		"MOVE":
			if inside(target): cost = CombatRules.move_time(self,actor,target)
		"ATTACK":
			cost = int(CombatStats.stats(self,actor).delay)
			if manual_mode and actor.get("last_action_kind","") == "ATTACK" and str(actor.get("gear",{}).get("weapon",{}).get("type","")) in ["sword","dagger"] and Mastery.rank(actor,"sword") >= 7: cost = maxi(60,cost-20)
		_:
			if Abilities.DEFINITIONS.has(kind): cost = int(Abilities.DEFINITIONS[kind].get("delay",100))
	var statuses: Dictionary = actor.get("statuses",{})
	if kind != "MOVE":
		if statuses.has("slow"): cost = cost*3/2
		if statuses.has("haste"): cost = cost*2/3
	return maxi(40,cost)

func submit(kind: String, target: Vector2i, value: String = "") -> bool:
	if not on_floor() or party.is_empty() or party[0].hp <= 0: return false
	manual_mode = true
	var actor: Dictionary = party[0]
	actor.ap = 1
	if not can_submit(actor,kind,target,value): return false
	if not Scheduler.flush_ready(self) or actor.hp <= 0: return false
	var cost := action_cost(actor,kind,target,value)
	if kind == "CAST":
		if not Spells.cast(self,actor,value,target): return false
		return Scheduler.advance(self,cost)
	if not act_as(actor,kind,target,false): return false
	actor.ap = 1
	return Scheduler.advance(self,cost)

func can_submit(actor: Dictionary, kind: String, target: Vector2i, value: String = "") -> bool:
	if kind == "CAST": return Spells.can_cast(self,actor,value,target)
	if not inside(target): return false
	if Abilities.DEFINITIONS.has(kind): return Abilities.legal(self,actor,kind,target)
	match kind:
		"WAIT": return target == actor.pos
		"MOVE": return target in movement_cells(0)
		"ATTACK": return not attack_preview(target,0).is_empty()
		"PYLON": return true
		"FIRE", "WATER", "ELECTRIC": return distance(actor.pos,target) <= 4 and tile(target).terrain != "wall"
	return false

func cast(id: String, target: Vector2i) -> bool:
	return submit("CAST",target,id)

func prepare_spell(index: int, id: String, on: bool) -> bool:
	if phase != "CAMP" or index < 0 or index >= party.size(): return false
	var actor: Dictionary = party[index]
	if id not in actor.spells or Spells.definition(id).is_empty(): return false
	if on:
		if id in actor.prepared: return true
		if actor.prepared.size() >= 3: return false
		actor.prepared.append(id)
	else:
		actor.prepared.erase(id)
	return true

func learn_spell(index: int, id: String) -> bool:
	if index < 0 or index >= party.size() or Spells.definition(id).is_empty(): return false
	var actor: Dictionary = party[index]
	if id in actor.spells: return false
	actor.spells.append(id)
	message(str(CombatStats.content.spells[id].name)+" 획득")
	return true

func gear_slot(item: Dictionary) -> String:
	var id: String = str(item.get("type",""))
	if id == "shield": return "shield"
	if CombatStats.content.weapons.has(id): return "weapon"
	if CombatStats.content.armours.has(id): return "armour"
	if CombatStats.content.rings.has(id): return "ring"
	return ""

func equip_gear(index: int, item: Dictionary) -> bool:
	if phase != "CAMP" or index < 0 or index >= party.size() or item not in gear_bag: return false
	var slot := gear_slot(item)
	if slot.is_empty(): return false
	var actor: Dictionary = party[index]
	if slot == "shield" and str(actor.gear.weapon.get("type","")) in ["bow","staff"]: return false
	if slot == "weapon" and str(item.type) in ["bow","staff"] and not actor.gear.shield.is_empty(): return false
	if slot == "armour" and actor.species_id == "elf" and str(item.type) == "plate": return false
	var previous: Dictionary = actor.gear[slot]
	if slot == "weapon" and not previous.is_empty():
		var old_axis := Mastery.weapon_axis(str(previous.type))
		var new_axis := Mastery.weapon_axis(str(item.type))
		if old_axis != new_axis and Mastery.rank(actor,old_axis) > 0: Mastery.catchup(actor,new_axis)
	gear_bag.erase(item)
	if not previous.is_empty(): gear_bag.append(previous)
	actor.gear[slot] = item.duplicate(true)
	return true

func unequip_gear(index: int, slot: String) -> bool:
	if phase != "CAMP" or index < 0 or index >= party.size() or slot not in ["weapon","armour","shield","ring"]: return false
	var actor: Dictionary = party[index]
	if actor.gear[slot].is_empty(): return false
	gear_bag.append(actor.gear[slot])
	actor.gear[slot] = {}
	return true

func _presentation_action(actor: Dictionary, kind: String, target: Vector2i) -> Dictionary:
	if not active_intent_event.is_empty() and int(active_intent_event.get("actor_id",-1)) == int(actor.id):
		return active_intent_event.duplicate(true)
	var target_actor: Dictionary = at(target)
	var target_id := int(target_actor.get("id",-1)) if not target_actor.is_empty() else -1
	var choice := {"kind":kind,"cell":target}
	return IntentUI.adapt(actor,choice,target_id,_intent_id(actor,choice,target_id))

## One action by `actor`. `chain` runs the legacy follow-up (companions acting
## after the hero, round end on empty AP); auto_step passes false and drives
## the round itself.
func act_as(actor: Dictionary, kind: String, target: Vector2i, chain: bool = true) -> bool:
	if not on_floor() or not inside(target): return false
	# A follower can round a corner outside the selected leader's sight.
	# Only automatic movement bypasses the UI visibility gate; movement_cells
	# still checks adjacency, terrain and occupancy. Attacks keep their gate.
	# A recruited npc is a party member: only one still standing in the dungeon
	# on its own walks outside the party's sight.
	var following: bool = (resolving_companions and kind == "MOVE") or wanderer(actor)
	if not floor_state.visible.has(target) and not following: return false
	var display_event := _presentation_action(actor,kind,target) if presentation != null else {}
	if kind == "PYLON":
		if not BossAI.disable_pylon(self,target): return false
		if presentation != null: presentation.capture(self,actor.id,display_event)
		if chain: finish_player_action()
		return true
	if actor.hp <= 0 or actor.ap <= 0: return false
	var was: Vector2i = actor.pos
	if Abilities.DEFINITIONS.has(kind):
		if not Abilities.execute(self,actor,kind,target): return false
		record_action(actor,kind,target,was)
		actor.ap -= 1; check_battle_end()
		if presentation != null: presentation.capture(self,actor.id,display_event)
		if chain: finish_player_action()
		return true
	var victim := at(target)
	match kind:
		"WAIT":
			if target != actor.pos: return false
		"MOVE":
			# movement_cells indexes the party; an npc is not in it, so it checks its own step.
			if bool(actor.get("npc",false)):
				# The same two-step frontier the party walks, keyed by the npc's id.
				if target not in movement_cells(actor.id): return false
			else:
				if target not in movement_cells(party.find(actor)): return false
			actor.pos = target
			actor.hit_and_run = false
		"ATTACK":
			if victim.is_empty() or not victim.enemy or not attack_reach(actor,target,int(CombatStats.stats(self,actor).range)): return false
			if manual_mode: CombatRules.attack(self,actor,victim)
			else:
				var hit := TurnCore.physical(Growth.power(actor,"MELEE",18) * actor.attack_factor / 100, 1000, 0, 2)
				damage(victim,int(hit.damage),actor.id,"SLASH")
			# A skirmisher with nothing to shoot strikes once, then breaks away.
			if Stances.effective(actor) == "SKIRMISHER" and Stances.ranged_part(actor).is_empty(): actor.hit_and_run = true
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
	record_action(actor,kind,target,was)
	actor.ap -= 1
	check_battle_end()
	if presentation != null: presentation.capture(self,actor.id,display_event)
	if chain: finish_player_action()
	return true

## What this member just did, for the utility selector's commitment term: a
## member that kept walking the same way is nudged to keep going.
func record_action(actor: Dictionary, kind: String, target: Vector2i, was: Vector2i) -> void:
	actor.last_action_kind = kind
	actor.last_action_dir = Vector2i(signi(target.x-was.x),signi(target.y-was.y)) if kind == "MOVE" else Vector2i.ZERO

func finish_player_action() -> void:
	if not on_floor() or resolving_companions: return
	floor_state.observe(self)
	if not on_floor(): return
	var leader := selected
	resolving_companions = true
	if companions:
		for i in range(party.size()):
			if i == leader or party[i].hp <= 0 or not on_floor(): continue
			selected = i
			var choice: Dictionary = companion_choice(party[i])
			party[i].reservation = {}
			if act(choice.kind,choice.cell): party[i].last_action = choice.reason
	selected = leader
	resolving_companions = false
	if on_floor() and party[selected].ap <= 0: end_round()

func reservation_choice(actor: Dictionary) -> Dictionary:
	var order: Dictionary = actor.reservation
	if order.is_empty() or actor.hp <= 0 or actor.ap <= 0 or not on_floor(): return {}
	var cell: Vector2i = order.cell
	var def: Dictionary = Abilities.DEFINITIONS.get(order.kind,{})
	if order.kind == "ATTACK" or def.get("target","") == "ENEMY":
		var target: Dictionary = {}
		for enemy in enemies:
			if enemy.id == order.target_id and enemy.hp > 0: target = enemy; break
		if target.is_empty(): return {}
		if not def.is_empty():
			if not Abilities.legal(self,actor,order.kind,target.pos): return {}
		elif attack_preview(target.pos,actor.id).is_empty(): return {}
		cell = target.pos
	elif order.kind == "MOVE":
		if cell not in movement_cells(actor.id): return {}
	elif order.kind == "WAIT": cell = actor.pos
	elif not def.is_empty():
		if def.target == "SELF": cell = actor.pos
		if not Abilities.legal(self,actor,order.kind,cell): return {}
	else: return {}
	return {"kind":order.kind,"cell":cell,"reason":"직접 예약","reserved":true}

func reserve_action(index: int, kind: String, cell: Vector2i) -> bool:
	if not companions or not on_floor() or index < 0 or index >= party.size() or index == selected: return false
	var actor: Dictionary = party[index]
	var previous: Dictionary = actor.reservation
	actor.reservation = {"kind":kind,"cell":cell,"target_id":at(cell).get("id",-1)}
	if reservation_choice(actor).is_empty(): actor.reservation = previous; return false
	return true

func cancel_reservation(index: int) -> void:
	if index >= 0 and index < party.size(): party[index].reservation = {}

## The party command's answer for `actor`, or {} when the rules decide.
func command_choice(actor: Dictionary) -> Dictionary:
	if party_command == "HOLD_POSITION":
		if combat_enemies().any(func(e): return melee_reach(actor.pos,e.pos)): return {}
		return {"kind":"WAIT","cell":actor.pos,"reason":"자리 지키기"}
	if party_command == "STOP_ATTACK":
		var destination: Vector2i = rally_point()
		if actor.pos == destination or maxi(absi(actor.pos.x-destination.x),absi(actor.pos.y-destination.y)) <= 1:
			return {"kind":"WAIT","cell":actor.pos,"reason":"공격 중지"}
		var route: Dictionary = TurnCore.path(BOARD_SIDE,BOARD_SIDE,actor.pos,[destination],func(a,b): return can_step(a,b),func(_p): return 100)
		return {"kind":"MOVE","cell":route.path[1],"reason":"공격 중지"} if route.found and route.path.size() > 1 else {"kind":"WAIT","cell":actor.pos,"reason":"공격 중지"}
	if party_command == "RETREAT":
		var best: Vector2i = Tactics.retreat_cell(self,actor)
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
	return {}

func companion_choice(actor: Dictionary) -> Dictionary:
	var reserved := reservation_choice(actor)
	if not reserved.is_empty(): return reserved
	if companions:
		var ordered := command_choice(actor)
		if not ordered.is_empty(): return ordered
	if floor_state.safe(self): return floor_state.follow(self,actor)
	return Tactics.choose(self,actor)

## Read-only display preview for currently actionable party members. `choose`
## is deterministic and does not commit a decision; exhausted members are
## omitted instead of predicting their next round.
func companion_intent_snapshot() -> Array:
	var result: Array = []
	if not in_combat(): return result
	for actor in party:
		if actor.hp <= 0 or actor.ap <= 0 or phase != "BATTLE": continue
		var choice: Dictionary = command_choice(actor)
		if choice.is_empty(): choice = Tactics.choose(self,actor)
		var target_id := -1
		if choice.get("kind", "") in ["ATTACK", "PUSH"] or Abilities.DEFINITIONS.has(str(choice.get("kind", ""))):
			var target: Dictionary = at(choice.get("cell", actor.pos))
			target_id = int(target.get("id", -1)) if not target.is_empty() else -1
		var dto := IntentUI.adapt(actor,choice,target_id,_intent_id(actor,choice,target_id))
		if not dto.is_empty(): result.append(dto)
	return result

func _intent_id(actor: Dictionary, choice: Dictionary, target_id: int) -> int:
	var actor_id := int(actor.get("id",-1))
	var signature := "%s|%s|%d|%s|%d" % [str(choice.get("kind","")),str(actor.get("pos",Vector2i.ZERO)),int(actor.get("ap",0)),str(choice.get("cell",Vector2i.ZERO)),target_id]
	var cached: Dictionary = intent_preview_ids.get(actor_id,{})
	if str(cached.get("signature","")) != signature:
		intent_decision_serial += 1
		cached = {"signature":signature,"decision_id":intent_decision_serial}
		intent_preview_ids[actor_id] = cached
	return int(cached.decision_id)

## One rules-driven round: every living member spends its AP through the
## command or the rules, then the round ends. Game UI and simulator both call this.
func auto_step() -> bool:
	if not in_combat() or alive().is_empty(): return false
	battle_stats.rounds = int(battle_stats.get("rounds",0))+1
	# Snapshot before anyone acts: the stop events ask what changed *during* the
	# round, so a death or a cleared field inside this step must still be a delta.
	remember_round()
	for actor in party:
		var guard := 0
		# One roll per member per round, so one tally however many actions it spends.
		var noted := false
		while actor.hp > 0 and actor.ap > 0 and phase == "BATTLE" and guard < 4:
			guard += 1
			var choice: Dictionary = command_choice(actor)
			if choice.is_empty(): choice = Tactics.choose(self,actor)
			if not noted and str(choice.get("mistake","")) != "":
				note_mistake(actor,str(choice.mistake)); noted = true
			note_explain(actor,choice)
			# last_action reports what actually ran, not what was wanted.
			var target: Dictionary = at(choice.get("cell",actor.pos))
			intent_decision_serial += 1
			active_intent_event = IntentUI.adapt(actor,choice,int(target.get("id",-1)),intent_decision_serial)
			var acted := act_as(actor,str(choice.get("kind","WAIT")),choice.get("cell",actor.pos),false)
			if acted:
				actor.last_action = str(choice.get("reason","대기"))
			else:
				var wait_choice := {"kind":"WAIT","cell":actor.pos,"reason":"대기"}
				active_intent_event = IntentUI.adapt(actor,wait_choice,-1,_intent_id(actor,wait_choice,-1))
				if not act_as(actor,"WAIT",actor.pos,false): active_intent_event = {}; break
				actor.last_action = "대기"
			active_intent_event = {}
		# Did the stance get what it wanted this round? One tally per member.
		var row: Dictionary = member_stats(actor.id)
		if not row.is_empty() and actor.hp > 0:
			row.role_rounds = row.get("role_rounds",{"in_role":0,"total":0})
			row.role_rounds.total += 1
			if Stances.in_role(self,actor): row.role_rounds.in_role += 1
	if on_floor(): end_round()
	return true

## Who is fighting against their standing orders, noted at every battle start.
## It costs nothing now — the badge is only there to explain the mistakes the
## member is about to make.
func open_battle_conflicts() -> void:
	for actor in alive():
		actor.conflicted = Knobs.conflicted(actor)

## The last EXPLAIN_KEEP utility explanations of one member, oldest dropped
## first: why the selector picked what it picked, for the balance tools and the
## `--explain` frequency tables. Early returns (fire, hesitation, the retreat
## line) carry no `explain`, so the row is read with `.get`. The reason string
## is untouched by this (설계 §0.4) — this is statistics, not UI.
const EXPLAIN_KEEP := 20

func note_explain(actor: Dictionary, choice: Dictionary) -> void:
	var row: Dictionary = member_stats(actor.id)
	if row.is_empty(): return
	var log: Array = row.get("explains",[])
	log.append({"round":int(battle_stats.get("rounds",0)),"kind":str(choice.get("kind","")),
		"cell":choice.get("cell",actor.pos),"explain":choice.get("explain",[])})
	while log.size() > EXPLAIN_KEEP: log.remove_at(0)
	row.explains = log

## What the log calls each kind of mistake.
const MISTAKE_NAMES := {"HESITATE":"머뭇거림","RECKLESS":"무모함","REVERT":"자기 방식대로"}

## One mistake by `actor` this round: tallied for the battle report, and
## announced once per battle so the log says why the round went sideways.
## Only auto_step calls this — a choice that was merely previewed costs nothing.
func note_mistake(actor: Dictionary, kind: String) -> void:
	var row: Dictionary = member_stats(actor.id)
	if row.is_empty(): return
	var first: bool = int(row.get("mistakes",0)) == 0
	row.mistakes = int(row.get("mistakes",0))+1
	run_stats.mistakes = int(run_stats.mistakes)+1
	if first: message("%s · %s" % [actor.name,MISTAKE_NAMES.get(kind,"실수")])

## The end of a fight cancels the standing order: a retreat called against one
## pack must not still be running when the next one is sighted.
func end_battle_orders() -> void:
	party_command = "FOLLOW"
	command_target = -1

## Snapshot of what auto_stop_reason compares against next round.
func remember_round() -> void:
	auto.prev_threats = party_enemies().size()
	auto.prev_low = alive().filter(func(a): return a.hp*100/a.max_hp <= int(auto.hp_low)).map(func(a): return a.id)
	auto.prev_alive = alive().size()

## The first stop event that applies at the start of this round, or "".
## Every applicable event is considered in AUTO_STOPS priority order, so a
## disabled or suppressed one never swallows a lower-priority event.
func auto_stop_reason() -> String:
	if not on_floor(): return ""
	var threats: int = party_enemies().size()
	var living: Array = alive()
	var applies := {
		"BATTLE_START": threats > 0 and int(auto.prev_threats) == 0,
		"BATTLE_END": threats == 0 and int(auto.prev_threats) > 0,
		"DEATH": living.size() < int(auto.prev_alive),
		"ALLY_LETHAL": living.any(func(a): return Rules.lethal_threat(self,a) >= a.hp),
		"HP_LOW": living.any(func(a): return a.hp*100/a.max_hp <= int(auto.hp_low) and a.id not in auto.prev_low)}
	var hard := false
	for reason in AUTO_STOPS:
		if not applies[reason]: continue
		if reason in ["BATTLE_START","BATTLE_END","DEATH"]: hard = true
		if not bool(auto.stops.get(reason,false)): continue
		# Repeated alerts are suppressed for three rounds; the hard events never are.
		if reason in ["ALLY_LETHAL","HP_LOW"] and auto.last_stop.reason == reason and round_number-int(auto.last_stop.round) < 3:
			continue
		if reason == "BATTLE_END": end_battle_orders()
		auto.last_stop = {"reason":reason,"round":round_number}
		auto.stops_log.append(reason)
		# The report belongs to one battle: the conflicts are opened first so
		# that the fresh rows already carry who fights against their orders.
		if reason == "BATTLE_START": open_battle_conflicts(); reset_battle_stats()
		battle_stats.stops.append(reason)
		remember_round()
		return reason
	# Nothing was raised, but a hard event happened: consume it so it cannot re-fire.
	if hard:
		if applies.BATTLE_START: open_battle_conflicts(); reset_battle_stats()
		if applies.BATTLE_END: end_battle_orders()
		remember_round()
	for a in alive(): a.conflicted = Knobs.conflicted(a)
	return ""

func companion_previews() -> Array:
	var previews: Array = []
	if not companions or not on_floor(): return previews
	# `selected` is an index into the party, not an actor id.
	for index in range(party.size()):
		var actor: Dictionary = party[index]
		if index == selected or actor.hp <= 0 or actor.ap <= 0: continue
		var choice: Dictionary = companion_choice(actor).duplicate(true)
		choice.actor = actor.id
		previews.append(choice)
	return previews

## Town and safe ground only: a standing order is not rewritten mid-fight.
## Whether it conflicts with the personality is judged when it matters, not stored.
func set_knob(index: int, key: String, value: int) -> bool:
	if not safe_management() or in_combat(): return false
	if index < 0 or index >= party.size() or party[index].hp <= 0: return false
	if not Knobs.RANGE.has(key): return false
	var bounds: Array = Knobs.RANGE[key]
	if value < int(bounds[0]) or value > int(bounds[1]): return false
	party[index].knobs[key] = value
	return true

## The stance is a standing order like a knob: set on safe ground only. A lone
## member has nobody to cover, so it cannot be a guardian.
func set_stance(index: int, stance: String) -> bool:
	if not safe_management() or in_combat(): return false
	if index < 0 or index >= party.size() or party[index].hp <= 0 or stance not in Stances.IDS: return false
	if stance == "GUARDIAN" and party.size() == 1: return false
	party[index].stance = stance
	return true

## Who a guardian covers: another living member, or -1 to let it pick.
func set_protect(index: int, target_index: int) -> bool:
	if not safe_management() or in_combat(): return false
	if index < 0 or index >= party.size() or party[index].hp <= 0: return false
	if target_index != -1 and (target_index == index or target_index < 0 or target_index >= party.size() or party[target_index].hp <= 0): return false
	party[index].protect_id = target_index
	return true

func set_tactic(index: int, skill: String, policy: String) -> bool:
	if index < 0 or index >= party.size(): return false
	var allowed: Array = ["PROTECT","OFFENSE","MANUAL"] if skill == "PUSH" else ["DANGER","LOW_HP","MANUAL"] if skill == "GUARD" else []
	if policy not in allowed: return false
	party[index].tactics[skill] = policy
	# Compatibility for previous callers; the live editor uses common rules.
	for rule in party[index].rules:
		if rule.skill == skill:
			rule.enabled = policy != "MANUAL"
			# 엄호 has one condition, so every legacy GUARD policy maps onto it;
			# only the enabled flag still separates MANUAL from the rest.
			if skill == "GUARD": rule.when = "ALLY_LETHAL"; rule.target = "ALLY"
			else: rule.when = "CHARGING" if policy == "PROTECT" else "HP" if policy == "LOW_HP" else "DANGER" if policy == "DANGER" else "ALWAYS"
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
	message("방전")

func conductive(point: Vector2i) -> bool:
	return tile(point).terrain in ["metal", "water"] or tile(point).wet >= 25

func roll_part(enemy: Dictionary) -> void:
	if not enemy.enemy or enemy.hp > 0 or enemy.get("part_rolled",false): return
	enemy.part_rolled = true
	for actor in alive():
		if manual_mode:
			if gain_level_xp(actor,18+depth*8) > 0: message(actor.name+" · 레벨 %d" % actor.level)
		elif Growth.gain(actor,25) > 0: message(actor.name+" · 레벨 %d" % actor.growth.level)
	var id: String = str(enemy.get("part_id",""))
	if not Abilities.DEFINITIONS.has(id): return
	var chance: int = Abilities.DROP_PERCENT
	if Hexaco.sample(seed_value,depth*10000+enemy.id,"essence",100) >= chance: return
	parts_bag[id] = int(parts_bag.get(id,0))+1
	battle_stats.drops[id] = int(battle_stats.drops.get(id,0))+1
	message(Abilities.DEFINITIONS[id].item+" 획득")

func gain_level_xp(actor: Dictionary, amount: int) -> int:
	var before := int(actor.get("level",1))
	actor.level_xp = int(actor.get("level_xp",0))+maxi(0,amount)
	while actor.level < 12 and actor.level_xp >= actor.level*actor.level*65:
		actor.level += 1
		actor.max_hp += 4; actor.hp = mini(actor.max_hp,actor.hp+4)
		actor.max_mp += 2; actor.mp = mini(actor.max_mp,actor.mp+2)
	return actor.level-before

func grant_gear(item: Dictionary) -> void:
	if item.is_empty(): return
	gear_bag.append(item.duplicate(true))
	message(str(item.get("type","장비"))+" 획득")

func spend_growth(index: int, id: String, stat: bool = false) -> bool:
	if not safe_management() or index < 0 or index >= party.size() or party[index].hp <= 0: return false
	return Growth.spend(party[index],id,stat)

func reset_rules(index: int) -> void:
	var actor: Dictionary = party[index]
	actor.rules = Rules.defaults(); actor.basic_target = Rules.BASIC_TARGET_DEFAULT
	for id in actor.equipped_abilities:
		if Abilities.DEFINITIONS.has(id): actor.rules.append(Abilities.default_rule(id))

## Town only: a part leaves the bag for a slot; the slot's old part returns to the bag.
func equip_part(index: int, slot: int, id: String) -> bool:
	if phase != "CAMP" or index < 0 or index >= party.size() or slot < 0 or slot >= 2: return false
	var actor: Dictionary = party[index]
	if actor.hp <= 0 or not Abilities.DEFINITIONS.has(id) or int(parts_bag.get(id,0)) <= 0: return false
	if id in actor.equipped_abilities: return false
	var old: String = str(actor.equipped_abilities[slot])
	if not old.is_empty(): unequip_part(index,slot)
	parts_bag[id] -= 1
	actor.equipped_abilities[slot] = id
	actor.reservation = {}
	if not actor.rules.any(func(r): return r.skill == id): actor.rules.append(Abilities.default_rule(id))
	return true

func unequip_part(index: int, slot: int) -> bool:
	if phase != "CAMP" or index < 0 or index >= party.size() or slot < 0 or slot >= 2: return false
	var actor: Dictionary = party[index]
	var old: String = str(actor.equipped_abilities[slot])
	if actor.hp <= 0 or old.is_empty(): return false
	actor.equipped_abilities[slot] = ""
	parts_bag[old] = int(parts_bag.get(old,0))+1
	actor.rules = actor.rules.filter(func(r): return r.skill != old)
	actor.reservation = {}
	return true

## Playtest helper: one of every catalog part in the bag, so loadouts can be tried without farming.
func grant_test_loadout() -> bool:
	if party.is_empty(): return false
	var added := 0
	for id in Abilities.DEFINITIONS:
		if int(parts_bag.get(id,0)) > 0: continue
		parts_bag[id] = 1; added += 1
	message("시험 로드아웃 · 이미 전부 보유" if added == 0 else "시험 로드아웃 · 파츠 %d종 지급 — 파츠 탭에서 장착하세요." % added)
	return true

## The battle-test arenas: the six rosters the simulator measures, plus the
## seat the player fills in by hand.
static var ARENA_PRESETS: Dictionary = load_arena_presets()

static func load_arena_presets() -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/balance_experiments.json"))
	var result: Dictionary = {}
	for id in data.experiments.action_economy.arenas:
		var row: Dictionary = data.experiments.action_economy.arenas[id]
		result[id] = {"members":row.members.duplicate(true),"label":id}
	result["custom"] = {"members":[],"label":"직접 구성"}
	return result

## A throwaway floor battle: full health, every part available, the members'
## stances and slots set as asked, dropped into an arena the simulator also
## uses. The town session is never involved.
static func arena_test(p_seed: int, party_size: int, arena: Dictionary, members: Array):
	var s = new(p_seed,true,party_size > 1,true,party_size)
	s.grant_test_loadout()
	for i in range(s.party.size()):
		var actor: Dictionary = s.party[i]
		var setup: Dictionary = members[i] if i < members.size() else {}
		var stance: String = str(setup.get("stance",actor.stance))
		if stance == "GUARDIAN" and party_size == 1: stance = "CHARGER"
		if stance in Stances.IDS: actor.stance = stance
		actor.equipped_abilities = ["",""]; actor.rules = []
		var parts: Array = setup.get("parts",["",""])
		for slot in range(2):
			var id: String = str(parts[slot]) if slot < parts.size() else ""
			if Abilities.DEFINITIONS.has(id) and id not in actor.equipped_abilities:
				actor.equipped_abilities[slot] = id; actor.rules.append(Abilities.default_rule(id))
	var spec: Dictionary = preload("res://expedition/sim/encounter_arena.gd").DEFAULT_SPEC.duplicate(true)
	spec.members = arena.members.map(func(m): return {"species_id":m[0],"role":m[1]})
	var theme: Dictionary = preload("res://expedition/floor_generator.gd").theme("F1_RUINS")
	s.simulation_arena = true
	Floor.apply(s,theme,preload("res://expedition/sim/encounter_arena.gd").layout(spec,theme,p_seed))
	arena_contact(s)
	s.reset_battle_stats()
	s.auto.prev_threats = 0
	return s

## The sim's arena drops the party at the door, out of sight of a roster placed
## as far from it as the room allows. A battle test is the fight, not the walk
## to it: the party closes in before round one so the first stop is 전투 시작.
static func arena_contact(s) -> void:
	var state = s.floor_state
	for _step in range(40):
		state.observe(s)
		if not state.safe(s): break
		var moved := false
		for actor in s.party:
			var foes: Array = s.enemies.filter(func(e): return e.hp > 0)
			if foes.is_empty(): return
			foes.sort_custom(func(a,b): return s.distance(actor.pos,a.pos) < s.distance(actor.pos,b.pos))
			var goal: Vector2i = foes[0].pos
			var delta := Vector2i(signi(goal.x-actor.pos.x),signi(goal.y-actor.pos.y))
			for cell in [actor.pos+delta,actor.pos+Vector2i(delta.x,0),actor.pos+Vector2i(0,delta.y)]:
				if cell == actor.pos or not s.can_step(actor.pos,cell): continue
				actor.pos = cell; moved = true; break
		if not moved: break
	state.observe(s)

func enemy_attack_effect(enemy: Dictionary, cells: Array, area: bool = false) -> void:
	if cells.is_empty(): return
	effects.append({"kind":"ENEMY_ATTACK","from":enemy.pos,"cell":cells[0],
		"cells":cells.duplicate(),"area":area,"amount":0,"form":"IMPACT"})
	if presentation == null and effects.size() > 32: effects.pop_front()

static func subject_name(value: String) -> String:
	var last := value.unicode_at(value.length()-1) if not value.is_empty() else 0
	return value+("이" if last >= 0xAC00 and last <= 0xD7A3 and (last-0xAC00)%28 != 0 else "가")

## Follows the 엄호 chain from `target` to the member who actually takes the
## hit. A protector who has fallen or stepped out of contact covers nobody, and
## a mutual guard collapses: the first member the chain revisits eats the hit
## itself, at half through its own `guarded`, and nothing is redirected.
func protection_recipient(target: Dictionary) -> Dictionary:
	var current: Dictionary = target
	var seen: Dictionary = {current.id:true}
	while true:
		var guardian: int = int(current.get("protected_by",-1))
		if guardian < 0: return current
		var next: Dictionary = {}
		for mate in party+npcs:
			if mate.id == guardian and mate.hp > 0 and melee_reach(mate.pos,current.pos): next = mate; break
		if next.is_empty(): return current
		if seen.has(next.id): return next
		seen[next.id] = true
		current = next
	return current

func actor_by_id(id: int) -> Dictionary:
	for actor in party+npcs+enemies:
		if actor.id == id: return actor
	return {}

func damage(target: Dictionary, amount: int, source: int, form: String) -> int:
	return CombatRules.damage(self,actor_by_id(source),target,amount,form)

func after_damage(target: Dictionary, amount: int, source: int, form: String) -> int:
	if target.hp <= 0: return 0
	var attacker: Dictionary = actor_by_id(source)
	# Retaliation is plain damage: it never triggers passives again.
	var passive_hit: bool = form != "RETALIATE"
	if passive_hit and not attacker.is_empty(): amount = Passives.outgoing(self,attacker,target,amount)
	# 엄호: the protector steps in front. Counted and logged once, and only when
	# the hit really lands on somebody else.
	var recipient: Dictionary = protection_recipient(target)
	var covered: bool = recipient.id != target.id
	if covered:
		var cover_row: Dictionary = member_stats(recipient.id)
		if not cover_row.is_empty(): cover_row.covers += 1
		message("%s %s 대신 맞습니다." % [subject_name(recipient.name),target.name])
		target = recipient
	if target.get("shield",false):
		message("보호막 · 피해 무효"); return 0
	if target.get("iron_guard",false): amount = maxi(1,amount / 4)
	elif target.get("guarded",false): amount = maxi(1,amount / 2)
	if not manual_mode and not target.enemy: amount = Growth.incoming(target,amount)
	if passive_hit: amount = Passives.incoming(self,target,amount)
	# A solo floor always grants one action; collapse instead exposes the hero
	# to one extra point of damage. Calming supplies can prevent this penalty.
	if party.size() == 1 and not target.enemy and target.stress >= 150 and amount > 0: amount += 1
	serial += 1
	var lost := mini(int(target.hp), amount)
	var source_cell: Vector2i = target.pos
	var source_name: String = {"FIRE":"불길","ELECTRIC":"방전","POISON":"독"}.get(form,"함정")
	if not attacker.is_empty(): source_cell = attacker.pos; source_name = attacker.name
	var effect := {"from":source_cell,"cell":target.pos,"amount":lost,"form":form}
	effects.append(effect)
	if presentation == null and effects.size() > 32: effects.pop_front()
	var dealt_row: Dictionary = member_stats(source) if not attacker.is_empty() and not attacker.enemy else {}
	if not dealt_row.is_empty(): dealt_row.dealt += lost
	var taken_row: Dictionary = member_stats(target.id) if not target.enemy else {}
	if not taken_row.is_empty():
		taken_row.taken += lost
		if covered: taken_row.redirected += lost
	target.hp -= lost; Body.sync(target)
	if on_floor() and lost > 0: noise.append(target.pos)
	if target.enemy and lost > 0: Floor.MonsterAI.on_hit(self,target)
	if not target.enemy:
		var entered_crisis: bool = (target.hp+lost)*4 > target.max_hp and target.hp*4 <= target.max_hp
		if entered_crisis:
			remember_important(target,"SELF_HARM",target.id+1,source+1,800 if target.hp <= 0 else 750)
		stress(target, 5 + lost / 2)
		if target.hp <= 0 and wanderer(target):
			target.state = "DEAD"; target.awake = false; target.activity = ""
			if pending_offer == int(target.id): pending_offer = -1
			# A stranger's death is not a comrade's: whoever watched it happen is
			# shaken, and someone the npc owed a debt to feels it twice.
			var watched: bool = floor_state.visible.has(target.pos)
			for ally in alive():
				if not watched: continue
				stress(ally,5)
				if int(target.memory.salience_for_subject(ally.id+1,["AID_RECEIVED"])) > 0: stress(ally,10)
		elif target.hp <= 0:
			# A recruited member falls as a comrade; the roster still records it.
			if target.get("npc",false): target.state = "DEAD"; target.awake = false; target.activity = ""
			if not taken_row.is_empty(): taken_row.downed = true
			for ally in alive():
				remember_important(ally,"ALLY_LOST",target.id+1,source+1,900)
				stress(ally, 22)
	message("%s %s에게 %d의 피해를 주었습니다.%s" % [subject_name(source_name),target.name,lost," "+subject_name(target.name)+" 쓰러졌습니다." if target.hp <= 0 else ""])
	if passive_hit: Passives.after_hit(self,target,attacker,form)
	if target.enemy and target.hp <= 0:
		Mastery.award(party+npcs,int(target.id),18+depth*8)
		battle_stats.kills = int(battle_stats.get("kills",0))+1
		run_stats.kills = int(run_stats.kills)+1
		score += 10
		if bool(Encounters.species(str(target.get("species_id",""))).get("beast",false)) and Hexaco.sample(seed_value,depth*1000+target.id,"beast_food",100) < 25:
			food += 1; message("고기 획득 · 식량 +1")
		if target.get("boss",false):
			grant_part(str(target.part_id)); score += 100
			var books: Array = Spells.IMPLEMENTED.filter(func(id): return id not in party[0].spells)
			if not books.is_empty(): learn_spell(0,str(books[Hexaco.sample(seed_value,depth*1000+target.id,"boss_book",books.size())]))
		else: roll_part(target)
	if not target.enemy and target.id == 0 and target.hp <= 0: check_battle_end()
	return lost

func plan_enemies() -> void:
	Floor.MonsterAI.plan(self)

func enemy_attack_turn(enemy: Dictionary) -> void:
	_enemy_attack_turn(enemy)
	if presentation != null: presentation.capture(self,enemy.id)

func _enemy_attack_turn(enemy: Dictionary) -> void:
	if phase != "BATTLE" or enemy.hp <= 0 or alive().is_empty(): return
	floor_state.enemy_turn(self,enemy)

func end_round() -> bool:
	if not on_floor(): return false
	world_time += 100
	# The floor's NPCs take their round before the monsters do.
	# Everyone listens to this round's noise first; only then is it cleared, so
	# that what the npcs themselves do is heard next round and nothing else is
	# lost down an early return below.
	var awake: Array = []
	for npc in npcs:
		if npc.hp > 0 and NpcAI.sense(self,npc): awake.append(npc)
	noise.clear()
	for npc in awake: NpcAI.turn(self,npc)
	for enemy in enemies:
		enemy_attack_turn(enemy)
		if party[0].hp <= 0: break
	if party[0].hp <= 0: check_battle_end(); return true
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
	# The round's guards end with the round, win or lose: a cleared room must not
	# carry 엄호 into EXPLORE.
	for actor in party+npcs: actor["guarded"] = false; actor["protected_by"] = -1
	check_battle_end()
	if not on_floor(): return true
	# Round-start passives run for the fighters only: the whole 64×64 roster is
	# not in this battle, so a distant monster must not regenerate off-screen.
	for actor in friends()+party_enemies(): Passives.round_start(self,actor)
	# Cooldowns and 철벽 belong to everyone fighting beside the party; stress, the
	# hunger clock and the action budget stay the party's own bookkeeping.
	for actor in friends():
		actor.iron_guard = false
		for id in actor.cooldowns: actor.cooldowns[id] = maxi(0,int(actor.cooldowns[id])-1)
	for actor in alive():
		if not floor_state.safe(self): stress(actor,2)
		actor.ap = action_budget(actor)
	round_number += 1
	floor_state.observe(self)
	if companions and party[selected].hp <= 0: selected = party.find(alive()[0])
	plan_enemies()
	return true

func check_battle_end() -> void:
	if on_floor() and party[0].hp <= 0: phase = "DEFEAT"; message("원정 종료")

func use_supply(slot: int, target: Vector2i = Vector2i(-1,-1), recipient: int = -1) -> bool:
	if phase not in ["EXPLORE","BATTLE","CAMP"] or slot < 0 or slot >= supplies.size() or supplies[slot] <= 0: return false
	var user: Dictionary = party[selected]
	if recipient < -1 or recipient >= party.size(): return false
	var actor: Dictionary = party[selected if recipient == -1 else recipient]
	if actor.hp <= 0 or user.hp <= 0 or on_floor() and user.ap <= 0: return false
	if slot in [3,4]:
		if not on_floor() or recipient != -1: return false
		supplies[slot] -= 1
		if not act("FIRE" if slot == 3 else "WATER",target): supplies[slot] += 1; return false
	else:
		if slot == 0 and actor.hp >= actor.max_hp: return false
		if slot == 1 and actor.stress == 0: return false
		if slot == 2 and actor.stress == 0 and actor.hp >= actor.max_hp: return false
		match slot:
			0: actor.hp = mini(actor.max_hp,actor.hp+20); Body.heal(actor)
			1: stress(actor,-25)
			2: stress(actor,-10); actor.hp = mini(actor.max_hp,actor.hp+5)
		supplies[slot] -= 1
		if on_floor(): user.ap -= 1
	message("%s · %s 사용" % [actor.name,SUPPLY_NAMES[slot]])
	if slot not in [3,4] and on_floor():
		if manual_mode:
			user.ap = 1; Scheduler.advance(self,100)
		else: finish_player_action()
	return true
