class_name AsciiVisualStyle
extends RefCounted

const HangulGrammar=preload("res://playtest/hangul_glyph_grammar.gd")

const VISIBILITY_STATES := ["VISIBLE", "MEMORY", "UNSEEN"]
const LIFE_STATES := ["ACTIVE", "DOWNED", "DEAD"]
const AWARENESS_STATES := ["UNAWARE","SUSPICIOUS","ALERT","HUNTING","SEARCHING","RETURNING"]
const ITEM_PRESENTATION_KINDS := ["WEAPON","ARMOR","POTION","SCROLL","ACCESSORY","MATERIAL"]

# Actor typography has two independent jobs. Species/body class owns scale;
# combat importance owns ink weight. Keeping those channels separate prevents a
# dangerous goblin from suddenly reading as a physically larger creature.
const ACTOR_BODY_SCALES := {"SMALL":0.88,"NORMAL":1.0,"LARGE":1.15}
const SMALL_BODY_SPECIES := ["goblin","kobold","dwarf","halfling"]
const LARGE_BODY_SPECIES := ["orc","ogre","troll","giant"]

const ACTOR_WEAPON_VISUALS := {
	"SHORT_SWORD":{"family":"SWORD","glyph":"/","color_hex":"#e6e0c8"},
	"THRUSTING_SWORD":{"family":"SWORD","glyph":"|","color_hex":"#eef0df"},
	"HAND_AXE":{"family":"AXE","glyph":"7","color_hex":"#d6c7a8"},
	"MACE":{"family":"MACE","glyph":"!","color_hex":"#c3cad0"},
	"SPEAR":{"family":"SPEAR","glyph":"^","color_hex":"#d9cfaa"},
	"BOW":{"family":"BOW","glyph":")","color_hex":"#c99652"},
	"CROSSBOW":{"family":"CROSSBOW","glyph":"+","color_hex":"#c8aa70"},
}

const ACTOR_ARMOR_VISUALS := {
	"ARMOR_LEATHER":{"kind":"LEATHER","left_glyph":"[","right_glyph":"]",
		"color_hex":"#a7774e"},
	"ARMOR_PADDED":{"kind":"PADDED","left_glyph":"[","right_glyph":"]",
		"color_hex":"#8da0a5"},
}

const ITEM_PRESENTATION_DEFINITIONS := {
	# A deliberately small roguelike grammar. Items use old metal, bone and
	# alchemical inks so actors and combat feedback remain the brightest layer.
	"WEAPON":{"glyph":")","label":"무기","color_hex":"#aeb9b3",
		"highlight_hex":"#dce3d5","underlay_hex":"#171c1b"},
	"ARMOR":{"glyph":"[","label":"방어구","color_hex":"#83959b",
		"highlight_hex":"#c1cdd0","underlay_hex":"#12191c"},
	"POTION":{"glyph":"!","label":"물약","color_hex":"#b9504b",
		"highlight_hex":"#ef8a6f","underlay_hex":"#24100f"},
	"SCROLL":{"glyph":"?","label":"두루마리","color_hex":"#c8ad72",
		"highlight_hex":"#ead6a0","underlay_hex":"#211b10"},
	"ACCESSORY":{"glyph":"=","label":"장신구","color_hex":"#b48d47",
		"highlight_hex":"#dfbd70","underlay_hex":"#21190c"},
	"MATERIAL":{"glyph":"*","label":"재료","color_hex":"#7f9567",
		"highlight_hex":"#b3c78b","underlay_hex":"#11180e"},
}


