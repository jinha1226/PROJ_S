extends RefCounted
## 3층 고블린 족장 (spec §7.1): 무리와 명령. While a minion stands the chief
## sits on its throne and gives one announced order a round; each order
## belongs to one minion and dies with it. With every minion down its nerve
## breaks: it rises to fight and takes thirty percent more from every blow.
const Common = preload("res://expedition/actors/bosses/boss_common.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
## species, monster role, the order it owns
const MINIONS := [["goblin","MELEE","FOCUS"],["goblin_archer","RANGED","VOLLEY"],["goblin_shield","MELEE","WALL"],["goblin_hexer","CASTER","CURSE"]]
const ORDERS := ["FOCUS","VOLLEY","WALL","CURSE"]
const ORDER_NAMES := {"FOCUS":"집중","VOLLEY":"화살비","WALL":"방진","CURSE":"저주"}
const VOLLEY_DAMAGE := 10
const FOCUS_TURNS := 2
const CURSE_TICKS := 300
const CLEAVE_DAMAGE := 12
const CLEAVE_EVERY := 3

static func spawn(s, boss: Dictionary, room: Dictionary, _depth: int) -> void:
	boss.order = ""; boss.order_index = 0; boss.order_target = -1; boss.morale_broken = false
	var cells: Array = s.Floor.Generator.room_backline(room).filter(func(p): return s.is_free(p))
	cells.sort_custom(func(a,b): return a.y < b.y or a.y == b.y and a.x < b.x)
	for i in range(mini(MINIONS.size(),cells.size())):
		var row: Array = MINIONS[i]
		var species: Dictionary = s.Encounters.species(str(row[0]))
		var member := {"display_name":str(species.get("display_name",row[0])),"max_health":int(species.get("max_health",30)),
			"species_id":str(row[0]),"role":str(row[1]),"pos":cells[i]}
		var minion: Dictionary = s.Floor.mint_enemy(s,member,"BOSS_GUARD","boss",true)
		minion.chief = int(boss.id); minion.order = str(row[2])

static func minions(s, boss: Dictionary) -> Array:
	return s.enemies.filter(func(e): return int(e.hp) > 0 and int(e.get("chief",-1)) == int(boss.id))

static func owner(s, boss: Dictionary, order: String) -> Dictionary:
	for minion in minions(s,boss):
		if str(minion.order) == order: return minion
	return {}

static func available(s, boss: Dictionary) -> Array:
	return ORDERS.filter(func(o): return not owner(s,boss,o).is_empty())

static func turn(s, boss: Dictionary) -> void:
	if not bool(boss.morale_broken) and minions(s,boss).is_empty(): break_morale(s,boss)
	if bool(boss.morale_broken):
		fight(s,boss); return
	if not str(boss.order).is_empty(): carry_out(s,boss)
	give_order(s,boss)

static func break_morale(s, boss: Dictionary) -> void:
	boss.morale_broken = true; boss.order = ""
	Common.clear(boss)
	s.message("%s · 사기 붕괴! 왕좌에서 일어납니다" % boss.name)

## The next order still owned by a living minion, cycling in ORDERS order.
static func give_order(s, boss: Dictionary) -> void:
	var open: Array = available(s,boss)
	if open.is_empty(): return
	var order := ""
	for step in range(ORDERS.size()):
		var candidate: String = ORDERS[(int(boss.order_index)+step) % ORDERS.size()]
		if candidate in open:
			order = candidate
			boss.order_index = (ORDERS.find(candidate)+1) % ORDERS.size()
			break
	var mark: Dictionary = mark_for(s,boss,order)
	if mark.is_empty(): return
	var cells: Array = [mark.pos]
	var damage := 0
	if order == "VOLLEY":
		cells = Common.cells_within(s,mark.pos,1)
		damage = Abilities.scaled(boss,VOLLEY_DAMAGE)
	elif order == "WALL":
		var cell: Vector2i = wall_cell(s,boss,mark)
		if cell.x < 0: return
		cells = [cell]
	boss.order = order; boss.order_target = int(mark.id)
	Common.announce(boss,cells,damage,"CHIEF_"+order,1)
	s.message("%s 명령 · %s → %s" % [boss.name,ORDER_NAMES[order],mark.name])

## 집중 marks the weakest member; every other order the one nearest the throne.
static func mark_for(s, boss: Dictionary, order: String) -> Dictionary:
	var foes: Array = Common.victims(s,boss)
	if foes.is_empty(): return {}
	if order == "FOCUS":
		foes.sort_custom(func(a,b):
			var ra: float = float(a.hp)/maxf(1.0,float(a.max_hp))
			var rb: float = float(b.hp)/maxf(1.0,float(b.max_hp))
			return ra < rb if ra != rb else int(a.id) < int(b.id))
		return foes[0]
	return Common.target(s,boss)

## The free cell beside the chief closest to the marked member.
static func wall_cell(s, boss: Dictionary, mark: Dictionary) -> Vector2i:
	var best := Vector2i(-1,-1)
	for direction in s.DIRECTIONS:
		var cell: Vector2i = boss.pos+direction
		if not s.is_free(cell): continue
		if best.x < 0 or Common.reach(cell,mark.pos) < Common.reach(best,mark.pos): best = cell
	return best

static func carry_out(s, boss: Dictionary) -> void:
	var order: String = str(boss.order)
	var cells: Array = boss.telegraph.get("cells",[])
	var damage: int = int(boss.telegraph.get("damage",0))
	Common.clear(boss); boss.order = ""
	var who: Dictionary = owner(s,boss,order)
	var mark: Dictionary = s.actor_by_id(int(boss.order_target))
	if who.is_empty() or mark.is_empty() or int(mark.hp) <= 0: return
	match order:
		"FOCUS":
			for minion in minions(s,boss):
				minion.focus_id = int(mark.id); minion.focus_until = int(boss.turns)+FOCUS_TURNS
			s.message("%s · 모두 %s을(를) 노린다!" % [boss.name,mark.name])
		"VOLLEY":
			s.enemy_attack_effect(who,cells,true)
			for foe in Common.victims(s,boss):
				if foe.pos in cells: s.damage(foe,damage,int(who.id),"IMPACT")
		"WALL":
			if not cells.is_empty() and s.is_free(cells[0]): who.pos = cells[0]
			var part: String = Abilities.species_part(str(who.species_id))
			if Abilities.has(part) and str(Abilities.definition(part).target) == "SELF": Abilities.resolve(s,who,part,who.pos)
		"CURSE":
			s.Statuses.apply(s,mark,"weak",CURSE_TICKS)
			s.message("%s · 저주 → %s" % [who.name,mark.name])

## With its nerve gone the chief closes in, swings, and every third turn
## announces a sweep of the cells around it.
static func fight(s, boss: Dictionary) -> void:
	if not (boss.get("telegraph",{}) as Dictionary).is_empty():
		Common.count_down(s,boss); return
	var foe: Dictionary = Common.target(s,boss)
	if foe.is_empty(): return
	if int(boss.turns) % CLEAVE_EVERY == 0 and Common.reach(boss.pos,foe.pos) <= 1:
		Common.announce(boss,Common.cells_within(s,boss.pos,1),Abilities.scaled(boss,CLEAVE_DAMAGE),"CHIEF_CLEAVE",1)
		s.message("%s · 휘두르기 준비" % boss.name)
		return
	if s.melee_reach(boss.pos,foe.pos): Common.swing(s,boss,foe); return
	if s.status_blocks(boss,"MOVE"): return
	Common.step_toward(s,boss,foe)
	if s.melee_reach(boss.pos,foe.pos): Common.swing(s,boss,foe)
