class_name DungeonPopulationActionDefinition
extends RefCounted

const CATEGORIES:=["CONTEXT","HEXACO","RELATION","STATE"]
const OPERATORS:=["EQ","GT","GTE","LT","LTE"]
const ATOMIC_VERBS:=["MELEE","MOVE","USE_ITEM","WAIT"]
const INPUT_IDS:={
	"HEXACO":["A","C","E","H","O","X"],
	"STATE":["armed","dot","dot_danger","health","hp_crisis","hp_ratio","injury","power",
		"power_disadvantage","power_gap","recent_interrupt","supplies","survival_crisis",
		"treatment_need"],
	"RELATION":["affinity","fear_pressure","hostility","memory_modifier","neutrality","shared_threat",
		"species_prior"],
	"CONTEXT":["approach_pressure","distance","escape_reached","escape_space","other_alive",
		"opportunity","threat","uncertainty"]}

var action_id:="HOLD"
var atomic_verb:="WAIT"
var target_role:="NONE"
var movement_direction:="NONE"
var base_score:int=0
var legal_terms:Array[Dictionary]=[]
var score_terms:Array[Dictionary]=[]
var commitment_turns:int=1
var retention_bonus:int=0
var switch_margin:int=0
var complete_after_turns:int=1
var goal_terms:Array[Dictionary]=[]

func _init(p_action_id:String="HOLD",p_atomic_verb:String="WAIT",p_target_role:String="NONE",
		p_movement_direction:String="NONE",p_base_score:int=0,p_legal_terms:Array=[],
		p_score_terms:Array=[],p_commitment_turns:int=1,p_retention_bonus:int=0,
		p_switch_margin:int=0,p_complete_after_turns:int=1,p_goal_terms:Array=[])->void:
	action_id=p_action_id;atomic_verb=p_atomic_verb;target_role=p_target_role
	movement_direction=p_movement_direction;base_score=p_base_score
	commitment_turns=p_commitment_turns;retention_bonus=p_retention_bonus
	switch_margin=p_switch_margin;complete_after_turns=p_complete_after_turns
	for row in p_legal_terms:legal_terms.append(row.duplicate(true))
	for row in p_score_terms:score_terms.append(row.duplicate(true))
	for row in p_goal_terms:goal_terms.append(row.duplicate(true))

func to_dict()->Dictionary:
	return {"action_id":action_id,"atomic_verb":atomic_verb,"target_role":target_role,
		"movement_direction":movement_direction,"base_score":base_score,
		"legal_terms":legal_terms.duplicate(true),"score_terms":score_terms.duplicate(true),
		"commitment_turns":commitment_turns,"retention_bonus":retention_bonus,
		"switch_margin":switch_margin,"complete_after_turns":complete_after_turns,
		"goal_terms":goal_terms.duplicate(true)}

func detached_copy():
	return load("res://sim/dungeon_population/dungeon_action_definition.gd").new(
		action_id,atomic_verb,target_role,movement_direction,base_score,legal_terms,score_terms,
		commitment_turns,retention_bonus,switch_margin,complete_after_turns,goal_terms)

func validation_error()->String:
	if action_id.is_empty() or atomic_verb not in ATOMIC_VERBS or target_role not in ["NONE","OTHER","SELF"] \
			or movement_direction not in ["AWAY","NONE","TOWARD"] \
			or base_score<-1000 or base_score>1000 or score_terms.is_empty() \
			or commitment_turns<1 or commitment_turns>20 or retention_bonus<0 or retention_bonus>1000 \
			or switch_margin<0 or switch_margin>1000 \
			or complete_after_turns < -1 or complete_after_turns > 20:
		return "invalid_duel_action_definition"
	if atomic_verb=="MOVE" and (target_role!="OTHER" or movement_direction=="NONE"):
		return "duel_move_requires_other_and_direction"
	if atomic_verb=="MELEE" and target_role!="OTHER":return "duel_melee_requires_other"
	if atomic_verb=="USE_ITEM" and target_role!="SELF":return "duel_item_requires_self"
	if atomic_verb=="WAIT" and (target_role!="NONE" or movement_direction!="NONE"):
		return "duel_wait_requires_no_target"
	for row in legal_terms:
		var keys:Array=row.keys();keys.sort()
		if keys != ["category","input_id","operator","rejection_reason","value"] \
				or row.category not in CATEGORIES or row.operator not in OPERATORS \
				or str(row.input_id) not in INPUT_IDS.get(row.category,[]) or str(row.rejection_reason).is_empty() \
				or not _number(row.value):return "invalid_duel_legal_term"
	for row in score_terms:
		var keys:Array=row.keys();keys.sort()
		if keys != ["category","input_id","weight_milli"] or row.category not in CATEGORIES \
				or str(row.input_id) not in INPUT_IDS.get(row.category,[]) or not _integer(row.weight_milli) \
				or absi(int(row.weight_milli))>2000:return "invalid_duel_score_term"
	for row in goal_terms:
		var keys:Array=row.keys();keys.sort()
		if keys != ["category","input_id","operator","value"] or row.category not in CATEGORIES \
				or row.operator not in OPERATORS or str(row.input_id) not in INPUT_IDS.get(row.category,[]) \
				or not _number(row.value):return "invalid_duel_goal_term"
	return ""

static func _number(value:Variant)->bool:return value is int or value is float
static func _integer(value:Variant)->bool:return value is int or (value is float and value==floor(value))
