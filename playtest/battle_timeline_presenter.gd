class_name BattleTimelinePresenter
extends RefCounted

## Pure projection of core readiness into the top action timeline DTO.
## Reads only the value dictionary it is given; never touches world, RNG or time.
## Spec: docs/concepts/BATTLE_ACTION_TIMELINE_HANDOFF.ko.md §4, §7.

const HORIZON_WORLD_TIME := 300
const MAX_VISIBLE_ENEMIES := 3
const ACTION_ROOT_TYPES := ["action.skill", "action.move", "action.melee_attack", "action.hold", "action.wait"]
const ALLY_MARKERS := ["①", "②", "③", "④", "⑤", "⑥"]
const ENEMY_MARKERS := ["A", "B", "C"]


static func build(input: Dictionary) -> Dictionary:
	var world_time := int(input.get("world_time", 0))
	var interval := maxi(1, int(input.get("actor_interval", 100)))
	var engaged := bool(input.get("engaged", false))
	var entries: Array = []
	var allies: Array = input.get("allies", [])
	var ally_rows: Array = []
	for raw in allies:
		if not raw is Dictionary or not bool(raw.get("alive", false)): continue
		ally_rows.append(raw)
	ally_rows.sort_custom(_by_slot)
	for index in range(ally_rows.size()):
		var row: Dictionary = ally_rows[index]
		var ready_at := int(row.busy_until)
		entries.append(_entry(row, "ALLY", ALLY_MARKERS[mini(index, ALLY_MARKERS.size() - 1)],
			ready_at, null, world_time, bool(row.get("can_act", true)), "READINESS_ONLY"))
	# Every observed participant is shown: an alive, visible enemy that has not yet
	# noticed the party is still on the field (spec 3), so it takes an entry with no
	# predicted moment rather than vanishing. Aware enemies sort first by their real
	# readiness; unaware ones follow in id order and share the cap and the +N count.
	var aware_rows: Array = []
	var unaware_rows: Array = []
	for raw in input.get("enemies", []):
		if not raw is Dictionary or not bool(raw.get("alive", false)) \
				or not bool(raw.get("visible", false)): continue
		if bool(raw.get("aware", false)): aware_rows.append(raw)
		else: unaware_rows.append(raw)
	aware_rows.sort_custom(_by_busy_until)
	unaware_rows.sort_custom(_by_entity_id)
	var enemy_rows: Array = aware_rows + unaware_rows
	var hidden := maxi(0, enemy_rows.size() - MAX_VISIBLE_ENEMIES)
	for index in range(mini(MAX_VISIBLE_ENEMIES, enemy_rows.size())):
		var row: Dictionary = enemy_rows[index]
		var ready_at := int(row.busy_until)
		if index >= aware_rows.size():
			# Unaware: the busy row is still a real core value, but nothing about when
			# this enemy joins the fight is known, so it never claims a moment or the
			# next mark.
			entries.append(_entry(row, "ENEMY", ENEMY_MARKERS[index], ready_at, null, world_time,
				false, "READINESS_ONLY"))
			continue
		# Enemies act only on actor ticks: the earliest real chance is the first tick
		# at or after max(ready_at, now). This is an expectation, not a confirmation.
		var eligible_at := maxi(ready_at,world_time) if bool(input.get("individual",false)) \
			else _ceil_to_interval(maxi(ready_at, world_time), interval)
		entries.append(_entry(row, "ENEMY", ENEMY_MARKERS[index], ready_at, eligible_at, world_time,
			bool(row.get("can_act", true)), "READINESS_ONLY" if bool(input.get("individual",false)) else "EXPECTED"))
	_assign_groups(entries, world_time)
	_mark_next(entries)
	return {"individual":bool(input.get("individual",false)),"revision": int(input.get("revision", 0)), "world_time": world_time, "phase": str(input.get("phase", "")),
		"visible": engaged and not entries.is_empty(), "entries": entries,
		"hidden_visible_enemy_count": hidden,
		"recent_actions": _recent_actions(input.get("recent_events", []))}


static func _by_slot(a: Dictionary, b: Dictionary) -> bool:
	if int(a.roster_slot) != int(b.roster_slot): return int(a.roster_slot) < int(b.roster_slot)
	return int(a.entity_id) < int(b.entity_id)


