# Hero-Turn Combat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dungeon combat stops at every protagonist turn; one tap = one protagonist action (melee / one step / hold / skill), then companions and enemies resolve automatically until the next protagonist turn. The old free-running clock stays as an `AUTO` toggle.

**Architecture:** The event-driven scheduler (`sim/systems/individual_battle_scheduler.gd`) already commits one actor event at a time and consumes per-actor reservations. We add one reservation kind (`reserve_action`: MELEE / MOVE / HOLD) that replaces the auto suggestion for that actor's next event, journaled and replayed like `reserve_skill`. The sandbox gains a presentation-only `battle_mode` (`HERO_TURN` default, `AUTO`); in `HERO_TURN` the display clock does not advance past the protagonist's next event while the protagonist has no reservation. Nothing in the ledger changes except the new journal kinds.

**Tech Stack:** Godot 4.6 GDScript, headless tests via `godot --headless --path . --script res://tests/<file>.gd`. Never run two Godot processes in the same project dir at once.

**Spec:** `docs/superpowers/specs/2026-09-09-hero-turn-combat-design.md`

## Global Constraints

- Canonical simulation rules (action times, damage, targeting) are unchanged. Only the scheduler's choice of action for an actor with an action reservation changes.
- Every new journal row has an exact key shape validated by `IndividualBattleScript.operation_error`; `_journal_wire_error` rejects anything else. Replay must reproduce the same snapshot.
- Reservations are UI-side state (not serialized); a loaded session starts without reservations, in `HERO_TURN`.
- One actor holds at most one of {skill reservation, action reservation}; a new reservation overwrites the other kind.
- `battle_mode` is a sandbox variable, never saved. Default `HERO_TURN`. Headless suites that assume a free-running clock set `ui.battle_mode="AUTO"` in their fixture.
- Display-speed constants: `AUTO` keeps `WORLD_UNITS_PER_SECOND 200`; `HERO_TURN` uses `HERO_TURN_UNITS_PER_SECOND 400`.
- Korean UI copy exactly as written in the tasks.
- Commit messages end with the two trailers used in this repo (Co-Authored-By Claude Fable 5.1, Claude-Session URL).

---

### Task 1: Action reservations in the scheduler, session, and journal

**Files:**
- Modify: `sim/systems/individual_battle_scheduler.gd` (`step`, `_ally_row`)
- Modify: `playtest/individual_battle_session.gd` (`reserve_action`, `cancel_action`, `reserve`, `operation_error`, `commit`)
- Modify: `playtest/party_playtest_session.gd` (journal replay switch near line 7441; `_journal_wire_error` kind list near line 7869)
- Test: `tests/hero_action_reservation_acceptance.gd` (new, SceneTree, extends `res://tests/battle_timeline_acceptance.gd` for `_new_engaged_duo`, `_check`, `_check_eq`, `failures`)

**Interfaces:**
- Produces: `individual_battle.reserve_action(actor_id:int, action:Dictionary, append_journal:bool=true)->Dictionary` where `action` is `{"type":"MELEE","target_id":int}` | `{"type":"MOVE","destination":[x,y]}` | `{"type":"HOLD"}`; returns `{"accepted","reason","message"}`.
- Produces: `individual_battle.cancel_action(actor_id:int, append_journal:bool=true)->Dictionary`.
- Produces: `individual_battle.queued(actor_id)` now returns either `{"skill_id","target_id"}` or `{"action":{...}}`.
- Produces: `commit()` DTO keeps `reservation_rejection` ("예약 조건이 달라져 기본 행동을 했습니다.") when a reserved action could not run.
- Journal kinds: `reserve_action` `{"actor_id":"<id>","type":"MELEE","target_id":"<id>"}` / `{"actor_id","type":"MOVE","destination":[x,y]}` / `{"actor_id","type":"HOLD"}`; `cancel_reserved_action` `{"actor_id"}`.

- [ ] **Step 1: Write the failing acceptance test**

