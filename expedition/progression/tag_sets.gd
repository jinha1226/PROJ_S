extends RefCounted
## Sets: equipped essences sharing a tag switch a bonus on. Role tags come
## from the species and make the role combos (2·4·6 stones, the highest
## bracket reached only); element tags come from a variant or a caster and
## make the element sets (2·3). The two are counted apart. What a role combo
## does in a fight lives in `StoneEffects`; this file counts and words it.
const Essences = preload("res://expedition/progression/essences.gd")
const ROLE_TEXT := {
	"TANK":{2:"방어 +2",4:"방어 +5, 막기 +10",6:"방어 +6, 막기 +12, 인접 아군 받는 피해 −10%"},
	"MELEE":{2:"공격력 +12%",4:"공격력 +25%, 치명타 +8%",6:"공격력 +30%, 치명타 +10%, 처치하면 HP 5% 회복"},
	"RANGED":{2:"원거리 사거리 +1",4:"원거리 피해 +20%",6:"원거리 피해 +25%, 15% 확률로 한 번 더"},
	"MAGIC":{2:"주문력 +12%",4:"주문력 +25%, 라운드마다 MP +2",6:"주문력 +30%, 주문 실패 없음"},
	"SUPPORT":{2:"주는 회복·보호 +20%",4:"주는 회복·보호 +30%, 파티 공격력 +8%",6:"주는 회복·보호 +40%, 파티 공격력 +10%, 인접 동료 25% 정화"}}
const TEXT := {
	"fire":{2:"화염 저항 +20, 모든 명중에 화염 피해 +3, 화염 피해 +20%",3:"모든 명중 15% 화상"},
	"ice":{2:"냉기 저항 +20, 모든 명중에 냉기 피해 +3, 냉기 피해 +20%",3:"모든 명중 10% 빙결"},
	"air":{2:"전기 저항 +20, 모든 명중에 전기 피해 +3, 전기 피해 +20%",3:"젖은 대상에게 피해 +30%"},
	"poison":{2:"독 저항 +20, 모든 명중에 독 피해 +3, 독 피해 +20%",3:"모든 명중 15% 중독"},
	"will":{2:"의지 저항 +20, 상태이상 지속 +30%",3:"모든 명중 10% 혼란"},
	"bleed":{2:"출혈 중인 대상에게 피해 +20%",3:"모든 명중 15% 출혈"}}
const BRACKETS := [2,4,6]
const TANK_ARMOUR := {2:2,4:5,6:6}
const TANK_BLOCK := {2:0,4:10,6:12}
## The elements a set lends resistance to: every one but bleeding.
const RESISTED := ["fire","ice","air","poison","will"]
## The statuses a will resists and a will set lengthens: the hex school's.
const WILL_STATUSES := ["confuse","slow","bind","weak","brittle","distort","vulnerable","dominate"]

static func counts(actor: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id in Essences.equipped(actor):
		for tag in [Essences.role(id),Essences.element(id)]:
			if not str(tag).is_empty(): result[tag] = int(result.get(tag,0))+1
	return result

static func count(actor: Dictionary, tag: String) -> int:
	return int(counts(actor).get(tag,0))

## The role bracket `stones` reach: 2, 4 or 6, or nothing under two.
static func bracket_of(stones: int) -> int:
	return 6 if stones >= 6 else 4 if stones >= 4 else 2 if stones >= 2 else 0

## A role combo's bracket on `actor`; the final boss's `set_boost` lifts a
## reached bracket one step (2→4, 4→6).
static func bracket(actor: Dictionary, role: String) -> int:
	var reached := bracket_of(count(actor,role))
	if reached > 0 and reached < 6 and bool(actor.get("set_boost",false)): reached += 2
	return reached

## The element sets' step: two or three stones. `set_boost` lifts a two to three.
static func step(stones: int) -> int:
	return 3 if stones >= 3 else 2 if stones >= 2 else 0

## A role tag reads its combo bracket, an element tag its set step.
static func level(actor: Dictionary, tag: String) -> int:
	if ROLE_TEXT.has(tag): return bracket(actor,tag)
	var reached := step(count(actor,tag))
	return 3 if reached == 2 and bool(actor.get("set_boost",false)) else reached

## The rows the soul stone screen lists: every role worn, with its count, the
## next bracket (0 at the top) and the words of the bracket on; then the
## element sets that are on.
static func active(actor: Dictionary) -> Array:
	var result: Array = []
	var tally := counts(actor)
	for role in ROLE_TEXT:
		var stones: int = int(tally.get(role,0))
		if stones <= 0: continue
		var on := bracket(actor,role)
		var next := 0
		for edge in BRACKETS:
			if edge > on and edge > stones: next = edge; break
		result.append({"tag":role,"name":str(Essences.ROLES.get(role,role)),"level":on,"count":stones,"next":next,"text":str(ROLE_TEXT[role].get(on,""))})
	for tag in TEXT:
		var reached := level(actor,tag)
		if reached == 0: continue
		var lines := PackedStringArray([TEXT[tag][2]])
		if reached == 3: lines.append(TEXT[tag][3])
		result.append({"tag":tag,"name":str(Essences.ELEMENTS.get(tag,tag)),"level":reached,"count":int(tally.get(tag,0)),"next":3 if reached < 3 else 0,"text":" · ".join(lines)})
	return result

## What the sets add to the stat sheet: 수호's armour and block, the element
## sets' resistance.
static func stat_bonus(actor: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var guard := bracket(actor,"TANK")
	if guard > 0:
		result.ac = int(TANK_ARMOUR[guard])
		if int(TANK_BLOCK[guard]) > 0: result.sh = int(TANK_BLOCK[guard])
	for element in RESISTED:
		if level(actor,element) >= 2: result["res_"+element] = 20
	return result

## 사수 2: a bow reaches one farther (the four and six brackets hit harder instead).
static func range_bonus(actor: Dictionary) -> int:
	return 1 if bracket(actor,"RANGED") == 2 else 0

## What an element set adds to a blow `attacker` is about to land.
static func outgoing(s, attacker: Dictionary, target: Dictionary, amount: int) -> int:
	if target.is_empty(): return amount
	if level(attacker,"bleed") >= 2 and target.get("statuses",{}).has("bleed"): amount = amount*12/10
	if level(attacker,"air") >= 3 and s.Reactions.is_wet(s,target): amount = amount*13/10
	return amount

## Kept for the passive hook: no set lowers damage taken any more.
static func incoming(_s, _target: Dictionary, amount: int) -> int:
	return amount

static func element_damage(source: Dictionary, element: String, amount: int) -> int:
	var key := element.to_lower()
	if not source.is_empty() and key in ["fire","ice","air","poison"] and level(source,key) >= 2: return amount*12/10
	return amount

static func status_ticks(caster: Dictionary, status: String, ticks: int) -> int:
	if status in WILL_STATUSES and level(caster,"will") >= 2: return ticks*13/10
	return ticks
