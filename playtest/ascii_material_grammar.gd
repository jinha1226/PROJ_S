class_name AsciiMaterialGrammar
extends RefCounted

## Presentation-only ASCII identity and material grammar. It never changes
## simulation terrain, collision, FOV, saves, RNG, or logical actor positions.

const SPECIES_GLYPHS := {
	"human":"h", "goblin":"g", "kobold":"k", "dwarf":"d", "elf":"e",
	"orc":"o", "beastkin":"b", "amphibian":"a", "slime":"s",
}
const ANIMATED_MATERIALS := ["water", "grass", "fire", "poison"]

static func actor_glyph(actor:Dictionary)->Dictionary:
	var species_id:=str(actor.get("species_id","human")).to_lower()
	if species_id.is_empty():species_id="human"
	var glyph:=species_bare_glyph(species_id)
	if bool(actor.get("is_protagonist",false)):glyph="@"
	var raw:Variant=actor.get("equipment_visual",actor.get("equipment",{}))
	var equipment:Dictionary=raw if raw is Dictionary else {}
	var weapon_id:=str(equipment.get("weapon_id",
		actor.get("weapon_id","UNARMED_STRIKE"))).to_upper()
	var armor_id:=str(equipment.get("armor_definition_id",
		actor.get("armor_definition_id",""))).to_upper()
	return {
		"glyph":glyph,"species_id":species_id,"species_component":glyph,
		"weapon_component":"","armor_component":"","weapon_id":weapon_id,
		"armor_definition_id":armor_id,"weapon_family":"UNARMED",
		"has_weapon":weapon_id not in ["","NONE","UNARMED_STRIKE"],
		"has_armor":armor_id not in ["","NONE","UNARMORED"],
		"is_composed":false,"grammar_id":"ASCII_MATERIAL_V1",
	}.duplicate(true)

static func species_bare_glyph(species_id:String)->String:
	return str(SPECIES_GLYPHS.get(species_id.to_lower(),"?"))

static func presentation_material_id(cell:Dictionary)->String:
	var explicit:=str(cell.get("presentation_material_id",
		cell.get("presentation_terrain_id",cell.get("environment_material_id",
		cell.get("material_id",""))))).to_lower()
	if explicit in ["water","grass","poison","ice","fog"]:return explicit
	if int(cell.get("poison_intensity",0))>0:return "poison"
	for flag in ["grass","ice","fog"]:
		if bool(cell.get(flag,false)):return flag
	var terrain_id:=str(cell.get("terrain_id",cell.get("terrain","floor"))).to_lower()
	return {"shallow_water":"water","water":"water","grass":"grass",
		"poison":"poison","poison_pool":"poison","ice":"ice","fog":"fog"}.get(
		terrain_id,terrain_id)

static func material_motion_spec(position:Vector2i,material_id:String,
		visibility_state:String,sample_time_ms:int,animate:bool=true)->Dictionary:
	var kind:=material_id.to_lower()
	var visible:=visibility_state.to_upper()=="VISIBLE" and kind in ANIMATED_MATERIALS
	var animated:=visible and animate
	var quantum_ms:=150
	var frames:=8
	match kind:
		"grass": quantum_ms=225;frames=8
		"fire": quantum_ms=75;frames=8
		"poison": quantum_ms=180;frames=8
	var tick:=int(floor(float(maxi(0,sample_time_ms))/float(quantum_ms))) if animated else 0
	var coordinate_phase:=visual_hash(position,{
		"water":211,"grass":307,"fire":401,"poison":503}.get(kind,0))%frames
	var phase:=(tick+coordinate_phase)%frames if animated else coordinate_phase
	var wave:=sin(TAU*float(phase)/float(frames)) if animated else 0.0
	var offset:=Vector2.ZERO;var opacity:=1.0;var glow:=0.0
	match kind:
		"water": offset.x=wave*0.055;opacity=0.86+0.08*cos(TAU*float(phase)/frames)
		"grass": offset.x=wave*0.035;offset.y=-absf(wave)*0.012
		"fire": offset.y=-absf(wave)*0.065;opacity=0.82+0.18*absf(wave);glow=0.14+0.12*absf(wave)
		"poison": offset.y=-float(phase)/float(frames)*0.055;opacity=0.76+0.16*absf(wave);glow=0.05+0.06*absf(wave)
	if not animated:
		offset=Vector2.ZERO;opacity=1.0;glow=0.0
	return {"visible":visible,"animated":animated,"material_id":kind,
		"position":[position.x,position.y],"phase":phase,"phase_count":frames,
		"coordinate_phase":coordinate_phase,"quantum_ms":quantum_ms,
		"offset_ratio":offset,"opacity":opacity,"glow_alpha":glow,
		"draw_trail":kind=="water" and visible,"draw_reflection":kind=="water" and visible,
		"rises":kind=="poison" and visible}.duplicate(true)

static func visual_hash(position:Vector2i,salt:int)->int:
	return ((int(position.x)*73856093) ^ (int(position.y)*19349663) \
		^ (salt*83492791)) & 0x7fffffff
