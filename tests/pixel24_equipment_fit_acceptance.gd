extends SceneTree

const MANIFEST_PATH := "res://tools/art/pixel24_human_fit_preview.json"
const SPECIES := ["human", "elf", "dwarf", "orc", "beastkin"]
const BASE_HASHES := {
	"human": "32de2e3f3b86de5b63366c110d2e8f86d10d971b9450991438eb3cfbc85dc87d",
	"elf": "459a83f7f192454666d9bb41c744de8ae2a799aeda106a3863016bd0724d393d",
	"dwarf": "ad8e86b40730a89cb0744a12fa9cb5e8d315c2c89bee72f3182e596c7eaf80f6",
	"orc": "216e349d454d64a89ae33d22442e39274900c877b9458c3ba9ee6e74c6a8ade9",
	"beastkin": "6c11308196286b066dec1df0d6724551d9730314ca864bd065747a914cac8a2a",
}

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	_check(parsed is Dictionary, "manifest parses as a JSON object")
	if not parsed is Dictionary:
		_finish()
		return
	var manifest: Dictionary = parsed
	var size: int = int(manifest.get("logical_size", 0))
	var root: String = str(manifest.get("runtime_root", ""))
	var metadata: Dictionary = manifest.get("fit_metadata", {})
	var active: Array[Dictionary] = []
	for value: Variant in manifest.get("entries", []):
		if value is Dictionary and bool(value.get("active", false)):
			active.append(value)
	_check(size == 24, "logical size remains 24")
	_check(metadata.size() == SPECIES.size(), "fit metadata covers exactly five species")

	var bases: Dictionary = {}
	var counts := {"actor_base": 0, "armor_layer": 0, "weapon_layer": 0, "offhand_layer": 0, "foreground_layer": 0}
	for entry: Dictionary in active:
		var kind: String = str(entry.get("kind", ""))
		counts[kind] = int(counts.get(kind, 0)) + 1
		var output_path: String = root.path_join(str(entry.get("output", "")))
		var image: Image = Image.load_from_file(output_path)
		_check(not image.is_empty(), "%s output loads" % entry.get("id", "unnamed"))
		if image.is_empty():
			continue
		_check(image.get_width() == size and image.get_height() == size, "%s is 24x24" % entry.id)
		_check(image.get_format() == Image.FORMAT_RGBA8, "%s loads as RGBA8" % entry.id)
		_check(_has_binary_alpha(image), "%s has nonempty binary alpha" % entry.id)
		if kind == "actor_base":
			var species: String = str(entry.id).trim_prefix("actor_")
			bases[species] = image
			_check(FileAccess.get_sha256(str(entry.source)) == str(BASE_HASHES.get(species, "missing")), "%s frozen base bytes are unchanged" % species)

	_check(int(counts.actor_base) == SPECIES.size(), "one active base exists per species")
	_check(int(counts.armor_layer) == SPECIES.size() * 2, "two active armor layers exist per species")
	_check(int(counts.weapon_layer) == 14, "seven standard/dwarf weapon pairs are active")
	_check(int(counts.offhand_layer) == 2, "standard and dwarf shields are active")
	_check(int(counts.foreground_layer) == SPECIES.size(), "one selective foreground exists per species")
	if bases.size() != SPECIES.size():
		_finish()
		return

	_check_grips(metadata, bases, size)
	for entry: Dictionary in active:
		var kind: String = str(entry.get("kind", ""))
		var image: Image = Image.load_from_file(root.path_join(str(entry.output)))
		if image.is_empty():
			continue
		if kind == "armor_layer":
			_check_armor(entry, image, metadata)
		elif kind == "weapon_layer":
			_check_weapon(entry, image, metadata, bases, size)
		elif kind == "offhand_layer":
			_check_offhand(entry, image, metadata, size)
		elif kind == "foreground_layer":
			_check_foreground(entry, image, bases)
	_finish()


func _check_grips(metadata: Dictionary, bases: Dictionary, size: int) -> void:
	for species: String in SPECIES:
		var spec: Dictionary = metadata.get(species, {})
		var base: Image = bases[species]
		for key: String in ["main_hand_grip", "off_hand_grip"]:
			var point: Vector2i = _point(spec.get(key, []))
			_check(_in_bounds(point, size), "%s %s is in bounds" % [species, key])
			if _in_bounds(point, size):
				_check(_alpha8(base, point) == 255, "%s %s refers to an actual opaque hand pixel" % [species, key])


func _check_armor(entry: Dictionary, image: Image, metadata: Dictionary) -> void:
	var species: String = _species_from_output(str(entry.output))
	_check(not species.is_empty(), "%s names a known species" % entry.id)
	if species.is_empty():
		return
	var spec: Dictionary = metadata[species]
	var rect_data: Array = spec.torso_rect
	var torso := Rect2i(int(rect_data[0]), int(rect_data[1]), int(rect_data[2]), int(rect_data[3]))
	var shoulder_y: int = int(spec.neck_shoulder_y)
	for y: int in image.get_height():
		for x: int in image.get_width():
			if _alpha8(image, Vector2i(x, y)) == 0:
				continue
			_check(torso.has_point(Vector2i(x, y)), "%s opaque pixel (%d,%d) stays inside torso envelope" % [entry.id, x, y])
			_check(y >= shoulder_y, "%s does not cover face rows at (%d,%d)" % [entry.id, x, y])


