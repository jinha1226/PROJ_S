extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Maps=preload("res://playtest/party_visual_test_map.gd")
func _init()->void:
	var failures:int=0
	for legacy in [false,true]:
		var source=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
		var layout:Dictionary=Maps.authored_campaign_dungeon(44) if legacy else Maps.product_dungeon(44)
		if not source.reset_party(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID,layout,false):printerr("reset failed");failures+=1;continue
		var loaded=Session.new(1,2,Session.SOLO_FIXTURE_SCENARIO_ID)
		var result:Dictionary=loaded.load_session_json(source.save_session_json())
		if not result.accepted or loaded.sim.snapshot()!=source.sim.snapshot():printerr("save/load failed legacy=",legacy," ",result.get("reason",""));failures+=1
		else:print("save/load legacy=",legacy," preserved ",loaded.sim.world.width,"x",loaded.sim.world.height)
	print("Compact campaign save: %d failures"%failures);quit(0 if failures==0 else 1)
