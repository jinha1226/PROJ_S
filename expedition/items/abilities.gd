extends RefCounted
## Parts catalog. One definition is both a monster's signature attack and the
## item the player equips: `passive` applies while equipped (or always, for the
## owning species), the active is executed by `resolve` for either side.
const DROP_PERCENT := 50
const NO_PASSIVE := {}
const IMMEDIATE := {"prep":0,"target":"NEAREST"}
const DEFINITIONS = {
	"PUSH":{"name":"밀치기","item":"밀치기 요령","description":"인접한 적을 한 칸 밀어냅니다. 밀 곳이 없으면 피해 8. 적의 예고 공격을 취소합니다.","target":"ENEMY","range":1,"radius":0,"damage":8,"cooldown":0,"effect":"PUSH","axis":"MELEE","rule_when":"CHARGING","short":"밀치기","shape":"SQUARE","self_hit":false,"icon":5,"species":"","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0},
	"GUARD":{"name":"엄호","item":"엄호 요령","description":"인접 아군이 받을 피해를 대신 받고 절반만 입습니다.","target":"ALLY","range":1,"radius":0,"damage":0,"cooldown":0,"effect":"GUARD","axis":"","rule_when":"ALLY_LETHAL","short":"엄호","shape":"SQUARE","self_hit":false,"icon":5,"species":"","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0},
	"SHOCKWAVE":{"name":"수렁 충격파","item":"수렁의 핵","description":"범위 2 · 피해 16 · 아군 피해 · 재사용 3턴","target":"SELF","range":0,"radius":2,"damage":16,"cooldown":3,"effect":"DAMAGE","axis":"MAGIC","rule_when":"ALWAYS","short":"충격파","shape":"CIRCLE","self_hit":false,"icon":4,"species":"","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":true,"tile_wet":0},
	"BOMB":{"name":"폭탄 투척","item":"암살자의 화약낭","description":"사거리 4 · 범위 1 · 피해 16 · 아군 피해 · 재사용 3턴","target":"ENEMY","range":4,"radius":1,"damage":16,"cooldown":3,"effect":"DAMAGE","axis":"RANGED","rule_when":"ALWAYS","short":"폭탄","shape":"SQUARE","self_hit":true,"icon":3,"species":"","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":true,"tile_wet":0},
	"IRON_HIDE":{"name":"철갑 방어","item":"거인의 철갑핵","description":"받는 피해 -75% · 1턴 · 재사용 3턴","target":"SELF","range":0,"radius":0,"damage":0,"cooldown":3,"effect":"SHIELD","axis":"","rule_when":"DANGER","short":"철갑","shape":"SQUARE","self_hit":false,"icon":5,"species":"","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0},
	"HEAVY_STRIKE":{"name":"시험 강타","item":"시험용 강타 문양","description":"인접 대상 · 피해 28 · 재사용 3턴","target":"ENEMY","range":1,"radius":0,"damage":28,"cooldown":3,"effect":"DAMAGE","axis":"MELEE","rule_when":"ALWAYS","short":"강타","shape":"SQUARE","self_hit":false,"icon":5,"species":"","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0},
	"THROWING_KNIFE":{"name":"시험 투척","item":"시험용 투척 문양","description":"사거리 4 · 피해 10 · 재사용 1턴","target":"ENEMY","range":4,"radius":0,"damage":10,"cooldown":1,"effect":"DAMAGE","axis":"RANGED","rule_when":"ALWAYS","short":"투척","shape":"SQUARE","self_hit":false,"icon":5,"species":"","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0},
	"FIELD_DRESSING":{"name":"시험 응급처치","item":"시험용 처치 문양","description":"자신 체력 +15 · 재사용 4턴","target":"SELF","range":0,"radius":0,"damage":0,"heal":15,"cooldown":4,"effect":"HEAL","axis":"","rule_when":"HP","short":"응급","shape":"SQUARE","self_hit":false,"icon":5,"species":"","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0},
	"LUNGE":{"name":"시험 돌진","item":"시험용 돌진 문양","description":"사거리 3 · 적 옆으로 이동 후 피해 12 · 재사용 3턴","target":"ENEMY","range":3,"radius":0,"damage":12,"cooldown":3,"effect":"LUNGE","axis":"MELEE","rule_when":"ALWAYS","short":"돌진","shape":"SQUARE","self_hit":false,"icon":5,"species":"","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0},
	"RAT_GNAW":{"name":"물어뜯기","item":"쥐 이빨","description":"무리: 인접 아군당 피해 +1 · 물어뜯기: 인접 대상 피해 9 · 재사용 2턴","target":"ENEMY","range":1,"radius":0,"damage":9,"cooldown":2,"effect":"DAMAGE","axis":"MELEE","rule_when":"ALWAYS","short":"물기","shape":"SQUARE","self_hit":false,"icon":5,"species":"dcss_rat","passive":{"kind":"PACK","value":1},"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"LIZARD_TAIL":{"name":"꼬리치기","item":"도마뱀 꼬리","description":"반격: 인접한 공격자에게 피해 2 · 꼬리치기: 대상 주위 3×3 피해 6 · 재사용 3턴","target":"ENEMY","range":1,"radius":1,"damage":6,"cooldown":3,"effect":"DAMAGE","axis":"MELEE","rule_when":"ALWAYS","short":"꼬리","shape":"SQUARE","self_hit":false,"icon":5,"species":"dcss_frilled_lizard","passive":{"kind":"RETALIATE","value":2},"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"KOBOLD_SLING":{"name":"투석","item":"코볼트 투석끈","description":"비열: 체력 절반 미만 대상에 피해 +3 · 투석: 사거리 4 피해 7 · 재사용 2턴","target":"ENEMY","range":4,"radius":0,"damage":7,"cooldown":2,"effect":"DAMAGE","axis":"RANGED","rule_when":"ALWAYS","short":"투석","shape":"SQUARE","self_hit":false,"icon":5,"species":"kobold","passive":{"kind":"DIRTY","value":3},"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"GOBLIN_SHIV":{"name":"기습","item":"고블린 단검","description":"기습: 고립된 대상에 피해 +3 · 기습: 사거리 3 이동 후 피해 10 · 재사용 3턴","target":"ENEMY","range":3,"radius":0,"damage":10,"cooldown":3,"effect":"LUNGE","axis":"MELEE","rule_when":"ALWAYS","short":"기습","shape":"SQUARE","self_hit":false,"icon":5,"species":"goblin","passive":{"kind":"AMBUSHER","value":3},"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"HOB_CLUB":{"name":"내려치기","item":"홉고블린 곤봉","description":"두꺼운 가죽: 받는 피해 -1 · 내려치기: 인접 대상 피해 14 · 재사용 3턴","target":"ENEMY","range":1,"radius":0,"damage":14,"cooldown":3,"effect":"DAMAGE","axis":"MELEE","rule_when":"ALWAYS","short":"곤봉","shape":"SQUARE","self_hit":false,"icon":5,"species":"dcss_hobgoblin","passive":{"kind":"THICK_HIDE","value":1},"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"ORC_CLEAVER":{"name":"휘두르기","item":"오크 도끼","description":"피의 갈망: 자신 체력 절반 미만이면 피해 +3 · 휘두르기: 대상 주위 3×3 피해 11 · 재사용 3턴","target":"ENEMY","range":1,"radius":1,"damage":11,"cooldown":3,"effect":"DAMAGE","axis":"MELEE","rule_when":"ALWAYS","short":"도끼","shape":"SQUARE","self_hit":false,"icon":5,"species":"dcss_orc","passive":{"kind":"BLOODLUST","value":3},"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"GNOLL_SPEAR":{"name":"창 찌르기","item":"놀 창","description":"재생: 라운드마다 체력 +2 · 창 찌르기: 사거리 2 피해 12 · 재사용 3턴","target":"ENEMY","range":2,"radius":0,"damage":12,"cooldown":3,"effect":"DAMAGE","axis":"MELEE","rule_when":"ALWAYS","short":"창","shape":"SQUARE","self_hit":false,"icon":5,"species":"dcss_gnoll","passive":{"kind":"REGEN","value":2},"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"RIVER_RAT_SPLASH":{"name":"물세례","item":"강쥐 가죽","description":"물갈퀴: 젖은 칸에서 피해 +3 · 물세례: 사거리 3 · 3×3 피해 5 · 칸을 적심 · 재사용 3턴","target":"ENEMY","range":3,"radius":1,"damage":5,"cooldown":3,"effect":"DAMAGE","axis":"RANGED","rule_when":"ALWAYS","short":"물","shape":"SQUARE","self_hit":false,"icon":5,"species":"dcss_river_rat","passive":{"kind":"AMPHIBIOUS","value":3},"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":70}}
## Actions that are not catalog parts.
const BASIC_BADGES := {"ATTACK":"공격","MOVE":"이동","WAIT":"대기"}

## Part ids that a species drops, in DEFINITIONS insertion order.
static func droppable() -> Array:
	var result: Array = []
	for id in DEFINITIONS:
		if not str(DEFINITIONS[id].species).is_empty(): result.append(id)
	return result

## The signature part of `species_id`, or "" when the species has none.
static func species_part(species_id: String) -> String:
	for id in DEFINITIONS:
		if str(DEFINITIONS[id].species) == species_id: return id
	return ""

## Short badge text for any action kind, catalog part or basic action.
static func badge(kind: String) -> String:
	return str(DEFINITIONS[kind].short) if DEFINITIONS.has(kind) else str(BASIC_BADGES.get(kind,kind))

static func default_rule(id: String) -> Dictionary:
	var def: Dictionary = DEFINITIONS[id]
	var target: String = {"SELF":"SELF","ALLY":"ALLY"}.get(def.target,"NEAREST")
	return preload("res://expedition/ai/tactic_rules.gd").make_rule(id,target,def.rule_when)

## Nearest free cell adjacent to the target that the actor can reach within the part's range.
static func lunge_cell(s, actor: Dictionary, id: String, target: Vector2i) -> Vector2i:
	var def: Dictionary = DEFINITIONS[id]
	var best := Vector2i(-1,-1)
	var best_len := 1 << 30
	for d in s.DIRECTIONS:
		var cell: Vector2i = target+d
		if not s.inside(cell) or not s.is_free(cell) or not s.melee_reach(cell,target): continue
		var route: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,actor.pos,[cell],func(a,b): return s.can_step(a,b),func(_p): return 100)
		if not route.found: continue
		var steps: int = route.path.size()-1
		if steps > int(def.range): continue
		if steps < best_len or (steps == best_len and str(cell) < str(best)): best = cell; best_len = steps
	return best

static func cells(s, actor: Dictionary, id: String, target: Vector2i) -> Array:
	var result: Array = []
	if not DEFINITIONS.has(id): return result
	var def: Dictionary = DEFINITIONS[id]
	var center: Vector2i = actor.pos if def.target == "SELF" else target
	for y in range(maxi(0,center.y-def.radius),mini(s.BOARD_SIDE,center.y+def.radius+1)):
		for x in range(maxi(0,center.x-def.radius),mini(s.BOARD_SIDE,center.x+def.radius+1)):
			var cell := Vector2i(x,y)
			var in_range: bool = s.distance(center,cell) <= def.radius if def.shape == "CIRCLE" else maxi(absi(center.x-x),absi(center.y-y)) <= def.radius
			if in_range and s.tile(cell).terrain != "wall" and s.TurnCore.Geometry.sees(center,cell,func(p): return s.tile(p).terrain == "wall"): result.append(cell)
	return result

## Party members grow; monsters hit for the listed damage plus the floor's darkness bonus.
static func power(s, actor: Dictionary, def: Dictionary) -> int:
	if actor.enemy: return int(def.damage)
	if s.manual_mode:
		var axis: String = "bow" if def.axis == "RANGED" else "hex" if def.axis == "MAGIC" else s.Mastery.weapon_axis(str(actor.get("gear",{}).get("weapon",{}).get("type","sword")))
		return int(def.damage)+s.Mastery.rank(actor,axis)
	return s.Growth.power(actor,def.axis,int(def.damage))

## Whether `actor` holds the part: a slot for party members, the species signature for monsters.
static func holds(actor: Dictionary, id: String) -> bool:
	return str(actor.get("part_id","")) == id if actor.enemy else id in actor.equipped_abilities

static func legal(s, actor: Dictionary, id: String, target: Vector2i) -> bool:
	if not DEFINITIONS.has(id) or not holds(actor,id) or actor.cooldowns.get(id,0) > 0: return false
	if s.phase != "BATTLE" or actor.hp <= 0 or not s.inside(target): return false
	if not actor.enemy and actor.ap <= 0: return false
	var def: Dictionary = DEFINITIONS[id]
	if def.target == "SELF":
		if def.effect == "HEAL" and actor.hp >= actor.max_hp: return false
		return target == actor.pos
	var victim: Dictionary = s.at(target)
	if victim.is_empty() or victim.hp <= 0: return false
	if def.target == "ALLY":
		return victim.enemy == actor.enemy and victim.id != actor.id and s.melee_reach(actor.pos,target)
	if victim.enemy == actor.enemy: return false
	# distance() is Manhattan, so a range-1 skill would miss the diagonals a
	# basic attack reaches; "adjacent" means melee_reach everywhere else.
	var in_range: bool = s.melee_reach(actor.pos,target) if int(def.range) == 1 else s.distance(actor.pos,target) <= int(def.range)
	if not in_range or not s.TurnCore.Geometry.sees(actor.pos,target,func(p): return s.tile(p).terrain == "wall"): return false
	if def.effect == "LUNGE": return lunge_cell(s,actor,id,target) != Vector2i(-1,-1)
	return true

static func execute(s, actor: Dictionary, id: String, target: Vector2i) -> bool:
	if not legal(s,actor,id,target): return false
	# Ranged and magical parts train only when they affect a hostile target.
	# Record before resolving damage so a killing blow receives its XP share.
	if s.manual_mode and not actor.enemy:
		var axis: String = "bow" if DEFINITIONS[id].axis == "RANGED" else "hex" if DEFINITIONS[id].axis == "MAGIC" else ""
		if not axis.is_empty():
			var affected: Array = cells(s,actor,id,target)
			for foe in s.enemies:
				if foe.hp > 0 and foe.pos in affected:
					s.Mastery.record(actor,int(foe.id),axis)
	resolve(s,actor,id,target)
	return true

## Resolves the part on `target` without a legality check: a telegraphed
## monster part lands on the announced cell whoever stands there now.
static func resolve(s, actor: Dictionary, id: String, target: Vector2i) -> void:
	var def: Dictionary = DEFINITIONS[id]
	var victim: Dictionary = s.at(target)
	# The use is logged first so that a miss is the last line the log shows.
	if def.effect not in ["GUARD","PUSH"]: s.message(actor.name+" · "+def.name)
	match def.effect:
		"SHIELD": actor.iron_guard = true
		"HEAL":
			var before: int = int(actor.hp)
			actor.hp = mini(int(actor.max_hp),int(actor.hp)+int(def.heal))
			s.Body.heal(actor)
			var row: Dictionary = s.member_stats(actor.id)
			if not row.is_empty(): row.healed += int(actor.hp)-before
		"GUARD":
			if victim.is_empty(): s.message(actor.name+"의 "+def.name+"가 빗나갔습니다.")
			else:
				actor["guarded"] = true
				victim["protected_by"] = actor.id
				var row: Dictionary = s.member_stats(actor.id)
				if not row.is_empty(): row.guards += 1
				s.message("%s · 엄호 → %s" % [actor.name,victim.name])
		"PUSH":
			if victim.is_empty(): s.message(actor.name+"의 "+def.name+"가 빗나갔습니다.")
			else:
				var destination: Vector2i = target+(target-actor.pos)
				if s.can_step(target,destination): victim.pos = destination
				else: s.damage(victim,power(s,actor,def),actor.id,"IMPACT")
				s.intents = s.intents.filter(func(intent): return intent.id != victim.id)
				if victim.get("boss",false) and victim.get("charging",false):
					victim.charging = false; victim.fuse = 0; victim.cooldown = 6; victim.recovery = 1
				else: s.Floor.MonsterAI.interrupt(s,victim)
				s.message("밀쳐내기 · 적의 예고 공격을 취소했습니다.")
		"LUNGE":
			var cell := lunge_cell(s,actor,id,target)
			if cell != Vector2i(-1,-1): actor.pos = cell
			# A telegraphed lunge lands on the announced cell, but never on the
			# caster's own side: a fellow monster who stepped in is a miss.
			var spared: bool = not victim.is_empty() and not def.allies_hit and victim.enemy == actor.enemy
			if victim.is_empty() or spared or cell == Vector2i(-1,-1): s.message(actor.name+"의 "+def.name+"가 빗나갔습니다.")
			else:
				s.effects.append({"kind":"ENEMY_ATTACK","from":actor.pos,"cell":target,"cells":[target],"area":false,"amount":0,"form":"SLASH"})
				s.damage(victim,power(s,actor,def),actor.id,"SLASH")
		"DAMAGE":
			var affected := cells(s,actor,id,target)
			var amount: int = power(s,actor,def)
			s.effects.append({"kind":"ENEMY_ATTACK","from":actor.pos,"cell":target,"cells":affected,"area":true,"amount":0,"form":"IMPACT"})
			var hit := 0
			for other in s.party+s.npcs+s.enemies:
				if other.hp <= 0 or other.id == actor.id or other.pos not in affected: continue
				if not def.allies_hit and other.enemy == actor.enemy: continue
				s.damage(other,amount,actor.id,"IMPACT"); hit += 1
			# Bombs can also hit the caster; self-centered shockwaves cannot.
			if def.self_hit and actor.pos in affected: s.damage(actor,amount,actor.id,"IMPACT"); hit += 1
			for cell in affected:
				if int(def.tile_wet) > 0: s.tile(cell).wet = maxi(int(s.tile(cell).wet),int(def.tile_wet))
			if hit == 0 and def.target != "SELF": s.message(actor.name+"의 "+def.name+"가 빗나갔습니다.")
	if int(def.cooldown) > 0: actor.cooldowns[id] = int(def.cooldown)+1
	# Who pressed what, for the battle report: the monsters' parts in one pot,
	# each member's in their own row.
	if actor.enemy: s.battle_stats.enemy_parts[id] = int(s.battle_stats.enemy_parts.get(id,0))+1
	else:
		var row: Dictionary = s.member_stats(actor.id)
		if not row.is_empty(): row.parts[id] = int(row.parts.get(id,0))+1
