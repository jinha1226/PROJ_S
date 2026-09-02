class_name PartyEncounterState
extends RefCounted

const SCHEMA_VERSION := 17
const LEGACY_SCHEMA_VERSION := 1
const ROSTER_SCHEMA_VERSION := 2
const PATROL_SCHEMA_VERSION := 3
const PROGRESSION_SCHEMA_VERSION := 4
const LOADOUT_SCHEMA_VERSION := 5
const DIAGONAL_GATEWAY_SCHEMA_VERSION := 6
const AWARENESS_SCHEMA_VERSION := 7
const ITEM_SCHEMA_VERSION := 8
const RECOVERY_SCHEMA_VERSION := 9
const OPENING_EVENT_SCHEMA_VERSION := 10
const GROWTH_BUILD_SCHEMA_VERSION := 11
# v12 moved the protagonist inventory and ground items to WorldItemState.
const WORLD_ITEM_SCHEMA_VERSION := 12
# v13 removed protagonist_loadout: the equipped MAIN_HAND instance is the only
# weapon authority, ammo lives on the entity row and reload on the weapon row.
const WEAPON_AUTHORITY_SCHEMA_VERSION := 13
# v14 persists companion panic hysteresis beside stress.
const MORALE_SCHEMA_VERSION := 14
# v15 replaces the temporary four-facet party personality with continuous
# HEXACO and records whether an old journal predates the semantic cut.
const HEXACO_SCHEMA_VERSION := 15
# v16 hard-cuts the player species enum and nested GrowthBuildState v2.
const PLAYER_SPECIES_SCHEMA_VERSION := 16
# v17 hard-cuts STR/DEX/INT and stat-scaled equipment snapshots.
const STAT_SCALING_SCHEMA_VERSION := 17
const MAX_ACTIVE_PARTY_SIZE := 4
const PHASES := ["GROUPED", "CONTACT", "ENGAGED", "REGROUP_READY", "GROUPED_COMPLETE", "PARTY_DEFEATED"]
const CONTACT_KINDS := ["NONE", "DETECTED", "PARTY_AMBUSH", "ENEMY_AMBUSH"]
const FORMATIONS := ["NONE", "WEDGE", "LINE", "COLUMN"]
const MAX_WORLD_TIME := 9223372036854775707
const MemberScript = preload("res://sim/party_member_state.gd")
const Int64CodecScript = preload("res://sim/int64_codec.gd")
const ProgressionScript = preload("res://sim/protagonist_progression.gd")
const WeaponLoadoutScript = preload("res://sim/weapon_loadout_state.gd")
const EnemyAwarenessScript = preload("res://sim/enemy_awareness_state.gd")
const InventoryScript = preload("res://sim/protagonist_inventory_state.gd")
const GroundItemScript = preload("res://sim/ground_item_state.gd")
const ItemOperationsScript = preload("res://sim/item_inventory_operations.gd")
const OpeningEventScript = preload("res://sim/opening_event_state.gd")
const GrowthBuildStateScript = preload("res://sim/growth_build_state.gd")
const PartyHexacoScript = preload("res://sim/dungeon_population/hexaco_profile.gd")

var schema_version := SCHEMA_VERSION
var encounter_id: int = 1
var safe_phase := "GROUPED"
var revision: int = 0
var protagonist_id: int = -1
var party_member_ids: Array[int] = []
var active_party_member_ids: Array[int] = []
var enemy_ids: Array[int] = []
var group_anchor := Vector2i.ZERO
var facing := Vector2i.RIGHT
var contact_kind := "NONE"
var contact_enemy_id: int = -1
var party_detection_radius := 4
var enemy_detection_radius := 3
var formation_id := "NONE"
var member_rows: Dictionary = {}
var enemy_busy_rows: Dictionary = {}
var enemy_awareness_rows: Dictionary = {}
var exile_records: Array[Dictionary] = []
var patrol_reserved_positions: Array[Vector2i] = []
var diagonal_gateway_positions: Array[Vector2i] = []
var protagonist_progression = ProgressionScript.new()
# Deterministic exploration-only recovery cadence. It is state, not UI timing.
var safe_recovery_turns: int = 0
var last_protagonist_damage_step: int = -1
var opening_event = null
var protagonist_growth = GrowthBuildStateScript.new("human")
var legacy_journal_origin := false

func member(entity_id: int): return member_rows.get(entity_id)
func enemy_awareness(entity_id:int):return enemy_awareness_rows.get(entity_id)

