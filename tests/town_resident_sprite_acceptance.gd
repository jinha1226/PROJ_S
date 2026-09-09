extends SceneTree

const SettlementView=preload("res://playtest/base_settlement_view.gd")
const ActorAssets=preload("res://playtest/fixed_front_topdown_assets.gd")

var failures:Array[String]=[]


func _init()->void:
	call_deferred("_run")


func _run()->void:
	var view=SettlementView.new()
	var center:=Vector2(120,96)
	for species_id in ["human","elf","dwarf","orc","beastkin"]:
		var spec:Dictionary=view.resident_visual_spec({
			"entity_id":1,"species_id":species_id},center,28.0)
		_check(bool(spec.get("uses_actual_asset",false)),
			"%s town resident uses an actual Pixel24 asset"%species_id)
		_check(spec.get("body_texture",null)==ActorAssets.body_texture(species_id),
			"%s resolves the canonical body texture"%species_id)
		_check(spec.get("source_canvas_size",Vector2.ZERO)==Vector2(24,24),
			"%s retains the 24x24 source canvas"%species_id)
		_check(spec.get("layer_order",[])==["body","armor","offhand","weapon","foreground"],
			"%s retains canonical paper-doll layer order"%species_id)
		_check(bool(spec.get("fixed_front",false)) and not bool(spec.get("ascii_glyph",true)),
			"%s remains fixed-front non-ASCII art"%species_id)
		var bounds:Rect2=spec.get("bounds",Rect2())
		_check(bounds.get_center()==center and bounds.size==Vector2(25,25),
			"%s is centered and nearest-scaled within its town cell"%species_id)

	var legacy:Dictionary=view.resident_visual_spec({"entity_id":2},center,28.0)
	_check(str(legacy.get("species_id",""))=="human"
		and bool(legacy.get("uses_actual_asset",false)),
		"legacy resident DTO defaults to the human sprite")
	var equipped:Dictionary=view.resident_visual_spec({"species_id":"dwarf",
		"equipment_visual":{"armor_definition_id":"ARMOR_PADDED",
			"weapon_definition_id":"WEAPON_HAND_AXE",
			"off_hand_definition_id":"SHIELD_WOOD"}},center,28.0)
	_check(equipped.get("armor_texture",null)!=null
		and equipped.get("weapon_texture",null)!=null
		and equipped.get("offhand_texture",null)!=null
		and equipped.get("foreground_texture",null)!=null,
		"town resident carries every available fitted equipment layer")
	var unknown:Dictionary=view.resident_visual_spec({"species_id":"future_species"},center,28.0)
	_check(not bool(unknown.get("uses_actual_asset",true)),
		"unknown future species selects the safe drawn fallback")
	view.free()

	if failures.is_empty():
		print("PASS town resident sprite acceptance: actual Pixel24 residents on the main town map")
		quit(0)
	else:
		for failure in failures:push_error(failure)
		quit(1)


func _check(condition:bool,message:String)->void:
	if not condition:failures.append(message)
