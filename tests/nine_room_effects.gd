extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Rules=preload("res://sim/room_transition_rules.gd")
const Effects=preload("res://sim/consumable_effects.gd")
const Ops=preload("res://sim/world_item_operations.gd")
const Action=preload("res://sim/party_action_command.gd")
const Sim=preload("res://sim/simulator.gd")
var failures:Array=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func place(w,id:int,p:Vector2i):
	var old:Vector2i=w.entities[id].position;w.entities[id].position=p;w.reindex_entity_occupancy(id,old,p)
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var w=s.sim.world;var party=w.party_encounter;var hero:int=party.protagonist_id;var enemy:int=party.enemy_ids[0]
	place(w,hero,Vector2i(14,11));party.group_anchor=w.entities[hero].position
	place(w,enemy,Vector2i(20,12))
	# Seed a canonical status fixture in the inactive room. Public potion
	# targeting is independently covered by expanded_consumables_acceptance.
	var granted:Dictionary=Ops.commit_grant(w,hero,"POTION_MYSTERY_POISON",1,w.entities[hero].position,"ROOM_EFFECT_FIXTURE")
	var consumed:Dictionary=Ops.commit_use(w,hero,str(granted.instance_id),w.entities[hero].position,100)
	var source=w.emit_event("consumable.activated",hero,enemy,w.entities[hero].position,0,int(consumed.event_id),{"schema_version":1,"definition_id":"POTION_MYSTERY_POISON","selection":{"target_id":enemy}})
	check(source!=null and Effects.add(w,hero,enemy,"POISON",source.id),"canonical poison fixture")
	var initial_hp:int=w.entities[enemy].health;var expiry:String=Effects.status(w,enemy,"POISON").data.until
	for i in range(3):check(s.commit_field_action(Action.hold(hero)).accepted,"inactive time advances")
	check(w.world_time==300 and w.entities[enemy].health==initial_hp,"inactive poison waits for reentry")
	var portal:Dictionary=Rules.portal(w,"F1_R4_R5")
	var entered:Dictionary=s.request_room_exit(hero,portal.portal_id,int(party.nine_room_floor.revision))
	check(entered.accepted and entered.room_result.transitioned,"effect catchup inside transition "+str(entered.get("reason","")))
	check(w.world_time==400 and w.entities[enemy].health==initial_hp-16,"four bounded poison pulses once")
	check(Effects.status(w,enemy,"POISON")==null and expiry=="400","absolute expiry unchanged")
	check(party.nine_room_floor.effect_processed_at["1:5"]=="400","catchup clock saved")
	check(w.world_state_error().is_empty(),"effect transition world audit "+w.world_state_error())
	var saved=s.sim.snapshot();check(saved!=null,"effect snapshot")
	if saved!=null:
		var clone=Sim.from_snapshot(saved);check(clone!=null,"effect restore")
		if clone!=null:check(clone.snapshot()==saved,"effect restore exact")
	var pulses:int=w.events.filter(func(e):return e.type=="consumable.pulse" and e.target_id==enemy).size()
	var hp:int=w.entities[enemy].health
	w.begin_step(w.step_index+1)
	check(Effects.tick(s.sim,400,400,Vector2i(1,5)),"repeated catchup empty")
	w.finish_step()
	check(w.entities[enemy].health==hp and w.events.filter(func(e):return e.type=="consumable.pulse" and e.target_id==enemy).size()==pulses,"catchup cannot double apply")
	print("NINE_ROOM_EFFECTS ","PASS" if failures.is_empty() else failures);quit(0 if failures.is_empty() else 1)
