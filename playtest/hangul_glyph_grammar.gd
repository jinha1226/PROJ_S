class_name HangulGlyphGrammar
extends RefCounted

## Presentation-only Hangul body grammar.
##
## Species owns one stable consonant silhouette (ㅇ, ㄱ ...). Equipment remains
## structured state and is projected separately as static ASCII by
## AsciiVisualStyle. Equipping an item must never replace the actor's identity
## glyph or change its logical cell.

const SPECIES_COMPONENTS := {
	"human":{"choseong":11,"bare":"ㅇ","label":"인간"},
	"goblin":{"choseong":0,"bare":"ㄱ","label":"고블린"},
	"kobold":{"choseong":15,"bare":"ㅋ","label":"코볼트"},
	"dwarf":{"choseong":3,"bare":"ㄷ","label":"드워프"},
	"elf":{"choseong":9,"bare":"ㅅ","label":"엘프"},
	"orc":{"choseong":6,"bare":"ㅁ","label":"오크"},
	"beastkin":{"choseong":7,"bare":"ㅂ","label":"수인"},
	"amphibian":{"choseong":17,"bare":"ㅍ","label":"양서인"},
	"slime":{"choseong":12,"bare":"ㅈ","label":"슬라임"},
}

static func actor_glyph(actor:Dictionary)->Dictionary:
	var species_id:=str(actor.get("species_id","human")).to_lower()
	if species_id.is_empty():species_id="human"
	var species:Dictionary=SPECIES_COMPONENTS.get(species_id,
		{"choseong":18,"bare":"ㅎ","label":"미상"})
	var raw:Variant=actor.get("equipment_visual",actor.get("equipment",{}))
	var equipment:Dictionary=raw if raw is Dictionary else {}
	var weapon_id:=str(equipment.get("weapon_id",
		actor.get("weapon_id","UNARMED_STRIKE"))).to_upper()
	var armor_id:=str(equipment.get("armor_definition_id",
		actor.get("armor_definition_id",""))).to_upper()
	var has_weapon:=not weapon_id.is_empty() and weapon_id not in ["NONE","UNARMED_STRIKE"]
	var has_armor:=not armor_id.is_empty() and armor_id not in ["NONE","UNARMORED"]
	var glyph:=str(species.bare)
	return {
		"glyph":glyph,"species_id":species_id,
		"species_component":str(species.bare),
		"weapon_component":"","armor_component":"",
		"weapon_id":weapon_id,"armor_definition_id":armor_id,
		"weapon_family":"UNARMED",
		"has_weapon":has_weapon,"has_armor":has_armor,
		"is_composed":false,
		"grammar_id":"HANGUL_BODY_ASCII_EQUIPMENT_V1",
	}.duplicate(true)


static func species_bare_glyph(species_id:String)->String:
	var definition:Dictionary=SPECIES_COMPONENTS.get(species_id.to_lower(),{})
	return str(definition.get("bare","ㅎ"))
