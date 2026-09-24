extends RefCounted
## The compat auto-battle path of the HUD: the timer that drives the rounds,
## the stop events and their banner sentence, and the after-battle report.
## Moved out of main.gd; the clocks and flags still live on `ui`.
const Session = preload("res://expedition/run/session.gd")
const BattleHud = preload("res://expedition/ui/battle_hud.gd")

## One timer step of the auto battle: 0.7s at 1×, half that at 2×.
static func auto_interval(ui) -> float:
	return 0.7/float(maxi(1,int(ui.session.auto.speed)))

## A stop event outranks the round: it halts the run, names itself in the
## banner and, at the end of a battle, opens the report.
static func auto_tick(ui) -> void:
	if is_instance_valid(ui.board) and ui.board.is_presenting(): return
	if ui.session == null: return
	var reason: String = ui.session.auto_stop_reason()
	if not reason.is_empty():
		ui.session.auto.running = false
		note_stop(ui,reason)
		if reason == "BATTLE_END": report_battle(ui)
		ui.refresh(); return
	# Nothing to fight: the run would spin on a refused auto_step.
	if not ui.session.in_combat():
		ui.session.auto.running = false; ui.refresh(); return
	ui.battle_reported = false
	ui.run_action(ui.session.auto_step)
	if is_instance_valid(ui.board) and ui.board.is_presenting(): return
	# The report is a summary, not a stop: it follows every battle, including
	# one whose BATTLE_END stop the player switched off.
	if not ui.session.in_combat(): report_battle(ui)

## The report of the battle that just ended, once.
static func report_battle(ui) -> void:
	if ui.battle_reported: return
	ui.battle_reported = true
	show_battle_report(ui)

static func toggle_auto(ui) -> void:
	ui.stop_navigation()
	ui.session.auto.running = not ui.session.auto.running
	var toggle = ui.find_child("AutoToggle",true,false)
	if toggle != null: toggle.text = "⏸ 정지" if ui.session.auto.running else "▶ 재개"
	if ui.session.auto.running: ui.stop_text = ""
	ui.auto_clock = 0.0
	ui.refresh()

static func toggle_speed(ui) -> void:
	ui.session.auto.speed = 1 if int(ui.session.auto.speed) > 1 else 2
	if is_instance_valid(ui.board): ui.board.playback_speed = float(ui.session.auto.speed)
	var speed = ui.find_child("SpeedToggle",true,false)
	if speed != null: speed.text = "%d×" % int(ui.session.auto.speed)
	ui.auto_clock = 0.0
	ui.refresh()

## `auto_stop_reason` has side effects, so the HUD asks it in exactly two
## places: every auto tick, and once at the end of every player action — a
## battle can begin or end by hand while the run is stopped.
static func check_stop(ui) -> void:
	if ui.session != null and ui.session.manual_mode: return
	if ui.session == null or ui.session.auto.running: return
	var reason: String = ui.session.auto_stop_reason()
	if reason.is_empty(): return
	note_stop(ui,reason)
	if reason == "BATTLE_END": report_battle(ui)

static func note_stop(ui, reason: String) -> void:
	ui.stop_text = stop_message(ui,reason)
	# A fresh battle owes the player a fresh report.
	if reason == "BATTLE_START": ui.battle_reported = false
	ui.auto_clock = 0.0

## The Korean sentence of a stop event, with whoever caused it.
static func stop_message(ui, reason: String) -> String:
	var session = ui.session
	match reason:
		"BATTLE_START": return "전투 시작 · 적 %d" % session.party_enemies().size()
		"BATTLE_END": return "전투 종료"
		"DEATH":
			var fallen: Array = session.party.filter(func(a): return a.hp <= 0)
			return "%s 쓰러짐" % (fallen[-1].name if not fallen.is_empty() else "아군")
		"ALLY_LETHAL":
			var risked: Array = session.alive().filter(func(a): return Session.Rules.lethal_threat(session,a) >= a.hp)
			return "%s 치명 위기" % (risked[0].name if not risked.is_empty() else "아군")
		"HP_LOW":
			var low: Array = session.alive().filter(func(a): return a.hp*100/a.max_hp <= int(session.auto.hp_low))
			return "%s 체력 %d%% 이하" % [low[0].name if not low.is_empty() else "아군",int(session.auto.hp_low)]
	return ""

## 후퇴 is the one standing order the HUD still offers, and the only control
## that works mid-run: calling the party off cannot wait for the next stop.
static func toggle_retreat(ui) -> void:
	ui.session.party_command = "FOLLOW" if ui.session.party_command == "RETREAT" else "RETREAT"
	ui.refresh()

static func show_battle_report(ui) -> void:
	ui.stop_navigation(); BattleHud.report(ui)