```gdscript
extends "res://tests/battle_timeline_acceptance.gd"

const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
const SimCommand=preload("res://sim/sim_command.gd")

func _run()->void:
	var session=_new_engaged_duo()
	if session==null:quit(1);return
	var flow=session.individual_battle
	var world=session.sim.world;var state=world.party_encounter
	var hero:int=int(state.protagonist_id)
	# Walk the clock until the hero's own event is next.
	var guard:=0
	while not flow.next_event().is_empty() and int(flow.next_event().actor_id)!=hero and guard<40:
		_check(bool(flow.commit().get("accepted",false)),"pre-hero events commit");guard+=1
	_check_eq(int(flow.next_event().actor_id),hero,"fixture reaches a hero event")
	var hero_position:Vector2i=world.entities[hero].position
	# HOLD reservation: the hero holds instead of the auto suggestion.
	_check(bool(flow.reserve_action(hero,{"type":"HOLD"}).get("accepted",false)),"HOLD reservation accepted")
	_check_eq(flow.queued(hero),{"action":{"type":"HOLD"}},"queued exposes the action reservation")
	_check_eq(session.command_journal[-1],{"kind":"reserve_action","operation":{"actor_id":str(hero),"type":"HOLD"}},
		"HOLD reservation is journaled")
	var held:Dictionary=flow.commit()
	_check(bool(held.get("accepted",false)),"hero event commits with a HOLD reservation")
	var held_actions:Array=[]
	for id in held.get("event_ids",[]):
		var event=world.event_by_id(int(id))
		if event!=null and int(event.actor_id)==hero and str(event.type).begins_with("action."):held_actions.append(str(event.type))
	_check_eq(held_actions,["action.hold"],"reserved HOLD produces exactly one hold action")
	_check(flow.queued(hero).is_empty(),"action reservation is consumed")
	# MOVE reservation to an adjacent free cell.
	var step_target:=Vector2i(-1,-1)
	for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		var candidate:Vector2i=hero_position+delta
		if world.in_bounds(candidate) and world.blocking_entity_at(candidate,hero)==null \
				and bool(session.preview_exploration(SimCommand.move_to(hero,candidate)).get("accepted",false)):
			step_target=candidate;break
	if step_target!=Vector2i(-1,-1):
		_advance_to_hero(flow,hero)
		_check(bool(flow.reserve_action(hero,{"type":"MOVE","destination":[step_target.x,step_target.y]}).get("accepted",false)),"MOVE reservation accepted")
		var moved:Dictionary=flow.commit()
		_check(bool(moved.get("accepted",false)),"hero event commits with a MOVE reservation")
		_check_eq(world.entities[hero].position,step_target,"reserved MOVE walks one cell")
	# MELEE reservation against an adjacent enemy (walk toward one if needed).
	var enemy:=_adjacent_enemy(session,hero)
	var walked:=0
	while enemy<=0 and walked<12 and str(session.party_status().get("safe_phase",""))=="ENGAGED":
		_advance_to_hero(flow,hero)
		var nearest:=_nearest_enemy(session,hero)
		if nearest<=0:break
		var path:Dictionary=session.sim.pathfinder.find_path(hero,world.entities[nearest].position)
		if not bool(path.get("found",false)) or path.path.size()<2:break
		var next_cell:Vector2i=path.path[1]
		flow.reserve_action(hero,{"type":"MOVE","destination":[next_cell.x,next_cell.y]})
		flow.commit();walked+=1
		enemy=_adjacent_enemy(session,hero)
	if enemy>0:
		_advance_to_hero(flow,hero)
		_check(bool(flow.reserve_action(hero,{"type":"MELEE","target_id":enemy}).get("accepted",false)),"MELEE reservation accepted")
		var attacked:Dictionary=flow.commit()
		var melee:=0
		for id in attacked.get("event_ids",[]):
			var event=world.event_by_id(int(id))
			if event!=null and str(event.type)=="action.melee_attack" and int(event.actor_id)==hero and int(event.target_id)==enemy:melee+=1
		_check_eq(melee,1,"reserved MELEE attacks the reserved target")
	# Invalid at execution: reserve MELEE on a far enemy id, expect auto fallback + rejection note.
	var far:=_farthest_enemy(session,hero)
	if far>0 and _distance(world.entities[hero].position,world.entities[far].position)>1:
		_advance_to_hero(flow,hero)
		_check(not bool(flow.reserve_action(hero,{"type":"MELEE","target_id":far}).get("accepted",false)),
			"non-adjacent MELEE reservation is rejected at reservation time")
	# Reservation kinds are exclusive.
	_advance_to_hero(flow,hero)
	flow.reserve_action(hero,{"type":"HOLD"})
	var skills:Array=session.active_skill_rows(hero)
	if not skills.is_empty() and bool(skills[0].get("can_select",false)):
		var target:=_nearest_enemy(session,hero)
		if bool(flow.reserve(hero,str(skills[0].skill_id),target).get("accepted",false)):
			_check(not flow.queued(hero).has("action"),"a skill reservation replaces the action reservation")
	_check(bool(flow.cancel_action(hero).get("accepted",false)) or flow.queued(hero).is_empty() or flow.queued(hero).has("skill_id"),
		"cancel_action clears an action reservation")
	# Journal wire: malformed rows are rejected, the real journal replays exactly.
	_check(session._journal_wire_error([{"kind":"reserve_action","operation":{"actor_id":str(hero),"type":"DANCE"}}])!="",
		"unknown action type is rejected by the wire validator")
	_check(session._journal_wire_error([{"kind":"reserve_action","operation":{"actor_id":str(hero),"type":"MOVE"}}])!="",
		"MOVE without destination is rejected by the wire validator")
	_check_eq(session._journal_wire_error(session.command_journal),"","the exercised journal validates")
	var saved:String=session.save_session_json();var loaded=Session.new()
	var load_result:Dictionary=loaded.load_session_json(saved)
	_check(bool(load_result.get("accepted",false)),"session with action reservations reloads: %s"%str(load_result.get("reason","")))
	if bool(load_result.get("accepted",false)):
		_check_eq(loaded.sim.snapshot(),session.sim.snapshot(),"action reservations replay exactly")
	_finish("hero action reservation")

func _advance_to_hero(flow,hero:int)->void:
	var guard:=0
	while not flow.next_event().is_empty() and int(flow.next_event().actor_id)!=hero and guard<60:
		if not bool(flow.commit().get("accepted",false)):break
		guard+=1

func _adjacent_enemy(session,hero:int)->int:
	var world=session.sim.world
	for id in session.party_status().get("visible_enemy_ids",[]):
		if world.is_autonomous_target(int(id)) and _distance(world.entities[hero].position,world.entities[int(id)].position)==1:return int(id)
	return -1

func _nearest_enemy(session,hero:int)->int:
	var world=session.sim.world;var best:=-1;var best_distance:=999
	for id in session.party_status().get("visible_enemy_ids",[]):
		if not world.is_autonomous_target(int(id)):continue
		var d:=_distance(world.entities[hero].position,world.entities[int(id)].position)
		if d<best_distance:best_distance=d;best=int(id)
	return best

func _farthest_enemy(session,hero:int)->int:
	var world=session.sim.world;var best:=-1;var best_distance:=-1
	for id in session.party_status().get("visible_enemy_ids",[]):
		if not world.is_autonomous_target(int(id)):continue
		var d:=_distance(world.entities[hero].position,world.entities[int(id)].position)
		if d>best_distance:best_distance=d;best=int(id)
	return best

func _distance(a:Vector2i,b:Vector2i)->int:return maxi(absi(a.x-b.x),absi(a.y-b.y))

func _finish(label:String)->void:
	if failures.is_empty():print("PASS %s"%label);quit(0)
	else:
		for failure in failures:printerr("FAIL ",failure)
		printerr("FAIL %s: %d failures"%[label,failures.size()]);quit(1)
```

