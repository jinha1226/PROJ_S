extends RefCounted
## Continuous actor coordinates in terrain units. `pos` is only the cached
## terrain cell, for terrain/features and compatibility with older simulations.
const RADIUS := 0.23
const STEP := 1.0
const CONTACT := 1.0
const EPS := 0.0001

static func cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x),floori(point.y))

static func center(point: Vector2i) -> Vector2:
	return Vector2(point)+Vector2.ONE*0.5

static func position(actor: Dictionary) -> Vector2:
	# Spawns, stairs and explicit teleports can change the terrain cache.
	if not actor.has("world_pos") or cell(actor.world_pos) != actor.pos:
		actor.world_pos = center(actor.pos)
	return actor.world_pos

static func place(actor: Dictionary, point: Vector2) -> void:
	actor.world_pos = point; actor.pos = cell(point)

static func enable(s) -> void:
	s.free_movement = true
	for actor in s.party+s.npcs+s.enemies: position(actor)
	s.floor_state.observe(s)

static func point(s, terrain: Vector2i, preferred: Dictionary = {}) -> Vector2:
	if not preferred.is_empty() and preferred.pos == terrain: return position(preferred)
	var occupant: Dictionary = s.at(terrain)
	return position(occupant) if not occupant.is_empty() else center(terrain)

static func gap(a: Dictionary, b: Dictionary) -> float:
	return position(a).distance_to(position(b))

static func occupants(s, at: Vector2i) -> Array:
	var result: Array = []; var seen: Dictionary = {}
	for actor in s.party+s.npcs+s.enemies:
		if actor.pos != at or seen.has(actor.id) or actor.hp <= 0 and not actor.get("downed",false): continue
		seen[actor.id] = true; result.append(actor)
	return result

static func wall(s, at: Vector2i) -> bool:
	return not s.inside(at) or s.tile(at).terrain == "wall" or int(s.tile(at).get("wall_until",0)) > s.time

static func fits(s, at: Vector2, actor: Dictionary = {}, bodies: bool = true, radius: float = RADIUS) -> bool:
	var box := cell(at)
	for y in range(box.y-1,box.y+2):
		for x in range(box.x-1,box.x+2):
			var tile := Vector2i(x,y)
			if not wall(s,tile): continue
			var nearest := Vector2(clampf(at.x,x,x+1),clampf(at.y,y,y+1))
			if at.distance_squared_to(nearest) < radius*radius-EPS: return false
	if bodies:
		for other in s.party+s.npcs+s.enemies:
			if other == actor or int(other.hp) <= 0 and not other.get("downed",false): continue
			if at.distance_to(position(other)) < RADIUS*2-EPS: return false
	return true

static func segment(s, a: Vector2, b: Vector2, radius: float = RADIUS, actor: Dictionary = {}, bodies: bool = false, perception: bool = false) -> bool:
	# Swept clearance: the sampling gap is smaller than an actor radius. Test
	# expanded wall rectangles as well, so diagonal corners cannot be tunneled.
	var low := cell(Vector2(minf(a.x,b.x),minf(a.y,b.y))-Vector2.ONE*radius)
	var high := cell(Vector2(maxf(a.x,b.x),maxf(a.y,b.y))+Vector2.ONE*radius)
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			if not wall(s,Vector2i(x,y)): continue
			if perception and s.inside(Vector2i(x,y)) and s.tile(Vector2i(x,y)).get("pillar",false): continue
			var rect := Rect2(Vector2(x,y),Vector2.ONE).grow(maxf(0,radius-0.001))
			if rect.has_point(a) or rect.has_point(b): return false
			var corners := [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
			for i in range(4):
				if Geometry2D.segment_intersects_segment(a,b,corners[i],corners[(i+1)%4]) != null: return false
	if bodies:
		var steps := maxi(1,ceili(a.distance_to(b)/0.1))
		for i in range(1,steps+1):
			if not fits(s,a.lerp(b,float(i)/steps),actor,true,radius): return false
	return true

static func sees(s, a: Vector2, b: Vector2, reach: float) -> bool:
	return a.distance_to(b) <= reach+EPS and segment(s,a,b,0.0)

static func reaches(s, actor: Dictionary, target: Dictionary, reach: float) -> bool:
	return not target.is_empty() and actor != target and sees(s,position(actor),position(target),reach)

static func actor_at(s, at: Vector2, radius: float = 0.48, visible_only: bool = true) -> Dictionary:
	var found: Dictionary = {}; var best := radius
	for actor in s.party+s.npcs+s.enemies:
		if int(actor.hp) <= 0 and not actor.get("downed",false): continue
		if visible_only and not s.floor_state.visible.has(actor.pos): continue
		var d := at.distance_to(position(actor))
		if d <= best: best = d; found = actor
	return found

static func route(s, actor: Dictionary, goal: Vector2, known: bool = false) -> Array:
	var start := position(actor)
	if not fits(s,goal,{},false): return []
	var allowed := func(p): return not known or s.floor_state.explored.has(p)
	if segment(s,start,goal) and (not known or remembered(s,start,goal)): return [start,goal]
	# Terrain search supplies corridor topology; string pulling supplies actual
	# continuous paths. Actors are never snapped to these planning cells.
	var result: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,actor.pos,[cell(goal)],
		func(a,b): return allowed.call(b) and not wall(s,b) and segment(s,center(a),center(b)),func(_p): return 100)
	if not result.found: return []
	var points: Array = [start]
	for p in result.path.slice(1): points.append(center(p))
	points.append(goal)
	var smooth: Array = [start]; var index := 0
	while index < points.size()-1:
		var next := index+1
		for j in range(index+2,points.size()):
			if segment(s,points[index],points[j]) and (not known or remembered(s,points[index],points[j])): next = j
		smooth.append(points[next]); index = next
	return smooth

