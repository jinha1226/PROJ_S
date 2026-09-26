extends SceneTree
const EffectEngine = preload("res://expedition/progression/effect_engine.gd")
const StoneEffects = preload("res://expedition/progression/stone_effects.gd")
var checks := 0
var failures := 0
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(why)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var data: Dictionary = EffectEngine.content
	check(int(data.version) == 1 and data.effects.values().filter(func(row): return row.get("source","") != "gear").size() == 90,"ninety parts and gear effects")
	check(EffectEngine.validate(data).is_empty(),"production effect schema: "+str(EffectEngine.validate(data)))
	for id in data.effects:
		var row: Dictionary = data.effects[id]
		check(not row.rules.is_empty() and not row.keywords.is_empty(),str(id)+" has behavior and keywords")
		check(row.name == StoneEffects.EFFECTS[id].name and row.text == StoneEffects.EFFECTS[id].text,str(id)+" keeps the UI labels")
	for bad in [{"when":"TYPO","do":[{"notice":"!"}]},{"when":"HIT","if":[{"chacne":5}],"do":[{"notice":"!"}]},{"when":"HIT","do":[{"teleport":1}]},{"when":"HIT","code":"unknown"},{"when":"ALWAYS","mod":{"damage_typo":5}},{"when":"HIT","if":[{"chance":25}],"do":[{"gain_mp":1}]}]:
		var malformed := {"effects":{"BAD":{"name":"bad","text":"bad","rules":[bad]}}}
		check(not EffectEngine.validate(malformed).is_empty(),"bad rule rejected: "+str(bad))
	print("Effect data: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
