extends "res://tests/test_case.gd"

const Session = preload("res://playtest/party_playtest_session.gd")
const Sandbox = preload("res://playtest/party_encounter_sandbox.gd")
const Command = preload("res://sim/sim_command.gd")
const PartyAction = preload("res://sim/party_action_command.gd")
const CampaignEncounterStream = preload("res://sim/campaign_encounter_stream.gd")

const STARTER_WEAPON_INSTANCE_IDS := {
	"HAND_AXE":"START_HAND_AXE_001",
	"MACE":"START_MACE_001",
	"SPEAR":"START_SPEAR_001",
	"BOW":"START_BOW_001",
	"CROSSBOW":"START_CROSSBOW_001",
}


func test_solo_starts_with_detached_sword_loadout_and_six_proficiencies() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	check(session.sim != null, "solo session initializes")
	if session.sim == null: return finish()
	var equipment: Dictionary = session.protagonist_equipment()
	check_eq([equipment.weapon_id, equipment.attack_form, equipment.range_max,
		equipment.arrows, equipment.bolts], ["SHORT_SWORD", "SLASH", 1, 12, 6],
		"new expedition loadout")
	var progression: Dictionary = session.protagonist_progression()
	check_eq(progression.skills.map(func(row): return row.skill_id),
		["SWORD", "AXE", "BLUNT", "SPEAR", "RANGED", "UNARMED"],
		"six proficiency cards")
	equipment.weapon_label = "FORGED"
	check(session.protagonist_equipment().weapon_label != "FORGED", "equipment DTO detached")
	check_eq(session.sim.world.world_state_error(), "", "fresh weapon world validates")
	return finish()


func test_equipment_and_reload_journal_replay_exactly() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var bow_equip:Dictionary=_equip_starter_weapon(session, "BOW")
	check(bool(bow_equip.get("accepted",false)), "bow equips: %s" % bow_equip)
	var bow_actor:=_observed_protagonist(session)
	check_eq(str((bow_actor.get("equipment_visual",{}) as Dictionary).get("weapon_id","")),
		"BOW","weapon swap immediately refreshes the actor observation")
	var crossbow_equip:Dictionary=_equip_starter_weapon(session, "CROSSBOW")
	check(bool(crossbow_equip.get("accepted",false)), "crossbow equips: %s" % crossbow_equip)
	var crossbow_actor:=_observed_protagonist(session)
	check_eq(str((crossbow_actor.get("equipment_visual",{}) as Dictionary).get("weapon_id","")),
		"CROSSBOW","second weapon swap immediately refreshes the actor observation")
	check_eq(session.protagonist_equipment().attack_block_reason, "reload_required",
		"crossbow blocks until reload")
	check(session.reload_protagonist_weapon().accepted, "crossbow reload API")
	check(session.protagonist_equipment().loaded, "crossbow is loaded")
	var restored = Session.new(1, 2, Session.SOLO_COMBAT_SCENARIO_ID)
	var loaded: Dictionary = restored.load_session_json(session.save_session_json())
	check(loaded.accepted, "equipment journal loads: %s" % loaded)
	if loaded.accepted:
		check_eq(restored.save_session_json(), session.save_session_json(),
			"equipment journal and snapshot replay exact")
	return finish()


func test_equipment_session_stays_ready_after_auto_opening_and_user_commands()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var state=session.sim.world.party_encounter
	state.party_detection_radius=0;state.enemy_detection_radius=0
	for enemy_id in state.enemy_ids:state.enemy_busy_rows[enemy_id]=1000000
	var anchors:Dictionary=load("res://playtest/deterministic_dungeon_map.gd") \
		.opening_event_anchors(session._map_layout,session.world_seed)
	var route:Array=anchors.get("entry_exit_path",[])
	var stop_index:=int(anchors.get("spawn_route_index",-1))
	for index in range(1,mini(route.size(),stop_index+1)):
		if bool(session.opening_event_status().get("can_interact",false)):break
		var moved:Dictionary=session.commit_exploration(
			Command.move_to(int(state.protagonist_id),route[index]))
		if not bool(moved.get("accepted",false)):break
	var auto:Dictionary=session.start_auto_explore()
	check_eq(str(auto.get("stop_reason","")),"auto_explore_interaction_discovered",
		"AUTO recognizes the fixed NPC interaction before equipment regression")
	var gave:Dictionary=session.commit_opening_event_choice("GIVE_POTION")
	check(bool(gave.get("accepted",false)),"potion handoff remains canonical")
	var resumed:Dictionary=session.start_auto_explore()
	if bool(resumed.get("running",false)):
		session.cancel_auto_explore("auto_explore_user_command")
	# Exercise a rejected inventory command too: neither it nor AUTO cancellation
	# may invalidate the live simulator used by the next real equipment swap.
	var rejected:Dictionary=session.equip_inventory_item("MISSING_ITEM","MAIN_HAND")
	check(not bool(rejected.get("accepted",false)),"missing gear is a clean rejection")
	var equipped:Dictionary=session.equip_inventory_item("START_HAND_AXE_001","MAIN_HAND")
	check(session.sim!=null and session.sim.world!=null \
			and str(equipped.get("reason",""))!="session_not_initialized" \
			and bool(equipped.get("accepted",false)),
		"AUTO, potion, cancellation, and rejection cannot detach the equipment session: %s" \
			%equipped)
	return finish()


