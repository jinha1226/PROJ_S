extends SceneTree
## Utility selector: curves, profiles, inputs, scoring and explanations.
const Session = preload("res://expedition/session.gd")
const Utility = preload("res://expedition/utility.gd")
const Stances = preload("res://expedition/stances.gd")
const Knobs = preload("res://expedition/knobs.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
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
	print("Utility: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func curves() -> void:
	check(Utility.curve("linear",0.25) == 0.25 and Utility.curve("inverse",0.25) == 0.75,"linear and inverse")
	check(Utility.curve("step",0.99) == 0.0 and Utility.curve("step",1.0) == 1.0,"step at 1")
	check(absf(Utility.curve("quad",0.5)-0.25) < 0.001 and absf(Utility.curve("sqrt",0.25)-0.5) < 0.001,"quad and sqrt")
	check(Utility.curve("linear",1.7) == 1.0 and Utility.curve("linear",-1.0) == 0.0,"inputs are clamped")
	check(Utility.curve("nope",0.5) == 0.5,"unknown curve is linear")

func profiles() -> void:
	var p: Dictionary = Utility.profiles()
	check(p.has("considerations") and p.has("profiles") and p.has("personality"),"profile file shape")
	for stance in Stances.IDS: check(p.profiles.has(stance),"profile for "+stance)
	for stance in p.profiles:
		for tag in p.profiles[stance]:
			for cid in p.profiles[stance][tag]:
				check(p.considerations.has(cid),"%s/%s uses a known consideration %s" % [stance,tag,cid])
	for cid in p.personality: check(p.considerations.has(cid) and p.personality[cid].knob in Knobs.RANGE,"personality entry valid: "+cid)
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

## The whole personality shift the profile asks of one knob for one tag: the
## sum of 100 × scale × curve(input) over the scaled considerations it uses.
func knob_shift(data: Dictionary, weights: Dictionary, knob: String, inp: Dictionary) -> float:
	var total := 0.0
	for cid in weights:
		var personal: Dictionary = data.personality.get(cid,{})
		if personal.is_empty() or str(personal.knob) != knob: continue
		total += 100.0*float(personal.scale)*Utility.curve(str(data.considerations[cid].curve),float(inp.get(cid,0.0)))
	return total

func inputs_and_score() -> void:
	var f := field(["CHARGER","SKIRMISHER","GUARDIAN"]); var s = f.s; var hero: Dictionary = s.party[0]
	var ctx: Dictionary = Utility.context(s,hero)
	check(ctx.target.id == f.foes[0].id and ctx.has("hp_ratio") and ctx.has("threats"),"context carries the shared target")
	var step := {"kind":"MOVE","cell":hero.pos+Vector2i(1,0),"tag":"MOVE:approach","dir":Vector2i(1,0)}
	var inp: Dictionary = Utility.inputs(s,hero,step,ctx)
	check(inp.closes_distance == 0.5 and inp.target_adjacent == 1.0 and inp.cell_danger == 1.0,"approach step: closes half a band, lands adjacent, safe cell")
	s.intents = [{"id":f.foes[0].id,"cell":step.cell,"damage":10,"kind":""}]
	inp = Utility.inputs(s,hero,step,ctx)
	check(inp.cell_danger == 0.5,"telegraphed cell: danger 10/20 → 0.5")
	s.intents = []
	# Score: weights × curves, integer, deterministic, explained.
	var scored: Dictionary = Utility.score(s,hero,step,ctx,"CHARGER",Knobs.DEFAULT)
	check(scored.score is int and scored.score > 0 and scored.explain.size() <= 3 and scored.explain[0].contrib >= scored.explain.back().contrib,"score is an integer with a ranked explanation")
	check(scored == Utility.score(s,hero,step,ctx,"CHARGER",Knobs.DEFAULT),"deterministic")
	# Personality multiplier: posture +100 shifts every posture-scaled weight of
	# the tag at once (damage +15, la_self_hit −30 in the charger's ATTACK).
	f.foes[0].pos = hero.pos+Vector2i(1,0); s.floor_state.observe(s); ctx = Utility.context(s,hero)
	var atk := {"kind":"ATTACK","cell":f.foes[0].pos,"tag":"ATTACK","damage":18}
	var calm: int = Utility.score(s,hero,atk,ctx,"CHARGER",Knobs.DEFAULT).score
	var bold: Dictionary = Knobs.DEFAULT.duplicate(); bold.posture = 100
	var boldly: int = Utility.score(s,hero,atk,ctx,"CHARGER",bold).score
	var data: Dictionary = Utility.profiles()
	var expected: float = knob_shift(data,data.profiles.CHARGER.ATTACK,"posture",Utility.inputs(s,hero,atk,ctx))
	check(expected != 0.0 and boldly-calm == int(round(expected)),"posture shifts the profile's posture-scaled weights")
	# Stance profiles differ: the same disengage step scores higher for a skirmisher than a charger.
	var away := {"kind":"MOVE","cell":hero.pos+Vector2i(-1,0),"tag":"MOVE:disengage","dir":Vector2i(-1,0)}
	check(Utility.score(s,hero,away,ctx,"SKIRMISHER",Knobs.DEFAULT).score > Utility.score(s,hero,away,ctx,"CHARGER",Knobs.DEFAULT).score,"profiles differ per stance")
	# Candidates now carry tags and no scores; choose still picks the contract behaviour.
	var options: Array = Stances.candidates(s,hero,"CHARGER",Knobs.DEFAULT)
	check(not options.is_empty() and options.all(func(o): return o.has("tag") and not o.has("score")),"candidates are tagged and unscored")
	check(s.Tactics.choose(s,hero).kind == "ATTACK","adjacent foe: charger attacks")
