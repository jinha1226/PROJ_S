extends "res://tests/test_case.gd"

const Session=preload("res://playtest/party_playtest_session.gd")
const Command=preload("res://sim/sim_command.gd")
const Action=preload("res://sim/party_action_command.gd")
const WorldState=preload("res://sim/world_state.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")

func test_initial_focus_save_replay_detachment_and_tamper_are_exact()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var before=session.save_session_json()
	var progression:Dictionary=session.protagonist_progression()
	check_eq([progression.level,progression.xp_total,progression.xp_current,
		progression.xp_required,progression.next_level_threshold],
		[1,0,0,100,100],"fresh run starts at level one with exact threshold")
	check_eq(progression.skills.map(func(row):return [row.skill_id,row.rank,row.focus]),
		[["MELEE",0,50],["GUARD",0,30],["EXPLORATION",0,20]],
		"three honest skills have deterministic default focus")
	progression.skills[0].focus=999
	check_eq(session.protagonist_progression().skills[0].focus,50,
		"progression presentation is deeply detached")
	check_eq(session.save_session_json(),before,"progression reads are pure")
	var focused:Dictionary=session.set_training_focus("MELEE")
	check(focused.accepted,"focus preset commits: %s"%focused)
	check_eq(session.protagonist_progression().skills.map(func(row):return row.focus),
		[60,20,20],"focus preset keeps exact total one hundred")
	check_eq(session.command_journal.size(),1,"focus change is journaled once")
	if not session.command_journal.is_empty():check_eq(session.command_journal[0].kind,
		"progression","focus journal kind")
	var duplicate_before:=session.save_session_json()
	check_eq(session.set_training_focus("MELEE").reason,"training_focus_unchanged",
		"same focus rejects without a duplicate event")
	check_eq(session.save_session_json(),duplicate_before,"duplicate focus is exact no-op")
	var restored=Session.new(1,2)
	check(restored.load_session_json(session.save_session_json()).accepted,
		"focus journal replays")
	check_eq(restored.sim.snapshot(),session.sim.snapshot(),"focus replay snapshot exact")
	var tampered:Dictionary=JSON.parse_string(session.save_session_json())
	tampered.snapshot.party_encounter.protagonist_progression.xp_total=1
	var target=Session.new(9,10);var target_before:=target.save_session_json()
	var rejection:Dictionary=target.load_session_json(JSON.stringify(tampered))
	check_eq(rejection.reason,"party_progression_projection_mismatch",
		"progression tamper is rejected by canonical event projection")
	check_eq(target.save_session_json(),target_before,"tamper rejection is transactional")
	return finish()

func test_canonical_victory_awards_once_levels_and_resets_fresh()->bool:
	var session=Session.new();var state=session.sim.world.party_encounter
	check(session.commit_exploration(Command.wait(state.protagonist_id)).accepted,
		"fixture reaches contact")
	check(session.preview_deployment("WEDGE",state.party_member_ids.slice(1)).accepted,
		"fixture deployment preview")
	check(session.commit_deployment().accepted,"fixture enters combat")
	check(_resolve_encounter(session,32),"canonical encounter clears")
	var progression:Dictionary=session.protagonist_progression()
	check_eq([progression.level,progression.xp_total,progression.xp_current,
		progression.xp_required,progression.next_level_threshold],
		[2,100,0,150,250],"victory grants exact level pacing XP")
	check_eq(progression.skills.map(func(row):return [row.skill_id,row.rank,row.training_total]),
		[["MELEE",1,50],["GUARD",0,30],["EXPLORATION",0,20]],
		"victory training allocation is integer-only by focus")
	var victory_count:=0
	for event in session.sim.world.events:
		if event.type=="party.victory":victory_count+=1
	check_eq([victory_count,
		session.sim.world.party_encounter.protagonist_progression.processed_victory_event_ids.size()],
		[1,1],"one canonical victory produces one award")
	var snapshot:Dictionary=session.sim.snapshot()
	for index in range(20):session.protagonist_progression();session.party_status()
	check_eq(session.sim.snapshot(),snapshot,"refresh cannot duplicate progression")
	var restored=WorldState.from_snapshot(JSON.parse_string(JSON.stringify(snapshot)))
	check(restored!=null,"progressed snapshot restores")
	if restored!=null:check_eq(restored.snapshot(),snapshot,"progressed snapshot round trip exact")
	check(session.reset_party(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID),
		"new expedition resets authority")
	check_eq([session.protagonist_progression().level,session.protagonist_progression().xp_total,
		session.command_journal.size()],[1,0,0],"fresh expedition has no carryover")
	return finish()