func test_equipment_replaces_a_staged_combat_action_instead_of_returning_generic_failure()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	check(_enter_solo_combat(session),"equipment draft fixture reaches solo combat")
	if str(session.party_status().get("safe_phase",""))!="ENGAGED":return finish()
	var hero_id:=int(session.party_status().protagonist_id)
	var draft:Dictionary=session.begin_turn(PartyAction.hold(hero_id))
	check(bool(draft.get("accepted",false)),"a real protagonist action is staged first")
	var equipped:Dictionary=session.equip_inventory_item("START_HAND_AXE_001","MAIN_HAND")
	check(bool(equipped.get("accepted",false)) \
			and str(session.protagonist_equipment().weapon_id)=="HAND_AXE",
		"explicit equipment change replaces the staged action: %s"%equipped)
	check(not bool(session.auto_combat_planning_state().get("active",false)),
		"successful equipment turn leaves no stale combat draft")
	return finish()


func test_item_tab_replaces_equipment_from_item_popover()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var sandbox=Sandbox.new();sandbox.size=Vector2(360,640)
	sandbox.initialize_for_headless_test(session,true)
	sandbox._open_hero_detail();sandbox._select_member_detail_tab("ITEM")
	sandbox._on_item_row_selected("START_HAND_AXE_001","")
	var replace:=sandbox.member_item_equip_button as Button
	check(sandbox.member_item_popover.visible and replace!=null and not replace.disabled \
			and replace.text=="[교체]" and replace.custom_minimum_size.y>=44.0 \
			and "현재 주무기" in sandbox.member_item_popover_compare.text,
		"selecting carried gear opens a touch-sized comparison/replacement popover")
	if replace!=null:replace.pressed.emit()
	var state=session.sim.world.party_encounter
	var inventory=session.sim.world.inventory_of(state.protagonist_id)
	check_eq([str(inventory.equipped.MAIN_HAND),
		inventory.unequipped_items().map(func(item):return item.instance_id).has("LEGACY_MAIN_HAND"),
		str(session.protagonist_equipment().weapon_id)],
		["START_HAND_AXE_001",true,"HAND_AXE"],
		"popover replacement equips the new item and returns the old one to the bag")
	check("변경" in sandbox.notice_text,"replacement reports immediate visible feedback")
	sandbox.free();return finish()


func test_weapon_rows_explain_species_requirements_and_failed_equip()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID,"elf")
	var axe_row:Dictionary={}
	for row in session.protagonist_inventory().backpack_rows:
		if str(row.get("definition_id",""))=="WEAPON_HAND_AXE":axe_row=row;break
	check(not axe_row.is_empty() and not bool(axe_row.requirements_met) \
		and str(axe_row.requirement_text)=="STR 5" \
		and int(axe_row.current_stats.STR)==3,
		"weapon row exposes the exact unmet species requirement")
	var sandbox=Sandbox.new();sandbox.size=Vector2(360,640)
	sandbox.initialize_for_headless_test(session,true)
	sandbox._open_hero_detail();sandbox._select_member_detail_tab("ITEM")
	sandbox._on_item_row_selected("START_HAND_AXE_001","")
	var equip:=sandbox.member_item_equip_button as Button
	check(sandbox.member_item_popover.visible and equip!=null \
		and equip.text=="[장착 불가]" and "STR 5" in sandbox.member_item_popover_body.text,
		"weapon popover explains why it cannot equip")
	if equip!=null:equip.pressed.emit()
	check(str(session.protagonist_equipment().weapon_id)=="SHORT_SWORD" \
		and "필요 능력치" in sandbox.notice_text,
		"failed weapon equip preserves equipment and gives a visible reason")
	sandbox.free();return finish()


