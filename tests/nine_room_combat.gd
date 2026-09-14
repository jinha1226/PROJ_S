extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Rules=preload("res://sim/room_transition_rules.gd")
const Exit=preload("res://sim/systems/room_transition_system.gd")
const Rounds=preload("res://sim/systems/round_combat_system.gd")
const State=preload("res://sim/round_combat_state.gd")
const Plans=preload("res://sim/round_plan_service.gd")
const Action=preload("res://sim/party_action_command.gd")
const Sim=preload("res://sim/simulator.gd")
var failures:Array=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func place(w,id:int,p:Vector2i):
	var old:Vector2i=w.entities[id].position;w.entities[id].position=p;w.reindex_entity_occupancy(id,old,p)
func fixture():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",false)
	if s.sim==null:return null
	var w=s.sim.world;var party=w.party_encounter;var portal:Dictionary=Rules.portal(w,"F1_R4_R5")
	var exit:=Rules.cell(w,portal,4);place(w,party.protagonist_id,exit+Vector2i.LEFT)
	place(w,party.active_party_member_ids[1],exit+Vector2i(-1,-1));party.group_anchor=w.entities[party.protagonist_id].position
	for index in range(3):
		var id:int=party.enemy_ids[index];place(w,id,exit+[Vector2i(-2,0),Vector2i(-2,1),Vector2i(-1,1)][index])
		var awareness=party.enemy_awareness(id);awareness.awareness_state="HUNTING";awareness.suspicion=1000;awareness.last_known_target_position=w.entities[party.protagonist_id].position
	party.member(party.protagonist_id).action_speeds={"MOVE":200,"ATTACK":200,"CAST":200}
	party.round_combat=State.fresh();Plans.begin(s.sim)
	return s
func audit(s,label:String):
	var error:String=s.sim.world.world_state_error();check(error.is_empty(),label+" audit "+error)
	if error.is_empty():
		var saved:Dictionary=s.sim.snapshot();var clone=Sim.from_snapshot(saved)
		check(clone!=null,label+" restore")
		if clone!=null:check(clone.snapshot()==saved,label+" exact")