func to_dict() -> Dictionary:
	var members: Array = []
	var all_member_ids: Array = member_rows.keys(); all_member_ids.sort()
	for entity_id in all_member_ids: members.append(member_rows[entity_id].to_dict())
	var busy_rows: Array = []
	var ids: Array = enemy_busy_rows.keys(); ids.sort()
	for entity_id in ids: busy_rows.append({"entity_id": str(entity_id), "busy_until": str(enemy_busy_rows[entity_id])})
	var awareness_rows:Array=[]
	var awareness_ids:Array=enemy_awareness_rows.keys();awareness_ids.sort()
	for entity_id in awareness_ids:awareness_rows.append(enemy_awareness_rows[entity_id].to_dict())
	var reserved_rows: Array = []
	var sorted_reserved: Array[Vector2i] = patrol_reserved_positions.duplicate()
	sorted_reserved.sort_custom(func(a: Vector2i, b: Vector2i):
		return a.y < b.y if a.y != b.y else a.x < b.x)
	for position in sorted_reserved: reserved_rows.append([position.x, position.y])
	var gateway_rows: Array = []
	var sorted_gateways: Array[Vector2i] = diagonal_gateway_positions.duplicate()
	sorted_gateways.sort_custom(func(a: Vector2i, b: Vector2i):
		return a.y < b.y if a.y != b.y else a.x < b.x)
	for position in sorted_gateways: gateway_rows.append([position.x, position.y])
	var wire := {"schema_version": schema_version, "encounter_id": str(encounter_id), "safe_phase": safe_phase,
		"revision": str(revision), "protagonist_id": str(protagonist_id),
		"party_member_ids": party_member_ids.map(func(id): return str(id)),
		"active_party_member_ids": active_party_member_ids.map(func(id): return str(id)),
		"enemy_ids": enemy_ids.map(func(id): return str(id)), "group_anchor": [group_anchor.x, group_anchor.y],
		"facing": [facing.x, facing.y], "contact_kind": contact_kind,
		"contact_enemy_id": str(contact_enemy_id), "party_detection_radius": party_detection_radius,
		"enemy_detection_radius": enemy_detection_radius, "formation_id": formation_id,
		"member_rows": members, "enemy_busy_rows": busy_rows,
		"enemy_awareness_rows":awareness_rows,
		"patrol_reserved_positions":reserved_rows,
		"diagonal_gateway_positions":gateway_rows,
		"protagonist_progression":protagonist_progression.to_dict(),
		"safe_recovery_turns":safe_recovery_turns,
		"last_protagonist_damage_step":str(last_protagonist_damage_step),
		"opening_event":null if opening_event == null else opening_event.to_dict(),
		"protagonist_growth":protagonist_growth.to_dict(),
		"exile_records":exile_records.duplicate(true)}
	if schema_version >= HEXACO_SCHEMA_VERSION:
		wire["legacy_journal_origin"] = legacy_journal_origin
	return wire

static func from_dict(row: Dictionary):
	var state = load("res://sim/party_encounter_state.gd").new()
	state.schema_version = SCHEMA_VERSION
	state.legacy_journal_origin = bool(row.get("legacy_journal_origin",
		int(row.get("schema_version", 1)) < HEXACO_SCHEMA_VERSION))
	state.encounter_id = Int64CodecScript.parse(row.encounter_id, "encounter ID")
	state.safe_phase = str(row.safe_phase); state.revision = Int64CodecScript.parse(row.revision, "revision")
	state.protagonist_id = Int64CodecScript.parse(row.protagonist_id, "protagonist ID")
	state.party_member_ids.clear(); for value in row.party_member_ids: state.party_member_ids.append(Int64CodecScript.parse(value, "party ID"))
	state.active_party_member_ids.clear()
	for value in row.get("active_party_member_ids", row.party_member_ids): state.active_party_member_ids.append(Int64CodecScript.parse(value, "active party ID"))
	state.enemy_ids.clear(); for value in row.enemy_ids: state.enemy_ids.append(Int64CodecScript.parse(value, "enemy ID"))
	state.group_anchor = Vector2i(int(row.group_anchor[0]), int(row.group_anchor[1])); state.facing = Vector2i(int(row.facing[0]), int(row.facing[1]))
	state.contact_kind = str(row.contact_kind); state.contact_enemy_id = Int64CodecScript.parse(row.contact_enemy_id, "contact enemy")
	state.party_detection_radius = int(row.party_detection_radius); state.enemy_detection_radius = int(row.enemy_detection_radius)
	state.formation_id = str(row.formation_id); state.member_rows.clear()
	for member_row in row.member_rows:
		var member = MemberScript.from_dict(member_row); state.member_rows[member.entity_id] = member
	state.enemy_busy_rows.clear(); for busy_row in row.enemy_busy_rows: state.enemy_busy_rows[Int64CodecScript.parse(busy_row.entity_id, "enemy ID")] = Int64CodecScript.parse(busy_row.busy_until, "enemy busy")
	state.enemy_awareness_rows.clear()
	if row.has("enemy_awareness_rows"):
		for awareness_row in row.enemy_awareness_rows:
			var awareness=EnemyAwarenessScript.from_dict(awareness_row)
			state.enemy_awareness_rows[awareness.enemy_id]=awareness
	else:
		# Old v1-v6 snapshots had a single globally-driven enemy. Preserve its
		# combat semantics while giving exploration saves a deterministic neutral
		# baseline. Session migration can refine home to the live entity position.
		for enemy_id in state.enemy_ids:
			var awareness=EnemyAwarenessScript.new(enemy_id,state.group_anchor)
			if state.safe_phase in ["CONTACT","ENGAGED"]:
				awareness.awareness_state="HUNTING";awareness.suspicion=1000
				awareness.last_known_target_position=state.group_anchor
				awareness.last_seen_step=0;awareness.last_seen_time=0
			state.enemy_awareness_rows[enemy_id]=awareness
	state.exile_records.clear()
	for record in row.get("exile_records",[]):state.exile_records.append(_canonical_exile_record(record))
	state.patrol_reserved_positions.clear()
	for position in row.get("patrol_reserved_positions",[]):
		state.patrol_reserved_positions.append(Vector2i(int(position[0]),int(position[1])))
	state.diagonal_gateway_positions.clear()
	for position in row.get("diagonal_gateway_positions",[]):
		state.diagonal_gateway_positions.append(Vector2i(int(position[0]),int(position[1])))
	state.protagonist_progression=ProgressionScript.from_dict(row.protagonist_progression) \
		if row.has("protagonist_progression") else ProgressionScript.new()
	# v5-v12 rows still carry loadout/inventory/ground keys. None of them is party
	# state any more, so this reader drops them instead of restoring a second
	# authority beside WorldItemState.
	state.safe_recovery_turns=int(row.get("safe_recovery_turns",0))
	state.last_protagonist_damage_step=Int64CodecScript.parse(
		row.get("last_protagonist_damage_step","-1"),"last protagonist damage step")
	state.opening_event = OpeningEventScript.from_dict(row.opening_event) \
		if row.get("opening_event") is Dictionary else null
	state.protagonist_growth = GrowthBuildStateScript.from_dict(row.protagonist_growth) \
		if row.get("protagonist_growth") is Dictionary else GrowthBuildStateScript.new("human")
	return state

