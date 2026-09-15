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
	check(s.enable_party_rescue().accepted,"activation")
	var w=s.sim.world;var p=w.party_encounter
	var hero:int=p.protagonist_id;var ally:int=p.active_party_member_ids[1]
	# Isolated transition fixture; session replay is tested in its own script.
	var origin:Vector2i=w.entities[hero].position
	var placed:=false
	for d in [Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN]:
		var cell:Vector2i=origin+d
		if w.in_bounds(cell) and w._terrain_is_passable(cell) and w.blocking_entity_at(cell)==null:
			w.entities[ally].position=cell;placed=true;break
	check(placed,"adjacent rescue fixture")
	w._occupancy_index_ready=false
	w.begin_step(1)
	var cause=w.emit_event("fixture.damage",-1,ally,w.entities[ally].position,1)
	var damage=s.sim.damage.apply_canonical_active_damage(w.entities[ally],w.entities[ally].health,"physical",cause.id,w.entities[ally].position,1,w.entities[ally].health)
	check(damage.accepted,"lethal hit accepted")
	var c=w.combatant_states[ally]
	check(c.life_state=="DOWNED" and c.downed_resolve_at==1000,"full ten-turn grace")
	var downed_source:int=c.downed_source_event_id
	check(not w.is_explicit_melee_target(ally),"no finisher during grace")
	var assist=Action.new("ASSIST",hero,Vector2i(-1,-1),ally)
	check(Rules.action_error(w,assist).is_empty(),"legal assistance")
	check(Rules.commit_action(s.sim,assist,100),"start assistance")
	check(Rules.action_error(w,assist)=="already_assisting","duplicate assistance rejected")
	check(Rules.action_error(w,Action.melee(hero,p.enemy_ids[0]))=="release_before_attack","carrying blocks attack")
	var before_deadline:int=c.downed_resolve_at
	w.world_time=100;p.member(hero).busy_until=100
	var moved:=false
	for d in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
		var dest:Vector2i=origin+d
		if not s.sim.movement.assess_move(hero,dest).accepted:continue
		var action=Action.move_to(hero,dest)
		var normal:int=preload("res://sim/field_action_timing.gd").duration(w,hero,"MOVE",int(preload("res://sim/terrain_registry.gd").definition(w.tile_at(dest).terrain).move_time_cost))
		check(s.sim.party_coordinator._action_row(action,"DIRECT",0).time_cost==(normal*3+1)/2,"movement costs 150 percent")
		moved=Field._commit_ally(s.sim,action,1);break
	check(moved and w.entities[ally].position==origin and w.entities[hero].position!=origin,"atomic trailing movement")
	check(c.downed_resolve_at==before_deadline,"moving never resets deadline")
	# Neutralize threats in this isolated fixture, exercising safe recovery and credit.
	for id in p.enemy_ids:w.combatant_states[id].life_state="DEAD";w.entities[id].health=0
	check(Rules.settle(s.sim),"safe recovery")
	check(c.life_state=="ACTIVE" and w.entities[ally].health==1,"one HP recovery")
	var rescues:Array=[]
	for e in w.events:
		if e.type=="party.rescue_completed":rescues.append(e)
	check(rescues.size()==1 and rescues[0].actor_id==hero,"one factual rescuer")
	check(preload("res://sim/systems/party_memory_system.gd").commit_batch(w,rescues),"rescue memory commits")
	check(p.member(ally).memory_state.salience_for_subject(hero,["RESCUED_BY"])>0,"rescuer remembered")
	check(Rules.settle(s.sim) and Rules.links(w).is_empty(),"repeated settlement cleans links without credit farming")
	w.world_time=300
	var promise=Action.new("PROMISE",hero,Vector2i(-1,-1),ally)
	var priority:int=Rules.rescue_priority(w,ally,hero)
	check(Rules.commit_dialogue(s.sim,promise),"rest promise")
	check(Rules.rescue_priority(w,ally,hero)==priority+200,"promise changes rescue preference")
	check(not Rules.commit_dialogue(s.sim,promise),"same rescue cannot be discussed twice")
	check(Rules.history_error(w).is_empty(),"rescue event graph validates")
	# Every environmental damage entry point shares the same grace contract.
	for kind in ["fire","electric","starvation"]:
		w.world_time=310;w.entities[hero].health=1
		var hc=w.combatant_states[hero]
		hc.life_state="ACTIVE";hc.downed_at=-1;hc.downed_resolve_at=-1;hc.downed_source_event_id=-1
		var environmental=w.emit_event("fixture.environment",-1,hero,w.entities[hero].position,20)
		check(s.sim.damage.apply_damage(w.entities[hero],20,kind,environmental.id,w.entities[hero].position,1)>0,"environment damage "+kind)
		check(hc.life_state=="DOWNED" and hc.downed_resolve_at==1310,"environment grace "+kind)
	w.entities[hero].health=1
	var hc=w.combatant_states[hero];hc.life_state="ACTIVE";hc.downed_at=-1;hc.downed_resolve_at=-1;hc.downed_source_event_id=-1
	# Timeout at an off-cadence instant wins over safety.
	w.world_time=350;c.life_state="DOWNED";w.entities[ally].health=0
	var downed=w.emit_event("entity.downed",-1,ally,w.entities[ally].position,0,downed_source,{})
	c.downed_at=350;c.downed_resolve_at=1350;c.downed_source_event_id=downed.id
	check(Rules.next_deadline(w,1349).is_empty() and Rules.next_deadline(w,1350).at==1350,"exact off-cadence deadline")
	w.world_time=1350
	check(Rules.settle(s.sim) and c.life_state=="DEAD","timeout precedes safe recovery")
	print("PARTY RESCUE TRANSITIONS: ","PASS" if failures.is_empty() else "FAIL",failures)
	quit(0 if failures.is_empty() else 1)
