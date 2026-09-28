extends RefCounted
## Ordinary monsters choose a basic move, attack or wait. Their species part
## supplies an automatic soul-stone effect, not an active attack. Bosses keep
## their separate encounter rules.
const Abilities = preload("res://expedition/items/abilities.gd")
const BossAI = preload("res://expedition/actors/boss_ai.gd")
const StoneEffects = preload("res://expedition/progression/stone_effects.gd")
const Utility = preload("res://expedition/ai/utility.gd")
const ROLES := {
	"MELEE":{"label":"추격병","range":1,"damage":7},
	"RANGED":{"label":"궁수","range":5,"damage":6},
	"CASTER":{"label":"술사","range":4,"damage":4},
}
## Outside the floor (room mode, boss trial) monsters keep the old fixed reach.

## Exploration visibility may be generous without waking monsters early.
const ALERT_SIGHT_RADIUS := 5
static func sight(_s) -> int:
	return ALERT_SIGHT_RADIUS

static func configure(enemy: Dictionary, role: String) -> void:
	enemy.role = role if ROLES.has(role) else "MELEE"
	enemy.name += " " + ROLES[enemy.role].label
	enemy.charging = false
	enemy.cast_id = ""
	enemy.cast_left = 0
	enemy.cast_cooldown = 2
	enemy.cast_recovery = 0

static func line(s, a: Vector2i, b: Vector2i, reach: int) -> bool:
	if s.free_movement: return s.Free.sees(s,s.Free.point(s,a),s.Free.point(s,b),reach)
	# Range uses eight-way tile distance; Geometry's circular cutoff must not trim diagonals.
	return distance(a,b) <= reach and s.TurnCore.Geometry.sees(a,b,func(p): return not s.inside(p) or s.tile(p).terrain == "wall" or int(s.tile(p).get("steam_until",0)) > int(s.time),ceili(reach*sqrt(2.0)))

static func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x-b.x),absi(a.y-b.y))

static func can_attack_target(s, enemy: Dictionary, target: Dictionary) -> bool:
	# Monsters keep pursuing beyond the camera, but cannot hit the hero from
	# a tile the player cannot see. Companions and NPCs still fight offscreen.
	return s.party.is_empty() or target != s.party[0] or s.floor_state.visible.has(enemy.pos)

## Compatibility for a pending cast loaded from an older save.
static func interrupt(s, enemy: Dictionary) -> void:
	if not enemy.get("charging",false): return
	enemy.charging = false
	enemy.cast_id = ""; enemy.cast_left = 0
	s.intents = s.intents.filter(func(i): return i.id != enemy.id)

## A hit also cancels any cast left in an older save.
static func on_hit(s, enemy: Dictionary) -> void:
	if enemy.get("boss",false): return
	interrupt(s,enemy)

static func plan(s) -> void:
	s.intents.clear()
	for enemy in s.enemies:
		if enemy.hp > 0 and enemy.get("boss",false): BossAI.plan(s,enemy)

static func turn(s, enemy: Dictionary) -> void:
	if s.time < int(enemy.get("sleep_until",0)): return
	# A dominated monster reads this list the other way round.
	var targets: Array = s.hostiles_of(enemy)
	var focus: Dictionary = BossAI.focus_of(s,enemy)
	if not focus.is_empty(): targets = [focus]
	if enemy.hp <= 0 or targets.is_empty(): return
	# 빙결 and 속박 hold a monster exactly as they hold the hero: the turn is
	# spent either way, but a frozen one neither steps nor swings and a bound
	# one can still reach whatever already stands beside it.
	if s.status_blocks(enemy,"ATTACK"): return
	var seen: int = sight(s)
	if targets.any(func(a): return line(s,enemy.pos,a.pos,seen)): enemy.alert = true
	if not enemy.get("alert",false):
		patrol(s,enemy)
		return
	if enemy.get("boss",false): BossAI.turn(s,enemy); return
	# An old save can contain a queued active. Discard it instead of firing
	# a skill that this combat model no longer has.
	if enemy.get("charging",false): interrupt(s,enemy)
	enemy.cast_recovery = 0
	if str(enemy.get("role","")) == "RANGED" and int(enemy.get("reload",0)) > 0:
		enemy.reload = int(enemy.reload)-1
		s.message(enemy.name+" · 재장전")
		return
	var taunter: Dictionary = taunter_of(s,enemy)
	if not taunter.is_empty():
		taunted_turn(s,enemy,taunter); return
	role_turn(s,enemy,targets,s.status_blocks(enemy,"MOVE"))

## An unalerted pack still takes its scheduled turns. Patrol stays near its
## encounter spawn, so distant enemies do not silently cross the whole floor.
static func patrol(s, enemy: Dictionary) -> void:
	if s.free_movement: s.Free.patrol(s,enemy); return
	if enemy.get("boss",false) or s.status_blocks(enemy,"MOVE"): return
	var home: Vector2i = enemy.get("home",enemy.pos)
	var heading: int = posmod(int(enemy.get("patrol_heading",int(enemy.id)+s.seed_value)),s.DIRECTIONS.size())
	for offset in range(s.DIRECTIONS.size()):
		var next_heading: int = (heading+offset)%s.DIRECTIONS.size()
		var cell: Vector2i = enemy.pos+s.DIRECTIONS[next_heading]
		if distance(home,cell) > 3 or not s.can_step(enemy.pos,cell): continue
		enemy.pos = cell
		enemy.patrol_heading = next_heading
		return

