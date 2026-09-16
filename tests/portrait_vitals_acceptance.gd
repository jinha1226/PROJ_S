extends SceneTree
const Portrait=preload("res://playtest/compact_party_portrait.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
var failures:Array[String]=[]
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func _init():run.call_deferred()
func run():
	var portrait=Portrait.new();portrait.compact_vitals=true
	portrait.actor={"health":30,"max_health":60,"energy":3,"max_energy":12,"progression":{"xp_current":25,"xp_required":100}}
	for width in [70,92,145,180,320]:
		portrait.size=Vector2(width,68)
		var meters=portrait.mobile_meter_specs()
		check(meters.size()==3,"three resource bars")
		for i in range(3):
			check(Rect2(Vector2.ZERO,portrait.size).encloses(meters[i].rect),"bar fits narrow portrait")
			check(is_equal_approx(meters[i].ratio,[0.5,0.25,0.25][i]),"resource ratio reflects actor")
			if i>0:check(meters[i-1].rect.end.y<meters[i].rect.position.y,"bars do not overlap")
	portrait.actor={"health":0,"max_health":0,"energy":0,"max_energy":0}
	for meter in portrait.mobile_meter_specs():check(meter.ratio==0,"empty resources stay empty")
	portrait.free()
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var before:Dictionary=session.sim.snapshot()
	for row in session.party_cards():
		check(row.progression==session.member_progression(row.entity_id),"each portrait uses its own progression")
	check(before==session.sim.snapshot(),"portrait projection cannot mutate world")
	print("PORTRAIT VITALS: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
