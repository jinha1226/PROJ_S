extends RefCounted
## Descent run host: persistent actors, floor terrain, enemies and intent.
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
const Memory = preload("res://sim/party_memory_state.gd")
const Body = preload("res://game/rebuilt/body_bridge.gd")
const TurnCore = preload("res://sim/turn_engine.gd")
const ElementRules = preload("res://sim/environment_rules.gd")
const NpcRoster = preload("res://expedition/actors/npc_roster.gd")
const NpcEssences = preload("res://expedition/actors/npc_essences.gd")
const NpcAI = preload("res://expedition/actors/npc_ai.gd")
const NpcHostility = preload("res://expedition/actors/npc_hostility.gd")
const Recruit = preload("res://expedition/actors/npc_recruit.gd")
var BOARD_SIDE := 64
const Floor = preload("res://expedition/level/continuous_floor.gd")
const Zones = preload("res://expedition/level/zones.gd")
const Encounters = preload("res://expedition/level/encounter_builder.gd")
var floor_state
const Tactics = preload("res://expedition/ai/tactical_action_selector.gd")
const Knobs = preload("res://expedition/ai/knobs.gd")
const Stances = preload("res://expedition/ai/stances.gd")
const Rules = preload("res://expedition/ai/tactic_rules.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const IntentUI = preload("res://expedition/ui/companion_intent_ui.gd")
const CombatStats = preload("res://expedition/combat/combat_stats.gd")
const CombatRules = preload("res://expedition/combat/combat_rules.gd")
const Scheduler = preload("res://expedition/time/scheduler.gd")
const Spells = preload("res://expedition/spells/spells.gd")
const Passives = preload("res://expedition/combat/passives.gd")
const Families = preload("res://expedition/combat/families.gd")
const Statuses = preload("res://expedition/combat/statuses.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
const Reactions = preload("res://expedition/combat/reactions.gd")
const Downed = preload("res://expedition/combat/downed.gd")
const Hunt = preload("res://expedition/progression/hunt.gd")
## Run modules: the session keeps the state and hands each group of verbs to
## its own file. Every public name here stays on the session as a delegate.
const Camp = preload("res://expedition/run/camp.gd")
const Descent = preload("res://expedition/run/descent.gd")
const Gear = preload("res://expedition/items/gear.gd")
const Consumables = preload("res://expedition/items/consumables.gd")
const AutoBattle = preload("res://expedition/run/autobattle.gd")
const Orders = preload("res://expedition/run/orders.gd")
const ArenaTest = preload("res://expedition/run/arena_test.gd")
const RunResult = preload("res://expedition/run/run_result.gd")
var parts_bag: Dictionary = {}
var essence_seen: Dictionary = {}
var events: Array = []
## Forwarded for callers that read it on the session; defined in `Camp`.
const PREPARED_SLOTS := Camp.PREPARED_SLOTS
const STARTING_PARTS := {}
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
## Forwarded for callers that read it on the session; defined in `AutoBattle`.
const AUTO_STOPS := AutoBattle.AUTO_STOPS
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
var action_serial := 0
var gear_bag: Array = []
var manual_mode := false
var selected := 0
var intents: Array = []
var effects: Array = []
## Utility selector: whether `Lookahead.predict` answers the `la_*`
## considerations. On by default; a simulation tool can turn it off to compare.
var lookahead_enabled := true
var bag: Dictionary = {}
var known: Dictionary = {}
var appearances: Dictionary = {}
var pending_choice: Dictionary = {}
const Curios = preload("res://expedition/items/curios.gd")
const BossAI = preload("res://expedition/actors/boss_ai.gd")

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
	appearances = Consumables.shuffle_appearances(p_seed)
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
		"equipped_abilities":[""],"cooldowns":{},"iron_guard":false,
		"essences":{},"essence_spells":{},"pool_bonus":{"hp":0,"mp":0},
		"protected_by":-1,
		"gear":{"weapon":{},"armour":{},"shield":{},"ring":{}},
		"mp":18,"max_mp":18,"usage":{},"statuses":{},"spells":[],"prepared":[],
		"buffs":{},"opinions":{},
		"level":1,"level_xp":0,"str_bonus":0,"sleep_until":0,"ready_at":0,
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

func reset_battle_stats() -> void: RunResult.reset_battle_stats(self)

func member_stats(id: int) -> Dictionary: return RunResult.member_stats(self,id)

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
	return alive()+npcs.filter(func(n): return n.hp > 0 and n.awake and side_of(n) == 0)+enemies.filter(func(e): return e.hp > 0 and dominated(e))

## A dominated monster fights for the party while the spell holds. The `enemy`
## flag never moves: only this clock decides which side it is counted on.
func dominated(actor: Dictionary) -> bool:
	return int(actor.get("dominated_until",0)) > time

## Which side an actor fights on this tick: 0 the party's, 1 the dungeon's.
## Domination moves a monster across without touching its `enemy` flag, so
## everything that used to read `enemy` to tell friend from foe reads this.
func side_of(actor: Dictionary) -> int:
	if wanderer(actor) and not actor.get("summoned",false): return 1 if actor.get("hostile",false) else 0
	return 1 if bool(actor.get("enemy",false)) != dominated(actor) else 0

## Whom this actor fights. A dominated monster turns on its own kind.
func hostiles_of(actor: Dictionary) -> Array:
	var side: int = side_of(actor)
	if bool(actor.get("enemy",false)) and side == 1:
		return (friends()+npcs.filter(func(n): return n.hp > 0 and n.awake and n.get("hostile",false))).filter(func(a): return int(a.id) != int(actor.id))
	if side == 1: return friends().filter(func(a): return int(a.id) != int(actor.id) and side_of(a) == 0)
	return (enemies+npcs).filter(func(e): return e.hp > 0 and int(e.id) != int(actor.id) and side_of(e) == 1)

func companion_rows() -> Array: return RunResult.companion_rows(self)

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
	if phase != "EXPLORE" or pending_offer >= 0 or npc.state != "MET" or npc.get("hostile",false) or npc_clock() < int(npc.get("offered_until",-99)): return false
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

func depart() -> bool: return Descent.depart(self)

func stress(actor: Dictionary, amount: int) -> void:
	var trauma := int(actor.memory.strongest(["SELF_HARM", "ALLY_LOST"]).get("salience", 0)) / 200
	var change := amount
	if amount > 0: change = maxi(1, amount * (650 + actor.profile.value("E")) / 1000 + trauma)
	# The solo run halves the hero's own stress; a dungeon NPC feels it whole.
	if amount > 0 and party.size() == 1 and not actor.get("npc",false): change = ceili(change*0.5)
	actor.stress = clampi(actor.stress + change, 0, 200)
	actor.condition = "붕괴" if actor.stress >= 150 else "불안" if actor.stress >= 100 else "평온"





func can_camp() -> String: return Camp.can_camp(self)

func camp() -> bool: return Camp.camp(self)

func end_camp() -> bool: return Camp.end_camp(self)

func stairs_sealed() -> bool: return Descent.stairs_sealed(self)

func descend() -> bool: return Descent.descend(self)

func grant_part(id: String) -> void: Gear.grant_part(self,id)

func push_event(event: Dictionary) -> void:
	events.append(event)
	while events.size() > 32: events.pop_front()

func absorb_essence(index: int, id: String) -> String: return Gear.absorb_essence(self,index,id)

func choose_essence_spell(index: int, essence_id: String, spell_id: String) -> bool: return Gear.choose_essence_spell(self,index,essence_id,spell_id)

func grant_item(kind: String, count: int = 1, identified: bool = false) -> void: Consumables.grant(self,kind,count,identified)
func use_item(kind: String, target: Vector2i = Vector2i(-1,-1), recipient: int = -1) -> bool: return Consumables.use(self,kind,target,recipient)
func identify_item(kind: String) -> void: Consumables.identify(self,kind)
func resolve_choice(option: String) -> bool: return Consumables.resolve_choice(self,option)
func item_label(kind: String) -> String: return Consumables.label(self,kind)

func start_battle() -> void:
	phase = "BATTLE"; round_number = 1
	Families.battle_start(self)
	for actor in party:
		actor.reservation = {}; actor.ap = action_budget(actor)
		actor["guarded"] = false; actor["protected_by"] = -1
	selected = party.find(alive()[0]); plan_enemies()

func solo_rule(key: String) -> int: return AutoBattle.solo_rule(self,key)

func action_budget(actor: Dictionary) -> int: return AutoBattle.action_budget(self,actor)

func tile(point: Vector2i) -> Dictionary:
	return tiles[point.y * BOARD_SIDE + point.x]

func inside(point: Vector2i) -> bool:
	return point.x >= 0 and point.y >= 0 and point.x < BOARD_SIDE and point.y < BOARD_SIDE

func at(point: Vector2i) -> Dictionary:
	for actor in party + enemies + npcs:
		if actor.hp > 0 and actor.pos == point: return actor
	return {}

func downed_at(point: Vector2i) -> Dictionary:
	return Downed.at(self,point)

func is_free(point: Vector2i) -> bool:
	return inside(point) and tile(point).terrain != "wall" and at(point).is_empty() and downed_at(point).is_empty() and int(tile(point).get("wall_until",0)) <= time

func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func melee_reach(a: Vector2i, b: Vector2i) -> bool:
	if not inside(a) or not inside(b) or a == b or maxi(absi(a.x-b.x),absi(a.y-b.y)) != 1: return false
	if tile(b).terrain == "wall": return false
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

## The five field orders shared with the party command UI. Choosing an order
## changes the next companion decision; it never spends the hero's turn.
func issue_party_command(command: String, target_id: int = -1) -> bool:
	if not on_floor() or command not in ["ATTACK_TARGET","RETREAT","STOP_ATTACK","HOLD_POSITION","FOLLOW"]: return false
	if command == "ATTACK_TARGET":
		if not in_combat() or not combat_enemies().any(func(enemy): return enemy.id == target_id and floor_state.visible.has(enemy.pos)): return false
	elif target_id != -1: return false
	elif command == "RETREAT" and not in_combat(): return false
	party_command = command
	command_target = target_id if command == "ATTACK_TARGET" else -1
	return true

func can_swap_formation() -> bool: return Orders.can_swap_formation(self)

func swap_formation(a: int, b: int) -> bool: return Orders.swap_formation(self,a,b)

func safe_management() -> bool:
	return phase in ["CAMP","EXPLORE"]

func auto_attack() -> bool: return AutoBattle.auto_attack(self)

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
		if old_victim.is_empty() or not (old_victim.enemy or wanderer(old_victim) and not old_victim.get("summoned",false)): return {}
		var old_actor: Dictionary = party[selected] if actor_index < 0 else (party[actor_index] if actor_index < party.size() else actor_by_id(actor_index))
		if old_actor.is_empty(): return {}
		var old_hit := TurnCore.physical(StatSheet.legacy_power(old_actor,"MELEE",18) * old_actor.attack_factor / 100, 1000, 0, 2)
		var old_amount := int(old_hit.damage)
		if old_victim.get("guarded",false): old_amount = maxi(1,old_amount/2)
		if old_victim.get("shield",false): old_amount = 0
		return {"actor":old_actor.id,"target":old_victim.id,"cell":target,"name":old_victim.name,"chance":100,"damage":old_amount,"damage_min":old_amount,"damage_max":old_amount,"time":100}
	var victim := at(target)
	if victim.is_empty() or not (victim.enemy or wanderer(victim) and not victim.get("summoned",false)): return {}
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
	if not pending_choice.is_empty(): return false
	if manual_mode: return submit(kind,target)
	return act_as(party[selected],kind,target,true)

func action_cost(actor: Dictionary, kind: String, target: Vector2i, _value: String = "") -> int:
	var cost := 100
	match kind:
		"MOVE", "SWAP":
			if inside(target): cost = CombatRules.move_time(self,actor,target)
		"ATTACK":
			cost = int(CombatStats.stats(self,actor).delay)
			cost = TagSets.attack_delay(actor,cost,str(CombatStats.stats(self,actor).trait) == "ranged")
		_:
			if Abilities.has(kind): cost = int(Abilities.definition(kind).get("delay",100))
	var statuses: Dictionary = actor.get("statuses",{})
	if kind != "MOVE":
		if statuses.has("slow"): cost = cost*3/2
		if statuses.has("haste"): cost = cost*2/3
	return maxi(40,cost)

func submit(kind: String, target: Vector2i, value: String = "") -> bool:
	if not pending_choice.is_empty(): return false
	if not on_floor() or party.is_empty() or party[0].hp <= 0: return false
	manual_mode = true
	var actor: Dictionary = party[0]
	actor.ap = 1
	if not can_submit(actor,kind,target,value): return false
	if kind == "SWAP":
		# Keep the tapped ally in place until the exchange; a due companion turn
		# in flush_ready could otherwise move it before this action resolves.
		var swapped_ally: Dictionary = at(target)
		var swap_cost := action_cost(actor,kind,target)
		if not act_as(actor,kind,target,false): return false
		swapped_ally.ready_at = maxi(int(swapped_ally.ready_at),time+swap_cost)
		actor.ap = 1
		return Scheduler.advance(self,swap_cost)
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
	if Abilities.has(kind): return Abilities.legal(self,actor,kind,target)
	match kind:
		"WAIT": return target == actor.pos
		"MOVE": return not status_blocks(actor,kind) and target in movement_cells(0)
		"SWAP":
			var ally: Dictionary = at(target)
			return not status_blocks(actor,"MOVE") and walk_reach(actor.pos,target) and ally in party and ally != actor
		"RESCUE": return Downed.can_rescue(self,actor,downed_at(target))
		"ATTACK": return not status_blocks(actor,kind) and not attack_preview(target,0).is_empty()
		"LEVER": return BossAI.lever_ready(self,actor,target)
		"FIRE", "WATER", "ELECTRIC": return distance(actor.pos,target) <= 4 and tile(target).terrain != "wall"
	return false

func cast(id: String, target: Vector2i) -> bool:
	return submit("CAST",target,id)

## 빙결 and 속박 stop the feet; only 빙결 also stops the arms. `Statuses` holds
## the body.
func status_blocks(actor: Dictionary, kind: String) -> bool: return Statuses.blocks(actor,kind)

func gear_slot(item: Dictionary) -> String: return Gear.gear_slot(self,item)

func equip_gear(index: int, item: Dictionary) -> bool: return Gear.equip_gear(self,index,item)

func unequip_gear(index: int, slot: String) -> bool: return Gear.unequip_gear(self,index,slot)

func _presentation_action(actor: Dictionary, kind: String, target: Vector2i) -> Dictionary:
	if not active_intent_event.is_empty() and int(active_intent_event.get("actor_id",-1)) == int(actor.id):
		return active_intent_event.duplicate(true)
	var target_actor: Dictionary = at(target)
	var target_id := int(target_actor.get("id",-1)) if not target_actor.is_empty() else -1
	var choice := {"kind":kind,"cell":target}
	return IntentUI.adapt(actor,choice,target_id,AutoBattle._intent_id(self,actor,choice,target_id))

## One action by `actor`. `chain` runs the legacy follow-up (companions acting
## after the hero, round end on empty AP); auto_step passes false and drives
## the round itself.
func act_as(actor: Dictionary, kind: String, target: Vector2i, chain: bool = true) -> bool:
	Reactions.begin_action(self)
	if not on_floor() or not inside(target): return false
	if not pending_choice.is_empty(): return false
	# A follower can round a corner outside the selected leader's sight.
	# Only automatic movement bypasses the UI visibility gate; movement_cells
	# still checks adjacency, terrain and occupancy. Attacks keep their gate.
	# A recruited npc is a party member: only one still standing in the dungeon
	# on its own walks outside the party's sight.
	var following: bool = (resolving_companions and kind in ["MOVE","RESCUE"]) or wanderer(actor)
	if not floor_state.visible.has(target) and not following: return false
	var display_event := _presentation_action(actor,kind,target) if presentation != null else {}
	if kind == "LEVER":
		if not BossAI.pull_lever(self,actor,target): return false
		if presentation != null: presentation.capture(self,actor.id,display_event)
		if chain: finish_player_action()
		return true
	if actor.hp <= 0 or actor.ap <= 0 or status_blocks(actor,kind): return false
	var was: Vector2i = actor.pos
	if Abilities.has(kind):
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
			if actor in party: Consumables.pickup(self,actor)
			actor.hit_and_run = false
		"SWAP":
			if status_blocks(actor,"MOVE") or actor not in party or victim not in party or victim == actor or not walk_reach(was,target): return false
			victim.pos = was
			actor.pos = target
			actor.hit_and_run = false
			victim.hit_and_run = false
		"RESCUE":
			if not Downed.rescue(self,actor,downed_at(target)): return false
		"ATTACK":
			if victim.is_empty() or victim.hp <= 0 or not attack_reach(actor,target,int(CombatStats.stats(self,actor).range)): return false
			var assault: bool = actor in party and wanderer(victim) and not victim.get("summoned",false)
			var npc_self_defense: bool = wanderer(actor) and victim.enemy
			if not assault and not npc_self_defense and side_of(actor) == side_of(victim): return false
			if assault: NpcHostility.provoke(self,victim,actor)
			if manual_mode and melee_reach(was,target):
				effects.append({"kind":"ATTACK_SWING","from":was,"cell":target,"amount":0,"form":"SLASH"})
			if manual_mode: CombatRules.attack(self,actor,victim)
			else:
				if not actor.enemy and victim.enemy: Hunt.record(actor,int(victim.id))
				var hit := TurnCore.physical(StatSheet.legacy_power(actor,"MELEE",18) * actor.attack_factor / 100, 1000, 0, 2)
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
	actor.last_action_dir = Vector2i(signi(target.x-was.x),signi(target.y-was.y)) if kind in ["MOVE","SWAP"] else Vector2i.ZERO

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

func reservation_choice(actor: Dictionary) -> Dictionary: return AutoBattle.reservation_choice(self,actor)

func reserve_action(index: int, kind: String, cell: Vector2i) -> bool: return AutoBattle.reserve_action(self,index,kind,cell)

func cancel_reservation(index: int) -> void: AutoBattle.cancel_reservation(self,index)

func command_choice(actor: Dictionary) -> Dictionary: return AutoBattle.command_choice(self,actor)

func companion_choice(actor: Dictionary) -> Dictionary: return AutoBattle.companion_choice(self,actor)

func companion_intent_snapshot() -> Array: return AutoBattle.companion_intent_snapshot(self)


func auto_step() -> bool: return AutoBattle.auto_step(self)

func open_battle_conflicts() -> void: AutoBattle.open_battle_conflicts(self)

## Forwarded for callers that read it on the session; defined in `RunResult`.
const EXPLAIN_KEEP := RunResult.EXPLAIN_KEEP

func note_explain(actor: Dictionary, choice: Dictionary) -> void: RunResult.note_explain(self,actor,choice)

## Forwarded for callers that read it on the session; defined in `RunResult`.
const MISTAKE_NAMES := RunResult.MISTAKE_NAMES

func note_mistake(actor: Dictionary, kind: String) -> void: RunResult.note_mistake(self,actor,kind)

func end_battle_orders() -> void: AutoBattle.end_battle_orders(self)

func remember_round() -> void: AutoBattle.remember_round(self)

func auto_stop_reason() -> String: return AutoBattle.auto_stop_reason(self)

func companion_previews() -> Array: return AutoBattle.companion_previews(self)

func set_knob(index: int, key: String, value: int) -> bool: return Orders.set_knob(self,index,key,value)

func set_stance(index: int, stance: String) -> bool: return Orders.set_stance(self,index,stance)

func set_protect(index: int, target_index: int) -> bool: return Orders.set_protect(self,index,target_index)

func set_tactic(index: int, skill: String, policy: String) -> bool: return Orders.set_tactic(self,index,skill,policy)

func set_basic_target(index: int, target: String) -> bool: return Orders.set_basic_target(self,index,target)

func update_rule(index: int, position: int, field: String, value: Variant) -> bool: return Orders.update_rule(self,index,position,field,value)

func reorder_rule(index: int, position: int, direction: int) -> bool: return Orders.reorder_rule(self,index,position,direction)

## Lightning running along wet and metal ground, six weaker each cell. It is a
## reaction: it never sets off another.
func discharge(origin: Vector2i, source: int, power: int = 18) -> void:
	var queue: Array = [{"pos":origin, "power":power}]
	var seen: Array = [origin]
	var owner: Dictionary = actor_by_id(source)
	while not queue.is_empty():
		var row: Dictionary = queue.pop_front()
		var victim := at(row.pos)
		if not victim.is_empty(): CombatRules.damage(self,owner,victim,int(row.power),"air",0,Reactions.REACTION_FORM)
		if row.power <= 6 or not conductive(row.pos): continue
		for direction in CARDINALS:
			var next: Vector2i = row.pos + direction
			if inside(next) and next not in seen and conductive(next):
				seen.append(next); queue.append({"pos":next, "power":row.power - 6})
	message("방전")

func conductive(point: Vector2i) -> bool:
	var ground: Dictionary = tile(point)
	return ground.terrain in ["metal", "water", "deep_water", "bog"] or int(ground.wet) >= 25 or bool(ground.get("deep_water",false)) or bool(ground.get("bog",false))

func roll_part(enemy: Dictionary, reward_actors: Variant = null) -> void: Gear.roll_part(self,enemy,reward_actors)

## The party shares a hunt it joined; independent NPCs earn only from fights
## they actually joined. A monster killing another monster rewards neither.
func hunt_recipients(enemy: Dictionary, killer: Dictionary) -> Array:
	var participants: Array = (party+npcs).filter(func(a):
		return a.hp > 0 and not a.get("summoned",false) and (a.get("usage",{}).has(int(enemy.id)) or not killer.is_empty() and int(a.id) == int(killer.id)))
	var result: Array = []
	if participants.any(func(a): return a in party): result.append_array(alive())
	result.append_array(participants.filter(func(a): return a not in party))
	return result

func gain_level_xp(actor: Dictionary, amount: int) -> int: return Descent.gain_level_xp(self,actor,amount)

func grant_gear(item: Dictionary) -> void: Gear.grant_gear(self,item)


func reset_rules(index: int) -> void: Gear.reset_rules(self,index)

func equip_part(index: int, slot: int, id: String) -> bool: return Gear.equip_part(self,index,slot,id)

func unequip_part(index: int, slot: int) -> bool: return Gear.unequip_part(self,index,slot)

func grant_test_loadout() -> bool: return Gear.grant_test_loadout(self)

## Forwarded for callers that read it on the session; defined in `ArenaTest`.
static var ARENA_PRESETS: Dictionary = ArenaTest.ARENA_PRESETS

static func load_arena_presets() -> Dictionary: return ArenaTest.load_arena_presets()

static func arena_test(p_seed: int, party_size: int, arena: Dictionary, members: Array): return ArenaTest.arena_test(new(p_seed,true,party_size > 1,true,party_size),p_seed,party_size,arena,members)

static func arena_contact(s) -> void: ArenaTest.arena_contact(s)

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
	var hit_form: String = form if form in Reactions.SECONDARY else Reactions.HIT_FORM
	return CombatRules.damage(self,actor_by_id(source),target,amount,form,0,hit_form)

func after_damage(target: Dictionary, amount: int, source: int, form: String) -> int:
	if target.hp <= 0: return 0
	var attacker: Dictionary = actor_by_id(source)
	# Retaliation is plain damage: it never triggers passives again.
	var passive_hit: bool = form not in Reactions.SECONDARY
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
	var cut: int = Abilities.reduction(target)
	if cut > 0: amount = maxi(1,amount*(100-cut)/100)
	if passive_hit: amount = Passives.incoming(self,target,amount)
	# A solo floor always grants one action; collapse instead exposes the hero
	# to one extra point of damage. Calming supplies can prevent this penalty.
	if party.size() == 1 and not target.enemy and target.stress >= 150 and amount > 0: amount += 1
	serial += 1
	amount = Families.lethal(self,target,amount)
	var lost := mini(int(target.hp), amount)
	if lost > 0 and bool(target.get("enemy",false)): target.sleep_until = 0
	var source_cell: Vector2i = target.pos
	var source_name: String = {"FIRE":"불길","ELECTRIC":"방전","POISON":"독"}.get(form,"함정")
	if not attacker.is_empty(): source_cell = attacker.pos; source_name = attacker.name
	var effect := {"from":source_cell,"cell":target.pos,"amount":lost,"form":form,"enemy":bool(target.get("enemy",false)) or bool(target.get("hostile",false))}
	effects.append(effect)
	if presentation == null and effects.size() > 32: effects.pop_front()
	var dealt_row: Dictionary = member_stats(source) if not attacker.is_empty() and not attacker.enemy else {}
	if not dealt_row.is_empty(): dealt_row.dealt += lost
	var taken_row: Dictionary = member_stats(target.id) if not target.enemy else {}
	if not taken_row.is_empty():
		taken_row.taken += lost
		if covered: taken_row.redirected += lost
	target.hp -= lost; Body.sync(target)
	if lost > 0 and bool(target.get("boss",false)): BossAI.on_damaged(self,target,form)
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
			# A summoned creature is a spell ending, not a stranger dying: the
			# party grieves nobody for it.
			var watched: bool = floor_state.visible.has(target.pos) and not bool(target.get("summoned",false)) and not bool(target.get("hostile",false))
			for ally in alive():
				if not watched: continue
				stress(ally,5)
				if int(target.memory.salience_for_subject(ally.id+1,["AID_RECEIVED"])) > 0: stress(ally,10)
		elif target.hp <= 0 and target in party and target != party[0] and not Downed.is_downed(target):
			if not taken_row.is_empty(): taken_row.downed = true
			Downed.enter(self,target,source)
	var fall_text := ""
	if Downed.is_downed(target): fall_text = " %s 빈사 · %d턴" % [target.name,int(target.bleedout_turns)]
	elif target.hp <= 0: fall_text = " "+subject_name(target.name)+" 쓰러졌습니다."
	message("%s %s에게 %d의 피해를 주었습니다.%s" % [subject_name(source_name),target.name,lost,fall_text])
	if passive_hit: Passives.after_hit(self,target,attacker,form,lost)
	if target.enemy and target.hp <= 0:
		BossAI.on_monster_death(self,target,attacker)
		var hunters: Array = hunt_recipients(target,attacker)
		var party_hunted: bool = hunters.any(func(a): return a in party)
		if not attacker.is_empty(): TagSets.on_kill(self,attacker)
		if not attacker.is_empty(): Families.on_kill(self,attacker)
		for actor in party+npcs: actor.get("usage",{}).erase(int(target.id))
		if party_hunted:
			battle_stats.kills = int(battle_stats.get("kills",0))+1
			run_stats.kills = int(run_stats.kills)+1
			score += 10
		if party_hunted and bool(Encounters.species(str(target.get("species_id",""))).get("beast",false)) and Hexaco.sample(seed_value,depth*1000+target.id,"beast_food",100) < 25:
			food += 1; message("고기 획득 · 식량 +1")
		if target.get("boss",false):
			if party_hunted:
				grant_part(str(target.part_id)); score += 100
			BossAI.on_boss_defeated(self,target)
			if depth >= Zones.FINAL_DEPTH: victory()
		else: roll_part(target,hunters)
		NpcEssences.on_hunt(self,target,hunters)
	if bool(target.get("fallen",false)) and target.hp <= 0 and not bool(target.get("defeated",false)):
		target.defeated = true
		BossAI.on_boss_defeated(self,target)
	if not target.enemy and target.id == 0 and target.hp <= 0: check_battle_end()
	return lost

func plan_enemies() -> void: AutoBattle.plan_enemies(self)

func enemy_attack_turn(enemy: Dictionary) -> void: AutoBattle.enemy_attack_turn(self,enemy)


func end_round() -> bool: return AutoBattle.end_round(self)

func victory() -> void:
	if phase == "VICTORY": return
	phase = "VICTORY"; score += 500
	message("원정 성공")

func check_battle_end() -> void:
	if on_floor() and party[0].hp <= 0: phase = "DEFEAT"; message("원정 종료")
