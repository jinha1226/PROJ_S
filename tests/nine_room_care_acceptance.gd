extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Care=preload("res://sim/nine_room_care_rules.gd")
const Body=preload("res://sim/body_penalty_rules.gd")
const Action=preload("res://sim/party_action_command.gd")
const Plans=preload("res://sim/round_plan_service.gd")
const RoundState=preload("res://sim/round_combat_state.gd")
const Sim=preload("res://sim/simulator.gd")
var failures:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func audit(s,label:String):
	var error:String=s.sim.world.world_state_error()
	check(error.is_empty(),label+" audit "+error)
	if not error.is_empty():return
	var saved:Dictionary=s.sim.snapshot();var clone=Sim.from_snapshot(saved)
	check(clone!=null,label+" decode")
	if clone!=null:check(saved==clone.snapshot(),label+" exact JSON snapshot")
func hurt(s,id:int,_amount:int):
	var w=s.sim.world
	var alive:Array=w.party_encounter.enemy_ids.filter(func(actor):return w.combatant_states[actor].life_state=="ACTIVE")
	var enemy:int=alive[0]
	var before:int=w.entities[id].health
	place(w,enemy,w.entities[id].position+Vector2i.RIGHT)
	w.party_encounter.enemy_awareness(enemy).awareness_state="HUNTING"
	w.party_encounter.enemy_awareness(enemy).suspicion=1000
	for attempt in range(8):
		var old:Dictionary=w.party_encounter.round_combat
		var fresh:Dictionary=RoundState.fresh();fresh.round_id=old.round_id;fresh.plan_revision=old.plan_revision
		w.party_encounter.round_combat=fresh;Plans.begin(s.sim)
		var r:Dictionary=w.party_encounter.round_combat
		r.plans[str(enemy)]=Plans.pack(w,Action.melee(enemy,id),"AI")
		for actor in w.party_encounter.active_party_member_ids:
			check(s.edit_round_plan(actor,{"action":Action.hold(actor).to_dict(),"path":[]},int(r.plan_revision)).accepted,"damage fixture hold plan")
		var result:Dictionary=s.confirm_round(int(r.round_id),int(r.plan_revision))
		check(result.accepted,"damage fixture full round "+str(result.get("reason","")))
		if w.entities[id].health<before:break
	for attempt in range(12):
		if w.combatant_states[enemy].life_state=="DEAD":break
		var r:Dictionary=w.party_encounter.round_combat
		r.plans[str(enemy)]=Plans.pack(w,Action.melee(enemy,id),"AI")
		for actor in w.party_encounter.active_party_member_ids:
			var action=Action.melee(actor,enemy) if actor==id else Action.hold(actor)
			check(s.edit_round_plan(actor,{"action":action.to_dict(),"path":[]},int(r.plan_revision)).accepted,"clear fixture enemy plan")
		check(s.confirm_round(int(r.round_id),int(r.plan_revision)).accepted,"clear fixture enemy round")
	check(w.combatant_states[enemy].life_state=="DEAD","fixture ends actual encounter")
	var old:Dictionary=w.party_encounter.round_combat
	var fresh:Dictionary=RoundState.fresh();fresh.round_id=old.round_id;fresh.plan_revision=old.plan_revision
	w.party_encounter.round_combat=fresh
	for index in range(4):
		if w.combatant_states[id].status_rows.is_empty():break
		check(s.commit_field_action(Action.hold(w.party_control_actor_id())).accepted,"settle existing injury statuses")
	check(w.entities[id].health<before,"canonical melee damage fixture")
	var error:String=w.world_state_error()
	check(error.is_empty(),"damage fixture audit "+error)
