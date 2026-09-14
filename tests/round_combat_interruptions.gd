extends SceneTree
const Fixture=preload("res://tests/round_combat_fixture.gd")
const State=preload("res://sim/round_combat_state.gd")
const Rules=preload("res://sim/round_combat_rules.gd")
const Field=preload("res://sim/field_turn_rules.gd")
const Plans=preload("res://sim/round_plan_service.gd")
const System=preload("res://sim/systems/round_combat_system.gd")
const Preview=preload("res://sim/round_preview_service.gd")
const Action=preload("res://sim/party_action_command.gd")
const Awareness=preload("res://sim/enemy_awareness_state.gd")
const Simulator=preload("res://sim/simulator.gd")
var failures:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	var s=Fixture.create();var w=s.sim.world;var party=w.party_encounter;var hero:int=party.protagonist_id
	for y in range(1,9):
		for x in range(3,12):
			var cell:=Vector2i(x,y)
			if w.blocking_entity_at(cell)!=null:continue
			check(w.bootstrap_set_terrain(cell,"wall" if x==7 and y!=3 else "stone_floor"),"fixture terrain "+str(cell))
	Fixture.relocate(w,party.enemy_ids[0],Vector2i(5,6))
	var hidden=w.add_entity("melee_enemy","비공개 추격자",Vector2i(9,3),40,["party_enemy"],"goblin","enemy")
	party.enemy_ids.append(hidden.id);party.enemy_ids.sort();party.enemy_busy_rows[hidden.id]=w.world_time
	party.enemy_awareness_rows[hidden.id]=Awareness.new(hidden.id,hidden.position)
	party.enemy_awareness(hidden.id).awareness_state="HUNTING"
	party.member(hero).action_speeds={"MOVE":150,"ATTACK":100,"CAST":100}
	party.round_combat=State.fresh();check(Plans.begin(s.sim),"begin hidden fixture")
	check(not Field.visible(w,hidden.id),"enemy hidden behind wall")
	check(str(hidden.id) not in party.round_combat.order,"hidden enemy excluded from order")
	for id in party.active_party_member_ids:
		check(Plans.edit(s.sim,id,{"action":Action.hold(id).to_dict(),"path":[]},party.round_combat.plan_revision).accepted,"hold ally")
	# Route to the gap is visible; the next step beyond it reveals a new threat.
	var route:Array=[[6,5],[6,4],[6,3],[7,3]]
	var edit:=Plans.edit(s.sim,hero,{"action":Action.hold(hero).to_dict(),"path":route},party.round_combat.plan_revision)
	check(edit.accepted,"gap movement plan "+str(edit))
	if not edit.accepted:quit(1);return
	var before=w.snapshot();var preview:=Preview.preview(s.sim)
	check(preview.accepted and preview.conditional,"preview marks undisclosed interruption conditional")
	check(not JSON.stringify(preview).contains("비공개 추격자") and not JSON.stringify(s.round_status()).contains("비공개 추격자"),"hidden name not leaked")
	check(before==w.snapshot(),"hidden preview leaves authority untouched")
	var r:Dictionary=party.round_combat;var rid:int=r.round_id;var revision:int=r.plan_revision;var time:int=w.world_time
	var interrupted:=System.confirm(s.sim,rid,revision)
	check(interrupted.accepted and interrupted.reason=="interrupted","logical mid-slot interruption "+str(interrupted))
	check(w.world_time==time and not r.round_time_committed,"partial round has no duplicate time tick")
	check(r.execution_cursor==0 and int(r.slot_progress.get(str(hero),0))<route.size(),"stopped before next movement step")
	check(w.entities[hero].position!=Vector2i(7,3),"unexecuted destination not committed")
	check(w.events.filter(func(e):return e.type=="action.melee_attack" and e.actor_id==hidden.id).is_empty(),"new enemy no surprise free attack")
	var snap=w.snapshot();check(snap!=null,"interrupted full snapshot "+w.world_state_error())
	if snap==null:quit(1);return
	var restored=Simulator.from_snapshot(snap);check(restored!=null,"interrupted state decode")
	if restored!=null:check(restored.snapshot()==snap,"partial cursor/budget/commitment restore exact")
	System.incorporate(s.sim)
	check(str(hidden.id) in r.order and r.order.back()==str(hidden.id),"new enemy appended at resume planning boundary")
	var moves_before:int=w.events.filter(func(e):return e.type=="action.move" and e.actor_id==hero).size()
	var remaining:int=route.size()-int(r.slot_progress.get(str(hero),0))
	var resumed:=System.confirm(s.sim,rid,r.plan_revision,true)
	check(resumed.accepted and resumed.completed,"resume completes suffix "+str(resumed))
	check(w.world_time==time+100,"resume charges one100 boundary")
	check(w.events.filter(func(e):return e.type=="action.move" and e.actor_id==hero).size()==moves_before+remaining,"completed movement prefix never repeated")
	check(not System.confirm(s.sim,rid,revision,true).accepted,"old resume duplicate refused")
	check(w.world_state_error().is_empty(),"resumed audit "+w.world_state_error())
	# Relevant search persists across walls until actual world ticks expire it.
	var enemy:int=party.enemy_ids[0]
	party.enemy_awareness(enemy).awareness_state="SEARCHING"
	check(enemy in Rules.relevant_enemies(w),"searching enemy retains party combat")
	party.enemy_awareness(enemy).awareness_state="RETURNING"
	Fixture.relocate(w,enemy,Vector2i(w.width-2,w.height-2))
	check(enemy not in Rules.relevant_enemies(w),"unrelated returning enemy not party pursuer")
	# Exhausted movement stays exhausted through repeated edits and a save.
	var budget_session=Fixture.create();var bw=budget_session.sim.world
	var br:Dictionary=bw.party_encounter.round_combat;var bh:int=bw.party_encounter.protagonist_id
	var bk:=str(bh);br.phase="INTERRUPTED";br.interrupt_reason="new_threat"
	br.slot_spent[bk]=int(br.plans[bk].move_budget)
	var total:int=br.slot_spent[bk]
	for attempt in range(3):
		check(Plans.edit(budget_session.sim,bh,{"action":Action.hold(bh).to_dict(),"path":[]},br.plan_revision).accepted,"exhausted actor can edit hold")
		check(int(br.slot_spent[bk])==total,"editing keeps spent movement")
		var cell:Vector2i=bw.entities[bh].position+Vector2i.UP
		var extra:=Plans.edit(budget_session.sim,bh,{"action":Action.hold(bh).to_dict(),"path":[[cell.x,cell.y]]},br.plan_revision)
		check(not extra.accepted and extra.reason=="round_move_budget","repeat edit cannot create free movement")
	var budget_snapshot=bw.snapshot()
	check(budget_snapshot!=null,"spent budget snapshot valid")
	if budget_snapshot!=null:
		var budget_restored=Simulator.from_snapshot(budget_snapshot)
		check(budget_restored!=null and int(budget_restored.world.party_encounter.round_combat.slot_spent[bk])==total,"spent budget survives reload")
	print("ROUND_INTERRUPTION ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
