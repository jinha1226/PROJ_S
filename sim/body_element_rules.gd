extends RefCounted
## Input is already resistance-resolved HP damage. Never apply resistance twice.
## Initial tuning values; physiological incapacitation is a separate lifecycle.
const RULESET_ID:="body-element-v1"
static func packet(element:String,damage:int)->Dictionary:
	if element not in ["FIRE","ELECTRIC"] or damage<=0 or damage>100000:return {}
	return {"form":element,"base_force":damage,"contact_size":20,"penetration":0,"stagger_force":0}

static func response(element:String,damage:int,shock_threshold:int)->Dictionary:
	if element not in ["FIRE","ELECTRIC"] or damage<=0 or damage>100000:return {}
	if element=="FIRE":
		return {"damage":damage,"depth":damage/4,"shock":maxi(1,damage*25/maxi(1,shock_threshold))}
	return {"damage":damage/4,"depth":damage/8,"shock":maxi(1,damage*200/maxi(1,shock_threshold))}
