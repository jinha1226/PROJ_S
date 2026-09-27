extends RefCounted
## Observes resolved actions only. Never changes combat state or consumes RNG.
var frames: Array = []
var previous: Dictionary = {}
var effect_cursor := 0

static func snapshot(s) -> Dictionary:
	var actors: Array = []
	for a in s.party+s.enemies+s.npcs:
		if a.hp <= 0: continue
		if not s.floor_state.visible.has(a.pos): continue
		var item := {}
		for key in ["id","name","pos","hp","max_hp","enemy","charging","cast_id","role","ap","guarded","protected_by","npc","awake","hostile","activity","boss","boss_kind","heat","species_id","sprite_species","variant_element"]:
			if a.has(key): item[key] = a[key]
		item.statuses = a.get("statuses",{}).duplicate(true)
		item.party_member = a in s.party
		actors.append(item)
	return {"actors":actors,"time":int(s.time),"focus":s.party[s.selected].pos,"intents":s.intents.duplicate(true),"companion_intents":s.companion_intent_snapshot(),"visible":s.floor_state.visible.duplicate(),"explored":s.floor_state.explored.duplicate()}

func begin(s) -> void:
	frames.clear()
	previous = snapshot(s)
	effect_cursor = s.effects.size()

func capture(s, actor_id: int = -1, executed_intent: Dictionary = {}) -> void:
	var after := snapshot(s)
	var hits: Array = s.effects.slice(effect_cursor).duplicate(true)
	effect_cursor = s.effects.size()
	# Autonomous offscreen procs must not create invisible playback pauses.
	hits = hits.filter(func(e):
		if e.get("kind","") == "ENEMY_ATTACK": return e.get("cells",[]).any(func(cell): return after.visible.has(cell))
		return after.visible.has(e.get("cell",Vector2i(-1,-1))))
	# Passage of time alone must not create an empty offscreen playback pause.
	var before_view := previous.duplicate(); before_view.erase("time")
	var after_view := after.duplicate(); after_view.erase("time")
	if before_view != after_view or not hits.is_empty() or not executed_intent.is_empty():
		frames.append({"before":previous,"after":after,"effects":hits,"actor":actor_id,"executed_intent":executed_intent.duplicate(true)})
	previous = after

func finish(s) -> void:
	capture(s)
