extends "res://tests/test_case.gd"

const Session=preload("res://playtest/party_playtest_session.gd")
const Command=preload("res://sim/sim_command.gd")


func _walk_to_contact(session)->bool:
	var state=session.sim.world.party_encounter
	var hero:int=state.protagonist_id
	var goal:Vector2i=session.sim.world.entities[state.enemy_ids[0]].position
	var best:Dictionary={}
	for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		var path:Dictionary=session.find_exploration_path(hero,goal+direction)
		if path.get("found",false) and (best.is_empty() \
				or path.path.size()<best.path.size()):best=path
	if best.is_empty():return false
	for cell in best.path.slice(1):
		if session.party_status().safe_phase=="CONTACT":break
		if not session.commit_exploration(Command.move_to(hero,cell)).accepted:break
	return session.party_status().safe_phase=="CONTACT"


func _first_equippable(session)->Dictionary:
	for row in session.protagonist_inventory().get("backpack_rows",[]):
		var allowed:Array=row.get("equip_slots",[])
		if not allowed.is_empty():return {"instance_id":str(row.get("instance_id","")),
			"slot":str(allowed[0]),"definition_id":str(row.get("definition_id",""))}
	return {}


func test_equipment_swaps_survive_a_multi_member_combat_turn()->bool:
	# A scenario flagged for solo combat can still deploy a companion. Routing the
	# item action's time step on that scenario flag instead of the live active
	# roster used to reject every in-combat equip with a generic rollback notice.
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var candidate:=_first_equippable(session)
	check(not candidate.is_empty(),"duo protagonist starts with a spare weapon")
	if candidate.is_empty():return finish()

	check(session.equip_inventory_item(candidate.instance_id,candidate.slot).accepted,
		"safe exploration equips the spare weapon")

	check(_walk_to_contact(session),"routed exploration reaches an encounter")
	if session.party_status().safe_phase!="CONTACT":return finish()
	check(session.preview_deployment("LINE",session.available_companion_ids()).accepted,
		"contact previews a full-party formation")
	check(session.commit_deployment().accepted,"contact deploys the party into combat")
	var state=session.sim.world.party_encounter
	check_eq(str(state.safe_phase),"ENGAGED","deployment engages the encounter")
	check(state.active_party_member_ids.size()>1,
		"the duo scenario deploys more than the protagonist")

	var in_combat:=_first_equippable(session)
	check(not in_combat.is_empty(),"a spare weapon is still in the backpack")
	if in_combat.is_empty():return finish()
	var result:Dictionary=session.equip_inventory_item(in_combat.instance_id,in_combat.slot)
	check(bool(result.accepted),
		"equipping during a multi-member combat turn is accepted, got reason %s" \
			%str(result.get("reason","")))
	check_eq(str(session.sim.world.item_state.inventory(
		state.protagonist_id).equipped.get(in_combat.slot,"")),in_combat.instance_id,
		"the combat equip actually moved the item into its slot")
	check(session.sim.world.world_state_error().is_empty(),
		"the combat equip leaves a valid world state")
	return finish()
