extends RefCounted
## Separate scenario identity keeps legacy party saves and their replay intact.
const SCENARIO_ID := "SOLO_EXPLORATION_V2"
const DUO_SCENARIO_ID := "DUO_AUTOBATTLE_V1"

static func allows_companions(scenario_id:String)->bool:
	return scenario_id not in [SCENARIO_ID, DUO_SCENARIO_ID]
