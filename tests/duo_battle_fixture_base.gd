extends SceneTree

## Shared DUO fixture base for battle acceptance tests: an ENGAGED expedition
## reached through the normal walk-to-contact route, plus check helpers.

const Session=preload("res://playtest/party_playtest_session.gd")
const SimCommand=preload("res://sim/sim_command.gd")
const WORLD_SEED:=44
const PERSONALITY_SEED:=20260828
var failures:Array[String]=[]

func _init()->void:call_deferred("_run")

func _run()->void:pass

func _check(value:bool,message:String)->void:
	if not value:failures.append(message)

func _check_eq(got:Variant,expected:Variant,message:String)->void:
	if got!=expected:failures.append("%s (expected %s, got %s)"%[message,str(expected),str(got)])

func _new_engaged_duo():
	var session=Session.new(WORLD_SEED,PERSONALITY_SEED,Session.DUO_SCENARIO_ID)
	if session.sim==null:
		_check(false,"DUO session did not initialize");return null
	var state=session.sim.world.party_encounter
	var hero_id:=int(state.protagonist_id)
	var best:Dictionary={}
	for enemy_id_value in state.enemy_ids:
		var enemy_id:=int(enemy_id_value)
		if not session.sim.world.is_unresolved_enemy(enemy_id):continue
		var enemy_position:Vector2i=session.sim.world.entities[enemy_id].position
		for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var path:Dictionary=session.find_exploration_path(hero_id,enemy_position+delta)
			if bool(path.get("found",false)) and (best.is_empty() or path.path.size()<best.path.size()):best=path
		if not best.is_empty() and best.path.size()<=4:break
	if best.is_empty():
		_check(false,"normal generated DUO map has no route to an encounter");return null
	for value in best.path.slice(1):
		var step:Dictionary=session.commit_exploration(SimCommand.move_to(hero_id,value))
		if not bool(step.get("accepted",false)):
			_check(false,"normal route step rejected: %s"%str(step.get("reason","")));return null
		if str(session.party_status().get("safe_phase",""))=="CONTACT":break
	_check_eq(session.party_status().get("safe_phase",""),"CONTACT","generated route reaches contact")
	if str(session.party_status().get("safe_phase",""))!="CONTACT":return null
	var companion_id:=int(state.party_member_ids[1])
	var preview:Dictionary=session.preview_deployment("LINE",[companion_id])
	_check(bool(preview.get("accepted",false)),"normal deployment preview accepts companion")
	if not bool(preview.get("accepted",false)):return null
	var committed:Dictionary=session.commit_deployment()
	_check(bool(committed.get("accepted",false)),"normal deployment enters combat")
	_check_eq(session.party_status().get("safe_phase",""),"ENGAGED","generated deployment enters ENGAGED")
	return session
const Clock=preload("res://playtest/autonomous_battle_clock.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")

