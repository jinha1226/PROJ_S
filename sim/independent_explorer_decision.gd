extends RefCounted
## Pure policy; world changes belong to IndependentExplorerSystem authorities.
const Registry=preload("res://sim/decision_ruleset_registry.gd")
const Appraisal=preload("res://sim/party_companion_appraisal.gd")
const RULESET_ID:="independent-explorer-utility-v1"
const ACTIONS:=["RETURN","FIGHT","REST","EXPLORE"]
const COMMIT_TIME:=300
const SWITCH_MARGIN:=80
const REASONS:={
	"supplies_missing":"식량이 떨어져 귀환 중", "low_health":"부상이 심해 귀환 중",
	"return_committed":"정한 귀환 경로를 따라 이동 중", "rest_committed":"안전한 곳에서 회복 중",
	"weapon_unavailable":"싸울 수 없는 장비·신체 상태라 후퇴 중",
	"danger":"위험을 피해 귀환 중", "enemy":"눈앞의 적과 교전 중",
	"fatigue":"피로를 풀기 위해 휴식 중", "injury":"상처와 긴장을 추스르는 중",
	"curiosity":"새로운 장소를 찾아 탐색 중", "keep_goal":"정한 목표를 계속 수행 중",
	"explore":"주변을 탐색 중"}
static var _definitions:Dictionary={}

static func _ensure()->void:
	if not _definitions.is_empty():return
	var specs:={
		"EXPLORE":[350,{"openness":200,"health":150,"fatigue":-250,"danger":-500,"stress":-200,"fear":-200}],
		"FIGHT":[150,{"boldness":350,"health":250,"danger":200,"anger":150,"grievance":100,
			"caution":-150,"fear":-300,"hp_loss":-300,"stress":-150}],
		"RETURN":[50,{"caution":150,"emotionality":150,"hp_loss":450,"danger":250,
			"stress":250,"fear":250,"fatigue":100,"boldness":-50}],
		"REST":[50,{"recovery_need":600,"fatigue":650,"caution":100,"stress":200,"fear":150}]}
	for action in ACTIONS:
		var def=Registry.ActionDef.new(action,["NORMAL"],ACTIONS.find(action),int(specs[action][0]),
			COMMIT_TIME,0,SWITCH_MARGIN,"independent-observation","existing-authority")
		for input in specs[action][1]:
			def.considerations.append(Registry.ConsiderationDef.new(action+"."+input,input,
				"linear_up",int(specs[action][1][input])))
		_definitions[action]=def

static func decide(profile,context:Dictionary,previous:Dictionary={},now:int=0)->Dictionary:
	_ensure()
	var health:=clampi(int(context.get("health_ratio",100)),0,100)
	var distance:=maxi(0,int(context.get("enemy_distance",999)))
	var caution:=Appraisal._facet(profile,"C");var emotion:=Appraisal._facet(profile,"E")
	var inputs:={"health":health*10,"hp_loss":(100-health)*10,
		"recovery_need":clampi((90-health)*40,0,1000),
		"fatigue":clampi(int(context.get("fatigue",0))*250,0,1000),
		"danger":clampi(1000-(distance-1)*200,0,1000),
		"caution":caution,"emotionality":emotion,"boldness":1000-emotion,
		"openness":Appraisal._facet(profile,"O"),"stress":int(context.get("stress",0)),
		"fear":int(context.get("fear",0)),"anger":int(context.get("anger",0)),
		"grievance":int(context.get("grievance",0))}
	var legal:={"RETURN":true,"EXPLORE":distance>1,
		"FIGHT":distance<=4 and bool(context.get("can_attack",true)),
		"REST":distance>5 and (health<100 or int(inputs.fatigue)>0 or int(inputs.stress)>0)}
	var candidates:Array=[];var best:Dictionary={};var current:Dictionary={}
	var prior:=str(previous.get("decision_mode",previous.get("state","")))
	for action in ACTIONS:
		var scored:=Registry.evaluate(_definitions[action],inputs)
		var candidate:={"action":action,"legal":bool(legal[action]),"score":int(scored.score)}
		candidates.append(candidate)
		if not candidate.legal:continue
		if best.is_empty() or int(candidate.score)>int(best.score):best=candidate
		if action==prior:current=candidate
	var selected:=str(best.action);var reason:=""
	# Survival/service commitments preempt utility and hysteresis immediately.
	if int(context.get("supplies",0))<=0:selected="RETURN";reason="supplies_missing"
	elif health<25+int((caution+emotion)/60):selected="RETURN";reason="low_health"
	elif str(previous.get("state",""))=="RETURN":selected="RETURN";reason="return_committed"
	elif distance<=4 and not bool(context.get("can_attack",true)):
		selected="RETURN";reason="weapon_unavailable"
	elif prior=="REST" and int(previous.get("rest_until",0))>now and bool(legal.REST):
		selected="REST";reason="rest_committed"
	elif not current.is_empty() and not (distance<=4 and prior in ["EXPLORE","REST"]) \
			and (now<int(previous.get("decision_until",0)) \
			or int(best.score)<int(current.score)+SWITCH_MARGIN):
		selected=prior
		if selected!=str(best.action):reason="keep_goal"
	if reason.is_empty():
		match selected:
			"RETURN":reason="danger"
			"FIGHT":reason="enemy"
			"REST":reason="fatigue" if int(inputs.fatigue)>=500 else "injury"
			_:reason="curiosity" if int(inputs.openness)>=650 else "explore"
	return {"ruleset_id":RULESET_ID,"mode":selected,"reason":reason,"label":REASONS[reason],
		"decision_until":int(previous.get("decision_until",now)) \
			if selected==prior and previous.has("decision_mode") else now+COMMIT_TIME,
		"candidates":candidates}
