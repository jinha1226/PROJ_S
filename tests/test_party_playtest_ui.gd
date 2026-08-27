extends "res://tests/test_case.gd"

const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
const Command=preload("res://sim/sim_command.gd")
const TerrainRegistry=preload("res://sim/terrain_registry.gd")

func test_same_grid_instance_and_mapping_survive_phase_change() -> bool:
	var sandbox=Sandbox.new(); sandbox.size=Vector2(450,800); sandbox.initialize_for_headless_test(Session.new())
	var id=sandbox.grid.get_instance_id(); var mapping=sandbox.grid.mapping_signature()
	var hero=sandbox.session.sim.world.party_encounter.protagonist_id; sandbox.session.commit_exploration(Command.wait(hero)); sandbox._refresh()
	check_eq(sandbox.grid.get_instance_id(),id,"same grid")
	check_eq(sandbox.grid.mapping_signature(),mapping,"same coordinate mapping")
	sandbox.free(); return finish()

func test_actor_hit_rect_is_at_least_28_and_outside_input_has_no_actor() -> bool:
	var sandbox=Sandbox.new(); sandbox.size=Vector2(360,640); sandbox.initialize_for_headless_test(Session.new())
	var hero=sandbox.session.sim.world.party_encounter.protagonist_id; var rect=sandbox.grid.actor_hit_rect(hero)
	check(rect.size.x>=44 and rect.size.y>=44,"actor hit target")
	check_eq(sandbox.grid.actor_at_pointer(Vector2(-100,-100)),-1,"outside no actor")
	sandbox.grid.modal_open=true; check(sandbox.grid.modal_open,"modal gate")
	sandbox.free(); return finish()

func test_each_formation_uses_visible_button_preview_ghosts_and_confirm_to_engaged() -> bool:
	for preset in ["WEDGE","LINE","COLUMN"]:
		var sandbox=Sandbox.new(); sandbox.size=Vector2(450,800); sandbox.initialize_for_headless_test(Session.new())
		var grid_id=sandbox.grid.get_instance_id(); var mapping=sandbox.grid.mapping_signature()
		var actor_count:=0; for cell in sandbox.session.observe_party_world().cells: actor_count += cell.actors.size()
		check_eq(actor_count,1,"%s enemies hidden before contact"%preset)
		_press(sandbox,"ExploreHold")
		check_eq(sandbox.session.party_status().safe_phase,"CONTACT","%s contact"%preset)
		actor_count=0; for cell in sandbox.session.observe_party_world().cells: actor_count += cell.actors.size()
		check_eq(actor_count,2,"%s enemy revealed at contact"%preset)
		var initial_confirm:Button=_button(sandbox,"DeployConfirm"); check(initial_confirm.disabled,"confirm disabled before preset")
		sandbox._on_deploy_confirm(); sandbox._refresh(); check("먼저" in str(sandbox.find_child("ActionStatus",true,false).text),"visible confirm rejection")
		_press(sandbox,"Preset%s"%preset)
		check_eq(sandbox.session.deployment_draft().preset_id,preset,"preset selection stored")
		check_eq(sandbox.grid._ghosts.size(),2,"companion ghost tokens")
		check(_button(sandbox,"Preset%s"%preset).button_pressed,"selected preset feedback")
		check(not _button(sandbox,"DeployConfirm").disabled,"valid confirm enabled")
		_press(sandbox,"DeployConfirm")
		check_eq(sandbox.session.party_status().safe_phase,"ENGAGED","%s button journey engaged"%preset)
		check("빈 칸=이동, 적=공격" in str(sandbox.find_child("ActionStatus",true,false).text), "%s combat instruction visible immediately"%preset)
		check_eq(sandbox.session.party_status().formation_id,preset,"formation committed")
		check_eq(sandbox.grid.get_instance_id(),grid_id,"same grid for %s"%preset)
		check_eq(sandbox.grid.mapping_signature(),mapping,"same mapping for %s"%preset)
		sandbox.free()
	return finish()

