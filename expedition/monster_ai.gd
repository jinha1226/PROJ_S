extends RefCounted
## Continuous-floor roles. Firing-position search adapts ../sim/stage_enemy_rules.gd.
const Melee = preload("res://expedition/floor_tactics_adapter.gd")
const ROLES := {
	"MELEE":{"label":"추격병","range":1,"damage":7},
	"RANGED":{"label":"궁수","range":5,"damage":6},
	"CASTER":{"label":"술사","range":4,"damage":4},
}

static func configure(enemy: Dictionary, role: String) -> void:
	enemy.role = role if ROLES.has(role) else "MELEE"
	enemy.name += " " + ROLES[enemy.role].label
	enemy.charging = false
	enemy.cast_cooldown = 2
	enemy.cast_recovery = 0

static func line(s, a: Vector2i, b: Vector2i, reach: int) -> bool:
	# Range uses eight-way tile distance; Geometry's circular cutoff must not trim diagonals.
	return distance(a,b) <= reach and s.TurnCore.Geometry.sees(a,b,func(p): return not s.inside(p) or s.tile(p).terrain == "wall",ceili(reach*sqrt(2.0)))

static func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x-b.x),absi(a.y-b.y))

static func interrupt(s, enemy: Dictionary) -> void:
	if not enemy.get("charging",false): return
	enemy.charging = false
	enemy.cast_recovery = 1
	enemy.cast_cooldown = 3
	s.intents = s.intents.filter(func(i): return i.id != enemy.id)
	s.message(enemy.name+"의 시전이 끊겼습니다.")

static func plan(s) -> void:
	s.intents.clear()
	for enemy in s.enemies:
		if enemy.hp > 0 and enemy.get("charging",false):
			s.intents.append({"id":enemy.id,"cell":enemy.cast_cell,"damage":14})

static func turn(s, enemy: Dictionary) -> void:
	var targets: Array = s.alive()
	if enemy.hp <= 0 or targets.is_empty(): return
	if targets.any(func(a): return line(s,enemy.pos,a.pos,9)): enemy.alert = true
	if not enemy.get("alert",false): return
	if targets.all(func(a): return distance(enemy.pos,a.pos) > 15):
		enemy.alert = false; enemy.charging = false; plan(s); return
	if enemy.get("cast_recovery",0) > 0:
		enemy.cast_recovery -= 1; return
	var role: String = enemy.get("role","MELEE")
	if role == "MELEE":
		var choice: Dictionary = Melee.new(s,enemy).choose(enemy)
		if choice.kind == "MOVE": enemy.pos = choice.cell
		elif choice.kind == "ATTACK": strike(s,enemy,s.at(choice.cell),7)
		return
	if enemy.get("charging",false):
		var cell: Vector2i = enemy.cast_cell
		enemy.charging = false; enemy.cast_cooldown = 3; plan(s)
		if line(s,enemy.pos,cell,4):
			s.enemy_attack_effect(enemy,[cell],true)
			var victim: Dictionary = s.at(cell)
			if not victim.is_empty() and not victim.enemy: s.damage(victim,14+s.floor_state.enemy_bonus(s.light),enemy.id,"ELECTRIC")
			s.message(enemy.name+"의 마법이 예고한 지점에 떨어졌습니다.")
		return
	targets.sort_custom(func(a,b): return distance(enemy.pos,a.pos) < distance(enemy.pos,b.pos))
	var reach: int = ROLES[role].range
	var ready: bool = enemy.get("cast_cooldown",2) <= 0
	enemy.cast_cooldown = maxi(0,int(enemy.get("cast_cooldown",2))-1)
	for target in targets:
		if s.melee_reach(enemy.pos,target.pos):
			strike(s,enemy,target,4); return # No endless retreat loop.
	for target in targets:
		if not line(s,enemy.pos,target.pos,reach): continue
		if role == "CASTER" and ready:
			enemy.charging = true; enemy.cast_cell = target.pos; plan(s)
			s.message(enemy.name+"가 마법을 준비합니다. 공격하면 시전을 끊을 수 있습니다.")
		else: strike(s,enemy,target,ROLES[role].damage)
		return
	# Search a bounded set of firing positions, then use the shared pathfinder.
	var goals: Array = []
	var target: Dictionary = targets[0]
	for y in range(maxi(0,target.pos.y-reach),mini(s.BOARD_SIDE,target.pos.y+reach+1)):
		for x in range(maxi(0,target.pos.x-reach),mini(s.BOARD_SIDE,target.pos.x+reach+1)):
			var p := Vector2i(x,y)
			if s.is_free(p) and distance(p,target.pos) >= 2 and line(s,p,target.pos,reach): goals.append(p)
	if goals.is_empty(): return
	var route: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,enemy.pos,goals,func(a,b): return s.can_step(a,b),func(_p): return 100,100,20)
	if route.found and route.path.size() > 1: enemy.pos = route.path[1]

static func strike(s, enemy: Dictionary, target: Dictionary, amount: int) -> void:
	if target.is_empty() or target.enemy: return
	s.enemy_attack_effect(enemy,[target.pos])
	s.damage(target,amount+s.floor_state.enemy_bonus(s.light),enemy.id,"ELECTRIC" if enemy.get("role","") == "CASTER" else "IMPACT")
