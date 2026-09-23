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

## Foes closing on `target`: within two cells or telegraphing its cell.
static func threats_to(s, target: Dictionary) -> Array:
	return s.combat_enemies().filter(func(e): return s.distance(e.pos,target.pos) <= 2 or s.intents.any(func(i): return i.id == e.id and i.cell == target.pos))

## Every first step that closes on that goal just as fast, the route's own step
## first: cohesion picks between them, so there has to be more than one.
static func steps_toward(s, actor: Dictionary, goals: Array, avoid_contact: bool = false) -> Array:
	var ok: Array = goals.filter(func(g): return s.is_free(g) and (not avoid_contact or not s.combat_enemies().any(func(e): return s.melee_reach(g,e.pos))))
	if ok.is_empty(): return []
	var route: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,actor.pos,ok,func(a,b): return s.can_step(a,b) and int(s.tile(b).fire) == 0,func(_p): return 100)
	if not route.found or route.path.size() < 2: return []
	var first: Vector2i = route.path[1]
	var goal: Vector2i = route.goal
	var steps: Array = [first]
	for d in s.DIRECTIONS:
		var c: Vector2i = actor.pos+d
		if c == first or not s.can_step(actor.pos,c) or int(s.tile(c).fire) > 0: continue
		if avoid_contact and s.combat_enemies().any(func(e): return s.melee_reach(c,e.pos)): continue
		if maxi(absi(c.x-goal.x),absi(c.y-goal.y)) == maxi(absi(first.x-goal.x),absi(first.y-goal.y)): steps.append(c)
	return steps

## One MOVE candidate per equally fast first step; the route's own step keeps
## the extra point, so it still wins when no knob says otherwise.
static func approach(s, actor: Dictionary, goals: Array, score: int, reason: String, options: Array, avoid_contact: bool = false) -> void:
	var steps := steps_toward(s,actor,goals,avoid_contact)
	for i in range(steps.size()):
		options.append({"kind":"MOVE","cell":steps[i],"score":score+(1 if i == 0 else 0),"reason":reason})

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
	if target.is_empty(): return
	if int(s.tile(actor.pos).fire) > 0:
		var out: Vector2i = s.Tactics.retreat_cell(s,actor)   # any adjacent step; fire is always left
		for d in s.DIRECTIONS:
			var c: Vector2i = actor.pos+d
			if s.can_step(actor.pos,c) and int(s.tile(c).fire) == 0: out = c; break
		if out != actor.pos: options.append({"kind":"MOVE","cell":out,"score":150,"reason":"불길 회피"})
	# A telegraph is no reason to stop hitting — unless the posture is very
	# cautious, and then stepping off it is all this member does.
	if int(knobs.posture) <= -60 and s.intents.any(func(i): return i.cell == actor.pos):
		for d in s.DIRECTIONS:
			var c: Vector2i = actor.pos+d
			if s.can_step(actor.pos,c) and s.Tactics.danger(s,c) == 0:
				options.append({"kind":"MOVE","cell":c,"score":60,"reason":"예고 회피"}); return
	if s.melee_reach(actor.pos,target.pos):
		var preview: Dictionary = s.attack_preview(target.pos,actor.id)
		options.append({"kind":"ATTACK","cell":target.pos,"score":100+int(preview.get("damage",0))+int(knobs.posture)*15/100,"reason":"돌격 · 공격"})
	else:
		approach(s,actor,adjacent_free(s,target.pos),80,"돌격 · 접근",options)

## 거리형: hold the band its part reaches, or hit and break away without one.
static func skirmisher(s, actor: Dictionary, target: Dictionary, knobs: Dictionary, options: Array) -> void:
	if target.is_empty(): return
	for cell in s.movement_cells(actor.id):   # telegraphs are always avoided
		if s.Tactics.danger(s,cell) < s.Tactics.danger(s,actor.pos): options.append({"kind":"MOVE","cell":cell,"score":200,"reason":"위험 회피"})
	var part := ranged_part(actor)
	var d: int = s.distance(actor.pos,target.pos)
	if not part.is_empty():
		var reach: int = int(Abilities.DEFINITIONS[part].range)-(1 if int(knobs.posture) > 50 else 0)
		if d < 2:
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
			approach(s,actor,goals,80,"거리 · 접근",options,true)
		return
	# No ranged part: approach, strike, break away.
	if bool(actor.get("hit_and_run",false)):
		var away: Vector2i = s.Tactics.retreat_cell(s,actor)
		if away != actor.pos: options.append({"kind":"MOVE","cell":away,"score":120,"reason":"치고 빠지기 · 이탈"})
		return
	if s.melee_reach(actor.pos,target.pos):
		options.append({"kind":"ATTACK","cell":target.pos,"score":100,"reason":"치고 빠지기 · 타격"})
	else:
		approach(s,actor,adjacent_free(s,target.pos),80,"치고 빠지기 · 접근",options)

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
	if s.distance(actor.pos,p.pos) <= keep:
		if not target.is_empty() and s.melee_reach(actor.pos,target.pos):
			options.append({"kind":"ATTACK","cell":target.pos,"score":60,"reason":"호위 · 공격"})
		options.append({"kind":"WAIT","cell":actor.pos,"score":40,"reason":"호위 · 대기"})
	else:
		approach(s,actor,adjacent_free(s,p.pos),80,"호위 · 합류",options)

## Is the member where its stance wants it? What role_rounds tallies.
static func in_role(s, actor: Dictionary) -> bool:
	match effective(actor):
		"GUARDIAN":
			var p := protectee(s,actor)
			return not p.is_empty() and s.distance(actor.pos,p.pos) <= 2
		"SKIRMISHER":
			var target := party_target(s)
			if target.is_empty(): return false
			var part := ranged_part(actor)
			if part.is_empty(): return bool(actor.get("hit_and_run",false)) or s.melee_reach(actor.pos,target.pos)
			var d: int = s.distance(actor.pos,target.pos)
			return d >= 2 and d <= int(Abilities.DEFINITIONS[part].range)
		_:
			var target := party_target(s)
			return not target.is_empty() and s.melee_reach(actor.pos,target.pos)
