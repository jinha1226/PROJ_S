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

static func range_bonus(actor: Dictionary) -> int:
	return 1 if level(actor,"ARCHER") >= 2 else 0

const ELEMENT_STATUS := {"fire":"burn","ice":"slow","poison":"poison","will":"confuse"}

## A foe still at full health: what 기습 calls a first blow.
static func fresh(target: Dictionary) -> bool:
	return int(target.hp) >= int(target.max_hp)

static func outgoing(s, attacker: Dictionary, target: Dictionary, amount: int) -> int:
	if bool(attacker.get("enemy",false)) or target.is_empty(): return amount
	var pack := level(attacker,"PACK")
	if pack > 0: amount += (1 if pack == 2 else 2)*int(s.Passives.adjacent_allies(s,attacker))
	if level(attacker,"AMBUSH") >= 2 and fresh(target): amount = amount*13/10
	if level(attacker,"air") >= 3:
		var ground: Dictionary = s.tile(target.pos)
		if ground.terrain == "water" or int(ground.wet) > 0: amount = amount*13/10
	return amount

static func incoming(_s, target: Dictionary, amount: int) -> int:
	if level(target,"PACK") >= 3: return maxi(1,amount-1)
	return amount

static func sure_hit(attacker: Dictionary, target: Dictionary) -> bool:
	return not bool(attacker.get("enemy",false)) and level(attacker,"AMBUSH") >= 3 and fresh(target)

static func element_damage(source: Dictionary, element: String, amount: int) -> int:
	var key := element.to_lower()
	if not source.is_empty() and key in ["fire","ice","air","poison"] and level(source,key) >= 2: return amount*12/10
	return amount

## Element step three: a landed blow may hang the element's own status.
static func on_hit(s, attacker: Dictionary, target: Dictionary) -> void:
	if bool(attacker.get("enemy",false)) or int(target.hp) <= 0: return
	for element in ELEMENT_STATUS:
		if level(attacker,element) < 3: continue
		var chance := 10 if element == "will" else 15
		if s.CombatRules.roll(s,attacker,target,"set_"+element,100) < chance:
			s.Statuses.apply(s,target,ELEMENT_STATUS[element],200 if element == "will" else 300)

static func attack_delay(actor: Dictionary, cost: int, ranged: bool) -> int:
	if level(actor,"BERSERK") >= 2 and int(actor.hp)*2 < int(actor.max_hp): cost -= 15
	if ranged and level(actor,"ARCHER") >= 3: cost -= 15
	return maxi(40,cost)

static func on_kill(_s, killer: Dictionary) -> void:
	if bool(killer.get("enemy",false)) or int(killer.hp) <= 0 or level(killer,"BERSERK") < 3: return
	killer.hp = mini(int(killer.max_hp),int(killer.hp)+5)

static func status_ticks(caster: Dictionary, status: String, ticks: int) -> int:
	if status in WILL_STATUSES and level(caster,"will") >= 2: return ticks*13/10
	return ticks

## 수호 3 on an adjacent friend lends this actor two armour; it never stacks.
static func ally_guard(s, actor: Dictionary) -> int:
	if s == null or bool(actor.get("enemy",false)) or not actor.has("pos"): return 0
	for other in s.party+s.npcs:
		if int(other.id) == int(actor.id) or int(other.hp) <= 0 or s.side_of(other) != s.side_of(actor): continue
		if s.melee_reach(actor.pos,other.pos) and level(other,"GUARD") >= 3: return 2
	return 0