static func remembered(s, a: Vector2, b: Vector2) -> bool:
	var steps := maxi(1,ceili(a.distance_to(b)*4))
	for i in range(steps+1):
		if not s.floor_state.explored.has(cell(a.lerp(b,float(i)/steps))): return false
	return true

static func next(s, actor: Dictionary, goal: Vector2, known: bool = false, budget: float = STEP) -> Vector2:
	var start := position(actor)
	var path := route(s,actor,goal,known)
	if path.size() < 2: return start
	var wanted: Vector2 = start.move_toward(path[1],budget)
	if segment(s,start,wanted,RADIUS,actor,true): return wanted
	# Local avoidance is relative to the desired heading, never eight fixed axes.
	var delta: Vector2 = wanted-start
	var best := start; var best_gap := start.distance_to(goal)
	for angle in [0.261799,-0.261799,0.523599,-0.523599,1.047198,-1.047198,1.570796,-1.570796]:
		var candidate := start+delta.rotated(angle)
		if known and not remembered(s,start,candidate): continue
		if not segment(s,start,candidate,RADIUS,actor,true): continue
		var score := candidate.distance_to(goal)
		if score < best_gap: best_gap = score; best = candidate
	if best != start: return best
	for scale in [0.75,0.5,0.25]:
		wanted = start+delta*scale
		if segment(s,start,wanted,RADIUS,actor,true): return wanted
	return start

static func approach(s, actor: Dictionary, target: Dictionary, reach: float = CONTACT) -> Vector2:
	var here := position(actor); var there := position(target)
	var delta := there-here
	if delta.length() <= reach+EPS and segment(s,here,there,0): return here
	var goal := there-delta.normalized()*maxf(RADIUS*2+0.03,reach-0.05)
	return next(s,actor,goal)

static func retreat(s, actor: Dictionary) -> Vector2:
	var foes: Array = (s.party+s.npcs+s.enemies).filter(func(a): return a.hp > 0 and s.MobileEffects.hostile(s,actor,a) and sees(s,position(actor),position(a),6))
	if foes.is_empty(): return position(actor)
	foes.sort_custom(func(a,b): return gap(actor,a) < gap(actor,b))
	var start := position(actor)
	var direction := (start-position(foes[0])).normalized()
	var best := start; var score := gap(actor,foes[0])
	for angle in [0.0,0.261799,-0.261799,0.523599,-0.523599,1.047198,-1.047198,1.570796,-1.570796]:
		var goal := start+direction.rotated(angle)*STEP
		if not segment(s,start,goal,RADIUS,actor,true) or s.tile(cell(goal)).fire > 0: continue
		var nearest := INF
		for foe in foes: nearest = minf(nearest,goal.distance_to(position(foe)))
		if nearest > score: best = goal; score = nearest
	return best

static func choice(actor: Dictionary, kind: String, at: Vector2, reason: String, tag: String = "") -> Dictionary:
	return {"kind":kind,"cell":cell(at),"world":at,"reason":reason,"tag":tag if not tag.is_empty() else kind,"dir":Vector2i(Vector2(at-position(actor)).sign())}