static func item_presentation_spec(value:Variant)->Dictionary:
	var kind:=_item_presentation_kind(value)
	if not ITEM_PRESENTATION_DEFINITIONS.has(kind):
		return {"visible":false,"kind":"","glyph":"","label":"",
			"color_hex":"#00000000","highlight_hex":"#00000000",
			"underlay_hex":"#00000000","font_ratio":0.0,
			"corner_font_ratio":0.0,"draw_image":false,"draw_texture":false}.duplicate(true)
	var definition:Dictionary=ITEM_PRESENTATION_DEFINITIONS[kind]
	return {"visible":true,"kind":kind,"glyph":str(definition.glyph),
		"label":str(definition.label),"color_hex":str(definition.color_hex),
		"highlight_hex":str(definition.highlight_hex),
		"underlay_hex":str(definition.underlay_hex),"font_ratio":0.68,
		"corner_font_ratio":0.38,"underlay_opacity":0.58,
		"ink_family":"RELIC","weight":"BOLD","draw_image":false,
		"draw_texture":false}.duplicate(true)


static func ground_item_spec(cell:Dictionary)->Dictionary:
	var direct:Variant=cell.get("ground_item_glyph","")
	var spec:=item_presentation_spec(direct)
	if bool(spec.visible):return spec
	var values:Variant=cell.get("ground_items",[])
	if values is Array:
		for value in values:
			spec=item_presentation_spec(value)
			if bool(spec.visible):return spec
	return item_presentation_spec("")


static func _item_presentation_kind(value:Variant)->String:
	if value is Dictionary:
		for key in ["presentation_kind","item_kind","kind","use_kind","category","glyph"]:
			if value.has(key):
				var nested:=_item_presentation_kind(value[key])
				if not nested.is_empty():return nested
		return ""
	var text:=str(value).strip_edges().to_upper()
	if text in ITEM_PRESENTATION_KINDS:return text
	var aliases:={"CONSUMABLE_POTION":"POTION","CONSUMABLE_SCROLL":"SCROLL"}
	aliases.merge({")":"WEAPON","[":"ARMOR","!":"POTION","?":"SCROLL",
		"=":"ACCESSORY","*":"MATERIAL"})
	if aliases.has(text):return str(aliases[text])
	for kind in ITEM_PRESENTATION_DEFINITIONS:
		if str(ITEM_PRESENTATION_DEFINITIONS[kind].glyph)==str(value):return str(kind)
	return ""


static func awareness_spec(value:Variant)->Dictionary:
	var state:=str(value if value!=null else "UNAWARE").to_upper()
	if state not in AWARENESS_STATES:state="UNAWARE"
	var definitions:={
		"UNAWARE":{"glyph":"","color_hex":"#00000000","label":"무인지"},
		"SUSPICIOUS":{"glyph":"의","color_hex":"#e6c45c","label":"의심"},
		"ALERT":{"glyph":"경","color_hex":"#e88b3d","label":"경계"},
		"HUNTING":{"glyph":"추","color_hex":"#e24f49","label":"추적"},
		"SEARCHING":{"glyph":"수","color_hex":"#58bfc0","label":"수색"},
		"RETURNING":{"glyph":"귀","color_hex":"#849097","label":"복귀"},
	}
	var definition:Dictionary=definitions[state]
	return {"state":state,"glyph":str(definition.glyph),
		"color_hex":str(definition.color_hex),"label":str(definition.label),
		"visible":state!="UNAWARE"}.duplicate(true)


static func monster_identity_spec(actor:Dictionary)->Dictionary:
	var species_id:=str(actor.get("species_id","")).to_lower()
	match species_id:
		"goblin", "":
			return {"species_id":"goblin","glyph":"ㄱ","name":"고블린",
				"color_hex":"#83d34f","highlight_hex":"#d8ff9a"}.duplicate(true)
		"kobold":
			return {"species_id":"kobold","glyph":"ㅋ","name":"코볼트",
				"color_hex":"#b79a45","highlight_hex":"#ead47b"}.duplicate(true)
		_:
			return {"species_id":species_id,"glyph":HangulGrammar.species_bare_glyph(species_id),
				"name":str(actor.get("species_name","괴물")),"color_hex":"#ff615c",
				"highlight_hex":"#ffc2a8"}.duplicate(true)

