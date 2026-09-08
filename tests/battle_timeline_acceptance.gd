extends SceneTree

## Bounded acceptance for the read-only battle timeline query.
## The session facade must project canonical readiness without touching RNG,
## events, world time, energy, the journal or staged plans.
## Spec: docs/concepts/BATTLE_ACTION_TIMELINE_HANDOFF.ko.md §7.

const Session = preload("res://playtest/party_playtest_session.gd")
const Presenter = preload("res://playtest/battle_timeline_presenter.gd")
const SimCommand = preload("res://sim/sim_command.gd")
const Bar = preload("res://playtest/battle_timeline_bar.gd")

const WORLD_SEED := 44
const PERSONALITY_SEED := 20260828

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_case("timeline_query_is_pure_and_matches_core", _timeline_query_is_pure_and_matches_core)
	_case("timeline_hides_outside_engaged_and_survives_reload", _timeline_hides_outside_engaged_and_survives_reload)
	_case("bar_layout_places_sides_center_groups_and_cap", _bar_layout_places_sides_center_groups_and_cap)
	if failures.is_empty():
		print("PASS battle timeline acceptance")
	else:
		for failure in failures: printerr("FAIL ", failure)
		print("FAIL battle timeline acceptance: ", failures.size(), " failures")
	quit(1 if not failures.is_empty() else 0)

func _case(label: String, callback: Callable) -> void:
	var before := failures.size()
	var result = callback.call()
	if result != true and failures.size() == before: failures.append(label + " did not return true")
	if failures.size() == before: print("PASS timeline :: ", label)

func _check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _check_eq(got: Variant, expected: Variant, message: String) -> void:
	if got != expected: failures.append("%s (expected %s, got %s)" % [message, str(expected), str(got)])

func _new_engaged_duo():
	var session = Session.new(WORLD_SEED, PERSONALITY_SEED, Session.DUO_SCENARIO_ID)
	if session.sim == null:
		_check(false, "DUO session did not initialize"); return null
	var state = session.sim.world.party_encounter
	var hero_id := int(state.protagonist_id)
	var best: Dictionary = {}
	for enemy_id_value in state.enemy_ids:
		var enemy_id := int(enemy_id_value)
		if not session.sim.world.is_unresolved_enemy(enemy_id): continue
		var enemy_position: Vector2i = session.sim.world.entities[enemy_id].position
		for delta in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var path: Dictionary = session.find_exploration_path(hero_id, enemy_position + delta)
			if bool(path.get("found", false)) and (best.is_empty() or path.path.size() < best.path.size()): best = path
		if not best.is_empty() and best.path.size() <= 4: break
	if best.is_empty():
		_check(false, "normal generated DUO map has no route to an encounter"); return null
	for value in best.path.slice(1):
		var step: Dictionary = session.commit_exploration(SimCommand.move_to(hero_id, value))
		if not bool(step.get("accepted", false)):
			_check(false, "normal route step rejected: %s" % str(step.get("reason", ""))); return null
		if str(session.party_status().get("safe_phase", "")) == "CONTACT": break
	_check_eq(session.party_status().get("safe_phase", ""), "CONTACT", "generated route reaches contact")
	if str(session.party_status().get("safe_phase", "")) != "CONTACT": return null
	var companion_id := int(state.party_member_ids[1])
	var preview: Dictionary = session.preview_deployment("LINE", [companion_id])
	_check(bool(preview.get("accepted", false)), "normal deployment preview accepts companion")
	if not bool(preview.get("accepted", false)): return null
	var committed: Dictionary = session.commit_deployment()
	_check(bool(committed.get("accepted", false)), "normal deployment enters combat")
	_check_eq(session.party_status().get("safe_phase", ""), "ENGAGED", "generated deployment enters ENGAGED")
	return session

func _timeline_query_is_pure_and_matches_core() -> bool:
	var session = _new_engaged_duo()
	if session == null: return false
	var world = session.sim.world
	var before_hash := JSON.stringify(world.snapshot()).sha256_text()
	var journal_before: int = session.command_journal.size()
	var events_before: int = world.events.size()
	var state: Dictionary = session.battle_timeline_state()
	var again: Dictionary = session.battle_timeline_state()
	_check_eq(JSON.stringify(world.snapshot()).sha256_text(), before_hash, "timeline query leaves the snapshot untouched")
	_check_eq(session.command_journal.size(), journal_before, "timeline query writes no journal row")
	_check_eq(world.events.size(), events_before, "timeline query emits no event")
	_check_eq(JSON.stringify(state), JSON.stringify(again), "repeated query is identical (cached)")
	_check(bool(state.visible), "engaged duo battle shows the timeline")
	var party = world.party_encounter
	for entry in state.entries:
		var id := int(entry.entity_id)
		if str(entry.side) == "ALLY":
			_check_eq(int(entry.ready_at), int(party.member(id).busy_until), "ally ready_at mirrors busy_until")
		else:
			_check_eq(int(entry.ready_at), int(party.enemy_busy_rows.get(id, 0)), "enemy ready_at mirrors the busy row")
			_check(id in session.party_status().visible_enemy_ids, "shown enemies are visible participants")
			# An observed participant that has not noticed the party yet is shown but
			# never given a predicted moment (spec §3, §4).
			var awareness = party.enemy_awareness(id)
			if awareness != null and str(awareness.awareness_state) in ["ALERT", "HUNTING"]:
				_check(entry.eligible_at != null, "an aware enemy carries a predicted actor tick")
			else:
				_check_eq(str(entry.status), "UNAVAILABLE", "an unaware participant is UNAVAILABLE")
				_check_eq(entry.eligible_at, null, "an unaware participant has no predicted moment")
	# One autonomous commit: recent actions must cite real root events of that step.
	var planning: Dictionary = session.prepare_autonomous_party_turn()
	_check(bool(planning.get("commit_ready", false)), "autonomous plan is committable")
	var result: Dictionary = session.commit_turn()
	_check(bool(result.get("accepted", false)), "autonomous commit accepted")
	var after: Dictionary = session.battle_timeline_state()
	_check(after.recent_actions.size() >= 1, "committed turn yields recent root actions")
	for action in after.recent_actions:
		var event = world.event_by_id(int(action.event_id))
		_check(event != null and str(event.type) in Presenter.ACTION_ROOT_TYPES, "recent action cites a real root event")
		_check_eq(int(action.acted_at), int(event.world_time), "acted_at is the event world time")
	_check(JSON.stringify(after) != JSON.stringify(state), "state revision changes after a commit")
	return true

