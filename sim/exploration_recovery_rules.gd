class_name ExplorationRecoveryRules
extends RefCounted

# Conservative recovery: safety must be maintained, so it removes neither
# attrition nor the value of a healing potion.
const RULESET_ID := "safe-exploration-recovery-v1"
const SAFE_TURNS_BEFORE_FIRST_HEAL := 5
const SAFE_TURNS_BETWEEN_HEALS := 3
const HEAL_PER_PULSE := 1
const RECENT_DAMAGE_STEP_BLOCK := 2
const THREAT_AWARENESS_STATES := ["SUSPICIOUS", "ALERT", "HUNTING", "SEARCHING"]


static func is_safe_to_recover(world, state, hero, hero_combatant,
		environment_risk: int = 0) -> bool:
	if world==null or state==null or hero==null or hero_combatant==null:return false
	if str(hero_combatant.life_state)!="ACTIVE" or int(hero.health)>=int(hero.max_health):return false
	if str(state.safe_phase) not in ["GROUPED","GROUPED_COMPLETE"]:return false
	if not hero_combatant.status_rows.is_empty():return false
	if int(state.last_protagonist_damage_step)>=0 and int(world.step_index) \
			- int(state.last_protagonist_damage_step)<=RECENT_DAMAGE_STEP_BLOCK:return false
	# Reuse the affinity-adjusted exposure evaluator supplied by the session:
	# water does not block recovery for a water-safe species unless it is actually
	# harmful in that entity's current element/risk calculation.
	if environment_risk>0:return false
	for enemy_id in state.enemy_ids:
		var enemy_combatant=world.combatant_states.get(enemy_id)
		if enemy_combatant==null or str(enemy_combatant.life_state)!="ACTIVE":continue
		var awareness=state.enemy_awareness(enemy_id)
		if awareness!=null and str(awareness.awareness_state) in THREAT_AWARENESS_STATES:return false
	return true


static func heal_due(safe_turn_count: int) -> bool:
	if safe_turn_count<SAFE_TURNS_BEFORE_FIRST_HEAL:return false
	return (safe_turn_count-SAFE_TURNS_BEFORE_FIRST_HEAL)%SAFE_TURNS_BETWEEN_HEALS==0