Check first that `tests/battle_timeline_acceptance.gd` defines `_new_engaged_duo`, `_check`, `_check_eq`, `failures` as used by `tests/individual_battle_acceptance.gd`; if its `_run` is not overridable this way, copy the fixture helper from `tests/individual_battle_acceptance.gd` instead of extending.

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path . --script res://tests/hero_action_reservation_acceptance.gd`
Expected: FAIL with `Nonexistent function 'reserve_action'`.

- [ ] **Step 3: Implement the session reservation API**

In `playtest/individual_battle_session.gd`:

```gdscript
const ActionCommand=preload("res://sim/party_action_command.gd")
const ACTION_TYPES:=["MELEE","MOVE","HOLD"]

func action_assessment(actor_id:int,action:Dictionary)->Dictionary:
	_bind()
	if _sim==null:return {"accepted":false,"reason":"individual_battle_not_engaged","message":"전투 중에만 행동을 지정할 수 있습니다."}
	var world=_sim.world;var party=world.party_encounter
	var kind:=str(action.get("type",""))
	if kind not in ACTION_TYPES:return {"accepted":false,"reason":"invalid_action_reservation","message":"지정할 수 없는 행동입니다."}
	if party.safe_phase!="ENGAGED" or actor_id not in party.active_party_member_ids \
			or party.member(actor_id)==null or party.member(actor_id).presence!="DEPLOYED" \
			or not world.can_act(actor_id,world.world_time):
		return {"accepted":false,"reason":"action_actor_unavailable","message":"행동 가능한 파티원을 선택하세요."}
	var command=_command_for(actor_id,action)
	if command==null:return {"accepted":false,"reason":"invalid_action_reservation","message":"지정할 수 없는 행동입니다."}
	if kind=="MELEE":
		var target_id:=int(action.get("target_id",-1))
		if not world.entities.has(target_id) or not world.is_autonomous_target(target_id) \
				or _sim.party_coordinator._distance(world.entities[actor_id].position,world.entities[target_id].position)!=1:
			return {"accepted":false,"reason":"action_target_not_adjacent","message":"인접한 적을 선택하세요."}
	var error:String=_sim.party_coordinator._action_error(command)
	if not error.is_empty():return {"accepted":false,"reason":error,"message":host.reason_message(error)}
	return {"accepted":true,"reason":"ok","message":{"MELEE":"공격 예약","MOVE":"한 걸음 예약","HOLD":"대기 예약"}[kind]}

func reserve_action(actor_id:int,action:Dictionary,append_journal:bool=true)->Dictionary:
	var assessed:=action_assessment(actor_id,action)
	if not bool(assessed.get("accepted",false)):return assessed
	queues[actor_id]={"action":_canonical_action(action)}
	if append_journal:
		var operation:Dictionary={"actor_id":str(actor_id),"type":str(action.type)}
		if str(action.type)=="MELEE":operation["target_id"]=str(int(action.target_id))
		elif str(action.type)=="MOVE":operation["destination"]=[int(action.destination[0]),int(action.destination[1])]
		host.command_journal.append({"kind":"reserve_action","operation":operation})
	return assessed

func cancel_action(actor_id:int,append_journal:bool=true)->Dictionary:
	_bind()
	if not queues.has(actor_id) or not queues[actor_id].has("action"):
		return {"accepted":false,"reason":"no_reserved_action"}
	queues.erase(actor_id)
	if append_journal:host.command_journal.append({"kind":"cancel_reserved_action","operation":{"actor_id":str(actor_id)}})
	return {"accepted":true,"reason":"ok","message":"예약 취소"}

func _canonical_action(action:Dictionary)->Dictionary:
	match str(action.get("type","")):
		"MELEE":return {"type":"MELEE","target_id":int(action.get("target_id",-1))}
		"MOVE":return {"type":"MOVE","destination":[int(action.destination[0]),int(action.destination[1])]}
	return {"type":"HOLD"}

func _command_for(actor_id:int,action:Dictionary):
	match str(action.get("type","")):
		"MELEE":return ActionCommand.melee(actor_id,int(action.get("target_id",-1)))
		"MOVE":
			var destination:Variant=action.get("destination",[])
			if not destination is Array or destination.size()!=2:return null
			return ActionCommand.move_to(actor_id,Vector2i(int(destination[0]),int(destination[1])))
		"HOLD":return ActionCommand.hold(actor_id)
	return null
```

`reserve` (skill) must overwrite any action reservation: it already assigns `queues[actor_id]={...}` so nothing changes there; `cancel` (skill) must only act when `queues[actor_id].has("skill_id")`.

In `commit()`, pass the reservation through unchanged (the scheduler reads either shape) and compute `reservation_failed` for both kinds:

```gdscript
	var queued_row:Dictionary=queues.get(int(next.actor_id),{})
	var result=Scheduler.step(host.sim,queued_row,movements.get(int(next.actor_id),Vector2i(-1,-1)),survival_rules)
	if not result.accepted:return host._rejection_dto(result.reason)
	var reservation_failed:bool=not queued_row.is_empty()
	for event in result.events:
		if int(event.actor_id)!=int(next.actor_id):continue
		if queued_row.has("skill_id") and event.type=="action.skill":reservation_failed=false
		if queued_row.has("action") and str(event.type)=={"MELEE":"action.melee_attack","MOVE":"action.move","HOLD":"action.hold"}[str(queued_row.action.type)]:reservation_failed=false
```

Extend `operation_error`:

