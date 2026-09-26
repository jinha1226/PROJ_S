extends SceneTree
const EffectEngine = preload("res://expedition/progression/effect_engine.gd")
const Conditions = preload("res://expedition/progression/effect_conditions.gd")
const Actions = preload("res://expedition/progression/effect_actions.gd")
const Stacks = preload("res://expedition/progression/stacks.gd")
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Stones = preload("res://expedition/progression/stone_effects.gd")
const Forms = preload("res://expedition/combat/forms.gd")
var checks := 0
var failures := 0
var original: Dictionary
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(why)
func _initialize() -> void: call_deferred("run")
func field() -> Dictionary:
	EffectEngine.content = original.duplicate(true)
	Forms.force = 99; Stones.force = 99
	var s = Session.new(731,false,true,true,2); s.depart(); s.manual_mode = true
	var c: Vector2i = Fixture.arena(s,8)
	var hero: Dictionary = s.party[0]; var ally: Dictionary = s.party[1]; var foe: Dictionary = s.enemies[0]
	hero.equipped_abilities = ["RAT_GNAW"]; ally.equipped_abilities = []
	hero.hp = 40; hero.max_hp = 100; hero.mp = 0; hero.max_mp = 50
	ally.pos = c+Vector2i(0,1)
	foe.pos = c+Vector2i(1,0); foe.hp = 100; foe.max_hp = 100; foe.part_id = ""; foe.species_id = ""; foe.ac = 0; foe.sh = 0; foe.ev = 0; foe.res = {}; foe.statuses = {}
	s.effects.clear(); s.Reactions.begin_action(s)
	return {"s":s,"hero":hero,"ally":ally,"foe":foe}
func rules(id: String, rows: Array, extra: Dictionary = {}) -> void:
	var row := {"name":"probe","text":"probe","keywords":["검사"],"rules":rows}
	row.merge(extra,true); EffectEngine.content.effects[id] = row
