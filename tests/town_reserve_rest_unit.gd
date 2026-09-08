extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
func _init()->void:call_deferred("run")
func run()->void:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var start:Dictionary=session.town_life_command({"action":"START"})
	if not start.get("accepted",false):printerr(start);quit(1);return
	var world=session.sim.world;var party=world.party_encounter
	var id:int=party.party_member_ids[1]
	# Controlled valid initial strain, not an end-to-end save/replay fixture.
	world.emit_event("town.company_joined",party.protagonist_id,id,party.group_anchor,1,-1,
		{"entity_id":str(id),"expedition_index":int(party.expedition_cycle.expedition_index)})
	var member=party.member(id)
	member.stress=300;member.emotion_state.set_channel("FEAR",400,-1,-1,"SAFE_DECAY")
	member.emotion_state.updated_at=world.world_time
	var audit:String=world.world_state_error()
	if not audit.is_empty():printerr("INVALID FIXTURE ",audit);quit(1);return
	var gold:int=session.town_gold()
	var result:Dictionary=session.town_life_command({"action":"REST","entity_id":str(id)})
	print("RESERVE_REST ",result)
	var passed:bool=result.get("accepted",false) and session.town_gold()==gold-15 \
		and member.stress==0 and member.emotion_state.intensity("FEAR")==100 \
		and world.world_state_error().is_empty()
	print("TOWN_RESERVE_REST_UNIT ","PASS" if passed else "FAIL")
	quit(0 if passed else 1)