func test_screen_touch_routes_exact_world_cells_at_both_portrait_sizes() -> bool:
	for viewport_size in [Vector2(360,640), Vector2(450,800)]:
		var sandbox = _engaged_sandbox("COLUMN", viewport_size)
		# This synchronous unit runner does not enter the scene tree, so containers do
		# not perform a layout pass. Give the real grid its portrait-budgeted extent;
		# the viewport smoke exercises the same routing after a live layout pass.
		sandbox.grid.size = sandbox.grid.custom_minimum_size
		var status: Dictionary = sandbox.session.party_status(); var hero := int(status.protagonist_id)
		_press(sandbox, "MemberCard%d" % hero)
		var hero_position := _card_position(sandbox, hero); var legal_count := 0
		for direction in [Vector2i.UP,Vector2i(1,-1),Vector2i.RIGHT,Vector2i(1,1),Vector2i.DOWN,Vector2i(-1,1),Vector2i.LEFT,Vector2i(-1,-1)]:
			var destination: Vector2i = hero_position + direction
			if not sandbox.session.sim.assess_move(hero, destination).accepted: continue
			legal_count += 1; _screen_touch(sandbox, destination); sandbox._refresh()
			var preview: Dictionary = sandbox.session.current_turn_preview()
			check(bool(preview.get("accepted", false)), "%s empty-cell touch creates accepted MOVE (%s)" % [viewport_size, preview.get("reason", "missing")])
			var rows: Array = preview.get("actor_rows", [])
			if not rows.is_empty():
				check_eq(rows[0].action.type, "MOVE", "%s exact empty cell is not stolen by 44px hero slop" % viewport_size)
				check_eq(rows[0].action.destination, [destination.x,destination.y], "%s touch MOVE destination exact" % viewport_size)
		check(legal_count > 0, "%s has legal adjacent touch regression cells" % viewport_size)
		var companion := int(status.party_member_ids[1]); _screen_touch(sandbox, _card_position(sandbox, companion)); sandbox._refresh()
		check_eq(sandbox.selected_member_id, companion, "%s party-cell touch selects member" % viewport_size)
		_screen_touch(sandbox, hero_position); sandbox._refresh()
		check_eq(sandbox.selected_member_id, hero, "%s protagonist cell reselects hero" % viewport_size)
		var enemy := int(status.visible_enemy_ids[0]); var enemy_position := Vector2i.ZERO
		for target in sandbox.session.enemy_targets():
			if int(target.entity_id) == enemy: enemy_position = Vector2i(int(target.position[0]),int(target.position[1])); break
		_screen_touch(sandbox, enemy_position); sandbox._refresh()
		check_eq(sandbox.selected_member_id, hero, "%s enemy-cell touch does not select enemy" % viewport_size)
		check_eq(sandbox.selected_target_id, enemy, "%s enemy-cell touch selects target" % viewport_size)
		var routed: Array = []; sandbox.grid.actor_pressed.connect(func(id): routed.append(id))
		var outside := InputEventScreenTouch.new(); outside.pressed = true
		outside.position = sandbox.grid.grid_rect().position + Vector2(-1.0, sandbox.grid.cell_size_px() * 0.5)
		sandbox.grid._gui_input(outside)
		check(routed.is_empty(), "%s touch outside grid never routes edge actor" % viewport_size)
		sandbox.free()
	return finish()

func test_member_cards_use_atlas_portraits_and_show_all_element_components() -> bool:
	var sandbox=Sandbox.new(); sandbox.size=Vector2(360,640); sandbox.initialize_for_headless_test(Session.new())
	for member_id in sandbox.session.party_status().party_member_ids:
		var card := _button(sandbox,"MemberCard%d"%int(member_id))
		var portrait := card.find_child("Portrait", true, false) as TextureRect
		check(portrait != null and portrait.texture is AtlasTexture, "member card has AtlasTexture portrait")
		var element_label := card.find_child("MemberElements", true, false) as Label
		for label in ["불","물","전","독"]:
			check(element_label != null and label in element_label.text, "card shows %s component"%label)
		check(card.find_child("MemberName", true, false) != null, "card has controlled name row")
		check(card.find_child("MemberState", true, false) != null, "card has HP/status/presence row")
		check(card.find_child("ExpectedAction", true, false) != null, "card has expected-action row")
	sandbox.free(); return finish()

