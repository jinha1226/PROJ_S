extends RefCounted
## Stances: how a member uses whatever it has — charge in, keep range, or
## guard someone. Personality sets an aptitude per stance; the player may pick
## any stance, and an uncomfortable one conflicts like a knob does.
const IDS := ["CHARGER","SKIRMISHER","GUARDIAN"]
const NAMES := {"CHARGER":"돌격형","SKIRMISHER":"거리형","GUARDIAN":"호위형"}
const SHORT := {"CHARGER":"돌","SKIRMISHER":"거","GUARDIAN":"호"}
const Abilities = preload("res://expedition/abilities.gd")

static func aptitude(profile) -> Dictionary:
	return {"CHARGER":profile.value("X")-profile.value("E"),
		"SKIRMISHER":profile.value("E")+profile.value("C")-1000,
		"GUARDIAN":profile.value("A")+profile.value("H")-1000}

static func default_stance(profile) -> String:
	var apt := aptitude(profile)
	var best: String = IDS[0]
	for id in IDS:
		if int(apt[id]) > int(apt[best]): best = id
	return best

## Within (200 + C/5) of the best aptitude: the conscientious tolerate more.
static func comfortable(profile, stance: String) -> bool:
	var apt := aptitude(profile)
	return int(apt.get(stance,-9999)) >= int(apt[default_stance(profile)])-(200+profile.value("C")/5)

## The equipped part with reach, if any: what a skirmisher keeps its distance with.
static func ranged_part(actor: Dictionary) -> String:
	for id in actor.equipped_abilities:
		var def: Dictionary = Abilities.DEFINITIONS.get(id,{})
		if def.is_empty(): continue
		if def.effect in ["DAMAGE","LUNGE"] and int(def.range) >= 3: return id
	return ""

## What the build hints at; a badge, never a rule.
static func suggested(actor: Dictionary) -> String:
	if not ranged_part(actor).is_empty(): return "SKIRMISHER"
	if actor.equipped_abilities.any(func(id): return Abilities.DEFINITIONS.get(id,{}).get("effect","") == "GUARD"): return "GUARDIAN"
	return "CHARGER"

## The stance the member actually fights in: chosen while calm, its own when anxious.
static func effective(actor: Dictionary) -> String:
	if int(actor.stress) >= 100: return default_stance(actor.profile)
	return str(actor.get("stance",default_stance(actor.profile)))
