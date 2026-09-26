extends SceneTree
const Subtypes = preload("res://expedition/progression/subtypes.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const EffectEngine = preload("res://expedition/progression/effect_engine.gd")
var checks := 0
var failures := 0
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(why)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	check(Subtypes.IDS.size() == 17,"seventeen subtypes")
	for id in Subtypes.IDS:
		check(Subtypes.GROUP.get(id,"") in Subtypes.GROUP_NAMES,"every subtype has a valid role group")
		check(int(Subtypes.LEGACY_FAMILY.get(id,0)) in range(1,13),"every subtype has a tactical channel")
	for id in EffectEngine.content.effects:
		check(not EffectEngine.content.effects[id].has("families"),"no numeric family metadata: "+id)
	for stone in Essences.catalog():
		var effect: String = str(Essences.row(str(stone)).effect)
		if effect.is_empty(): continue
		check(Subtypes.of(effect) in Subtypes.IDS,"every part effect has one subtype: "+effect)
	for id in {"RAT_GNAW":"BOOST","LIZARD_TAIL":"REFLECT","HOB_TAUNT":"DEFENSE","ORC_THROW":"VOLLEY","TOAD_SPIT":"VENOM","GRAVEKEEPER":"DEATH","VAMPIRE_BITE":"REGEN","LEECh":""}:
		var expected: String = {"RAT_GNAW":"BOOST","LIZARD_TAIL":"REFLECT","HOB_TAUNT":"DEFENSE","ORC_THROW":"VOLLEY","TOAD_SPIT":"VENOM","GRAVEKEEPER":"DEATH","VAMPIRE_BITE":"REGEN","LEECh":""}[id]
		check(Subtypes.of(id) == expected,"explicit subtype mapping "+id)
	check(Subtypes.long_label("DEFENSE") == "탱커 · 방어탱","readable subtype name")
	check(Subtypes.of("COST_AXE") == "" and Subtypes.label("unknown") == "","unclassified and unknown effects are safe")
	print("Subtypes: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