func test_melee_rank_changes_authoritative_preview_without_level_multiplier()->bool:
	var baseline=_engaged_adjacent_fixture()
	var hero:=int(baseline.party_status().protagonist_id)
	var enemy:=int(baseline.party_status().visible_enemy_ids[0])
	var base_preview:Dictionary=baseline.preview_actor_action(hero,"MELEE",[],enemy)
	var base_damage:=int(base_preview.actor_rows[0].combat_assessment.normal_final_damage)
	var skilled=_engaged_adjacent_fixture()
	var skilled_state=skilled.sim.world.party_encounter
	# Unit fixture: isolate the rank seam. Canonical award/event projection is
	# covered above; this checks the combat kernel consumes rank, not level.
	skilled_state.protagonist_progression.skill_training.MELEE=50
	var skilled_preview:Dictionary=skilled.preview_actor_action(
		int(skilled_state.protagonist_id),"MELEE",[],int(skilled_state.enemy_ids[0]))
	var skilled_damage:=int(skilled_preview.actor_rows[0].combat_assessment.normal_final_damage)
	check_eq(skilled_damage,base_damage+2,"melee rank one adds transparent two damage")
	check_eq(skilled.protagonist_progression().level,1,
		"combat effect does not use character level as multiplier")
	return finish()

func test_guard_rank_changes_frozen_preview_resolution_and_rank_zero_validates()->bool:
	var baseline=_engaged_adjacent_fixture();var base_state=baseline.sim.world.party_encounter
	var hero:=int(base_state.protagonist_id);var enemy:=int(base_state.enemy_ids[0])
	baseline.sim.world.combatant_states[hero].guarded_until=baseline.sim.world.world_time+200
	var base_assessment:Dictionary=baseline.sim.melee.assess_attack(enemy,hero,"SUGGESTED",
		baseline.sim.world.step_index+1,baseline.sim.world.world_time,"GUARD_TEST",0)
	var skilled=_engaged_adjacent_fixture();var skilled_state=skilled.sim.world.party_encounter
	var skilled_hero:=int(skilled_state.protagonist_id);var skilled_enemy:=int(skilled_state.enemy_ids[0])
	skilled_state.protagonist_progression.skill_training.GUARD=50
	skilled.sim.world.combatant_states[skilled_hero].guarded_until=skilled.sim.world.world_time+200
	var skilled_assessment:Dictionary=skilled.sim.melee.assess_attack(skilled_enemy,skilled_hero,"SUGGESTED",
		skilled.sim.world.step_index+1,skilled.sim.world.world_time,"GUARD_TEST",0)
	check(not base_assessment.is_empty() and not skilled_assessment.is_empty(),"guard fixtures create canonical-shaped assessments")
	if not base_assessment.is_empty() and not skilled_assessment.is_empty():
		check(int(skilled_assessment.guard_reduction)>int(base_assessment.guard_reduction),
			"GUARD rank one raises HOLD reduction from 25% to 30%")
		var frozen=skilled.sim.melee.freeze_assessment(skilled_assessment,120,0,true)
		var resolution=skilled.sim.melee.resolve_frozen_intent(frozen)
		check(resolution!=null and int(resolution.final_damage)==int(skilled_assessment.normal_final_damage),
			"frozen resolution consumes the ranked guard preview exactly")
	var hold_preview:Dictionary=skilled.preview_actor_action(skilled_hero,"HOLD")
	check(bool(hold_preview.get("accepted",false)) and hold_preview.get("selected_action_preview",{}) is Dictionary \
		and "30%" in str(hold_preview.selected_action_preview.get("reason","")),
		"detached HOLD presentation reports the authoritative ranked percentage")
	check_eq(skilled.protagonist_progression().level,1,"GUARD effect never reads character level")

	var canonical=_engaged_adjacent_fixture();var canonical_hero:=int(canonical.party_status().protagonist_id)
	check(canonical.set_actor_action(canonical_hero,"HOLD").accepted,"rank-zero HOLD draft accepted")
	check(canonical.commit_turn().accepted,"rank-zero HOLD resolution commits")
	check_eq(canonical.sim.world.world_state_error(),"","rank-zero guard events pass canonical validator")
	var tampered:Dictionary=canonical.sim.snapshot();var changed:=false
	for event in tampered.events:
		if event.type=="action.melee_attack" and event.target_id==str(canonical_hero) and bool(event.data.guarded):
			event.data.guard_reduction=int(event.data.guard_reduction)+1;changed=true;break
	check(changed,"fixture records a guarded canonical melee action")
	if changed:check(WorldState.from_snapshot(tampered)==null,"validator rejects a forged guard reduction")
	return finish()

