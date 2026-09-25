extends RefCounted
## Sets: two or three equipped essences sharing a tag switch a bonus on.
## Role tags come from the species, element tags from a variant or a caster;
## the two are counted apart.
const Essences = preload("res://expedition/progression/essences.gd")
const TEXT := {
	"PACK":{2:"인접 아군당 피해 +1",3:"반응이 터지면 반경 3 아군의 다음 공격 피해 +20%"},
	"BERSERK":{2:"체력 절반 미만이면 공격 지연 −15",3:"처치할 때 HP 5 회복, 액티브 재사용 대기 −1"},
	"AMBUSH":{2:"첫 공격 피해 +30%",3:"피할 때 다음 공격 확정 치명(×1.5)"},
	"GUARD":{2:"방어 +2, 막기 +5",3:"막을 때 공격자에게 반격(무기 피해 절반, 속성 포함)"},
	"ARCHER":{2:"원거리 사거리 +1",3:"원거리 공격 지연 −15, 상태이상 대상에게 원거리 피해 +20%"},
	"CASTER":{2:"최대 MP +5",3:"주문 실패율 −10, 반응 피해 +30%"},
	"fire":{2:"화염 저항 +20, 모든 명중에 화염 피해 +3, 화염 피해 +20%",3:"모든 명중 15% 화상"},
	"ice":{2:"냉기 저항 +20, 모든 명중에 냉기 피해 +3, 냉기 피해 +20%",3:"모든 명중 10% 빙결"},
	"air":{2:"전기 저항 +20, 모든 명중에 전기 피해 +3, 전기 피해 +20%",3:"젖은 대상에게 피해 +30%"},
	"poison":{2:"독 저항 +20, 모든 명중에 독 피해 +3, 독 피해 +20%",3:"모든 명중 15% 중독"},
	"will":{2:"의지 저항 +20, 상태이상 지속 +30%",3:"모든 명중 10% 혼란"},
	"bleed":{2:"출혈 중인 대상에게 피해 +20%",3:"모든 명중 15% 출혈"}}
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

static func step(count: int) -> int:
	return 3 if count >= 3 else 2 if count >= 2 else 0

static func level(actor: Dictionary, tag: String) -> int:
	var reached := step(int(counts(actor).get(tag,0)))
	return 3 if reached == 2 and bool(actor.get("set_boost",false)) else reached

static func active(actor: Dictionary) -> Array:
	var result: Array = []
	var tally := counts(actor)
	for tag in TEXT:
		var reached := step(int(tally.get(tag,0)))
		if reached == 2 and bool(actor.get("set_boost",false)): reached = 3
		if reached == 0: continue
		var lines := PackedStringArray([TEXT[tag][2]])
		if reached == 3: lines.append(TEXT[tag][3])
		result.append({"tag":tag,"name":str(Essences.ROLES.get(tag,Essences.ELEMENTS.get(tag,tag))),"level":reached,"text":" · ".join(lines)})
	return result