static func role_turn(s, enemy: Dictionary, targets: Array, held: bool = false) -> void:
	if s.free_movement:
		free_role_turn(s,enemy,targets,held); return
	var role: String = str(enemy.get("role","MELEE"))
	if not ROLES.has(role): role = "MELEE"
	var reach: int = mini(int(ROLES[role].range),sight(s))+StoneEffects.range_bonus(enemy,s)
	var options: Array = [{"kind":"WAIT","cell":enemy.pos,"reason":"대기"}]
	for target in targets:
		if not can_attack_target(s,enemy,target): continue
		var adjacent: bool = s.melee_reach(enemy.pos,target.pos)
		if not adjacent and not line(s,enemy.pos,target.pos,reach): continue
		var amount: int = int(enemy.get("basic_attack",ROLES[role].damage))
		if role != "MELEE" and adjacent: amount = 4
		options.append({"kind":"ATTACK","cell":target.pos,"target_id":int(target.id),"damage":amount,"reason":"공격"})
	if not held:
		var ordered: Array = targets.duplicate()
		ordered.sort_custom(func(a,b): return distance(enemy.pos,a.pos) < distance(enemy.pos,b.pos) if distance(enemy.pos,a.pos) != distance(enemy.pos,b.pos) else int(a.id) < int(b.id))
		if not ordered.is_empty():
			var target: Dictionary = ordered[0]
			var goals: Array = []
			for y in range(maxi(0,target.pos.y-reach),mini(s.BOARD_SIDE,target.pos.y+reach+1)):
				for x in range(maxi(0,target.pos.x-reach),mini(s.BOARD_SIDE,target.pos.x+reach+1)):
					var p := Vector2i(x,y)
					if not s.is_free(p) or distance(p,target.pos) > reach: continue
					if role != "MELEE" and distance(p,target.pos) < 2: continue
					if line(s,p,target.pos,reach): goals.append(p)
			if not goals.is_empty():
				var route: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,enemy.pos,goals,func(a,b): return s.can_step(a,b),func(_p): return 100,100,20)
				if route.found and route.path.size() > 1: options.append({"kind":"MOVE","cell":route.path[1],"reason":"접근"})
	var choice: Dictionary = Utility.combat_pick(s,enemy,options)
	match str(choice.kind):
		"MOVE": enemy.pos = choice.cell
		"ATTACK":
			var target: Dictionary = s.at(choice.cell)
			strike(s,enemy,target,int(choice.damage))
			if role == "RANGED" and not s.melee_reach(enemy.pos,target.pos): enemy.reload = 1

static func strike(s, enemy: Dictionary, target: Dictionary, amount: int) -> void:
	amount = int(enemy.basic_attack) if enemy.has("basic_attack") else Abilities.scaled(enemy,amount)
	if target.is_empty() or s.side_of(target) == s.side_of(enemy) and not (s.wanderer(target) and not s.dominated(enemy)): return
	if not can_attack_target(s,enemy,target): return
	s.enemy_attack_effect(enemy,[target.pos])
	if s.manual_mode:
		enemy.power = amount
		s.CombatRules.attack(s,enemy,target)
	else: s.damage(target,amount,enemy.id,"ELECTRIC" if enemy.get("role","") == "CASTER" else "IMPACT")

## Who taunted `enemy`, while the taunt lasts and the taunter stands.
static func taunter_of(s, enemy: Dictionary) -> Dictionary:
	if not enemy.get("statuses",{}).has("taunted"): return {}
	var who: Dictionary = s.actor_by_id(int(enemy.get("status_power",{}).get("taunted",-1)))
	return who if not who.is_empty() and int(who.hp) > 0 else {}

## A taunted monster strikes its taunter if it can, else steps toward it.
static func taunted_turn(s, enemy: Dictionary, taunter: Dictionary) -> void:
	if s.free_movement:
		if s.Free.reaches(s,enemy,taunter,1): strike(s,enemy,taunter,int(ROLES.MELEE.damage))
		else: s.Free.monster_move(s,enemy,taunter)
		return
	if s.melee_reach(enemy.pos,taunter.pos):
		strike(s,enemy,taunter,int(ROLES.MELEE.damage)); return
	if s.status_blocks(enemy,"MOVE"): return
	var goals: Array = []
	for direction in s.DIRECTIONS:
		var cell: Vector2i = taunter.pos+direction
		if s.inside(cell) and s.is_free(cell) and s.melee_reach(cell,taunter.pos): goals.append(cell)
	var route: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,enemy.pos,goals,func(a,b): return s.can_step(a,b),func(_p): return 100)
	if route.found and route.path.size() > 1: enemy.pos = route.path[1]

static func free_role_turn(s, enemy: Dictionary, targets: Array, held: bool) -> void:
	if targets.is_empty(): return
	targets.sort_custom(func(a,b): return s.Free.gap(enemy,a) < s.Free.gap(enemy,b))
	var role: String = str(enemy.get("role","MELEE"))
	var reach: float = minf(float(ROLES[role].range),float(sight(s)))+StoneEffects.range_bonus(enemy,s)
	var target: Dictionary = targets[0]
	if s.Free.reaches(s,enemy,target,reach) and can_attack_target(s,enemy,target):
		strike(s,enemy,target,int(ROLES[role].damage))
		if role == "RANGED": enemy.reload = 1
	elif not held: s.Free.monster_move(s,enemy,target,reach-0.05)
