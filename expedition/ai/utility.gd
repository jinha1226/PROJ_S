extends RefCounted
## Utility selector: every candidate action is scored as Σ weight × curve(input)
## over a closed catalogue of considerations; the stance picks the weights,
## personality knobs shift them, and the top three terms explain the choice.
const Stances = preload("res://expedition/ai/stances.gd")
const Rules = preload("res://expedition/ai/tactic_rules.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Lookahead = preload("res://expedition/ai/lookahead.gd")
## The considerations that cost a prediction. A profile column with none of them
## skips `Lookahead.predict` entirely and reads the disabled-lookahead values.
const LOOKAHEAD_IDS := ["la_self_hit","la_ally_hit","la_enemy_hit","la_lethal_saved"]
static var _profiles: Dictionary = {}

static func profiles() -> Dictionary:
	if _profiles.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/tactics_profiles.json"))
		if parsed is Dictionary: _profiles = parsed
		else: push_error("tactics_profiles.json is not a JSON object; every candidate will score 0")
	return _profiles

## Every curve but `signed` reads a 0..1 input. `signed` is the exception the
## safety considerations need: a delta against standing pat, -1..1, where a
## worse cell is a real penalty and neutral is 0 rather than a paid bonus.
static func curve(name: String, x: float) -> float:
	if name == "signed": return clampf(x,-1.0,1.0)
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
	return "PART" if Abilities.has(str(action.kind)) else str(action.kind)

## Per-actor facts every candidate shares. Everything that depends on the
## protectee alone — whether it is about to die, and the cell that bodies the
## gap — is settled here rather than once per candidate.
## `pool` is the round's whole candidate list: `rule_ready` needs the siblings
## of a part candidate to say which of them a rule's target preference wants.
static func context(s, actor: Dictionary, pool: Array = []) -> Dictionary:
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
	# The baseline every safety consideration is measured against: what this
	# round costs if the member simply stands where it is. Predicted once.
	var stand: Dictionary = {"self":0,"allies":0,"enemies":0,"lethal_saved":0}
	# Who is already in lethal danger does not depend on the candidate either:
	# one `lethal_threat` pass per member, reused by every prediction this round.
	var before: Dictionary = {}
	if bool(s.lookahead_enabled):
		before = Lookahead.baseline(s)
		stand = Lookahead.predict(s,actor,{"kind":"WAIT","cell":actor.pos},before)
	var ally_hp := 0
	for mate in s.friends():
		if mate.id != actor.id: ally_hp += int(mate.hp)
	return {"pool":pool,"target":Stances.party_target(s),"protectee":protectee,"threats":threats,
		"protectee_lethal":lethal,"gap":gap,"ranged":Stances.ranged_part(actor),
		"stand":stand,"before_lethal":before,"ally_hp":ally_hp,"danger_now":int(s.Tactics.danger(s,actor.pos)),
		"last_kind":str(actor.get("last_action_kind","")),"last_dir":actor.get("last_action_dir",Vector2i.ZERO)}

## Every consideration's value for one candidate. `weights` is the profile
## column this candidate will be weighed against, when the caller has it: a
## column that asks for none of the `la_*` considerations never pays for a
## prediction. An empty `weights` (a direct caller, a test) computes them all.
static func inputs(s, actor: Dictionary, action: Dictionary, ctx: Dictionary, weights: Dictionary = {}) -> Dictionary:
	var kind: String = str(action.kind)
	var dest: Vector2i = action.cell if kind == "MOVE" else actor.pos
	var target: Dictionary = ctx.target
	var d_now: int = Stances.steps_between(actor.pos,target.pos) if not target.is_empty() else 0
	var d_then: int = Stances.steps_between(dest,target.pos) if not target.is_empty() else 0
	var damage: float = float(action.get("damage",0))
	var victim: Dictionary = s.at(action.cell) if kind != "MOVE" else {}
	# 설계 §2 개정(Task 3): the three safety considerations are signed deltas
	# against standing pat -- 0 means "no better and no worse than staying".
	var own_hp: float = maxf(1.0,float(actor.hp))
	var la_self := 0.0
	var la_ally := 0.0
	var la_enemy: float = damage/40.0
	var la_saved := 0.0
	var wanted: bool = weights.is_empty() or LOOKAHEAD_IDS.any(func(id): return weights.has(id))
	if bool(s.lookahead_enabled) and wanted:
		var stand: Dictionary = ctx.get("stand",{"self":0,"allies":0,"enemies":0})
		var after: Dictionary = Lookahead.predict(s,actor,action,ctx.get("before_lethal",{}))
		la_self = float(int(stand.self)-int(after.self))/own_hp
		la_ally = float(int(stand.allies)-int(after.allies))/maxf(1.0,float(ctx.get("ally_hp",0)))
		la_enemy = minf(1.0,float(after.enemies)/40.0)
		la_saved = minf(1.0,float(after.lethal_saved)/3.0)
	var result := {
		"target_adjacent": 1.0 if not target.is_empty() and s.melee_reach(dest,target.pos) else 0.0,
		"any_foe_adjacent": 1.0 if s.combat_enemies().any(func(e): return s.melee_reach(dest,e.pos)) else 0.0,
		"damage": damage/40.0,
		"kill": 1.0 if not victim.is_empty() and victim.get("enemy",false) and damage >= float(victim.hp) else 0.0,
		"closes_distance": maxf(0.0,float(d_now-d_then))/2.0,
		"opens_distance": maxf(0.0,float(d_then-d_now))/2.0,
		"in_band": 0.0,
		"cell_danger": float(int(ctx.get("danger_now",0))-int(s.Tactics.danger(s,dest)))/own_hp,
		"ally_delta": (float(s.Tactics.adjacent_allies(s,actor,dest)-s.Tactics.adjacent_allies(s,actor,actor.pos))+1.0)/2.0,
		"protectee_near": 0.0, "protectee_gap": 0.0, "protectee_lethal": 0.0,
		"rule_ready": 0.0, "contact_penalty": 0.0,
		"same_as_last": 1.0 if kind == ctx.last_kind and (kind != "MOVE" or action.get("dir",Vector2i.ZERO) == ctx.last_dir) else 0.0,
		"la_self_hit": la_self, "la_ally_hit": la_ally, "la_enemy_hit": la_enemy, "la_lethal_saved": la_saved}
	if not str(ctx.ranged).is_empty() and not target.is_empty():
		# The band is measured the way the skirmisher's own generator builds it:
		# `s.distance`, not the eight-way step count, and the part's raw range —
		# shrinking it at a bold posture is that generator's own preference.
		var reach: int = int(Abilities.definition(ctx.ranged).range)
		var band: int = s.distance(dest,target.pos)
		result.in_band = 1.0 if band >= 2 and band <= reach else 0.0
	var p: Dictionary = ctx.protectee
	if not p.is_empty():
		result.protectee_near = 1.0 if Stances.steps_between(dest,p.pos) <= 1 else 0.0
		result.protectee_lethal = 1.0 if bool(ctx.protectee_lethal) else 0.0
		result.protectee_gap = 1.0 if dest == ctx.gap else 0.0
	if Abilities.has(kind):
		var def: Dictionary = Abilities.definition(kind)
		result.rule_ready = rule_grade(s,actor,action,ctx)
		# Only a genuinely ranged part is holstered in contact: a MELEE dash part
		# (돌진·기습) reaches three cells precisely in order to close.
		if str(def.get("axis","")) == "RANGED" and int(def.range) >= 3 and s.combat_enemies().any(func(e): return s.melee_reach(actor.pos,e.pos)): result.contact_penalty = 1.0
	return result

## 설계 §2 `rule_ready`, Task 2 판정: 등급형이다. The rule list used to be a
## priority sort with a target preference inside it (`rule_choice`); both have
## to survive as a number now that the parts merely compete. The first matching
## rule gives 1.0 − 0.02·min(index,4) — a tiebreak between rules, not a scale —
## and a candidate its rule would not have targeted keeps four fifths of that.
## Rules for parts the member is not carrying are skipped before the count, the
## way `rule_choice` skipped them; `Rules.matches` already reads `enabled`.
static func rule_grade(s, actor: Dictionary, action: Dictionary, ctx: Dictionary) -> float:
	var index := 0
	for rule in actor.rules:
		if not Abilities.holds(actor,str(rule.get("skill",""))): continue
		if Rules.matches(s,actor,action,rule):
			var base: float = 1.0-0.02*float(mini(index,4))
			return base if preferred(s,actor,action,rule,ctx) else base*0.8
		index += 1
	return 0.0

## Whether `action` is the cell this rule would have picked among the sibling
## candidates of the same part: the lowest health for LOWEST_HP/ALLY, the
## nearest otherwise, ties by cell name — `rule_choice`'s old sort.
static func preferred(s, actor: Dictionary, action: Dictionary, rule: Dictionary, ctx: Dictionary) -> bool:
	var want: Vector2i = action.cell
	var mark: int = preference(s,actor,action.cell,rule)
	for other in ctx.get("pool",[]):
		if str(other.kind) != str(action.kind) or other.cell == want: continue
		if not Rules.matches(s,actor,other,rule): continue
		var value: int = preference(s,actor,other.cell,rule)
		if value < mark or (value == mark and str(other.cell) < str(want)): want = other.cell; mark = value
	return want == action.cell

static func preference(s, actor: Dictionary, cell: Vector2i, rule: Dictionary) -> int:
	if str(rule.get("target","")) in ["LOWEST_HP","ALLY"]:
		# An empty cell has no wound to follow: least preferred, not hp 0.
		var occupant: Dictionary = s.at(cell)
		return int(occupant.hp) if not occupant.is_empty() else 9999
	return int(s.distance(actor.pos,cell))

## Σ weight × curve(input) for the stance's column, rounded to an integer, with
## the three terms that carried it.
static func score(s, actor: Dictionary, action: Dictionary, ctx: Dictionary, stance: String, knobs: Dictionary) -> Dictionary:
	var data := profiles()
	var weights: Dictionary = data.profiles.get(stance,{}).get(tag(action),{})
	var inp := inputs(s,actor,action,ctx,weights)
	var total := 0.0
	var terms: Array = []
	var ids: Array = weights.keys(); ids.sort()
	for cid in ids:
		var weight: float = float(weights[cid])
		var personal: Dictionary = data.personality.get(cid,{})
		if not personal.is_empty(): weight += float(knobs.get(personal.knob,0))*float(personal.scale)
		var shape: String = str(data.considerations[cid].curve)
		# A signed consideration is a delta, so a knob that drives its weight
		# below zero would turn a penalty into a reward — a bold member would be
		# paid to step onto a telegraph. Bold means indifferent, never rewarded.
		if shape == "signed": weight = maxf(0.0,weight)
		var value: float = curve(shape,float(inp.get(cid,0.0)))
		var contrib: float = weight*value
		total += contrib
		terms.append({"id":cid,"input":inp.get(cid,0.0),"weight":weight,"contrib":int(round(contrib))})
	terms.sort_custom(func(a,b): return a.contrib > b.contrib if a.contrib != b.contrib else a.id < b.id)
	return {"score":int(round(total)),"explain":terms.slice(0,3)}