func _timeline_hides_outside_engaged_and_survives_reload() -> bool:
	var fresh = Session.new(WORLD_SEED, PERSONALITY_SEED, Session.DUO_SCENARIO_ID)
	_check(not bool(fresh.battle_timeline_state().visible), "exploration shows no timeline")
	var session = _new_engaged_duo()
	if session == null: return false
	var saved: String = session.save_session_json()
	var reloaded = Session.new(WORLD_SEED, PERSONALITY_SEED, Session.DUO_SCENARIO_ID)
	_check(bool(reloaded.load_session_json(saved).get("accepted", false)), "engaged save reloads")
	var rebuilt: Dictionary = reloaded.battle_timeline_state()
	_check(bool(rebuilt.visible), "reloaded engaged battle rebuilds the timeline from core state")
	_check(rebuilt.recent_actions.is_empty() or int(rebuilt.recent_actions.back().acted_at) <= int(reloaded.sim.world.world_time), "reload never replays future actions")
	return true


func _bar_layout_places_sides_center_groups_and_cap() -> bool:
	var entries := [
		{"entity_id":1,"side":"ALLY","display_name":"A","portrait_key":"human","marker":"①","ready_at":80,"eligible_at":null,"status":"READY","group_key":"ALLY@80","timing_confidence":"READINESS_ONLY","is_next_candidate":true},
		{"entity_id":2,"side":"ALLY","display_name":"B","portrait_key":"human","marker":"②","ready_at":80,"eligible_at":null,"status":"READY","group_key":"ALLY@80","timing_confidence":"READINESS_ONLY","is_next_candidate":true},
		{"entity_id":9,"side":"ENEMY","display_name":"g","portrait_key":"goblin","marker":"A","ready_at":170,"eligible_at":200,"status":"RECOVERING","group_key":"ENEMY@200","timing_confidence":"EXPECTED","is_next_candidate":false},
		{"entity_id":10,"side":"ENEMY","display_name":"h","portrait_key":"goblin","marker":"B","ready_at":700,"eligible_at":700,"status":"RECOVERING","group_key":"ENEMY@700","timing_confidence":"EXPECTED","is_next_candidate":false},
	]
	var state := {"revision":1,"world_time":120,"phase":"ENGAGED","visible":true,"entries":entries,"hidden_visible_enemy_count":2,"recent_actions":[]}
	for width in [360.0, 390.0]:
		var spec: Dictionary = Bar.layout_spec(state, width)
		var ally_items: Array = []; var enemy_items: Array = []
		for item in spec.items:
			if str(item.side) == "ALLY": ally_items.append(item)
			else: enemy_items.append(item)
		_check_eq(ally_items.size(), 1, "%d: two allies at the same moment collapse into one group item" % int(width))
		_check_eq(ally_items[0].entity_ids, [1, 2], "%d: group item lists both allies" % int(width))
		_check_eq(str(ally_items[0].group_label), "같은 행동 묶음", "%d: same group key is labelled as one batch" % int(width))
		_check(float(ally_items[0].x) < spec.center.position.x + 0.5 and float(ally_items[0].x) >= spec.center.position.x - 1.0, "%d: ready allies sit at the left edge of the center zone" % int(width))
		_check_eq(enemy_items.size(), 2, "%d: enemies at different times stay separate" % int(width))
		var near: Dictionary = enemy_items[0]; var far: Dictionary = enemy_items[1]
		_check(float(near.x) > spec.center.end.x - 0.5 and float(near.x) < float(far.x), "%d: nearer enemy is closer to center on the right" % int(width))
		_check(bool(far.out_of_range) and float(far.x) >= spec.right_rail.end.x - 24.0, "%d: beyond-horizon enemy is pinned at the outer end with a marker" % int(width))
		_check_eq(str(spec.hidden_label), "+2", "%d: hidden participants show as +N" % int(width))
		for item in spec.items:
			var touch: Rect2 = item.touch
			_check(touch.size.x >= 47.9 and touch.size.y >= 47.9, "%d: every touch target is at least 48px" % int(width))
			_check(touch.position.x >= -0.1 and touch.end.x <= width + 0.1, "%d: touch targets stay inside the bar" % int(width))
	return true
