extends SceneTree
const Fixture = preload("res://tests/followup_fixture.gd")
const Randart = preload("res://expedition/items/randart.gd")
const Equipment = preload("res://expedition/items/equipment.gd")
var checks := 0
var failures := 0
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(why)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var s = Fixture.reset().s
	var flaws := 0; var spread: Dictionary = {}
	for zone in range(1,5):
		s.depth = (zone-1)*3+1
		for i in range(80):
			var kind: String = ["sword","robe","power","shield","orb","off_mace"][i%6]
			var item: Dictionary = Randart.make(s,zone*1000+i,kind,"randart")
			check(item == Randart.make(s,zone*1000+i,kind,"randart"),"same seed/drop key generates the same item")
			var count: int = item.props.size()+(1 if item.has("affix") else 0)
			check(count >= 2 and count <= 4 and (zone != 1 or count == 2) and (zone != 3 or count == 3),"zone controls positive-property count, flaw is separate")
			var seen: Array = []
			for prop in item.props:
				check(prop.key not in seen,"numeric property sampled without replacement"); seen.append(prop.key)
				var definition: Array = Equipment.content.loot.randart_props.filter(func(p): return p.key == prop.key)
				check(not definition.is_empty() and (Equipment.slot(item) in definition[0].slots or kind in definition[0].slots),"property respects the equipment slot")
			if item.has("affix"):
				check(Randart.effects[item.affix].gear_kind == "affix","exactly one valid build option")
				if zone == 1 and kind == "power": check(false,"first-zone rings must not amplify builds")
			if item.has("flaw"):
				flaws += 1
				check(item.flaw.key not in seen,"no contradictory numeric property and flaw")
				for prop in item.props:
					var bounds: Array = Equipment.content.loot.randart_props.filter(func(p): return p.key == prop.key)[0].ranges[zone-1]
					check(int(prop.value) >= ceili(float(bounds[0])*1.5) and int(prop.value) <= ceili(float(bounds[1])*1.5),"flaw compensates numeric values with rounded-up fifty percent")
			check(not str(item.name).is_empty() and item.enchant == zone-1,"name and base enhancement generated")
			spread[item.name] = true
	check(flaws > 60 and flaws < 140,"flaw frequency remains around thirty percent")
	check(spread.size() > 100,"drop keys provide independent names")
	# Unique artifact depletion falls back to a usable randart.
	s.unrands_seen = {}
	for row in Randart.artifacts: s.unrands_seen[str(row.id)] = true
	check(Randart.make(s,5000,"sword","unrand").tier == "randart","exhausted artifact catalogue falls back")
	print("Randarts: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
