extends SceneTree

## Contact rule (schema 24): seeing an enemy does not open a contact. An enemy
## that has noticed the party (ALERT/HUNTING) opens it; the party can open it
## first by striking (PARTY_AMBUSH + first_strike). Older saves keep the
## sight-based rule through legacy_contact_rule.

const Session=preload("res://playtest/party_playtest_session.gd")
const SimCommand=preload("res://sim/sim_command.gd")
var failures:Array[String]=[]

func _init()->void:call_deferred("run")
func _check(value:bool,message:String)->void:
	if not value:failures.append(message);printerr("FAIL ",message)

func _walk(session,goal:Vector2i,stop_at:Vector2i=Vector2i(-1,-1))->bool:
	var world=session.sim.world;var hero:int=int(world.party_encounter.protagonist_id)
	var path:Dictionary=session.find_exploration_path(hero,goal)
	if not bool(path.get("found",false)):return false
	for v in path.path.slice(1):
		if not bool(session.commit_exploration(SimCommand.move_to(hero,v)).get("accepted",false)):return false
		if world.entities[hero].position==stop_at:return true
		if str(world.party_encounter.safe_phase)!="GROUPED":return true
	return true

func run()->void:
	# Fixture: DUO dungeon, hero at (6,40); an unaware trio waits around (20,40).
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var world=session.sim.world;var state=world.party_encounter;var hero:int=int(state.protagonist_id)
	_check(not state.legacy_contact_rule,"new sessions use the awareness contact rule")
	# 1. Sight alone: walking to four cells from the trio, in plain view, keeps exploring.
	_check(_walk(session,Vector2i(19,40),Vector2i(16,40)) and world.entities[hero].position==Vector2i(16,40),"hero walks into view of the trio")
	var aware3=state.enemy_awareness(3)
	_check(str(state.safe_phase)=="GROUPED" and aware3!=null and str(aware3.awareness_state)=="SUSPICIOUS","seeing each other only makes the enemy suspicious (phase %s, enemy %s)"%[str(state.safe_phase),str(aware3.awareness_state) if aware3!=null else "none"])
	_check(world.world_state_error().is_empty(),"world stays valid: %s"%world.world_state_error())
	# 2. The enemy notices: suspicion keeps growing while it watches; contact follows.
	var noticed:=false
	for turn in range(20):
		if not bool(session.commit_exploration_direction(Vector2i.ZERO).get("accepted",false)):break
		if str(state.safe_phase)!="GROUPED":noticed=true;break
	_check(noticed,"an enemy that keeps watching the party eventually opens the contact")
	if noticed:
		_check(str(state.contact_kind) in ["DETECTED","ENEMY_AMBUSH"],"enemy-opened contact is DETECTED or ENEMY_AMBUSH (%s)"%str(state.contact_kind))
		_check(world.world_state_error().is_empty(),"awareness contact validates: %s"%world.world_state_error())
		var settled:Dictionary=session.settle_contact()
		_check(bool(settled.get("accepted",false)) and str(state.safe_phase)=="ENGAGED","settle_contact deploys at once: %s"%str(settled.get("reason","")))
		_check(world.world_state_error().is_empty(),"settled contact validates: %s"%world.world_state_error())
	# 3. First strike: from three cells away (party sight radius), while the trio is only suspicious, the
	# party opens the fight itself (a ranged skill or a bump on a busy enemy in play).
	var strike=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var sworld=strike.sim.world;var sstate=sworld.party_encounter;var shero:int=int(sstate.protagonist_id)
	_check(_walk(strike,Vector2i(19,40),Vector2i(17,40)) and sworld.entities[shero].position==Vector2i(17,40) and str(sstate.safe_phase)=="GROUPED","first-strike fixture stands three cells from a suspicious enemy, in party sight")
	var refused:Dictionary=strike.strike_enemy(3)
	_check(not bool(refused.get("accepted",false)) and str(refused.get("reason",""))=="strike_requires_adjacent","a distant enemy tap is refused, not walked to (%s)"%str(refused.get("reason","")))
	var opened:Dictionary=strike.first_strike_contact(3)
	_check(bool(opened.get("accepted",false)),"the party opens the contact by striking first: %s"%str(opened.get("reason","")))
	_check(str(sstate.safe_phase)=="CONTACT" and str(sstate.contact_kind)=="PARTY_AMBUSH","first strike is a PARTY_AMBUSH contact (phase %s kind %s)"%[str(sstate.safe_phase),str(sstate.contact_kind)])
	_check(sworld.world_state_error().is_empty(),"first strike validates: %s"%sworld.world_state_error())
	var contact_event=null
	for event in sworld.events:
		if event.type=="encounter.party_ambush":contact_event=event
	_check(contact_event!=null and bool(contact_event.data.get("first_strike",false)),"contact event carries first_strike")
	var deployed:Dictionary=strike.settle_contact()
	_check(bool(deployed.get("accepted",false)) and str(sstate.safe_phase)=="ENGAGED","first strike deploys at once: %s"%str(deployed.get("reason","")))
	var ordered:Dictionary=strike.issue_actor_command(shero,"ATTACK_TARGET",3)
	_check(bool(ordered.get("accepted",false)),"hero attack order on the struck enemy: %s"%str(ordered.get("reason","")))
	var hero_attacked:=false;var hero_acted:=0
	for step in range(40):
		var next:Dictionary=strike.individual_battle.next_event()
		if next.is_empty():break
		var events_before:int=sworld.events.size()
		var result:Dictionary=strike.individual_battle.commit()
		if not bool(result.get("accepted",false)):break
		for index in range(events_before,sworld.events.size()):
			var event=sworld.events[index]
			if int(event.actor_id)==shero and str(event.type).begins_with("action."):hero_acted+=1
			if str(event.type)=="action.melee_attack" and int(event.actor_id)==shero and int(event.target_id)==3:hero_attacked=true
		if hero_attacked or str(sstate.safe_phase)!="ENGAGED":break
	_check(hero_attacked,"the hero closes in and attacks the struck enemy (hero actions %d)"%hero_acted)
	_check(sworld.world_state_error().is_empty(),"post-strike combat validates: %s"%sworld.world_state_error())
	var saved:String=strike.save_session_json();var loaded=Session.new()
	var load_result:Dictionary=loaded.load_session_json(saved)
	_check(bool(load_result.get("accepted",false)),"first strike journal reloads: %s"%str(load_result.get("reason","")))
	if bool(load_result.get("accepted",false)):_check(loaded.sim.snapshot()==strike.sim.snapshot(),"first strike replays exactly")
	# 4. Legacy saves keep the sight rule.
	var legacy=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var decoded:Variant=JSON.parse_string(legacy.save_session_json())
	var party_wire:Dictionary=decoded["snapshot"]["party_encounter"] if decoded is Dictionary and decoded.get("snapshot",{}) is Dictionary and decoded["snapshot"].has("party_encounter") else {}
	_check(not party_wire.is_empty() and int(party_wire.get("schema_version",0))==24 and party_wire.get("legacy_contact_rule")==false,"fresh save writes schema 24 with legacy_contact_rule=false")
	if not party_wire.is_empty():
		party_wire["schema_version"]=23;party_wire.erase("legacy_contact_rule")
		var old_loaded=Session.new()
		var old_result:Dictionary=old_loaded.load_session_json(JSON.stringify(decoded))
		_check(bool(old_result.get("accepted",false)),"schema 23 save loads: %s"%str(old_result.get("reason","")))
		if bool(old_result.get("accepted",false)):
			var lstate=old_loaded.sim.world.party_encounter
			_check(lstate.legacy_contact_rule,"schema 23 save keeps the legacy contact rule")
			_walk(old_loaded,Vector2i(19,40),Vector2i(16,40))
			_check(str(lstate.safe_phase)!="GROUPED","legacy rule still opens contact on sight (phase %s)"%str(lstate.safe_phase))
			_check(old_loaded.sim.world.world_state_error().is_empty(),"legacy contact validates: %s"%old_loaded.sim.world.world_state_error())
	if failures.is_empty():print("PASS awareness contact");quit(0)
	else:printerr("FAIL awareness contact: %d failures"%failures.size());quit(1)
