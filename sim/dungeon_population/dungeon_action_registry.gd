class_name DungeonDuelActionRegistry
extends RefCounted

const DefinitionScript=preload("res://sim/dungeon_population/dungeon_action_definition.gd")
const HexacoScript=preload("res://sim/dungeon_population/hexaco_profile.gd")

var _definitions:Dictionary={}

func _init()->void:
	register_definition(DefinitionScript.new("APPROACH","MOVE","OTHER","TOWARD",80,[
		_legal("CONTEXT","distance","GT",1,"이미 공격 가능한 거리다.")],[
		_score("HEXACO","X",180),_score("HEXACO","O",120),
		_score("RELATION","species_prior",1500),_score("RELATION","memory_modifier",1500),
		_score("RELATION","affinity",60),_score("RELATION","hostility",220),
		_score("CONTEXT","approach_pressure",180),_score("CONTEXT","threat",60),
		_score("CONTEXT","opportunity",160)],
		2,120,80,-1,[_goal("CONTEXT","distance","LTE",1)]))
	register_definition(DefinitionScript.new("ENGAGE","MELEE","OTHER","NONE",90,[
		_legal("CONTEXT","distance","LTE",1,"공격 거리가 아니다."),
		_legal("STATE","armed","EQ",1000,"무기가 없다."),
		_legal("CONTEXT","other_alive","EQ",1000,"상대가 이미 쓰러졌다.")],[
		_score("HEXACO","X",180),_score("HEXACO","A",-240),_score("HEXACO","E",-80),
		_score("STATE","health",140),_score("STATE","power",120),
		_score("STATE","survival_crisis",-450),
		_score("RELATION","species_prior",-1800),_score("RELATION","memory_modifier",-1800),
		_score("RELATION","hostility",250),_score("CONTEXT","threat",100)],
		2,100,100,-1,[]))
	register_definition(DefinitionScript.new("FLEE","MOVE","OTHER","AWAY",85,[
		_legal("CONTEXT","escape_space","GTE",1000,"도망칠 공간이 없다."),
		_legal("CONTEXT","other_alive","EQ",1000,"도망칠 상대가 없다.")],[
		_score("HEXACO","E",260),_score("HEXACO","X",-130),
		_score("STATE","injury",240),_score("STATE","power_gap",220),
		_score("STATE","survival_crisis",700),
		_score("RELATION","species_prior",-1000),_score("RELATION","memory_modifier",-1000),
		_score("RELATION","fear_pressure",120),_score("CONTEXT","threat",180)],
		2,140,100,-1,[_goal("CONTEXT","escape_reached","GTE",1000)]))
	register_definition(DefinitionScript.new("HOLD","WAIT","NONE","NONE",70,[],[
		_score("HEXACO","C",140),_score("HEXACO","X",-50),
		_score("CONTEXT","uncertainty",160),_score("RELATION","neutrality",80)],
		1,80,60,1,[]))
	register_definition(DefinitionScript.new("SELF_TREAT","USE_ITEM","SELF","NONE",110,[
		_legal("STATE","supplies","GTE",1000,"치료 도구가 없다."),
		_legal("STATE","treatment_need","GTE",250,"치료할 필요가 없다.")],[
		_score("HEXACO","C",220),_score("HEXACO","E",70),
		_score("STATE","supplies",160),_score("STATE","treatment_need",480),_score("STATE","dot",300),
		_score("STATE","survival_crisis",300),
		_score("CONTEXT","threat",-100)],1,90,60,1,[]))

func register_definition(definition)->Dictionary:
	if definition==null or not definition.has_method("validation_error"):
		return {"accepted":false,"reason":"invalid_duel_action_definition"}
	var error:String=definition.validation_error()
	if not error.is_empty():return {"accepted":false,"reason":error}
	if _definitions.has(definition.action_id):return {"accepted":false,"reason":"duplicate_duel_action_id"}
	_definitions[definition.action_id]=definition.detached_copy()
	return {"accepted":true,"reason":"ok"}

func action_ids()->Array:
	var ids:Array=_definitions.keys();ids.sort();return ids

func definition(action_id:String)->Dictionary:
	var row=_definitions.get(action_id)
	return {} if row==null else row.to_dict().duplicate(true)

func validation_error()->String:
	for action_id in action_ids():
		var error:String=_definitions[action_id].validation_error()
		if not error.is_empty():return error
	return "" if _definitions.has("HOLD") else "duel_hold_definition_missing"

