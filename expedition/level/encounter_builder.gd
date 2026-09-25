extends RefCounted
## DCSS-style depth table + DD-style threat budget. Pure functions over the
## seeded RNG passed in; never touches the session.
const Registry = preload("res://expedition/legacy/dcss_enemy_registry.gd")
const Zones = preload("res://expedition/level/zones.gd")
const FALLBACK_DEPTH := 6
static var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/floor_monsters.json"))
const ROLE_BONUS := {"MELEE":0,"RANGED":1,"CASTER":2}
const ROLE_WEIGHTS := {"MELEE":60,"RANGED":30,"CASTER":10}
const MAX_MEMBERS := 4
const MAX_REROLLS := 20
const MAX_DRAWS := 40
const OOD_PERCENT := 10

static func table() -> Array:
	return content.get("species",[])

static func species(id: String) -> Dictionary:
	for row in table():
		if row.species_id == id: return row
	return {}

static func curve(row: Dictionary, depth: int) -> float:
	var lo: int = int(row.min_depth); var hi: int = int(row.max_depth)
	if depth < lo or depth > hi: return 0.0
	var t: float = 0.0 if hi == lo else float(depth-lo)/float(hi-lo)
	match str(row.curve):
		"RISE": return 0.15+0.85*t
		"FALL": return 1.0-0.85*t
		"PEAK": return 0.2+0.8*(1.0-absf(2.0*t-1.0))
		_: return 1.0

static func weight(row: Dictionary, depth: int) -> float:
	if row.has("zone"): return float(row.rarity) if int(row.zone) == Zones.zone_of(depth) else 0.0
	return float(row.rarity)*curve(row,mini(depth,FALLBACK_DEPTH))

static func threat(member: Dictionary) -> int:
	var row := species(member.species_id)
	return int(row.get("threat",1))+int(ROLE_BONUS.get(member.role,0))

static func candidates(depth: int, max_threat: int) -> Array:
	return table().filter(func(r): return weight(r,depth) > 0.0 and int(r.threat) <= max_threat)

static func pick_weighted(rng: RandomNumberGenerator, rows: Array, weights: Array) -> Variant:
	var total := 0.0
	for w in weights: total += w
	if total <= 0.0: return null
	var roll := rng.randf()*total
	for i in range(rows.size()):
		roll -= weights[i]
		if roll <= 0.0: return rows[i]
	return rows[rows.size()-1]

static func health_for(id: String, row: Dictionary) -> int:
	var profile: Dictionary = Registry.profile(id)
	return int(profile.get("max_health",row.get("max_health",28)))

static func member(row: Dictionary, role: String) -> Dictionary:
	var result := {"species_id":str(row.species_id),"role":role,"display_name":str(row.display_name),"max_health":health_for(row.species_id,row)}
	result.threat = threat(result)
	return result

static func role_allowed(members: Array, row: Dictionary, role: String) -> bool:
	if role not in row.roles: return false
	if role == "CASTER" and members.any(func(m): return m.role == "CASTER"): return false
	var same: int = members.filter(func(m): return m.species_id == row.species_id and m.role == role).size()
	return same < 2

static func choose_role(rng: RandomNumberGenerator, members: Array, row: Dictionary) -> String:
	var roles: Array = []; var weights: Array = []
	for role in ROLE_WEIGHTS:
		if role_allowed(members,row,role): roles.append(role); weights.append(float(ROLE_WEIGHTS[role]))
	if roles.is_empty(): return ""
	return pick_weighted(rng,roles,weights)

## Empty string when the group is legal for the budget; otherwise the reason.
static func valid(members: Array, budget: int, max_members: int = MAX_MEMBERS) -> String:
	if members.is_empty(): return "empty"
	if members.size() > max_members: return "too many"
	var total := 0
	for m in members: total += int(m.get("threat",threat(m)))
	if total < budget-1: return "too weak (%d < %d)" % [total,budget-1]
	if total > budget+1: return "too strong (%d > %d)" % [total,budget+1]
	if members.filter(func(m): return m.role == "CASTER").size() > 1: return "two casters"
	var band: Variant = species("dcss_gnoll").get("band")
	var followers: Array = band.get("followers",[]) if band is Dictionary else []
	var gnoll_band: bool = members.any(func(m): return m.species_id == "dcss_gnoll") and members.filter(func(m): return m.species_id in followers).size() >= 2
	if members.any(func(m): return m.species_id == "dcss_gnoll") and not gnoll_band: return "incomplete gnoll band"
	if members.size() >= 3 and members.all(func(m): return m.role == "MELEE") and not gnoll_band: return "no backline"
	var pairs: Dictionary = {}
	for m in members:
		var key: String = m.species_id+"/"+m.role
		pairs[key] = int(pairs.get(key,0))+1
		if pairs[key] > 2: return "three of a kind"
	return ""

