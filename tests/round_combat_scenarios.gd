extends SceneTree
const Fixture=preload("res://tests/round_combat_fixture.gd")
const Rules=preload("res://sim/round_combat_rules.gd")
const State=preload("res://sim/round_combat_state.gd")
const Plans=preload("res://sim/round_plan_service.gd")
const System=preload("res://sim/systems/round_combat_system.gd")
const Preview=preload("res://sim/round_preview_service.gd")
const Action=preload("res://sim/party_action_command.gd")
var failures:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	var s=Fixture.create();check(s!=null,"small three-person fixture")
	if s==null:quit(1);return
	var w=s.sim.world;var party=w.party_encounter
	check(s.round_active(),"fixture planning")
	check(w.world_state_error().is_empty(),"fixture audit "+w.world_state_error())
	var r:Dictionary=party.round_combat
	var before=w.snapshot();var journal=s.command_journal.duplicate(true)
	var preview=Preview.preview(s.sim)
	check(preview.accepted,"same resolver preview "+str(preview))
	check(before==w.snapshot() and journal==s.command_journal,"preview full authority unchanged")
	var plans:Dictionary=r.plans.duplicate(true);var hero:int=party.protagonist_id
	var edit=Plans.edit(s.sim,hero,{"action":Action.hold(hero).to_dict(),"path":[]},r.plan_revision)
	check(edit.accepted,"ally editable")
	for id in plans:
		if int(id)!=hero:check(plans[id]==r.plans[id],"other plans fixed "+id)
	var enemy:int=party.enemy_ids[0]
	check(not Plans.edit(s.sim,enemy,{"action":Action.hold(enemy).to_dict(),"path":[]},r.plan_revision).accepted,"enemy readonly")
	check(not System.confirm(s.sim,r.round_id,int(r.plan_revision)-1).accepted,"stale confirm")
	var rid:int=r.round_id;var revision:int=r.plan_revision;var time:int=w.world_time
	var done=System.confirm(s.sim,rid,revision)
	check(done.accepted,"mixed resolver confirm "+str(done))
	check(w.world_time==time+100,"fixed100 time for party3")
	check(done.slots.size()==r.participants.size(),"one slot each")
	check(not System.confirm(s.sim,rid,revision).accepted,"double tap refused")
	check(w.world_state_error().is_empty(),"actual combat audit "+w.world_state_error())
	print("ROUND_SCENARIOS ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