func test_ranged_combat_controls_expose_shoot_and_crossbow_reload()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	check(_equip_starter_weapon(session,"CROSSBOW").accepted,
		"ranged control fixture equips crossbow")
	check(_enter_solo_combat(session),"ranged control fixture enters combat")
	var sandbox=Sandbox.new();sandbox.size=Vector2(360,640)
	sandbox.initialize_for_headless_test(session,true)
	sandbox._sync_product_control_state()
	check(sandbox.product_attack_button.text=="[사격]" \
		and sandbox.product_interact_button.text=="[RELOAD]" \
		and not sandbox.product_interact_button.disabled,
		"crossbow publishes shoot and enabled reload controls in combat")
	var before:=session.save_session_json()
	sandbox._on_product_attack()
	check_eq(session.save_session_json(),before,
		"unloaded shoot consumes no action")
	check("[RELOAD]" in sandbox.notice_text,
		"unloaded shoot directs the player to the reload control")
	sandbox._on_product_interact()
	check(bool(session.protagonist_equipment().loaded),
		"combat reload control updates authoritative crossbow state")
	check(sandbox.product_interact_button.disabled,
		"loaded crossbow disables redundant combat reload")
	check("재장전" in sandbox.notice_text,
		"combat reload gives immediate visible feedback")
	sandbox.free();return finish()


func test_crossbow_after_shot_reload_preserves_live_combat_session_and_ui()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	check(_equip_starter_weapon(session,"CROSSBOW").accepted,
		"after-shot reload fixture equips crossbow")
	check(_enter_solo_combat(session),"after-shot reload fixture enters combat")
	if str(session.party_status().get("safe_phase",""))!="ENGAGED":return finish()
	var state=session.sim.world.party_encounter
	var hero_id:=int(state.protagonist_id)
	var enemy_id:=int(state.enemy_ids[0])
	check(session.reload_protagonist_weapon().accepted,"fixture loads its first bolt")
	var shot_preview:Dictionary=session.preview_actor_action(hero_id,"MELEE",[],enemy_id)
	check(bool(shot_preview.get("accepted",false)),
		"contact enemy begins inside the crossbow firing envelope: %s"%shot_preview)
	var shot:Dictionary=session.commit_direct_solo_action(hero_id,"MELEE",[],enemy_id)
	check(bool(shot.get("accepted",false)),"crossbow shot commits before reload: %s"%shot)
	check(not bool(session.protagonist_equipment().loaded),
		"committed crossbow shot consumes the loaded state")
	check_eq(session.sim.world.world_state_error(),"",
		"crossbow shot leaves a serializable settled world before reload")
	var sandbox=Sandbox.new();sandbox.size=Vector2(360,640)
	sandbox.initialize_for_headless_test(session,true)
	var live_reload_button:Button=sandbox.product_interact_button
	sandbox._on_product_interact()
	var after_status:Dictionary=session.party_status()
	check(session.sim!=null and session.sim.world!=null \
			and str(after_status.get("safe_phase",""))=="ENGAGED" \
			and not bool(session.run_progress().get("terminal",false)),
		"after-shot reload cannot terminate or detach the combat session")
	check(bool(session.protagonist_equipment().loaded) \
			and sandbox.product_interact_button==live_reload_button \
			and sandbox.product_interact_button.disabled,
		"after-shot reload keeps the stable combat UI and disables repeat reload: %s / %s" \
			%[session.protagonist_equipment(),sandbox.notice_text])
	check("재장전" in sandbox.notice_text \
			and session.sim.world.world_state_error().is_empty(),
		"after-shot reload reports success and leaves authoritative state valid")
	sandbox.free();return finish()