```gdscript
	elif kind=="reserve_action":
		var action_type:=str(row.get("type",""))
		if action_type not in ["MELEE","MOVE","HOLD"]:return "invalid_reserved_action"
		if action_type=="MELEE":
			if keys!=["actor_id","target_id","type"] or not Codec.is_canonical(row.get("target_id")) \
					or Codec.parse(row.target_id,"action target")<=0:return "invalid_reserved_action"
		elif action_type=="MOVE":
			if keys!=["actor_id","destination","type"] or not row.get("destination") is Array \
					or row.destination.size()!=2:return "invalid_reserved_action"
			for value in row.destination:
				if not (value is int or value is float and value==floor(value)) \
						or value<0 or value>2147483647:return "invalid_reserved_action"
		elif keys!=["actor_id","type"]:return "invalid_reserved_action"
	elif kind=="cancel_reserved_action":
		if keys!=["actor_id"]:return "invalid_reserved_action_cancel"
```

Keep the trailing `actor_id` canonical check (it applies to the new kinds too).

- [ ] **Step 4: Implement the scheduler side**

In `sim/systems/individual_battle_scheduler.gd` `step`:

```gdscript
	var skill:Dictionary={};var row:Dictionary={};var skill_rejection:=""
	if actor_id>0 and party.member(actor_id)!=null:
		if reservation.has("skill_id"):
			skill=Skills.assess(world,actor_id,str(reservation.skill_id),int(reservation.target_id),false,true)
			if not bool(skill.get("accepted",false)):
				skill_rejection=str(skill.get("reason","active_skill_rejected"));skill.clear()
		if skill.is_empty():row=_ally_row(sim,actor_id,step_index,movement_goal,reservation.get("action",{}))
```

and in `_ally_row`:

```gdscript
static func _ally_row(sim,id:int,step_index:int,movement_goal:Vector2i=Vector2i(-1,-1),reserved_action:Dictionary={})->Dictionary:
	var coordinator=sim.party_coordinator;var world=sim.world;var party=world.party_encounter
	var seed=Action.hold(party.protagonist_id)
	var board:Dictionary=Blackboard.build(world,seed)
	if int(board.focus_target_id)>0:board.claims[party.protagonist_id]=int(board.focus_target_id)
	var action=null
	if not reserved_action.is_empty():
		action=_reserved_command(id,reserved_action)
		# A reserved basic action is re-validated at its event; a stale one falls
		# back to the ordinary suggestion exactly like a stale skill reservation.
		if action==null or not coordinator._action_error(action).is_empty():action=null
	if action==null:
		action=coordinator._suggest(id,seed,board)
		if movement_goal!=Vector2i(-1,-1):
			action=preload("res://sim/systems/battle_position_order.gd").action(sim,id,movement_goal,action)
	...unchanged from here (error check, _action_row, melee assessment)

static func _reserved_command(id:int,reserved:Dictionary):
	match str(reserved.get("type","")):
		"MELEE":return Action.melee(id,int(reserved.get("target_id",-1)))
		"MOVE":
			var destination:Variant=reserved.get("destination",[])
			if destination is Array and destination.size()==2:
				return Action.move_to(id,Vector2i(int(destination[0]),int(destination[1])))
			return null
		"HOLD":return Action.hold(id)
	return null
```

Also change `if not reservation.is_empty():` → `if reservation.has("skill_id"):` so an action reservation never reaches `Skills.assess`. The existing `_commit_skill_effect(...) if not skill.is_empty() else ...` branch is unchanged.

- [ ] **Step 5: Journal replay and validation in the session**

In `playtest/party_playtest_session.gd` replay `match` (next to `"reserve_move":`):

```gdscript
			"reserve_action":
				var operation:Dictionary=row.operation
				var action:Dictionary={"type":str(operation.type)}
				if str(operation.type)=="MELEE":action["target_id"]=int(operation.target_id)
				elif str(operation.type)=="MOVE":action["destination"]=[int(operation.destination[0]),int(operation.destination[1])]
				replay_result=replay.individual_battle.reserve_action(int(operation.actor_id),action)
			"cancel_reserved_action":
				replay_result=replay.individual_battle.cancel_action(int(row.operation.actor_id))
```

In `_journal_wire_error`, add `"reserve_action","cancel_reserved_action"` to the kind list that delegates to `IndividualBattleScript.operation_error`.

- [ ] **Step 6: Run the test and the neighbouring suites**

Run (sequentially): `hero_action_reservation_acceptance`, `individual_battle_acceptance`, `battle_timeline_acceptance`, `battle_timeline_integration`, `duo_autobattle_smoke`, `battleheart_mvp_acceptance` (known 4 pre-existing failures: "skill tap enters target mode" ×2, "skill mode pauses auto combat" ×2 — no new lines allowed).
Expected: new test PASS, others unchanged.

- [ ] **Step 7: Commit**

```bash
git add sim/systems/individual_battle_scheduler.gd playtest/individual_battle_session.gd playtest/party_playtest_session.gd tests/hero_action_reservation_acceptance.gd
git commit -m "feat(combat): journaled basic-action reservations (melee, step, hold) for the per-actor scheduler"
```

---

### Task 2: HERO_TURN clock policy in the sandbox

**Files:**
- Modify: `playtest/autonomous_battle_clock.gd`
- Modify: `playtest/individual_battle_session.gd` (`hero_turn_pending`)
- Modify: `playtest/party_encounter_sandbox.gd` (`battle_mode`, `_tick_autonomous_battle`, `_add_battle_portrait_utilities`, `_on_product_execute`, new `_on_battle_mode_toggle`)
- Modify: `playtest/battle_command_flow.gd` (`check_danger` and `paint` are AUTO-only; HERO_TURN notice)
- Test: `tests/hero_turn_combat_acceptance.gd` (new)
- Modify fixtures: `tests/duo_autobattle_smoke.gd`, `tests/battle_command_flow_acceptance.gd`, `tests/battle_timeline_integration.gd`, `tests/battle_tap_move_regression.gd`, `tests/battleheart_mvp_acceptance.gd` — set `ui.battle_mode="AUTO"` right after `initialize_for_headless_test`.

