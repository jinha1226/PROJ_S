extends "res://tests/test_case.gd"

const Session=preload("res://playtest/party_playtest_session.gd")
const Command=preload("res://sim/sim_command.gd")
const Action=preload("res://sim/party_action_command.gd")
const WorldState=preload("res://sim/world_state.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")

func test_initial_modes_save_replay_detachment_and_tamper_are_exact()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var before=session.save_session_json()
	var progression:Dictionary=session.protagonist_progression()
	check_eq([progression.level,progression.xp_total,progression.xp_current,
		progression.xp_required,progression.next_level_threshold],
		[1,0,0,100,100],"fresh run starts at level one with exact threshold")
	check_eq(progression.skills.map(func(row):return [row.skill_id,row.rank,row.training_mode]),
		[["SWORD",0,"NORMAL"],["AXE",0,"NORMAL"],["BLUNT",0,"NORMAL"],
			["SPEAR",0,"NORMAL"],["RANGED",0,"NORMAL"],["UNARMED",0,"NORMAL"]],
		"six weapon proficiencies have independent deterministic default modes")
	progression.skills[0].training_mode="OFF"
	check_eq(session.protagonist_progression().skills[0].training_mode,"NORMAL",
		"progression presentation is deeply detached")
	check_eq(session.save_session_json(),before,"progression reads are pure")
	var focused:Dictionary=session.set_training_mode("SWORD","FOCUS")
	check(focused.accepted,"independent mode commits: %s"%focused)
	check_eq(session.protagonist_progression().skills.map(func(row):return row.training_mode),
		["FOCUS","NORMAL","NORMAL","NORMAL","NORMAL","NORMAL"],
		"SWORD changes without overwriting other rows")
	check(session.set_training_mode("AXE","OFF").accepted,"second row changes independently")
	check_eq(session.protagonist_progression().skills.map(func(row):return row.training_mode),
		["FOCUS","OFF","NORMAL","NORMAL","NORMAL","NORMAL"],
		"multiple independent mode choices coexist")
	check_eq(session.command_journal.size(),2,"each mode change is journaled once")
	if not session.command_journal.is_empty():check_eq(session.command_journal[0].kind,
		"progression","focus journal kind")
	var duplicate_before:=session.save_session_json()
	check_eq(session.set_training_mode("SWORD","FOCUS").reason,"training_mode_unchanged",
		"same mode rejects without a duplicate event")
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
		[["SWORD",0,17],["AXE",0,17],["BLUNT",0,17],["SPEAR",0,17],
			["RANGED",0,16],["UNARMED",0,16]],
		"victory training remainder follows fixed proficiency order")
	var victory_count:=0
	for event in session.sim.world.events:
		if event.type=="party.victory":victory_count+=1
	check_eq([victory_count,
		session.sim.world.party_encounter.protagonist_progression.processed_victory_event_ids.size()],
		[1,1],"one canonical victory produces one award")
	var snapshot:Dictionary=session.sim.snapshot()
	for index in range(20):session.protagonist_progression();session.party_status()
	check_eq(session.sim.snapshot(),snapshot,"refresh cannot duplicate progression")
	# `WorldState.from_snapshot` is the strict typed-wire boundary. JSON transport
	# canonicalization (including integral item fields decoded as floats) belongs
	# to `Session.load_session_json`, which is exercised immediately below.
	var restored=WorldState.from_snapshot(snapshot.duplicate(true))
	check(restored!=null,"progressed typed snapshot restores")
	if restored!=null:check_eq(restored.snapshot(),snapshot,"progressed snapshot round trip exact")
	var legacy_session:Dictionary=JSON.parse_string(session.save_session_json())
	var legacy_progression:Dictionary=legacy_session.snapshot.party_encounter.protagonist_progression
	legacy_progression.schema_version=2;legacy_progression.erase("training_modes")
	legacy_progression.training_focus=[]
	for row in [{"skill_id":"SWORD","weight":30},{"skill_id":"AXE","weight":15},
			{"skill_id":"BLUNT","weight":15},{"skill_id":"SPEAR","weight":15},
			{"skill_id":"RANGED","weight":15},{"skill_id":"UNARMED","weight":10}]:
		legacy_progression.training_focus.append(row)
	var migrated_session=Session.new(1,2)
	check(migrated_session.load_session_json(JSON.stringify(legacy_session)).accepted,
		"schema two session progression migrates through canonical event replay")
	check_eq(migrated_session.sim.snapshot(),session.sim.snapshot(),
		"schema two session migration preserves the canonical projection")
	check(session.reset_party(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID),
		"new expedition resets authority")
	check_eq([session.protagonist_progression().level,session.protagonist_progression().xp_total,
		session.command_journal.size()],[1,0,0],"fresh expedition has no carryover")
	return finish()