func test_mobile_card_detail_focus_and_enemy_threat_are_visible()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var sandbox=Sandbox.new();sandbox.size=Vector2(360,640)
	sandbox.initialize_for_headless_test(session,true)
	var level=sandbox.find_child("LevelProgress",true,false) as Label
	var compact_xp=sandbox.find_child("CompactXPBar",true,false) as ProgressBar
	check(level!=null and "Lv.1" in level.text and "공" in level.text and compact_xp!=null \
		and compact_xp.max_value==100,"solo mobile hero card shows level, stats, and real XP bar")
	sandbox._open_hero_detail()
	check(sandbox.member_detail_tab_row.visible and sandbox.member_detail_status_tab.button_pressed \
		and sandbox.member_detail_body.visible and not sandbox.member_progression_window.visible,
		"hero detail predictably opens on the dedicated status tab")
	check(sandbox.member_detail_status_tab.custom_minimum_size.y>=44 \
		and sandbox.member_detail_skill_tab.custom_minimum_size.y>=44 \
		and "●" in sandbox.member_detail_status_tab.text,
		"status/skill tabs are touch-sized with an obvious selected state")
	check("집중 버튼" not in sandbox.member_detail_body.text and "레벨은 피해" not in sandbox.member_detail_body.text,
		"status tab has no duplicate progression copy")
	sandbox._select_member_detail_tab("SKILL")
	check(sandbox.member_progression_window.visible and not sandbox.member_detail_body.visible \
		and sandbox.member_progression_xp.max_value==100 and "공격력" in sandbox.member_progression_stats.text,
		"skill tab alone shows visual XP and honest derived combat stats")
	check(sandbox.member_progression_skill_rows.size()==3 \
		and "미래" in str((sandbox.member_progression_skill_rows.EXPLORATION.future as Label).text),
		"three visual skill cards distinguish current and future effects")
	check(sandbox.member_detail_focus_buttons.visible,
		"hero detail exposes focus controls")
	check((sandbox.member_detail_focus_buttons.get_child(0) as Button).button_pressed \
		and "✓" in (sandbox.member_detail_focus_buttons.get_child(0) as Button).text,
		"dominant training focus has an obvious selected state")
	for child in sandbox.member_detail_focus_buttons.get_children():
		check(child is Button and child.custom_minimum_size.y>=44,
			"focus control remains mobile readable")
	sandbox._on_training_focus("GUARD")
	check(sandbox.member_detail_current_tab=="SKILL" and sandbox.member_progression_window.visible \
		and sandbox.member_detail_skill_tab.button_pressed,
		"focus changes refresh while preserving the skill tab")
	sandbox._close_member_detail();sandbox._open_hero_detail()
	check(sandbox.member_detail_current_tab=="STATUS" and sandbox.member_detail_body.visible,
		"closing and reopening predictably returns to status")
	var companion_session=Session.new();var companion_ui=Sandbox.new();companion_ui.size=Vector2(360,640)
	companion_ui.initialize_for_headless_test(companion_session,false)
	var companion_id:=int(companion_session.party_status().party_member_ids[1]);companion_ui._open_member_detail(companion_id)
	check(not companion_ui.member_detail_tab_row.visible and companion_ui.member_detail_body.visible \
		and not companion_ui.member_progression_window.visible,
		"companions without progression never expose fake tabs")
	var engaged=_engaged_adjacent_fixture();var combat_ui=Sandbox.new();combat_ui.size=Vector2(360,640)
	combat_ui.initialize_for_headless_test(engaged,true)
	combat_ui.selected_target_id=int(engaged.party_status().visible_enemy_ids[0])
	combat_ui._refresh()
	var inspector=combat_ui.find_child("EnemyInspector",true,false) as Label
	check(inspector!=null and "레벨" in inspector.text \
		and ("하찮음" in inspector.text or "대등" in inspector.text \
			or "위험" in inspector.text or "치명적" in inspector.text),
		"enemy contextual inspector shows derived level and threat")
	sandbox.free();companion_ui.free();combat_ui.free()
	return finish()