**Interfaces:**
- Consumes: Task 1 `reserve_action`, `queued`.
- Produces: `individual_battle.hero_turn_pending()->bool` — true when `next_event()` is the protagonist and `queues` has no entry for it (movement orders count as a reservation only in AUTO; in HERO_TURN the sandbox never creates them for the hero).
- Produces: sandbox `var battle_mode:="HERO_TURN"` (`"AUTO"` alternative), `const HERO_TURN_UNITS_PER_SECOND:=400.0`, `func hero_turn_waiting()->bool` (HERO_TURN and engaged and `hero_turn_pending()` and not blocked).
- Produces: clock `advance(delta, world_time, blocked, units_per_second:=WORLD_UNITS_PER_SECOND, hold_at:=-1.0)` — when `hold_at>=0` the cursor never exceeds `hold_at`.

- [ ] **Step 1: Write the failing acceptance test**

```gdscript
extends SceneTree

## HERO_TURN: the fight stops at every protagonist turn; one reservation lets
## the clock run to the next protagonist turn. AUTO keeps the free-running clock.

const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const SimCommand=preload("res://sim/sim_command.gd")
var failures:Array[String]=[]

func _init()->void:call_deferred("run")
func _check(value:bool,message:String)->void:
	if not value:failures.append(message);printerr("FAIL ",message)

func _engaged_duo():
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var state=session.sim.world.party_encounter;var hero_id:=int(state.protagonist_id);var best:Dictionary={}
	for enemy_id_value in state.enemy_ids:
		var enemy_id:=int(enemy_id_value)
		if not session.sim.world.is_unresolved_enemy(enemy_id):continue
		var ep:Vector2i=session.sim.world.entities[enemy_id].position
		for d in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var path:Dictionary=session.find_exploration_path(hero_id,ep+d)
			if bool(path.get("found",false)) and (best.is_empty() or path.path.size()<best.path.size()):best=path
		if not best.is_empty() and best.path.size()<=4:break
	if best.is_empty():return null
	for v in best.path.slice(1):
		if not bool(session.commit_exploration(SimCommand.move_to(hero_id,v)).get("accepted",false)):return null
		if str(session.party_status().get("safe_phase",""))=="CONTACT":break
	session.preview_deployment("LINE",[int(state.party_member_ids[1])]);session.commit_deployment()
	return session if str(session.party_status().get("safe_phase",""))=="ENGAGED" else null

func _pump(ui,seconds:float)->void:
	# Drive the presentation tick directly; the sandbox has process disabled.
	var elapsed:=0.0
	while elapsed<seconds:
		ui._tick_autonomous_battle(0.05);elapsed+=0.05

func run()->void:
	var session=_engaged_duo()
	_check(session!=null,"fixture is ENGAGED")
	if session==null:_finish();return
	var world=session.sim.world;var hero:int=int(world.party_encounter.protagonist_id)
	var ui=Sandbox.new();ui.size=Vector2(390,800);ui.initialize_for_headless_test(session,true)
	ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);ui.size=Vector2(390,800);root.add_child(ui);ui.set_process(false)
	for i in range(3):await process_frame
	_check(ui.battle_mode=="HERO_TURN","HERO_TURN is the default battle mode")
	# 1. The clock runs until the hero's event and stops there.
	_pump(ui,3.0)
	var flow=session.individual_battle
	_check(ui.hero_turn_waiting(),"clock waits at the protagonist's turn")
	_check(int(flow.next_event().get("actor_id",-1))==hero,"next event is the protagonist")
	var waiting_events:int=world.events.size()
	_pump(ui,2.0)
	_check(world.events.size()==waiting_events,"nothing happens while waiting for the hero")
	_check(not ui.autonomous_battle_clock.paused,"waiting is not the explicit pause")
	# 2. A HOLD reservation lets the world advance to the next hero turn.
	var step_before:int=world.step_index
	_check(bool(flow.reserve_action(hero,{"type":"HOLD"}).get("accepted",false)),"hero HOLD reservation accepted")
	_pump(ui,3.0)
	_check(world.step_index>step_before,"reserved action ran and the clock advanced")
	_check(ui.hero_turn_waiting() or str(session.party_status().get("safe_phase",""))!="ENGAGED",
		"clock stops again at the next protagonist turn")
	var hero_actions:=0;var other_actions:=0
	for index in range(waiting_events,world.events.size()):
		var event=world.events[index]
		if not str(event.type).begins_with("action."):continue
		if int(event.actor_id)==hero:hero_actions+=1
		else:other_actions+=1
	_check(hero_actions==1,"exactly one protagonist action per reservation (got %d)"%hero_actions)
	# 3. AUTO mode keeps running without reservations.
	ui.battle_mode="AUTO";ui._request_refresh();await process_frame
	var auto_before:int=world.step_index
	_pump(ui,2.0)
	_check(world.step_index>auto_before or str(session.party_status().get("safe_phase",""))!="ENGAGED",
		"AUTO mode advances without a reservation")
	# 4. Portrait utility exposes the mode toggle.
	ui.battle_mode="HERO_TURN";ui._refresh();await process_frame
	var toggle:=ui.find_child("PortraitBattleMode",true,false) as Button
	_check(toggle!=null and toggle.text=="자동","HERO_TURN shows the 자동 toggle")
	if toggle!=null:
		toggle.pressed.emit();await process_frame
		_check(ui.battle_mode=="AUTO","toggle switches to AUTO")
		toggle=ui.find_child("PortraitBattleMode",true,false) as Button
		_check(toggle!=null and toggle.text=="수동","AUTO shows the 수동 toggle")
	# 5. Save/load lands in HERO_TURN with an empty reservation set.
	var loaded=Session.new();var load_result:Dictionary=loaded.load_session_json(session.save_session_json())
	_check(bool(load_result.get("accepted",false)),"session reloads")
	if bool(load_result.get("accepted",false)):
		_check(loaded.sim.snapshot()==session.sim.snapshot(),"replay is exact")
		var ui2=Sandbox.new();ui2.size=Vector2(390,800);ui2.initialize_for_headless_test(loaded,true)
		_check(ui2.battle_mode=="HERO_TURN" and loaded.individual_battle.queued(hero).is_empty(),"loaded session starts HERO_TURN without reservations")
		ui2.free()
	_finish()

func _finish()->void:
	if failures.is_empty():print("PASS hero turn combat");quit(0)
	else:printerr("FAIL hero turn combat: %d failures"%failures.size());quit(1)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `godot --headless --path . --script res://tests/hero_turn_combat_acceptance.gd`