func test_product_pickup_button_collects_the_current_tile_without_an_empty_turn()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	check(session.drop_inventory_item("START_POTION_001").accepted,
		"pickup button fixture drops one canonical instance on the hero tile")
	var sandbox=Sandbox.new();sandbox.size=Vector2(360,640)
	sandbox.initialize_for_headless_test(session,true)
	check(sandbox.product_pickup_button!=null \
			and sandbox.product_pickup_button.text=="[줍기]" \
			and sandbox.product_pickup_button.custom_minimum_size.y>=32.0,
		"D-pad context rail exposes a real touch-sized pickup button")
	var pickup_time:=int(session.sim.world.world_time)
	var pickup_journal_size:int=session.command_journal.size()
	sandbox._activate_product_control("ProductPickup")
	check_eq([session.ground_items_at_protagonist().size(),
		int(session.sim.world.world_time),session.command_journal.size(),
		str(session.command_journal[-1].operation.action)],
		[0,pickup_time+100,pickup_journal_size+1,"PICKUP"],
		"pickup button uses the canonical timed item transaction and journal")
	check("가방에 주웠습니다" in sandbox.notice_text,
		"successful button pickup is immediately visible")
	var empty_snapshot:Dictionary=session.sim.snapshot()
	var empty_journal:Array=session.command_journal.duplicate(true)
	sandbox._activate_product_control("ProductPickup")
	check_eq([session.sim.snapshot(),session.command_journal],[empty_snapshot,empty_journal],
		"pressing pickup on an empty tile consumes no turn and writes no journal row")
	check("주울 아이템이 없습니다" in sandbox.notice_text,
		"empty pickup explains why nothing happened")
	sandbox.free();return finish()


func test_entering_ground_item_tile_reports_its_name_in_product_log()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var state=session.sim.world.party_encounter
	state.party_detection_radius=0;state.enemy_detection_radius=0
	for enemy_id in state.enemy_ids:state.enemy_busy_rows[enemy_id]=1000000
	var hero=session.sim.world.entities[state.protagonist_id]
	var item_position:Vector2i=hero.position
	check(session.drop_inventory_item("START_POTION_001").accepted,
		"arrival notice fixture drops a named item")
	var moved_away:=false
	for direction in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,
			Vector2i(1,-1),Vector2i(1,1),Vector2i(-1,1),Vector2i(-1,-1)]:
		var move:Dictionary=session.commit_exploration_direction(direction)
		if bool(move.get("accepted",false)):moved_away=true;break
	check(moved_away,"arrival notice fixture can leave the item tile")
	if not moved_away:return finish()
	var sandbox=Sandbox.new();sandbox.size=Vector2(360,640)
	sandbox.initialize_for_headless_test(session,true)
	var current:Vector2i=session.sim.world.entities[state.protagonist_id].position
	sandbox._on_explore(item_position-current)
	check("바닥 아이템" in sandbox.notice_text and "회복 물약" in sandbox.notice_text \
			and "[줍기]" in sandbox.notice_text,
		"stepping onto loot prints its exact name and pickup affordance: %s"%sandbox.notice_text)
	check("회복 물약" in sandbox.event_label.text,
		"the compact product event log receives the same arrival notice: %s" \
			%sandbox.event_label.text)
	sandbox.free();return finish()


