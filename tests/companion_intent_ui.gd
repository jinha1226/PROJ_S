extends SceneTree
const IntentUI = preload("res://expedition/companion_intent_ui.gd")
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Presentation = preload("res://expedition/battle_presentation.gd")
var failures := 0

func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var ui = IntentUI.new()
	var actors := [
		{"id":11,"pos":Vector2i(2,3)},
		{"id":22,"pos":Vector2i(2,4)},
		{"id":33,"pos":Vector2i(2,5)}
	]
	var rows: Array = []
	for actor in actors: rows.append(ui.preview(actor,{"kind":"MOVE","cell":actor.pos+Vector2i.RIGHT}))
	check(rows.size() == 3 and rows.map(func(row): return row.actor_id) == [11,22,33],"all living companions have stable-id descriptors")
	check(rows.all(func(row): return row.path == [row.from,row.cell]),"a move without a supplied route previews only its next cell")
	var first := IntentUI.adapt(actors[0],{"kind":"ATTACK","cell":Vector2i(4,3)},99,1)
	check(ui.record_execution(first,true,0.0).is_empty(),"the first executed decision has no speech")
	var retreat := IntentUI.adapt(actors[0],{"kind":"MOVE","cell":Vector2i(1,3),"reason":"후퇴"},-1,2)
	check(ui.record_execution(retreat,true,0.5).text == "물러날게!","attack to retreat produces the supported line")
	check(ui.record_execution(retreat,true,1.0).is_empty(),"continued retreat does not repeat a line")
	ui.record_execution(first.merged({"decision_id":3},true),true,5.0)
	check(not ui.record_execution(retreat.merged({"decision_id":4},true),true,6.0).is_empty(),"retreat can speak again after resuming attack")
	var evade := IntentUI.adapt(actors[0],{"kind":"MOVE","cell":Vector2i.ONE,"tag":"MOVE:escape","reason_code":"FIRE","explain":[{"id":"cell_danger"}]})
	check(evade.intent == "EVADE" and evade.explain.size() == 1,"semantic AI tags and explanations survive the adapter")
	var s := Session.new(712,true,false,true,1)
	s.depart()
	var center := Fixture.arena(s)
	check(s.companion_intent_snapshot().is_empty(),"no combat plans leak into safe exploration")
	s.enemies[0].pos = center+Vector2i.RIGHT
	s.enemies[0].hp = 200; s.enemies[0].max_hp = 200
	s.floor_state.observe(s)
	var party_before := s.party.duplicate(true); var serial_before := s.serial; var ap_before := s.party.map(func(a): return a.ap)
	var intents: Array = s.companion_intent_snapshot()
	check(intents.size() == s.party.size(),"one preview is available for every actionable companion")
	check(s.party == party_before and s.serial == serial_before and s.party.map(func(a): return a.ap) == ap_before,"preview leaves actor state, RNG serial and AP unchanged")
	var recorder = Presentation.new()
	recorder.begin(s)
	var saved: Array = recorder.previous.companion_intents.duplicate(true)
	for actor in s.party: actor.ap = 0
	check(recorder.previous.companion_intents == saved and not recorder.previous.companion_intents.is_empty(),"presentation keeps the before-frame plans after session state changes")
	print("Companion intent UI: %d failures" % failures)
	quit(1 if failures else 0)
