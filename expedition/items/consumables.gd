extends RefCounted
## Run-local appearances and a shared bag of potions and scrolls.
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
const Body = preload("res://game/rebuilt/body_bridge.gd")
const Scheduler = preload("res://expedition/time/scheduler.gd")
const Statuses = preload("res://expedition/combat/statuses.gd")
const Summons = preload("res://expedition/spells/summons.gd")
static var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/consumables.json"))
const NO_TARGET := Vector2i(-1,-1)

static func definition(kind: String) -> Dictionary:
	for row in content.kinds:
		if row.id == kind: return row
	return {}

static func kinds() -> Array:
	return content.kinds.map(func(row): return str(row.id))

static func potions() -> Array:
	return content.kinds.filter(func(row): return row["class"] == "potion")

static func scrolls() -> Array:
	return content.kinds.filter(func(row): return row["class"] == "scroll")

static func shuffle_appearances(seed: int) -> Dictionary:
	var result := {}
	for category in ["potion","scroll"]:
		var rows: Array = potions() if category == "potion" else scrolls()
		var looks: Array = content.appearances[category].duplicate()
		for i in range(looks.size()-1,0,-1):
			var j: int = Hexaco.sample(seed,i,"appearance_"+category,i+1)
			var old = looks[i]; looks[i] = looks[j]; looks[j] = old
		for i in range(rows.size()):
			result[str(rows[i].id)] = "%s 물약" % looks[i] if category == "potion" else "'%s' 두루마리" % looks[i]
	return result

static func label(s, kind: String) -> String:
	var row: Dictionary = definition(kind)
	if row.is_empty(): return kind
	return str(row.name) if s.known.has(kind) else str(s.appearances.get(kind,row.name))

static func description(s, kind: String) -> String:
	return str(definition(kind).get("description","")) if s.known.has(kind) else "정체 불명"

static func random_kind(seed: int, key: int) -> String:
	var total := 0
	for row in content.kinds: total += int(row.weight)
	var roll: int = Hexaco.sample(seed,key,"item_kind",total)
	for row in content.kinds:
		roll -= int(row.weight)
		if roll < 0: return str(row.id)
	return str(content.kinds.back().id)

static func grant(s, kind: String, count: int = 1, known: bool = false) -> void:
	if definition(kind).is_empty() or count <= 0: return
	if known: s.known[kind] = true
	s.bag[kind] = int(s.bag.get(kind,0))+count
	s.message(label(s,kind)+" 획득")

static func pickup(s, actor: Dictionary) -> void:
	var feature: Dictionary = s.floor_state.features.get(actor.pos,{})
	if feature.get("kind","") != "item": return
	s.floor_state.features.erase(actor.pos)
	s.floor_state.clear_marker(actor.pos)
	grant(s,str(feature.get("item_id","")))

static func identify(s, kind: String) -> void:
	if definition(kind).is_empty() or s.known.has(kind): return
	var old: String = label(s,kind)
	s.known[kind] = true
	s.message(old+"은 "+label(s,kind)+"이었다")

static func spend(s, kind: String) -> void:
	var left: int = int(s.bag.get(kind,0))-1
	if left <= 0: s.bag.erase(kind)
	else: s.bag[kind] = left

static func use(s, kind: String, target: Vector2i = NO_TARGET, recipient: int = -1) -> bool:
	var row: Dictionary = definition(kind)
	if row.is_empty() or s.phase not in ["EXPLORE","BATTLE","CAMP"] or not s.pending_choice.is_empty(): return false
	if int(s.bag.get(kind,0)) <= 0 or s.party.is_empty() or s.selected < 0 or s.selected >= s.party.size(): return false
	if recipient < -1 or recipient >= s.party.size(): return false
	var user: Dictionary = s.party[s.selected]
	var actor: Dictionary = s.party[s.selected if recipient == -1 else recipient]
	if user.hp <= 0 or actor.hp <= 0 or s.on_floor() and user.ap <= 0: return false
	var thrown: bool = target != NO_TARGET
	if thrown:
		if row["class"] != "potion" or recipient != -1 or not s.on_floor() or not s.inside(target): return false
		if s.distance(user.pos,target) > 4 or not s.Floor.MonsterAI.line(s,user.pos,target,4): return false
	else:
		if row["class"] == "scroll" and recipient != -1: return false
	var effective := true
	if row["class"] == "potion":
		if thrown:
			if bool(row.area): effective = potion_area(s,kind,target,false)
		else: effective = drink(s,kind,actor)
	else: effective = read(s,kind,user)
	if not effective: return false
	spend(s,kind)
	if not thrown or bool(row.area): identify(s,kind)
	s.message(label(s,kind)+(" 투척" if thrown else " 사용"))
	if s.on_floor():
		user.ap -= 1
		if s.manual_mode:
			user.ap = 1
			Scheduler.advance(s,100)
		else: s.finish_player_action()
	return true