func test_short_sword_preview_and_commit_use_weapon_formula_and_position_pair_vfx() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	check(_enter_solo_combat(session), "solo reaches combat")
	if session.party_status().safe_phase != "ENGAGED": return finish()
	var captured: Dictionary = {}
	for _turn in range(48):
		var status: Dictionary = session.party_status()
		if status.safe_phase != "ENGAGED": break
		var hero := int(status.protagonist_id)
		var enemy := int(session.sim.world.party_encounter.enemy_ids[0])
		var preview: Dictionary = session.set_actor_action(hero, "MELEE", [], enemy)
		if preview.accepted:
			for row in preview.actor_rows:
				if int(row.actor_id) == hero: captured = row.combat_assessment
			check_eq([captured.get("schema_version"), captured.get("weapon_id"),
				captured.get("attack_form"), captured.get("attack_time")],
				[2, "SHORT_SWORD", "SLASH", 100], "weapon assessment reaches draft")
			var result: Dictionary = session.commit_turn()
			check(result.accepted, "weapon attack commits: %s" % result)
			if result.accepted:
				var attack_events: Array = session.sim.world.events.filter(
					func(event): return str(event.type) == "action.melee_attack" \
						and int(event.actor_id) == hero)
				check(not attack_events.is_empty() \
					and int(attack_events[-1].data.bleed_roll_milli) >= 0,
					"weapon attack records a valid deterministic BLEED roll")
				var vfx_rows:Array=result.visual_effects.filter(
					func(row):return str(row.kind)=="MELEE_VFX")
				if str(attack_events[-1].data.outcome) in ["HIT","FINISHER"]:
					# A committed turn may also contain an enemy counterattack. Match the
					# historical attack event rather than assuming one VFX row per turn.
					var historical_vfx:Array=vfx_rows.filter(func(row):
						return int(row.get("event_id",-1))==int(attack_events[-1].id))
					check(historical_vfx.size()==1 \
						and historical_vfx[0].attacker_grid_pos is Array \
						and historical_vfx[0].target_grid_pos==[
							attack_events[-1].position.x,attack_events[-1].position.y],
						"committed hit carries one exact historical position pair")
					if historical_vfx.size()==1:
						check(not historical_vfx[0].has("glyph") \
							and not historical_vfx[0].has("attack_form"),
							"session VFX row carries no inline slash glyph grammar")
				else:
					check(vfx_rows.is_empty(),"miss produces no melee VFX")
				check_eq(session.sim.world.world_state_error(), "", "weapon event history validates")
			return finish()
		var path: Dictionary = session.sim.party_coordinator.pathfinder.find_path_to_any(
			hero, _adjacent_open_cells(session, enemy))
		if bool(path.get("found", false)) and path.path.size() >= 2:
			var step: Vector2i = path.path[1]
			preview = session.set_actor_action(hero, "MOVE", [step.x, step.y])
		else:
			preview = session.set_actor_action(hero, "HOLD")
		if not preview.accepted or not session.commit_turn().accepted: break
	check(false, "short sword attack was never available")
	return finish()


func test_spear_and_bow_preview_at_real_weapon_range() -> bool:
	var spear_session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	check(_equip_starter_weapon(spear_session, "SPEAR").accepted,
		"spear equips before combat")
	check(_enter_solo_combat(spear_session), "spear fixture reaches combat")
	if spear_session.party_status().safe_phase != "ENGAGED": return finish()
	var spear_hero := int(spear_session.party_status().protagonist_id)
	var spear_active:Array[int]=CampaignEncounterStream.active_enemy_ids(
		spear_session.sim.world)
	check(not spear_active.is_empty(),"spear fixture exposes one active encounter group")
	if spear_active.is_empty():return finish()
	var spear_enemy := int(spear_active[0])
	check(_place_enemy_on_open_line(spear_session, spear_enemy, 2),
		"open two-cell spear line exists")
	var spear_preview: Dictionary = spear_session.preview_actor_action(
		spear_hero, "MELEE", [], spear_enemy)
	check(bool(spear_preview.get("accepted", false)),
		"SPEAR preview accepts an enemy two cells away: %s" % spear_preview)
	if bool(spear_preview.get("accepted", false)):
		var spear_assessment: Dictionary = spear_preview.actor_rows[0].combat_assessment
		check_eq([spear_assessment.weapon_id, spear_assessment.range_max,
			spear_assessment.attack_time], ["SPEAR", 2, 110],
			"spear preview uses weapon range and intrinsic time")
	var bow_session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	check(_equip_starter_weapon(bow_session, "BOW").accepted, "bow equips before combat")
	check(_enter_solo_combat(bow_session), "bow fixture reaches combat")
	if bow_session.party_status().safe_phase != "ENGAGED": return finish()
	var bow_hero := int(bow_session.party_status().protagonist_id)
	var bow_active:Array[int]=CampaignEncounterStream.active_enemy_ids(
		bow_session.sim.world)
	check(not bow_active.is_empty(),"bow fixture exposes one active encounter group")
	if bow_active.is_empty():return finish()
	var bow_enemy := int(bow_active[0])
	check(_place_enemy_on_open_line(bow_session, bow_enemy, 3),
		"open three-cell bow line exists")
	var bow_preview: Dictionary = bow_session.preview_actor_action(
		bow_hero, "MELEE", [], bow_enemy)
	check(bool(bow_preview.get("accepted", false)),
		"BOW preview accepts a clear ranged target: %s" % bow_preview)
	if bool(bow_preview.get("accepted", false)):
		var bow_assessment: Dictionary = bow_preview.actor_rows[0].combat_assessment
		check_eq([bow_assessment.weapon_id, bow_assessment.range_min,
			bow_assessment.range_max, bow_assessment.attack_time], ["BOW", 2, 8, 90],
			"bow preview uses ranged limits and intrinsic time")
	return finish()


