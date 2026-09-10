extends SceneTree

## Single-screen combat: no turn clock, no mode toggle. Every tap is one hero
## action; companions and enemies act on their own between taps. Cells move,
## adjacent enemies are attacked, skills paint reachable cells red, [퇴각]
## keeps the party moving away without further taps.

const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const SimCommand=preload("res://sim/sim_command.gd")
const PartyCommand=preload("res://sim/party_exception_command.gd")
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
	# Awareness rule: an enemy that noticed the party opens the contact on its
	# next step. Give it up to three turns after the walk.
	for wait_turn in range(3):
		if str(session.party_status().get("safe_phase",""))!="GROUPED":break
		if not bool(session.commit_exploration(SimCommand.wait(hero_id)).get("accepted",false)):break
	if str(session.party_status().get("safe_phase",""))!="CONTACT":return null
	var settled:Dictionary=session.settle_contact()
	return session if bool(settled.get("accepted",false)) and str(session.party_status().get("safe_phase",""))=="ENGAGED" else null

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

func _nearest_enemy(session,hero:int)->Array:
	var world=session.sim.world;var best:=-1;var best_d:=9999
	for id in session.party_status().get("visible_enemy_ids",[]):
		if not world.is_autonomous_target(int(id)):continue
		var p:Vector2i=world.entities[int(id)].position;var h:Vector2i=world.entities[hero].position
		var d:int=maxi(absi(p.x-h.x),absi(p.y-h.y))
		if d<best_d:best_d=d;best=int(id)
	return [best,best_d]