const DIORAMA_PALETTE := {
	"void_hex":"#010203",
	"substrate_hex":"#030507",
	"unseen_ground_hex":"#020304",
	# MEMORY must remain clearly darker than live terrain while still being
	# distinguishable from the virtually black UNSEEN field on a phone display.
	"memory_ground_hex":"#060a0e",
	"visible_ground_hex":"#070b10",
	"wall_side_hex":"#080a12",
	"shadow_hex":"#010304",
	"ink_black_hex":"#02040a",
	"hero_ink_hex":"#ffd85a",
	"hostile_ink_hex":"#ff5d68",
	"ally_ink_hex":"#55d7ed",
}

const TERRAIN_DEFINITIONS := {
	# Full-cell Hangul material words replace the old ASCII legend. Ordinary floor
	# stays quiet; structural and hazardous materials carry the dense semantic ink.
	"floor": {"glyph":"", "base_hex":"#11161c", "glyph_hex":"#59636d", "edge_hex":"#333c44", "font_ratio":0.24, "raised":false, "ink_family":"VOID_FLOOR", "slab_ratio":Vector2(0.96,0.96), "glyph_offset":Vector2.ZERO, "outline_passes":0, "weight_passes":1},
	"stone_floor": {"glyph":"돌", "base_hex":"#182732", "glyph_hex":"#718796", "edge_hex":"#465d6d", "font_ratio":0.72, "raised":false, "ink_family":"STONE_HANGUL", "slab_ratio":Vector2(0.96,0.96), "glyph_offset":Vector2(-0.03,0.04), "outline_passes":0, "weight_passes":1},
	"wood_floor": {"glyph":"나", "base_hex":"#302820", "glyph_hex":"#9b8162", "edge_hex":"#67533e", "font_ratio":0.72, "raised":false, "ink_family":"WOOD_HANGUL", "slab_ratio":Vector2(0.96,0.96), "glyph_offset":Vector2(0.03,0.04), "outline_passes":0, "weight_passes":1},
	"metal": {"glyph":"쇠", "base_hex":"#253740", "glyph_hex":"#80a0ad", "edge_hex":"#57737e", "font_ratio":0.78, "raised":false, "ink_family":"METAL_HANGUL", "slab_ratio":Vector2(0.96,0.96), "glyph_offset":Vector2.ZERO, "outline_passes":0, "weight_passes":1},
	"rubble": {"glyph":"깨", "base_hex":"#352d23", "glyph_hex":"#9a825f", "edge_hex":"#69583d", "font_ratio":0.74, "raised":false, "ink_family":"RUBBLE_HANGUL", "slab_ratio":Vector2(0.96,0.96), "glyph_offset":Vector2(-0.04,0.05), "outline_passes":0, "weight_passes":1},
	"shallow_water": {"glyph":"물", "base_hex":"#123b48", "glyph_hex":"#759eaa", "edge_hex":"#376f80", "font_ratio":0.84, "raised":false, "ink_family":"WATER_HANGUL", "slab_ratio":Vector2(0.96,0.96), "glyph_offset":Vector2(0.02,0.03), "outline_passes":0, "weight_passes":1},
	"wall": {"glyph":"벽", "base_hex":"#262d34", "glyph_hex":"#9faab3", "edge_hex":"#626c75", "font_ratio":0.94, "raised":true, "ink_family":"WALL_HANGUL", "slab_ratio":Vector2(0.98,0.96), "glyph_offset":Vector2.ZERO, "outline_passes":1, "weight_passes":2},
}


static func diorama_palette_spec() -> Dictionary:
	return DIORAMA_PALETTE.duplicate(true)


static func visibility_state(cell: Dictionary) -> String:
	var state := str(cell.get("visibility_state", cell.get("visibility", "VISIBLE"))).to_upper()
	return state if state in VISIBILITY_STATES else "VISIBLE"


