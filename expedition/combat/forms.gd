extends RefCounted
## Damage forms (2026-09-26 damage forms spec §4): slash, impact and pierce.
## A blow's form scales it by the target's skin or bone step, may leave a
## wound, and the killing blow's form picks which body part a stone comes from.
## While a blow resolves its form sits in `s.blow_form` (`begin`/`end`), so
## every damage path below it reads the same form.
const SLASH := "SLASH"
const IMPACT := "IMPACT"
const PIERCE := "PIERCE"
const FORMS := [SLASH, IMPACT, PIERCE]
## Body parts in form order: cut by a slash, broken by impact, pierced.
const PARTS := ["cut","broken","pierced"]
const NAMES := {SLASH:"베기", IMPACT:"타격", PIERCE:"찌르기"}
const SKIN_NAMES := {-1:"무름", 0:"보통", 1:"질김"}
const BONE_NAMES := {-1:"약함", 0:"보통", 1:"단단함"}
const STEP_PERCENT := 25
const WOUND_BASE := 20
const WOUND_STEP := 10
const FRACTURE_PERCENT := 25
const SPELL_FORMS := {"bolt":PIERCE, "line":PIERCE, "burst":IMPACT, "cone":IMPACT, "wall":IMPACT}
const WOUNDS := {SLASH:["bleed",300,"출혈!"], IMPACT:["fracture",300,"골절!"], PIERCE:["exposed",200,"급소!"]}
const DOT_FORMS := {"bleed":SLASH, "poison":PIERCE, "burn":IMPACT}
## Tests pin the wound roll here: -1 rolls for real, anything else is the roll.
static var force := -1
static var combat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/combat.json"))
static var monsters: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/floor_monsters.json"))

static func species_rows() -> Array:
	return monsters.get("species",[])

static func species_row(species_id: String) -> Dictionary:
	if species_id.is_empty(): return {}
	for row in species_rows():
		if str(row.species_id) == species_id: return row
	return {}

## A form that is one of the three, or IMPACT for anything else.
static func known(form: String) -> String:
	return form if form in FORMS else IMPACT

## The form of `actor`'s basic attack: a summon's row, a monster's species,
## a member's weapon (bare hands slam).
static func of_actor(actor: Dictionary) -> String:
	if bool(actor.get("summoned",false)):
		return known(str(combat.get("summons",{}).get(str(actor.get("summon_kind","")),{}).get("form","")))
	if bool(actor.get("enemy",false)):
		return known(str(species_row(str(actor.get("species_id",""))).get("form","")))
	var weapon: String = str(actor.get("gear",{}).get("weapon",{}).get("type",""))
	return known(str(combat.get("weapons",{}).get(weapon,{}).get("form","")))

## A part's own form, else its species', else impact.
static func of_part(def: Dictionary) -> String:
	if str(def.get("form","")) in FORMS: return str(def.form)
	return known(str(species_row(str(def.get("species",""))).get("form","")))

## A spell's form counts only for which part drops: no scaling, no wound.
static func of_spell(spell: Dictionary) -> String:
	return str(SPELL_FORMS.get(str(spell.get("shape","")),""))

static func of_dot(status: String) -> String:
	return str(DOT_FORMS.get(status,""))

## Skin and bone steps: -1, 0 or 1. Only a monster with a species row has any.
static func skin(actor: Dictionary) -> int:
	if not bool(actor.get("enemy",false)) or bool(actor.get("summoned",false)): return 0
	return clampi(int(species_row(str(actor.get("species_id",""))).get("skin",0)),-1,1)

static func bone(actor: Dictionary) -> int:
	if not bool(actor.get("enemy",false)) or bool(actor.get("summoned",false)): return 0
	return clampi(int(species_row(str(actor.get("species_id",""))).get("bone",0)),-1,1)

## The step a form answers to: skin for a slash, bone for impact, none for pierce.
static func step(form: String, target: Dictionary) -> int:
	match form:
		SLASH: return skin(target)
		IMPACT: return bone(target)
	return 0

## A quarter less against the tough step, a quarter more against the weak one.
static func scale(raw: int, form: String, target: Dictionary) -> int:
	if raw <= 0 or form not in FORMS: return raw
	return maxi(1,raw*(100-STEP_PERCENT*step(form,target))/100)

