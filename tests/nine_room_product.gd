extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
func _init():call_deferred("run")
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	if s.sim==null:printerr("NINE_PRODUCT initialization failed");quit(1);return
	print("NINE_PRODUCT ",s.room_status())
	var error:String=s.sim.world.world_state_error()
	if not s.room_enabled() or not error.is_empty():printerr("NINE_PRODUCT audit ",error);quit(1);return
	var saved:String=s.save_session_json();var restored=Session.new();var decoded:Dictionary=restored.load_session_json(saved)
	if not decoded.accepted:printerr("NINE_PRODUCT load ",decoded);quit(1);return
	if s.sim.snapshot()!=restored.sim.snapshot():printerr("NINE_PRODUCT restore mismatch");quit(1);return
	print("NINE_PRODUCT PASS");quit(0)