static func attempt(rng: RandomNumberGenerator, depth: int, budget: int, ood: bool, max_members: int = MAX_MEMBERS) -> Array:
	var members: Array = []
	var remaining := budget
	var table_depth := depth
	if ood and rng.randi_range(1,100) <= OOD_PERCENT: table_depth = mini(depth+1,Zones.last_floor(Zones.zone_of(depth)))
	var draws := 0
	while remaining >= 1 and members.size() < max_members:
		# A bounded number of draws: a table whose guardrails saturate must not spin.
		draws += 1
		if draws > MAX_DRAWS: break
		var rows: Array = candidates(table_depth,remaining+1)
		if rows.is_empty(): break
		var row: Dictionary = pick_weighted(rng,rows,rows.map(func(r): return weight(r,table_depth)))
		var role := choose_role(rng,members,row)
		if role.is_empty(): continue
		var picked := member(row,role)
		members.append(picked); remaining -= picked.threat
		if row.band != null and members.filter(func(m): return m.species_id == row.species_id).size() == 1:
			var count: int = rng.randi_range(int(row.band.count[0]),int(row.band.count[1]))
			for _i in range(count):
				if members.size() >= max_members: break
				var follower_id: String = row.band.followers[rng.randi_range(0,row.band.followers.size()-1)]
				var follower := member(species(follower_id),"MELEE")
				members.append(follower); remaining -= follower.threat
			break
	if members.size() >= 3 and members.all(func(m): return m.role == "MELEE"):
		for i in range(members.size()-1,-1,-1):
			var row := species(members[i].species_id)
			if "RANGED" in row.roles:
				members[i] = member(row,"RANGED"); break
	return members

static func fill(rng: RandomNumberGenerator, depth: int, budget: int, ood: bool, max_members: int = MAX_MEMBERS) -> Array:
	for _try in range(MAX_REROLLS):
		var members := attempt(rng,depth,budget,ood,max_members)
		if valid(members,budget,max_members).is_empty(): return members
	# Fallback: the strongest single species that fits, always legal for budget-1..budget+1.
	var rows: Array = candidates(depth,budget+1)
	rows.sort_custom(func(a,b): return int(a.threat) > int(b.threat))
	for row in rows:
		var solo := [member(row,"MELEE")]
		if valid(solo,budget,max_members).is_empty(): return solo
	return [member(rows[0] if not rows.is_empty() else species("kobold"),"MELEE")]

## One pack for a theme at this depth, seeded on its own. Members match
## `layout.encounters[].members` in shape: species_id, display_name, max_health, role.
static func pack(theme: Dictionary, budget: int, depth: int, pack_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = pack_seed
	var max_members: int = int(theme.get("monsters",{}).get("max_members",MAX_MEMBERS))
	return fill(rng,maxi(1,depth),budget,false,max_members)

static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x-b.x),absi(a.y-b.y))

static func door_distance(p: Vector2i, doors: Array) -> int:
	var best := 999
	for d in doors: best = mini(best,chebyshev(p,d))
	return best

## Leader on the anchor (farthest floor cell from the doors when the room has
## no anchor), melee beside the leader, backline on P cells or beside obstacles
## behind the leader. Every member ends >= 3 from every door.
static func place(members: Array, floor_cells: Array, doors: Array, anchor: Vector2i, backline: Array, obstacles: Dictionary, rng: RandomNumberGenerator) -> bool:
	var free: Dictionary = {}
	for p in floor_cells:
		if not obstacles.has(p): free[p] = true
	var ordered: Array = free.keys()
	ordered.sort_custom(func(a,b): return door_distance(a,doors) > door_distance(b,doors) if door_distance(a,doors) != door_distance(b,doors) else (a.y > b.y if a.y != b.y else a.x < b.x))
	var anchors: Array = ([anchor] if anchor != Vector2i(-1,-1) and free.has(anchor) else [])+ordered
	var leader_index := 0
	for i in range(members.size()):
		if members[i].threat > members[leader_index].threat: leader_index = i
	for start in anchors:
		if door_distance(start,doors) < 3: continue
		var taken: Dictionary = {start:true}
		var placed := {leader_index:start}
		var ok := true
		for i in range(members.size()):
			if i == leader_index: continue
			var options: Array = []
			if members[i].role != "MELEE":
				for p in backline:
					if free.has(p) and not taken.has(p) and door_distance(p,doors) >= 3: options.append(p)
				if options.is_empty():
					for p in ordered:
						if taken.has(p) or door_distance(p,doors) < 3 or chebyshev(p,start) > 3: continue
						var near_obstacle := false
						for d in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT,Vector2i(1,1),Vector2i(-1,1),Vector2i(1,-1),Vector2i(-1,-1)]:
							if obstacles.has(p+d) or not free.has(p+d): near_obstacle = true
						if near_obstacle: options.append(p)
			if options.is_empty():
				for p in ordered:
					if not taken.has(p) and door_distance(p,doors) >= 3 and chebyshev(p,start) <= 2: options.append(p)
			if options.is_empty(): ok = false; break
			var pick: Vector2i = options[rng.randi_range(0,options.size()-1)]
			taken[pick] = true; placed[i] = pick
		if ok:
			for i in placed: members[i].pos = placed[i]
			return true
	return false