func test_skill_and_item_tabs_separate_training_from_real_equipment() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var sandbox = Sandbox.new()
	sandbox.size = Vector2(450, 800)
	sandbox.initialize_for_headless_test(session, true)
	sandbox._open_hero_detail()
	sandbox._select_member_detail_tab("SKILL")
	sandbox._toggle_weapon_mastery_category()
	check_eq(sandbox.member_progression_skill_rows.keys().size(), 6,
		"six fixed proficiency ledger rows")
	check("장착 숙련 · 단검" in sandbox.member_progression_stats.text \
		and "장비는 아이템 탭" in sandbox.member_progression_stats.text \
		and sandbox.member_skill_help.text=="행 터치: 집중×3 → 보통×1 → 끄기×0",
		"skill tab identifies the equipped proficiency while training stays independent")
	check(sandbox.find_child("SkillDetail",true,false)==null \
		and sandbox.find_child("TrainingProgress",true,false)==null \
		and sandbox.find_child("FutureMilestone",true,false)==null,
		"fixed ledger removes expandable detail, progress gauge, and future copy")
	for skill_id in ["SWORD","AXE","BLUNT","SPEAR","RANGED","UNARMED"]:
		var row:Dictionary=sandbox.member_progression_skill_rows[skill_id]
		var panel:PanelContainer=row.panel;var ledger:=panel.find_child("SkillLedgerRow",false,false)
		var rank:Label=row.rank;var skill_name:Label=row.name;var effect:Label=row.effect
		var mode:Label=row.mode;var xp:Label=row.xp
		check(panel.visible and bool(panel.get_meta("fixed_single_line_ledger",false)) \
			and ledger!=null,"%s is one visible fixed ledger row"%skill_id)
		check(rank.text.begins_with("R") and not skill_name.text.is_empty() \
			and "명중" in effect.text and "피해" in effect.text,
			"%s row shows rank, name, and current combat effect"%skill_id)
		check("×" in mode.text and mode.horizontal_alignment==HORIZONTAL_ALIGNMENT_RIGHT \
			and "/" in xp.text and xp.horizontal_alignment==HORIZONTAL_ALIGNMENT_RIGHT \
			and ledger.get_child(ledger.get_child_count()-1)==xp,
			"%s row ends with mode multiplier and current XP"%skill_id)
	sandbox._select_member_detail_tab("ITEM")
	check("장착" not in sandbox.member_item_weapon_text.text \
		and "공격" in sandbox.member_item_weapon_text.text \
		and "방어" in sandbox.member_item_weapon_text.text \
		and "회피" in sandbox.member_item_weapon_text.text \
		and "막기" in sandbox.member_item_weapon_text.text,
		"item tab owns equipment and the compact combat summary")
	sandbox._select_member_detail_tab("STATUS")
	sandbox._on_item_row_selected("LEGACY_MAIN_HAND","MAIN_HAND")
	check(sandbox.member_item_popover.visible and sandbox.member_item_unequip_button.visible \
		and not sandbox.member_item_unequip_button.disabled \
		and "단검" in sandbox.member_item_popover_title.text,
		"selecting status equipment opens its touch-sized unequip popover")
	sandbox.member_item_quick_unequip_button.pressed.emit()
	check(bool(session.protagonist_inventory().equipment_slots[0].empty) \
		and not sandbox.member_item_popover.visible \
		and sandbox.member_detail_current_tab=="STATUS" \
		and "단검" in JSON.stringify(session.protagonist_inventory().backpack_rows),
		"popover unequip commits, refreshes equipment, and preserves the status tab")
	sandbox.free()
	var crossbow_session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	check(_equip_starter_weapon(crossbow_session, "CROSSBOW").accepted,
		"crossbow UI fixture equips")
	var crossbow_ui=Sandbox.new();crossbow_ui.size=Vector2(360,640)
	crossbow_ui.initialize_for_headless_test(crossbow_session,true)
	crossbow_ui._open_hero_detail();crossbow_ui._select_member_detail_tab("ITEM")
	check(crossbow_ui.member_item_reload_button.visible \
		and not crossbow_ui.member_item_reload_button.disabled \
		and crossbow_ui.member_item_reload_button.custom_minimum_size.y>=44,
		"reloadable item exposes an enabled touch-sized reload button")
	crossbow_ui._on_item_reload()
	check("장전됨" in crossbow_ui.member_item_ammo_text.text,
		"item reload action refreshes authoritative load state")
	crossbow_ui.free()
	return finish()