static func candidates(s, actor: Dictionary, stance: String) -> Array:
	var foes: Array = (s.party+s.npcs+s.enemies).filter(func(a): return a.hp > 0 and s.MobileEffects.hostile(s,actor,a) and sees(s,position(actor),position(a),6))
	foes.sort_custom(func(a,b): return gap(actor,a) < gap(actor,b))
	var options: Array = [choice(actor,"WAIT",position(actor),"대기","WAIT:hold")]
	if foes.is_empty(): return options
	var target: Dictionary = foes[0]
	if s.party_command == "ATTACK_TARGET":
		for foe in foes:
			if int(foe.id) == s.command_target: target = foe; break
	var reach := float(s.CombatStats.stats(s,actor).range)
	if reaches(s,actor,target,reach):
		var attack := choice(actor,"ATTACK",position(target),"공격")
		attack.target_id = int(target.id); attack.damage = int(s.CombatStats.stats(s,actor).damage)
		options.append(attack)
	if not s.status_blocks(actor,"MOVE"):
		var dest := approach(s,actor,target,reach)
		if dest != position(actor): options.append(choice(actor,"MOVE",dest,"접근","MOVE:approach"))
		if stance == "SKIRMISHER" and gap(actor,target) < maxf(1.2,reach*0.5):
			var away := retreat(s,actor)
			if away != position(actor): options.append(choice(actor,"MOVE",away,"거리 확보","MOVE:disengage"))
		if stance == "GUARDIAN":
			var protectee: Dictionary = s.Stances.protectee(s,actor)
			if not protectee.is_empty() and gap(actor,protectee) > 2:
				var rejoin := approach(s,actor,protectee,1.1)
				if rejoin != position(actor): options.append(choice(actor,"MOVE",rejoin,"호위 합류","MOVE:rejoin"))
	return options

static func follow(s, actor: Dictionary) -> Dictionary:
	var lead: Dictionary = s.leader()
	var order: int = s.formation.find(s.party.find(actor))
	if order > 1:
		var previous: Dictionary = s.party[s.formation[order-1]]
		if previous.hp > 0: lead = previous
	var dest := position(actor)
	if gap(actor,lead) > 0.9 and not s.status_blocks(actor,"MOVE"): dest = approach(s,actor,lead,0.85)
	return choice(actor,"WAIT" if dest == position(actor) else "MOVE",dest,"동행")

static func perform(s, actor: Dictionary, action: Dictionary, intentional: bool = true) -> bool:
	if actor.hp <= 0 or not s.on_floor(): return false
	var kind: String = str(action.kind)
	if s.status_blocks(actor,kind) and not (kind == "WAIT" and s.MobileEffects.active(actor)): return false
	var start := position(actor)
	var dest: Vector2 = action.get("world",center(action.get("cell",actor.pos)))
	var victim: Dictionary = s.actor_by_id(int(action.get("target_id",-1)))
	if kind == "MOVE" and (start.distance_to(dest) > STEP+EPS or start.distance_to(dest) < EPS or not segment(s,start,dest,RADIUS,actor,true)): return false
	if kind == "ATTACK":
		if victim.is_empty(): victim = actor_at(s,dest)
		if victim.is_empty() or not (s.MobileEffects.hostile(s,actor,victim) or actor in s.party and s.wanderer(victim) and not victim.get("summoned",false)) or not reaches(s,actor,victim,float(s.CombatStats.stats(s,actor).range)): return false
		if actor == s.party[0] and not s.floor_state.visible.has(victim.pos): return false
	if kind == "SWAP":
		if victim.is_empty() or not s.can_swap_with(actor,victim) or gap(actor,victim) > 1: return false
		s.Reactions.begin_action(s); s.MobileEffects.begin(s,actor,kind,intentional)
		place(actor,position(victim)); place(victim,start)
		s.record_action(actor,kind,actor.pos,cell(start)); s.Consumables.pickup(s,actor); return true
	if kind not in ["MOVE","ATTACK","WAIT"]: return s.act_as(actor,kind,cell(dest),false,intentional)
	var old_cell: Vector2i = actor.pos
	var stacks: Dictionary = actor.get("stacks",{}).duplicate(true)
	s.Reactions.begin_action(s); s.MobileEffects.begin(s,actor,kind,intentional)
	match kind:
		"MOVE":
			place(actor,dest)
			actor.hit_and_run = false
			if actor in s.party: s.Consumables.pickup(s,actor)
		"ATTACK":
			if s.wanderer(victim) and actor in s.party: s.NpcHostility.provoke(s,victim,actor)
			s.effects.append({"kind":"ATTACK_SWING","from":old_cell,"cell":victim.pos,"amount":0,"form":"SLASH","world_from":start,"world_cell":position(victim)})
			s.CombatRules.attack(s,actor,victim)
		"WAIT":
			if intentional and not s.status_blocks(actor,"ATTACK"): s.MobileEffects.push(s,"WAIT",actor,{"target":actor})
	s.record_action(actor,kind,actor.pos if kind != "ATTACK" else victim.pos,old_cell,stacks)
	if kind == "MOVE":
		actor.effect_move_action = int(s.action_serial); actor.effect_moved_round = int(s.time)/100; actor.moved_since_attack = true
		actor.last_world_dir = (dest-start).normalized()
		if old_cell == actor.pos: s.StoneEffects.fire(s,"MOVED",{"actor":actor,"from":old_cell,"to":actor.pos})
	actor.ap = 1
	s.check_battle_end()
	return true

