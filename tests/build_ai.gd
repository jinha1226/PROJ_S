extends SceneTree
const Fixture = preload("res://tests/followup_fixture.gd")
const Build = preload("res://expedition/ai/build_sense.gd")
const Tactics = preload("res://expedition/ai/tactical_action_selector.gd")
const Intent = preload("res://expedition/ui/companion_intent_ui.gd")
var checks := 0
var failures := 0
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(why)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var d := Fixture.reset(); var s = d.s
	Fixture.slot(d.hero,["LEECH_SEGMENT"])
	var other: Dictionary = d.foe.duplicate(true); other.id = 101; other.pos = Vector2i(4,4); other.statuses.bleed = 300; s.enemies.append(other)
	var choice: Dictionary = Tactics.choose(s,d.hero)
	check(choice.cell == other.pos,"bleeding target wins between two enemies already in reach")
	check(choice.get("reason_code","") == "BUILD_TARGET","reason records a selection changed by build preference")
	var ui := Intent.new()
	var text := ui.transition_line({"intent":"ATTACK","reason_code":"","target_id":100},Intent.adapt(d.hero,choice,101,1))
	check(text.contains("출혈"),"in-game reason uses a short build phrase")
	s.party_command = "ATTACK_TARGET"; s.command_target = int(d.foe.id)
	var ordered: Dictionary = s.companion_choice(d.hero)
	check(ordered.cell == d.foe.pos and not ordered.get("reason_code","").begins_with("BUILD"),"explicit attack order overrides build preference")
	d = Fixture.reset(s); Fixture.slot(d.hero,["ARCHER_EYE","KOBOLD_HEART"]); d.hero.gear.weapon = {"type":"bow"}; d.foe.pos = Vector2i(6,3)
	choice = Tactics.choose(s,d.hero)
	check(choice.kind not in ["MOVE","WAIT"] and choice.cell == d.foe.pos,"aiming archer shoots from current position instead of closing on melee")
	check(d.hero.pos == Vector2i(3,3),"decision preview leaves position unchanged")
	# A lethal telegraph cannot be overridden by even a very large build bonus.
	d.hero.hp = 10; s.intents = [{"id":100,"cell":d.hero.pos,"damage":50,"resolve_at":100}]
	var options: Array = [{"kind":"ATTACK","cell":d.foe.pos,"damage":1},{"kind":"MOVE","cell":Vector2i(2,3)}]
	var safe := Build.safe_options(s,d.hero,options,{})
	check(safe.size() == 1 and safe[0].kind == "MOVE","survival filter excludes lethal attack when an escape exists")
	# A distant recovering enemy can be left to an ally who acts before it.
	d = Fixture.reset(s); Fixture.slot(d.hero,["ARCHER_EYE"]); d.hero.gear.weapon = {"type":"bow"}; d.hero.pos = Vector2i(3,3)
	d.foe.part_id = "RAT_GNAW"; d.foe.species_id = "dcss_rat"; d.foe.pos = Vector2i(6,3); d.foe.hp = 1; d.foe.max_hp = 10; d.foe.cast_recovery = 1; d.foe.ready_at = 200
	d.ally.pos = Vector2i(5,3); d.ally.ready_at = 20; s.part_wishes = {"dcss_rat":["cut"]}
	choice = Tactics.choose(s,d.hero)
	check(choice.kind == "WAIT" and choice.get("reason_code","") == "FINISH_YIELD","one safe yield lets the correct-form ally finish")
	check(s.finish_yielded.is_empty(),"preview never consumes yield allowance")
	Build.committed(s,choice)
	check(s.finish_yielded.size() == 1,"successful execution consumes one yield")
	choice = Tactics.choose(s,d.hero)
	check(choice.kind != "WAIT" or choice.get("reason_code","") != "FINISH_YIELD","same target cannot produce a repeated waiting loop")
	s.finish_yielded.clear(); d.ally.ready_at = 300
	check(not Build.yield_to(s,d.hero,d.foe,["cut"]),"ally scheduled after enemy cannot receive a yield")
	d.ally.ready_at = 20; d.foe.cast_recovery = 0
	check(not Build.yield_to(s,d.hero,d.foe,["cut"]),"contact threat prevents yield")
	d.foe.cast_recovery = 1; d.foe.guarded = true; d.foe.hp = 10
	check(not Build.yield_to(s,d.hero,d.foe,["cut"]),"guarded target uses conservative finishing damage")
	d.foe.guarded = false; d.ally.hp = 1; s.intents = [{"id":999,"cell":d.ally.pos,"damage":5}]
	check(not Build.yield_to(s,d.hero,d.foe,["cut"]),"danger to another ally blocks the yield")
	s.aim_parts = false
	check(Build.inputs(s,d.hero,{"kind":"ATTACK","cell":d.foe.pos,"damage":10}).finish_form == 0,"party toggle disables collection preference")
	print("Build AI: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
