extends RefCounted
## Stances: how a member uses whatever it has — charge in, keep range, or
## guard someone. Personality sets an aptitude per stance; the player may pick
## any stance, and an uncomfortable one conflicts like a knob does.
const IDS := ["CHARGER","SKIRMISHER","GUARDIAN"]
const NAMES := {"CHARGER":"돌격형","SKIRMISHER":"거리형","GUARDIAN":"호위형"}
const SHORT := {"CHARGER":"돌","SKIRMISHER":"거","GUARDIAN":"호"}
const Abilities = preload("res://expedition/abilities.gd")

static func aptitude(profile) -> Dictionary:
	return {"CHARGER":profile.value("X")-profile.value("E"),
		"SKIRMISHER":profile.value("E")+profile.value("C")-1000,
		"GUARDIAN":profile.value("A")+profile.value("H")-1000}

static func default_stance(profile) -> String:
	var apt := aptitude(profile)
	var best: String = IDS[0]
	for id in IDS:
		if int(apt[id]) > int(apt[best]): best = id
	return best

## Within (200 + C/5) of the best aptitude: the conscientious tolerate more.
static func comfortable(profile, stance: String) -> bool:
	var apt := aptitude(profile)
	return int(apt.get(stance,-9999)) >= int(apt[default_stance(profile)])-(200+profile.value("C")/5)

## The equipped part with reach, if any: what a skirmisher keeps its distance with.
static func ranged_part(actor: Dictionary) -> String:
	for id in actor.equipped_abilities:
		var def: Dictionary = Abilities.DEFINITIONS.get(id,{})
		if def.is_empty(): continue
		if def.effect in ["DAMAGE","LUNGE"] and int(def.range) >= 3: return id
	return ""

## What the build hints at; a badge, never a rule.
static func suggested(actor: Dictionary) -> String:
	if not ranged_part(actor).is_empty(): return "SKIRMISHER"
	if actor.equipped_abilities.any(func(id): return Abilities.DEFINITIONS.get(id,{}).get("effect","") == "GUARD"): return "GUARDIAN"
	return "CHARGER"

## The stance the member actually fights in: chosen while calm, its own when anxious.
static func effective(actor: Dictionary) -> String:
	if int(actor.stress) >= 100: return default_stance(actor.profile)
	return str(actor.get("stance",default_stance(actor.profile)))

## The party's shared target: the attack order, else whoever a charger is on,
## else the nearest visible foe.
static func party_target(s) -> Dictionary:
	if s.party_command == "ATTACK_TARGET":
		for e in s.combat_enemies():
			if e.id == s.command_target: return e
	for a in s.alive():
		if effective(a) != "CHARGER": continue
		for e in s.combat_enemies():
			if s.melee_reach(a.pos,e.pos): return e
	var best_d := 999
	for a in s.alive():
		for e in s.combat_enemies():
			best_d = mini(best_d,s.distance(a.pos,e.pos))
	var nearest: Array = s.combat_enemies().filter(func(e): return s.alive().any(func(a): return s.distance(a.pos,e.pos) == best_d))
	if nearest.is_empty(): return {}
	# `basic_target` survives only as the tie-break between equally near foes.
	var lowest: bool = s.alive().any(func(a): return a.basic_target == "LOWEST_HP")
	nearest.sort_custom(func(x,y):
		if lowest and x.hp != y.hp: return x.hp < y.hp
		return x.id < y.id)
	return nearest[0]

## Whom a guardian covers: the explicit pick, else a skirmisher, else the
## member lowest on health.
static func protectee(s, actor: Dictionary) -> Dictionary:
	var idx: int = int(actor.get("protect_id",-1))
	if idx >= 0 and idx < s.party.size() and s.party[idx].hp > 0 and s.party[idx].id != actor.id: return s.party[idx]
	for a in s.alive():
		if a.id != actor.id and effective(a) == "SKIRMISHER": return a
	var best: Dictionary = {}
	for a in s.alive():
		if a.id == actor.id: continue
		if best.is_empty() or a.hp*100/a.max_hp < best.hp*100/best.max_hp: best = a
	return best

## Steps between two cells: movement is eight-way, so this and not Manhattan
## is what "beside" and "two cells out" mean.
static func steps_between(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x-b.x),absi(a.y-b.y))

## Foes closing on `target`: within two steps or telegraphing its cell.
static func threats_to(s, target: Dictionary) -> Array:
	return s.combat_enemies().filter(func(e): return steps_between(e.pos,target.pos) <= 2 or s.intents.any(func(i): return i.id == e.id and i.cell == target.pos))

