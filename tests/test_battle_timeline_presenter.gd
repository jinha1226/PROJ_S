extends "res://tests/test_case.gd"

const Presenter = preload("res://playtest/battle_timeline_presenter.gd")


func _ally(id: int, name: String, slot: int, busy: int, alive := true, can_act := true) -> Dictionary:
	return {"entity_id": id, "display_name": name, "species_id": "human", "roster_slot": slot,
		"busy_until": busy, "alive": alive, "can_act": can_act}


func _enemy(id: int, name: String, busy: int, visible := true, aware := true, alive := true) -> Dictionary:
	return {"entity_id": id, "display_name": name, "species_id": "goblin", "busy_until": busy,
		"alive": alive, "can_act": alive, "visible": visible, "aware": aware}


func _input(world_time: int, allies: Array, enemies: Array, events: Array = []) -> Dictionary:
	return {"world_time": world_time, "actor_interval": 100, "phase": "ENGAGED", "engaged": true,
		"allies": allies, "enemies": enemies, "recent_events": events}


func test_batch_boundary_allies_ready_together_are_one_group_at_center() -> bool:
	# Costs 80/120 in one party batch: the batch settled at 120, so both are READY now.
	var state: Dictionary = Presenter.build(_input(120, [_ally(1, "A", 0, 80), _ally(2, "B", 1, 120)], [_enemy(9, "g", 0)]))
	var a: Dictionary = state.entries[0]; var b: Dictionary = state.entries[1]
	check_eq(str(a.status), "READY", "ally ready before settle time is READY, not a fake new cooldown")
	check_eq(str(b.status), "READY", "ally ready exactly at settle time is READY")
	check_eq(int(a.ready_at), 80, "ready_at is the raw busy_until")
	check_eq(str(a.group_key), str(b.group_key), "same-time allies share one group key")
	check_eq(str(a.marker), "①", "allies carry roster numbers")
	check_eq(str(b.marker), "②", "second ally is ②")
	return finish()


func test_enemy_eligible_at_rounds_up_to_the_next_actor_tick() -> bool:
	# busy_until 170 but actor ticks run every 100: the earliest real chance is 200.
	var state: Dictionary = Presenter.build(_input(120, [_ally(1, "A", 0, 120)], [_enemy(9, "g", 170)]))
	var enemy: Dictionary = state.entries[1]
	check_eq(int(enemy.ready_at), 170, "enemy ready_at is the raw busy row")
	check_eq(int(enemy.eligible_at), 200, "enemy eligible_at is the next actor tick at or after ready_at")
	check_eq(str(enemy.timing_confidence), "EXPECTED", "tick-rounded enemy timing is an expectation, not a confirmation")
	check_eq(str(enemy.status), "RECOVERING", "future ready is RECOVERING")
	return finish()


func test_ready_ally_is_the_next_candidate_before_a_later_enemy() -> bool:
	var state: Dictionary = Presenter.build(_input(120, [_ally(1, "A", 0, 80)], [_enemy(9, "g", 170)]))
	check(bool(state.entries[0].is_next_candidate), "the earliest eligible entry is next")
	check(not bool(state.entries[1].is_next_candidate), "later entries are not next")
	check_eq(str(state.entries[0].timing_confidence), "READINESS_ONLY", "ally readiness is not a confirmed order")
	return finish()


func test_unaware_or_hidden_enemies_and_dead_actors_are_excluded() -> bool:
	var enemies := [_enemy(9, "g", 0), _enemy(10, "h", 0, false), _enemy(11, "u", 0, true, false), _enemy(12, "d", 0, true, true, false)]
	var state: Dictionary = Presenter.build(_input(120, [_ally(1, "A", 0, 120), _ally(2, "B", 1, 120, false)], enemies))
	var ids: Array = []
	for entry in state.entries: ids.append(int(entry.entity_id))
	check_eq(ids, [1, 9], "dead ally, hidden enemy, unaware enemy and dead enemy are all absent")
	check_eq(int(state.hidden_visible_enemy_count), 0, "hidden/unaware enemies never count toward +N")
	return finish()


func test_enemy_cap_three_earliest_and_hidden_count() -> bool:
	var enemies := [_enemy(9, "a", 300), _enemy(10, "b", 100), _enemy(11, "c", 200), _enemy(12, "d", 250), _enemy(13, "e", 150)]
	var state: Dictionary = Presenter.build(_input(120, [_ally(1, "A", 0, 120)], enemies))
	var enemy_ids: Array = []; var markers: Array = []
	for entry in state.entries:
		if str(entry.side) == "ENEMY": enemy_ids.append(int(entry.entity_id)); markers.append(str(entry.marker))
	check_eq(enemy_ids, [10, 13, 11], "only the three earliest visible participating enemies are shown, in time order")
	check_eq(markers, ["A", "B", "C"], "shown enemies carry A/B/C markers")
	check_eq(int(state.hidden_visible_enemy_count), 2, "the rest of the observed participants are counted as +N")
	return finish()


func test_next_candidate_moves_when_the_earliest_dies() -> bool:
	var alive: Dictionary = Presenter.build(_input(120, [_ally(1, "A", 0, 200)], [_enemy(9, "g", 100), _enemy(10, "h", 150)]))
	check_eq(int(_next(alive).entity_id), 9, "earliest live enemy is next")
	var dead: Dictionary = Presenter.build(_input(120, [_ally(1, "A", 0, 200)], [_enemy(9, "g", 100, true, true, false), _enemy(10, "h", 150)]))
	check_eq(int(_next(dead).entity_id), 10, "next candidate moves immediately when the earliest dies")
	return finish()


func test_recent_actions_use_root_events_only_and_batch_by_step() -> bool:
	var events := [
		{"event_id": 40, "step_index": 7, "world_time": 100, "type": "action.melee_attack", "actor_id": 1},
		{"event_id": 41, "step_index": 7, "world_time": 100, "type": "combat.physical_damage", "actor_id": -1},
		{"event_id": 42, "step_index": 7, "world_time": 100, "type": "action.hold", "actor_id": 2},
		{"event_id": 43, "step_index": 7, "world_time": 100, "type": "action.move", "actor_id": 9},
		{"event_id": 44, "step_index": 8, "world_time": 200, "type": "action.skill", "actor_id": 1},
	]
	var state: Dictionary = Presenter.build(_input(200, [_ally(1, "A", 0, 200), _ally(2, "B", 1, 200)], [_enemy(9, "g", 300)], events))
	check_eq(state.recent_actions.size(), 4, "derived damage events are not actions")
	check_eq(str(state.recent_actions[0].batch_key), str(state.recent_actions[2].batch_key), "same step shares a batch key")
	check(str(state.recent_actions[3].batch_key) != str(state.recent_actions[0].batch_key), "a new step is a new batch")
	check_eq(str(state.recent_actions[3].action_kind), "SKILL", "action kinds are derived from the root event type")
	return finish()


func test_not_engaged_is_invisible_and_pure() -> bool:
	var input := _input(120, [_ally(1, "A", 0, 120)], [_enemy(9, "g", 0)])
	input["engaged"] = false
	var frozen := JSON.stringify(input)
	var state: Dictionary = Presenter.build(input)
	check(not bool(state.visible), "timeline is hidden outside ENGAGED")
	check_eq(JSON.stringify(input), frozen, "build does not mutate its input")
	return finish()


func _next(state: Dictionary) -> Dictionary:
	for entry in state.entries:
		if bool(entry.is_next_candidate): return entry
	return {}