func test_sword_rank_changes_only_accuracy_and_damage_without_level_or_speed_multiplier()->bool:
	var baseline=_engaged_adjacent_fixture()
	var hero:=int(baseline.party_status().protagonist_id)
	var enemy:=int(baseline.party_status().visible_enemy_ids[0])
	var base_preview:Dictionary=baseline.preview_actor_action(hero,"MELEE",[],enemy)
	var base_assessment:Dictionary=base_preview.actor_rows[0].combat_assessment
	var skilled=_engaged_adjacent_fixture()
	var skilled_state=skilled.sim.world.party_encounter
	# Unit fixture: isolate the rank seam. Canonical award/event projection is
	# covered above; this checks the combat kernel consumes rank, not level.
	skilled_state.protagonist_progression.skill_training.SWORD=50
	var skilled_preview:Dictionary=skilled.preview_actor_action(
		int(skilled_state.protagonist_id),"MELEE",[],int(skilled_state.enemy_ids[0]))
	var skilled_assessment:Dictionary=skilled_preview.actor_rows[0].combat_assessment
	check(int(skilled_assessment.proficiency_accuracy_milli) \
			> int(base_assessment.proficiency_accuracy_milli),
		"SWORD rank one raises authoritative accuracy even when final chance hits its cap")
	check_eq(int(skilled_assessment.normal_final_damage),
		int(base_assessment.normal_final_damage)+1,"SWORD rank one adds transparent damage")
	check_eq(skilled_assessment.attack_time,base_assessment.attack_time,
		"SWORD rank cannot change the weapon's intrinsic attack time")
	check_eq(skilled.protagonist_progression().level,1,
		"combat effect does not use character level as multiplier")
	return finish()

func test_hold_is_fixed_twenty_five_percent_without_a_guard_proficiency()->bool:
	var baseline=_engaged_adjacent_fixture();var base_state=baseline.sim.world.party_encounter
	var hero:=int(base_state.protagonist_id);var enemy:=int(base_state.enemy_ids[0])
	baseline.sim.world.combatant_states[hero].guarded_until=baseline.sim.world.world_time+200
	var base_assessment:Dictionary=baseline.sim.melee.assess_attack(enemy,hero,"SUGGESTED",
		baseline.sim.world.step_index+1,baseline.sim.world.world_time,"GUARD_TEST",0)
	var skilled=_engaged_adjacent_fixture();var skilled_state=skilled.sim.world.party_encounter
	var skilled_hero:=int(skilled_state.protagonist_id);var skilled_enemy:=int(skilled_state.enemy_ids[0])
	skilled_state.protagonist_progression.skill_training.SWORD=50
	skilled.sim.world.combatant_states[skilled_hero].guarded_until=skilled.sim.world.world_time+200
	var skilled_assessment:Dictionary=skilled.sim.melee.assess_attack(skilled_enemy,skilled_hero,"SUGGESTED",
		skilled.sim.world.step_index+1,skilled.sim.world.world_time,"GUARD_TEST",0)
	check(not base_assessment.is_empty() and not skilled_assessment.is_empty(),"guard fixtures create canonical-shaped assessments")
	if not base_assessment.is_empty() and not skilled_assessment.is_empty():
		check_eq(skilled_assessment.guard_reduction,base_assessment.guard_reduction,
			"weapon proficiency cannot alter HOLD reduction")
		check_eq(int(base_assessment.guard_reduction),
			int(int(base_assessment.base_damage-base_assessment.armor_reduction)*25/100),
			"HOLD reduces post-armor damage by a fixed 25 percent")
		var frozen=skilled.sim.melee.freeze_assessment(skilled_assessment,120,0,true)
		var resolution=skilled.sim.melee.resolve_frozen_intent(frozen)
		check(resolution!=null,"frozen HOLD assessment resolves deterministically")
		if resolution!=null:
			var expected_damage:=int(skilled_assessment.normal_final_damage) \
				if str(resolution.outcome)=="HIT" else 0
			check_eq(int(resolution.final_damage),expected_damage,
				"frozen resolution consumes the fixed HOLD preview exactly")
	var hold_preview:Dictionary=skilled.preview_actor_action(skilled_hero,"HOLD")
	check(bool(hold_preview.get("accepted",false)) and hold_preview.get("selected_action_preview",{}) is Dictionary \
		and "25%" in str(hold_preview.selected_action_preview.get("reason","")),
		"detached HOLD presentation reports the fixed percentage")
	check_eq(skilled.protagonist_progression().level,1,"HOLD never reads character level")

	var canonical=_engaged_adjacent_fixture();var canonical_hero:=int(canonical.party_status().protagonist_id)
	var guarded_event_recorded:=false
	for _turn in range(8):
		if canonical.party_status().safe_phase!="ENGAGED":break
		check(canonical.set_actor_action(canonical_hero,"HOLD").accepted,"rank-zero HOLD draft accepted")
		check(canonical.commit_turn().accepted,"rank-zero HOLD resolution commits")
		for event in canonical.sim.world.events:
			if event.type=="action.melee_attack" and int(event.target_id)==canonical_hero \
					and bool(event.data.guarded):
				guarded_event_recorded=true;break
		if guarded_event_recorded:break
	check_eq(canonical.sim.world.world_state_error(),"","rank-zero guard events pass canonical validator")
	var tampered:Dictionary=canonical.sim.snapshot();var changed:=false
	for event in tampered.events:
		if event.type=="action.melee_attack" and int(event.target_id)==canonical_hero and bool(event.data.guarded):
			event.data.guard_reduction=int(event.data.guard_reduction)+1;changed=true;break
	check(changed and guarded_event_recorded,"fixture records a guarded canonical melee action")
	if changed:check(WorldState.from_snapshot(tampered)==null,"validator rejects a forged guard reduction")
	return finish()