static func submit(s, action: Dictionary) -> bool:
	if not s.pending_stone_drops.is_empty() or not s.pending_choice.is_empty() or s.party.is_empty(): return false
	var actor: Dictionary = s.party[0]
	if s.Forms.attack_action(s,str(action.kind)) and int(actor.get("effect_moved_round",-1)) == s.time/100 and s.StoneEffects.modifier(s,"no_attack_after_move",actor) > 0: return false
	# Resolve other due turns first, then re-check continuous legality.
	if not legal(s,actor,action): return false
	if not s.Scheduler.flush_ready(s) or actor.hp <= 0: return false
	if not s.pending_stone_drops.is_empty(): return false
	if not perform(s,actor,action): return false
	var cost: int = s.action_cost(actor,str(action.kind),actor.pos)
	return s.Scheduler.advance(s,cost)

static func attack(s) -> bool:
	var hero: Dictionary = s.party[0]
	var foes: Array = s.party_enemies().filter(func(a): return s.MobileEffects.hostile(s,hero,a))
	if foes.is_empty(): return false
	foes.sort_custom(func(a,b):
		var am: bool = int(a.id) == s.command_target; var bm: bool = int(b.id) == s.command_target
		if am != bm: return am
		return gap(hero,a) < gap(hero,b))
	var target: Dictionary = foes[0]
	if reaches(s,hero,target,float(s.CombatStats.stats(s,hero).range)):
		var action := choice(hero,"ATTACK",position(target),"공격"); action.target_id = int(target.id)
		return submit(s,action)
	var dest := approach(s,hero,target,float(s.CombatStats.stats(s,hero).range))
	return submit(s,choice(hero,"MOVE",dest,"접근"))

static func monster_move(s, actor: Dictionary, target: Dictionary, reach: float = 0.95) -> void:
	if s.status_blocks(actor,"MOVE"): return
	var dest := approach(s,actor,target,reach)
	if dest != position(actor): place(actor,dest)

static func patrol(s, actor: Dictionary) -> void:
	if s.status_blocks(actor,"MOVE"): return
	var home: Vector2 = center(actor.get("home",actor.pos))
	var angle: float = float(actor.id)*0.618+float(s.time)*0.007
	var goal := home+Vector2.from_angle(angle)*1.5
	var dest := next(s,actor,goal)
	if dest != position(actor): place(actor,dest)

static func legal(s, actor: Dictionary, action: Dictionary) -> bool:
	if actor.hp <= 0 or not s.on_floor(): return false
	var kind: String = str(action.kind)
	if s.status_blocks(actor,kind) and not (kind == "WAIT" and s.MobileEffects.active(actor)): return false
	if kind == "WAIT": return true
	if kind == "SWAP":
		var mate: Dictionary = s.actor_by_id(int(action.get("target_id",-1)))
		return not mate.is_empty() and s.can_swap_with(actor,mate) and gap(actor,mate) <= 1
	var at: Vector2 = action.get("world",center(action.get("cell",actor.pos)))
	if kind == "MOVE":
		var delta := position(actor).distance_to(at)
		return delta > EPS and delta <= STEP+EPS and segment(s,position(actor),at,RADIUS,actor,true)
	if kind == "ATTACK":
		var victim: Dictionary = s.actor_by_id(int(action.get("target_id",-1)))
		if victim.is_empty(): victim = actor_at(s,at)
		return not victim.is_empty() and (s.MobileEffects.hostile(s,actor,victim) or actor in s.party and s.wanderer(victim) and not victim.get("summoned",false)) and reaches(s,actor,victim,float(s.CombatStats.stats(s,actor).range)) and (actor != s.party[0] or s.floor_state.visible.has(victim.pos))
	return s.can_submit(actor,kind,cell(at))
