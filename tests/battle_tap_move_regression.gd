extends SceneTree

## Regression: while a companion fights (safe_phase ENGAGED, COMBAT view) the
## hero must still be movable from the map. Tapping a reachable cell reserves a
## journaled position order for the protagonist and the battle clock walks it.

const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const SimCommand=preload("res://sim/sim_command.gd")
var failures:Array[String]=[]

func _init()->void:call_deferred("run")
func _check(value:bool,message:String)->void:
	if not value:failures.append(message);printerr("FAIL ",message)

func _engaged_duo():
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var state=session.sim.world.party_encounter;var hero_id:=int(state.protagonist_id)
	var best:Dictionary={}
	for enemy_id_value in state.enemy_ids:
		var enemy_id:=int(enemy_id_value)
		if not session.sim.world.is_unresolved_enemy(enemy_id):continue
		var enemy_position:Vector2i=session.sim.world.entities[enemy_id].position
		for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var path:Dictionary=session.find_exploration_path(hero_id,enemy_position+delta)
			if bool(path.get("found",false)) and (best.is_empty() or path.path.size()<best.path.size()):best=path
		if not best.is_empty() and best.path.size()<=4:break
	if best.is_empty():_check(false,"no route to an encounter");return null
	for value in best.path.slice(1):
		var step:Dictionary=session.commit_exploration(SimCommand.move_to(hero_id,value))
		if not bool(step.get("accepted",false)):_check(false,"route step rejected");return null
		if str(session.party_status().get("safe_phase",""))=="CONTACT":break
	# Awareness rule: an enemy that noticed the party opens the contact on its
	# next step. Give it up to three turns after the walk.
	for wait_turn in range(3):
		if str(session.party_status().get("safe_phase",""))!="GROUPED":break
		if not bool(session.commit_exploration(SimCommand.wait(hero_id)).get("accepted",false)):break
	var companion_id:=int(state.party_member_ids[1])
	if not bool(session.preview_deployment("LINE",[companion_id]).get("accepted",false)):
		_check(false,"deployment preview rejected");return null
	if not bool(session.commit_deployment().get("accepted",false)):
		_check(false,"deployment rejected");return null
	_check(str(session.party_status().get("safe_phase",""))=="ENGAGED","fixture is ENGAGED")
	return session

func run()->void:
	var session=_engaged_duo()
	if session==null:_finish();return
	var world=session.sim.world;var hero:int=int(world.party_encounter.protagonist_id)
	var ui=Sandbox.new();ui.size=Vector2(390,800);ui.initialize_for_headless_test(session,true);ui.battle_mode="AUTO"
	ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);ui.size=Vector2(390,800);root.add_child(ui)
	ui.set_process(false)
	for i in range(4):await process_frame
	_check(str(session.party_status().get("view_mode",""))=="COMBAT","companion fight shows the COMBAT view")
	var start:Vector2i=world.entities[hero].position
	# A reachable cell that is not adjacent to the hero: a plain walk order.
	var goal:Vector2i=Vector2i(-1,-1)
	for radius in [2,3]:
		for dy in range(-radius,radius+1):
			for dx in range(-radius,radius+1):
				var cell:Vector2i=start+Vector2i(dx,dy)
				if maxi(absi(dx),absi(dy))!=radius or not world.in_bounds(cell):continue
				var path:Dictionary=session.sim.pathfinder.find_path(hero,cell)
				if bool(path.get("found",false)) and path.path.size()==radius+1:goal=cell;break
			if goal!=Vector2i(-1,-1):break
		if goal!=Vector2i(-1,-1):break
	_check(goal!=Vector2i(-1,-1),"fixture has a walkable cell two or three steps away")
	if goal==Vector2i(-1,-1):_finish();return
	var journal_before:int=session.command_journal.size()
	ui.grid.world_cell_pressed.emit(goal)
	for i in range(2):await process_frame
	_check(session.individual_battle.movements.get(hero,Vector2i(-1,-1))==goal,
		"map tap during a companion fight reserves the hero position order")
	_check(session.command_journal.size()==journal_before+1 \
		and str(session.command_journal[-1].get("kind",""))=="reserve_move",
		"the reservation is journaled as reserve_move")
	var moved:=false
	for i in range(40):
		if world.entities[hero].position==goal:moved=true;break
		if str(session.party_status().get("safe_phase",""))!="ENGAGED":break
		var result:Dictionary=session.individual_battle.commit()
		if not bool(result.get("accepted",false)):break
	_check(moved,"the battle clock walks the hero to the tapped cell (at %s, wanted %s)"%[
		world.entities[hero].position,goal])
	if moved:
		var saved:String=session.save_session_json();var loaded=Session.new()
		var load_result:Dictionary=loaded.load_session_json(saved)
		_check(bool(load_result.get("accepted",false)),"session with a reserved move reloads")
		if bool(load_result.get("accepted",false)):
			_check(loaded.sim.snapshot()==session.sim.snapshot(),"reserved move replays exactly")
	_finish()

func _finish()->void:
	if failures.is_empty():print("PASS battle tap move regression");quit(0)
	else:printerr("FAIL battle tap move regression: %d failures"%failures.size());quit(1)