func test_mobile_card_detail_focus_and_enemy_threat_are_visible()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var sandbox=Sandbox.new();sandbox.size=Vector2(360,640)
	sandbox.initialize_for_headless_test(session,true)
	sandbox.size=Vector2(360,640);sandbox._refresh()
	var level=sandbox.find_child("LevelProgress",true,false) as Label
	var compact_xp=sandbox.find_child("CompactXPBar",true,false)
	var compact_xp_spec:Dictionary=compact_xp.call("gauge_spec") if compact_xp!=null else {}
	var card_name=sandbox.find_child("MemberName",true,false) as Label
	var card_hp=sandbox.find_child("MemberState",true,false) as Label
	var card_hp_spec:Dictionary=card_hp.call("gauge_spec") if card_hp!=null \
			and card_hp.has_method("gauge_spec") else {}
	var card_state=sandbox.find_child("EmotionState",true,false) as Label
	var actor_seal=sandbox.find_child("ActorGlyphSeal",true,false) as Label
	check(level!=null and level.text=="LV01" and card_name!=null and card_hp!=null \
		and int(card_hp_spec.get("value",-1))==120 \
		and int(card_hp_spec.get("max_value",0))==120 \
		and str(card_hp_spec.get("primitive",""))=="DOS_TEXT_GAUGE" \
		and card_state!=null and compact_xp!=null \
		and int(compact_xp_spec.get("max_value",0))==100 \
		and str(compact_xp_spec.get("primitive",""))=="DOS_TEXT_GAUGE" \
		and sandbox.find_child("StressState",true,false)!=null \
		and sandbox.find_child("DossierAsciiFrame",true,false)==null \
		and actor_seal!=null and actor_seal.text=="@",
		"top status strip shows exact identity, HP, LV, state, stress, and XP")
	check("공" not in level.text and "방" not in level.text,
		"solo mobile hero card does not persist derived attack or defense")
	check(not sandbox.phase_panel.visible and sandbox.cards.get_index()<sandbox.grid.get_index() \
		and sandbox.cards.custom_minimum_size.y==68.0 \
		and sandbox.grid.custom_minimum_size==Vector2(360,360) \
		and sandbox.bottom_navigation.visible and sandbox.bottom_navigation.custom_minimum_size.y>=44.0,
		"360x640 places the adaptive status strip before a full-width map and fixed navigation")
	var wide_session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var wide=Sandbox.new();wide.initialize_for_headless_test(wide_session,true)
	wide.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);wide.size=Vector2(450,800);wide._refresh()
	var wide_card=wide.cards.get_child(0) as Button
	check(wide.cards.get_index()<wide.grid.get_index() \
		and wide.grid.custom_minimum_size==Vector2(450,450),
		"450x800 keeps the status strip before the full-width map")
	check(wide_card.custom_minimum_size.x>=438,"450x800 solo card uses the available width")
	check(wide_card.find_child("Portrait",true,false)==null \
		and wide_card.find_child("SoloIdentity",true,false)!=null,
		"450x800 solo card spends its width on identity instead of a duplicate portrait")
	check(wide_card.find_child("CompactXPBar",true,false)!=null \
		and "공" not in str((wide_card.find_child("LevelProgress",true,false) as Label).text),
		"450x800 solo card keeps XP but no persistent combat stats")
	wide.free()
	sandbox.person_nav_button.pressed.emit()
	check(sandbox.member_detail_tab_row.visible and sandbox.member_detail_status_tab.button_pressed \
		and sandbox.member_status_window.visible and sandbox.member_detail_body.visible \
		and not sandbox.member_progression_window.visible,
		"hero detail predictably opens on the dedicated status tab")
	check(sandbox.find_child("StatusPortrait",true,false)==null \
		and sandbox.find_child("MemberDetailPortrait",true,false)==null \
		and sandbox.find_child("MemberDetailGlyphSeal",true,false)!=null \
		and sandbox.member_detail_title.text=="주인공" \
		and "인간 / 주인공 / LV01 / 생존" in sandbox.member_detail_subtitle.text \
		and sandbox.find_child("StatusFolioGrid",true,false) is GridContainer \
		and (sandbox.find_child("StatusFolioGrid",true,false) as GridContainer).columns==2 \
		and sandbox.find_child("StatusHealthBar",true,false)!=null \
		and sandbox.find_child("StatusStressBar",true,false)!=null \
		and sandbox.find_child("StatusEmotion",true,false)!=null \
		and sandbox.find_child("StatusStress",true,false)!=null \
		and sandbox.find_child("StatusCombatSummary",true,false)!=null,
		"status folio keeps identity in its header and meaningful vital/combat facts in two columns")
	var status_hp=sandbox.find_child("StatusHealthBar",true,false)
	var status_stress=sandbox.find_child("StatusStressBar",true,false)
	check(status_hp!=null and status_stress!=null \
		and status_hp.has_method("gauge_spec") and status_stress.has_method("gauge_spec") \
		and int(status_hp.call("gauge_spec").get("value",-1))==120 \
		and int(status_hp.call("gauge_spec").get("max_value",0))==120 \
		and int(status_stress.call("gauge_spec").get("value",-1))==0 \
		and int(status_stress.call("gauge_spec").get("max_value",0))==1000,
		"status folio DOS gauges retain authoritative HP and stress values")
	check("관계" not in sandbox.member_detail_body.text and "없음" not in sandbox.member_detail_body.text,
		"hero status hides relations and empty placeholder values")
	check(sandbox.member_detail_status_tab.custom_minimum_size.y>=44 \
		and sandbox.member_detail_skill_tab.custom_minimum_size.y>=44 \
		and sandbox.member_detail_item_tab.custom_minimum_size.y>=44 \
		and "[상태]" in sandbox.member_detail_status_tab.text \
		and bool(sandbox.member_detail_status_tab.get_meta("ascii_rail",false)),
		"status/skill tabs are touch-sized glyph-backed segments")
	check("집중 버튼" not in sandbox.member_detail_body.text and "레벨은 피해" not in sandbox.member_detail_body.text,
		"status tab has no duplicate progression copy")
	sandbox._close_member_detail();sandbox.skill_nav_button.pressed.emit()
	check(sandbox.member_progression_window.visible and not sandbox.member_detail_body.visible \
		and not sandbox.member_status_window.visible and sandbox.member_progression_xp.max_value==100 \
		and "아이템 탭" in sandbox.member_progression_stats.text,
		"skill tab alone shows visual XP without equipment")
	check_eq(sandbox.member_progression_skill_rows.keys().size(),6,
		"six visual proficiency cards are present")
	check(not sandbox.member_skill_category_expanded,"weapon mastery starts collapsed")
	sandbox._toggle_weapon_mastery_category()
	for skill_id in ["SWORD","AXE","BLUNT","SPEAR","RANGED","UNARMED"]:
		var skill_row:Dictionary=sandbox.member_progression_skill_rows.get(skill_id,{})
		check(not skill_row.is_empty() \
			and (skill_row.title as Button).custom_minimum_size.y>=44 \
			and str((skill_row.rank as Label).text).begins_with("R") \
			and "명중" in str((skill_row.effect as Label).text) \
			and "×" in str((skill_row.mode as Label).text) \
			and "/" in str((skill_row.xp as Label).text),
			"%s row exposes fixed rank/name/effect/mode/current XP ledger"%skill_id)
	check(sandbox.find_child("SkillDetail",true,false)==null \
		and sandbox.find_child("TrainingProgress",true,false)==null,
		"skill ledger has no selected-row expansion")
	sandbox._close_member_detail();sandbox.equipment_nav_button.pressed.emit()
	var item_stats=sandbox.find_child("EquippedWeaponStats",true,false) as GridContainer
	var time_stat=sandbox.find_child("WeaponTimeStat",true,false) as Label
	check(sandbox.member_item_window.visible and "단검" in sandbox.member_item_weapon_text.text \
		and item_stats!=null and item_stats.columns==2 and item_stats.get_child_count()==4 \
		and time_stat!=null and time_stat.text=="공격시간  100" \
		and "화살 12" in sandbox.member_item_ammo_text.text,
		"item tab owns real weapon, compact stats, and ammo information")
	sandbox._select_member_detail_tab("SKILL")
	var modes_before:Array=session.protagonist_progression().skills.map(
		func(row):return [str(row.skill_id),str(row.training_mode)])
	sandbox._on_training_focus("AXE")
	check(sandbox.member_detail_current_tab=="SKILL" and sandbox.member_progression_window.visible \
		and sandbox.member_detail_skill_tab.button_pressed \
		and str(session.protagonist_progression().skills[1].training_mode)=="FOCUS" \
		and str(session.protagonist_progression().skills[0].training_mode)==str(modes_before[0][1]),
		"focus changes only AXE authority and preserves the skill tab")
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
	var enemy_id:=int(engaged.party_status().visible_enemy_ids[0])
	var threat:Dictionary=engaged.inspect_enemy(enemy_id)
	check(bool(threat.get("accepted",false)) and int(threat.get("level",0))>=1 \
		and str(threat.get("threat_id","")) in ["TRIVIAL","EVEN","DANGEROUS","LETHAL"] \
		and str(threat.get("threat_label","")) in ["하찮음","대등","위험","치명적"],
		"session DTO preserves authoritative enemy level and threat")
	check(inspector==null and combat_ui.grid._intent_overlays.is_empty() \
		and combat_ui.grid.route_draw_spec().segments.is_empty() \
		and combat_ui.grid.cursor_cell==Vector2i(-1,-1),
		"solo direct combat has no persistent enemy inspector, plan, route, or cursor clutter")
	sandbox.free();companion_ui.free();combat_ui.free()
	return finish()