static func visibility_spec(cell_or_state: Variant) -> Dictionary:
	var state := str(cell_or_state).to_upper() if cell_or_state is String else visibility_state(
		cell_or_state if cell_or_state is Dictionary else {})
	if state not in VISIBILITY_STATES:
		state = "VISIBLE"
	return {
		"state": state,
		"draw_terrain": state != "UNSEEN",
		"draw_hazards": state == "VISIBLE",
		"draw_actors": state == "VISIBLE",
		"accepts_actor_input": state == "VISIBLE",
		"opacity": 1.0 if state == "VISIBLE" else (0.38 if state == "MEMORY" else 0.0),
		"background_hex":str(DIORAMA_PALETTE.get({
			"VISIBLE":"visible_ground_hex", "MEMORY":"memory_ground_hex",
			"UNSEEN":"unseen_ground_hex"}[state], "#030507")),
		"glyph_desaturation":0.0 if state == "VISIBLE" else (0.78 if state == "MEMORY" else 1.0),
	}.duplicate(true)


static func terrain_spec(cell: Dictionary) -> Dictionary:
	var terrain_id := str(cell.get("terrain_id", cell.get("terrain", "floor")))
	var registered := TERRAIN_DEFINITIONS.has(terrain_id)
	var definition: Dictionary = TERRAIN_DEFINITIONS.get(terrain_id, {
		"glyph":"", "base_hex":"#091017", "glyph_hex":"#091017", "edge_hex":"#060a0e",
		"font_ratio":0.52, "raised":false,
	})
	var result := definition.duplicate(true)
	var visibility := visibility_spec(cell)
	result["terrain_id"] = terrain_id
	result["visibility_state"] = visibility.state
	result["visible"] = bool(visibility.draw_terrain)
	result["opacity"] = float(visibility.opacity)
	result["registered"] = registered
	result["glyph_primary"] = registered and bool(visibility.draw_terrain)
	result["draw_image"] = false
	result["draw_tile_border"] = false
	var slab_ratio:Vector2=result.get("slab_ratio",Vector2.ZERO)
	result["draw_cell_surface"] = registered and slab_ratio.x>0.0 and slab_ratio.y>0.0 \
		and bool(visibility.draw_terrain)
	result["background_source"] = "TERRAIN_PROJECTED"
	result["outline_hex"] = "#020508"
	result["slab_hex"] = str(result.get("base_hex","#091017"))
	return result.duplicate(true)


static func hazard_spec(cell: Dictionary) -> Dictionary:
	var visibility := visibility_spec(cell)
	var fire := clampi(int(cell.get("fire_intensity", cell.get("fire", 0))), 0, 100)
	var wetness := clampi(int(cell.get("wetness", 0)), 0, 100)
	var cues: Array[Dictionary] = []
	if bool(visibility.draw_hazards) and fire > 0:
		cues.append({"kind":"FIRE", "glyph":"불", "color_hex":"#ff7a3d", "value":fire,
			"corner":"BOTTOM_LEFT", "fill_alpha":0.12 + 0.34 * float(fire) / 100.0})
	if bool(visibility.draw_hazards) and wetness > 0:
		cues.append({"kind":"WET", "glyph":"물", "color_hex":"#62c8ff", "value":wetness,
			"corner":"BOTTOM_RIGHT", "fill_alpha":0.08 + 0.20 * float(wetness) / 100.0})
	# Conductivity remains inspectable simulation data, but it has no persistent
	# floor glyph. Electricity should be communicated only when an actual event
	# happens, not as a misleading lightning mark on every conductive tile.
	return {"visibility_state":visibility.state, "fire":fire, "wetness":wetness,
		"cues":cues}.duplicate(true)