static func armour(ac: int, form: String) -> int:
	return ac/2 if form == IMPACT else ac

## Hangs `form` on the blow now resolving; returns what was there before.
static func begin(s, form: String) -> String:
	var previous: String = str(s.blow_form)
	s.blow_form = form
	return previous

static func end(s, previous: String) -> void:
	s.blow_form = previous

## The form written on whoever a hit lands on: none for secondary damage,
## the blow's form while one resolves, else the damage's own form word.
static func kill_form(s, form: String, secondary: Array) -> String:
	if form in secondary: return ""
	if str(s.blow_form) in FORMS: return str(s.blow_form)
	return form if form in FORMS else ""

static func wound_chance(form: String, target: Dictionary) -> int:
	if form not in FORMS: return 0
	return WOUND_BASE-WOUND_STEP*step(form,target)

## How much slower a fractured actor acts, in percent; a boss half as much.
static func fracture_percent(actor: Dictionary) -> int:
	return FRACTURE_PERCENT/2 if bool(actor.get("boss",false)) else FRACTURE_PERCENT

static func fracture_delay(actor: Dictionary, cost: int) -> int:
	return cost*(100+fracture_percent(actor))/100 if actor.get("statuses",{}).has("fracture") else cost

static func attack_action(s, kind: String) -> bool:
	if kind == "ATTACK": return true
	if not s.Abilities.has(kind): return false
	var def: Dictionary = s.Abilities.definition(kind)
	return str(def.get("effect","")) in ["DAMAGE","LUNGE","PUSH"] and str(def.get("element","")) in ["","bleed"]

## Which of the three parts a roll of 0..99 gives: the killing form's own part
## half the time, the next two a quarter each; no form spreads it evenly.
static func pick_part(form: String, roll: int) -> String:
	var own := FORMS.find(form)
	if own < 0: return PARTS[0] if roll < 34 else PARTS[1] if roll < 67 else PARTS[2]
	if roll < 50: return PARTS[own]
	if roll < 75: return PARTS[(own+1)%3]
	return PARTS[(own+2)%3]

static func form_name(form: String) -> String:
	return str(NAMES.get(form,""))

## "공격 베기 · 피부 질김 · 뼈 단단함" for the enemy info card.
static func body_line(actor: Dictionary) -> String:
	return "공격 %s · 피부 %s · 뼈 %s" % [form_name(of_actor(actor)),SKIN_NAMES[skin(actor)],BONE_NAMES[bone(actor)]]

## A landed primary blow's wound: only while a blow's form is set, never from a
## spell or a sourceless tick. Returns the status it hung, or "".
static func wound(s, source: Dictionary, target: Dictionary, lost: int) -> String:
	var form: String = str(s.blow_form)
	if lost <= 0 or source.is_empty() or form not in FORMS or int(s.casting) > 0: return ""
	if target.is_empty() or int(target.get("hp",0)) <= 0: return ""
	var odds := clampi(wound_chance(form,target)+s.StoneEffects.modifier(s,"wound_chance",source,{"target":target,"form":form})+s.StoneEffects.modifier(s,"wound_chance."+form,source,{"target":target,"form":form}),0,100)
	var rolled: int = force if force >= 0 else int(s.CombatRules.roll(s,source,target,"wound",100))
	if rolled >= odds: return ""
	var row: Array = WOUNDS[form]
	var already: bool = target.get("statuses",{}).has(str(row[0]))
	if not s.Statuses.apply(s,target,str(row[0]),s.StoneEffects.status_ticks(source,str(row[0]),int(row[1]),s),source): return ""
	if not target.get("statuses",{}).has(str(row[0])): return ""
	s.StoneEffects.proc(s,target.pos,str(row[2]),"debuff")
	s.StoneEffects.fire(s,"WOUND",{"source":source,"target":target,"victim":target,"status":str(row[0]),"form":form,"status_already":already})
	return str(row[0])

## "장검 · 베기": a weapon's name with its form, the bare name when it has none.
static func weapon_label(name: String, weapon_id: String) -> String:
	var form: String = str(combat.get("weapons",{}).get(weapon_id,{}).get("form",""))
	return name if form not in FORMS else "%s · %s" % [name,form_name(form)]
