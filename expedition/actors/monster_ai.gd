extends RefCounted
## Continuous-floor roles plus the species signature part. Firing-position
## search adapts ../sim/stage_enemy_rules.gd. A monster that can use its part
## announces it (`prep` rounds) and resolves it on the announced cell; the
## caster role's own spell uses the same charging state with an empty cast_id.
const Melee = preload("res://expedition/actors/floor_tactics_adapter.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const BossAI = preload("res://expedition/actors/boss_ai.gd")
const ROLES := {
	"MELEE":{"label":"추격병","range":1,"damage":7},
	"RANGED":{"label":"궁수","range":5,"damage":6},
	"CASTER":{"label":"술사","range":4,"damage":4},
}
const SPELL_DAMAGE := 14
## Outside the floor (room mode, boss trial) monsters keep the old fixed reach.

## What a monster can see is what the party can see: the floor's light sets
## one radius for both sides, so nothing shoots from beyond the torchlight.
static func sight(s) -> int:
	return ceili(s.Floor.SIGHT_RADIUS)

static func configure(enemy: Dictionary, role: String) -> void:
	enemy.role = role if ROLES.has(role) else "MELEE"
	enemy.name += " " + ROLES[enemy.role].label
	enemy.charging = false
	enemy.cast_id = ""
	enemy.cast_left = 0
	enemy.cast_cooldown = 2
	enemy.cast_recovery = 0

static func line(s, a: Vector2i, b: Vector2i, reach: int) -> bool:
	# Range uses eight-way tile distance; Geometry's circular cutoff must not trim diagonals.
	return distance(a,b) <= reach and s.TurnCore.Geometry.sees(a,b,func(p): return not s.inside(p) or s.tile(p).terrain == "wall",ceili(reach*sqrt(2.0)))

static func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x-b.x),absi(a.y-b.y))

## Cancels any charge. 밀치기 reaches this directly; ordinary damage goes
## through on_hit(), which spares a part that is merely being wound up.
static func interrupt(s, enemy: Dictionary) -> void:
	if not enemy.get("charging",false): return
	var id: String = str(enemy.get("cast_id",""))
	enemy.charging = false
	enemy.cast_recovery = 1
	if id.is_empty(): enemy.cast_cooldown = 3
	else:
		enemy.cooldowns[id] = int(Abilities.DEFINITIONS[id].cooldown)
		s.battle_stats.interrupts = int(s.battle_stats.get("interrupts",0))+1
	enemy.cast_id = ""; enemy.cast_left = 0
	s.intents = s.intents.filter(func(i): return i.id != enemy.id)
	s.message(enemy.name+"의 시전이 끊겼습니다.")

## A hit breaks the caster role's own spell (it needs concentration) but not a
## signature part: a telegraphed part is answered by dodging, guarding or pushing.
static func on_hit(s, enemy: Dictionary) -> void:
	if enemy.get("boss",false): return
	if str(enemy.get("cast_id","")).is_empty(): interrupt(s,enemy)

static func plan(s) -> void:
	s.intents.clear()
	for enemy in s.enemies:
		if enemy.hp > 0 and enemy.get("boss",false): BossAI.plan(s,enemy); continue
		if enemy.hp <= 0 or not enemy.get("charging",false): continue
		var id: String = str(enemy.get("cast_id",""))
		var amount: int = int(Abilities.DEFINITIONS[id].damage) if Abilities.DEFINITIONS.has(id) else SPELL_DAMAGE
		# An area part announces every cell it will hit, so threat assessment and
		# the board see the whole ring, not just its centre.
		var cells: Array = Abilities.cells(s,enemy,id,enemy.cast_cell) if Abilities.DEFINITIONS.has(id) else [enemy.cast_cell]
		for cell in cells: s.intents.append({"id":enemy.id,"cell":cell,"damage":amount,"kind":id,"resolve_at":int(enemy.get("resolve_at",s.time+int(enemy.cast_left)*100))})

static func turn(s, enemy: Dictionary) -> void:
	# A dominated monster reads this list the other way round.
	var targets: Array = s.hostiles_of(enemy)
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
	if targets.all(func(a): return distance(enemy.pos,a.pos) > 15):
		enemy.alert = false; enemy.charging = false; enemy.cast_id = ""; enemy.cast_left = 0; plan(s)
		patrol(s,enemy)
		return
	if enemy.get("cast_recovery",0) > 0:
		enemy.cast_recovery -= 1; return
	var part: String = str(enemy.get("part_id",""))
	if Abilities.DEFINITIONS.has(part): enemy.cooldowns[part] = maxi(0,int(enemy.cooldowns.get(part,0))-1)
	if enemy.get("charging",false):
		if s.manual_mode:
			if s.time < int(enemy.get("resolve_at",s.time)): return
			enemy.cast_left = 0
		else: enemy.cast_left = int(enemy.get("cast_left",1))-1
		if enemy.cast_left > 0: plan(s); return
		var id: String = str(enemy.get("cast_id",""))
		var cell: Vector2i = enemy.cast_cell
		enemy.charging = false; enemy.cast_id = ""; plan(s)
		if id.is_empty(): resolve_spell(s,enemy,cell)
		else: Abilities.resolve(s,enemy,id,cell)
		return
	# A bound monster cannot work a manoeuvre that carries it anywhere; it is
	# left with whatever it can already reach.
	if Abilities.DEFINITIONS.has(part) and int(enemy.cooldowns.get(part,0)) <= 0 and not s.status_blocks(enemy,"MOVE"):
		targets.sort_custom(func(a,b): return distance(enemy.pos,a.pos) < distance(enemy.pos,b.pos))
		for target in targets:
			if not line(s,enemy.pos,target.pos,seen) or not Abilities.legal(s,enemy,part,target.pos): continue
			var prep: int = int(Abilities.DEFINITIONS[part].enemy.prep)
			if prep <= 0: Abilities.execute(s,enemy,part,target.pos); return
			enemy.charging = true; enemy.cast_id = part; enemy.cast_cell = target.pos; enemy.cast_left = prep
			enemy.resolve_at = s.time+prep*100
			plan(s); s.message("%s · %s 준비" % [enemy.name,Abilities.DEFINITIONS[part].name])
			return
	role_turn(s,enemy,targets,s.status_blocks(enemy,"MOVE"))