## The living foe this member could reach soonest, or {}.
static func nearest_foe(s, actor: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for e in s.combat_enemies():
		if best.is_empty() or steps_between(actor.pos,e.pos) < steps_between(actor.pos,best.pos): best = e
	return best

## The foe this member would defend itself against: the shared target when it
## is already in reach, else whatever else is.
static func adjacent_foe(s, actor: Dictionary, target: Dictionary) -> Dictionary:
	if not target.is_empty() and s.melee_reach(actor.pos,target.pos): return target
	for e in s.combat_enemies():
		if s.melee_reach(actor.pos,e.pos): return e
	return {}

## Every first step that closes on that goal just as fast, the route's own step
## first: cohesion picks between them, so there has to be more than one.
## The fire-free route is tried first; if the only way through burns, the
## member walks it rather than standing still while a foe is reachable.
static func steps_toward(s, actor: Dictionary, goals: Array, avoid_contact: bool = false) -> Array:
	var ok: Array = goals.filter(func(g): return s.is_free(g) and (not avoid_contact or not s.combat_enemies().any(func(e): return s.melee_reach(g,e.pos))))
	if ok.is_empty(): return []
	var steps := route_steps(s,actor,ok,avoid_contact,false)
	return steps if not steps.is_empty() else route_steps(s,actor,ok,avoid_contact,true)

## The first steps of the shortest route, `through_fire` deciding whether a
## burning cell is merely expensive or forbidden.
static func route_steps(s, actor: Dictionary, goals: Array, avoid_contact: bool, through_fire: bool) -> Array:
	var can := func(a,b): return s.can_step(a,b) and (through_fire or int(s.tile(b).fire) == 0)
	var cost := func(p): return 100+(int(s.tile(p).fire) if through_fire else 0)
	var route: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,actor.pos,goals,can,cost)
	if not route.found or route.path.size() < 2: return []
	var first: Vector2i = route.path[1]
	var goal: Vector2i = route.goal
	var steps: Array = [first]
	for d in s.DIRECTIONS:
		var c: Vector2i = actor.pos+d
		if c == first or not s.can_step(actor.pos,c): continue
		if int(s.tile(c).fire) > int(s.tile(first).fire): continue
		if avoid_contact and s.combat_enemies().any(func(e): return s.melee_reach(c,e.pos)): continue
		if steps_between(c,goal) == steps_between(first,goal): steps.append(c)
	return steps

## One MOVE candidate per equally fast first step; the route's own step keeps
## the extra point, so it still wins when no knob says otherwise. `fallback`
## is where the member heads when nothing on `goals` can be reached at all.
static func approach(s, actor: Dictionary, goals: Array, score: int, reason: String, options: Array, avoid_contact: bool = false, fallback: Array = []) -> void:
	var steps := steps_toward(s,actor,goals,avoid_contact)
	if steps.is_empty() and not fallback.is_empty(): steps = steps_toward(s,actor,fallback)
	for i in range(steps.size()):
		options.append({"kind":"MOVE","cell":steps[i],"score":score+(1 if i == 0 else 0),"reason":reason})

## Cells beside the nearest foe: where a member goes when the shared target is
## out of reach entirely.
static func fallback_goals(s, actor: Dictionary, target: Dictionary) -> Array:
	var foe := nearest_foe(s,actor)
	if foe.is_empty() or foe.get("id",-1) == target.get("id",-2): return []
	return adjacent_free(s,foe.pos)

## Free cells within `radius` steps of a point: where a guardian settles when
## every cell beside its charge is taken.
static func near_free(s, point: Vector2i, radius: int) -> Array:
	var cells: Array = []
	for y in range(point.y-radius,point.y+radius+1):
		for x in range(point.x-radius,point.x+radius+1):
			var c := Vector2i(x,y)
			if s.inside(c) and s.is_free(c): cells.append(c)
	return cells

## Free cells from which `target_pos` can be struck in melee.
static func adjacent_free(s, target_pos: Vector2i) -> Array:
	var cells: Array = []
	for d in s.DIRECTIONS:
		if s.is_free(target_pos+d) and s.melee_reach(target_pos+d,target_pos): cells.append(target_pos+d)
	return cells

## Everything the stance would have this member do, scored. The selector ranks
## these against nothing else: no rule matched, so the stance decides.
static func candidates(s, actor: Dictionary, stance: String, knobs: Dictionary) -> Array:
	var options: Array = []
	var target := party_target(s)
	match stance:
		"CHARGER": charger(s,actor,target,knobs,options)
		"SKIRMISHER": skirmisher(s,actor,target,knobs,options)
		"GUARDIAN":
			var p := protectee(s,actor)
			if p.is_empty(): charger(s,actor,target,knobs,options)
			else: guardian(s,actor,p,target,knobs,options)
	return options

