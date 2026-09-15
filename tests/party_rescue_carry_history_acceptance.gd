extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Rules=preload("res://sim/party_rescue_rules.gd")
const Action=preload("res://sim/party_action_command.gd")
const Field=preload("res://sim/systems/field_turn_system.gd")
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL ",message)
func run()->void:
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	s.enable_party_rescue()
	var w=s.sim.world;var p=w.party_encounter
	var hero:int=p.protagonist_id;var ally:int=p.active_party_member_ids[1];var enemy:int=p.enemy_ids[0]
	var origin:Vector2i=w.entities[hero].position
	var placed:=false
	for d in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
		var a:Vector2i=origin+d;var e:Vector2i=origin+d*2
		if w.in_bounds(e) and w._terrain_is_passable(a) and w._terrain_is_passable(e) and w.blocking_entity_at(a)==null and w.blocking_entity_at(e)==null:
			w.entities[ally].position=a;w.entities[enemy].position=e;placed=true;break
	check(placed,"line fixture")
	w.entities[ally].health=1;w._occupancy_index_ready=false
	p.member(ally).busy_until=10000
	for id in p.enemy_ids:
		if id!=enemy:p.enemy_busy_rows[id]=10000
	p.enemy_awareness(enemy).awareness_state="HUNTING";p.enemy_awareness(enemy).suspicion=1000
	var assisted:=false;var carried:=false;var saved_carry:=false;var recovered:=false
	for turn in range(20):
		if not s.field_turns_active():break
		var actor:int=w.party_control_actor_id()
		var action=Action.hold(actor)
		if not w.can_act(actor,w.world_time) or p.member(actor).busy_until>w.world_time:action=Action.new("CRISIS",actor)
		elif not assisted and w.combatant_states[ally].life_state=="DOWNED":
			action=Action.new("ASSIST",actor,Vector2i(-1,-1),ally)
			if not Field.assess(s.sim,action).accepted:action=Action.hold(actor)
		elif Rules.links(w).has(actor):
			action=Rules.suggest(w,actor,s.sim.movement)
		var result=Field.step(s.sim,action)
		check(result.accepted,"field action: "+str(result.reason))
		if not result.accepted:break
		for e in result.events:
			if e.type=="party.assist_started":assisted=true;p.enemy_busy_rows[enemy]=10000
			if e.type=="party.rescue_completed":recovered=true
			if e.type=="party.assist_moved":carried=true
		var error:String=w.world_state_error()
		check(error.is_empty(),"full history: "+error)
		if not error.is_empty():break
		if carried and not saved_carry:
			var snapshot:Dictionary=s.sim.snapshot()
			check(not snapshot.is_empty(),"carry snapshot")
			check(preload("res://sim/simulator.gd").from_snapshot(snapshot)!=null,"carry snapshot restore")
			var invalid=Field.step(s.sim,Action.move_to(hero,w.entities[ally].position))
			check(not invalid.accepted and s.sim.snapshot()==snapshot,"blocked swap preserves both actors and history")
			var corrupt:Dictionary=snapshot.duplicate(true)
			for row in corrupt.events:
				if row.type=="party.assist_moved":row.data.to_position=[999,999];break
			check(preload("res://sim/simulator.gd").from_snapshot(corrupt)==null,"forged carry position rejected")
			saved_carry=true
		if recovered:break
	check(recovered,"actual rescue completion")
	if recovered:
		check(p.member(ally).memory_state.salience_for_subject(hero,["RESCUED_BY"])>0,"actual rescue memory")
		var dialogue=Field.step(s.sim,Action.new("PROMISE",hero,Vector2i(-1,-1),ally))
		check(dialogue.accepted,"actual rest dialogue")
		check(w.world_state_error().is_empty(),"dialogue and relationship history audit")
		var final_snapshot:Dictionary=s.sim.snapshot()
		check(not final_snapshot.is_empty() and preload("res://sim/simulator.gd").from_snapshot(final_snapshot)!=null,"rescue and promise snapshot restoration")
	check(assisted and carried,"actual melee -> assist -> carry exercised")
	print("PARTY RESCUE CARRY HISTORY: ","PASS" if failures.is_empty() else "FAIL",failures)
	quit(0 if failures.is_empty() else 1)