func run():
	var s=fixture();check(s!=null,"combat fixture")
	if s==null:quit(1);return
	var w=s.sim.world;var party=w.party_encounter;var hero:int=party.protagonist_id;var companion:int=party.active_party_member_ids[1];var portal:Dictionary=Rules.portal(w,"F1_R4_R5")
	var before:Dictionary=s.sim.capture_rollback_memento(false)
	place(w,companion,Vector2i(9,9));var time:int=w.world_time;var serial:int=party.nine_room_floor.request_serial
	var rejection:=s.request_room_exit(hero,portal.portal_id,int(party.nine_room_floor.revision))
	check(not rejection.accepted and rejection.reason=="room_party_far","far companion rejected")
	check(w.world_time==time and party.nine_room_floor.request_serial==serial,"preflight costs no time")
	s.sim.restore_rollback_memento(before);w=s.sim.world;party=w.party_encounter
	var life=w.combatant_states[companion];var previous_life:String=life.life_state;var previous_hp:int=w.entities[companion].health
	life.life_state="DOWNED";w.entities[companion].health=0
	var frozen_time:int=w.world_time
	check(s.assess_room_exit(hero,portal.portal_id).reason=="room_party_cannot_move","downed companion cannot be abandoned")
	check(w.world_time==frozen_time,"downed preflight no time")
	life.life_state=previous_life;w.entities[companion].health=previous_hp
	var blocked:Array=[];var saved_wetness:Dictionary={}
	var target_exit:=Rules.cell(w,portal,5)
	for y in range(8,16):
		for x in range(16,24):
			var cell:=Vector2i(x,y)
			if Rules.distance(cell,target_exit)>2:continue
			saved_wetness[cell]=w.tile_at(cell).wetness;w.tile_at(cell).wetness=1
	check(s.assess_room_exit(hero,portal.portal_id).reason=="room_arrival_full","blocked arrival rejects")
	check(w.world_time==frozen_time,"blocked preflight no time")
	for cell in saved_wetness:w.tile_at(cell).wetness=saved_wetness[cell]
	var old_round:int=party.round_combat.round_id;var revision:int=party.nine_room_floor.revision;var hp:int=w.entities[hero].health
	var result:=s.request_room_exit(hero,portal.portal_id,revision)
	check(result.accepted and result.room_result.transitioned,"combat retreat succeeds "+str(result))
	check(w.world_time==100,"combat retreat one boundary100")
	check(result.room_result.slots.filter(func(slot):return slot.actor_id in party.enemy_ids).size()==3,"published enemy opportunities actually resolved")
	check(party.nine_room_floor.active_room_id==5,"combat room commit")
	check(party.round_combat.round_id>=old_round,"global round identity preserved")
	check(not s.request_room_exit(hero,portal.portal_id,revision).accepted,"double retreat rejected")
	check(party.nine_room_floor.pending_pursuit.size() in range(1,3),"at most two pursuers")
	var queue:Array=party.nine_room_floor.pending_pursuit.duplicate(true);var ids:Array=w.entities.keys()
	check(s.room_status().pursuit_warning,"arrival warning public")
	for row in queue:check(not Rules.actor_active(w,int(row.entity_id)),"queued actor cannot attack")
	audit(s,"retreat")
	# Passage reversal never resets pursuit eligibility or duplicates the ID.
	var back:=Rules.cell(w,portal,5);var goals:Array=[]
	for d in [Vector2i.LEFT,Vector2i.UP,Vector2i.DOWN]:
		if Rules.same_room(w,back,back+d) and Rules.safe(w,back+d):goals.append(back+d)
	# A response boundary has passed, but entry and its first attack stay separate.
	var start:int=w.events.size();check(Exit.boundary(s.sim),"first response boundary")
	check(party.nine_room_floor.pending_pursuit==queue,"no immediate pursuit arrival")
	for cell in saved_wetness:w.tile_at(cell).wetness=1
	check(Exit.boundary(s.sim),"blocked next enemy boundary")
	check(party.nine_room_floor.pending_pursuit==queue,"blocked pursuers wait with original eligibility")
	for cell in saved_wetness:w.tile_at(cell).wetness=saved_wetness[cell]
	check(Exit.boundary(s.sim),"next enemy boundary")
	var arrivals:Array=w.events.slice(start).filter(func(e):return e.type=="room.pursuit_arrived")
	check(arrivals.size()==queue.size(),"same IDs enter after response")
	check(not w.events.slice(start).any(func(e):return e.type=="combat.physical_damage"),"arrival cannot also attack")
	check(w.entities.keys()==ids,"no pursuit clone")
	for row in queue:check(Rules.current(w,w.entities[int(row.entity_id)].position),"pursuer target membership")
	audit(s,"pursuit")
	# A real completed prefix enemy action is retained on interrupted retreat.
	s=fixture();w=s.sim.world;party=w.party_encounter
	var r:Dictionary=party.round_combat;var first:int=party.enemy_ids[0]
	r.order.erase(str(first));r.order.push_front(str(first));w.begin_step(w.step_index+1);r.phase="RESOLVING"
	var slot:=Rounds.execute_slot(s.sim,r.plans[str(first)],w._active_step_index)
	check(slot.accepted,"prefix enemy really acted")
	r.completed_actor_ids=[str(first)];r.execution_cursor=1;r.phase="INTERRUPTED";r.interrupt_reason="new_threat";w.finish_step()
	var count:int=w.events.filter(func(e):return e.actor_id==first and e.type.begins_with("action.")).size()
	var retreat:=s.request_room_exit(hero,portal.portal_id,int(party.nine_room_floor.revision))
	check(retreat.accepted,"interrupted retreat")
	check(w.events.filter(func(e):return e.actor_id==first and e.type.begins_with("action.")).size()==count,"completed enemy not replayed")
	check(w.world_time==100,"interrupted retreat boundary once")
	audit(s,"prefix")
	# Damage comes from canonical attacks. If a party member falls, the accepted
	# retreat fails after combat and must preserve the HP loss and time.
	s=fixture();w=s.sim.world;party=w.party_encounter
	for attempt in range(20):
		if not w.can_act(hero,w.world_time):break
		var plan:Dictionary=party.round_combat
		for id in party.active_party_member_ids:Plans.edit(s.sim,id,{"action":Action.hold(id).to_dict(),"path":[]},int(plan.plan_revision))
		var done:=Rounds.confirm(s.sim,int(plan.round_id),int(plan.plan_revision),plan.phase=="INTERRUPTED")
		check(done.accepted,"canonical harm setup "+str(done)+" internal="+Rounds.last_execution_error+" hp="+str(w.entities[hero].health)+" t="+str(w.world_time))
		if not done.accepted:break
		if w.entities[hero].health<25:break
	if w.can_act(hero,w.world_time):
		var prior:int=w.world_time;var outcome:=s.request_room_exit(hero,portal.portal_id,int(party.nine_room_floor.revision))
		check(outcome.accepted,"accepted retreat under lethal pressure")
		if not w.can_act(hero,w.world_time):
			check(not outcome.room_result.transitioned and party.nine_room_floor.active_room_id==4,"fallen party prevents commit")
			check(w.world_time==prior+100,"failed retreat preserves time and attacks")
	check(not w.can_act(hero,w.world_time),"canonical attacks produce fallen retreat scenario")
	audit(s,"failed retreat")
	print("NINE_ROOM_COMBAT ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
