extends RefCounted
## Behaviour knobs and where personality puts them. A knob outside its comfort
## band is a standing order the member dislikes: it costs stress at every
## battle start, and an anxious member ignores it.
const DEFAULT := {"posture":0,"cohesion":0,"retreat_hp":25}
const RANGE := {"posture":[-100,100],"cohesion":[-100,100],"retreat_hp":[0,60]}

static func defaults(profile) -> Dictionary:
	return {"posture":clampi((profile.value("X")-profile.value("E"))/10,-100,100),
		"cohesion":clampi((profile.value("A")-500)/5,-100,100),
		"retreat_hp":clampi(10+profile.value("E")/25,0,50)}

## [low, high] per knob; wider for the conscientious.
static func comfort(profile) -> Dictionary:
	var base := defaults(profile)
	var wide: int = 20+profile.value("C")/20
	var narrow: int = 10+profile.value("C")/50
	return {"posture":[base.posture-wide,base.posture+wide],
		"cohesion":[base.cohesion-wide,base.cohesion+wide],
		"retreat_hp":[base.retreat_hp-narrow,base.retreat_hp+narrow]}

static func conflicted(actor: Dictionary) -> bool:
	var band := comfort(actor.profile)
	for key in DEFAULT:
		var value: int = int(actor.knobs.get(key,DEFAULT[key]))
		if value < int(band[key][0]) or value > int(band[key][1]): return true
	return false

## The knobs the member actually fights with: as set while calm, personality
## defaults when anxious, an extreme posture when collapsed.
static func effective(actor: Dictionary) -> Dictionary:
	var chosen: Dictionary = actor.get("knobs",DEFAULT).duplicate()
	if int(actor.stress) < 100: return chosen
	var own := defaults(actor.profile)
	if int(actor.stress) >= 150: own.posture = -100 if actor.profile.value("E") >= 500 else 100
	return own