static func feature_spec(feature_id: String) -> Dictionary:
	var definitions := {
		"run_entry":{"glyph":"입", "color_hex":"#55C8FF", "halo_hex":"#173c52"},
		"run_exit_locked":{"glyph":"닫", "color_hex":"#E47A88", "halo_hex":"#51232e"},
		"run_exit_open":{"glyph":"출", "color_hex":"#6EFFA8", "halo_hex":"#17442e"},
		"open_door":{"glyph":"문", "color_hex":"#FFD166", "halo_hex":"#4a3512"},
	}
	if not definitions.has(feature_id):
		return {"visible":false, "feature_id":"", "glyph":"",
			"color_hex":"#FFFFFF", "halo_hex":"#000000"}.duplicate(true)
	var definition: Dictionary = definitions[feature_id]
	return {"visible":true, "feature_id":feature_id,
		"glyph":str(definition.glyph),
		"color_hex":str(definition.color_hex),
		"halo_hex":str(definition.halo_hex)}.duplicate(true)


static func ground_mark_spec(cell:Dictionary)->Dictionary:
	var mark_id:=str(cell.get("ground_mark_id","")).to_lower()
	var visibility:=visibility_spec(cell)
	if mark_id!="blood" or not bool(visibility.draw_terrain):
		return {"visible":false,"mark_id":"","glyph":"","color_hex":"#00000000",
			"opacity":0.0,"font_ratio":0.0}.duplicate(true)
	return {"visible":true,"mark_id":"blood","glyph":"피","color_hex":"#a42f3f",
		"opacity":0.88 if str(visibility.state)=="VISIBLE" else 0.34,
		"font_ratio":0.78,"draw_image":false,"draw_texture":false}.duplicate(true)


