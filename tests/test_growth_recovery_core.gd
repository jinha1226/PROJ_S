extends "res://tests/test_case.gd"

const Session=preload("res://playtest/party_playtest_session.gd")
const Command=preload("res://sim/sim_command.gd")
const Progression=preload("res://sim/protagonist_progression.gd")
const ProgressionRegistry=preload("res://sim/progression_registry.gd")
const RecoveryRules=preload("res://sim/exploration_recovery_rules.gd")
const PartyState=preload("res://sim/party_encounter_state.gd")
const Coordinator=preload("res://sim/systems/party_encounter_coordinator.gd")

class FakeWorld:
	var step_index:=0
	var combatant_states:Dictionary={}

class FakeState:
	var safe_phase:="GROUPED"
	var last_protagonist_damage_step:=-1
	var enemy_ids:Array=[]
	var enemy_awareness_rows:Dictionary={}
	func enemy_awareness(enemy_id:int):return enemy_awareness_rows.get(enemy_id)

class FakeHero:
	var health:=80
	var max_health:=120

class FakeCombatant:
	var life_state:="ACTIVE"
	var status_rows:Array=[]

class FakeRewardWorld:
	var _active_step_index:=7
	var step_index:=7
	var events:Array=[]
	var entities:Dictionary={101:FakeRewardEnemy.new(),102:FakeRewardEnemy.new()}
	var _next_id:=30
	func emit_event(event_type:String,actor_id:int,target_id:int,position:Vector2i,
			magnitude:int,cause_id:int,data:Dictionary={}):
		var event={"id":_next_id,"type":event_type,"actor_id":actor_id,
			"target_id":target_id,"position":position,"magnitude":magnitude,
			"cause_id":cause_id,"step_index":_active_step_index,"data":data}
		_next_id+=1;events.append(event);return event

class FakeRewardEnemy:
	var species_id:="goblin"


func test_new_run_focus_and_enemy_rewards_are_parallel_sorted_and_once()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var modes:Dictionary=session.sim.world.party_encounter.protagonist_progression.training_modes
	check_eq(modes,{"SWORD":"FOCUS","AXE":"OFF","BLUNT":"OFF","SPEAR":"OFF",
		"RANGED":"OFF","UNARMED":"OFF"},"starter short sword alone starts focused")
	var progression=Progression.new();progression.training_modes=modes.duplicate(true)
	check(progression.award_enemy_death(12) and progression.award_enemy_death(20),
		"two canonical source deaths each award once")
	check(not progression.award_enemy_death(20),"duplicate source death cannot reward twice")
	check_eq([progression.xp_total,progression.skill_training.SWORD,
		progression.skill_training.AXE,progression.processed_source_death_event_ids],
		[200,200,0,[12,20]],"XP and mastery are parallel 100-point ledgers in source-id order")
	check_eq(ProgressionRegistry.enemy_kill_mastery_allocation(modes).SWORD,100,
		"one focused weapon receives the whole independent mastery pool")
	var fake_world=FakeRewardWorld.new()
	fake_world.events=[{"id":11,"type":"entity.died","target_id":101,"position":Vector2i(3,4),
		"step_index":7,"instigator_id":1},{"id":12,"type":"entity.died","target_id":102,
		"position":Vector2i(4,4),"step_index":7,"instigator_id":1}]
	var state=PartyState.new();state.protagonist_id=1
	state.enemy_ids.append(101);state.enemy_ids.append(102)
	state.protagonist_progression.training_modes=modes.duplicate(true)
	var coordinator=Coordinator.new(fake_world,null,null,null)
	check(coordinator._award_canonical_enemy_deaths(state),"same-step multi-death reward scan accepts")
	check_eq(state.protagonist_progression.processed_source_death_event_ids,[11,12],
		"coordinator pays same-step multi-kills once in ascending source-event order")
	check_eq(state.protagonist_progression.xp_total,200,
		"coordinator creates both parallel kill rewards without victory dependency")
	return finish()


