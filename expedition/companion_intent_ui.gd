extends RefCounted
## Presentation-only adapter and speech state for companion decisions.
const Abilities = preload("res://expedition/abilities.gd")

var next_decision_id := 1
var previous_execution: Dictionary = {}
var cooldowns: Dictionary = {}
var repeated_lines: Dictionary = {}
var speech: Array = []

static func adapt(actor: Dictionary, choice: Dictionary, target_id: int = -1, decision_id: int = 0) -> Dictionary:
	if actor.is_empty() or choice.is_empty(): return {}
	var kind := str(choice.get("kind", ""))
	if kind.is_empty(): return {}
	var cell: Vector2i = choice.get("cell", actor.get("pos", Vector2i.ZERO))
	var intent := "HOLD"
	if kind in ["ATTACK"]: intent = "ATTACK"
	elif kind == "MOVE": intent = "RETREAT" if str(choice.get("reason", "")) == "후퇴" else "APPROACH"
	elif kind == "WAIT": intent = "HOLD"
	elif kind == "GUARD" or Abilities.DEFINITIONS.get(kind,{}).get("effect","") == "GUARD": intent = "PROTECT"
	elif Abilities.DEFINITIONS.has(kind):
		var definition: Dictionary = Abilities.DEFINITIONS[kind]
		intent = "ATTACK" if definition.target == "ENEMY" and definition.effect in ["DAMAGE","LUNGE","PUSH"] else "SKILL"
	# Explicit semantic data takes precedence over the legacy display fallback.
	var tag := str(choice.get("tag", ""))
	var reason_code := str(choice.get("reason_code", ""))
	if kind == "MOVE":
		if tag in ["MOVE:escape", "MOVE:sidestep"] or reason_code in ["DANGER", "FIRE", "EVADE"]: intent = "EVADE"
		elif tag == "MOVE:disengage" or reason_code in ["LOW_HP", "RETREAT"]: intent = "RETREAT"
	if choice.get("intent", "") in ["ATTACK","APPROACH","RETREAT","EVADE","PROTECT","HOLD","SKILL"]:
		intent = str(choice.intent)
	var path: Array = []
	if kind == "MOVE": path = choice.get("path", [actor.get("pos", Vector2i.ZERO), cell]).duplicate(true)
	var resolved_target := target_id
	if resolved_target < 0 and kind in ["ATTACK", "PUSH"] + Abilities.DEFINITIONS.keys():
		resolved_target = int(choice.get("target_id", -1))
	return {"actor_id":int(actor.get("id", -1)), "decision_id":decision_id, "kind":kind,
		"from":actor.get("pos", Vector2i.ZERO), "cell":cell, "target_id":resolved_target,
		"path":path, "intent":intent, "reason_code":str(choice.get("reason_code", "")),
		"skill_id":kind if Abilities.DEFINITIONS.has(kind) else "", "explain":choice.get("explain",[]).duplicate(true)}

func preview(actor: Dictionary, choice: Dictionary, target_id: int = -1) -> Dictionary:
	if actor.is_empty() or choice.is_empty(): return {}
	var result := adapt(actor, choice, target_id, next_decision_id)
	next_decision_id += 1
	return result

func record_execution(intent: Dictionary, succeeded: bool, now: float) -> Dictionary:
	if intent.is_empty(): return {}
	if not succeeded: return {}
	var actor_id := int(intent.get("actor_id", -1))
	var prior: Dictionary = previous_execution.get(actor_id, {})
	if not prior.is_empty() and int(prior.get("decision_id",-1)) == int(intent.get("decision_id",-2)): return {}
	if prior.get("intent","") != intent.get("intent",""): repeated_lines.erase(actor_id)
	previous_execution[actor_id] = intent.duplicate(true)
	var line := transition_line(prior, intent)
	if line.is_empty() or now < float(cooldowns.get(actor_id, 0.0)) or repeated_lines.get(actor_id, "") == line: return {}
	cooldowns[actor_id] = now+4.0
	repeated_lines[actor_id] = line
	var item := {"actor_id":actor_id,"text":line,"remaining":1.2,"priority":2 if intent.intent in ["EVADE","PROTECT"] else 1}
	speech = speech.filter(func(row): return int(row.actor_id) != actor_id)
	speech.append(item)
	speech.sort_custom(func(a,b): return int(a.priority) > int(b.priority))
	while speech.size() > 2: speech.pop_back()
	return item

func transition_line(prior: Dictionary, current: Dictionary) -> String:
	if prior.is_empty(): return ""
	var old := str(prior.get("intent", "")); var new := str(current.get("intent", ""))
	if new == "RETREAT" and old in ["ATTACK", "APPROACH", "SKILL"]: return "물러날게!"
	var reason := str(current.get("reason_code", ""))
	if reason in ["DANGER", "FIRE", "EVADE"] and new == "EVADE" and old != new: return "위험해!"
	if new == "PROTECT" and (old != new or current.get("target_id",-1) != prior.get("target_id",-1)): return "엄호할게!"
	if reason == "PRIORITY_TARGET_CHANGED" and int(current.get("target_id", -1)) != int(prior.get("target_id", -1)):
		return "저쪽부터!"
	return ""

func tick(delta: float, paused: bool) -> void:
	if paused: return
	for row in speech: row.remaining = float(row.remaining)-delta
	speech = speech.filter(func(row): return float(row.remaining) > 0.0)