Expected: FAIL (`battle_mode` missing).

- [ ] **Step 3: Clock and pending query**

`playtest/autonomous_battle_clock.gd`:

```gdscript
func advance(delta:float,world_time:int,blocked:bool,units_per_second:float=WORLD_UNITS_PER_SECOND,
		hold_at:float=-1.0)->float:
	if cursor<0:cursor=float(world_time)
	cursor=maxf(cursor,float(world_time))
	if not paused and not blocked:
		# Returning from a suspended browser must not instantly resolve a battle.
		cursor+=clampf(delta,0.0,0.1)*units_per_second
	# HERO_TURN: the cursor may reach the protagonist's event but never pass it
	# while that event has no reservation.
	if hold_at>=0.0:cursor=minf(cursor,maxf(hold_at,float(world_time)))
	return cursor
```

`playtest/individual_battle_session.gd`:

```gdscript
func hero_turn_pending()->bool:
	_bind()
	if _sim==null:return false
	var next:Dictionary=next_event()
	var hero:int=int(_sim.world.party_encounter.protagonist_id)
	return not next.is_empty() and int(next.actor_id)==hero and not queues.has(hero)
```

- [ ] **Step 4: Sandbox mode, tick, buttons**

Near the other battle vars in `playtest/party_encounter_sandbox.gd`:

```gdscript
# Presentation-only combat pacing. HERO_TURN stops the display clock at every
# protagonist event until the player reserves an action; AUTO is the old
# free-running clock. Never saved; a loaded session starts in HERO_TURN.
var battle_mode:="HERO_TURN"
const HERO_TURN_UNITS_PER_SECOND:=400.0

func hero_turn_waiting()->bool:
	return battle_mode=="HERO_TURN" and session!=null and session.is_duo_autobattle() \
		and session.sim!=null and session.sim.world.party_encounter.safe_phase=="ENGAGED" \
		and session.individual_battle.hero_turn_pending()
```

In `_tick_autonomous_battle` replace the `advance` line and the loop guard:

```gdscript
	var blocked:=_battle_presentation_blocked()
	var hold_at:=-1.0
	if battle_mode=="HERO_TURN" and session.individual_battle.hero_turn_pending():
		hold_at=float(session.individual_battle.next_event().at)
	var at:float=autonomous_battle_clock.advance(delta,session.sim.world.world_time,blocked,
		HERO_TURN_UNITS_PER_SECOND if battle_mode=="HERO_TURN" else autonomous_battle_clock.WORLD_UNITS_PER_SECOND,hold_at)
	...
	if not blocked and not autonomous_battle_clock.paused:
		for iteration in range(16):
			var next:Dictionary=session.individual_battle.next_event()
			if next.is_empty() or float(next.at)>at:break
			if battle_mode=="HERO_TURN" and session.individual_battle.hero_turn_pending():break
			...
			if battle_mode=="AUTO" and battle_command_flow.check_danger(self):break
```

Keep `_refresh_individual_battle_surface()` on `changed`. After the loop, when the waiting state flips (compare with a `var _hero_turn_notice_shown:=false`), call `_request_refresh()` once so buttons and the notice update.

Portrait utilities: add a third button in `_add_battle_portrait_utilities` before the pause button; in HERO_TURN hide the pause button (`pause.visible=battle_mode=="AUTO"`):

```gdscript
	var mode:=Button.new();mode.name="PortraitBattleMode"
	mode.text="자동" if battle_mode=="HERO_TURN" else "수동"
	mode.tooltip_text="전투를 자동으로 진행합니다." if battle_mode=="HERO_TURN" else "내 차례마다 멈춥니다."
	mode.custom_minimum_size=Vector2(48,48)
	DarkPixelSkinScript.apply_action_button(mode,DarkPixelSkinScript.BRASS)
	mode.pressed.connect(_on_battle_mode_toggle);utility.add_child(mode)

func _on_battle_mode_toggle()->void:
	battle_mode="AUTO" if battle_mode=="HERO_TURN" else "HERO_TURN"
	if battle_mode=="AUTO":autonomous_battle_clock.paused=false;battle_command_flow.resume()
	_show_manual_battle_feedback("자동 진행" if battle_mode=="AUTO" else "내 차례마다 멈춥니다")
	_request_refresh()
```

`_on_product_execute` (pause/resume) stays AUTO-only: guard its first branch with `battle_mode=="AUTO"`.

`playtest/battle_command_flow.gd`: `sync` calls `check_danger` only when `host.battle_mode=="AUTO"`; in `paint`, when `host.battle_mode=="HERO_TURN"` the notice is `"내 차례 · 칸/적/스킬을 고르세요"` while `host.hero_turn_waiting()` and `""` otherwise; the danger portrait highlight remains (informational) but never pauses.

- [ ] **Step 5: Fixtures of the AUTO-dependent suites**