func test_legacy_zero_victory_save_restores_its_historical_origin()->bool:
	var source=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var wire:Dictionary=JSON.parse_string(source.save_session_json())
	var old:Dictionary=wire.snapshot.party_encounter.protagonist_progression
	old.clear()
	old.merge({"schema_version":3,"xp_total":0,"processed_victory_event_ids":[],
		"training_modes":[{"skill_id":"SWORD","mode":"NORMAL"},{"skill_id":"AXE","mode":"NORMAL"},
			{"skill_id":"BLUNT","mode":"NORMAL"},{"skill_id":"SPEAR","mode":"NORMAL"},
			{"skill_id":"RANGED","mode":"NORMAL"},{"skill_id":"UNARMED","mode":"NORMAL"}],
		"skill_training":[{"skill_id":"SWORD","training_total":0},{"skill_id":"AXE","training_total":0},
			{"skill_id":"BLUNT","training_total":0},{"skill_id":"SPEAR","training_total":0},
			{"skill_id":"RANGED","training_total":0},{"skill_id":"UNARMED","training_total":0}]})
	var restored=Session.new(1,2,Session.SOLO_COMBAT_SCENARIO_ID)
	var result:Dictionary=restored.load_session_json(JSON.stringify(wire))
	check(bool(result.accepted),"legacy save with zero victories restores and replays")
	if bool(result.accepted):
		var progression=restored.sim.world.party_encounter.protagonist_progression
		check(progression.legacy_reward_origin,"legacy source marker survives zero-victory migration")
		check_eq(progression.training_modes,{"SWORD":"NORMAL","AXE":"NORMAL","BLUNT":"NORMAL",
			"SPEAR":"NORMAL","RANGED":"NORMAL","UNARMED":"NORMAL"},
			"legacy baseline is not overwritten with the new starter focus")
		check_eq(restored.sim.world.world_state_error(),"","legacy zero-victory projection is valid")
	return finish()


func test_canonical_melee_kill_immediately_emits_reward_and_replays()->bool:
	var session=_engaged_session();var state=session.sim.world.party_encounter
	var hero_id:int=state.protagonist_id;var enemy_id:int=state.enemy_ids[0]
	var final_result:Dictionary={}
	for _turn in range(40):
		if str(session.sim.world.combatant_states[enemy_id].life_state)=="DEAD":break
		var hero=session.sim.world.entities[hero_id];var enemy=session.sim.world.entities[enemy_id]
		var delta:Vector2i=enemy.position-hero.position
		final_result=session.commit_direct_solo_action(hero_id,"MELEE",[],enemy_id) \
			if maxi(absi(delta.x),absi(delta.y))<=1 \
			else session.commit_direct_solo_action(hero_id,"MOVE",
				[hero.position.x+signi(delta.x),hero.position.y+signi(delta.y)])
		if not bool(final_result.accepted):break
	var rewards:Array=[]
	for event in session.sim.world.events:
		if str(event.type)=="progression.enemy_reward":rewards.append(event)
	check(str(session.sim.world.combatant_states[enemy_id].life_state)=="DEAD",
		"actual canonical melee resolves the enemy death")
	check_eq([rewards.size(),session.protagonist_progression().xp_total,
		int(session.protagonist_progression().skills[0].training_total)],
		[1,100,100],"one real enemy death immediately raises parallel XP/mastery ledgers")
	if rewards.size()==1:
		check(int(rewards[0].id) in final_result.get("event_ids",[]),
			"killing action DTO exposes its progression reward event")
	var has_progression_log:=false
	for row in session.recent_event_log(80):
		if "경험치 +100" in str(row.message):has_progression_log=true
	check(has_progression_log,"combat log exposes the immediate kill progression reward")
	check_eq(session.sim.world.world_state_error(),"","canonical kill reward preserves world projection")
	var restored=Session.new(1,2,Session.SOLO_COMBAT_SCENARIO_ID)
	check(restored.load_session_json(session.save_session_json()).accepted,
		"canonical death reward survives save/load/replay")
	return finish()


func test_recovery_rule_cadence_and_blocks_are_explicit()->bool:
	var world=FakeWorld.new();var state=FakeState.new();var hero=FakeHero.new();var combatant=FakeCombatant.new()
	check_eq([RecoveryRules.heal_due(4),RecoveryRules.heal_due(5),RecoveryRules.heal_due(6),
		RecoveryRules.heal_due(8)],[false,true,false,true],"safe recovery is 1HP at turn 5 then every 3 turns")
	check(RecoveryRules.is_safe_to_recover(world,state,hero,combatant,0),"quiet healthy exploration can recover")
	check(not RecoveryRules.is_safe_to_recover(world,state,hero,combatant,1),"actual harmful affinity-adjusted risk blocks recovery")
	state.last_protagonist_damage_step=world.step_index
	check(not RecoveryRules.is_safe_to_recover(world,state,hero,combatant,0),"recent damage blocks recovery")
	state.last_protagonist_damage_step=-1;combatant.status_rows=[{"status_id":"POISON"}]
	check(not RecoveryRules.is_safe_to_recover(world,state,hero,combatant,0),"harmful status blocks recovery")
	combatant.status_rows=[];state.safe_phase="ENGAGED"
	check(not RecoveryRules.is_safe_to_recover(world,state,hero,combatant,0),"contact/combat blocks recovery")
	return finish()


