extends RefCounted
## Short adaptation effects, recorded against the irreversible acquisition event.
const DURATION=300
const EFFECTS={
	"FIREBOLT":"BURN","COLD_GLAND":"CHILL","FROST_SILK":"CHILL",
	"WATER_SAC":"SOAKED","ARC_GLAND":"SHOCK","CHARGE_ORGAN":"SHOCK",
	"VENOM_FANG":"POISON","CAUSTIC_BLOOD":"POISON",
	"HIDE_PLATING":"STIFF","CARAPACE":"STIFF","STONE_SKELETON":"STIFF",
	"ECHO_SENSE":"DIZZY","DEEP_EYE":"DIZZY","SHADOW_VEIL":"DIZZY",
	"PREDATOR_NERVE":"TREMOR","THROWING_INSTINCT":"TREMOR","HUNTER_LEAP":"TREMOR",
	"REGENERATIVE_TISSUE":"NAUSEA","BLOOD_SIPHON":"NAUSEA"}
static func apply(w,source)->bool:
	var effect:String=EFFECTS.get(str(source.data.ability_id),"NAUSEA")
	return w.emit_event("consumable.status",source.actor_id,source.actor_id,source.position,1,source.id,
		{"schema_version":1,"effect":effect,"until":str(w.world_time+DURATION)})!=null
static func status_error(e,source)->String:
	var effect:String=EFFECTS.get(str(source.data.get("ability_id","")),"NAUSEA")
	if e.type!="consumable.status" or e.actor_id!=source.actor_id or e.target_id!=source.actor_id \
			or e.world_time!=source.world_time or e.step_index!=source.step_index or e.position!=source.position \
			or e.magnitude!=1 or e.data.size()!=3 or e.data.get("effect")!=effect \
			or e.data.get("until")!=str(e.world_time+DURATION):return "part_ingestion_status_invalid"
	return ""
