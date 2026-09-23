extends RefCounted
## The run's NPC roster and its placement on each floor.
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
const Stances = preload("res://expedition/stances.gd")
const Abilities = preload("res://expedition/abilities.gd")
const Generator = preload("res://expedition/floor_generator.gd")
const Encounters = preload("res://expedition/encounter_builder.gd")
static var names: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/npc_names.json")).names
const COUNT := 10
const DUOS := 2
const SITUATIONS := ["FIGHTING","WOUNDED","RESTING"]

## Plan A shim: depth when the run has it, the expedition number before that.
static func depth(s) -> int:
	return int(s.depth) if s.get("depth") != null else int(s.expedition_number)

## Plan A shim: the generator's npc_rooms, else the rooms holding no encounter
## member and not the entry, farthest from the entry first.
static func npc_rooms(layout: Dictionary) -> Array:
	if layout.has("npc_rooms"): return layout.npc_rooms
	var busy: Dictionary = {}
	for e in layout.encounters:
		for r in layout.rooms:
			if e.members.any(func(m): return r.rect.has_point(m.pos)): busy[r.id] = true
	for r in layout.rooms:
		if r.rect.has_point(layout.entry): busy[r.id] = true
	var plain: Array = layout.rooms.filter(func(r): return not busy.has(r.id))
	plain.sort_custom(func(a,b): return Generator.center(a).distance_to(Vector2(layout.entry)) > Generator.center(b).distance_to(Vector2(layout.entry)))
	return plain.slice(0,5).map(func(r): return r.id)

static func generate(s) -> Array:
	var rows: Array = []
	var pool: Array = names.duplicate()
	for i in range(COUNT):
		var id: int = 100+i
		var pick: int = Hexaco.sample(s.seed_value,id,"npc_name",pool.size())
		var actor: Dictionary = s.make_actor(id,pool.pop_at(pick),false)
		actor.profile = Hexaco.generated(s.seed_value,id)
		actor.stance = Stances.default_stance(actor.profile)
		actor.knobs = s.Knobs.defaults(actor.profile)
		actor.stress = Hexaco.sample(s.seed_value,id,"npc_stress",41)
		actor.equipped_abilities = ["",""]; actor.rules = []
		if Hexaco.sample(s.seed_value,id,"npc_part",100) < 40:
			var parts: Array = Abilities.droppable()
			var part: String = parts[Hexaco.sample(s.seed_value,id,"npc_part_id",parts.size())]
			actor.equipped_abilities[0] = part; actor.rules = [Abilities.default_rule(part)]
		actor.merge({"npc":true,"awake":false,"mode":"","mode_until":0,"hungry":false,"partner":-1,"bond":"",
			"state":"UNMET","floor_seen":0,"activity":"","explains":[],"noise_seen":-99,"declined_until":-99,"offered_until":-99})
		rows.append(actor)
	for d in range(DUOS):
		var a: Dictionary = rows[d*2]; var b: Dictionary = rows[d*2+1]
		a.partner = b.id; b.partner = a.id
		var bond: String = "close" if Hexaco.sample(s.seed_value,a.id,"npc_bond",100) < 60 else "strained"
		a.bond = bond; b.bond = bond
	s.roster = rows
	return rows

static func situation(npc: Dictionary) -> String:
	return str(npc.get("situation",""))

