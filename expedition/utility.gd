extends RefCounted
## Utility selector: every candidate action is scored as Σ weight × curve(input)
## over a closed catalogue of considerations; the stance picks the weights,
## personality knobs shift them, and the top three terms explain the choice.
const Stances = preload("res://expedition/stances.gd")
const Rules = preload("res://expedition/tactic_rules.gd")
const Abilities = preload("res://expedition/abilities.gd")
static var _profiles: Dictionary = {}

static func profiles() -> Dictionary:
	if _profiles.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/tactics_profiles.json"))
		if parsed is Dictionary: _profiles = parsed
		else: push_error("tactics_profiles.json is not a JSON object; every candidate will score 0")
	return _profiles

static func curve(name: String, x: float) -> float:
	x = clampf(x,0.0,1.0)
	match name:
		"inverse": return 1.0-x
		"step": return 1.0 if x >= 1.0 else 0.0
		"quad": return x*x
		"sqrt": return sqrt(x)
		_: return x

## Which column of the stance profile this action is weighed against: the tag
## the candidate generator put on it, else the part catalogue, else the kind.
static func tag(action: Dictionary) -> String:
	if action.has("tag"): return str(action.tag)
	return "PART" if Abilities.DEFINITIONS.has(str(action.kind)) else str(action.kind)

## Per-actor facts every candidate shares. Everything that depends on the
## protectee alone — whether it is about to die, and the cell that bodies the
## gap — is settled here rather than once per candidate.
static func context(s, actor: Dictionary) -> Dictionary:
	var protectee := Stances.protectee(s,actor)
	var threats: Array = []
	var lethal := false
	var gap := Vector2i(-1,-1)
	if not protectee.is_empty():
		threats = Stances.threats_to(s,protectee)
		lethal = Rules.lethal_threat(s,protectee) >= int(protectee.hp)
		if not threats.is_empty():
			var t: Dictionary = threats[0]
			gap = protectee.pos+Vector2i(signi(t.pos.x-protectee.pos.x),signi(t.pos.y-protectee.pos.y))
	return {"target":Stances.party_target(s),"protectee":protectee,"threats":threats,
		"protectee_lethal":lethal,"gap":gap,"ranged":Stances.ranged_part(actor),
		"last_kind":str(actor.get("last_action_kind","")),"last_dir":actor.get("last_action_dir",Vector2i.ZERO)}

## Every consideration's value for one candidate, all normalised to 0..1.
static func inputs(s, actor: Dictionary, action: Dictionary, ctx: Dictionary) -> Dictionary:
	var kind: String = str(action.kind)
	var dest: Vector2i = action.cell if kind == "MOVE" else actor.pos
	var target: Dictionary = ctx.target
	var d_now: int = Stances.steps_between(actor.pos,target.pos) if not target.is_empty() else 0
	var d_then: int = Stances.steps_between(dest,target.pos) if not target.is_empty() else 0
	var damage: float = float(action.get("damage",0))
	var victim: Dictionary = s.at(action.cell) if kind != "MOVE" else {}
	var result := {
		"target_adjacent": 1.0 if not target.is_empty() and s.melee_reach(dest,target.pos) else 0.0,
		"any_foe_adjacent": 1.0 if s.combat_enemies().any(func(e): return s.melee_reach(dest,e.pos)) else 0.0,
		"damage": damage/40.0,
		"kill": 1.0 if not victim.is_empty() and victim.get("enemy",false) and damage >= float(victim.hp) else 0.0,
		"closes_distance": maxf(0.0,float(d_now-d_then))/2.0,
		"opens_distance": maxf(0.0,float(d_then-d_now))/2.0,
		"in_band": 0.0, "cell_danger": 1.0-minf(1.0,float(s.Tactics.danger(s,dest))/20.0),
		"ally_delta": (float(s.Tactics.adjacent_allies(s,actor,dest)-s.Tactics.adjacent_allies(s,actor,actor.pos))+1.0)/2.0,
		"protectee_near": 0.0, "protectee_gap": 0.0, "protectee_lethal": 0.0,
		"rule_ready": 0.0, "contact_penalty": 0.0,
		"same_as_last": 1.0 if kind == ctx.last_kind and (kind != "MOVE" or action.get("dir",Vector2i.ZERO) == ctx.last_dir) else 0.0,
		"la_self_hit": 1.0, "la_ally_hit": 1.0, "la_enemy_hit": damage/40.0, "la_lethal_saved": 0.0}
	if not str(ctx.ranged).is_empty() and not target.is_empty():
		# The band is measured the way the skirmisher's own generator builds it:
		# `s.distance`, not the eight-way step count, and the part's raw range —
		# shrinking it at a bold posture is that generator's own preference.
		var reach: int = int(Abilities.DEFINITIONS[ctx.ranged].range)
		var band: int = s.distance(dest,target.pos)
		result.in_band = 1.0 if band >= 2 and band <= reach else 0.0
	var p: Dictionary = ctx.protectee
	if not p.is_empty():
		result.protectee_near = 1.0 if Stances.steps_between(dest,p.pos) <= 1 else 0.0
		result.protectee_lethal = 1.0 if bool(ctx.protectee_lethal) else 0.0
		result.protectee_gap = 1.0 if dest == ctx.gap else 0.0
	if Abilities.DEFINITIONS.has(kind):
		var def: Dictionary = Abilities.DEFINITIONS[kind]
		for rule in actor.rules:
			if rule.skill == kind and Rules.matches(s,actor,action,rule): result.rule_ready = 1.0
		if int(def.range) >= 3 and s.combat_enemies().any(func(e): return s.melee_reach(actor.pos,e.pos)): result.contact_penalty = 1.0
	return result

## Σ weight × curve(input) for the stance's column, rounded to an integer, with
## the three terms that carried it.
static func score(s, actor: Dictionary, action: Dictionary, ctx: Dictionary, stance: String, knobs: Dictionary) -> Dictionary:
	var data := profiles()
	var weights: Dictionary = data.profiles.get(stance,{}).get(tag(action),{})
	var inp := inputs(s,actor,action,ctx)
	var total := 0.0
	var terms: Array = []
	var ids: Array = weights.keys(); ids.sort()
	for cid in ids:
		var weight: float = float(weights[cid])
		var personal: Dictionary = data.personality.get(cid,{})
		if not personal.is_empty(): weight += float(knobs.get(personal.knob,0))*float(personal.scale)
		var value: float = curve(str(data.considerations[cid].curve),float(inp.get(cid,0.0)))
		var contrib: float = weight*value
		total += contrib
		terms.append({"id":cid,"input":inp.get(cid,0.0),"weight":weight,"contrib":int(round(contrib))})
	terms.sort_custom(func(a,b): return a.contrib > b.contrib if a.contrib != b.contrib else a.id < b.id)
	return {"score":int(round(total)),"explain":terms.slice(0,3)}