static func actor_spec(actor: Dictionary, ghost: bool = false) -> Dictionary:
	var species_id := str(actor.get("species_id", "")).to_lower()
	var faction_id := str(actor.get("faction_id", "")).to_lower()
	var is_protagonist := bool(actor.get("is_protagonist", false))
	var is_enemy := bool(actor.get("is_enemy", false)) or faction_id == "enemy"
	var is_party := is_protagonist or faction_id == "party" or int(actor.get("roster_slot", -1)) >= 0
	var composition_actor:=actor
	if species_id.is_empty():
		composition_actor=actor.duplicate(false)
		composition_actor["species_id"]="goblin" if is_enemy else "human"
	var composition:Dictionary=HangulGrammar.actor_glyph(composition_actor)
	var glyph := str(composition.glyph)
	var color_hex := "#d5e2ea"
	var highlight_hex := "#ffffff"
	if is_protagonist:
		color_hex = "#ffdc55"; highlight_hex = "#fff3a8"
	elif is_enemy:
		var identity:=monster_identity_spec(actor)
		color_hex=str(identity.color_hex)
		highlight_hex=str(identity.highlight_hex)
	elif is_party and species_id == "goblin":
		color_hex = "#91e45f"; highlight_hex = "#dcffa4"
	elif is_party:
		if int(actor.get("roster_slot", -1)) == 2:
			color_hex = "#759cff"; highlight_hex = "#d7e0ff"
		else:
			color_hex = "#5ed6ff"; highlight_hex = "#d0f4ff"

	var life_state := str(actor.get("life_state", "ACTIVE")).to_upper()
	if life_state not in LIFE_STATES:
		life_state = "DEAD" if actor.has("alive") and not bool(actor.get("alive", true)) else "ACTIVE"
	if life_state == "DEAD":
		glyph = "흔"; color_hex = "#8d6870"; highlight_hex = "#c7959d"
	var statuses: Array[String] = []
	var raw_statuses: Variant = actor.get("status_ids", [])
	if raw_statuses is Array:
		for raw_status in raw_statuses:
			var status_id := str(raw_status.get("status_id", "")) if raw_status is Dictionary else str(raw_status)
			if not status_id.is_empty() and status_id not in statuses:
				statuses.append(status_id)
	statuses.sort()
	var facing := normalized_facing(actor.get("facing", [0, 1]))
	var stance := str(actor.get("visual_stance", actor.get("stance", "IDLE"))).to_upper()
	if stance not in ["IDLE", "MOVING", "ENGAGE", "FLEE", "APPROACH", "GUARD"]:
		stance = "IDLE"
	var geometry := _pose_geometry(life_state, facing, stance)
	var guarded := bool(actor.get("guarded", false))
	var body_class:=actor_body_class(actor)
	var presence_class:=actor_presence_class(actor)
	var bold_presence:=presence_class in ["HERO","ELITE","BOSS"]
	var step_phase:=str(actor.get("step_phase","SETTLE")).to_upper()
	var stride_sign:=clampi(int(actor.get("stride_sign",0)),-1,1)
	var glyph_bob_ratio:=clampf(float(actor.get("glyph_bob_ratio",0.0)),-1.0,0.0)
	if stance=="MOVING":
		geometry=_pose_geometry(life_state,facing,stance,step_phase,stride_sign,
			glyph_bob_ratio)
	# The field stays black at rest. Underlays are semantic registration marks,
	# not faction-coloured tile cards; the actor glyph carries the saturated ink.
	var underlay_hex:="#262318" if is_protagonist else ("#281317" if is_enemy \
		else ("#102329" if is_party else "#141b20"))
	var equipment:=actor_equipment_spec(actor)
	return {
		"glyph":glyph, "color_hex":color_hex, "highlight_hex":highlight_hex,
		"composition":composition,"grammar_id":"HANGUL_BODY_ASCII_EQUIPMENT_V1",
		"shadow_hex":"#03070b", "outline_hex":"#0a1016",
		"opacity":0.46 if ghost else (0.58 if life_state == "DOWNED" else 1.0),
		"ghost":ghost, "life_state":life_state, "statuses":statuses,
		"bleeding":"BLEEDING" in statuses, "guarded":guarded,
		"facing":[facing.x, facing.y], "pose":geometry.pose, "stance":stance,
		"body_center":geometry.glyph_center, "glyph_center":geometry.glyph_center,
		"glyph_half_width":geometry.glyph_half_width,
		"glyph_half_height":geometry.glyph_half_height,
		"glyph_is_body":true, "detached_head":false,
		"glyph_weight":"INK_STAMP", "glyph_outline_passes":4,
		"glyph_weight_passes":2 if bold_presence else 1,
		"glyph_font_weight":"BOLD" if bold_presence else "REGULAR",
		"body_class":body_class,"presence_class":presence_class,
		"glyph_scale":float(ACTOR_BODY_SCALES.get(body_class,1.0)),
		"glyph_offset":Vector2.ZERO,
		"underlay_hex":underlay_hex,"underlay_opacity":0.52 if not ghost else 0.22,
		"underlay_ratio":Vector2(0.84,0.46),
		"step_phase":step_phase,"stride_sign":stride_sign,
		"limb_segments":[],
		"guard_segments":_guard_geometry(facing) if guarded and life_state == "ACTIVE" else [],
		# The Hangul body stays stable. Static ASCII equipment shares its visual
		# cell, while logical mapping, FOV and hit authority remain unchanged.
		"equipment":equipment,
		"draw_equipment":bool(equipment.visible) and life_state=="ACTIVE",
		"equipment_primitive_count":int(equipment.primitive_count) \
			if life_state=="ACTIVE" else 0,
		"draw_head":false, "draw_limbs":false,
	}.duplicate(true)


static func actor_body_class(actor:Dictionary)->String:
	var explicit:=str(actor.get("body_class",actor.get("presentation_body_class",""))).to_upper()
	if explicit in ACTOR_BODY_SCALES:return explicit
	var species_id:=str(actor.get("species_id","")).to_lower()
	if species_id in SMALL_BODY_SPECIES:return "SMALL"
	if species_id in LARGE_BODY_SPECIES:return "LARGE"
	return "NORMAL"