func run()->void:
	var session=_engaged_duo()
	_check(session!=null,"fixture is ENGAGED through settle_contact")
	if session==null:_finish();return
	var world=session.sim.world;var hero:int=int(world.party_encounter.protagonist_id)
	var ui=Sandbox.new();ui.size=Vector2(390,800);ui.initialize_for_headless_test(session,true)
	ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);ui.size=Vector2(390,800);root.add_child(ui);ui.set_process(false)
	for i in range(3):await process_frame
	# 1. One screen: no clock, no toggle; dock reads 공격/대기/퇴각; skill row above portraits; enemy strip over the map.
	_check(ui.find_child("BattleTimelineBar",true,false)==null and ui.find_child("PortraitBattleMode",true,false)==null \
		and ui.find_child("PortraitBattlePause",true,false)==null,"no turn clock or mode controls in combat")
	_check(ui.product_attack_button!=null and ui.product_attack_button.text=="[공격]" \
		and ui.product_wait_guard_button.text=="[대기]" and ui.product_rest_button.text=="[휴식]" \
		and ui.product_auto_button.text=="[탐험]" and ui.product_tactics_button!=null \
		and not ui.product_tactics_button.disabled and ui.product_bag_button!=null,
		"the dock keeps 공격 / 대기 / 휴식 / 탐험 / 전술 / 가방 during a fight")
	_check(ui.hero_skill_row.visible and ui.hero_skill_row.get_index()==ui.cards.get_index()-1 \
		and ui.event_surface.get_index()==ui.hero_skill_row.get_index()-1,
		"feed, then hero skills, then portraits")
	_check(ui.battle_enemy_strip.get_parent()==ui.grid and ui.battle_enemy_strip.visible,"enemy portraits float over the map")
	_check(ui.event_surface.get_node("EventSurfaceInset").visible,"the event feed stays visible during combat")
	# 2. Waiting: nothing happens until the hero acts.
	_pump(ui,3.0)
	_check(ui.hero_turn_waiting(),"combat waits for the hero's decision")
	var waiting_events:int=world.events.size()
	_pump(ui,2.0)
	_check(world.events.size()==waiting_events,"nothing happens while waiting")
	# 3. Own-cell tap = one action, then waiting again.
	ui.grid.world_cell_pressed.emit(world.entities[hero].position);await process_frame
	_pump(ui,3.0)
	_check(_hero_actions_since(world,hero,waiting_events)==1,"own-cell tap is exactly one hero action (got %d)"%_hero_actions_since(world,hero,waiting_events))
	_check(ui.hero_turn_waiting() or not _engaged(session),"waits again at the next hero turn")
	# 4. [대기] is one action too.
	if _engaged(session):
		var before:int=world.events.size()
		ui._on_product_wait_guard();await process_frame;_pump(ui,3.0)
		_check(_hero_actions_since(world,hero,before)==1,"[대기] is exactly one hero action")
	# 5. Enemy tap: distant enemy is refused with a hint, adjacent enemy is attacked.
	if _engaged(session):
		_pump(ui,3.0)
		var nearest:Array=_nearest_enemy(session,hero)
		if nearest[0]>0 and int(nearest[1])>1:
			var before_tap:int=world.events.size()
			ui.grid.actor_pressed.emit(int(nearest[0]));await process_frame
			_check(ui.hero_turn_waiting() and "인접" in str(ui.notice_text)+str(ui.action_feedback_text)+str(ui.event_label.text),
				"a distant enemy tap explains adjacency instead of walking")
			_pump(ui,1.0)
			_check(world.events.size()==before_tap,"the refused tap costs nothing")
		# Approach with [공격] (one step per tap) until adjacent, then the tap attacks.
		var attacked:=false
		for round in range(12):
			if not _engaged(session) or not ui.hero_turn_waiting():_pump(ui,2.0)
			if not _engaged(session):break
			nearest=_nearest_enemy(session,hero)
			if nearest[0]<=0:break
			var before_round:int=world.events.size()
			if int(nearest[1])<=1:
				ui.grid.actor_pressed.emit(int(nearest[0]));await process_frame;_pump(ui,3.0)
				for index in range(before_round,world.events.size()):
					var event=world.events[index]
					if str(event.type)=="action.melee_attack" and int(event.actor_id)==hero:attacked=true
				if attacked:break
			else:
				ui._on_product_attack_any();await process_frame;_pump(ui,3.0)
				_check(_hero_actions_since(world,hero,before_round)<=2,"[공격] approach is a short step, not a chase (got %d)"%_hero_actions_since(world,hero,before_round))
		_check(attacked or not _engaged(session),"an adjacent enemy tap attacks it")
	# 6. Skill tap paints red cells; empty cell tap cancels.
	if _engaged(session):
		_pump(ui,3.0)
		var strike_button:=ui.hero_skill_row.find_child("ActorSkill_%d_STRIKE"%hero,true,false) as Button
		_check(strike_button!=null,"hero STRIKE button is in the skill row")
		if strike_button!=null and not strike_button.disabled:
			strike_button.pressed.emit();await process_frame
			_check(not ui._battle_target_mode.is_empty() and not ui.grid.skill_reach_cells().is_empty(),
				"skill tap enters targeting and paints reachable cells")
			var away:Vector2i=world.entities[hero].position+Vector2i(3,3)
			ui.grid.world_cell_pressed.emit(away);await process_frame
			_check(ui._battle_target_mode.is_empty() and ui.grid.skill_reach_cells().is_empty(),"empty cell tap cancels targeting and clears the cells")
	# 7. [퇴각]: the party keeps moving away without further taps.
	if _engaged(session):
		_pump(ui,3.0)
		var before_retreat:int=world.events.size()
		ui._on_product_tactic_selected(1);await process_frame
		_check(ui._retreat_active and str(PartyCommand.effective(world,world.party_encounter).get("command_id",""))=="RETREAT","전술 → 후퇴 issues the party RETREAT directive")
		_pump(ui,6.0)
		_check(_hero_actions_since(world,hero,before_retreat)>=2 or not _engaged(session),"retreat keeps the hero acting without taps (got %d)"%_hero_actions_since(world,hero,before_retreat))
		ui.grid.world_cell_pressed.emit(world.entities[hero].position);await process_frame
		_check(not ui._retreat_active,"any tap ends the retreat")
	# 8. Save/load replays exactly.
	var loaded=Session.new();var load_result:Dictionary=loaded.load_session_json(session.save_session_json())
	_check(bool(load_result.get("accepted",false)),"session reloads: %s"%str(load_result.get("reason","")))
	if bool(load_result.get("accepted",false)):_check(loaded.sim.snapshot()==session.sim.snapshot(),"replay is exact")
	_finish()

func _finish()->void:
	if failures.is_empty():print("PASS single screen combat");quit(0)
	else:printerr("FAIL single screen combat: %d failures"%failures.size());quit(1)
