extends SceneTree

const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Portrait=preload("res://playtest/compact_party_portrait.gd")
var failures:Array[String]=[]

func check(value:bool,label:String)->void:
	if not value:failures.append(label);printerr("FAIL ",label)

func _init()->void:call_deferred("run")

func run()->void:
	var session=Session.new(903,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var hero_id:=int(session.party_status().protagonist_id)
	var detail:Dictionary=session.inspect_party_member(hero_id)
	var body:Dictionary=detail.get("body_state",{})
	var authority=session.sim.world.body_states[hero_id]
	check([body.blood,body.blood_capacity,body.skin_toughness,
		body.soft_tissue_cushioning,body.bone_fracture_threshold,
		body.shock_threshold,body.consciousness_threshold]==[
		authority.current_blood,authority.body_scalars.blood_capacity,
		authority.body_scalars.skin_toughness,
		authority.body_scalars.soft_tissue_cushioning,
		authority.body_scalars.bone_fracture_threshold,
		authority.body_scalars.shock_threshold,
		authority.body_scalars.consciousness_threshold],
		"inspection exposes exact authoritative body scalars")
	var text:="\n".join(Sandbox.body_status_lines(body))
	check(not "혈액" in text,"retired blood resource is hidden")
	check(not "연부조직" in text,"soft tissue is presented as muscle")
	for label in ["피부 질김","근육","뼈 강도"]:
		check(str(label) in text,"body status includes %s"%str(label))
	var healthy:=body.duplicate(true)
	healthy.consciousness=1000;healthy.shock=0;healthy.wound_count=5
	healthy.penalties={"attack_milli":1000,"move_milli":1000,"recovery_milli":1000}
	healthy.parts=[{"part_id":"HEAD","condition":"FUNCTIONAL","injury_stage":"정상","integrity_milli":1000}]
	var lines:=Sandbox.body_status_lines(healthy)
	check(lines.size()==1 and lines[0].count(" / ")==2,"healthy body shows traits on one line only, even with historical wounds")
	healthy.parts.append({"part_id":"LEFT_ARM","condition":"FUNCTIONAL","injury_stage":"정상","integrity_milli":950})
	healthy.parts.append({"part_id":"RIGHT_LEG","condition":"FUNCTIONAL","injury_stage":"골절","integrity_milli":500})
	lines=Sandbox.body_status_lines(healthy)
	check(lines.size()==3 and lines[1]=="왼팔 가벼운 상처" and lines[2]=="오른다리 골절","show only injured parts, including mild tissue damage")
	check(not "머리" in "\n".join(lines) and not "정상" in "\n".join(lines),"normal parts hidden")
	healthy.parts[1].condition="SEVERED"
	check("왼팔 절단" in Sandbox.body_status_lines(healthy),"severed part stays visible")
	var portrait=Portrait.new();portrait.actor={"health":60,"max_health":120,
		"energy":3,"max_energy":12,"stress":800}
	var labels:=portrait.resource_labels(true)
	check(labels==["HP 60/120","MP 3/12","TNS 800"],
		"tension uses TNS while STR remains reserved for strength")
	portrait.free()
	print("BODY STATUS SCALARS: ",failures)
	quit(0 if failures.is_empty() else 1)