## 돌격형: close on the shared target and stay on it.
static func charger(s, actor: Dictionary, target: Dictionary, knobs: Dictionary, options: Array) -> void:
	# Fire underfoot is left before anything else is considered.
	var out := off_the_fire(s,actor,target)
	if out != actor.pos:
		options.append({"kind":"MOVE","cell":out,"score":150,"reason":"불길 회피"}); return
	if target.is_empty(): return
	# A telegraph is no reason to stop hitting — unless the posture is very
	# cautious, and then stepping off it is all this member does.
	# 문턱을 0으로 올리는 안은 측정 후 보류했다: 돌격형 단일 파티의 `deep_caster`는
	# 0.55 → 0.90으로 오르지만 솔로 완주가 3/8 → 2/8로 떨어져 설계 §4의 솔로 기준을
	# 깬다. 수치는 docs/balance/stance-gates.md "3차 측정"에 있다.
	if int(knobs.posture) <= -60 and s.intents.any(func(i): return i.cell == actor.pos):
		for d in s.DIRECTIONS:
			var c: Vector2i = actor.pos+d
			if s.can_step(actor.pos,c) and s.Tactics.danger(s,c) == 0:
				options.append({"kind":"MOVE","cell":c,"score":60,"reason":"예고 회피"}); return
	# Whatever is already swinging at this member is answered, target or not.
	var foe := adjacent_foe(s,actor,target)
	if not foe.is_empty():
		var preview: Dictionary = s.attack_preview(foe.pos,actor.id)
		options.append({"kind":"ATTACK","cell":foe.pos,"score":100+int(preview.get("damage",0))+int(knobs.posture)*15/100,"reason":"돌격 · 공격"})
	else:
		approach(s,actor,adjacent_free(s,target.pos),80,"돌격 · 접근",options,false,fallback_goals(s,actor,target))

## The neighbouring cell a burning member steps onto: never another fire, and
## as close to the target as the ring allows. `actor.pos` when it is not on fire
## or there is nowhere better.
static func off_the_fire(s, actor: Dictionary, target: Dictionary) -> Vector2i:
	if int(s.tile(actor.pos).fire) == 0: return actor.pos
	var best: Vector2i = actor.pos
	for d in s.DIRECTIONS:
		var c: Vector2i = actor.pos+d
		if not s.can_step(actor.pos,c) or int(s.tile(c).fire) > 0: continue
		if best == actor.pos: best = c; continue
		if target.is_empty(): continue
		if steps_between(c,target.pos) < steps_between(best,target.pos): best = c
	return best

## 거리형: hold the band its part reaches, or hit and break away without one.
static func skirmisher(s, actor: Dictionary, target: Dictionary, knobs: Dictionary, options: Array) -> void:
	if target.is_empty(): return
	for cell in s.movement_cells(actor.id):   # telegraphs are always avoided
		if s.Tactics.danger(s,cell) < s.Tactics.danger(s,actor.pos): options.append({"kind":"MOVE","cell":cell,"score":200,"reason":"위험 회피"})
	var part := ranged_part(actor)
	var d: int = s.distance(actor.pos,target.pos)
	# Contact is eight-way (movement's own definition, matching the rule filter
	# in tactical_action_selector.gd), and any foe counts, not only the shared
	# target — a diagonal attacker must trigger the opening step just the same.
	var in_contact: bool = s.combat_enemies().any(func(e): return s.melee_reach(actor.pos,e.pos))
	if not part.is_empty():
		var reach: int = int(Abilities.DEFINITIONS[part].range)-(1 if int(knobs.posture) > 50 else 0)
		if in_contact:
			var away: Vector2i = s.Tactics.retreat_cell(s,actor)
			if away != actor.pos: options.append({"kind":"MOVE","cell":away,"score":120,"reason":"거리 · 이탈"})
		elif d <= reach:
			var adjacent: Array = s.combat_enemies().filter(func(e): return s.melee_reach(actor.pos,e.pos))
			if not adjacent.is_empty(): options.append({"kind":"ATTACK","cell":adjacent[0].pos,"score":60,"reason":"거리 · 반격"})
			options.append({"kind":"WAIT","cell":actor.pos,"score":50,"reason":"거리 · 유지"})
		else:
			var goals: Array = []
			for y in range(target.pos.y-reach,target.pos.y+reach+1):
				for x in range(target.pos.x-reach,target.pos.x+reach+1):
					var g := Vector2i(x,y)
					if s.inside(g) and s.distance(g,target.pos) <= reach and s.distance(g,target.pos) >= 2: goals.append(g)
			approach(s,actor,goals,80,"거리 · 접근",options,true,fallback_goals(s,actor,target))
		return
	# No ranged part: approach, strike, break away.
	if bool(actor.get("hit_and_run",false)):
		var away: Vector2i = s.Tactics.retreat_cell(s,actor)
		if away != actor.pos: options.append({"kind":"MOVE","cell":away,"score":120,"reason":"치고 빠지기 · 이탈"})
		return
	if s.melee_reach(actor.pos,target.pos):
		options.append({"kind":"ATTACK","cell":target.pos,"score":100,"reason":"치고 빠지기 · 타격"})
	else:
		approach(s,actor,adjacent_free(s,target.pos),80,"치고 빠지기 · 접근",options,false,fallback_goals(s,actor,target))

