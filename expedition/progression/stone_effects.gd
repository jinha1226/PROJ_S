extends RefCounted
const Forms = preload("res://expedition/combat/forms.gd")
## The soul stones' headline effects and the role combos in a fight
## (2026-09-26 spec §2–3, §6). A member has the effect of every stone it
## wears, each once; a monster has its own species' stone's effect; a boss
## has none. The combos are counted in `TagSets`; everything they and the
## effects do to a blow, a kill, a round or a status is here, together with
## the critical hit and the notices a proc raises.
##
## Only primary damage reaches these hooks: the session keeps the secondary
## forms (`Reactions.SECONDARY`: extras, reactions, counters, reflections)
## out, so nothing here calls itself again.
const Essences = preload("res://expedition/progression/essences.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
const EFFECTS := {
	"RAT_GNAW":{"name":"떼 물기","text":"인접 아군 1명당 공격력 +10%"},
	"LIZARD_TAIL":{"name":"꼬리 반격","text":"근접 공격을 받으면 25% 확률로 반격(공격력의 60%)"},
	"KOBOLD_SLING":{"name":"투석","text":"원거리 피해 +25%"},
	"GOBLIN_SHIV":{"name":"기습","text":"체력이 가득한 대상에게 주는 첫 피해 ×2"},
	"GOBLIN_AIM":{"name":"조준","text":"원거리 사거리 +2"},
	"SHIELD_STANCE":{"name":"방패 태세","text":"막기 확률 +20"},
	"HOB_TAUNT":{"name":"거구","text":"최대 HP +20%"},
	"GOBLIN_HEXER":{"name":"저주 연장","text":"내가 거는 상태이상 지속 +50%"},
	"ORC_CLEAVER":{"name":"난폭","text":"공격력 +20%, 받는 피해 +10%"},
	"ORC_THROW":{"name":"연속 투척","text":"원거리 공격이 20% 확률로 한 번 더"},
	"SPIDER_WEB":{"name":"거미줄","text":"공격에 25% 확률로 속박 1라운드"},
	"BEETLE_CURL":{"name":"껍질","text":"받는 피해 −15%"},
	"ORE_SLAM":{"name":"강타","text":"공격에 20% 확률로 기절 1라운드"},
	"FIRE_CALLER":{"name":"불씨","text":"화염 피해 +30%, 공격에 15% 확률로 화상"},
	"STORM_BAT":{"name":"질풍","text":"행동 속도 +20%"},
	"RIVER_RAT_SPLASH":{"name":"물장구","text":"젖은 칸(또는 물)에 서 있으면 모든 피해 +25%"},
	"LEECH_LATCH":{"name":"달라붙기","text":"같은 대상을 연달아 칠 때마다 피해 +15%(최대 +60%)"},
	"TOAD_SPIT":{"name":"독침","text":"공격에 30% 확률로 중독"},
	"SERPENT_SHED":{"name":"탈피","text":"걸리는 상태이상을 50% 확률로 막음"},
	"WATER_WAVE":{"name":"치유의 물결","text":"라운드마다 자신과 인접 아군 HP 3% 회복"},
	"GNOLL_SPEAR":{"name":"분노","text":"체력 절반 이하일 때 공격력 +35%"},
	"FROST_IMP":{"name":"서리","text":"냉기 피해 +30%, 공격에 10% 확률로 빙결 1라운드"},
	"GNOLL_SUMMONER":{"name":"무리 부르기","text":"동시에 부를 수 있는 소환수 +1, 소환수 피해 +50%"},
	"SKELETON_WALL":{"name":"뼈 방벽","text":"인접 아군이 받는 피해 −10%"},
	"SKELETON_VOLLEY":{"name":"급소 사격","text":"치명타 확률 +15%, 치명타 피해 +50%"},
	"GHOUL_CLAW":{"name":"포식","text":"처치하면 최대 HP의 15% 회복"},
	"VAMPIRE_BITE":{"name":"흡혈","text":"준 피해의 15%를 흡혈"},
	"THORN_ARMOUR":{"name":"가시 갑주","text":"받은 근접 피해의 30% 반사"},
	"WRAITH":{"name":"원한","text":"공격에 20% 확률로 약화, 처치하면 반경 2 적 혼란 1라운드"},
	"GRAVEKEEPER":{"name":"무덤 지기","text":"전투마다 한 번, 쓰러질 피해를 받으면 HP 30%로 일어남"}}
## The effects that hang a status on a blow: status, chance, ticks, notice.
const STATUS_PROCS := {
	"SPIDER_WEB":["bind",25,100,"속박!"],
	"ORE_SLAM":["stun",20,100,"기절!"],
	"FIRE_CALLER":["burn",15,300,"화상!"],
	"TOAD_SPIT":["poison",30,300,"중독!"],
	"FROST_IMP":["freeze",10,100,"빙결!"],
	"WRAITH":["weak",20,300,"약화!"]}
## The statuses a hexer lengthens and a serpent sheds (`Statuses.HARMFUL`).
const HARMFUL := ["confuse","slow","freeze","bind","burn","weak","brittle","distort","vulnerable","dominate","bleed","poison","taunted","stun","fracture","exposed"]
## The blows that can be critical: weapon attacks (a landed hit, the old
## slash) and actives. Spells never are, and the secondary forms never get here.
const CRIT_FORMS := ["physical","SLASH","IMPACT","PIERCE"]
const CRIT_BASE := 150
const CRIT_STEP := 50
const SPEED_CAP := 40
const PACK_ATTACK := {2:10,4:20,6:30}
const BERSERK_ATTACK := {2:15,4:30,6:50}
const AMBUSH_CRIT := {2:10,4:20,6:30}
const ARCHER_RANGED := {4:25,6:40}
const CASTER_SPELL := {2:15,4:30,6:50}
const TONES := ["buff","heal","debuff","crit"]
## Tests pin every roll here: -1 rolls for real, anything else is the roll.
static var force := -1
static var by_species: Dictionary = {}

## The headline effect a stone carries: its base row's, none for a boss stone.
static func effect_of(id: String) -> String:
	if not Essences.has(id): return ""
	return str(Essences.content.rows[Essences.base_of(id)].get("effect",""))

static func species_effect(species_id: String) -> String:
	if species_id.is_empty(): return ""
	if by_species.is_empty():
		for id in Essences.content.rows: by_species[str(Essences.content.rows[id].get("species",""))] = str(id)
	return effect_of(str(by_species.get(species_id,"")))

## Every effect `actor` has, each once, in slot order.
static func effects(actor: Dictionary) -> Array:
	var result: Array = []
	if actor.is_empty(): return result
	if bool(actor.get("enemy",false)):
		if bool(actor.get("boss",false)): return result
		var own := effect_of(str(actor.get("part_id","")))
		if own.is_empty(): own = species_effect(str(actor.get("species_id","")))
		if not own.is_empty(): result.append(own)
		return result
	for id in Essences.equipped(actor):
		var effect := effect_of(str(id))
		if not effect.is_empty() and effect not in result: result.append(effect)
	return result

static func has(actor: Dictionary, effect: String) -> bool:
	return effect in effects(actor)

static func alive(actor: Dictionary) -> bool:
	return not actor.is_empty() and int(actor.get("hp",0)) > 0

static func under_half(actor: Dictionary) -> bool:
	return int(actor.hp)*2 <= int(actor.max_hp)

static func fresh(target: Dictionary) -> bool:
	return int(target.hp) >= int(target.max_hp)

## A roll out of a hundred, below `percent` to fire.
static func chance(s, source: Dictionary, target: Dictionary, lane: String, percent: int) -> bool:
	if percent <= 0: return false
	var rolled: int = force if force >= 0 else int(s.CombatRules.roll(s,source,target,"stone_"+lane,100))
	return rolled < percent

## A proc's notice over `cell`: drawn by the board like a reaction's name,
## smaller and in its tone's colour, never logged.
static func proc(s, cell: Vector2i, text: String, tone: String) -> void:
	s.effects.append({"kind":"PROC","from":cell,"cell":cell,"text":text,"tone":tone if tone in TONES else "buff"})
	if s.presentation == null and s.effects.size() > 32: s.effects.pop_front()

static func heal(s, actor: Dictionary, amount: int) -> int:
	if not alive(actor) or amount <= 0: return 0
	var before: int = int(actor.hp)
	actor.hp = mini(int(actor.max_hp),before+amount)
	var gained: int = int(actor.hp)-before
	if gained > 0:
		s.Body.heal(actor)
		proc(s,actor.pos,"+%d" % gained,"heal")
	return gained

## The members of `actor`'s side: the party and whoever stands with it.
static func side(s, actor: Dictionary) -> Array:
	return (s.party+s.npcs).filter(func(o): return alive(o) and not bool(o.get("enemy",false)) and s.side_of(o) == s.side_of(actor))

static func allies_beside(s, actor: Dictionary) -> Array:
	return (s.party+s.npcs+s.enemies).filter(func(o): return alive(o) and int(o.id) != int(actor.id) and s.side_of(o) == s.side_of(actor) and s.melee_reach(actor.pos,o.pos))

## 무리: the party takes the best bracket any of its members wears.
static func pack_bracket(s, actor: Dictionary) -> int:
	if bool(actor.get("enemy",false)): return 0
	var best := TagSets.bracket(actor,"PACK")
	if s == null: return best
	for member in side(s,actor): best = maxi(best,TagSets.bracket(member,"PACK"))
	return best

# ── numbers ────────────────────────────────────────────────────────────────

## What the effects add to the stat sheet.
static func stat_bonus(actor: Dictionary) -> Dictionary:
	return {"sh":20} if has(actor,"SHIELD_STANCE") else {}

## Max HP in percent: 홉고블린's, and 무리 4's for the whole party.
static func hp_percent(s, actor: Dictionary) -> int:
	var percent := 20 if has(actor,"HOB_TAUNT") else 0
	if pack_bracket(s,actor) == 4: percent += 20
	return percent

static func range_bonus(actor: Dictionary) -> int:
	return 2 if has(actor,"GOBLIN_AIM") else 0

## 행동 속도 in percent: the stones' own, 폭풍 박쥐's, 광폭 4 when wounded.
static func speed(s, actor: Dictionary) -> int:
	var total := 0
	if not bool(actor.get("enemy",false)): total += int(s.StatSheet.value(s,actor,"speed"))
	if has(actor,"STORM_BAT"): total += 20
	if TagSets.bracket(actor,"BERSERK") == 4 and under_half(actor): total += 20
	return clampi(total,0,SPEED_CAP)

static func delay(s, actor: Dictionary, cost: int, kind: String = "ATTACK") -> int:
	var cut := speed(s,actor)
	var result: int = cost if cut <= 0 else cost*(100-cut)/100
	if kind in ["MOVE","SWAP"] or Forms.attack_action(s,kind): result = Forms.fracture_delay(actor,result)
	return result

static func crit_chance(_s, attacker: Dictionary, target: Dictionary) -> int:
	var total := 15 if has(attacker,"SKELETON_VOLLEY") else 0
	var ambush := TagSets.bracket(attacker,"AMBUSH")
	total += int(AMBUSH_CRIT.get(ambush,0))
	if ambush == 6 and not target.is_empty() and fresh(target): total = 100
	if not target.is_empty() and target.get("statuses",{}).has("exposed"): total += 25
	return mini(100,total)

## A critical's damage in percent: ×1.5, fifty more from each of 해골 궁수 and 기습 4·6.
static func crit_percent(attacker: Dictionary) -> int:
	var total := CRIT_BASE
	if has(attacker,"SKELETON_VOLLEY"): total += CRIT_STEP
	if TagSets.bracket(attacker,"AMBUSH") >= 4: total += CRIT_STEP
	return total

static func spell_percent(_s, caster: Dictionary) -> int:
	return int(CASTER_SPELL.get(TagSets.bracket(caster,"CASTER"),0))

## 술사 6: no spell fails.
static func sure_casting(caster: Dictionary) -> bool:
	return TagSets.bracket(caster,"CASTER") == 6

static func summon_extra(caster: Dictionary) -> int:
	return 1 if has(caster,"GNOLL_SUMMONER") else 0

static func status_ticks(caster: Dictionary, status: String, ticks: int) -> int:
	if status in HARMFUL and has(caster,"GOBLIN_HEXER"): return ticks*3/2
	return ticks

# ── hooks ──────────────────────────────────────────────────────────────────

static func casting(s) -> bool:
	return int(s.casting) > 0

static func ranged(s, attacker: Dictionary, target: Dictionary) -> bool:
	return attacker.has("pos") and target.has("pos") and s.distance(attacker.pos,target.pos) > 1

## A primary blow `attacker` is about to land on `target`.
static func outgoing(s, attacker: Dictionary, target: Dictionary, amount: int, form: String = "HIT") -> int:
	if attacker.is_empty() or target.is_empty() or amount <= 0: return amount
	var spell := casting(s)
	var far := ranged(s,attacker,target)
	var element: String = s.Reactions.element_of(form)
	var percent := 0
	if not spell:
		if has(attacker,"RAT_GNAW"): percent += 10*allies_beside(s,attacker).size()
		if has(attacker,"ORC_CLEAVER"): percent += 20
		if far and has(attacker,"KOBOLD_SLING"): percent += 25
		if has(attacker,"GNOLL_SPEAR"):
			if under_half(attacker):
				percent += 35
				if not bool(attacker.get("raging",false)): attacker.raging = true; proc(s,attacker.pos,"분노!","buff")
			else: attacker.raging = false
		percent += int(PACK_ATTACK.get(pack_bracket(s,attacker),0))
		percent += int(BERSERK_ATTACK.get(TagSets.bracket(attacker,"BERSERK"),0))
		if far: percent += int(ARCHER_RANGED.get(TagSets.bracket(attacker,"ARCHER"),0))
	if element == "fire" and has(attacker,"FIRE_CALLER"): percent += 30
	if element == "ice" and has(attacker,"FROST_IMP"): percent += 30
	if has(attacker,"RIVER_RAT_SPLASH") and s.Reactions.is_wet(s,attacker): percent += 25
	if bool(attacker.get("summoned",false)) and has(s.actor_by_id(int(attacker.get("summoner",-1))),"GNOLL_SUMMONER"): percent += 50
	percent += latch(s,attacker,target)
	amount = amount*(100+percent)/100
	if has(attacker,"GOBLIN_SHIV") and fresh(target):
		amount *= 2; proc(s,target.pos,"기습!","buff")
	if not spell and form in CRIT_FORMS:
		var exposed: bool = target.get("statuses",{}).has("exposed")
		if chance(s,attacker,target,"crit",crit_chance(s,attacker,target)):
			amount = amount*crit_percent(attacker)/100
			proc(s,target.pos,"치명타!","crit")
			s.message("%s 치명타" % str(attacker.get("name","")))
		if exposed: target.statuses.erase("exposed")
	return amount

## 거머리: fifteen percent more for every blow in a row on the same target.
static func latch(s, attacker: Dictionary, target: Dictionary) -> int:
	if not has(attacker,"LEECH_LATCH"): return 0
	var held: Dictionary = attacker.get("latch",{})
	var stacks := 0
	if int(held.get("target",-1)) == int(target.id):
		stacks = mini(4,int(held.get("stacks",0))+1)
		if stacks > int(held.get("stacks",0)): proc(s,target.pos,"+15%","buff")
	attacker.latch = {"target":int(target.id),"stacks":stacks}
	return 15*stacks

## A primary blow `target` is about to take.
static func incoming(s, target: Dictionary, amount: int) -> int:
	if target.is_empty() or amount <= 0: return amount
	var percent := 0
	if has(target,"ORC_CLEAVER"): percent += 10
	if has(target,"BEETLE_CURL"): percent -= 15
	if target.has("pos"):
		var neighbours: Array = allies_beside(s,target)
		if neighbours.any(func(o): return has(o,"SKELETON_WALL")): percent -= 10
		if neighbours.any(func(o): return TagSets.bracket(o,"GUARD") == 6): percent -= 15
	return maxi(1,amount*(100+percent)/100)

## The statuses a landed primary blow may hang, rolled after the blow's own
## reactions (`CombatRules.damage` calls this). Spells hang none.
static func procs(s, attacker: Dictionary, target: Dictionary, lost: int) -> void:
	if lost <= 0 or casting(s) or not alive(attacker) or not alive(target): return
	for effect in STATUS_PROCS:
		if not alive(target) or not has(attacker,effect): continue
		var row: Array = STATUS_PROCS[effect]
		if not chance(s,attacker,target,effect,int(row[1])): continue
		s.Statuses.apply(s,target,str(row[0]),status_ticks(attacker,str(row[0]),int(row[2])),attacker)
		if target.get("statuses",{}).has(str(row[0])): proc(s,target.pos,str(row[3]),"debuff")

## After a primary blow landed: the attacker's lifesteal and second shot,
## then the target's counter and reflection.
static func after_hit(s, target: Dictionary, attacker: Dictionary, form: String, lost: int) -> void:
	if not alive(attacker) or target.is_empty(): return
	var spell := casting(s)
	if lost > 0 and has(attacker,"VAMPIRE_BITE"): heal(s,attacker,lost*15/100)
	if not spell and form == "physical" and alive(target) and ranged(s,attacker,target): second_shot(s,attacker,target)
	if spell or not alive(target) or not attacker.has("pos") or not target.has("pos") or not s.melee_reach(target.pos,attacker.pos): return
	if has(target,"LIZARD_TAIL") and chance(s,target,attacker,"counter",25) and s.Reactions.once(s,target,"COUNTER"):
		var amount: int = maxi(1,int(s.CombatStats.stats(s,target).damage)*60/100)
		proc(s,target.pos,"반격!","buff")
		s.message("%s 반격" % str(target.get("name","")))
		s.CombatRules.damage(s,target,attacker,amount,"physical",0,s.Reactions.COUNTER_FORM)
	if lost > 0 and alive(attacker) and has(target,"THORN_ARMOUR"):
		proc(s,target.pos,"반사!","buff")
		s.damage(attacker,maxi(1,lost*30/100),int(target.id),"RETALIATE")

## 오크 투척병 and 사수 6: one more ranged attack, once an action.
static func second_shot(s, attacker: Dictionary, target: Dictionary) -> void:
	var odds := 0
	if has(attacker,"ORC_THROW"): odds = 20
	if TagSets.bracket(attacker,"ARCHER") == 6: odds = 100-(100-odds)*75/100
	if not chance(s,attacker,target,"double",odds) or not s.Reactions.once(s,attacker,"DOUBLE"): return
	proc(s,attacker.pos,"연사!","buff")
	s.CombatRules.attack(s,attacker,target)

## A felling blow on a 묘지기 stone: once a fight it rises at thirty percent.
static func lethal(s, target: Dictionary, amount: int) -> int:
	if amount < int(target.get("hp",0)) or bool(target.get("revived",false)) or not has(target,"GRAVEKEEPER"): return amount
	if not s.Reactions.once(s,target,"REVIVE"): return amount
	target.revived = true
	target.hp = maxi(1,int(target.max_hp)*30/100)
	proc(s,target.pos,"부활!","heal")
	return 0

static func on_kill(s, killer: Dictionary, victim: Dictionary) -> void:
	if not alive(killer): return
	if has(killer,"GHOUL_CLAW"): heal(s,killer,int(killer.max_hp)*15/100)
	if TagSets.bracket(killer,"BERSERK") == 6: heal(s,killer,int(killer.max_hp)*10/100)
	if pack_bracket(s,killer) == 6:
		for member in side(s,killer): heal(s,member,int(member.max_hp)*5/100)
	if has(killer,"WRAITH") and victim.has("pos"):
		for other in s.party+s.npcs+s.enemies:
			if not alive(other) or s.side_of(other) == s.side_of(killer): continue
			if maxi(absi(other.pos.x-victim.pos.x),absi(other.pos.y-victim.pos.y)) > 2: continue
			s.Statuses.apply(s,other,"confuse",100,killer)
			if other.get("statuses",{}).has("confuse"): proc(s,other.pos,"혼란!","debuff")

static func round_start(s, actor: Dictionary) -> void:
	if not alive(actor): return
	if has(actor,"WATER_WAVE"):
		for member in [actor]+allies_beside(s,actor): heal(s,member,maxi(1,int(member.max_hp)*3/100))
	if TagSets.bracket(actor,"CASTER") == 4 and actor.has("max_mp"): actor.mp = mini(int(actor.max_mp),int(actor.get("mp",0))+2)

## 신전 뱀: half the harmful statuses that would land slide off.
static func shed(s, victim: Dictionary, status: String, source: Dictionary) -> bool:
	if status not in HARMFUL or not has(victim,"SERPENT_SHED"): return false
	if not chance(s,source,victim,"shed",50): return false
	if victim.has("pos"): proc(s,victim.pos,"면역!","buff")
	return true

## A fight begins: the once-a-fight rising and the running tallies are fresh.
static func battle_start(s) -> void:
	for actor in s.party+s.npcs+s.enemies:
		actor.revived = false; actor.raging = false; actor.erase("latch")
