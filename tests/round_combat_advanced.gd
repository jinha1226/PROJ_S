extends SceneTree
const Fixture=preload("res://tests/round_combat_fixture.gd")
const State=preload("res://sim/round_combat_state.gd")
const Rules=preload("res://sim/round_combat_rules.gd")
const Plans=preload("res://sim/round_plan_service.gd")
const System=preload("res://sim/systems/round_combat_system.gd")
const Preview=preload("res://sim/round_preview_service.gd")
const Action=preload("res://sim/party_action_command.gd")
const Awareness=preload("res://sim/enemy_awareness_state.gd")
const Simulator=preload("res://sim/simulator.gd")
const Items=preload("res://sim/world_item_operations.gd")
var failures:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func restart(s):
	s.sim.world.party_encounter.round_combat=State.fresh()
	check(Plans.begin(s.sim),"fixture plan boundary")
func edit(s,id:int,path:Array=[],action=null)->Dictionary:
	return Plans.edit(s.sim,id,{"action":(action if action!=null else Action.hold(id)).to_dict(),"path":path},int(s.sim.world.party_encounter.round_combat.plan_revision))
func confirm(s)->Dictionary:
	var r:Dictionary=s.sim.world.party_encounter.round_combat
	return System.confirm(s.sim,int(r.round_id),int(r.plan_revision),r.phase=="INTERRUPTED")
func audit(s,label:String):
	var error:String=s.sim.world.world_state_error();check(error.is_empty(),label+" audit "+error)
	if error.is_empty():
		var snap=s.sim.snapshot();var clone=Simulator.from_snapshot(snap)
		check(clone!=null,label+" decode")
		if clone!=null:check(clone.snapshot()==snap,label+" exact restore")
func add_enemy(s,p:Vector2i)->int:
	var w=s.sim.world;var e=w.add_entity("melee_enemy","추가 고블린",p,40,["party_enemy"],"goblin","enemy")
	var party=w.party_encounter;party.enemy_ids.append(e.id);party.enemy_ids.sort()
	party.enemy_busy_rows[e.id]=w.world_time;party.enemy_awareness_rows[e.id]=Awareness.new(e.id,p)
	party.enemy_awareness(e.id).awareness_state="HUNTING";party.enemy_awareness(e.id).suspicion=1000
	return e.id