## 호위형: stay on the protectee and put itself between them and what comes.
static func guardian(s, actor: Dictionary, p: Dictionary, target: Dictionary, knobs: Dictionary, options: Array) -> void:
	var threats := threats_to(s,p)
	var keep: int = 1 if int(knobs.cohesion) >= 0 else 2
	if not threats.is_empty():
		var t: Dictionary = threats[0]
		if s.melee_reach(actor.pos,t.pos):
			options.append({"kind":"ATTACK","cell":t.pos,"score":100+int(knobs.posture)*15/100,"reason":"호위 · 저지"})
		var gap: Vector2i = p.pos+Vector2i(signi(t.pos.x-p.pos.x),signi(t.pos.y-p.pos.y))
		if gap != actor.pos and s.is_free(gap):
			approach(s,actor,[gap],130 if s.Rules.lethal_threat(s,p) >= p.hp else 90,"호위 · 가로막기",options)
		return
	if steps_between(actor.pos,p.pos) <= keep:
		var foe := adjacent_foe(s,actor,target)
		if not foe.is_empty(): options.append({"kind":"ATTACK","cell":foe.pos,"score":60,"reason":"호위 · 공격"})
		else: advance(s,actor,p,target,keep,options)
		options.append({"kind":"WAIT","cell":actor.pos,"score":40,"reason":"호위 · 대기"})
	else:
		approach(s,actor,adjacent_free(s,p.pos),80,"호위 · 합류",options,false,near_free(s,p.pos,keep+1))

## 호위형 §2.3 (d): nothing threatens the charge and nothing is in reach, so the
## pair walks toward the shared target together rather than standing still.
## Every destination stays inside `keep+1` of the charge, so "advance" never
## becomes "abandon"; mutual guardians leapfrog forward a step at a time.
## Score 50 — under the 60 of a foe in reach, over the 40 of holding.
static func advance(s, actor: Dictionary, p: Dictionary, target: Dictionary, keep: int, options: Array) -> void:
	if target.is_empty(): return
	var band: int = keep+1
	var beside: Array = adjacent_free(s,target.pos)
	var goals: Array = beside.filter(func(c): return steps_between(c,p.pos) <= band)
	if not goals.is_empty():
		approach(s,actor,goals,50,"호위 · 동반 전진",options); return
	# Nothing beside the target is inside the band yet: take whichever first
	# step of the route to the target still is.
	var steps := steps_toward(s,actor,beside)
	for i in range(steps.size()):
		if steps_between(steps[i],p.pos) <= band:
			options.append({"kind":"MOVE","cell":steps[i],"score":50+(1 if i == 0 else 0),"reason":"호위 · 동반 전진"})

## Is the member where its stance wants it? What role_rounds tallies.
static func in_role(s, actor: Dictionary) -> bool:
	match effective(actor):
		"GUARDIAN":
			var p := protectee(s,actor)
			return not p.is_empty() and steps_between(actor.pos,p.pos) <= 2
		"SKIRMISHER":
			var target := party_target(s)
			if target.is_empty(): return false
			var part := ranged_part(actor)
			if part.is_empty(): return bool(actor.get("hit_and_run",false)) or s.melee_reach(actor.pos,target.pos)
			if s.combat_enemies().any(func(e): return s.melee_reach(actor.pos,e.pos)): return false
			var d: int = s.distance(actor.pos,target.pos)
			return d >= 2 and d <= int(Abilities.DEFINITIONS[part].range)
		_:
			var target := party_target(s)
			return not target.is_empty() and s.melee_reach(actor.pos,target.pos)
