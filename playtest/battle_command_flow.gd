extends RefCounted

## Presentation policy only: pause/zoom/alarms never mutate canonical combat.
const COMBAT_VIEW_CELLS:=11
const DANGER_PERCENT:=25
const REARM_PERCENT:=35
const Portrait=preload("res://playtest/compact_party_portrait.gd")
var world_id:=-1
var in_battle:=false
var awaiting_start:=false
var exploration_zoom:=19
var latched:Dictionary={}
var danger_ids:Array[int]=[]

func sync(host)->bool:
	if host.session==null or host.session.sim==null:return false
	var world=host.session.sim.world
	var changed:=false
	if world_id!=world.get_instance_id():
		if in_battle:host._product_zoom_cell_count=exploration_zoom
		world_id=world.get_instance_id();in_battle=false;latched.clear();danger_ids.clear()
	var engaged:bool=host.session.is_duo_autobattle() and world.party_encounter.safe_phase=="ENGAGED"
	if engaged and not in_battle:
		exploration_zoom=host._product_zoom_cell_count
		host._product_zoom_cell_count=mini(exploration_zoom,COMBAT_VIEW_CELLS)
		host.autonomous_battle_clock.paused=true
		in_battle=true;awaiting_start=true;latched.clear();changed=true
	elif not engaged and in_battle:
		host._product_zoom_cell_count=exploration_zoom
		in_battle=false;awaiting_start=false;latched.clear();danger_ids.clear();changed=true
	if engaged and check_danger(host):changed=true
	paint(host)
	return changed

func check_danger(host)->bool:
	var world=host.session.sim.world
	if world.party_encounter.safe_phase!="ENGAGED":return false
	var newly_low:=false
	danger_ids.clear()
	for id in world.party_encounter.active_party_member_ids:
		var entity=world.entities[id]
		if world.combatant_states[id].life_state=="DEAD":continue
		var percent:=float(entity.health)*100.0/maxi(1,entity.max_health)
		if percent>REARM_PERCENT:latched.erase(id)
		if percent<=DANGER_PERCENT:
			danger_ids.append(id)
			if not latched.has(id):newly_low=true;latched[id]=true
	if newly_low:host.autonomous_battle_clock.paused=true
	return newly_low

func resume()->void:awaiting_start=false

func paint(host)->void:
	if host.grid==null:return
	var pause_button:=host.cards.find_child("PortraitBattlePause",true,false) as Button
	if pause_button!=null:
		pause_button.text=("시작" if awaiting_start else "재개") if host.autonomous_battle_clock.paused else "지휘"
	var notice:=""
	if in_battle and host.autonomous_battle_clock.paused:
		if not danger_ids.is_empty():
			var names:Array[String]=[]
			for id in danger_ids:names.append(host._actor_display_name(id))
			notice="위험: %s · 일시정지"%", ".join(names)
		else:notice="전투 준비 · 끌어서 배치 후 시작" if awaiting_start else "지휘 중 · 지정 후 재개"
	host.session.individual_battle._bind()
	var goals:Dictionary=host.session.individual_battle.movements if in_battle else {}
	if host.grid.battle_notice!=notice or host.grid.danger_actor_ids!=danger_ids \
			or host.grid.battle_move_goals!=goals:
		host.grid.battle_notice=notice;host.grid.danger_actor_ids=danger_ids.duplicate()
		host.grid.battle_move_goals=goals.duplicate();host.grid.queue_redraw()
	for id in host.session.sim.world.party_encounter.active_party_member_ids:
		var portrait=host.cards.find_child("MemberCard%d"%id,true,false)
		if portrait is Portrait and portrait.danger!=(id in danger_ids):
			portrait.danger=id in danger_ids;portrait.queue_redraw()