func test_enemy_tap_targets_without_selecting_enemy_and_rejections_are_visible() -> bool:
	var sandbox=_engaged_sandbox("WEDGE"); var status:Dictionary=sandbox.session.party_status()
	var hero:=int(status.protagonist_id); var enemy:=int(status.visible_enemy_ids[0])
	check_eq(sandbox.selected_member_id,hero,"hero initially selected")
	sandbox._on_actor(enemy)
	sandbox._refresh()
	check_eq(sandbox.selected_member_id,hero,"enemy tap never selects enemy")
	check_eq(sandbox.selected_target_id,enemy,"enemy target highlighted")
	check(_button(sandbox,"OverrideClear").disabled,"enemy tap does not expose companion override")
	check("공격" in str(sandbox.find_child("ActionStatus",true,false).text),"illegal enemy tap reason visible")
	_press(sandbox,"ActorHold"); check(bool(sandbox.session.current_turn_preview().accepted),"hero draft via hold")
	var companion:=int(status.party_member_ids[1]); _press(sandbox,"MemberCard%d"%companion)
	var companion_row:Dictionary
	for row in sandbox.session.party_cards(): if int(row.entity_id)==companion: companion_row=row
	var destination:=[int(companion_row.logical_position[0])+1,int(companion_row.logical_position[1])]
	sandbox._on_cell(Vector2i(destination[0],destination[1]))
	sandbox._refresh()
	var overridden:Dictionary
	for row in sandbox.session.party_cards(): if int(row.entity_id)==companion: overridden=row
	check(overridden.expected_action is Dictionary and overridden.expected_action.source=="OVERRIDE","companion move override")
	check("지정" in str(overridden.expected_action.text),"override Korean label")
	_press(sandbox,"ActorHold")
	for row in sandbox.session.party_cards(): if int(row.entity_id)==companion: overridden=row
	check_eq(overridden.expected_action.type,"HOLD","selected companion HOLD override")
	_press(sandbox,"OverrideClear")
	for row in sandbox.session.party_cards(): if int(row.entity_id)==companion: overridden=row
	check_eq(overridden.expected_action.source,"SUGGESTED","clear restores automatic suggestion")
	sandbox.free(); return finish()

func test_same_grid_survives_combat_regroup_complete_and_post_regroup_move() -> bool:
	var sandbox=_engaged_sandbox("LINE"); var grid_id=sandbox.grid.get_instance_id(); var mapping=sandbox.grid.mapping_signature()
	var status:Dictionary=sandbox.session.party_status(); var hero:=int(status.protagonist_id); var enemy:=int(status.visible_enemy_ids[0])
	check(_relocate_with_move_events(sandbox.session.sim, enemy,
		sandbox.session.sim.world.entities[hero].position + Vector2i.RIGHT), "UI enemy canonical relocation")
	sandbox.session.sim.world.entities[enemy].health=22; sandbox._refresh()
	sandbox._on_actor(enemy); sandbox._refresh(); check(bool(sandbox.session.current_turn_preview().accepted),"enemy tap creates hero melee")
	_press(sandbox,"TurnConfirm"); check_eq(sandbox.session.party_status().safe_phase,"REGROUP_READY","victory via UI turn confirm")
	check_eq(sandbox.grid.get_instance_id(),grid_id,"grid survives combat")
	_press(sandbox,"RegroupConfirm"); check_eq(sandbox.session.party_status().safe_phase,"GROUPED_COMPLETE","UI regroup")
	check_eq(sandbox.session.party_status().contact_kind,"NONE","stale contact cleared")
	check_eq(sandbox.session.party_status().formation_id,"NONE","stale formation cleared")
	var old_anchor:Array=sandbox.session.party_status().anchor
	_press(sandbox,"ExploreW"); check(sandbox.session.party_status().anchor!=old_anchor,"post-regroup UI move")
	check_eq(sandbox.grid.get_instance_id(),grid_id,"grid survives regroup move")
	check_eq(sandbox.grid.mapping_signature(),mapping,"mapping survives full journey")
	sandbox.free(); return finish()