static func actor_presence_class(actor:Dictionary)->String:
	var explicit:=str(actor.get("presence_class",actor.get(
		"presentation_presence_class",""))).to_upper()
	if explicit in ["NORMAL","HERO","ELITE","BOSS"]:return explicit
	if bool(actor.get("is_boss",false)):return "BOSS"
	if bool(actor.get("is_elite",false)):return "ELITE"
	if bool(actor.get("is_protagonist",false)):return "HERO"
	var threat_id:=str(actor.get("threat_id","")).to_upper()
	if threat_id=="LETHAL":return "BOSS"
	if threat_id=="DANGEROUS":return "ELITE"
	return "NORMAL"


static func actor_equipment_spec(actor:Dictionary)->Dictionary:
	var raw:Variant=actor.get("equipment_visual",actor.get("equipment",{}))
	var equipment:Dictionary=raw if raw is Dictionary else {}
	var weapon_id:=str(equipment.get("weapon_id",actor.get("weapon_id","UNARMED_STRIKE"))).to_upper()
	var weapon:Dictionary=ACTOR_WEAPON_VISUALS.get(weapon_id,{})
	var armor_id:=str(equipment.get("armor_definition_id",
		actor.get("armor_definition_id",""))).to_upper()
	var armor:Dictionary=ACTOR_ARMOR_VISUALS.get(armor_id,{})
	var weapon_visible:=not weapon.is_empty()
	var armor_visible:=not armor.is_empty()
	return {
		"visible":weapon_visible or armor_visible,
		"weapon_visible":weapon_visible,"weapon_id":weapon_id,
		"weapon_family":str(weapon.get("family","UNARMED")),
		"weapon_glyph":str(weapon.get("glyph","")),
		"weapon_color_hex":str(weapon.get("color_hex","#00000000")),
		"armor_visible":armor_visible,"armor_definition_id":armor_id,
		"armor_kind":str(armor.get("kind","NONE")),
		"armor_left_glyph":str(armor.get("left_glyph","")),
		"armor_right_glyph":str(armor.get("right_glyph","")),
		"armor_component":"",
		"armor_color_hex":str(armor.get("color_hex","#00000000")),
		"composed_glyph":"",
		"primitive_count":int(weapon_visible)+2*int(armor_visible),
		"semantic_component_count":int(weapon_visible)+int(armor_visible),
		"tile_local":true,"changes_core_glyph":false,
		"composition_mode":"STATIC_ASCII","draw_image":false,
	}.duplicate(true)


static func follower_spec(actor: Dictionary) -> Dictionary:
	var display_role := str(actor.get("display_role", "")).to_upper()
	var logical := _array_position(actor.get("logical_position", actor.get("position", [])))
	var display := _array_position(actor.get("display_position", actor.get("position", [])))
	var has_separation := logical != Vector2i(-1,-1) and display != Vector2i(-1,-1) \
		and logical != display
	return {
		"display_role":display_role,
		"visible":display_role == "FOLLOWER" and has_separation,
		"logical_position":[logical.x,logical.y],
		"display_position":[display.x,display.y],
		"tether_hex":"#67bfe2", "footprint_hex":"#9cdbef",
		"opacity":0.62, "dash_count":4, "footprint_radius_ratio":0.12,
	}.duplicate(true)


static func normalized_facing(value: Variant) -> Vector2i:
	var facing := Vector2i.DOWN
	if value is Vector2i:
		facing = value
	elif value is Vector2:
		facing = Vector2i(signi(int(value.x)), signi(int(value.y)))
	elif value is Array and value.size() == 2:
		facing = Vector2i(signi(int(value[0])), signi(int(value[1])))
	if facing == Vector2i.ZERO:
		return Vector2i.DOWN
	return Vector2i(signi(facing.x), signi(facing.y))