func run() -> void:
	original = EffectEngine.content.duplicate(true)
	conditions(); gate(); aura(); chaining(); secondary(); snapshots(); lethal(); expiry(); actions(); source_ticks(); summons(); remaining_actions(); attack_stacks(); deterministic(); hit_timing()
	EffectEngine.content = original; Forms.force = -1; Stones.force = -1
	print("Effect engine: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func conditions() -> void:
	var d := field(); var s = d.s
	d.foe.statuses = {"bleed":200,"weak":200}; d.hero.statuses = {"wet":200,"haste":200}
	Stacks.add(d.hero,"rage",2,5,"battle",s.time)
	d.ally.effect_target = d.foe.id; d.ally.effect_hit_round = int(s.time)/100
	d.hero.effect_moved_round = int(s.time)/100
	var ctx := {"target":d.foe,"attacker":d.hero,"form":"SLASH","element":"fire","spell":false,"ranged":false,"status":"bleed","status_already":true,"killer_is_crit":true,"victim_statuses":{"bleed":200},"primary":true,"phase":"probe","damage_element":"physical"}
	for pair in [["form","SLASH","PIERCE"],["element","fire","ice"],["spell",false,true],["ranged",false,true],["target_has","bleed","freeze"],["target_harmful_at_least",2,3],["target_full",true,false],["target_distance_at_least",1,5],["self_hp_below",50,30],["self_has","haste","freeze"],["self_wet",true,false],["status_is",["bleed","poison"],["stun"]],["adjacent_allies_at_least",1,4],["adjacent_enemies_at_least",1,4],["no_adjacent_enemy",false,true],["stack_at_least",["rage",2],["rage",3]],["first_attack",true,false],["same_target_as_ally",true,false],["moved_this_round",true,false],["killer_is_crit",true,false],["victim_had","bleed","poison"],["status_already",true,false],["alive_target",true,false],["alive_other",true,false],["melee",true,false],["phase","probe","other"],["primary",true,false],["victim_enemy",true,false],["damage_element","physical","fire"]]:
		check(Conditions.test(s,str(pair[0]),pair[1],d.hero,ctx),"condition true: "+str(pair[0]))
		check(not Conditions.test(s,str(pair[0]),pair[2],d.hero,ctx),"condition false: "+str(pair[0]))
	check(Conditions.test(s,"victim_had","harmful",d.hero,ctx),"harmful kill snapshot")
	check(Conditions.test(s,"owner_adjacent_to_target",true,d.hero,ctx),"aura adjacency")
	check(not Conditions.test(s,"owner_adjacent_to_target",true,d.foe,ctx),"aura excludes owner")
	check(Conditions.test(s,"chance",100,d.hero,ctx) and not Conditions.test(s,"chance",0,d.hero,ctx),"pinned chance boundary")
	d.hero.gear.weapon = {}
	check(Conditions.test(s,"unarmed",true,d.hero,ctx) and not Conditions.test(s,"unarmed",false,d.hero,ctx),"unarmed condition")
	check(not Conditions.test(s,"unknown",true,d.hero,ctx),"unknown conditions fail closed")

func gate() -> void:
	var d := field(); var s = d.s
	rules("RAT_GNAW",[{"when":"HIT","if":[{"target_has":"bleed"}],"do":[{"gain_mp":1}]},{"when":"HIT","if":[{"target_has":"bleed"}],"do":[{"gain_mp":2}]}])
	var ctx := {"attacker":d.hero,"target":d.foe}
	Stones.fire(s,"HIT",ctx); check(d.hero.mp == 0,"failed condition does not fire")
	d.foe.statuses.bleed = 300
	Stones.fire(s,"HIT",ctx); check(d.hero.mp == 3,"both eligible sibling rules run; false first candidate spent no gate")
	Stones.fire(s,"HIT",ctx); check(d.hero.mp == 3,"same effect/event only once per action")
	s.Reactions.begin_action(s); Stones.fire(s,"HIT",ctx)
	check(d.hero.mp == 6 and s.effect_depth == 0,"next action opens gate and depth restores")

func aura() -> void:
	var d := field(); var s = d.s
	d.hero.equipped_abilities = []; d.ally.equipped_abilities = ["SKELETON_WALL"]
	check(Stones.incoming(s,d.hero,100) == 90,"ally owner's aura found")
	check(Stones.incoming(s,d.ally,100) == 100,"aura does not protect itself")
	var guard: Dictionary = s.make_actor(980,"guard",false); guard.pos = d.hero.pos+Vector2i(-1,0); guard.equipped_abilities = ["SKELETON_WALL"]; s.npcs.append(guard)
	check(Stones.incoming(s,d.hero,100) == 90,"same aura group does not stack")
	guard.pos += Vector2i(-5,0); d.ally.pos += Vector2i(0,5)
	check(Stones.incoming(s,d.hero,100) == 100,"distant aura excluded")

func chaining() -> void:
	var d := field(); var s = d.s
	rules("RAT_GNAW",[{"when":"HIT","do":[{"apply_status":"weak","ticks":100},{"notice":"1"}]},{"when":"STATUS_GIVEN","do":[{"apply_status":"poison","ticks":100},{"gain_mp":1},{"notice":"2"}]}],{"limit":"event"})
	Stones.fire(s,"HIT",{"attacker":d.hero,"target":d.foe})
	check(d.foe.statuses.has("weak") and d.foe.statuses.has("poison"),"second depth may apply a status")
	check(d.hero.mp == 1 and s.effect_depth == 0,"third depth suppressed and depth unwinds")

func secondary() -> void:
	var d := field(); var s = d.s
	rules("RAT_GNAW",[{"when":"HIT","do":[{"gain_mp":1}]},{"when":"KILL","do":[{"gain_mp":2}]}])
	s.CombatRules.damage(s,d.hero,d.foe,10,"physical",0,s.Reactions.EXTRA_FORM)
	check(d.hero.mp == 0,"secondary damage has no HIT")
	d.foe.hp = 1; s.CombatRules.damage(s,d.hero,d.foe,1,"physical",0,s.Reactions.EXTRA_FORM)
	check(d.hero.mp == 2,"secondary kill still has KILL")
	d = field(); s = d.s
	rules("RAT_GNAW",[{"when":"HIT","do":[{"extra_damage":5}]},{"when":"KILL","do":[{"gain_mp":2}]}])
	d.foe.hp = 2; s.CombatRules.damage(s,d.hero,d.foe,1,"physical")
	check(d.foe.hp == 0 and s.battle_stats.kills == 1,"on-hit extra kill pays reward exactly once")
	check(d.hero.mp == 2 and s.effect_depth == 0,"nested kill fires once within depth bound")

func snapshots() -> void:
	var d := field(); var s = d.s
	rules("RAT_GNAW",[{"when":"KILL","if":[{"victim_had":"exposed"},{"killer_is_crit":true}],"do":[{"gain_mp":4}]}])
	d.hero.equipped_abilities.append("SKELETON_VOLLEY"); d.foe.statuses.exposed = 200; d.foe.hp = 2; Stones.force = 0
	var was := Forms.begin(s,"PIERCE")
	s.CombatRules.damage(s,d.hero,d.foe,5,"physical"); Forms.end(s,was)
	check(d.hero.mp == 4 and not d.foe.statuses.has("exposed"),"kill sees pre-consumption exposed and actual critical")
	check(d.foe.last_form == "PIERCE" and s.blow_form == "","form snapshot is the blow's, not physical element")

func lethal() -> void:
	var d := field(); var s = d.s
	d.hero.equipped_abilities = []; d.ally.equipped_abilities = ["RAT_GNAW"]
	rules("RAT_GNAW",[{"when":"ALLY_LETHAL","do":[{"redirect":true}]},{"when":"ALLY_CRISIS","do":[{"gain_mp":1}]}])
	d.hero.hp = 3; var hp: int = d.ally.hp
	var received: Dictionary = {}; s.after_damage(d.hero,5,int(d.foe.id),"physical",received)
	check(d.hero.hp == 3 and d.ally.hp == hp-5,"pre-lethal redirect prevents original death")
	check(received.target.id == d.ally.id,"redirect returns actual recipient")
	d = field(); s = d.s; d.hero.equipped_abilities = []; d.ally.equipped_abilities = ["RAT_GNAW"]; d.ally.mp = 0
	rules("RAT_GNAW",[{"when":"ALLY_CRISIS","do":[{"gain_mp":1}]}])
	d.hero.hp = 26; s.after_damage(d.hero,2,int(d.foe.id),"physical")
	s.after_damage(d.hero,1,int(d.foe.id),"physical")
	check(d.ally.mp == 1,"crisis only when crossing quarter-HP boundary")

func expiry() -> void:
	var actor := {"stacks":{}}
	for boundary in ["action","attack","battle"]:
		Stacks.add(actor,boundary,3,2,boundary,0); check(Stacks.count(actor,boundary) == 2,"stack cap: "+boundary)
		Stacks.expire(actor,boundary,0); check(Stacks.count(actor,boundary) == 0,"stack boundary: "+boundary)
	Stacks.add(actor,"timed",2,5,100,0)
	check(Stacks.count(actor,"timed",99) == 2 and Stacks.count(actor,"timed",100) == 0,"tick expiry includes boundary")

func actions() -> void:
	var d := field(); var s = d.s
	Actions.run(s,d.hero,[{"stack":"rage","add":3,"max":5,"until":"attack"},{"gain_mp":3}],{"target":d.foe})
	check(Stacks.count(d.hero,"rage",s.time) == 3 and d.hero.mp == 3,"data stack and MP actions")
	rules("RAT_GNAW",[{"when":"ALWAYS","mod":{"attack_percent":{"value":5,"per_stack":["rage",1]}}}])
	check(Stones.modifier(s,"attack_percent",d.hero,{"target":d.foe}) == 15,"per-stack modifier")
	var ctx := {"target":d.foe,"amount":10}
	Actions.run(s,d.hero,[{"damage_percent":50},{"apply_status":"bleed","ticks":100},{"notice":"검사"},{"extend_status":"bleed","percent":50}],ctx)
	check(ctx.amount == 15 and d.foe.statuses.bleed == s.time+150,"damage and duration actions")
	d.hero.cooldowns = {"one":3}; Actions.run(s,d.hero,[{"cooldowns":2},{"heal":5,"target":"self"}],ctx)
	check(d.hero.cooldowns.one == 1 and d.hero.hp == 45,"cooldown and healing actions")
	d.foe.statuses.immune = 200; s.effects.clear()
	Actions.run(s,d.hero,[{"apply_status":"freeze"},{"notice":"blocked"}],ctx)
	check(not s.effects.any(func(e): return e.get("text","") == "blocked"),"blocked status has no false notice")

func source_ticks() -> void:
	var d := field(); var s = d.s
	rules("RAT_GNAW",[{"when":"ALWAYS","mod":{"bleed_tick":3}}])
	s.Statuses.apply(s,d.foe,"bleed",100,d.hero); var before: int = d.foe.hp
	s.Statuses.tick(s)
	check(d.foe.hp == before-5,"DOT bonus belongs to status source")
	d = field(); s = d.s; d.hero.equipped_abilities = []; d.foe.part_id = "RAT_GNAW"
	rules("RAT_GNAW",[{"when":"ALWAYS","mod":{"bleed_tick":3}}])
	s.Statuses.apply(s,d.foe,"bleed",100,d.hero); before = d.foe.hp; s.Statuses.tick(s)
	check(d.foe.hp == before-2,"victim's own effect does not boost incoming DOT")

func summons() -> void:
	var d := field(); var s = d.s
	rules("RAT_GNAW",[{"when":"SUMMON","do":[{"gain_mp":1}]},{"when":"SUMMON_END","do":[{"gain_mp":2}]}])
	var cell: Vector2i = s.Spells.Summons.summon_cells(s,d.hero)[0]
	var pet: Dictionary = s.Spells.Summons.summon(s,d.hero,cell)
	check(d.hero.mp == 1 and pet.summoner == d.hero.id,"summon event belongs to its caster")
	pet.expires_at = s.time; s.Spells.Summons.expire(s); s.Spells.Summons.expire(s)
	check(d.hero.mp == 3 and pet not in s.npcs,"expiration emits one summon-end event")

func remaining_actions() -> void:
	var d := field(); var s = d.s
	var ctx := {"target":d.foe,"victim_statuses":{"bleed":100}}
	var ally_hp: int = d.ally.hp
	var neighbour: Dictionary = s.make_actor(981,"near",true); neighbour.pos = d.foe.pos+Vector2i(1,1); neighbour.hp = 100; neighbour.max_hp = 100; s.enemies.append(neighbour)
	Actions.run(s,d.hero,[{"spread_status":"bleed","radius":1,"ticks":300},{"burst":1,"damage":3}],ctx)
	check(neighbour.statuses.has("bleed") and neighbour.hp == 97,"spread and burst reach nearby enemies")
	check(d.ally.hp == ally_hp,"burst never damages allies")
	var before: Vector2i = d.foe.pos
	Actions.run(s,d.hero,[{"push":1}],ctx)
	check(d.foe.pos == before+Vector2i.RIGHT,"data push moves away from source")
	s.tile(d.foe.pos+Vector2i.RIGHT).terrain = "wall"; var hp: int = d.foe.hp
	Actions.run(s,d.hero,[{"push":1,"blocked_damage":4}],ctx)
	check(d.foe.hp == hp-4,"blocked push deals secondary collision damage")
	Actions.run(s,d.hero,[{"buff":"haste","target":"self","ticks":100},{"stack":"one","until":"battle"},{"clear_stack":"one"}],ctx)
	check(d.hero.statuses.has("haste") and Stacks.count(d.hero,"one") == 0,"buff and stack removal")
	d.hero.hp = 1; var lethal_ctx := {"when":"LETHAL","amount":50,"target":d.hero}
	Actions.run(s,d.hero,[{"revive":30}],lethal_ctx)
	check(d.hero.hp == 30 and lethal_ctx.amount == 0,"data revive cancels the lethal hit")
	d.foe.hp = 0
	Actions.run(s,d.hero,[{"raise_dead":"hound","ticks":200}],ctx)
	check(s.npcs.any(func(p): return bool(p.get("summoned",false)) and p.pos == d.foe.pos and int(p.expires_at) == int(s.time)+200),"raise-dead uses corpse cell and lifetime")
	d = field(); s = d.s
	Actions.run(s,d.hero,[{"summon":"hound","ticks":100}],{})
	check(s.npcs.any(func(p): return bool(p.get("summoned",false)) and p.summoner == d.hero.id),"data summon belongs to owner")

func attack_stacks() -> void:
	var d := field(); var s = d.s
	rules("RAT_GNAW",[{"when":"CRIT","do":[{"stack":"next","add":1,"max":1,"until":"attack"},{"notice":"next"}]}])
	d.hero.equipped_abilities.append("SKELETON_VOLLEY"); Stones.force = 0
	s.CombatRules.damage(s,d.hero,d.foe,1,"physical")
	check(Stacks.count(d.hero,"next",s.time) == 1,"stack granted during critical survives for next attack")
	Stones.force = 99; s.Reactions.begin_action(s); s.CombatRules.damage(s,d.hero,d.foe,1,"physical")
	check(Stacks.count(d.hero,"next",s.time) == 0,"next attack consumes old charge")

func deterministic() -> void:
	var samples: Array = []
	for attempt in range(2):
		var d := field(); var s = d.s; Stones.force = -1
		rules("RAT_GNAW",[{"when":"HIT","if":[{"chance":40}],"do":[{"gain_mp":1},{"notice":"roll"}]}])
		var outcome: Array = []
		for step in range(12):
			s.Reactions.begin_action(s); Stones.fire(s,"HIT",{"attacker":d.hero,"target":d.foe}); outcome.append(int(d.hero.mp))
		samples.append(outcome)
	check(samples[0] == samples[1],"same seed and actions reproduce effect rolls")

func hit_timing() -> void:
	var d := field(); var s = d.s
	rules("RAT_GNAW",[{"when":"HIT","do":[{"apply_status":"freeze","ticks":100},{"notice":"freeze"}]}])
	s.CombatRules.damage(s,d.hero,d.foe,5,"physical")
	check(d.foe.statuses.has("freeze"),"on-hit freeze is applied after this hit's shatter reaction")
	d = field(); s = d.s
	rules("RAT_GNAW",[{"when":"HIT","do":[{"gain_mp":1}]}]); d.foe.hp = 1
	s.CombatRules.damage(s,d.hero,d.foe,1,"physical")
	check(d.hero.mp == 1,"a fatal primary blow still emits HIT")
	d = field(); s = d.s
	rules("RAT_GNAW",[{"when":"HIT","if":[{"spell":true},{"element":"fire"}],"do":[{"gain_mp":1}]}])
	s.Spells.hurt(s,d.hero,d.foe,5,"fire")
	check(d.hero.mp == 1 and s.casting == 0,"spell hit carries actual spell flag and element")
