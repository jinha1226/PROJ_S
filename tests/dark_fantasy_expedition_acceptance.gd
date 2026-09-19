extends SceneTree

const Session=preload("res://playtest/party_playtest_session.gd")
var failures:Array[String]=[]

func _init()->void:
	call_deferred("run")

func check(ok:bool,label:String)->void:
	if not ok:
		failures.append(label)
		printerr("FAIL ",label)

func run()->void:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var playable=Session.new(44,20260828,Session.DARK_FANTASY_SCENARIO_ID)
	check(playable.dark_expedition_status().get("active",false) \
		and playable.dark_expedition_status().members.size()==3,
		"dark scenario boots a three-member expedition state")
	var playable_loaded=Session.new()
	var playable_restore:Dictionary=playable_loaded.load_session_json(playable.save_session_json())
	check(playable_restore.get("accepted",false),"dark scenario bootstrap save/load replays")
	var started:Dictionary=session.start_dark_fantasy_expedition(17)
	check(started.get("accepted",false),"short expedition starts")
	var status:=session.dark_expedition_status()
	check(status.get("active",false) and status.room_index==0 and status.rescue_supplies==2,
		"start owns room and rescue supply state")
	var expedition_rules=preload("res://sim/dark_fantasy_expedition_rules.gd")
	var event_session=Session.new(45,20260829,Session.DUO_SCENARIO_ID)
	check(event_session.start_dark_fantasy_expedition(0).get("accepted",false),"event consumer fixture starts")
	check(expedition_rules.commit_event_batch(event_session.sim.world,[
		{"id":9001,"type":"combat.physical_damage","target_id":1,"magnitude":3},
		{"id":9002,"type":"entity.downed","target_id":2,"magnitude":0},
		{"id":9003,"type":"entity.died","target_id":2,"magnitude":0}]),
		"expedition event consumer accepts a batch")
	status=event_session.dark_expedition_status()
	check(status.members[0].stress==24 and status.members[1].stress==0,
		"damage and death stress use the expedition 0..100 scale once")
	check(status.members[1].injury_ids==["SPRAINED_ANKLE"],"dying assigns the first injury")
	check(expedition_rules.commit_event_batch(event_session.sim.world,[
		{"id":9001,"type":"combat.physical_damage","target_id":1,"magnitude":3}]),
		"duplicate expedition events are harmless")
	check(event_session.complete_dark_expedition_room(0).get("accepted",false),"camp fixture clears room one")
	check(event_session.enter_dark_expedition_camp().get("accepted",false),"camp fixture enters camp")
	check(event_session.dark_expedition_camp_action("CALM",1).get("accepted",false),"camp calm spends CP")
	check(event_session.dark_expedition_status().camp_cp==2 and event_session.dark_expedition_status().members[0].stress==4,
		"camp calm reduces stress without restoring CP")
	var heal_session=Session.new(46,20260830,Session.DUO_SCENARIO_ID)
	check(heal_session.start_dark_fantasy_expedition(0).get("accepted",false),
		"healing fixture starts")
	var heal_world=heal_session.sim.world
	var heal_target=heal_world.entities[heal_world.party_encounter.party_member_ids[0]]
	heal_target.health-=20
	var heal_id:=int(heal_target.id)
	check(heal_session.complete_dark_expedition_room(0).get("accepted",false),"healing fixture clears room")
	check(heal_session.enter_dark_expedition_camp().get("accepted",false),"healing fixture enters camp")
	check(heal_session.dark_expedition_camp_action("HEAL",heal_id).get("accepted",false),
		"camp heal records canonical recovery")
	check(heal_target.health==heal_target.max_health,
		"camp heal restores the bounded quarter-health amount")
	check(session.complete_dark_expedition_room(0).get("accepted",false),"first room completes")
	check(session.enter_dark_expedition_camp().get("accepted",false),"camp opens after first room")
	check(session.dark_expedition_status().get("camp_cp",-1)==4,"camp starts with four CP")
	check(session.leave_dark_expedition_camp().get("accepted",false),"camp is single opportunity")
	check(not session.enter_dark_expedition_camp().get("accepted",false),"camp cannot be reopened")
	check(session.complete_dark_expedition_room(1).get("accepted",false),"second room completes")
	check(session.complete_dark_expedition_room(2).get("accepted",false),"third room completes")
	check(session.settle_dark_expedition("COMPLETE").get("accepted",false),"complete settles once")
	check(session.dark_expedition_status().preserved_gold==17,"complete preserves all gold")
	check(not session.settle_dark_expedition("SAFE_RETREAT").get("accepted",false),"settlement cannot duplicate")
	var encoded:=session.save_session_json()
	var loaded=Session.new()
	var restored:Dictionary=loaded.load_session_json(encoded)
	check(restored.get("accepted",false),"short expedition save/load replays: "+str(restored))
	if restored.get("accepted",false):
		check(loaded.dark_expedition_status()==session.dark_expedition_status(),"short expedition state survives replay")
	print("DARK_FANTASY_EXPEDITION ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