Add `ui.battle_mode="AUTO"` immediately after each `initialize_for_headless_test(...)` in: `tests/duo_autobattle_smoke.gd`, `tests/battle_command_flow_acceptance.gd`, `tests/battle_timeline_integration.gd`, `tests/battle_tap_move_regression.gd`, `tests/battleheart_mvp_acceptance.gd` (every `Sandbox.new()` site). `tests/member_detail_stash_regression.gd` is exploration-only; leave it.

- [ ] **Step 6: Run the tests**

Run sequentially: `hero_turn_combat_acceptance`, `hero_action_reservation_acceptance`, `duo_autobattle_smoke`, `battle_command_flow_acceptance`, `battle_timeline_integration`, `battle_tap_move_regression`, `battleheart_mvp_acceptance`.
Expected: new test PASS; the rest as before (battleheart keeps its 4 known failures only).

- [ ] **Step 7: Commit**

```bash
git add playtest/autonomous_battle_clock.gd playtest/individual_battle_session.gd playtest/party_encounter_sandbox.gd playtest/battle_command_flow.gd tests/hero_turn_combat_acceptance.gd tests/duo_autobattle_smoke.gd tests/battle_command_flow_acceptance.gd tests/battle_timeline_integration.gd tests/battle_tap_move_regression.gd tests/battleheart_mvp_acceptance.gd
git commit -m "feat(ui): HERO_TURN battle pacing that stops at every protagonist turn"
```

---

### Task 3: Tap mapping in HERO_TURN

**Files:**
- Modify: `playtest/party_encounter_sandbox.gd` (`_on_cell` combat branch, `_on_actor` enemy branch, `_reserve_battle_move`, `_on_product_direction`)
- Test: extend `tests/hero_turn_combat_acceptance.gd`

**Interfaces:**
- Consumes: Task 1 `reserve_action`, Task 2 `battle_mode`, `hero_turn_waiting`.
- Produces: `func _reserve_hero_action(action:Dictionary)->void` (HERO_TURN) used by cell, actor and direction inputs.

- [ ] **Step 1: Extend the acceptance test (append before `_finish()` in `run`, after section 5, using a fresh fixture)**

```gdscript
	# 6. Taps map to reservations in HERO_TURN.
	var session2=_engaged_duo()
	if session2!=null:
		var world2=session2.sim.world;var hero2:int=int(world2.party_encounter.protagonist_id)
		var ui3=Sandbox.new();ui3.size=Vector2(390,800);ui3.initialize_for_headless_test(session2,true)
		ui3.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);ui3.size=Vector2(390,800);root.add_child(ui3);ui3.set_process(false)
		for i in range(3):await process_frame
		_pump(ui3,3.0)
		var flow2=session2.individual_battle
		var hero_cell:Vector2i=world2.entities[hero2].position
		ui3.grid.world_cell_pressed.emit(hero_cell);await process_frame
		_check(flow2.queued(hero2)=={"action":{"type":"HOLD"}},"own-cell tap reserves HOLD")
		_pump(ui3,3.0)
		var far_cell:=Vector2i(-1,-1)
		var start:Vector2i=world2.entities[hero2].position
		for r in [3,4,2]:
			for dy in range(-r,r+1):
				for dx in range(-r,r+1):
					var c:Vector2i=start+Vector2i(dx,dy)
					if maxi(absi(dx),absi(dy))!=r or not world2.in_bounds(c):continue
					var p:Dictionary=session2.sim.pathfinder.find_path(hero2,c)
					if bool(p.get("found",false)) and p.path.size()>=3:far_cell=c;break
				if far_cell!=Vector2i(-1,-1):break
			if far_cell!=Vector2i(-1,-1):break
		if far_cell!=Vector2i(-1,-1) and ui3.hero_turn_waiting():
			var expected_step:Vector2i=session2.sim.pathfinder.find_path(hero2,far_cell).path[1]
			ui3.grid.world_cell_pressed.emit(far_cell);await process_frame
			_check(flow2.queued(hero2)=={"action":{"type":"MOVE","destination":[expected_step.x,expected_step.y]}},
				"far-cell tap reserves one step along the path")
			_check(flow2.movements.is_empty(),"HERO_TURN never creates a standing movement order")
		# Enemy tap: adjacent -> MELEE, far -> one step toward it.
		_pump(ui3,3.0)
		var nearest:=-1;var nearest_d:=999
		for id in session2.party_status().get("visible_enemy_ids",[]):
			if not world2.is_autonomous_target(int(id)):continue
			var d:int=maxi(absi(world2.entities[hero2].position.x-world2.entities[int(id)].position.x),absi(world2.entities[hero2].position.y-world2.entities[int(id)].position.y))
			if d<nearest_d:nearest_d=d;nearest=int(id)
		if nearest>0 and ui3.hero_turn_waiting():
			ui3.grid.actor_pressed.emit(nearest);await process_frame
			var queued2:Dictionary=flow2.queued(hero2)
			if nearest_d==1:_check(queued2=={"action":{"type":"MELEE","target_id":nearest}},"adjacent enemy tap reserves MELEE")
			else:_check(queued2.has("action") and str(queued2.action.type)=="MOVE","far enemy tap reserves one step toward it")
		ui3.queue_free();await process_frame
```

- [ ] **Step 2: Run to verify the new section fails**

Expected: FAIL on "own-cell tap reserves HOLD".

- [ ] **Step 3: Implement the mapping**

