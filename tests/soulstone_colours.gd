extends SceneTree
const Mobile = preload("res://expedition/progression/attack_wait.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const FRAME := "res://assets/soulstone-icons-v1/png/frames/%s.png"
const EFFECT := "res://assets/soulstone-icons-v1/png/effects/%s.png"
const BADGE := "res://assets/soulstone-icons-v1/png/badges/%s.png"
var checked := 0
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, reason: String) -> void:
	checked += 1
	if not ok:
		failed += 1
		push_error(reason)

func run() -> void:
	check(Mobile.validate().is_empty(),"effect table validates: "+str(Mobile.validate()))
	for id in Mobile.data.effects:
		var row: Dictionary = Mobile.data.effects[id]
		var colour: String = str(row.get("colour",""))
		var icon: String = str(row.get("icon",""))
		var badge: String = str(row.get("badge",""))
		check(FileAccess.file_exists(FRAME % colour),"missing colour frame: "+str(id))
		check(FileAccess.file_exists(EFFECT % icon),"missing effect icon: "+str(id))
		if not badge.is_empty(): check(FileAccess.file_exists(BADGE % badge),"missing badge: "+str(id))
		check((colour == "red" and row.event in ["ATTACK","HIT"]) or (colour == "purple" and row.event == "WAIT") or (colour == "green" and row.event == "STRUCK"),"colour/event mismatch: "+str(id))
	for stone in Mobile.catalog():
		check(not Mobile.row(str(stone)).is_empty(),"unmapped stone: "+str(stone))
		var actor := {"combat_profile":Mobile.PROFILE}
		var stats: Dictionary = Essences.stats(str(stone),actor)
		var expected: Dictionary = Mobile.data.role_stats[Mobile.colour(str(stone))]
		var correct := true
		for key in expected:
			if int(stats.get(key,-999)) != int(expected[key]): correct = false
		if Essences.variant_element(str(stone)) not in ["","bleed"]:
			if int(stats.get("res_"+Essences.variant_element(str(stone)),0)) != 10: correct = false
		check(correct,"colour reward: "+str(stone))
	print("Soulstone colours: %d checks, %d failures" % [checked,failed])
	quit(1 if failed else 0)