func test_terminal_defeat_and_atlas_touch_tie_break_are_explicit() -> bool:
	var session=Session.new(); var state=session.sim.world.party_encounter; session.sim.world.entities[state.protagonist_id].health=5
	check(session.sim.world.bootstrap_set_fire(state.group_anchor,100)!=null,"defeat fire")
	session.commit_exploration(Command.wait(state.protagonist_id))
	var sandbox=Sandbox.new(); sandbox.size=Vector2(360,640); sandbox.initialize_for_headless_test(session)
	check_eq(sandbox.session.party_status().safe_phase,"PARTY_DEFEATED","terminal phase")
	check(sandbox.find_child("TerminalOverlay",true,false)!=null,"terminal overlay visible")
	check(sandbox.find_child("TurnConfirm",true,false)==null,"terminal turn confirm hidden")
	check(sandbox.grid.CHARACTER_ATLAS!=null,"existing character atlas loaded")
	var observation={"cells":[{"position":[7,7],"terrain_id":"floor","actors":[
		{"entity_id":10,"is_protagonist":false,"roster_slot":1,"faction_id":"party","sprite_frame":4},
		{"entity_id":11,"is_protagonist":true,"roster_slot":0,"faction_id":"party","sprite_frame":0}]}]}
	sandbox.grid.set_observation(observation); var center=sandbox.grid.world_to_pixel_center(Vector2i(7,7))
	check_eq(sandbox.grid.actor_at_pointer(center),11,"overlap tie favors protagonist")
	check_eq(sandbox.grid.actor_hit_rect(11).size,Vector2(44,44),"44 square actor hit target")
	sandbox.free(); return finish()

func _engaged_sandbox(preset:String, viewport_size: Vector2 = Vector2(450,800)):
	var sandbox=Sandbox.new(); sandbox.size=viewport_size; sandbox.initialize_for_headless_test(Session.new())
	_press(sandbox,"ExploreHold"); _press(sandbox,"Preset%s"%preset); _press(sandbox,"DeployConfirm")
	return sandbox

func _button(root:Node,node_name:String)->Button:
	return root.find_child(node_name,true,false) as Button

func _press(root, node_name:String) -> void:
	_button(root,node_name).pressed.emit(); root._refresh()

func _screen_touch(sandbox, position: Vector2i) -> void:
	var event := InputEventScreenTouch.new(); event.pressed = true; event.position = sandbox.grid.world_to_pixel_center(position)
	sandbox.grid._gui_input(event)

func _card_position(sandbox, entity_id: int) -> Vector2i:
	for row in sandbox.session.party_cards():
		if int(row.entity_id) == entity_id: return Vector2i(int(row.logical_position[0]),int(row.logical_position[1]))
	return Vector2i(-1,-1)

func _relocate_with_move_events(sim, entity_id: int, target: Vector2i) -> bool:
	for attempt in range(64):
		var current: Vector2i = sim.world.entities[entity_id].position
		if current == target:
			return true
		var delta := target - current
		var directions: Array[Vector2i] = [
			Vector2i(signi(delta.x), signi(delta.y)),
			Vector2i(signi(delta.x), 0),
			Vector2i(0, signi(delta.y)),
		]
		var moved := false
		for direction in directions:
			if direction == Vector2i.ZERO:
				continue
			var destination := current + direction
			if maxi(absi(destination.x-target.x),absi(destination.y-target.y)) \
					>= maxi(absi(current.x-target.x),absi(current.y-target.y)):
				continue
			var assessment = sim.movement.assess_move(entity_id, destination)
			if not assessment.accepted:
				continue
			var definition: Dictionary = TerrainRegistry.definition(str(assessment.terrain_id))
			if sim.movement.commit_preflighted_move(entity_id, destination,
					str(assessment.terrain_id), int(definition.move_time_cost)) == null:
				return false
			moved = true
			break
		if not moved:
			return false
	return false