## Places three (the first floor) or four to five NPCs from the roster into the
## floor's npc rooms.
static func place(s) -> void:
	s.npcs = []
	var d: int = depth(s)
	var first_floor: bool = d <= 1 and s.roster.all(func(n): return n.state == "UNMET")
	var want: int = 3 if first_floor else 4+Hexaco.sample(s.seed_value,d,"npc_count",2)
	var rooms: Array = npc_rooms(s.floor_state.layout)
	if rooms.is_empty(): return
	var free: Array = s.roster.filter(func(n): return n.state in ["UNMET","MET"])
	free.sort_custom(func(a,b):
		if (a.state == "UNMET") != (b.state == "UNMET"): return a.state == "UNMET"
		return Hexaco.sample(s.seed_value,a.id,"npc_order",1000) < Hexaco.sample(s.seed_value,b.id,"npc_order",1000))
	var chosen: Array = []
	for n in free:
		if chosen.size() >= want: break
		if n in chosen: continue
		chosen.append(n)
		if n.partner >= 0:
			var mate: Array = free.filter(func(m): return m.id == n.partner)
			if not mate.is_empty() and chosen.size() < want and mate[0] not in chosen: chosen.append(mate[0])
	var room_i := 0
	var used: Dictionary = {}
	for n in chosen:
		var partner_here: bool = n.partner >= 0 and chosen.any(func(m): return m.id == n.partner and used.has(m.id))
		var room: Dictionary
		if partner_here:
			# Stand in the room the partner already occupies, not the next one in the cycle.
			var mate_pos: Vector2i = chosen.filter(func(m): return m.id == n.partner)[0].pos
			var host: Array = s.floor_state.layout.rooms.filter(func(r): return r.rect.has_point(mate_pos))
			room = host[0] if not host.is_empty() else s.floor_state.layout.rooms[rooms[(room_i+rooms.size()-1) % rooms.size()]]
		else:
			room = s.floor_state.layout.rooms[rooms[room_i % rooms.size()]]
			room_i += 1
		var cells: Array = Generator.floor_cells(s.floor_state.layout.terrain,s.floor_state.layout.size,room.rect).filter(func(p): return s.at(p).is_empty() and not s.floor_state.features.has(p))
		if partner_here:
			var mate_pos: Vector2i = chosen.filter(func(m): return m.id == n.partner)[0].pos
			cells = cells.filter(func(p): return s.distance(p,mate_pos) <= 2)
		if cells.is_empty(): continue
		n.pos = cells[Hexaco.sample(s.seed_value,d*1000+n.id,"npc_cell",cells.size())]
		var situ: String = SITUATIONS[Hexaco.sample(s.seed_value,d*1000+n.id,"npc_situation",3)] if not partner_here else situation(chosen.filter(func(m): return m.id == n.partner)[0])
		n.situation = situ
		if n.state == "MET": n.hp = maxi(1,n.hp-n.max_hp*(10+Hexaco.sample(s.seed_value,d*1000+n.id,"npc_wear",21))/100)
		match situ:
			"WOUNDED":
				n.hp = ceili(n.max_hp*(30+Hexaco.sample(s.seed_value,d*1000+n.id,"npc_hp",21))/100.0)
				s.stress(n,30); n.stress = maxi(int(n.stress),30)
			"FIGHTING":
				n.hp = ceili(n.max_hp*(60+Hexaco.sample(s.seed_value,d*1000+n.id,"npc_hp",21))/100.0)
				spawn_pack(s,n,room)
			"RESTING": pass
		n.hungry = situ != "RESTING" and Hexaco.sample(s.seed_value,d*1000+n.id,"npc_hungry",2) == 0
		n.state = "MET"; n.floor_seen = d; n.awake = false; n.mode = ""; n.ap = 1
		used[n.id] = true
		s.npcs.append(n)

## One small monster pack next to a fighting NPC, tagged with the NPC's id.
static func spawn_pack(s, npc: Dictionary, room: Dictionary) -> void:
	var theme: Dictionary = Generator.theme(str(s.floor_state.layout.get("theme_id","F1_RUINS")))
	var members: Array = Encounters.pack(theme,3,depth(s),s.seed_value+npc.id)
	var cells: Array = Generator.floor_cells(s.floor_state.layout.terrain,s.floor_state.layout.size,room.rect).filter(func(p): return s.at(p).is_empty() and s.distance(p,npc.pos) <= 2 and p != npc.pos)
	for i in range(mini(members.size(),cells.size())):
		var m: Dictionary = members[i]
		var enemy: Dictionary = s.make_actor(100+s.enemies.size(),m.display_name,true)
		enemy.pos = cells[i]; enemy.hp = int(m.max_health); enemy.max_hp = enemy.hp
		enemy.group = "NPC_%d" % npc.id; enemy.home = enemy.pos; enemy.alert = true
		enemy.species_id = m.species_id; enemy.tier = "early"; enemy.mandatory = false; enemy.npc_pack = npc.id
		s.Floor.MonsterAI.configure(enemy,m.role)
		enemy.part_id = Abilities.species_part(m.species_id)
		s.enemies.append(enemy)
