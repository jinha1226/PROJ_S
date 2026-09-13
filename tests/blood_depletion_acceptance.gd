extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Simulator=preload("res://sim/simulator.gd")
const Action=preload("res://sim/party_action_command.gd")
const Terrain=preload("res://sim/terrain_registry.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
var failures:Array[String]=[]
func _init():run.call_deferred()
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.town_life_command({"action":"START"}).accepted,"start")
	check(s.depart_town().accepted,"depart")
	var w=s.sim.world;var hero:int=w.party_control_actor_id();var best:Dictionary={}
	for enemy in w.party_encounter.enemy_ids:
		if not w.is_autonomous_target(enemy):continue
		for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var p:Dictionary=s.sim.pathfinder.find_path(hero,w.entities[enemy].position+delta)
			if p.get("found",false) and p.path.size()>1 and (best.is_empty() or p.path.size()<best.path.size()):best=p
	check(not best.is_empty(),"adjacent enemy path")
	if best.is_empty():quit(1);return
	for cell in best.path.slice(1):
		var terrain:String=w.tile_at(cell).terrain
		check(s.sim.movement.commit_preflighted_move(hero,cell,terrain,int(Terrain.definition(terrain).move_time_cost))!=null,"fixture move")
	w.party_encounter.group_anchor=w.entities[hero].position
	var baseline:Dictionary=s.sim.snapshot()
	# Boundary fixture only: attacks, injury, HP and death remain real simulation results.
	w.body_states[hero].current_blood=1;w.body_states[hero].revision+=1
	for n in range(8):
		var result=s.FieldTurns.step(s.sim,Action.hold(hero))
		check(result.accepted,"enemy turn "+str(result.reason))
		if not result.accepted:quit(1);return
		if w.combatant_states[hero].life_state!="ACTIVE":break
	var deaths:Array=w.events.filter(func(e):return e.type=="body.blood_depleted" and e.target_id==hero)
	check(deaths.size()==1,"blood depletion fires exactly once")
	check(w.body_states[hero].current_blood==0,"actual injury consumes final blood")
	check(w.entities[hero].health==0 and w.combatant_states[hero].life_state=="DEAD","zero blood kills immediately")
	if deaths.size()==1:
		check(deaths[0].magnitude>0,"blood depletion removes remaining HP")
		check(w.events.any(func(e):return e.type=="entity.died" and e.target_id==hero and e.world_time==deaths[0].world_time),"death on same timestamp")
	check(not s.FieldTurns.assess(s.sim,Action.hold(hero)).accepted,"dead actor cannot act")
	var error:String=w.world_state_error();check(error.is_empty(),"world audit "+error)
	var restored=Simulator.from_snapshot(s.sim.snapshot())
	check(restored!=null,"death snapshot restores")
	if restored!=null:check(restored.snapshot()==s.sim.snapshot(),"snapshot equality")
	# A previous build could save an ACTIVE actor with wounds and no blood.
	s.sim=Simulator.from_snapshot(baseline);w=s.sim.world
	for n in range(8):
		if not w.body_states[hero].wounds.is_empty():break
		check(s.FieldTurns.step(s.sim,Action.hold(hero)).accepted,"legacy injury fixture")
	check(not w.body_states[hero].wounds.is_empty() and w.entities[hero].health>0,"legacy survivor has real wound")
	w.body_states[hero].current_blood=0;w.body_states[hero].revision+=1
	s.sim=Simulator.from_snapshot(s.sim.snapshot())
	check(s.sim!=null,"legacy zero blood save loads")
	if s.sim!=null:
		w=s.sim.world;var before:int=w.events.size()
		check(s.FieldTurns.step(s.sim,Action.hold(hero)).accepted,"legacy depletion resolves")
		check(w.combatant_states[hero].life_state=="DEAD","legacy survivor cannot continue")
		check(not w.events.slice(before).any(func(e):return e.type=="action.hold" and e.actor_id==hero),"legacy actor dies before requested action")
		check(w.world_state_error().is_empty(),"legacy death validates")
	check(not preload("res://playtest/product_features.gd").SETTLEMENT_ENABLED,"settlement suspended")
	check("사망" in Sandbox._body_help("혈액"),"blood help describes mortality")
	print("BLOOD DEPLETION ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