func place(w,id:int,cell:Vector2i):
	var old:Vector2i=w.entities[id].position;w.entities[id].position=cell;w.reindex_entity_occupancy(id,old,cell)
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.sim!=null,"new run initialized")
	if s.sim==null:quit(1);return
	var w=s.sim.world;var hero:int=w.party_encounter.protagonist_id
	check(s.personal_rest_enabled(),"new ruleset enabled")
	var saved:String=s.save_session_json();var loaded=Session.new()
	check(loaded.load_session_json(saved).accepted and loaded.sim.snapshot()==s.sim.snapshot(),"new care session save replay")
	var before:Dictionary=s.sim.snapshot();var full:Dictionary=s.personal_rest_preview()
	check(not full.accepted,"fully restored party cannot rest")
	check(not s.request_personal_rest(1,1).accepted and s.sim.snapshot()==before,"full rejection no cost")
	hurt(s,hero,6)
	var food:int=w.party_encounter.ration_milli;var hp:int=w.entities[hero].health
	for index in range(100):
		var direction:=Vector2i.RIGHT if index%2==0 else Vector2i.LEFT
		var result:Dictionary=s.commit_field_action(Action.move_to(hero,w.entities[hero].position+direction)) if index<50 else s.commit_field_action(Action.hold(hero))
		check(result.accepted,"safe MOVE/HOLD accepted "+str(index))
	check(w.party_encounter.ration_milli==food and w.entities[hero].health==hp,"100 safe actions no food drain or heal")
	var offer:Dictionary=s.personal_rest_preview();
	check(w.world_state_error().is_empty(),"safe actions audit "+w.world_state_error())
	before=s.sim.snapshot()
	for index in range(30):check(s.personal_rest_preview()==offer,"preview repeat stable")
	check(s.sim.snapshot()==before,"preview preserves time food RNG residuals")
	check(offer.accepted,"hurt party can rest "+str(offer.reason))
	check(not s.request_personal_rest(int(offer.revision)+1,int(offer.request_id)).accepted and s.sim.snapshot()==before,"stale request no cost")
	# Invalid settings must fail before payment and leave the request reusable.
	var duration:Variant=Care.CONFIG.rest_time_cost
	Care.CONFIG.rest_time_cost=10001
	var failed:Dictionary=s.request_personal_rest(int(offer.revision),int(offer.request_id))
	Care.CONFIG.rest_time_cost=duration;w=s.sim.world
	check(not failed.accepted and s.sim.snapshot()==before,"invalid settings leave food time events residuals and request unchanged")
	var time:int=w.world_time
	var rested:Dictionary=s.request_personal_rest(int(offer.revision),int(offer.request_id))
	check(rested.accepted,"explicit rest accepted "+str(rested.get("reason",""))+" / "+Care.last_error)
	check(w.world_time==time+100 and w.party_encounter.ration_milli==food-10000,"one fixed food/time cost")
	check(w.entities[hero].health>hp,"personal HP restored")
	before=s.sim.snapshot()
	check(not s.request_personal_rest(int(offer.revision),int(offer.request_id)).accepted and s.sim.snapshot()==before,"duplicate request cannot heal/pay twice")
	audit(s,"one-person rest")
	# Empty food disables only rest, without legacy starvation or automatic meals.
	w.party_encounter.ration_milli=0;hurt(s,hero,2);hp=w.entities[hero].health
	var stress:int=w.party_encounter.member(hero).stress
	for index in range(10):check(s.commit_field_action(Action.hold(hero)).accepted,"empty food waiting")
	check(w.entities[hero].health==hp and w.party_encounter.ration_milli==0 and w.party_encounter.member(hero).stress==stress,"no starvation damage/stress or auto food")
	before=s.sim.snapshot();offer=s.personal_rest_preview()
	check(not offer.accepted and not s.request_personal_rest(int(offer.revision),int(offer.request_id)).accepted and s.sim.snapshot()==before,"insufficient food no cost")
	# Fixed-point HP/MP and personal differences use actual actor stat profiles.
	var trio=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",false)
	w=trio.sim.world;hero=w.party_encounter.protagonist_id
	var ids:Array=w.party_encounter.active_party_member_ids
	for id in ids: hurt(trio,id,12)
	var residual:Dictionary=Care.state(w).residuals.duplicate(true)
	check(Care.recover(w,ids,1,"COMBAT"),"personal resource pulse")
	check(Care.state(w).residuals!=residual,"fixed-point residual persisted")
	var snapshot:Variant=trio.sim.snapshot();var clone=Sim.from_snapshot(snapshot) if snapshot!=null else null
	check(clone!=null,"personal residual snapshot restores")
	if clone!=null:check(clone.snapshot()==snapshot,"personal residual exact restore")
	var original_tags:Array=w.entities[ids[1]].tags.duplicate()
	for tag in original_tags:
		if str(tag).begins_with("personal_talent:"):w.entities[ids[1]].tags.erase(tag)
	w.entities[ids[1]].tags.append("personal_talent:STRONG")
	var strong:Dictionary=Care.profile(w,ids[1])
	w.entities[ids[1]].tags.erase("personal_talent:STRONG")
	w.entities[ids[1]].tags.append("personal_talent:ARCANE")
	var arcane:Dictionary=Care.profile(w,ids[1])
	check(strong.hp_milli>arcane.hp_milli and strong.mp_milli<arcane.mp_milli,"actual personal talents produce different HP/MP rates")
	var second:Dictionary=arcane
	var mp_rate:int=Care.profile(w,ids[1]).mp_milli
	var hp_rate:int=Care.profile(w,ids[1]).hp_milli
	var body=w.body_states[ids[1]];var part:Dictionary=body.parts[1]
	for entry in body.parts:
		entry.condition="FUNCTIONAL"
		for layer in entry.layers:layer.integrity=1000
	var healthy:Dictionary=Care.profile(w,ids[1])
	mp_rate=healthy.mp_milli;hp_rate=healthy.hp_milli
	part.layers[2].integrity=550
	check(Care.profile(w,ids[1]).hp_milli<hp_rate and Care.profile(w,ids[1]).mp_milli==mp_rate,"injury reduces only own HP rate")
	part.layers[0].integrity=950;part.layers[1].integrity=695;part.layers[2].integrity=595
	var changes:Array=Body.heal_layers(body,1)
	check(part.layers[0].integrity==975 and part.layers[1].integrity==710 and part.layers[2].integrity==603,"skin muscle bone retain separate rates")
	check(Body.part_stage(part)==0,"fracture and deep wound thresholds recover immediately")
	part.condition="SEVERED";part.layers[0].integrity=0
	Body.heal_layers(body,10)
	check(part.condition=="SEVERED" and part.layers[0].integrity==0,"rest cannot regrow severed part")
	# Actual mixed-round HOLD at zero food earns one pulse and preview earns none.
	var fight=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	w=fight.sim.world;hero=w.party_encounter.protagonist_id
	hurt(fight,hero,4);w.party_encounter.ration_milli=0
	var enemy:int=w.party_encounter.enemy_ids.filter(func(actor):return w.combatant_states[actor].life_state=="ACTIVE")[0]
	place(w,enemy,w.entities[hero].position+Vector2i(2,0))
	w.party_encounter.enemy_awareness(enemy).awareness_state="HUNTING"
	w.party_encounter.enemy_awareness(enemy).suspicion=1000
	w.party_encounter.round_combat=RoundState.fresh();Plans.begin(fight.sim)
	check(fight.round_active(),"active encounter fixture")
	var r:Dictionary=w.party_encounter.round_combat
	check(fight.edit_round_plan(hero,{"action":Action.hold(hero).to_dict(),"path":[]},int(r.plan_revision)).accepted,"hold draft")
	before=fight.sim.snapshot();fight.round_preview();fight.round_preview()
	check(fight.sim.snapshot()==before,"combat previews do not recover")
	var result:Dictionary=fight.confirm_round(int(r.round_id),int(r.plan_revision))
	check(result.accepted,"actual combat hold resolves "+str(result.get("reason","")))
	check(w.party_encounter.ration_milli==0,"combat at zero food does not consume or auto eat")
	check(w.events.any(func(e):return e.type=="care.recovered" and e.data.context=="COMBAT"),"actual combat hold receives recovery")
	audit(fight,"combat care")
	print("NINE_ROOM_CARE ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