static func _canonical_exile_record(record: Dictionary) -> Dictionary:
	var initial_statuses:Array=[]
	for status in record.initial_status_effects:
		initial_statuses.append({"status_id":str(status.status_id),
			"remaining_ticks":int(status.remaining_ticks),"tick_damage":int(status.tick_damage)})
	var statuses:Array=[]
	for status in record.status_effects:
		statuses.append({"status_id":str(status.status_id),
			"remaining_ticks":int(status.remaining_ticks),"tick_damage":int(status.tick_damage)})
	var personality_summary: Dictionary = {}
	if int(record.schema_version) >= 2:
		personality_summary = {"style_label":str(record.personality_summary.style_label),
			"profile_hash":str(record.personality_summary.profile_hash),
			"H":int(record.personality_summary.H),"E":int(record.personality_summary.E),
			"X":int(record.personality_summary.X),"A":int(record.personality_summary.A),
			"C":int(record.personality_summary.C),"O":int(record.personality_summary.O)}
	else:
		personality_summary = {
			"archetype_id":str(record.personality_summary.archetype_id),
			"archetype_label":str(record.personality_summary.archetype_label),
			"profile_hash":str(record.personality_summary.profile_hash),
			"aggression":int(record.personality_summary.aggression),
			"altruism":int(record.personality_summary.altruism),
			"boldness":int(record.personality_summary.boldness),
			"composure":int(record.personality_summary.composure)}
	return {"schema_version":int(record.schema_version),
		"former_member_id":str(record.former_member_id),"display_name":str(record.display_name),
		"species_id":str(record.species_id),"personality_summary":personality_summary,
		"dismissed_world_time":str(record.dismissed_world_time),
		"dismissed_step_index":str(record.dismissed_step_index),
		"dismissal_event_id":str(record.dismissal_event_id),"condition_snapshot":{
			"condition_band":str(record.condition_snapshot.condition_band),
			"hp":int(record.condition_snapshot.hp),
			"hp_percent":int(record.condition_snapshot.hp_percent),
			"stress":int(record.condition_snapshot.stress),
			"harmful_status":bool(record.condition_snapshot.harmful_status)},
		"emotion_modifiers":{"resentment_delta":int(record.emotion_modifiers.resentment_delta),
			"fear_delta":int(record.emotion_modifiers.fear_delta)},
		"relationship_snapshot":{"trust":int(record.relationship_snapshot.trust),
			"fear":int(record.relationship_snapshot.fear),
			"hostility":int(record.relationship_snapshot.hostility),
			"gratitude":int(record.relationship_snapshot.gratitude),
			"grievance":int(record.relationship_snapshot.grievance)},
		"current_hp":int(record.current_hp),"max_hp":int(record.max_hp),
		"alive":bool(record.alive),"initial_status_effects":initial_statuses,
		"status_effects":statuses,"location_id":str(record.location_id),
		"initial_safety":int(record.initial_safety),"safety":int(record.safety),
		"current_behavior":str(record.current_behavior),
		"last_world_time":str(record.last_world_time),"last_world_step":str(record.last_world_step),
		"encounter_eligible_after_step":str(record.encounter_eligible_after_step)}