func _engaged_adjacent_fixture():
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var state=session.sim.world.party_encounter
	var hero_id:=int(state.protagonist_id)
	for _step in range(256):
		if session.party_status().safe_phase=="CONTACT":break
		var enemy_id:=int(state.enemy_ids[0])
		var path:Dictionary=session.sim.party_coordinator.pathfinder.find_path_to_any(
			hero_id,_adjacent_open_cells(session,enemy_id))
		if not bool(path.get("found",false)) or path.path.size()<2:break
		var next_position:Vector2i=path.path[1]
		if not session.commit_exploration(Command.move_to(hero_id,next_position)).accepted:break
	if session.party_status().safe_phase=="CONTACT":session.enter_solo_combat()
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

func _adjacent_open_cells(session,entity_id:int)->Array[Vector2i]:
	var result:Array[Vector2i]=[]
	var origin:Vector2i=session.sim.world.entities[entity_id].position
	for direction_value in session.sim.movement.MOVE_DIRECTIONS_8:
		var direction:Vector2i=direction_value;var position:=origin+direction
		if not session.sim.world.in_bounds(position):continue
		var terrain:Dictionary=load("res://sim/terrain_registry.gd").definition(
			session.sim.world.tile_at(position).terrain)
		if bool(terrain.get("passable",false)):result.append(position)
	return result

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
