extends RefCounted
## Camp: rest, and the cooldowns it resets.
const CombatStats = preload("res://expedition/combat/combat_stats.gd")
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
const Essences = preload("res://expedition/progression/essences.gd")
## How many spells a caster may hold ready at once, chosen at camp.
const PREPARED_SLOTS := Essences.QUICK_SPELLS

static func can_camp(s) -> String:
	if s.phase != "EXPLORE": return "지금은 불가"
	if not s.floor_state.safe(s): return "적이 보임"
	var needed: int = s.alive().size()
	if s.food < needed: return "식량 %d 필요" % needed
	return ""

static func camp(s) -> bool:
	if not s.can_camp().is_empty(): return false
	s.auto.running = false
	s.food -= s.alive().size()
	for actor in s.alive():
		actor.hp = mini(actor.max_hp,actor.hp+ceili(actor.max_hp*0.5))
		s.stress(actor,-30)
		for id in actor.cooldowns: actor.cooldowns[id] = 0
	s.phase = "CAMP"; s.intents.clear()
	s.Codex.flush(s)
	s.message("야영 · 식량 -%d" % s.alive().size()); return true

static func end_camp(s) -> bool:
	if s.phase != "CAMP": return false
	s.phase = "EXPLORE"
	for actor in s.alive(): actor.ap = s.action_budget(actor)
	s.floor_state.observe(s); return true
