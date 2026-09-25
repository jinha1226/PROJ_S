extends RefCounted
## Sets: two or three equipped essences sharing a tag switch a bonus on.
## Role tags come from the species, element tags from a variant or a caster;
## the two are counted apart.
const Essences = preload("res://expedition/progression/essences.gd")
const TEXT := {
	"PACK":{2:"인접 아군당 피해 +1",3:"인접 아군당 피해 +2, 받는 피해 −1"},
	"BERSERK":{2:"체력 절반 미만이면 공격 지연 −15",3:"처치하면 HP 5 회복"},
	"AMBUSH":{2:"첫 공격 피해 +30%",3:"회피 +5, 첫 공격이 확정 명중"},
	"GUARD":{2:"방어 +2, 막기 +5",3:"인접 아군 방어 +2"},
	"ARCHER":{2:"원거리 사거리 +1",3:"원거리 공격 지연 −15"},
	"CASTER":{2:"최대 MP +5",3:"주문 실패율 −10"},
	"fire":{2:"화염 저항 +20, 화염 피해 +20%",3:"공격이 15% 확률로 화상"},
	"ice":{2:"냉기 저항 +20, 냉기 피해 +20%",3:"공격이 15% 확률로 둔화"},
	"air":{2:"전기 저항 +20, 전기 피해 +20%",3:"젖은 칸의 적에게 피해 +30%"},
	"poison":{2:"독 저항 +20, 독 피해 +20%",3:"공격이 15% 확률로 중독"},
	"will":{2:"의지 저항 +20, 상태이상 지속 +30%",3:"공격이 10% 확률로 혼란"}}
## The statuses a will resists and a will set lengthens: the hex school's.
const WILL_STATUSES := ["confuse","slow","bind","weak","brittle","distort","vulnerable","dominate"]

static func counts(actor: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id in Essences.equipped(actor):
		for tag in [Essences.role(id),Essences.element(id)]:
			if not str(tag).is_empty(): result[tag] = int(result.get(tag,0))+1
	return result

static func step(count: int) -> int:
	return 3 if count >= 3 else 2 if count >= 2 else 0

static func level(actor: Dictionary, tag: String) -> int:
	return step(int(counts(actor).get(tag,0)))

static func active(actor: Dictionary) -> Array:
	var result: Array = []
	var tally := counts(actor)
	for tag in TEXT:
		var reached := step(int(tally.get(tag,0)))
		if reached == 0: continue
		var lines := PackedStringArray([TEXT[tag][2]])
		if reached == 3: lines.append(TEXT[tag][3])
		result.append({"tag":tag,"name":str(Essences.ROLES.get(tag,Essences.ELEMENTS.get(tag,tag))),"level":reached,"text":" · ".join(lines)})
	return result

## What the sets add to the stat sheet and to the MP pool.
static func stat_bonus(actor: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if level(actor,"GUARD") >= 2: result.ac = 2; result.sh = 5
	if level(actor,"AMBUSH") >= 3: result.ev = 5
	if level(actor,"CASTER") >= 2: result.mp = 5
	for element in Essences.ELEMENTS:
		if level(actor,element) >= 2: result["res_"+element] = 20
	return result