func test_real_safe_exploration_emits_auto_recovery_after_damage()->bool:
	var session=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
	var state=session.sim.world.party_encounter;var hero_id:int=state.protagonist_id
	# Valid focused fixture: keep the existing enemy/awareness rows, but place its
	# authored home away from this compact hazard lane so the test isolates the
	# recovery rule rather than an unrelated contact transition.
	state.party_detection_radius=0;state.enemy_detection_radius=0
	var enemy_id:int=state.enemy_ids[0];var enemy=session.sim.world.entities[enemy_id]
	enemy.position=Vector2i(12,1)
	var awareness=state.enemy_awareness(enemy_id)
	awareness.home_position=enemy.position;awareness.awareness_state="UNAWARE";awareness.suspicion=0
	check_eq(session.sim.world.world_state_error(),"","safe-recovery fixture remains a valid world")
	for position in [Vector2i(3,12),Vector2i(4,12),Vector2i(5,12),Vector2i(4,12),
			Vector2i(3,12),Vector2i(2,12)]:
		check(session.commit_exploration(Command.move_to(hero_id,position)).accepted,
			"canonical hazard/safe movement commits")
	var hp_before_wait:int=session.sim.world.entities[hero_id].health
	var auto_result:Dictionary={}
	for _turn in range(5):
		var wait_result:Dictionary=session.commit_exploration(Command.wait(hero_id))
		for event_id in wait_result.get("event_ids",[]):
			var event=session.sim.world.event_by_id(int(event_id))
			if event!=null and str(event.type)=="health.restored":auto_result=wait_result
	check_eq(int(session.sim.world.entities[hero_id].health),hp_before_wait+1,
		"after recent-damage block, five consecutive safe exploration turns restore 1HP")
	var auto_event_id:=-1
	for event in session.sim.world.events:
		if str(event.type)=="health.restored" and str(event.data.get("kind",""))=="AUTO":
			auto_event_id=int(event.id)
	check(auto_event_id>0 and auto_event_id in auto_result.get("event_ids",[]),
		"committing safety turn exposes AUTO recovery through action DTO events")
	var has_recovery_log:=false
	for row in session.recent_event_log(80):
		if "안전을 되찾아" in str(row.message):has_recovery_log=true
	check(has_recovery_log,"important log includes automatic recovery")
	check_eq(session.sim.world.world_state_error(),"","AUTO recovery health projection remains valid")
	return finish()


func test_potion_heals_stack_consumes_time_and_save_replays()->bool:
	var session=_engaged_session()
	var state=session.sim.world.party_encounter;var hero_id:int=state.protagonist_id
	# A full-health attempt is rejected before any time/inventory mutation.
	var full_session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var full_before:Dictionary=full_session.sim.world.inventory_row(
		full_session.sim.world.party_encounter.protagonist_id).to_dict()
	check_eq(full_session.use_inventory_item("START_POTION_001").reason,"item_heal_not_needed",
		"full-health potion use is rejected")
	check_eq(full_session.sim.world.inventory_row(
		full_session.sim.world.party_encounter.protagonist_id).to_dict(),full_before,
		"full-health rejection is atomic")
	# Let the adjacent enemy resolve until its canonical damage has actually
	# injured the protagonist; no direct HP fixture bypasses the event ledger.
	for _turn in range(12):
		if int(session.sim.world.entities[hero_id].health)<int(session.sim.world.entities[hero_id].max_health):break
		if not session.commit_direct_solo_action(hero_id,"HOLD").accepted:break
	var hero=session.sim.world.entities[hero_id]
	check(int(hero.health)<int(hero.max_health),"fixture receives canonical combat damage before potion")
	if int(hero.health)<int(hero.max_health):
		var start_hp:int=hero.health;var start_time:int=session.sim.world.world_time
		var result:Dictionary=session.use_inventory_item("START_POTION_001")
		check(bool(result.accepted),"healing potion is usable under threat")
		if bool(result.accepted):
			check(int(result.healed_amount)>0 and int(result.healed_amount)<=35 \
				and int(result.current_hp)<=120 and int(result.time_cost)==100,
				"potion heals up to fixed 35 with max clamp and one action cost")
			check_eq(int(session.sim.world.inventory_row(
				state.protagonist_id).item("START_POTION_001").quantity),2,
				"one potion stack unit is consumed")
			check_eq(int(session.sim.world.world_time),start_time+100,"potion advances exactly one action")
			check_eq(session.sim.world.world_state_error(),"","potion health event projects canonically")
			var restored=Session.new(1,2,Session.SOLO_COMBAT_SCENARIO_ID)
			check(restored.load_session_json(session.save_session_json()).accepted,"potion journal save/replay is exact")
	return finish()


func _engaged_session():
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var state=session.sim.world.party_encounter;var hero_id:int=state.protagonist_id
	for _step in range(16):
		if session.party_status().safe_phase!="GROUPED":break
		var hero=session.sim.world.entities[hero_id]
		var enemy=session.sim.world.entities[int(state.enemy_ids[0])]
		var delta:Vector2i=enemy.position-hero.position
		var move=Command.move_to(hero_id,hero.position+Vector2i(signi(delta.x),signi(delta.y)))
		if not session.commit_exploration(move).accepted:break
	if session.party_status().safe_phase=="CONTACT":session.enter_solo_combat()
	return session