static func _by_busy_until(a: Dictionary, b: Dictionary) -> bool:
	if int(a.busy_until) != int(b.busy_until): return int(a.busy_until) < int(b.busy_until)
	return int(a.entity_id) < int(b.entity_id)


static func _by_entity_id(a: Dictionary, b: Dictionary) -> bool:
	return int(a.entity_id) < int(b.entity_id)


static func _entry(row: Dictionary, side: String, marker: String, ready_at: int, eligible_at,
		world_time: int, can_act: bool, confidence: String) -> Dictionary:
	var status := "UNAVAILABLE"
	if can_act: status = "READY" if ready_at <= world_time else "RECOVERING"
	return {"entity_id": int(row.entity_id), "side": side, "display_name": str(row.get("display_name", "")),
		"portrait_key": str(row.get("species_id", "")), "marker": marker,
		"ready_at": ready_at, "eligible_at": eligible_at, "status": status,
		"group_key": "", "timing_confidence": confidence, "is_next_candidate": false}


static func _ceil_to_interval(value: int, interval: int) -> int:
	return int(ceil(float(value) / float(interval))) * interval


## Earliest moment the entry can act: the expected tick when the core gives one,
## the raw readiness otherwise. Never null, so ordering stays total.
static func _acts_at(entry: Dictionary) -> int:
	return int(entry.eligible_at) if entry.eligible_at != null else int(entry.ready_at)


static func _assign_groups(entries: Array, world_time: int) -> void:
	# Same side + same drawn moment = same group. Anything already due sits at the
	# center (§4: remaining = max(0, ready_at - world_time)), so a party batch that
	# settled at 120 keeps its 80-cost and 120-cost members together instead of
	# inventing a separate earlier slot for the faster one. Groups never mix sides.
	# An unaware enemy (ENEMY side, no predicted moment) has no moment to share, so it
	# gets a group of its own instead of merging into a timed one.
	for entry in entries:
		if str(entry.side) == "ENEMY" and entry.eligible_at == null:
			entry["group_key"] = "ENEMY@unaware:%d" % int(entry.entity_id)
			continue
		entry["group_key"] = "%s@%d" % [str(entry.side), maxi(_acts_at(entry), world_time)]


static func _mark_next(entries: Array) -> void:
	# Earliest expected moment wins, then the earlier raw readiness. A genuine full
	# tie -- same acts_at and same ready_at -- marks every tied group whatever the
	# side: they are equally next and the core decides at execution. The UI never
	# invents an ally-first or low-id priority of its own (spec 4).
	var best_at := 0; var best_ready := 0; var found := false
	for entry in entries:
		if str(entry.status) == "UNAVAILABLE": continue
		var acts_at := _acts_at(entry)
		var ready_at := int(entry.ready_at)
		if found and (acts_at > best_at or (acts_at == best_at and ready_at >= best_ready)): continue
		best_at = acts_at; best_ready = ready_at; found = true
	var next_groups: Array = []
	for entry in entries:
		if str(entry.status) == "UNAVAILABLE": continue
		if _acts_at(entry) != best_at or int(entry.ready_at) != best_ready: continue
		var key := str(entry.group_key)
		if not key in next_groups: next_groups.append(key)
	for entry in entries:
		entry["is_next_candidate"] = found and str(entry.status) != "UNAVAILABLE" \
			and str(entry.group_key) in next_groups


static func _recent_actions(events: Array) -> Array:
	var rows: Array = []
	for raw in events:
		if not raw is Dictionary: continue
		var type := str(raw.get("type", ""))
		if not type in ACTION_ROOT_TYPES: continue
		rows.append({"event_id": int(raw.get("event_id", -1)), "actor_id": int(raw.get("actor_id", -1)),
			"acted_at": int(raw.get("world_time", 0)),
			"action_kind": type.trim_prefix("action.").to_upper().replace("MELEE_ATTACK", "ATTACK"),
			"batch_key": "step:%d" % int(raw.get("step_index", -1))})
	rows.sort_custom(_by_event_id)
	return rows


static func _by_event_id(a: Dictionary, b: Dictionary) -> bool:
	return int(a.event_id) < int(b.event_id)
