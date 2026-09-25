extends RefCounted
## The run's NPC roster and its placement on each floor.
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
const Stances = preload("res://expedition/ai/stances.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Generator = preload("res://expedition/level/floor_generator.gd")
const Encounters = preload("res://expedition/level/encounter_builder.gd")
static var names: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/npc_names.json")).names
const COUNT := 10
const DUOS := 2
const SITUATIONS := ["FIGHTING","WOUNDED","RESTING"]

static func depth(s) -> int:
	return int(s.depth)

## The floor's npc rooms, as the generator laid them out (a boss floor has none).
static func npc_rooms(layout: Dictionary) -> Array:
	return layout.npc_rooms

static func generate(s) -> Array:
	var rows: Array = []
	var pool: Array = names.duplicate()
	for i in range(COUNT):
		var id: int = 1000+i
		var pick: int = Hexaco.sample(s.seed_value,id,"npc_name",pool.size())
		var actor: Dictionary = s.make_actor(id,pool.pop_at(pick),false)
		actor.profile = Hexaco.generated(s.seed_value,id)
		# A stranger's first opinion uses the same A/H relation that the living
		# world will update through later events. It stays on the roster row.
		var hero: Dictionary = s.party[0]
		actor.opinions[int(hero.id)] = clampi((actor.profile.value("A")+hero.profile.value("A"))/40-absi(actor.profile.value("H")-hero.profile.value("H"))/40,-30,30)
		var weapon := "sword"
		if actor.profile.value("X") >= 600: weapon = "axe" if i % 2 == 0 else "mace"
		elif actor.profile.value("C") >= 600: weapon = "spear" if i % 2 == 0 else "bow"
		actor.gear.weapon = {"type":weapon,"enchant":0}
		actor.gear.armour = {"type":"robe","enchant":0}
		actor.stance = Stances.default_stance(actor.profile)
		actor.knobs = s.Knobs.defaults(actor.profile)
		actor.stress = Hexaco.sample(s.seed_value,id,"npc_stress",41)
		actor.equipped_abilities = ["",""]; actor.rules = []
		if Hexaco.sample(s.seed_value,id,"npc_part",100) < 40:
			var parts: Array = Abilities.droppable()
			var part: String = parts[Hexaco.sample(s.seed_value,id,"npc_part_id",parts.size())]
			actor.equipped_abilities[0] = part; actor.rules = [Abilities.default_rule(part)]
		actor.merge({"npc":true,"awake":false,"hostile":false,"mode":"","mode_until":0,"hungry":false,"partner":-1,"bond":"",
			"state":"UNMET","floor_seen":0,"joined_floor":0,"activity":"","explains":[],"noise_seen":-99,"declined_until":-99,"offered_until":-99})
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
	# Nobody from the last floor is still standing there with an offer open.
	s.pending_offer = -1
	# Re-placing on a live floor: the packs this function minted last time go with it.
	s.enemies = s.enemies.filter(func(e): return not e.has("npc_pack"))
	var d: int = depth(s)
	var first_floor: bool = d <= 1 and s.roster.all(func(n): return n.state == "UNMET")
	var want: int = 3 if first_floor else 4+Hexaco.sample(s.seed_value,d,"npc_count",2)
	var rooms: Array = npc_rooms(s.floor_state.layout)
	if rooms.is_empty(): return
	var free: Array = s.roster.filter(func(n): return n.state in ["UNMET","MET"])
	# The order key is hashed once per NPC: a comparator must not do work per comparison.
	var order: Dictionary = {}
	for n in free: order[n.id] = Hexaco.sample(s.seed_value,n.id,"npc_order",1000)
	free.sort_custom(func(a,b):
		if (a.state == "UNMET") != (b.state == "UNMET"): return a.state == "UNMET"
		return order[a.id] < order[b.id])
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
		var lane: int = d*100000+n.id
		n.pos = cells[Hexaco.sample(s.seed_value,lane,"npc_cell",cells.size())]
		var situ: String = SITUATIONS[Hexaco.sample(s.seed_value,lane,"npc_situation",3)] if not partner_here else situation(chosen.filter(func(m): return m.id == n.partner)[0])
		n.situation = situ
		# A stranger arrives at the band its situation asks for; someone met before
		# carries last floor's wounds and loses another 10-30% of them (spec 5.2).
		if n.state == "MET":
			n.hp = maxi(1,ceili(n.hp*(90-Hexaco.sample(s.seed_value,lane,"npc_wear",21))/100.0))
		else:
			match situ:
				"WOUNDED": n.hp = ceili(n.max_hp*(30+Hexaco.sample(s.seed_value,lane,"npc_hp",21))/100.0)
				"FIGHTING": n.hp = ceili(n.max_hp*(60+Hexaco.sample(s.seed_value,lane,"npc_hp",21))/100.0)
				"RESTING": n.hp = n.max_hp
		if situ == "WOUNDED": s.stress(n,30)
		if situ == "FIGHTING": spawn_pack(s,n,room)
		n.hungry = situ != "RESTING" and Hexaco.sample(s.seed_value,lane,"npc_hungry",2) == 0
		# One action in hand, like a floor monster waking up.
		n.state = "MET"; n.floor_seen = d; n.awake = false; n.mode = ""; n.ap = 1
		used[n.id] = true
		s.npcs.append(n)

## One small monster pack next to a fighting NPC, tagged with the NPC's id.
static func spawn_pack(s, npc: Dictionary, room: Dictionary) -> void:
	var d: int = depth(s)
	var theme: Dictionary = Generator.theme(str(s.floor_state.layout.get("theme_id","F1_RUINS")))
	# The catalog ends at depth 8; deeper packs reuse its mature rows like the floor's own encounters do.
	var members: Array = Encounters.pack(theme,3,mini(d,6),s.seed_value+d*100000+npc.id)
	var cells: Array = Generator.floor_cells(s.floor_state.layout.terrain,s.floor_state.layout.size,room.rect).filter(func(p): return s.at(p).is_empty() and s.distance(p,npc.pos) <= 2 and p != npc.pos)
	for i in range(mini(members.size(),cells.size())):
		var m: Dictionary = members[i].duplicate(true)
		m.pos = cells[i]
		# Same minting as a generated encounter, solo health scaling included.
		var enemy: Dictionary = s.Floor.mint_enemy(s,m,"NPC_%d" % npc.id,"early",false)
		enemy.npc_pack = npc.id; enemy.alert = true