## What the sets add to the stat sheet and to the MP pool.
static func stat_bonus(actor: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if level(actor,"GUARD") >= 2: result.ac = 2; result.sh = 5
	if level(actor,"CASTER") >= 2: result.mp = 5
	for element in RESISTED:
		if level(actor,element) >= 2: result["res_"+element] = 20
	return result

static func range_bonus(actor: Dictionary) -> int:
	return 1 if level(actor,"ARCHER") >= 2 else 0

## A foe still at full health: what 기습 calls a first blow.
static func fresh(target: Dictionary) -> bool:
	return int(target.hp) >= int(target.max_hp)

## What a set adds to a blow `attacker` is about to land. Monsters wear no
## essences, so this is a party member's (or a fallen adventurer's) business.
static func outgoing(s, attacker: Dictionary, target: Dictionary, amount: int) -> int:
	if target.is_empty(): return amount
	if level(attacker,"PACK") >= 2: amount += adjacent_allies(s,attacker)
	if level(attacker,"AMBUSH") >= 2 and fresh(target): amount = amount*13/10
	if level(attacker,"bleed") >= 2 and target.get("statuses",{}).has("bleed"): amount = amount*12/10
	if level(attacker,"air") >= 3 and s.Reactions.is_wet(s,target): amount = amount*13/10
	if level(attacker,"ARCHER") >= 3 and ranged(s,attacker) and s.distance(attacker.pos,target.pos) > 1 and statused(target): amount = amount*12/10
	var worn: Dictionary = attacker.get("statuses",{})
	if worn.has("poised"):
		worn.erase("poised"); amount = amount*3/2
		s.message("%s 치명타" % str(attacker.get("name","")))
	if worn.has("rally"):
		worn.erase("rally"); amount = amount*12/10
	return amount

static func adjacent_allies(s, actor: Dictionary) -> int:
	var count := 0
	for other in s.party+s.npcs+s.enemies:
		if int(other.id) != int(actor.id) and int(other.hp) > 0 and s.side_of(other) == s.side_of(actor) and s.melee_reach(actor.pos,other.pos): count += 1
	return count

## Kept for the passive hook: no set lowers damage taken any more.
static func incoming(_s, _target: Dictionary, amount: int) -> int:
	return amount

static func element_damage(source: Dictionary, element: String, amount: int) -> int:
	var key := element.to_lower()
	if not source.is_empty() and key in ["fire","ice","air","poison"] and level(source,key) >= 2: return amount*12/10
	return amount

static func attack_delay(actor: Dictionary, cost: int, ranged: bool) -> int:
	if level(actor,"BERSERK") >= 2 and int(actor.hp)*2 < int(actor.max_hp): cost -= 15
	if ranged and level(actor,"ARCHER") >= 3: cost -= 15
	return maxi(40,cost)

static func status_ticks(caster: Dictionary, status: String, ticks: int) -> int:
	if status in WILL_STATUSES and level(caster,"will") >= 2: return ticks*13/10
	return ticks

## 광폭 3: a kill heals five and takes a round off every cooldown.
static func on_kill(s, killer: Dictionary) -> void:
	if int(killer.get("hp",0)) <= 0 or level(killer,"BERSERK") < 3 or not s.Reactions.once(s,killer,"BERSERK"): return
	killer.hp = mini(int(killer.max_hp),int(killer.hp)+5)
	for id in killer.get("cooldowns",{}): killer.cooldowns[id] = maxi(0,int(killer.cooldowns[id])-1)

static func ranged(s, actor: Dictionary) -> bool:
	return str(s.CombatStats.stats(s,actor).trait) == "ranged"

## A status that counts as one for 사수 3: anything but being wet or a set's own mark.
static func statused(target: Dictionary) -> bool:
	return target.get("statuses",{}).keys().any(func(k): return str(k) not in ["wet","poised","rally"])

## 기습 3: a dodge readies the next blow as a sure critical.
static func on_dodge(s, defender: Dictionary, _attacker: Dictionary) -> void:
	if int(defender.get("hp",0)) <= 0 or level(defender,"AMBUSH") < 3 or not s.Reactions.once(s,defender,"AMBUSH"): return
	defender.statuses["poised"] = int(s.time)+300
	s.message("%s · 기습 태세" % str(defender.get("name","")))

## 수호 3: a block strikes back once, for half the weapon, with the element
## sets' extras riding on it.
static func on_block(s, defender: Dictionary, attacker: Dictionary) -> void:
	if int(defender.get("hp",0)) <= 0 or int(attacker.get("hp",0)) <= 0 or level(defender,"GUARD") < 3: return
	if not s.melee_reach(defender.pos,attacker.pos) or not s.Reactions.once(s,defender,"GUARD"): return
	var amount: int = maxi(1,int(s.CombatStats.stats(s,defender).damage)/2)
	s.message("%s · 반격" % str(defender.get("name","")))
	s.CombatRules.damage(s,defender,attacker,amount,"physical",0,s.Reactions.COUNTER_FORM)
	s.Reactions.extras(s,defender,attacker)

## 무리 3: a reaction this member set off rallies every ally within three.
static func on_reaction(s, source: Dictionary) -> void:
	if int(source.get("hp",0)) <= 0 or level(source,"PACK") < 3 or not s.Reactions.once(s,source,"PACK"): return
	for ally in s.party+s.npcs+s.enemies:
		if int(ally.id) == int(source.id) or int(ally.hp) <= 0 or s.side_of(ally) != s.side_of(source): continue
		if maxi(absi(ally.pos.x-source.pos.x),absi(ally.pos.y-source.pos.y)) <= 3: ally.statuses["rally"] = int(s.time)+300
