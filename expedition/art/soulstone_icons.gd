extends RefCounted
## Attack/wait soulstone artwork. All overlays are composited once per visual
## combination, then the same texture is reused in every UI surface.
const Mobile = preload("res://expedition/progression/attack_wait.gd")
const ROOT := "res://assets/soulstone-icons-v1/png/"
const FRAMES := ["red","purple","green"]
const EFFECTS := ["bleed","poison","burn","freeze","shock","curse","extra_strike","crit","heal","guard","thorns","summon","wet","push"]
const BADGES := ["boost","burst"]
const STATUS_EFFECT := {
	"bleed":"bleed","poison":"poison","burn":"burn","slow":"freeze","freeze":"freeze",
	"charge":"shock","stun":"shock","weak":"curse","vulnerable":"curse","confuse":"curse",
	"death_mark":"curse","exposed":"crit","wet":"wet","blessing":"guard","guard":"guard",
	"regen":"heal","healing":"heal"}
const ICON_NAMES := {"bleed":"출혈","poison":"독","burn":"화상","freeze":"빙결","shock":"감전","curse":"저주","extra_strike":"연타","crit":"조준","heal":"회복","guard":"보호","thorns":"반격","summon":"소환","wet":"젖음","push":"밀치기"}
static var cache: Dictionary = {}
static var image_cache: Dictionary = {}
static var effect_cache: Dictionary = {}

static func source(folder: String, key: String) -> Image:
	var path := ROOT+folder+"/"+key+".png"
	if not image_cache.has(path):
		var loaded := Image.new()
		if loaded.load(path) != OK: return null
		image_cache[path] = loaded
	return image_cache[path]

static func effect_icon(key: String) -> Texture2D:
	if key not in EFFECTS: return null
	if not effect_cache.has(key):
		var picture := source("effects",key)
		if picture == null: return null
		effect_cache[key] = ImageTexture.create_from_image(picture)
	return effect_cache[key]

static func status_icon(status: String) -> Texture2D:
	return effect_icon(str(STATUS_EFFECT.get(status,"")))

static func stone_icon(stone_id: String) -> Texture2D:
	var effect: Dictionary = Mobile.row(stone_id)
	if effect.is_empty(): return null
	var colour: String = str(effect.get("colour",""))
	var icon: String = str(effect.get("icon",""))
	var badge: String = str(effect.get("badge",""))
	if colour not in FRAMES or icon not in EFFECTS: return null
	var key := colour+"/"+icon+"/"+badge
	if cache.has(key): return cache[key]
	var frame := source("frames",colour)
	var drawing := source("effects",icon)
	if frame == null or drawing == null: return null
	var picture: Image = frame.duplicate()
	picture.convert(Image.FORMAT_RGBA8)
	picture.blend_rect(drawing,Rect2i(Vector2i.ZERO,drawing.get_size()),Vector2i.ZERO)
	if badge in BADGES:
		var mark := source("badges",badge)
		if mark != null: picture.blend_rect(mark,Rect2i(Vector2i.ZERO,mark.get_size()),Vector2i.ZERO)
	var result := ImageTexture.create_from_image(picture)
	cache[key] = result
	return result
