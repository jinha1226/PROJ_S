extends SceneTree

## HERO_TURN: the fight stops at every protagonist turn until the player
## releases it (own-cell tap, enemy tap, position order, skill, or [진행]);
## companions and enemies then resolve automatically until the next hero turn.
## AUTO keeps the free-running clock.

const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const SimCommand=preload("res://sim/sim_command.gd")
var failures:Array[String]=[]

func _init()->void:call_deferred("run")
func _check(value:bool,message:String)->void:
	if not value:failures.append(message);printerr("FAIL ",message)

func _engaged_duo():
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var state=session.sim.world.party_encounter;var hero_id:=int(state.protagonist_id);var best:Dictionary={}
	for enemy_id_value in state.enemy_ids:
		var enemy_id:=int(enemy_id_value)
		if not session.sim.world.is_unresolved_enemy(enemy_id):continue
		var ep:Vector2i=session.sim.world.entities[enemy_id].position
		for d in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var path:Dictionary=session.find_exploration_path(hero_id,ep+d)
			if bool(path.get("found",false)) and (best.is_empty() or path.path.size()<best.path.size()):best=path
		if not best.is_empty() and best.path.size()<=4:break
	if best.is_empty():return null
	for v in best.path.slice(1):
		if not bool(session.commit_exploration(SimCommand.move_to(hero_id,v)).get("accepted",false)):return null
		if str(session.party_status().get("safe_phase",""))=="CONTACT":break
	session.preview_deployment("LINE",[int(state.party_member_ids[1])]);session.commit_deployment()
	return session if str(session.party_status().get("safe_phase",""))=="ENGAGED" else null

func _pump(ui,seconds:float)->void:
	var elapsed:=0.0
	while elapsed<seconds:
		ui._tick_autonomous_battle(0.05);elapsed+=0.05

func _hero_actions_since(world,hero:int,start:int)->int:
	var count:=0
	for index in range(start,world.events.size()):
		var event=world.events[index]
		if int(event.actor_id)==hero and str(event.type).begins_with("action."):count+=1
	return count

func _engaged(session)->bool:return str(session.party_status().get("safe_phase",""))=="ENGAGED"

func run()->void:
	var session=_engaged_duo()
	_check(session!=null,"fixture is ENGAGED")
	if session==null:_finish();return
	var world=session.sim.world;var hero:int=int(world.party_encounter.protagonist_id)
	var ui=Sandbox.new();ui.size=Vector2(390,800);ui.initialize_for_headless_test(session,true)
	ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);ui.size=Vector2(390,800);root.add_child(ui);ui.set_process(false)
	for i in range(3):await process_frame
	_check(ui.battle_mode=="HERO_TURN","HERO_TURN is the default battle mode")
	# 1. The clock runs to the hero's event and stops there.
	_pump(ui,3.0)
	_check(ui.hero_turn_waiting(),"clock waits at the protagonist's turn")
	_check(int(session.individual_battle.next_event().get("actor_id",-1))==hero,"next event is the protagonist")
	var waiting_events:int=world.events.size()
	_pump(ui,2.0)
	_check(world.events.size()==waiting_events,"nothing happens while waiting for the hero")
	_check(not ui.autonomous_battle_clock.paused,"waiting is not the explicit pause")
	_check(str(ui.grid.battle_notice).begins_with("내 차례"),"map notice announces the hero turn")
	var pause_button:=ui.find_child("PortraitBattlePause",true,false) as Button
	_check(pause_button!=null and pause_button.text=="진행","HERO_TURN pause slot reads 진행")
	# 2. Own-cell tap releases exactly one hero action, then the clock waits again.
	ui.grid.world_cell_pressed.emit(world.entities[hero].position);await process_frame
	_check(not ui.hero_turn_waiting(),"own-cell tap releases the turn")
	_pump(ui,3.0)
	_check(_hero_actions_since(world,hero,waiting_events)==1,"exactly one protagonist action per release (got %d)"%_hero_actions_since(world,hero,waiting_events))
	_check(ui.hero_turn_waiting() or not _engaged(session),"clock stops again at the next protagonist turn")
	# 3. [진행] releases one turn too.
	if _engaged(session):
		var before:int=world.events.size()
		ui._on_product_execute();await process_frame
		_pump(ui,3.0)
		_check(_hero_actions_since(world,hero,before)==1,"진행 releases exactly one protagonist action")
	# 4. A far position order keeps walking without stopping until arrival.
	if _engaged(session) and ui.hero_turn_waiting():
		var start:Vector2i=world.entities[hero].position;var goal:=Vector2i(-1,-1)
		for r in [3,4,2]:
			for dy in range(-r,r+1):
				for dx in range(-r,r+1):
					var c:Vector2i=start+Vector2i(dx,dy)
					if maxi(absi(dx),absi(dy))!=r or not world.in_bounds(c):continue
					var p:Dictionary=session.sim.pathfinder.find_path(hero,c)
					if bool(p.get("found",false)) and p.path.size()==r+1:goal=c;break
				if goal!=Vector2i(-1,-1):break
			if goal!=Vector2i(-1,-1):break
		if goal!=Vector2i(-1,-1):
			var before_walk:int=world.events.size()
			ui.grid.world_cell_pressed.emit(goal);await process_frame
			_pump(ui,6.0)
			var moves:=_hero_actions_since(world,hero,before_walk)
			_check(moves>=2 or world.entities[hero].position==goal or not _engaged(session),
				"a standing position order walks several steps without re-confirming (got %d)"%moves)
	# 5. Enemy tap (focus) releases the turn.
	if _engaged(session):
		_pump(ui,3.0)
		var enemy:=-1
		for id in session.party_status().get("visible_enemy_ids",[]):
			if world.is_autonomous_target(int(id)):enemy=int(id);break
		if enemy>0 and ui.hero_turn_waiting():
			ui.grid.actor_pressed.emit(enemy);await process_frame
			_check(not ui.hero_turn_waiting(),"enemy tap releases the turn with a focus target")
	# 6. AUTO toggle: button text and free running.
	ui._refresh();await process_frame
	var toggle:=ui.find_child("PortraitBattleMode",true,false) as Button
	_check(toggle!=null and toggle.text=="자동","HERO_TURN shows the 자동 toggle")
	if toggle!=null:
		toggle.pressed.emit();await process_frame
		_check(ui.battle_mode=="AUTO","toggle switches to AUTO")
		toggle=ui.find_child("PortraitBattleMode",true,false) as Button
		_check(toggle!=null and toggle.text=="수동","AUTO shows the 수동 toggle")
	if _engaged(session):
		var auto_before:int=world.step_index
		_pump(ui,3.0)
		_check(world.step_index>auto_before or not _engaged(session),"AUTO advances without a release")
	# 7. Save/load: replay exact, mode defaults to HERO_TURN.
	var loaded=Session.new();var load_result:Dictionary=loaded.load_session_json(session.save_session_json())
	_check(bool(load_result.get("accepted",false)),"session reloads: %s"%str(load_result.get("reason","")))
	if bool(load_result.get("accepted",false)):
		_check(loaded.sim.snapshot()==session.sim.snapshot(),"replay is exact")
		var ui2=Sandbox.new();ui2.size=Vector2(390,800);ui2.initialize_for_headless_test(loaded,true)
		_check(ui2.battle_mode=="HERO_TURN","loaded session starts in HERO_TURN")
		ui2.free()
	_finish()

func _finish()->void:
	if failures.is_empty():print("PASS hero turn combat");quit(0)
	else:printerr("FAIL hero turn combat: %d failures"%failures.size());quit(1)
