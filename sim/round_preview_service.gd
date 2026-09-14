extends RefCounted
const Rules=preload("res://sim/round_combat_rules.gd")
const Field=preload("res://sim/field_turn_rules.gd")
const System=preload("res://sim/systems/round_combat_system.gd")
const Simulator=preload("res://sim/simulator.gd")

static func preview(sim)->Dictionary:
	var w=sim.world;var r:Dictionary=w.party_encounter.round_combat
	if not Rules.active(w):return {"accepted":false,"reason":"round_not_active","slots":[]}
	var key:Array=[w.get_instance_id(),w.step_index,w.world_time,w.events.size(),
		w.item_state.revision,r.round_id,r.plan_revision,r.phase,r.execution_cursor]
	var cached:Dictionary=w.get_meta("round_preview_cache",{})
	if cached.get("key",[])==key:return cached.dto.duplicate(true)
	var begun:=Time.get_ticks_usec()
	var shadow=Simulator.new(0,0,1)
	if not shadow.restore_rollback_memento(w.rollback_memento(false)):
		return {"accepted":false,"reason":"round_preview_unavailable","slots":[]}
	var result:=System.confirm(shadow,int(r.round_id),int(r.plan_revision),r.phase=="INTERRUPTED",true)
	var slots:Array=[];var visible:=Field.visible_cells(w)
	var shown_ids:Array=w.party_encounter.active_party_member_ids.duplicate()
	for id in w.party_encounter.enemy_ids:
		if Field.visible(w,id):shown_ids.append(id)
	for raw in result.get("slots",[]):
		if int(raw.actor_id) not in shown_ids:continue
		var row:Dictionary=raw.duplicate(true)
		row.movement=row.movement.filter(func(cell):return visible.has("%d:%d"%[int(cell[0]),int(cell[1])]))
		for coordinate in ["from_position","end_position"]:
			if row.has(coordinate) and not visible.has("%d:%d"%[int(row[coordinate][0]),int(row[coordinate][1])]):
				row[coordinate]=[-1,-1];row.conditional=true
		row.damage=row.damage.filter(func(damage):return int(damage.target_id) in shown_ids)
		# Cancellation due to a hidden obstacle is conditional, never an enemy
		# name, HP estimate, coordinate or diagnostic from the authority world.
		if row.get("interrupted",false):row.reason="unrevealed_change";row.conditional=true
		slots.append(row)
	var boundary_damage:Array=[]
	if result.get("accepted",false):
		for event in shadow.world.events_since(int(result.events_start)):
			if event.type.begins_with("combat.") and event.type.ends_with("_damage") and event.target_id in shown_ids:
				boundary_damage.append({"target_id":event.target_id,"amount":event.magnitude})
	var dto:={"accepted":bool(result.get("accepted",false)),"reason":"ok" if result.get("accepted",false) else "round_preview_unavailable",
		"round_id":int(r.round_id),"plan_revision":int(r.plan_revision),"slots":slots,
		"effects":boundary_damage,"conditional":not result.get("completed",false),
		"policy":"KEYED_OUTCOME_IF_NO_UNREVEALED_CHANGE","elapsed_usec":Time.get_ticks_usec()-begun,"clones":1}
	w.set_meta("round_preview_cache",{"key":key,"dto":dto.duplicate(true)})
	return dto