func _equip_starter_weapon(session,weapon_id:String)->Dictionary:
	var instance_id:=str(STARTER_WEAPON_INSTANCE_IDS.get(weapon_id,""))
	if instance_id.is_empty():return {"accepted":false,"reason":"unknown_starter_weapon"}
	var unequipped:Dictionary=session.unequip_inventory_slot("MAIN_HAND")
	if not bool(unequipped.get("accepted",false)):return unequipped
	return session.equip_inventory_item(instance_id,"MAIN_HAND")


func _observed_protagonist(session)->Dictionary:
	var grid:Dictionary=session.observe_party_ui(15).get("grid",{})
	for cell in grid.get("cells",[]):
		for actor in cell.get("actors",[]):
			if bool(actor.get("is_protagonist",false)):return actor
	return {}


func _enter_solo_combat(session) -> bool:
	if session.sim == null: return false
	var hero_id:=int(session.sim.world.party_encounter.protagonist_id)
	for _step in range(256):
		if session.party_status().safe_phase=="CONTACT":break
		var enemy_id:=int(session.sim.world.party_encounter.enemy_ids[0])
		var path:Dictionary=session.sim.party_coordinator.pathfinder.find_path_to_any(
			hero_id,_adjacent_open_cells(session,enemy_id))
		if not bool(path.get("found",false)) or path.path.size()<2:return false
		var next_position:Vector2i=path.path[1]
		if not session.commit_exploration(Command.move_to(hero_id,next_position)).accepted:return false
	if session.party_status().safe_phase != "CONTACT":return false
	var entered:Dictionary=session.enter_solo_combat()
	return bool(entered.get("accepted", false))


func _adjacent_open_cells(session, entity_id: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var origin: Vector2i = session.sim.world.entities[entity_id].position
	for direction_value in session.sim.movement.MOVE_DIRECTIONS_8:
		var direction:Vector2i=direction_value
		var position:Vector2i = origin + direction
		if not session.sim.world.in_bounds(position): continue
		var tile = session.sim.world.tile_at(position)
		if bool(load("res://sim/terrain_registry.gd").definition(tile.terrain).get("passable", false)):
			result.append(position)
	result.sort_custom(func(a:Vector2i,b:Vector2i):
		return a.y < b.y if a.y != b.y else a.x < b.x)
	return result


func _place_enemy_on_open_line(session, enemy_id: int, distance: int) -> bool:
	var hero_id := int(session.sim.world.party_encounter.protagonist_id)
	var hero_position: Vector2i = session.sim.world.entities[hero_id].position
	for direction_value in session.sim.movement.MOVE_DIRECTIONS_8:
		var direction: Vector2i = direction_value
		var candidate := hero_position + direction * distance
		if not session.sim.world.in_bounds(candidate): continue
		var clear := true
		for step in range(1, distance + 1):
			var position := hero_position + direction * step
			var terrain: Dictionary = load("res://sim/terrain_registry.gd").definition(
				session.sim.world.tile_at(position).terrain)
			if not bool(terrain.get("passable", false)):
				clear = false
				break
			for entity_id in session.sim.world.entities:
				if int(entity_id) not in [hero_id, enemy_id] \
						and session.sim.world.entities[entity_id].position == position \
						and session.sim.world.occupies_tile(int(entity_id)):
					clear = false
					break
			if not clear: break
		if clear:
			return _relocate_with_move_events(session.sim,enemy_id,candidate)
	return false


func _relocate_with_move_events(sim,entity_id:int,target:Vector2i)->bool:
	var route:Dictionary=sim.find_path(entity_id,target)
	if not bool(route.get("found",false)):return false
	for index in range(1,route.path.size()):
		var destination:Vector2i=route.path[index]
		var assessment=sim.movement.assess_move(entity_id,destination)
		if not bool(assessment.accepted):return false
		var definition:Dictionary=load("res://sim/terrain_registry.gd").definition(
			str(assessment.terrain_id))
		if sim.movement.commit_preflighted_move(entity_id,destination,
				str(assessment.terrain_id),int(definition.move_time_cost))==null:
			return false
	return sim.world.entities[entity_id].position==target
