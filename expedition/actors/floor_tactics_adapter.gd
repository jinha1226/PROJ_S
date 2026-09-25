extends RefCounted
## Contract adapter: original legacy selector is unchanged.
const Selector = preload("res://expedition/legacy/tactical_action_selector.gd")
var s
var actors: Array = []
var timeline
var Effects
var body_bridge
var BOUNDS := Vector2i(100,100)
var seed: int
var now: int
var ready: Dictionary = {}
var origin: Dictionary = {}
func _init(host,source: Dictionary) -> void:
	s = host; seed = s.seed_value; now = s.world_time; origin = source
	timeline = self; Effects = self; body_bridge = self
	# An awake npc is a target like any party member, and a dominated monster
	# reads the same roster the other way round: its own kind is the other team.
	var seen_ids: Dictionary = {}
	for actor in s.friends()+s.hostiles_of(source)+[source]:
		if actor.hp <= 0 or seen_ids.has(int(actor.id)): continue
		seen_ids[int(actor.id)] = true
		var row: Dictionary = actor.duplicate()
		row.position = actor.pos; row.team = 0 if source.get("enemy",false) and not s.dominated(source) and s.wanderer(actor) else s.side_of(actor)
		row.profile = actor.profile.to_dict(); row.skills = []; row.barrier = 0
		actors.append(row); ready[row.id] = now
func duration(_actor: Dictionary,_kind: String) -> int: return 100
func distance(a: Vector2i,b: Vector2i) -> int: return maxi(absi(a.x-b.x),absi(a.y-b.y))
func blocked(p: Vector2i) -> bool: return not s.inside(p) or s.tile(p).terrain == "wall"
func clear_line(a: Vector2i,b: Vector2i,_blocked: Callable) -> bool:
	if distance(a,b) == 1: return s.melee_reach(a,b)
	return s.TurnCore.Geometry.sees(a,b,blocked)
func basic_power(actor: Dictionary) -> int: return int(s.CombatStats.stats(s,actor).damage) if s.manual_mode else 7 if actor.enemy else s.StatSheet.legacy_power(actor,"MELEE",18)
func use_error(_actor: Dictionary,_kind: String) -> String: return ""
func assess(_kind: String,_source: Dictionary,_target: Dictionary,_actors: Array,_blocked: Callable,_bounds: Vector2i) -> Dictionary: return {"accepted":false}
func preview(_source: int,_kind: String,_target: int) -> Dictionary: return {"accepted":false}
func _next_step(a: Vector2i,b: Vector2i) -> Vector2i:
	# There is no approach move to make once this melee unit is in contact with
	# something it actually fights — which, for a dominated monster, is its own
	# kind rather than the party.
	if s.hostiles_of(origin).any(func(foe): return s.melee_reach(a,foe.pos)): return a
	var goals: Array = []
	for d in s.DIRECTIONS:
		if s.is_free(b+d) and s.melee_reach(b+d,b): goals.append(b+d)
	if goals.is_empty(): return a
	var route: Dictionary = s.TurnCore.path(100,100,a,goals,func(from,to): return s.can_step(from,to),func(_p): return 100,100,50)
	return route.path[1] if route.found and route.path.size() > 1 else a
func choose(source: Dictionary) -> Dictionary:
	var row: Dictionary = actors.filter(func(a): return a.id == source.id)[0]
	var choice: Dictionary = Selector.choose(self,row)
	var cell: Vector2i = choice.position if choice.kind == "MOVE" else source.pos
	if choice.kind == "ATTACK":
		cell = actors.filter(func(a): return a.id == choice.target)[0].pos
	# Break self references after the original selector has finished.
	timeline = null; Effects = null; body_bridge = null
	return {"kind":choice.kind,"cell":cell,"reason":choice.reason}
