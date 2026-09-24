extends SceneTree
## Utility selector: curves, profiles, inputs, scoring and explanations.
const Session = preload("res://expedition/session.gd")
const Utility = preload("res://expedition/ai/utility.gd")
const Stances = preload("res://expedition/ai/stances.gd")
const Knobs = preload("res://expedition/ai/knobs.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Parts = preload("res://expedition/ai/parts_candidates.gd")
const Lookahead = preload("res://expedition/ai/lookahead.gd")
## Every (stance, tag) pair the candidate generators in stances.gd can emit.
## 호위형 runs the charger programme whenever it has no living protectee, so it
## needs the charger's columns as well as its own.
const EMITTED := {
	"CHARGER": ["ATTACK","MOVE:approach","MOVE:sidestep"],
	"SKIRMISHER": ["ATTACK","MOVE:approach","MOVE:escape","MOVE:disengage","WAIT:hold"],
	"GUARDIAN": ["ATTACK","ATTACK:intercept","MOVE:advance","MOVE:block","MOVE:rejoin","WAIT:hold","MOVE:approach","MOVE:sidestep"]}
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func run() -> void:
	curves()
	profiles()
	inputs_and_score()
	commitment()
	parts()
	lookahead()
	oscillation()
	signed_weights_never_reward()
	retreat_needs_no_column()
	explanations()
	print("Utility: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func curves() -> void:
	check(Utility.curve("linear",0.25) == 0.25 and Utility.curve("inverse",0.25) == 0.75,"linear and inverse")
	check(Utility.curve("step",0.99) == 0.0 and Utility.curve("step",1.0) == 1.0,"step at 1")
	check(absf(Utility.curve("quad",0.5)-0.25) < 0.001 and absf(Utility.curve("sqrt",0.25)-0.5) < 0.001,"quad and sqrt")
	check(Utility.curve("linear",1.7) == 1.0 and Utility.curve("linear",-1.0) == 0.0,"inputs are clamped")
	check(Utility.curve("nope",0.5) == 0.5,"unknown curve is linear")
	check(Utility.curve("signed",-0.5) == -0.5 and Utility.curve("signed",-2.0) == -1.0 and Utility.curve("signed",2.0) == 1.0,"signed keeps the sign and clamps to -1..1")

func profiles() -> void:
	var p: Dictionary = Utility.profiles()
	check(p.has("considerations") and p.has("profiles") and p.has("personality"),"profile file shape")
	for stance in Stances.IDS: check(p.profiles.has(stance),"profile for "+stance)
	for stance in p.profiles:
		for tag in p.profiles[stance]:
			for cid in p.profiles[stance][tag]:
				check(p.considerations.has(cid),"%s/%s uses a known consideration %s" % [stance,tag,cid])
	for cid in p.personality: check(p.considerations.has(cid) and p.personality[cid].knob in Knobs.RANGE,"personality entry valid: "+cid)
	# Coverage: a candidate whose tag has no column scores 0 and is picked by
	# name alone, which is the bug this check exists to catch.
	for stance in EMITTED:
		for tag in EMITTED[stance]:
			check(p.profiles[stance].has(tag),"%s can emit %s, so it needs that column" % [stance,tag])
	# Cohesion has to reach every movement candidate, not only some of them.
	for stance in p.profiles:
		for tag in p.profiles[stance]:
			if str(tag).begins_with("MOVE"): check(p.profiles[stance][tag].has("ally_delta"),"%s/%s carries the cohesion term" % [stance,tag])
	check(Utility.tag({"kind":"MOVE","tag":"MOVE:approach"}) == "MOVE:approach" and Utility.tag({"kind":"HOB_CLUB"}) == "PART" and Utility.tag({"kind":"ATTACK"}) == "ATTACK","tags: explicit, part, default kind")

## Three members with basics, one foe two cells right of the hero.
func field(stances: Array, foes: int = 1) -> Dictionary:
	var s = Session.new(731,true,true,true,3); s.depart()
	var c := Fixture.arena(s,9); Fixture.equip_basics(s)
	for i in range(3):
		s.party[i].stance = stances[i]; s.party[i].knobs = Knobs.DEFAULT.duplicate(); s.party[i].stress = 0
		s.party[i].pos = c+Vector2i(0,i); s.mistake_override[s.party[i].id] = false
	var revived: Array = []
	for i in range(foes):
		var foe: Dictionary = s.enemies[i]
		foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.charging = false; foe.cast_recovery = 0; foe.part_id = ""
		foe.pos = c+Vector2i(2+i,0); revived.append(foe)
	s.floor_state.observe(s); s.selected = 0
	for a in s.party: a.ap = 1
	return {"s":s,"c":c,"foes":revived}

## The whole personality shift the profile asks of one knob at +100 for one tag:
## the sum of (shifted weight − base weight) × curve(input) over the scaled
## considerations it uses. A signed consideration's weight is clamped at 0 by
## the selector, so the knob's real reach there is the clamped difference.
func knob_shift(data: Dictionary, weights: Dictionary, knob: String, inp: Dictionary) -> float:
	var total := 0.0
	for cid in weights:
		var personal: Dictionary = data.personality.get(cid,{})
		if personal.is_empty() or str(personal.knob) != knob: continue
		var shape: String = str(data.considerations[cid].curve)
		var base: float = float(weights[cid])
		var shifted: float = base+100.0*float(personal.scale)
		if shape == "signed": base = maxf(0.0,base); shifted = maxf(0.0,shifted)
		total += (shifted-base)*Utility.curve(shape,float(inp.get(cid,0.0)))
	return total

func inputs_and_score() -> void:
	var f := field(["CHARGER","SKIRMISHER","GUARDIAN"]); var s = f.s; var hero: Dictionary = s.party[0]
	var ctx: Dictionary = Utility.context(s,hero)
	check(ctx.target.id == f.foes[0].id and ctx.has("protectee") and ctx.has("threats") and ctx.has("gap"),"context carries the shared target and the protectee's own facts")
	var step := {"kind":"MOVE","cell":hero.pos+Vector2i(1,0),"tag":"MOVE:approach","dir":Vector2i(1,0)}
	var inp: Dictionary = Utility.inputs(s,hero,step,ctx)
	check(inp.closes_distance == 0.5 and inp.target_adjacent == 1.0 and inp.cell_danger == 0.0,"approach step: closes half a band, lands adjacent, no safer and no worse")
	s.intents = [{"id":f.foes[0].id,"cell":step.cell,"damage":10,"kind":""}]
	inp = Utility.inputs(s,hero,step,ctx)
	check(inp.cell_danger == -10.0/float(hero.hp),"stepping onto a 10-damage telegraph is a negative delta")
	hero.pos = step.cell; s.floor_state.observe(s)
	var back := {"kind":"MOVE","cell":hero.pos+Vector2i(-1,0),"tag":"MOVE:approach","dir":Vector2i(-1,0)}
	check(Utility.inputs(s,hero,back,Utility.context(s,hero)).cell_danger == 10.0/float(hero.hp),"stepping off it is the same delta, positive")
	hero.pos = step.cell+Vector2i(-1,0); s.floor_state.observe(s)
	s.intents = []
	# Score: weights × curves, integer, deterministic, explained.
	var scored: Dictionary = Utility.score(s,hero,step,ctx,"CHARGER",Knobs.DEFAULT)
	check(scored.score is int and scored.score > 0 and scored.explain.size() <= 3 and scored.explain[0].contrib >= scored.explain.back().contrib,"score is an integer with a ranked explanation")
	check(scored == Utility.score(s,hero,step,ctx,"CHARGER",Knobs.DEFAULT),"deterministic")
	# Personality multiplier: posture +100 shifts every posture-scaled weight of
	# the tag at once (damage +15, la_self_hit −30 in the charger's ATTACK).
	# The foe is nearly down: the blow kills it, so the lookahead's `la_self_hit`
	# is a real positive delta and both posture-scaled terms of the column move.
	f.foes[0].pos = hero.pos+Vector2i(1,0); f.foes[0].hp = 5; s.floor_state.observe(s); ctx = Utility.context(s,hero)
	var atk := {"kind":"ATTACK","cell":f.foes[0].pos,"tag":"ATTACK","damage":18}
	var atk_inputs: Dictionary = Utility.inputs(s,hero,atk,ctx)
	check(atk_inputs.la_self_hit > 0.0 and atk_inputs.damage > 0.0,"the knob fixture drives both posture-scaled terms")
	var calm: int = Utility.score(s,hero,atk,ctx,"CHARGER",Knobs.DEFAULT).score
	var bold: Dictionary = Knobs.DEFAULT.duplicate(); bold.posture = 100
	var boldly: int = Utility.score(s,hero,atk,ctx,"CHARGER",bold).score
	var data: Dictionary = Utility.profiles()
	var expected: float = knob_shift(data,data.profiles.CHARGER.ATTACK,"posture",atk_inputs)
	check(int(round(expected)) != 0 and boldly-calm == int(round(expected)),"posture shifts the profile's posture-scaled weights")
	# Stance profiles differ: the same disengage step scores higher for a skirmisher than a charger.
	f.foes[0].hp = 30; s.floor_state.observe(s); ctx = Utility.context(s,hero)
	var away := {"kind":"MOVE","cell":hero.pos+Vector2i(-1,0),"tag":"MOVE:disengage","dir":Vector2i(-1,0)}
	check(Utility.score(s,hero,away,ctx,"SKIRMISHER",Knobs.DEFAULT).score > Utility.score(s,hero,away,ctx,"CHARGER",Knobs.DEFAULT).score,"profiles differ per stance")
	# The band is Manhattan, the metric the skirmisher's generator builds it with:
	# three cells out diagonally is six steps, outside a range-4 sling, while the
	# eight-way step count would call both of these cells in band.
	hero.equipped_abilities = ["KOBOLD_SLING","GUARD"]
	var ranged: Dictionary = Utility.context(s,hero)
	var corner := {"kind":"MOVE","cell":f.foes[0].pos+Vector2i(3,3),"tag":"MOVE:approach","dir":Vector2i(1,1)}
	var inside := {"kind":"MOVE","cell":f.foes[0].pos+Vector2i(2,2),"tag":"MOVE:approach","dir":Vector2i(1,1)}
	check(Utility.inputs(s,hero,corner,ranged).in_band == 0.0 and Utility.inputs(s,hero,inside,ranged).in_band == 1.0,"in_band is measured with s.distance, not the step count")
	hero.equipped_abilities = ["PUSH","GUARD"]
	# Candidates now carry tags and no scores; choose still picks the contract behaviour.
	var options: Array = Stances.candidates(s,hero,"CHARGER",Knobs.DEFAULT)
	check(not options.is_empty() and options.all(func(o): return o.has("tag") and not o.has("score")),"candidates are tagged and unscored")
	check(s.Tactics.choose(s,hero).kind == "ATTACK","adjacent foe: charger attacks")

## Commitment: the same kind as last round, and for a MOVE the same direction,
## is worth the profile's `same_as_last`. A new battle starts uncommitted.
func commitment() -> void:
	var f := field(["CHARGER","SKIRMISHER","GUARDIAN"]); var s = f.s; var hero: Dictionary = s.party[0]
	f.foes[0].pos = hero.pos+Vector2i(1,0); s.floor_state.observe(s)
	var atk := {"kind":"ATTACK","cell":f.foes[0].pos,"tag":"ATTACK","damage":18}
	var fresh: int = Utility.score(s,hero,atk,Utility.context(s,hero),"CHARGER",Knobs.DEFAULT).score
	hero.last_action_kind = "ATTACK"; hero.last_action_dir = Vector2i.ZERO
	var again: int = Utility.score(s,hero,atk,Utility.context(s,hero),"CHARGER",Knobs.DEFAULT).score
	check(again-fresh == 10,"striking the same way again is worth the profile's 10")
	var step := {"kind":"MOVE","cell":hero.pos+Vector2i(0,-1),"tag":"MOVE:approach","dir":Vector2i(0,-1)}
	hero.last_action_kind = "MOVE"; hero.last_action_dir = Vector2i(0,1)
	var turned: int = Utility.score(s,hero,step,Utility.context(s,hero),"CHARGER",Knobs.DEFAULT).score
	hero.last_action_dir = Vector2i(0,-1)
	var straight: int = Utility.score(s,hero,step,Utility.context(s,hero),"CHARGER",Knobs.DEFAULT).score
	check(straight-turned == 10,"a MOVE only commits when the direction matches too")
	s.reset_battle_stats()
	check(hero.last_action_kind == "" and hero.last_action_dir == Vector2i.ZERO,"a new battle starts uncommitted")

## 파츠는 같은 풀에서 경쟁한다: 밀치기·엄호도 후보이고, 규칙 조건(`rule_ready`)이
## 참일 때 그 파츠가 최고 점수를 받는다.
func parts() -> void:
	var f := field(["CHARGER","CHARGER","CHARGER"]); var s = f.s; var hero: Dictionary = s.party[0]
	f.foes[0].pos = hero.pos+Vector2i(1,0); s.floor_state.observe(s)
	var pool: Array = Parts.candidates(s,hero)
	check(pool.any(func(o): return o.kind == "PUSH" and o.tag == "PART") and pool.any(func(o): return o.kind == "GUARD" and o.cell == s.party[1].pos),"push and guard are part candidates")
	# Rule condition drives the part: a charging foe makes PUSH outscore the basic attack.
	s.intents = [{"id":f.foes[0].id,"cell":hero.pos,"damage":9,"kind":""}]; f.foes[0].charging = true
	check(s.Tactics.choose(s,hero).kind == "PUSH","charging foe: push (rule_ready) wins")
	s.intents = []; f.foes[0].charging = false
	check(s.Tactics.choose(s,hero).kind == "ATTACK","no telegraph: basic attack wins over an idle push")
	# Guard when an ally would die. The foe is not winding up: a charge would
	# also satisfy 밀치기's own rule, which is listed first, and the rule list's
	# order is a promise `rule_ready` keeps (등급형, 설계 §2).
	s.party[1].hp = 3; f.foes[0].pos = s.party[1].pos+Vector2i(1,0); s.floor_state.observe(s)
	s.intents = [{"id":f.foes[0].id,"cell":s.party[1].pos,"damage":9,"kind":""}]
	var pick: Dictionary = s.Tactics.choose(s,hero)
	check(pick.kind == "GUARD" and pick.cell == s.party[1].pos,"ally lethal: guard wins")
	s.intents = []; s.party[1].hp = s.party[1].max_hp
	# A skirmisher in contact never fires a ranged part.
	var g := field(["SKIRMISHER","CHARGER","CHARGER"]); var t = g.s; var h: Dictionary = t.party[0]
	h.equipped_abilities = ["KOBOLD_SLING","GUARD"]; h.rules = [t.Abilities.default_rule("KOBOLD_SLING"),t.Abilities.default_rule("GUARD")]; h.cooldowns = {}
	g.foes[0].pos = h.pos+Vector2i(1,1); t.floor_state.observe(t)
	check(t.Tactics.choose(t,h).kind != "KOBOLD_SLING","contact: the sling is penalised out")
	g.foes[0].pos = h.pos+Vector2i(3,0); t.floor_state.observe(t)
	check(t.Tactics.choose(t,h).kind == "KOBOLD_SLING","at range: fires")
	# The part choice carries an explanation naming rule_ready.
	check(t.Tactics.choose(t,h).explain.any(func(e): return e.id == "rule_ready"),"explanation names the rule")

## 설계 §3: one round ahead from public information only.
func lookahead() -> void:
	var f := field(["CHARGER","CHARGER","CHARGER"]); var s = f.s; var hero: Dictionary = s.party[0]
	# Stepping onto a telegraphed cell is predicted as damage to self.
	var cell: Vector2i = hero.pos+Vector2i(1,0)
	s.intents = [{"id":f.foes[0].id,"cell":cell,"damage":10,"kind":""}]; f.foes[0].charging = true
	var stay := Lookahead.predict(s,hero,{"kind":"WAIT","cell":hero.pos})
	var into := Lookahead.predict(s,hero,{"kind":"MOVE","cell":cell})
	check(stay.self == 0 and into.self >= 10,"moving into the telegraph costs at least the announced damage")
	# Guarding a lethal ally saves it.
	s.intents = [{"id":f.foes[0].id,"cell":s.party[1].pos,"damage":9,"kind":""}]; s.party[1].hp = 5
	var guard := Lookahead.predict(s,hero,{"kind":"GUARD","cell":s.party[1].pos})
	check(guard.lethal_saved == 1,"guard saves a lethal ally")
	# Pushing the caster cancels its intent.
	f.foes[0].pos = hero.pos+Vector2i(1,0); s.floor_state.observe(s)
	var push := Lookahead.predict(s,hero,{"kind":"PUSH","cell":f.foes[0].pos,"damage":8})
	check(push.lethal_saved == 1 and push.allies == 0,"push cancels the telegraph")
	s.intents = []; f.foes[0].charging = false; s.party[1].hp = s.party[1].max_hp
	# Killing blow is predicted as enemy damage and removes that foe's threat.
	f.foes[0].hp = 5
	var kill := Lookahead.predict(s,hero,{"kind":"ATTACK","cell":f.foes[0].pos,"damage":18})
	check(kill.enemies >= 5 and kill.self == 0,"a kill removes the foe's threat")
	# A killed caster's telegraph dies with it, not only a shoved one's.
	s.intents = [{"id":f.foes[0].id,"cell":hero.pos,"damage":10,"kind":""}]; f.foes[0].charging = true
	var was_hp: int = hero.hp
	hero.hp = 9
	var silenced := Lookahead.predict(s,hero,{"kind":"ATTACK","cell":f.foes[0].pos,"damage":18})
	check(silenced.self == 0 and silenced.lethal_saved == 1,"killing the caster drops its telegraph too")
	hero.hp = was_hp; s.intents = []; f.foes[0].charging = false
	# Inputs are wired: la_self_hit lower for the telegraphed step.
	f.foes[0].hp = 30; s.intents = [{"id":f.foes[0].id,"cell":cell,"damage":10,"kind":""}]; f.foes[0].charging = true
	var ctx: Dictionary = Utility.context(s,hero)
	check(Utility.inputs(s,hero,{"kind":"MOVE","cell":cell,"tag":"MOVE:approach"},ctx).la_self_hit < Utility.inputs(s,hero,{"kind":"WAIT","cell":hero.pos,"tag":"WAIT"},ctx).la_self_hit,"la_self_hit reads the predictor")
	s.lookahead_enabled = false
	check(Utility.inputs(s,hero,{"kind":"MOVE","cell":cell,"tag":"MOVE:approach"},ctx).la_self_hit == 0.0,"disabled: neutral is 0, not a paid bonus")
	s.lookahead_enabled = true

## Commitment has to beat the flip-flop: four rounds against a stationary foe
## must not come out A-B-A-B.
func oscillation() -> void:
	var f := field(["SKIRMISHER","CHARGER","CHARGER"]); var s = f.s; var h: Dictionary = s.party[0]
	h.equipped_abilities = ["KOBOLD_SLING","GUARD"]; h.rules = [s.Abilities.default_rule("KOBOLD_SLING"),s.Abilities.default_rule("GUARD")]; h.cooldowns = {}
	f.foes[0].pos = h.pos+Vector2i(5,0); f.foes[0].alert = false; s.floor_state.observe(s)
	var kinds: Array = []
	for round in range(4):
		h.ap = 1
		var pick: Dictionary = s.Tactics.choose(s,h)
		kinds.append(pick.kind+str(pick.get("dir",Vector2i.ZERO)))
		s.act_as(h,pick.kind,pick.cell,false)
	check(not (kinds[0] == kinds[2] and kinds[1] == kinds[3] and kinds[0] != kinds[1]),"no A-B-A-B: %s" % [kinds])

## A knob may not turn a signed penalty into a reward: at the boldest posture
## the danger terms fall to zero, never below it.
func signed_weights_never_reward() -> void:
	var f := field(["CHARGER","CHARGER","CHARGER"]); var s = f.s; var hero: Dictionary = s.party[0]
	var bold: Dictionary = Knobs.DEFAULT.duplicate(); bold.posture = 100
	var step := {"kind":"MOVE","cell":hero.pos+Vector2i(1,0),"tag":"MOVE:approach","dir":Vector2i(1,0)}
	s.intents = [{"id":f.foes[0].id,"cell":step.cell,"damage":10,"kind":""}]; f.foes[0].charging = true
	var ctx: Dictionary = Utility.context(s,hero)
	var inp: Dictionary = Utility.inputs(s,hero,step,ctx)
	check(inp.cell_danger < 0.0 and inp.la_self_hit < 0.0,"the telegraphed step is negative on both signed terms")
	var risky: Dictionary = Utility.score(s,hero,step,ctx,"CHARGER",bold)
	check(risky.explain.all(func(e): return e.id not in ["cell_danger","la_self_hit"] or e.contrib <= 0),"no signed danger term pays a bold member")
	s.intents = []; f.foes[0].charging = false
	var safe: Dictionary = Utility.score(s,hero,step,Utility.context(s,hero),"CHARGER",bold)
	check(risky.score <= safe.score,"stepping onto a telegraph never scores better than stepping onto a clear cell")

## The retreat line is the stage above the utility pool: its MOVE carries no tag
## and is ranked by the hand constant, so no profile column applies to it.
func retreat_needs_no_column() -> void:
	var f := field(["CHARGER","SKIRMISHER","GUARDIAN"]); var s = f.s; var hero: Dictionary = s.party[0]
	hero.hp = 1; hero.knobs.retreat_hp = 60
	var pick: Dictionary = s.Tactics.choose(s,hero)
	check(pick.kind == "MOVE" and pick.reason == "후퇴" and not pick.has("tag") and pick.score == s.Tactics.RETREAT.score,"the retreat MOVE is untagged and keeps its own constant")

## 설계 §6: `auto_step` files every choice's explanation in the member's battle
## row, newest last, and the row never grows past EXPLAIN_KEEP.
func explanations() -> void:
	var f := field(["CHARGER","SKIRMISHER","GUARDIAN"]); var s = f.s
	var hero: Dictionary = s.party[0]
	s.auto_step()
	var log: Array = s.member_stats(hero.id).get("explains",[])
	var first: Dictionary = log[0] if not log.is_empty() else {}
	check(not log.is_empty() and first.has("round") and first.has("kind") and first.has("cell") and first.explain is Array,"auto_step records round, kind, cell and explanation")
	check(log.any(func(e): return not (e.explain as Array).is_empty() and (e.explain as Array)[0].has("id") and (e.explain as Array)[0].has("contrib")),"at least one recorded round carries the utility terms")
	# The row is a window, not a transcript: the oldest entry is dropped.
	var row: Dictionary = s.member_stats(hero.id)
	row.explains = []
	for i in range(s.EXPLAIN_KEEP+5): s.note_explain(hero,{"kind":str(i),"cell":hero.pos,"explain":[]})
	var capped: Array = s.member_stats(hero.id).explains
	check(capped.size() == s.EXPLAIN_KEEP and capped[0].kind == "5" and capped[capped.size()-1].kind == str(s.EXPLAIN_KEEP+4),"the window keeps the last %d, oldest dropped" % s.EXPLAIN_KEEP)
