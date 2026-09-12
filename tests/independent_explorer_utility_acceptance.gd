extends SceneTree
const Policy=preload("res://sim/independent_explorer_decision.gd")
const Profile=preload("res://sim/dungeon_population/hexaco_profile.gd")
const LegacyProfile=preload("res://sim/personality_profile.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
const Population=preload("res://sim/town_population_rules.gd")
const Explorer=preload("res://sim/systems/independent_explorer_system.gd")
const Living=preload("res://sim/living_expedition_rules.gd")
const Shell=preload("res://playtest/party_encounter_sandbox.gd")
const Command=preload("res://sim/sim_command.gd")
var failures:Array=[]
var live_completed:=false
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func score(result:Dictionary,action:String)->int:
	for row in result.candidates:
		if row.action==action:return int(row.score)
	return -1000000
func run()->void:
	var neutral=Profile.new();var bold=Profile.new({"C":100,"E":100})
	var cautious=Profile.new({"C":900,"E":900})
	var context:={"health_ratio":65,"enemy_distance":3,"supplies":1,"fatigue":0}
	check(Policy.decide(bold,context).mode=="FIGHT","bold explorer fights")
	check(Policy.decide(cautious,context).mode=="RETURN","cautious explorer retreats in same situation")
	context.health_ratio=80
	var calm:=Policy.decide(neutral,context)
	context.fear=1000
	check(calm.mode=="FIGHT" and Policy.decide(neutral,context).mode=="RETURN","fear changes decision")
	context.fear=0;context.grievance=1000
	check(score(Policy.decide(neutral,context),"FIGHT")>score(calm,"FIGHT"),"existing target memory affects combat drive")
	context.grievance=0
	var committed:={"decision_mode":"EXPLORE","decision_until":500,"state":"EXPLORE"}
	check(Policy.decide(neutral,context,committed,100).mode=="FIGHT","enemy interrupts exploration commitment")
	context.enemy_distance=999;context.health_ratio=100
	check(Policy.decide(neutral,context,{"decision_mode":"FIGHT","decision_until":500},100).mode=="EXPLORE",
		"lost enemy cannot remain an actionable target")
	var curious:=Policy.decide(Profile.new({"O":950}),context)
	check(score(curious,"EXPLORE")>score(Policy.decide(Profile.new({"O":50}),context),"EXPLORE"),"openness affects exploration score")
	context.fatigue=2
	var rest:={"decision_mode":"REST","decision_until":0,"state":"REST"}
	check(Policy.decide(neutral,context).mode=="EXPLORE" and Policy.decide(neutral,context,rest,400).mode=="REST",
		"switch margin prevents small-score oscillation")
	context.fatigue=1
	check(Policy.decide(neutral,context,rest,400).mode=="EXPLORE","substantial improvement permits switching")
	rest.decision_until=500
	check(Policy.decide(neutral,context,rest,400).mode=="REST","minimum commitment uses world time")
	context.supplies=0
	check(Policy.decide(neutral,context,rest,400).reason=="supplies_missing","no supplies interrupts rest immediately")
	context.supplies=1;context.health_ratio=10
	check(Policy.decide(neutral,context,committed,100).reason=="low_health","critical injury overrides personality")
	context.health_ratio=100;context.enemy_distance=1;context.can_attack=false
	check(Policy.decide(bold,context).reason=="weapon_unavailable","unusable weapon cannot win combat scoring")
	context.enemy_distance=999;context.can_attack=true;context.fatigue=0
	check(Policy.decide(neutral,context,{"state":"RETURN"},10).mode=="RETURN","service return survives resupply")
	check(not Policy.decide(LegacyProfile.new(),context).label.is_empty(),"missing legacy HEXACO facets use neutral fallback")
	var expected:=Policy.decide(neutral,context)
	var begun:=Time.get_ticks_usec()
	for i in range(1000):check(Policy.decide(neutral,context)==expected,"deterministic pure policy")
	print("UTILITY 1000 decisions including equality check us=",Time.get_ticks_usec()-begun)
	await live_checks()
	check(live_completed,"live integration checks reach completion")
	print("INDEPENDENT UTILITY: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)

func live_checks()->void:
	var session=Session.new(91,20260828,Session.DUO_SCENARIO_ID)
	check(session.start_new_run_with_species("elf",true).get("accepted",false),"living campaign starts")
	check(session.town_life_command({"action":"START"}).get("accepted",false),"enter town")
	check(session.depart_town().get("accepted",false),"depart town")
	for i in range(3):
		check(session.commit_exploration(Command.wait(session.sim.world.party_control_actor_id())).get("accepted",false),"canonical NPC cadence")
	var world=session.sim.world
	var rows:Array=Population.locations(world)
	check(rows.any(func(row):return row.get("decision_ruleset","")==Policy.RULESET_ID),"live patrol persists policy state")
	var loaded=Session.new()
	var restored:Dictionary=loaded.load_session_json(session.save_session_json())
	check(restored.get("accepted",false) and loaded.sim.snapshot()==session.sim.snapshot(),"policy commitment and reasons replay exactly")
	var id:=-1
	for row in rows:
		if Living.present(world,int(row.entity_id)) and row.has("decision_reason"):id=int(row.entity_id);break
	check(id>0,"active independent visitor available")
	if id<=0:return
	# Isolated capability seam: a recovering actor cannot heal/move/attack before
	# its recovery lock. Other NPCs/enemies are held to isolate this one tick.
	for row in rows:world.party_encounter.member(int(row.entity_id)).busy_until=world.world_time+1000
	for enemy in world.party_encounter.enemy_ids:world.party_encounter.enemy_busy_rows[enemy]=world.world_time+1000
	world.party_encounter.member(id).busy_until=world.world_time
	world.combatant_states[id].recovery_lock_until=world.world_time+100
	var before:Array=[world.events.size(),world.entities[id].health,world.entities[id].position,
		world.party_encounter.member(id).busy_until]
	check(Explorer.process_tick(session.sim,world.step_index) and before==[world.events.size(),
		world.entities[id].health,world.entities[id].position,world.party_encounter.member(id).busy_until],
		"recovery lock causes no NPC action or healing")
	world.combatant_states[id].recovery_lock_until=0
	# UI-only fixture; no saving fabricated positions. The actual text renderer
	# consumes only an observed NPC's activity, not the private candidate scores.
	var hero=world.entities[world.party_control_actor_id()]
	var visitor=world.entities[id]
	hero.position=visitor.position;world.party_encounter.group_anchor=hero.position
	session._invalidate_explored_presentation_cache()
	var detail:Dictionary=session.inspect_party_member(id)
	check(not str(detail.get("npc_activity","")).is_empty(),"visible NPC detail exposes one-line reason")
	var ui=Shell.new();ui.initialize_for_headless_test(session,false);root.add_child(ui);ui.set_process(false)
	await process_frame;await process_frame
	check(ui._member_detail_text(detail).contains("현재 행동 · "),"existing status body renders reason")
	check(not detail.has("candidates"),"private utility scores stay out of inspector")
	hero.position=Vector2i.ZERO;world.party_encounter.group_anchor=hero.position
	# Ensure a genuinely distant point even if the chosen visitor is near (0,0).
	if hero.position.distance_to(visitor.position)<20:
		hero.position=Vector2i(world.width-1,world.height-1);world.party_encounter.group_anchor=hero.position
	session._invalidate_explored_presentation_cache()
	check(str(session.inspect_party_member(id).get("npc_activity","")).is_empty(),"unseen NPC reveals no live decision reason")
	ui.queue_free();await process_frame
	live_completed=true