static func wire_error(row: Variant, width: int, height: int) -> String:
	if not row is Dictionary: return "invalid_party_encounter_shape"
	var keys: Array = row.keys(); keys.sort()
	var v1_keys := ["contact_enemy_id", "contact_kind", "encounter_id", "enemy_busy_rows", "enemy_detection_radius", "enemy_ids", "facing", "formation_id", "group_anchor", "member_rows", "party_detection_radius", "party_member_ids", "protagonist_id", "revision", "safe_phase", "schema_version"]
	var v2_keys: Array = v1_keys.duplicate(); v2_keys.append_array(["active_party_member_ids","exile_records"]); v2_keys.sort()
	var v3_keys: Array = v2_keys.duplicate(); v3_keys.append("patrol_reserved_positions"); v3_keys.sort()
	var v4_keys:Array=v3_keys.duplicate();v4_keys.append("protagonist_progression");v4_keys.sort()
	var v5_keys:Array=v4_keys.duplicate();v5_keys.append("protagonist_loadout");v5_keys.sort()
	var v6_keys:Array=v5_keys.duplicate();v6_keys.append("diagonal_gateway_positions");v6_keys.sort()
	var v7_keys:Array=v6_keys.duplicate();v7_keys.append("enemy_awareness_rows");v7_keys.sort()
	var v8_keys:Array=v7_keys.duplicate();v8_keys.append_array([
		"protagonist_inventory","ground_items"]);v8_keys.sort()
	var v9_keys:Array=v8_keys.duplicate();v9_keys.append_array([
		"safe_recovery_turns","last_protagonist_damage_step"]);v9_keys.sort()
	var v10_keys:Array=v9_keys.duplicate();v10_keys.append("opening_event");v10_keys.sort()
	var v11_keys:Array=v10_keys.duplicate();v11_keys.append("protagonist_growth");v11_keys.sort()
	var v12_keys:Array=v11_keys.duplicate()
	v12_keys.erase("protagonist_inventory");v12_keys.erase("ground_items");v12_keys.sort()
	var v13_keys:Array=v12_keys.duplicate()
	v13_keys.erase("protagonist_loadout");v13_keys.sort()
	var v14_keys:Array=v13_keys.duplicate()
	var v15_keys:Array=v14_keys.duplicate();v15_keys.append("legacy_journal_origin");v15_keys.sort()
	if not _integer(row.get("schema_version")): return "unsupported_party_schema"
	var parsed_schema_version := int(row.schema_version)
	if (parsed_schema_version == LEGACY_SCHEMA_VERSION and keys != v1_keys) \
			or (parsed_schema_version == ROSTER_SCHEMA_VERSION and keys != v2_keys) \
			or (parsed_schema_version == PATROL_SCHEMA_VERSION and keys != v3_keys) \
			or (parsed_schema_version == PROGRESSION_SCHEMA_VERSION and keys != v4_keys) \
			or (parsed_schema_version == LOADOUT_SCHEMA_VERSION and keys != v5_keys) \
			or (parsed_schema_version == DIAGONAL_GATEWAY_SCHEMA_VERSION and keys != v6_keys) \
			or (parsed_schema_version == AWARENESS_SCHEMA_VERSION and keys != v7_keys) \
		or (parsed_schema_version == ITEM_SCHEMA_VERSION and keys != v8_keys) \
		or (parsed_schema_version == RECOVERY_SCHEMA_VERSION and keys != v9_keys) \
		or (parsed_schema_version == OPENING_EVENT_SCHEMA_VERSION and keys != v10_keys) \
		or (parsed_schema_version == GROWTH_BUILD_SCHEMA_VERSION and keys != v11_keys) \
		or (parsed_schema_version == WORLD_ITEM_SCHEMA_VERSION and keys != v12_keys) \
		or (parsed_schema_version == WEAPON_AUTHORITY_SCHEMA_VERSION and keys != v13_keys) \
		or (parsed_schema_version == MORALE_SCHEMA_VERSION and keys != v14_keys) \
		or (parsed_schema_version == HEXACO_SCHEMA_VERSION and keys != v15_keys) \
		or (parsed_schema_version == SCHEMA_VERSION and keys != v15_keys):
		return "invalid_party_encounter_keys"
	if parsed_schema_version not in [LEGACY_SCHEMA_VERSION, ROSTER_SCHEMA_VERSION,
			PATROL_SCHEMA_VERSION,PROGRESSION_SCHEMA_VERSION,LOADOUT_SCHEMA_VERSION,
		DIAGONAL_GATEWAY_SCHEMA_VERSION,AWARENESS_SCHEMA_VERSION,ITEM_SCHEMA_VERSION,
		RECOVERY_SCHEMA_VERSION,OPENING_EVENT_SCHEMA_VERSION,GROWTH_BUILD_SCHEMA_VERSION,
			WORLD_ITEM_SCHEMA_VERSION,WEAPON_AUTHORITY_SCHEMA_VERSION,MORALE_SCHEMA_VERSION,
			HEXACO_SCHEMA_VERSION,SCHEMA_VERSION]: return "unsupported_party_schema"
	if parsed_schema_version >= HEXACO_SCHEMA_VERSION \
			and not row.get("legacy_journal_origin") is bool:
		return "invalid_legacy_journal_origin"
	for key in ["encounter_id", "protagonist_id", "revision", "contact_enemy_id"]:
		if not Int64CodecScript.is_canonical(row.get(key)): return "noncanonical_party_%s" % key
	if Int64CodecScript.parse(row.encounter_id, "encounter") <= 0 or Int64CodecScript.parse(row.protagonist_id, "protagonist") <= 0 or Int64CodecScript.parse(row.revision, "revision") < 0:
		return "invalid_party_scalar"
	if row.safe_phase not in PHASES or row.contact_kind not in CONTACT_KINDS or row.formation_id not in FORMATIONS:
		return "unknown_party_enum"
	if not _position(row.group_anchor, width, height) or not _facing(row.facing):
		return "invalid_party_position_or_facing"
	if not _integer(row.party_detection_radius) or not _integer(row.enemy_detection_radius) or row.party_detection_radius < 0 or row.party_detection_radius > 15 or row.enemy_detection_radius < 0 or row.enemy_detection_radius > 15:
		return "invalid_detection_radius"
	for list_key in ["party_member_ids", "enemy_ids"]:
		if not row.get(list_key) is Array or row[list_key].is_empty() or row[list_key].size() > 64: return "invalid_%s" % list_key
		var previous := -1
		for value in row[list_key]:
			if not Int64CodecScript.is_canonical(value): return "noncanonical_%s" % list_key
			var parsed := Int64CodecScript.parse(value, list_key)
			if parsed <= previous: return "duplicate_or_unsorted_%s" % list_key
			previous = parsed
	var active_rows: Variant = row.get("active_party_member_ids", row.party_member_ids)
	if not active_rows is Array or active_rows.is_empty() \
			or active_rows.size() > MAX_ACTIVE_PARTY_SIZE:
		return "invalid_active_party_member_ids"
	var previous_active := -1
	for value in active_rows:
		if not Int64CodecScript.is_canonical(value): return "noncanonical_active_party_member_ids"
		var parsed := Int64CodecScript.parse(value, "active party member ID")
		if parsed <= previous_active: return "duplicate_or_unsorted_active_party_member_ids"
		previous_active = parsed
	var party_set: Dictionary = {}
	for value in row.party_member_ids: party_set[value] = true
	for value in active_rows:
		if not party_set.has(value): return "active_party_member_not_in_roster"
	for value in row.enemy_ids:
		if party_set.has(value): return "party_enemy_id_overlap"
	if not row.member_rows is Array or row.member_rows.size() != party_set.size(): return "invalid_party_member_rows"
	var active_set: Dictionary = {}; for value in active_rows: active_set[value] = true
	var seen_slots: Dictionary = {}
	for index in range(row.member_rows.size()):
		var error := MemberScript.wire_error(row.member_rows[index],
			parsed_schema_version >= MORALE_SCHEMA_VERSION,
			parsed_schema_version >= HEXACO_SCHEMA_VERSION)
		if not error.is_empty(): return error
		if index > 0 and Int64CodecScript.parse(row.member_rows[index-1].entity_id,"member") \
				>= Int64CodecScript.parse(row.member_rows[index].entity_id,"member"):
			return "party_member_order_mismatch"
		var member_id: String = str(row.member_rows[index].entity_id)
		if not party_set.has(member_id): return "party_member_set_mismatch"
		var slot := int(row.member_rows[index].roster_slot)
		if seen_slots.has(slot): return "duplicate_party_roster_slot"
		seen_slots[slot] = true
		if not active_set.has(member_id) and (row.member_rows[index].role != "COMPANION" \
				or row.member_rows[index].presence not in ["RECRUITABLE", "EXILED"]):
			return "invalid_inactive_party_member_state"
		if active_set.has(member_id) and member_id == row.protagonist_id \
				and (row.member_rows[index].role != "PROTAGONIST" or slot != 0):
			return "party_protagonist_roster_invalid"
	for slot in range(seen_slots.size()):
		if not seen_slots.has(slot): return "party_roster_slots_not_continuous"
	if active_rows[0] != row.protagonist_id or row.party_member_ids[0] != row.protagonist_id:
		return "party_protagonist_roster_invalid"
	if parsed_schema_version >= ROSTER_SCHEMA_VERSION:
		if not row.get("exile_records") is Array: return "invalid_exile_records_shape"
		var seen_exiles: Dictionary = {}
		for record in row.exile_records:
			var record_error := _exile_record_wire_error(record, party_set,
				parsed_schema_version >= HEXACO_SCHEMA_VERSION)
			if not record_error.is_empty(): return record_error
			if seen_exiles.has(record.former_member_id): return "duplicate_exile_record"
			seen_exiles[record.former_member_id] = true
	if parsed_schema_version >= PATROL_SCHEMA_VERSION:
		if not row.get("patrol_reserved_positions") is Array \
				or row.patrol_reserved_positions.size()>64:
			return "invalid_patrol_reserved_positions"
		var previous_reserved:=Vector2i(-1,-1)
		for position in row.patrol_reserved_positions:
			if not _position(position,width,height):return "invalid_patrol_reserved_positions"
			var parsed_position:=Vector2i(int(position[0]),int(position[1]))
			if previous_reserved!=Vector2i(-1,-1) \
					and (parsed_position.y<previous_reserved.y \
					or (parsed_position.y==previous_reserved.y \
					and parsed_position.x<=previous_reserved.x)):
				return "invalid_patrol_reserved_positions"
			previous_reserved=parsed_position
	if parsed_schema_version >= DIAGONAL_GATEWAY_SCHEMA_VERSION:
		if not row.get("diagonal_gateway_positions") is Array \
				or row.diagonal_gateway_positions.size()>64:
			return "invalid_diagonal_gateway_positions"
		var previous_gateway:=Vector2i(-1,-1)
		for position in row.diagonal_gateway_positions:
			if not _position(position,width,height):return "invalid_diagonal_gateway_positions"
			var parsed_position:=Vector2i(int(position[0]),int(position[1]))
			if previous_gateway!=Vector2i(-1,-1) \
					and (parsed_position.y<previous_gateway.y \
					or (parsed_position.y==previous_gateway.y \
					and parsed_position.x<=previous_gateway.x)):
				return "invalid_diagonal_gateway_positions"
			previous_gateway=parsed_position
	if parsed_schema_version>=AWARENESS_SCHEMA_VERSION:
		if not row.get("enemy_awareness_rows") is Array \
				or row.enemy_awareness_rows.size()!=row.enemy_ids.size():
			return "invalid_enemy_awareness_rows"
		for index in range(row.enemy_awareness_rows.size()):
			var awareness_error:=EnemyAwarenessScript.wire_error(
				row.enemy_awareness_rows[index],width,height)
			if not awareness_error.is_empty():return awareness_error
			if str(row.enemy_awareness_rows[index].enemy_id)!=str(row.enemy_ids[index]):
				return "enemy_awareness_order_mismatch"
	if parsed_schema_version>=PROGRESSION_SCHEMA_VERSION:
		var progression_error:=ProgressionScript.wire_error(row.get("protagonist_progression"))
		if not progression_error.is_empty():return progression_error
	if parsed_schema_version>=LOADOUT_SCHEMA_VERSION \
			and parsed_schema_version<WEAPON_AUTHORITY_SCHEMA_VERSION:
		# v5-v12 only. The duplicate weapon authority is gone from the current wire.
		var loadout_error:=WeaponLoadoutScript.wire_error(row.get("protagonist_loadout"))
		if not loadout_error.is_empty():return loadout_error
	if parsed_schema_version>=ITEM_SCHEMA_VERSION \
			and parsed_schema_version<WORLD_ITEM_SCHEMA_VERSION:
		# v8-v11 only. The current contract validates these against the world item
		# state, where the single canonical authority now lives.
		var inventory_error:=InventoryScript.wire_error(row.get("protagonist_inventory"))
		if not inventory_error.is_empty():return inventory_error
		var ground_error:=GroundItemScript.wire_error(row.get("ground_items"),width,height)
		if not ground_error.is_empty():return ground_error
		var inventory=InventoryScript.from_dict(row.protagonist_inventory)
		var ground=GroundItemScript.from_dict(row.ground_items)
		var combined_error:=ItemOperationsScript.combined_state_error(inventory,ground,
			Rect2i(Vector2i.ZERO,Vector2i(width,height)))
		if not combined_error.is_empty():return combined_error
		var main=inventory.equipped_item("MAIN_HAND")
		var bridged_weapon_id:="UNARMED_STRIKE"
		if main!=null:
			var main_definition=load("res://sim/item_registry.gd").definition(main.definition_id)
			if main_definition==null:return "inventory_loadout_bridge_mismatch"
			bridged_weapon_id=str(main_definition.weapon_id)
		if bridged_weapon_id!=str(row.protagonist_loadout.equipped_weapon_id):
			return "inventory_loadout_bridge_mismatch"
	if parsed_schema_version>=RECOVERY_SCHEMA_VERSION:
		if not _integer(row.get("safe_recovery_turns")) or int(row.safe_recovery_turns)<0 \
			or int(row.safe_recovery_turns)>1000000 \
			or not Int64CodecScript.is_canonical(row.get("last_protagonist_damage_step")) \
			or Int64CodecScript.parse(row.last_protagonist_damage_step,"recovery damage step") < -1:
			return "invalid_party_recovery_state"
	if parsed_schema_version>=OPENING_EVENT_SCHEMA_VERSION:
		var opening_value: Variant = row.get("opening_event")
		if opening_value != null:
			var opening_error := OpeningEventScript.wire_error(opening_value, width, height)
			if not opening_error.is_empty(): return opening_error
	if parsed_schema_version>=GROWTH_BUILD_SCHEMA_VERSION:
		var growth_error := GrowthBuildStateScript.wire_error(row.get("protagonist_growth"))
		if not growth_error.is_empty(): return growth_error
	if not row.enemy_busy_rows is Array or row.enemy_busy_rows.size() != row.enemy_ids.size(): return "invalid_enemy_busy_rows"
	for index in range(row.enemy_busy_rows.size()):
		var busy = row.enemy_busy_rows[index]
		if not busy is Dictionary: return "invalid_enemy_busy_row"
		var busy_keys: Array = busy.keys(); busy_keys.sort()
		if busy_keys != ["busy_until", "entity_id"]: return "invalid_enemy_busy_row"
		if busy.entity_id != row.enemy_ids[index] or not Int64CodecScript.is_canonical(busy.busy_until): return "enemy_busy_order_mismatch"
		var busy_until := Int64CodecScript.parse(busy.busy_until, "enemy busy")
		if busy_until < 0 or busy_until > MAX_WORLD_TIME: return "enemy_busy_out_of_range"
	var contact_id := Int64CodecScript.parse(row.contact_enemy_id, "contact enemy")
	if (row.contact_kind == "NONE") != (contact_id == -1): return "contact_identity_mismatch"
	if contact_id != -1 and not row.enemy_ids.has(str(contact_id)): return "contact_enemy_not_in_encounter"
	if row.safe_phase in ["GROUPED", "GROUPED_COMPLETE"] and (row.contact_kind != "NONE" or row.formation_id != "NONE"):
		return "grouped_contact_or_formation_invalid"
	if row.safe_phase == "CONTACT" and (row.contact_kind == "NONE" or row.formation_id != "NONE"):
		return "contact_phase_formation_invalid"
	if row.safe_phase in ["ENGAGED", "REGROUP_READY"] and (row.contact_kind == "NONE" or row.formation_id == "NONE"):
		return "engaged_contact_or_formation_invalid"
	return ""