func _engaged_adjacent_fixture():
	var session=Session.new();var state=session.sim.world.party_encounter
	session.commit_exploration(Command.wait(state.protagonist_id))
	session.preview_deployment("WEDGE",state.party_member_ids.slice(1));session.commit_deployment()
	for _turn in range(4):
		var hero:=int(session.party_status().protagonist_id)
		var enemy:=int(session.party_status().visible_enemy_ids[0])
		var hero_position:=_party_position(session,hero)
		var enemy_position:=Vector2i(session.enemy_targets()[0].position[0],session.enemy_targets()[0].position[1])
		if maxi(absi(hero_position.x-enemy_position.x),absi(hero_position.y-enemy_position.y))==1:break
		var direction:=Vector2i(signi(enemy_position.x-hero_position.x),signi(enemy_position.y-hero_position.y))
		session.set_actor_action(hero,"MOVE",[hero_position.x+direction.x,hero_position.y+direction.y])
		session.commit_turn()
	return session

func _resolve_encounter(session,limit:int)->bool:
	for _turn in range(limit):
		var status:Dictionary=session.party_status()
		if status.safe_phase=="GROUPED_COMPLETE":return true
		if status.safe_phase!="ENGAGED":return false
		var hero:=int(status.protagonist_id);var hero_position:=_party_position(session,hero)
		var targets:Array=session.enemy_targets()
		if targets.is_empty():return false
		var enemy:Dictionary=targets[0]
		var enemy_position:=Vector2i(int(enemy.position[0]),int(enemy.position[1]))
		var preview:Dictionary={"accepted":false}
		if maxi(absi(hero_position.x-enemy_position.x),absi(hero_position.y-enemy_position.y))==1:
			preview=session.set_actor_action(hero,"MELEE",[],int(enemy.entity_id))
		else:
			for direction in [Vector2i(signi(enemy_position.x-hero_position.x),signi(enemy_position.y-hero_position.y)),
					Vector2i(signi(enemy_position.x-hero_position.x),0),Vector2i(0,signi(enemy_position.y-hero_position.y))]:
				if direction==Vector2i.ZERO:continue
				preview=session.set_actor_action(hero,"MOVE",[hero_position.x+direction.x,hero_position.y+direction.y])
				if bool(preview.get("accepted",false)):break
		if not bool(preview.get("accepted",false)):preview=session.set_actor_action(hero,"HOLD")
		if not bool(preview.get("accepted",false)) or not session.commit_turn().accepted:return false
	return session.party_status().safe_phase=="GROUPED_COMPLETE"

func _party_position(session,entity_id:int)->Vector2i:
	for card in session.party_cards():
		if int(card.entity_id)==entity_id:return Vector2i(int(card.logical_position[0]),int(card.logical_position[1]))
	return Vector2i(-1,-1)