func run():
	var s=Fixture.create(1);check(s!=null,"advanced fixture")
	if s==null:quit(1);return
	var w=s.sim.world;var party=w.party_encounter;var hero:int=party.protagonist_id
	var allies:Array=party.active_party_member_ids.duplicate();var enemy_a:int=party.enemy_ids[0]
	Fixture.relocate(w,hero,Vector2i(6,5));Fixture.relocate(w,allies[1],Vector2i(4,5));Fixture.relocate(w,allies[2],Vector2i(4,6))
	Fixture.relocate(w,enemy_a,Vector2i(7,5));var enemy_b:=add_enemy(s,Vector2i(5,5));var enemy_c:=add_enemy(s,Vector2i(8,5))
	party.group_anchor=w.entities[hero].position
	party.member(hero).action_speeds={"MOVE":200,"ATTACK":200,"CAST":200}
	party.member(allies[1]).action_speeds={"MOVE":125,"ATTACK":125,"CAST":125}
	party.member(allies[2]).action_speeds={"MOVE":50,"ATTACK":50,"CAST":50}
	restart(s);var base:Dictionary=s.sim.capture_rollback_memento(false)
	check(party.round_combat.order.size()==6,"party3 enemies3")
	var indices:Array=[]
	for id in party.round_combat.order:indices.append(id in allies.map(func(v):return str(v)))
	check(indices==[true,true,false,false,false,true],"initiative genuinely mixes factions")
	var fixed:Dictionary=party.round_combat.plans.duplicate(true)
	check(edit(s,hero,[[6,6]]).accepted,"first ally leaves attack tile")
	check(edit(s,allies[1],[],Action.skill(allies[1],"SHOVE",enemy_b)).accepted,"hero shove plan")
	check(edit(s,allies[2]).accepted,"last ally hold")
	for id in [enemy_a,enemy_b,enemy_c]:check(party.round_combat.plans[str(id)]==fixed[str(id)],"enemy plan fixed "+str(id))
	# Lowering initial fixture HP is legitimate initial state, not injected damage.
	w.entities[enemy_b].health=20
	var before=s.sim.snapshot();var predicted:=Preview.preview(s.sim)
	check(predicted.accepted,"shove sequential preview")
	check(before==s.sim.snapshot(),"shove preview does not mutate")
	var xp:int=party.protagonist_progression.xp_total
	var time:int=w.world_time;var done:=confirm(s)
	check(done.accepted and done.completed,"six slots one confirm "+str(done))
	check(w.world_time==time+100,"six actors one100 boundary")
	if done.accepted:
		check(done.slots.size()==6,"all six opportunities exactly once")
		var damage_events:Array=w.events.filter(func(e):return e.type=="combat.physical_damage" and e.target_id==enemy_b)
		check(damage_events.any(func(e):return w.event_by_id(e.cause_id).actor_id==enemy_a),"enemy hits displaced enemy on fixed tile")
		check(w.combatant_states[enemy_b].life_state=="DEAD","enemy friendly-fire kill")
		check(party.protagonist_progression.xp_total>xp,"enemy friendly-fire kill grants player xp")
		var rewards:Array=w.events.filter(func(e):return e.type=="progression.enemy_reward" and e.target_id==enemy_b)
		check(rewards.size()==1,"friendly-fire XP rewarded exactly once")
		if rewards.size()==1:
			var death=w.event_by_id(rewards[0].cause_id)
			check(death!=null and death.type=="entity.died" and death.instigator_id==enemy_a,"friendly-fire XP preserves real killer")
		var rewarded_xp:int=party.protagonist_progression.xp_total
		check(s.sim.party_coordinator.reconcile_liveness(false),"repeat friendly-fire reconciliation")
		check(party.protagonist_progression.xp_total==rewarded_xp,"repeat reconciliation cannot duplicate XP")
		check(done.slots.any(func(row):return row.actor_id==enemy_b and row.status=="CANCELLED"),"dead actor's later slot cancelled")
		for p in predicted.slots:
			var actual:Array=done.slots.filter(func(row):return row.actor_id==p.actor_id)
			if not actual.is_empty():check(p.damage==actual[0].damage and p.status==actual[0].status,"preview actual damage/cancel match "+str(p.actor_id))
	audit(s,"friendly fire/drop")
	# Injury affects movement, never initiative or fixed round time.
	s.sim.restore_rollback_memento(base);w=s.sim.world;party=w.party_encounter
	var budget:=Rules.move_budget(w,hero);var initiative:=Rules.initiative(w,hero)
	w.entities[hero].tags.append("body_penalties_v1")
	var leg:Dictionary=w.body_states[hero].parts[4];leg.layers[2].integrity=500
	check(Rules.move_budget(w,hero)<budget,"leg fracture reduces move budget")
	check(Rules.initiative(w,hero)==initiative,"leg fracture does not change initiative")
	preload("res://sim/body_penalty_rules.gd").heal_layers(w.body_states[hero],20)
	check(Rules.move_budget(w,hero)==budget,"rest healing restores movement")
	# Blocked fixed path: no reroute and no target substitution.
	s.sim.restore_rollback_memento(base);w=s.sim.world;party=w.party_encounter
	check(edit(s,allies[1],[[4,6],[5,6]]).accepted,"blocked path authorable")
	var row:Dictionary=party.round_combat.plans[str(hero)]
	var p:=Preview.preview(s.sim)
	check(p.slots.any(func(slot):return slot.actor_id==allies[1] and slot.reason=="path_blocked"),"occupied path predicts stop")
	# Item use edits the plan and uses the existing potion effect at its slot.
	s.sim.restore_rollback_memento(base);w=s.sim.world;party=w.party_encounter
	# Existing enemy resolver supplies canonical HP loss, not fixture injection.
	for attempt in range(5):
		for ally in allies:edit(s,ally)
		var harm:=confirm(s)
		check(harm.accepted,"canonical potion setup damage")
		if w.entities[hero].health<w.entities[hero].max_health:break
	var injured_hp:int=w.entities[hero].health
	check(injured_hp<w.entities[hero].max_health,"potion starts after real damage")
	var held_before=s.sim.snapshot();var count:int=w.inventory_of(hero).item("START_POTION_001").quantity
	var item_edit=s.stage_round_item("USE","START_POTION_001","",{})
	check(item_edit.accepted,"potion planned")
	check(w.entities[hero].health==injured_hp and w.inventory_of(hero).item("START_POTION_001").quantity==count,"potion edit spends no HP/item")
	var item_preview:=Preview.preview(s.sim);check(item_preview.accepted,"potion shadow effect")
	var item_done:=confirm(s);check(item_done.accepted,"potion real slot")
	check(w.inventory_of(hero).item("START_POTION_001").quantity==count-1,"potion consumed exactly once")
	audit(s,"item slot")
	print("ROUND_ADVANCED ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