static func drink(s, kind: String, actor: Dictionary) -> bool:
	match kind:
		"healing":
			if actor.hp >= actor.max_hp and not actor.statuses.has("bleed"): return false
			actor.hp = mini(actor.max_hp,actor.hp+20); actor.statuses.erase("bleed"); Body.heal(actor)
		"strength":
			actor.str_bonus = int(actor.get("str_bonus",0))+3
			actor.max_hp += 5; actor.hp += 5
		"haste": Statuses.apply(s,actor,"haste",300)
		"liquid_flame", "frost", "toxic_gas":
			potion_area(s,kind,actor.pos,true)
		"experience":
			if actor.level >= 12: return false
			s.gain_level_xp(actor,actor.level*actor.level*65-int(actor.level_xp))
		"calm":
			if actor.stress <= 0: return false
			s.stress(actor,-25)
		_: return false
	return true

static func potion_area(s, kind: String, center: Vector2i, swallowed: bool) -> bool:
	for dy in range(-1,2):
		for dx in range(-1,2):
			var p := center+Vector2i(dx,dy)
			if not s.inside(p) or s.tile(p).terrain == "wall": continue
			var tile: Dictionary = s.tile(p)
			if kind == "liquid_flame" and tile.terrain == "wood": tile.fire = mini(100,int(tile.fire)+35)
			if kind == "frost": tile.wet = mini(100,int(tile.wet)+70)
			var victim: Dictionary = s.at(p)
			if victim.is_empty(): continue
			if kind == "liquid_flame": Statuses.apply(s,victim,"burn",100)
			elif kind == "frost": Statuses.apply(s,victim,"freeze",100)
			elif kind == "toxic_gas": Statuses.apply(s,victim,"poison",300)
	if swallowed and kind == "liquid_flame": Statuses.apply(s,s.at(center),"burn",100)
	elif swallowed and kind == "frost": Statuses.apply(s,s.at(center),"freeze",100)
	elif swallowed and kind == "toxic_gas": Statuses.apply(s,s.at(center),"poison",300)
	return true

static func read(s, kind: String, user: Dictionary) -> bool:
	match kind:
		"identify":
			identify(s,kind)
			var options: Array = s.bag.keys().filter(func(id): return id != kind and not s.known.has(id))
			options.sort()
			if options.is_empty(): s.message("감정할 것이 없다")
			else: s.pending_choice = {"kind":"identify","actor":s.selected,"options":options}
		"upgrade":
			var slots: Array = ["weapon","armour"].filter(func(slot): return not user.gear[slot].is_empty())
			if slots.is_empty(): return false
			s.pending_choice = {"kind":"upgrade","actor":s.selected,"options":slots}
		"magic_mapping":
			for y in range(s.floor_state.size):
				for x in range(s.floor_state.size):
					var p := Vector2i(x,y)
					if s.tile(p).terrain != "wall": s.floor_state.explored[p] = true
		"teleportation":
			var far: Array = []; var best := -1
			for y in range(s.floor_state.size):
				for x in range(s.floor_state.size):
					var p := Vector2i(x,y)
					if not s.is_free(p): continue
					var d: int = absi(p.x-user.pos.x)+absi(p.y-user.pos.y)
					if d >= 12: far.append(p)
					if d > best: best = d
			if far.is_empty():
				for y in range(s.floor_state.size):
					for x in range(s.floor_state.size):
						var p := Vector2i(x,y)
						if s.is_free(p) and absi(p.x-user.pos.x)+absi(p.y-user.pos.y) == best: far.append(p)
			if far.is_empty(): return false
			var index: int = Hexaco.sample(s.seed_value,s.time+s.serial,"teleportation",far.size())
			user.pos = far[index]
			pickup(s,user)
		"mirror_image":
			var cells: Array = Summons.summon_cells(s,user)
			for i in range(mini(2,cells.size())): Summons.summon(s,user,cells[i],"mirror")
		"lullaby":
			for enemy in s.enemies:
				if enemy.hp > 0 and s.floor_state.visible.has(enemy.pos):
					enemy.sleep_until = s.time+300; enemy.alert = false
		"rage":
			for enemy in s.enemies:
				if enemy.hp > 0: enemy.alert = true; Statuses.apply(s,enemy,"haste",200)
		"recharging":
			if user.mp >= user.max_mp: return false
			user.mp = user.max_mp
		_: return false
	return true

static func resolve_choice(s, option: String) -> bool:
	var choice: Dictionary = s.pending_choice
	if choice.is_empty() or option not in choice.options: return false
	if choice.kind == "identify": identify(s,option)
	elif choice.kind == "upgrade":
		var actor: Dictionary = s.party[int(choice.actor)]
		actor.gear[option].enchant = int(actor.gear[option].get("enchant",0))+1
		s.message(actor.name+" · "+option+" +1")
	else: return false
	s.pending_choice = {}
	return true