func canonical_manifest()->Array:
	var rows:Array=[]
	for action_id in action_ids():
		var definition=_definitions[action_id];var legal_rows:Array=[];var score_rows:Array=[];var goal_rows:Array=[]
		for term in definition.legal_terms:
			legal_rows.append({"category":str(term.category),"input_id":str(term.input_id),
				"operator":str(term.operator),"rejection_reason":str(term.rejection_reason),
				"value":str(int(term.value))})
		for term in definition.score_terms:
			score_rows.append({"category":str(term.category),"input_id":str(term.input_id),
				"weight_milli":str(int(term.weight_milli))})
		for term in definition.goal_terms:
			goal_rows.append({"category":str(term.category),"input_id":str(term.input_id),
				"operator":str(term.operator),"value":str(int(term.value))})
		rows.append({"action_id":str(action_id),"atomic_verb":str(definition.atomic_verb),
			"target_role":str(definition.target_role),
			"movement_direction":str(definition.movement_direction),
			"base_score":str(int(definition.base_score)),"legal_terms":legal_rows,
			"score_terms":score_rows,"commitment_turns":str(int(definition.commitment_turns)),
			"retention_bonus":str(int(definition.retention_bonus)),
			"switch_margin":str(int(definition.switch_margin)),
			"complete_after_turns":str(int(definition.complete_after_turns)),
			"goal_terms":goal_rows})
	return rows.duplicate(true)

func ruleset_fingerprint()->String:
	return JSON.stringify(canonical_manifest()).sha256_text()

func evaluate_actor(actor,other,inputs:Dictionary,seed:int,decision_episode_id:int)->Dictionary:
	var candidate_rows:Array=[];var selected_id:="";var selected_total:=-2147483648
	for action_id in action_ids():
		var definition=_definitions[action_id];var legal:=true;var rejection:=""
		for term in definition.legal_terms:
			var actual:int=int(inputs.get(term.category,{}).get(term.input_id,0))
			if not _compare(actual,str(term.operator),int(term.value)):
				legal=false;rejection=str(term.rejection_reason);break
		var buckets:={"HEXACO":[],"STATE":[],"RELATION":[],"CONTEXT":[]}
		var total:int=int(definition.base_score)
		for term in definition.score_terms:
			var actual:int=int(inputs.get(term.category,{}).get(term.input_id,0))
			var contribution:int=int(actual*int(term.weight_milli)/1000)
			buckets[term.category].append({"input_id":str(term.input_id),"input_value":actual,
				"weight_milli":int(term.weight_milli),"contribution":contribution})
			total+=contribution
		var jitter:=HexacoScript.sample(seed,actor.entity_id,
			"duel/episode/"+str(decision_episode_id)+"/"+action_id,31)-15
		total+=jitter
		var row:={"action_id":action_id,"atomic_verb":definition.atomic_verb,
			"target_role":definition.target_role,"movement_direction":definition.movement_direction,
			"legal":legal,"rejection_reason":rejection,"base":definition.base_score,
			"hexaco_terms":buckets.HEXACO,"state_terms":buckets.STATE,
			"relation_terms":buckets.RELATION,"context_terms":buckets.CONTEXT,
			"jitter":jitter,"total":total,"selected":false}
		candidate_rows.append(row)
		if legal and (total>selected_total or (total==selected_total and (selected_id.is_empty() or action_id<selected_id))):
			selected_total=total;selected_id=action_id
	if selected_id.is_empty():selected_id="HOLD"
	for row in candidate_rows:row.selected=str(row.action_id)==selected_id
	return {"actor_id":str(actor.entity_id),"selected_action_id":selected_id,
		"selected_reason_ko":"합법 행동 중 효용 점수 %d점으로 가장 높았다."%selected_total,
		"candidates":candidate_rows}.duplicate(true)

func intent_policy(action_id:String)->Dictionary:
	var definition=_definitions.get(action_id)
	if definition==null:return {}
	return {"commitment_turns":int(definition.commitment_turns),
		"retention_bonus":int(definition.retention_bonus),
		"switch_margin":int(definition.switch_margin),
		"complete_after_turns":int(definition.complete_after_turns),
		"goal_terms":definition.goal_terms.duplicate(true)}

func goal_complete(action_id:String,inputs:Dictionary,elapsed_turns:int)->bool:
	var definition=_definitions.get(action_id)
	if definition==null:return true
	if int(definition.complete_after_turns)>=0 and elapsed_turns>=int(definition.complete_after_turns):
		return true
	if definition.goal_terms.is_empty():return false
	for term in definition.goal_terms:
		var actual:int=int(inputs.get(term.category,{}).get(term.input_id,0))
		if not _compare(actual,str(term.operator),int(term.value)):return false
	return true

func execution(action_id:String)->Dictionary:
	var definition=_definitions.get(action_id)
	if definition==null:return {}
	return {"action_id":action_id,"atomic_verb":definition.atomic_verb,
		"target_role":definition.target_role,"movement_direction":definition.movement_direction}

static func _compare(actual:int,operator:String,expected:int)->bool:
	match operator:
		"EQ":return actual==expected
		"GT":return actual>expected
		"GTE":return actual>=expected
		"LT":return actual<expected
		"LTE":return actual<=expected
	return false

static func _legal(category:String,input_id:String,operator:String,value:int,reason:String)->Dictionary:
	return {"category":category,"input_id":input_id,"operator":operator,"value":value,
		"rejection_reason":reason}

static func _score(category:String,input_id:String,weight_milli:int)->Dictionary:
	return {"category":category,"input_id":input_id,"weight_milli":weight_milli}

static func _goal(category:String,input_id:String,operator:String,value:int)->Dictionary:
	return {"category":category,"input_id":input_id,"operator":operator,"value":value}