static func bracket_segments(rect: Rect2, inset_ratio: float = 0.08,
		arm_ratio: float = 0.24) -> Array:
	var inset := maxf(1.0, minf(rect.size.x, rect.size.y) * inset_ratio)
	var inner := rect.grow(-inset)
	var arm := maxf(3.0, minf(inner.size.x, inner.size.y) * arm_ratio)
	var tl := inner.position; var tr := Vector2(inner.end.x, inner.position.y)
	var br := inner.end; var bl := Vector2(inner.position.x, inner.end.y)
	return [
		[tl, tl + Vector2(arm, 0)], [tl, tl + Vector2(0, arm)],
		[tr, tr + Vector2(-arm, 0)], [tr, tr + Vector2(0, arm)],
		[br, br + Vector2(-arm, 0)], [br, br + Vector2(0, -arm)],
		[bl, bl + Vector2(arm, 0)], [bl, bl + Vector2(0, -arm)],
	].duplicate(true)


static func _pose_geometry(life_state: String, facing: Vector2i,
		stance: String = "IDLE", step_phase:String="SETTLE", stride_sign:int=0,
		glyph_bob_ratio:float=0.0) -> Dictionary:
	var half_width := 0.40
	var half_height := 0.18
	if life_state == "DOWNED":
		var center := Vector2(0.0, 0.25)
		return {"pose":"DOWNED", "glyph_center":center,
			"glyph_half_width":half_width, "glyph_half_height":half_height,
			"limb_segments":[
				[center+Vector2(-half_width,0.0),Vector2(-0.49,0.12)],
				[center+Vector2(half_width,0.0),Vector2(0.49,0.34)],
				[center+Vector2(-half_width*0.30,half_height),Vector2(-0.30,0.47)],
				[center+Vector2(half_width*0.30,half_height),Vector2(0.32,0.45)],
			]}
	if life_state == "DEAD":
		return {"pose":"DEAD", "glyph_center":Vector2(0.0,0.28),
			"glyph_half_width":half_width, "glyph_half_height":half_height,
			"limb_segments":[]}
	var direction := Vector2(facing).normalized()
	var center := Vector2(0.0,0.18+glyph_bob_ratio*0.026)
	var left_edge := center+Vector2(-half_width,-0.01)
	var right_edge := center+Vector2(half_width,-0.01)
	var left_hip := center+Vector2(-half_width*0.28,half_height)
	var right_hip := center+Vector2(half_width*0.28,half_height)
	var stride := 0.10 if stance in ["MOVING", "APPROACH", "FLEE"] else 0.035
	if stance=="MOVING":
		stride=0.13*float(stride_sign) if step_phase!="SETTLE" else 0.025
	var attack_lift := -0.13 if stance == "ENGAGE" else 0.0
	var facing_x := direction.x*0.065
	var facing_y := direction.y*0.040
	return {"pose":"STANDING", "glyph_center":center,
		"glyph_half_width":half_width, "glyph_half_height":half_height,
		"limb_segments":[
			[left_edge,Vector2(-0.49+facing_x,center.y+0.08-facing_y)],
			[right_edge,Vector2(0.49+facing_x,center.y+0.07+facing_y+attack_lift)],
			[left_hip,Vector2(-0.19-direction.x*stride,0.47-direction.y*0.025+glyph_bob_ratio*0.012)],
			[right_hip,Vector2(0.19+direction.x*stride,0.47+direction.y*0.025+glyph_bob_ratio*0.012)],
		]}


static func _guard_geometry(facing: Vector2i) -> Array:
	var direction := Vector2(facing).normalized()
	var side := Vector2(-direction.y, direction.x)
	var center := direction * 0.29 + Vector2(0.0,0.01)
	return [[center-side*0.15-direction*0.04, center-side*0.15+direction*0.06],
		[center-side*0.15-direction*0.04, center+side*0.15-direction*0.04],
		[center+side*0.15-direction*0.04, center+side*0.15+direction*0.06]]


static func _array_position(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Array and value.size()==2:
		return Vector2i(int(value[0]),int(value[1]))
	return Vector2i(-1,-1)
