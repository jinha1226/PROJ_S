extends "res://tests/first_floor_stages_acceptance.gd"
const Stage=preload("res://sim/stage_counterplay.gd")
const Catalog=preload("res://sim/stage_catalog.gd")
const Rules=preload("res://sim/round_combat_rules.gd")
const Plans=preload("res://sim/round_plan_service.gd")
const System=preload("res://sim/systems/round_combat_system.gd")
const Fixture=preload("res://tests/round_combat_fixture.gd")
func advance(s)->Dictionary:
	var r:Dictionary=s.sim.world.party_encounter.round_combat
	return s.resume_round(r.round_id,r.plan_revision) if r.phase=="INTERRUPTED" else s.confirm_round(r.round_id,r.plan_revision)
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var w=s.sim.world;var hero:int=w.party_control_actor_id()
	check(walk(s,Vector2i(11,14)),"approach combat room")
	check(s.request_room_exit(hero,"F1_R4_R7",w.party_encounter.nine_room_floor.revision).accepted,"enter")
	var r:Dictionary=w.party_encounter.round_combat
	check(r.phase=="DEPLOYMENT","entry requires placement confirmation")
	var positions:Dictionary={};var hp:int=w.entities[hero].health;var time:int=w.world_time
	for id in Stage.enemies(w):positions[id]=w.entities[id].position
	check(not s.stage_round_action(Action.move_to(hero,Vector2i(11,21))).accepted,"deployment restricted to entrance")
	check(s.stage_round_action(Action.move_to(hero,Vector2i(10,17))).accepted,"place hero inside two-cell entrance zone")
	check(advance(s).accepted,"deployment confirmed")
	r=w.party_encounter.round_combat
	check(r.phase=="PLANNING","placement enters individual turns")
	check(w.world_time==time and w.entities[hero].health==hp,"deployment consumes no time or health")
	check(positions.keys().all(func(id):return positions[id]==w.entities[id].position),"enemies never move before their own turn")
	check(r.order==Rules.order(w,r.participants.map(func(id):return int(id))),"mixed initiative order")
	check(s.round_overlays().all(func(row):return row.role!="ENEMY"),"no fixed-cell enemy attack promises")
	var before:Dictionary=s.sim.snapshot()
	for i in range(3):s.round_preview();s.observe_party_ui(8,true,8)
	check(s.sim.snapshot()==before,"observation and preview are read only")
	var clone=Session.new();var loaded:Dictionary=clone.load_session_json(s.save_session_json())
	check(loaded.accepted,"deployment journal replay "+str(loaded.get("reason")))
	if loaded.accepted:check(clone.sim.snapshot()==s.sim.snapshot(),"deployment replay exact")
	var result:Dictionary=advance(s)
	check(result.accepted,"individual turn execution "+str(result.get("reason")))
	check(Stage.current(w).turn==1,"full cycle advances wave once")
	check(w.world_time==time+100,"full cycle commits one time boundary")
	check(w.world_state_error().is_empty(),"round audit "+w.world_state_error())
	var round_clone=Session.new();var round_loaded:Dictionary=round_clone.load_session_json(s.save_session_json())
	check(round_loaded.accepted,"individual command journal replay "+str(round_loaded.get("reason")))
	if round_loaded.accepted:check(round_clone.sim.snapshot()==s.sim.snapshot(),"individual replay exact")
	var interval:int=int(Stage.config(w).reinforcements.interval_rounds)
	var count:int=w.party_encounter.enemy_ids.size()
	for i in range(interval-2):check(Stage.finish_round(s.sim),"predeadline counter")
	check(Stage.current(w).turn==interval-1 and w.party_encounter.enemy_ids.size()==count,"no wave before deadline")
	check(Stage.finish_round(s.sim),"deadline reinforcement")
	var expected:int=Catalog.wave_enemies(Catalog.room(1,7),1).size()
	if expected==0:expected=int(Stage.CONFIG.wave_size)
	check(w.party_encounter.enemy_ids.size()==count+expected,"authored wave size at deadline")
	check(Stage.current(w).waves==1,"one wave counted")
	check(w.world_state_error().is_empty(),"reinforcement audit "+w.world_state_error())
	var wire:Dictionary=s.sim.snapshot();var restored=preload("res://sim/simulator.gd").from_snapshot(wire)
	check(restored!=null,"reinforcement snapshot restores")
	if restored!=null:check(restored.snapshot()==wire,"wave counter and actors persist")
	var old_ids:Array=w.party_encounter.enemy_ids.duplicate()
	w.party_encounter.enemy_ids.clear();Stage.current(w).turn=13
	check(Stage.finish_round(s.sim),"clear-room deadline")
	check(Stage.current(w).waves==1,"no wave after enemies are gone")
	w.party_encounter.enemy_ids.assign(old_ids)
	# Snapshot fixture tests budgets and interleaving without rewriting gameplay history.
	var shadow=preload("res://sim/simulator.gd").from_snapshot(before)
	check(shadow!=null,"individual fixture restores")
	if shadow!=null:budget_checks(shadow,hero)
	print("STAGE_COUNTERPLAY ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
func budget_checks(sim,hero:int):
	var w=sim.world;var member=w.party_encounter.member(hero);var r:Dictionary=w.party_encounter.round_combat
	for rate in [25,99,100,149,150,400]:
		member.action_speeds.MOVE=rate
		check(Rules.move_budget(w,hero)==(1 if rate<100 else 2 if rate<150 else 3),"movement rate boundary %d"%rate)
	member.action_speeds.MOVE=100
	member.action_speeds.ATTACK=25
	check(Rules.attack_budget(w,hero)==1,"slow attacks retain one basic strike")
	member.action_speeds.ATTACK=400
	check(Rules.attack_budget(w,hero)==3,"very fast attacks cap at three")
	member.action_speeds.ATTACK=200
	check(Rules.attack_budget(w,hero)>=2 and Rules.attack_budget(w,hero)<=3,"fast attacks grant multiple strikes")
	# Planning changes neither position nor health; one confirmation ends the actor.
	var cell:=Vector2i(11,18)
	var initial:Vector2i=w.entities[hero].position
	var enemy:int=Stage.enemies(w)[0]
	var to:=cell+Vector2i.RIGHT
	var route:Dictionary=sim.pathfinder.find_path(enemy,to)
	check(route.get("found",false),"enemy fixture route")
	var cause=w.emit_event("stage.enemy_movement",enemy,-1,w.entities[enemy].position,0,-1,{"round_id":r.round_id,"room":Stage.key(w)})
	for next in route.get("path",[]).slice(1):
		var old:Vector2i=w.entities[enemy].position
		var terrain:String=w.tile_at(next).terrain
		check(sim.movement.commit_preflighted_move(enemy,next,terrain,100,cause.id)!=null,"enemy fixture move")
		w.reindex_entity_occupancy(enemy,old,next)
	var strikes:int=Rules.attack_budget(w,hero)
	var start_time:int=w.world_time
	var edited:=Plans.edit(sim,hero,{"action":Action.melee(hero,enemy).to_dict(),"path":[[cell.x,cell.y]]},r.plan_revision)
	check(edited.accepted,"stage movement and attack together "+str(edited.get("reason")))
	check(w.entities[hero].position==initial,"planning never moves authority")
	var stale:int=r.plan_revision
	var result:=System.confirm(sim,r.round_id,r.plan_revision)
	check(result.accepted,"classic turn execution "+str(result.get("reason"))+System.last_execution_error)
	check(w.entities[hero].position==cell,"confirmation moves to preview position")
	check(int(r.slot_attacks.get(str(hero),0))>=1 and int(r.slot_attacks.get(str(hero),0))<=strikes,"same confirmation executes attack budget")
	check(not System.confirm(sim,r.round_id,stale).accepted,"stale turn confirmation rejected")
	check(w.world_time==start_time+100,"one confirmation completes solo cycle")
	check(w.world_state_error().is_empty(),"budget fixture world audit "+w.world_state_error())
	if w.party_encounter.party_member_ids.size()>1:mixed_checks(sim,hero)
func mixed_checks(sim,hero:int):
	var w=sim.world;var member=w.party_encounter.member(hero);var r:Dictionary=w.party_encounter.round_combat
	var result:Dictionary
	# Another deployed ally must wait for its own cursor even if selected elsewhere.
	var companion:int=w.party_encounter.party_member_ids.filter(func(id):return id!=hero)[0]
	w.party_encounter.member(companion).presence="DEPLOYED"
	if companion not in w.party_encounter.active_party_member_ids:w.party_encounter.active_party_member_ids.append(companion)
	Fixture.relocate(w,companion,Vector2i(9,17))
	w.party_encounter.member(companion).action_speeds={"MOVE":25,"ATTACK":25,"CAST":25}
	r.phase="EXPLORATION";Stage.current(w).started=false
	check(Plans.begin(sim),"begin companion deployment")
	r=w.party_encounter.round_combat
	check(r.phase=="DEPLOYMENT","companion placement phase")
	check(Plans.edit(sim,companion,{"action":Action.hold(companion).to_dict(),"path":[[10,17]]},r.plan_revision).accepted,"companion deployment editable before its initiative")
	check(w.entities[companion].position==Vector2i(9,17),"companion deployment remains a preview")
	check(System.confirm(sim,r.round_id,r.plan_revision).accepted,"confirm companion placement")
	check(w.entities[companion].position==Vector2i(10,17),"companion deployment position committed")
	r=w.party_encounter.round_combat
	r.phase="EXPLORATION";member.action_speeds.ATTACK=100;member.action_speeds.MOVE=200
	check(Plans.begin(sim),"begin mixed-party round")
	r=w.party_encounter.round_combat
	check(Rules.current_actor(w)==hero,"fast hero leads mixed cycle")
	check(r.order.find(str(Stage.enemies(w)[0]))<r.order.find(str(companion)),"enemy initiative interleaves between allies")
	check(not Plans.edit(sim,companion,{"action":Action.hold(companion).to_dict(),"path":[]},r.plan_revision).accepted,"future ally cannot act")
	check(Plans.edit(sim,hero,{"action":Action.hold(hero).to_dict(),"path":[]},r.plan_revision).accepted,"end hero turn")
	result=System.confirm(sim,r.round_id,r.plan_revision)
	check(result.accepted and not result.completed,"cycle pauses at second ally")
	check(Rules.current_actor(w)==companion,"next ally gets its own turn")
	check(result.slots.all(func(slot):return slot.actor_id!=companion),"confirmation never auto-acts next ally")
	check(Plans.edit(sim,companion,{"action":Action.hold(companion).to_dict(),"path":[]},r.plan_revision).accepted,"second ally can act on its cursor")
	result=System.confirm(sim,r.round_id,r.plan_revision)
	check(result.accepted and result.completed,"second ally completes mixed cycle")
	member.action_speeds={"MOVE":25,"ATTACK":25,"CAST":25}
	r=w.party_encounter.round_combat;r.phase="EXPLORATION"
	check(Plans.begin(sim),"begin enemy-led cycle")
	r=w.party_encounter.round_combat
	check(w.party_encounter.member(Rules.current_actor(w))==null,"faster enemy leads cycle")
	var before:int=w.world_time
	result=System.confirm(sim,r.round_id,r.plan_revision)
	check(result.accepted and not result.completed,"enemy turn pauses before ally")
	check(result.slots.all(func(slot):return w.party_encounter.member(slot.actor_id)==null),"enemy-led confirmation never auto-acts ally")
	check(w.world_time==before and w.party_encounter.member(Rules.current_actor(w))!=null,"enemy action does not consume whole cycle")