static func _exile_record_wire_error(record: Variant, party_set: Dictionary,
		require_hexaco: bool) -> String:
	if not record is Dictionary: return "invalid_exile_record_shape"
	var keys: Array = record.keys(); keys.sort()
	if keys != ["alive","condition_snapshot","current_behavior","current_hp",
			"dismissal_event_id","dismissed_step_index","dismissed_world_time","display_name",
			"emotion_modifiers","encounter_eligible_after_step","former_member_id",
			"initial_safety","initial_status_effects","last_world_step","last_world_time",
			"location_id","max_hp","personality_summary","relationship_snapshot",
			"safety","schema_version","species_id","status_effects"]:
		return "invalid_exile_record_keys"
	if record.schema_version != (2 if require_hexaco else 1) \
			or record.current_behavior not in ["SEEK_SAFETY","SELF_TREAT","RECOVER","DEAD"]:
		return "invalid_exile_record_enum"
	for key in ["former_member_id","dismissal_event_id","dismissed_step_index",
			"dismissed_world_time","encounter_eligible_after_step","last_world_step","last_world_time"]:
		if not Int64CodecScript.is_canonical(record.get(key)): return "noncanonical_exile_record_time_or_id"
	if not party_set.has(str(record.former_member_id)) \
			or Int64CodecScript.parse(record.dismissal_event_id,"dismissal event") <= 0 \
			or Int64CodecScript.parse(record.dismissed_step_index,"dismissed step") < 0 \
			or Int64CodecScript.parse(record.dismissed_world_time,"dismissed time") < 0 \
			or Int64CodecScript.parse(record.last_world_time,"last world time") \
				<Int64CodecScript.parse(record.dismissed_world_time,"dismissed time") \
			or Int64CodecScript.parse(record.last_world_step,"last world step") \
				<Int64CodecScript.parse(record.dismissed_step_index,"dismissed step") \
			or Int64CodecScript.parse(record.encounter_eligible_after_step,"eligible step") \
				< Int64CodecScript.parse(record.dismissed_step_index,"dismissed step"):
		return "invalid_exile_record_time_or_id"
	if not record.display_name is String or str(record.display_name).is_empty() \
			or not record.species_id is String or str(record.species_id).is_empty():
		return "invalid_exile_record_identity"
	if not record.personality_summary is Dictionary:
		return "invalid_exile_personality_summary"
	var summary_keys:Array=record.personality_summary.keys();summary_keys.sort()
	var expected_summary_keys := ["A","C","E","H","O","X","profile_hash","style_label"] \
		if require_hexaco else ["aggression","altruism","archetype_id",
			"archetype_label","boldness","composure","profile_hash"]
	if summary_keys != expected_summary_keys \
			or (require_hexaco and not record.personality_summary.style_label is String) \
			or (not require_hexaco and (not record.personality_summary.archetype_id is String \
				or not record.personality_summary.archetype_label is String)) \
			or not record.personality_summary.profile_hash is String \
			or str(record.personality_summary.profile_hash).length()!=64:
		return "invalid_exile_personality_summary"
	for facet_key in (PartyHexacoScript.FACETS if require_hexaco else \
			["aggression","altruism","boldness","composure"]):
		if not _integer(record.personality_summary.get(facet_key)) \
				or int(record.personality_summary[facet_key])<0 \
				or int(record.personality_summary[facet_key])>1000:
			return "invalid_exile_personality_summary"
	if not record.alive is bool or not _integer(record.current_hp) or not _integer(record.max_hp) \
			or int(record.max_hp)<=0 or int(record.current_hp)<0 or int(record.current_hp)>int(record.max_hp) \
			or bool(record.alive)!=(int(record.current_hp)>0) or not _integer(record.safety) \
			or int(record.safety)<0 or int(record.safety)>1000:
		return "invalid_exile_actor_vitals"
	if not record.location_id is String or str(record.location_id).is_empty():return "invalid_exile_location"
	if not record.condition_snapshot is Dictionary or not record.emotion_modifiers is Dictionary \
			or not record.relationship_snapshot is Dictionary:return "invalid_exile_state_summary"
	var condition_keys:Array=record.condition_snapshot.keys();condition_keys.sort()
	if condition_keys!=["condition_band","harmful_status","hp","hp_percent","stress"] \
			or record.condition_snapshot.condition_band not in ["HEALTHY","STRAINED","ENDANGERED"] \
			or not record.condition_snapshot.harmful_status is bool:
		return "invalid_exile_condition_snapshot"
	for score in [record.condition_snapshot.hp,record.condition_snapshot.hp_percent,record.condition_snapshot.stress]:
		if not _integer(score) or int(score)<0 or int(score)>1000:return "invalid_exile_condition_snapshot"
	var emotion_keys:Array=record.emotion_modifiers.keys();emotion_keys.sort()
	if emotion_keys!=["fear_delta","resentment_delta"]:return "invalid_exile_emotion_modifiers"
	for score in record.emotion_modifiers.values():
		if not _integer(score) or int(score)<0 or int(score)>100:return "invalid_exile_emotion_modifiers"
	var relation_keys:Array=record.relationship_snapshot.keys();relation_keys.sort()
	if relation_keys!=["fear","gratitude","grievance","hostility","trust"]:return "invalid_exile_relationship_snapshot"
	for score in record.relationship_snapshot.values():
		if not _integer(score) or int(score)<-100 or int(score)>100:return "invalid_exile_relationship_snapshot"
	if not record.initial_status_effects is Array or not record.status_effects is Array \
			or record.initial_status_effects.size()>4 or record.status_effects.size()>4:
		return "invalid_exile_status_effects"
	for rows in [record.initial_status_effects,record.status_effects]:
		var status_error:=_exile_status_effects_error(rows)
		if not status_error.is_empty():return status_error
	if not _integer(record.initial_safety) or int(record.initial_safety)<0 or int(record.initial_safety)>1000:
		return "invalid_exile_actor_vitals"
	if not record.alive and (record.current_behavior!="DEAD" or not record.status_effects.is_empty()):
		return "invalid_dead_exile_actor_state"
	return ""

static func _exile_status_effects_error(rows:Array)->String:
	var previous_status:=""
	for status in rows:
		if not status is Dictionary:return "invalid_exile_status_effect"
		var status_keys:Array=status.keys();status_keys.sort()
		if status_keys!=["remaining_ticks","status_id","tick_damage"] \
				or not status.status_id is String or str(status.status_id)<=previous_status \
				or not _integer(status.remaining_ticks) or int(status.remaining_ticks)<1 or int(status.remaining_ticks)>16 \
				or not _integer(status.tick_damage) or int(status.tick_damage)<0 or int(status.tick_damage)>100:
			return "invalid_exile_status_effect"
		previous_status=str(status.status_id)
	return ""

static func _position(value: Variant, width: int, height: int) -> bool:
	return value is Array and value.size() == 2 and _integer(value[0]) and _integer(value[1]) and value[0] >= 0 and value[1] >= 0 and value[0] < width and value[1] < height

static func _facing(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _integer(value[0]) and _integer(value[1]) \
		and Vector2i(int(value[0]), int(value[1])) in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

static func _integer(value: Variant) -> bool:
	return value is int or (value is float and value == floor(value))