func _check_weapon(entry: Dictionary, image: Image, metadata: Dictionary, bases: Dictionary, size: int) -> void:
	var transform: Dictionary = entry.get("anchor_transform", {})
	var source_species: Array[String] = []
	if "dwarf" in str(entry.output):
		source_species.assign(["dwarf"])
	else:
		source_species.assign(["human", "elf", "orc", "beastkin"])
	var target_from: Vector2i = _point(transform.get("target_from", []))
	var target_to: Vector2i = _point(transform.get("target_to", []))
	_check(_in_bounds(target_from, size), "%s target_from is in bounds" % entry.id)
	_check(_in_bounds(target_to, size), "%s target_to is in bounds" % entry.id)
	if _in_bounds(target_from, size):
		_check(_alpha8(image, target_from) == 255, "%s target_from is opaque output alpha" % entry.id)
	for species: String in source_species:
		var grip: Vector2i = _point(metadata[species].main_hand_grip)
		_check(target_from == grip, "%s target_from matches %s main-hand grip" % [entry.id, species])
		var overlap: Array[String] = []
		var shoulder_y: int = int(metadata[species].neck_shoulder_y)
		var base: Image = bases[species]
		for y: int in shoulder_y:
			for x: int in size:
				var p := Vector2i(x, y)
				if _alpha8(image, p) == 255 and _alpha8(base, p) == 255:
					overlap.append("(%d,%d)" % [x, y])
		_check(overlap.is_empty(), "%s overlaps actual %s head pixels above shoulder: %s" % [entry.id, species, ", ".join(overlap)])


func _check_offhand(entry: Dictionary, image: Image, metadata: Dictionary, size: int) -> void:
	var species_list: Array[String] = []
	if "dwarf" in str(entry.output):
		species_list.assign(["dwarf"])
	else:
		species_list.assign(["human", "elf", "orc", "beastkin"])
	var anchor: Vector2i = _point(entry.get("target_anchor", []))
	_check(_in_bounds(anchor, size), "%s target anchor is in bounds" % entry.id)
	if _in_bounds(anchor, size):
		_check(_alpha8(image, anchor) == 255, "%s target anchor is opaque output alpha" % entry.id)
	for species: String in species_list:
		_check(anchor == _point(metadata[species].off_hand_grip), "%s anchor matches %s off-hand grip" % [entry.id, species])


func _check_foreground(entry: Dictionary, image: Image, bases: Dictionary) -> void:
	var species: String = _species_from_output(str(entry.output))
	if species.is_empty():
		_check(false, "%s names a known foreground species" % entry.id)
		return
	var base: Image = bases[species]
	var allowed: Dictionary = {}
	for raw: Variant in entry.get("retain_points", []):
		allowed[_point(raw)] = true
	for region_value: Variant in entry.get("retain_color_regions", []):
		var region: Dictionary = region_value
		var data: Array = region.rect
		var rect := Rect2i(int(data[0]), int(data[1]), int(data[2]), int(data[3]))
		var colors: Dictionary = {}
		for rgb_value: Variant in region.rgb:
			var rgb: Array = rgb_value
			colors[Color8(int(rgb[0]), int(rgb[1]), int(rgb[2]), 255).to_rgba32()] = true
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				var p := Vector2i(x, y)
				if colors.has(base.get_pixelv(p).to_rgba32()):
					allowed[p] = true
	var opaque_count := 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			var point := Vector2i(x, y)
			if _alpha8(image, point) == 0:
				continue
			opaque_count += 1
			_check(allowed.has(point), "%s contains only selected hand/beard pixels; unexpected (%d,%d)" % [entry.id, x, y])
			_check(image.get_pixelv(point).to_rgba32() == base.get_pixelv(point).to_rgba32(), "%s restores exact base pixel at (%d,%d)" % [entry.id, x, y])
	_check(opaque_count == allowed.size(), "%s restores every selected base pixel (%d/%d)" % [entry.id, opaque_count, allowed.size()])


func _species_from_output(output: String) -> String:
	var stem: String = output.get_file().get_basename()
	for species: String in SPECIES:
		if stem == species or stem.ends_with("_" + species):
			return species
	return ""


func _has_binary_alpha(image: Image) -> bool:
	var opaque := 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			var alpha: int = _alpha8(image, Vector2i(x, y))
			if alpha != 0 and alpha != 255:
				return false
			if alpha == 255:
				opaque += 1
	return opaque > 0


func _alpha8(image: Image, point: Vector2i) -> int:
	return roundi(image.get_pixelv(point).a * 255.0)


func _point(value: Variant) -> Vector2i:
	if not value is Array or value.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(value[0]), int(value[1]))


func _in_bounds(point: Vector2i, size: int) -> bool:
	return point.x >= 0 and point.y >= 0 and point.x < size and point.y < size


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Pixel24 equipment fit acceptance: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error("FAIL: " + failure)
	print("Pixel24 equipment fit acceptance: %d failure(s)" % _failures.size())
	quit(1)