```gdscript
func _reserve_hero_action(action:Dictionary)->void:
	# HERO_TURN input contract: every tap is the protagonist's next action. A tap
	# while the clock is still running is accepted as the reservation for the
	# next protagonist event, so the player can pre-commit.
	var status:Dictionary=session.party_status()
	var hero:int=int(status.protagonist_id)
	var result:Dictionary=session.individual_battle.reserve_action(hero,action)
	var message:=str(result.get("message","행동을 지정할 수 없습니다."))
	_show_manual_battle_feedback(message)
	if bool(result.get("accepted",false)):
		notice_text=message;action_feedback_text=message
		if str(action.get("type",""))=="MELEE":
			grid.set_selection(selected_member_id,int(action.target_id));grid.set_actor_emphasis(int(action.target_id),600)
	_request_refresh()

func _hero_step_toward(goal:Vector2i)->Dictionary:
	var status:Dictionary=session.party_status();var hero:int=int(status.protagonist_id)
	var path:Dictionary=session.sim.pathfinder.find_path(hero,goal)
	if not bool(path.get("found",false)) or path.path.size()<2:return {}
	var next_cell:Vector2i=path.path[1]
	return {"type":"MOVE","destination":[next_cell.x,next_cell.y]}
```

`_on_cell` combat branch:

```gdscript
	if status.view_mode!="COMBAT":return
	if session.is_duo_autobattle():
		if battle_mode=="HERO_TURN":
			var hero_cell:=Vector2i(int(status.protagonist_position[0]),int(status.protagonist_position[1]))
			if position==hero_cell:_reserve_hero_action({"type":"HOLD"});return
			var step:Dictionary=_hero_step_toward(position)
			if step.is_empty():_show_manual_battle_feedback("이동할 수 없는 칸입니다.");return
			_reserve_hero_action(step);return
		_reserve_battle_move(int(status.protagonist_id),position);return
```

`_on_actor` enemy branch (the `_portrait_battle_controls_visible()` check near the top):

```gdscript
	if _portrait_battle_controls_visible() and entity_id in session.party_status().get("visible_enemy_ids",[]):
		if battle_mode=="HERO_TURN":
			var status0:Dictionary=session.party_status();var hero0:int=int(status0.protagonist_id)
			var hero_cell0:=Vector2i(int(status0.protagonist_position[0]),int(status0.protagonist_position[1]))
			var enemy_cell:Vector2i=session.sim.world.entities[entity_id].position
			if maxi(absi(hero_cell0.x-enemy_cell.x),absi(hero_cell0.y-enemy_cell.y))==1:
				_reserve_hero_action({"type":"MELEE","target_id":entity_id});return
			var approach:Dictionary=_hero_step_toward(enemy_cell)
			if approach.is_empty():_show_manual_battle_feedback("다가갈 길이 없습니다.");return
			_reserve_hero_action(approach);return
		_focus_battle_enemy(entity_id);return
```

`_on_product_direction` ENGAGED branch: in HERO_TURN reserve `{"type":"MOVE","destination":[hero+direction]}` (or HOLD for `Vector2i.ZERO`); AUTO keeps `_reserve_battle_move`.

- [ ] **Step 4: Run the acceptance test and the AUTO suites again**

Run: `hero_turn_combat_acceptance`, `battle_tap_move_regression` (AUTO fixture), `battle_command_flow_acceptance`, `duo_autobattle_smoke`.
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add playtest/party_encounter_sandbox.gd tests/hero_turn_combat_acceptance.gd
git commit -m "feat(ui): HERO_TURN taps reserve melee, one step, or hold for the protagonist"
```

---

### Task 4: Timeline bar "내 차례" cue

**Files:**
- Modify: `playtest/battle_timeline_presenter.gd` (input key `hero_waiting:bool` → DTO `hero_waiting`)
- Modify: `playtest/party_playtest_session.gd` (`battle_timeline_state` passes nothing new; the controller injects the flag)
- Modify: `playtest/battle_timeline_controller.gd` (`sync`: `state["hero_waiting"]=host.hero_turn_waiting()` before `set_state`, and include it in the change comparison)
- Modify: `playtest/battle_timeline_bar.gd` (`_draw`: when `_state.hero_waiting` the center header text is `"내 차례"` instead of `"행동"` and the protagonist portrait frame uses `UiSkin.BRASS`)
- Test: `tests/test_battle_timeline_presenter.gd` (one case: `build({...,"hero_waiting":true})` echoes `hero_waiting`), and extend `tests/hero_turn_combat_acceptance.gd` with `_check(ui.battle_timeline_bar._state.get("hero_waiting",false),"timeline shows 내 차례 while waiting")` right after the first waiting check.

- [ ] **Step 1: Write the failing presenter test**

```gdscript
func test_hero_waiting_flag_is_echoed() -> bool:
	var dto: Dictionary = Presenter.build({"engaged":true,"allies":[],"enemies":[],"hero_waiting":true})
	check_eq(bool(dto.get("hero_waiting",false)), true, "hero_waiting is carried into the DTO")
	var silent: Dictionary = Presenter.build({"engaged":true,"allies":[],"enemies":[]})
	check_eq(bool(silent.get("hero_waiting",false)), false, "hero_waiting defaults to false")
	return finish()
```

- [ ] **Step 2: Run to verify it fails**, **Step 3: implement** (presenter: `result["hero_waiting"]=bool(input.get("hero_waiting",false))`; controller: set the flag on the state dictionary it passes to the bar; bar: header text and hero frame color), **Step 4: run** `test_battle_timeline_presenter` runner, `battle_timeline_acceptance`, `hero_turn_combat_acceptance`, **Step 5: commit**

```bash
git add playtest/battle_timeline_presenter.gd playtest/battle_timeline_controller.gd playtest/battle_timeline_bar.gd tests/test_battle_timeline_presenter.gd tests/hero_turn_combat_acceptance.gd
git commit -m "feat(ui): timeline bar announces the protagonist's turn"
```

---

## Verification (after all tasks)

Sequentially: `hero_action_reservation_acceptance`, `hero_turn_combat_acceptance`, `individual_battle_acceptance`, `battle_timeline_acceptance`, `battle_timeline_integration`, `duo_autobattle_smoke`, `battle_command_flow_acceptance`, `battle_tap_move_regression`, `battleheart_mvp_acceptance` (4 known failures only), `run_product_tests` (compare `^FAIL` lines with the pre-change run; only pre-existing failures allowed).
