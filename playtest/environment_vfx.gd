extends RefCounted

# Presentation-only mapping: no RNG, simulation writes, or per-frame events.
const EVENTS := {
	"environment.ignited":"ENV_IGNITE", "environment.fire_spread":"ENV_IGNITE",
	"environment.fire_extinguished":"ENV_EXTINGUISH", "environment.fire_weakened":"ENV_EXTINGUISH",
	"environment.fire_burned_out":"ENV_EXTINGUISH",
	"environment.water_frozen":"ENV_FREEZE", "environment.ice_melted":"ENV_MELT",
	"environment.steam_condensed":"ENV_CONDENSE", "environment.water_applied":"ENV_SPLASH",
	"environment.electric_arc":"ENV_SPARK", "environment.terrain_destroyed":"ENV_DEBRIS",
	"environment.explosion_wave":"ENV_BLAST",
}
const STYLES := {
	"ENV_IGNITE":{"color":"#ff963e","duration":650},
	"ENV_EXTINGUISH":{"color":"#a4c9d2","duration":750},
	"ENV_FREEZE":{"color":"#bdedff","duration":850},
	"ENV_MELT":{"color":"#69c9ed","duration":750},
	"ENV_CONDENSE":{"color":"#a8e5ef","duration":650},
	"ENV_SPLASH":{"color":"#65b9ee","duration":550},
	"ENV_SPARK":{"color":"#ffee9a","duration":420},
	"ENV_BLAST":{"color":"#ffae51","duration":650},
	"ENV_RUPTURE":{"color":"#d3dbe0","duration":650},
	"ENV_DEBRIS":{"color":"#a79b83","duration":800},
}
const MAX_PER_BATCH := 24

static func kind(event) -> String:
	if event.type=="environment.explosion_wave" and event.data.get("kind")=="rupture":
		return "ENV_RUPTURE"
	if event.magnitude<=0 and event.type!="environment.fire_burned_out":return ""
	return str(EVENTS.get(event.type,""))

static func style(effect_kind:String)->Dictionary:
	return STYLES.get(effect_kind,{}).duplicate()