## An unalerted pack still takes its scheduled turns. Patrol stays near its
## encounter spawn, so distant enemies do not silently cross the whole floor.
static func patrol(s, enemy: Dictionary) -> void:
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

## The caster's own spell, cell-locked at SPELL_DAMAGE.
static func resolve_spell(s, enemy: Dictionary, cell: Vector2i) -> void:
	enemy.cast_cooldown = 3
	if not line(s,enemy.pos,cell,4): return
	s.enemy_attack_effect(enemy,[cell],true)
	var victim: Dictionary = s.at(cell)
	if not victim.is_empty() and s.side_of(victim) != s.side_of(enemy): s.damage(victim,SPELL_DAMAGE,enemy.id,"ELECTRIC")
	s.message(enemy.name+"의 마법이 예고한 지점에 떨어졌습니다.")

static func role_turn(s, enemy: Dictionary, targets: Array, held: bool = false) -> void:
	var role: String = enemy.get("role","MELEE")
	if role == "MELEE":
		var choice: Dictionary = Melee.new(s,enemy).choose(enemy)
		if choice.kind == "MOVE":
			if held: return
			enemy.pos = choice.cell
		elif choice.kind == "ATTACK": strike(s,enemy,s.at(choice.cell),7)
		return
	targets.sort_custom(func(a,b): return distance(enemy.pos,a.pos) < distance(enemy.pos,b.pos))
	var reach: int = mini(int(ROLES[role].range),sight(s))
	var ready: bool = enemy.get("cast_cooldown",2) <= 0
	enemy.cast_cooldown = maxi(0,int(enemy.get("cast_cooldown",2))-1)
	# An archer reloads for a round after every shot: half the volleys, and the
	# round in which closing the distance is not punished.
	var reloading: bool = role == "RANGED" and int(enemy.get("reload",0)) > 0
	if reloading: enemy.reload = int(enemy.reload)-1
	for target in targets:
		if s.melee_reach(enemy.pos,target.pos):
			strike(s,enemy,target,4); return # No endless retreat loop.
	for target in targets:
		if reloading: break
		if not line(s,enemy.pos,target.pos,reach): continue
		if role == "CASTER" and ready:
			enemy.charging = true; enemy.cast_id = ""; enemy.cast_cell = target.pos; enemy.cast_left = 1; enemy.resolve_at = s.time+100; plan(s)
			s.message(enemy.name+" · 시전")
		else:
			strike(s,enemy,target,ROLES[role].damage)
			if role == "RANGED": enemy.reload = 1
		return
	if reloading:
		s.message(enemy.name+" · 재장전")
		# Already in a firing spot: stand and reload rather than shuffle.
		if targets.any(func(a): return line(s,enemy.pos,a.pos,reach)): return
	# Search a bounded set of firing positions, then use the shared pathfinder.
	var goals: Array = []
	var target: Dictionary = targets[0]
	for y in range(maxi(0,target.pos.y-reach),mini(s.BOARD_SIDE,target.pos.y+reach+1)):
		for x in range(maxi(0,target.pos.x-reach),mini(s.BOARD_SIDE,target.pos.x+reach+1)):
			var p := Vector2i(x,y)
			if s.is_free(p) and distance(p,target.pos) >= 2 and line(s,p,target.pos,reach): goals.append(p)
	if goals.is_empty() or held: return
	var route: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,enemy.pos,goals,func(a,b): return s.can_step(a,b),func(_p): return 100,100,20)
	if route.found and route.path.size() > 1: enemy.pos = route.path[1]

static func strike(s, enemy: Dictionary, target: Dictionary, amount: int) -> void:
	if target.is_empty() or s.side_of(target) == s.side_of(enemy): return
	s.enemy_attack_effect(enemy,[target.pos])
	if s.manual_mode:
		enemy.power = amount
		s.CombatRules.attack(s,enemy,target)
	else: s.damage(target,amount,enemy.id,"ELECTRIC" if enemy.get("role","") == "CASTER" else "IMPACT")
