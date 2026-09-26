extends RefCounted
const EffectEngine = preload("res://expedition/progression/effect_engine.gd")
const Stacks = preload("res://expedition/progression/stacks.gd")
const Forms = preload("res://expedition/combat/forms.gd")
const Vfx = preload("res://expedition/ui/effect_vfx.gd")
## The soul stones' headline effects and the role combos in a fight
## (2026-09-26 spec §2–3, §6). A member has the effect of every stone it
## wears, each once; a monster has its own species' stone's effect; a boss
## has none. The combos are counted in `TagSets`; everything they and the
## effects do to a blow, a kill, a round or a status is here, together with
## the critical hit and the notices a proc raises.
##
## Attack modifiers, criticals and on-hit effects only read primary damage.
## Secondary kills may raise death events; EffectEngine caps their chain depth.
const Essences = preload("res://expedition/progression/essences.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
static var EFFECTS: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/stone_effects.json")).get("effects",{})
## The statuses a hexer lengthens and a serpent sheds (`Statuses.HARMFUL`).
const HARMFUL := ["confuse","slow","freeze","bind","burn","weak","brittle","distort","vulnerable","dominate","bleed","poison","taunted","stun","fracture","exposed","marked"]
## The blows that can be critical: weapon attacks (a landed hit, the old
## slash) and actives. Spells never are, and the secondary forms never get here.
const CRIT_FORMS := ["physical","SLASH","IMPACT","PIERCE"]
const CRIT_BASE := 150
const CRIT_STEP := 50
const SPEED_CAP := 40
const SUPPORT_ATTACK := {4:8,6:10}
const MELEE_ATTACK := {2:12,4:25,6:30}
const MELEE_CRIT := {4:8,6:10}
const SUPPORT_HEAL := {2:20,4:30,6:40}
const RANGED_DAMAGE := {4:20,6:25}
const MAGIC_SPELL := {2:12,4:25,6:30}
const TONES := ["buff","heal","debuff","crit"]
## Tests pin every roll here: -1 rolls for real, anything else is the roll.
static var force := -1
static var by_species: Dictionary = {}

## The headline effect a stone carries: its base row's, none for a boss stone.
static func effect_of(id: String) -> String:
	if not Essences.has(id): return ""
	return str(Essences.row(id).get("effect",""))

static func species_effect(species_id: String) -> String:
	if species_id.is_empty(): return ""
	if by_species.is_empty():
		for id in Essences.content.rows: by_species[str(Essences.content.rows[id].get("species",""))] = str(id)
	return effect_of(str(by_species.get(species_id,"")))

## Every effect `actor` has, each once, in slot order.
static func effects(actor: Dictionary) -> Array:
	return EffectEngine.effects(actor)

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
static func proc(s, cell: Vector2i, text: String, tone: String, visual: String = "", origin: Variant = null) -> void:
	s.effects.append({"kind":"PROC","from":cell if origin == null else origin,"cell":cell,"text":text,"tone":tone if tone in TONES else "buff","vfx":visual})
	Vfx.trim(s)

static func heal(s, actor: Dictionary, amount: int, healer: Dictionary = {}, lifesteal: bool = false, drain_from: Dictionary = {}) -> int:
	if not alive(actor) or amount <= 0: return 0
	var heal_ctx := {"source":healer,"target":actor,"external_heal":not healer.is_empty() and healer != actor,"lifesteal":lifesteal}
	amount = amount*(100+EffectEngine.modifier(s,"heal_taken_percent",actor,heal_ctx))/100
	amount = amount*(100+EffectEngine.modifier(s,"heal_given_percent",healer,heal_ctx)+int(SUPPORT_HEAL.get(TagSets.bracket(healer,"SUPPORT"),0)))/100
	var before: int = int(actor.hp)
	actor.hp = mini(int(actor.max_hp),before+amount)
	var gained: int = int(actor.hp)-before
	if gained > 0 or (lifesteal and amount > 0):
		if gained > 0:
			s.Body.heal(actor)
			if not s.effect_source.is_empty(): s.EffectReport.note(s,int(s.effect_source.owner),str(s.effect_source.effect),"heal",gained)
		proc(s,actor.pos,"+%d" % gained,"heal",("lifesteal" if lifesteal else "heal") if gained > 0 else "",drain_from.get("pos",healer.get("pos",actor.pos)))
		if not healer.is_empty(): fire(s,"HEALED",{"healer":healer,"target":actor,"amount":gained,"overheal":maxi(0,amount-gained),"lifesteal":lifesteal})
	return gained

## The members of `actor`'s side: the party and whoever stands with it.
static func side(s, actor: Dictionary) -> Array:
	return (s.party+s.npcs).filter(func(o): return alive(o) and not bool(o.get("enemy",false)) and s.side_of(o) == s.side_of(actor))

static func allies_beside(s, actor: Dictionary) -> Array:
	return (s.party+s.npcs+s.enemies).filter(func(o): return alive(o) and int(o.id) != int(actor.id) and s.side_of(o) == s.side_of(actor) and s.melee_reach(actor.pos,o.pos))

## 지원: the party takes the best bracket any of its members wears.
static func support_bracket(s, actor: Dictionary) -> int:
	if bool(actor.get("enemy",false)): return 0
	var best := TagSets.bracket(actor,"SUPPORT")
	if s == null: return best
	for member in side(s,actor): best = maxi(best,TagSets.bracket(member,"SUPPORT"))
	return best

# ── numbers ────────────────────────────────────────────────────────────────

## What the effects add to the stat sheet.
static func stat_bonus(actor: Dictionary, s = null) -> Dictionary:
	var result: Dictionary = {}
	for pair in [["block","sh"],["armour","ac"],["dodge","dodge"]]:
		var bonus: int = EffectEngine.modifier(s,str(pair[0]),actor)
		if bonus != 0: result[str(pair[1])] = bonus
	for element in ["fire","ice","air","poison","will"]:
		var bonus: int = EffectEngine.modifier(s,"res."+element,actor)
		if bonus != 0: result["res_"+element] = bonus
	return result

## Max HP in percent from equipped effects; no role lends HP to the party.
static func hp_percent(s, actor: Dictionary) -> int:
	var percent := EffectEngine.modifier(s,"max_hp_percent",actor)
	return percent

static func range_bonus(actor: Dictionary, s = null) -> int:
	return EffectEngine.modifier(s,"range",actor)

## 행동 속도 in percent from base stone stats and actual effects.
static func speed(s, actor: Dictionary) -> int:
	var total := 0
	if not bool(actor.get("enemy",false)): total += int(s.StatSheet.value(s,actor,"speed"))
	total += EffectEngine.modifier(s,"speed",actor)
	return clampi(total,-50,SPEED_CAP)

static func delay(s, actor: Dictionary, cost: int, kind: String = "ATTACK") -> int:
	var cut := speed(s,actor)
	var result: int = cost*(100-cut)/100
	if kind == "MOVE": result = result*(100+EffectEngine.modifier(s,"move_delay_percent",actor))/100
	if kind in ["MOVE","SWAP"] or Forms.attack_action(s,kind): result = Forms.fracture_delay(actor,result)
	return result

static func crit_chance(_s, attacker: Dictionary, target: Dictionary) -> int:
	var total := EffectEngine.modifier(_s,"crit_chance",attacker,{"target":target})
	total += int(MELEE_CRIT.get(TagSets.bracket(attacker,"MELEE"),0))
	if not target.is_empty() and target.get("statuses",{}).has("exposed"): total += 25+EffectEngine.modifier(_s,"exposed_bonus",attacker)
	return mini(100,total)

## A critical's damage in percent: ×1.5, fifty more from 해골 궁수.
static func crit_percent(attacker: Dictionary, s = null) -> int:
	var total := CRIT_BASE
	total += EffectEngine.modifier(s,"crit_damage",attacker)
	return total

static func spell_percent(_s, caster: Dictionary) -> int:
	return int(MAGIC_SPELL.get(TagSets.bracket(caster,"MAGIC"),0))

## 마법 6: no spell fails.
static func sure_casting(caster: Dictionary) -> bool:
	return TagSets.bracket(caster,"MAGIC") == 6

static func summon_extra(caster: Dictionary, s = null) -> int:
	return EffectEngine.modifier(s,"summon_count",caster)

static func status_ticks(caster: Dictionary, status: String, ticks: int, s = null) -> int:
	var protection: int = int(SUPPORT_HEAL.get(TagSets.bracket(caster,"SUPPORT"),0)) if status == "ward" else 0
	return ticks*(100+protection+EffectEngine.modifier(s,"status_ticks",caster,{"status":status,"harmful":status in HARMFUL})+EffectEngine.modifier(s,"status_ticks."+status,caster))/100

# ── hooks ──────────────────────────────────────────────────────────────────

static func casting(s) -> bool:
	return int(s.casting) > 0

static func ranged(s, attacker: Dictionary, target: Dictionary) -> bool:
	return attacker.has("pos") and target.has("pos") and s.distance(attacker.pos,target.pos) > 1

## A primary blow `attacker` is about to land on `target`.
static func outgoing(s, attacker: Dictionary, target: Dictionary, amount: int, form: String = "HIT", result: Dictionary = {}) -> int:
	if attacker.is_empty() or target.is_empty() or amount <= 0: return amount
	var ctx := context(s,attacker,target,form)
	var spent_stacks: Dictionary = attacker.get("stacks",{}).duplicate(true)
	ctx.amount = amount; ctx.attack_percent = 0; ctx.phase = "prepare"
	fire(s,"ATTACK",ctx)
	var percent := EffectEngine.modifier(s,"attack_percent",attacker,ctx)+int(ctx.attack_percent)
	if not bool(ctx.spell):
		percent += int(SUPPORT_ATTACK.get(support_bracket(s,attacker),0))
		percent += int(MELEE_ATTACK.get(TagSets.bracket(attacker,"MELEE"),0))
		if bool(ctx.ranged): percent += int(RANGED_DAMAGE.get(TagSets.bracket(attacker,"RANGED"),0))
	percent += EffectEngine.modifier(s,"summon_power",attacker,ctx)
	percent += EffectEngine.modifier(s,"harmful_bonus_step",attacker,ctx)*EffectEngine.Conditions.harmful_count(s,target)
	ctx.amount = amount*(100+percent)/100; ctx.phase = "scaled"
	fire(s,"ATTACK",ctx)
	amount = int(ctx.amount)
	result.critical = false
	if not bool(ctx.spell) and form in CRIT_FORMS:
		var exposed: bool = target.get("statuses",{}).has("exposed")
		if chance(s,attacker,target,"crit",crit_chance(s,attacker,target)):
			amount = amount*crit_percent(attacker,s)/100; result.critical = true
			proc(s,target.pos,"치명타!","crit","crit",attacker.pos); s.message("%s 치명타" % str(attacker.get("name","")))
			fire(s,"CRIT",ctx)
		if not bool(result.critical): amount = amount*(100+EffectEngine.modifier(s,"noncrit_percent",attacker,ctx))/100
		if exposed: target.statuses.erase("exposed")
	if not bool(ctx.spell):
		attacker.moved_since_attack = false
		attacker.effect_attacks = int(attacker.get("effect_attacks",0))+1
		for key in spent_stacks:
			if str(spent_stacks[key].get("until","")) == "attack" and int(attacker.get("stacks",{}).get(key,{}).get("generation",-1)) == int(spent_stacks[key].get("generation",-2)): Stacks.clear(attacker,str(key))
	return amount

## 거머리: fifteen percent more for every blow in a row on the same target.
static func latch(s, attacker: Dictionary, target: Dictionary) -> int:
	var ctx := context(s,attacker,target)
	ctx.attack_percent = 0; ctx.phase = "prepare"
	if has(attacker,"LEECH_LATCH"): EffectEngine.Code.run(s,"leech_prepare",attacker,{},ctx)
	return int(ctx.attack_percent)

## A primary blow `target` is about to take.
static func incoming(s, target: Dictionary, amount: int, source: Dictionary = {}) -> int:
	if target.is_empty() or amount <= 0: return amount
	var percent := EffectEngine.modifier(s,"taken_percent",target,{"source":source,"target":target})
	if target.has("pos") and allies_beside(s,target).any(func(o): return TagSets.bracket(o,"TANK") == 6): percent -= 10
	var reduced: int = maxi(1,amount*(100+percent)/100)
	if source.has("pos") and target.has("pos") and s.melee_reach(source.pos,target.pos): reduced = maxi(1,reduced-EffectEngine.modifier(s,"melee_flat_cut",target))
	return reduced

## The statuses a landed primary blow may hang, rolled after the blow's own
## reactions (`CombatRules.damage` calls this). Spells hang none.
static func procs(s, attacker: Dictionary, target: Dictionary, lost: int, element: String = "physical", facts: Dictionary = {}) -> void:
	if lost <= 0 or not alive(attacker) or target.is_empty(): return
	var ctx := context(s,attacker,target,element)
	ctx.merge(facts,true)
	ctx.lost = lost; ctx.phase = "proc"
	fire(s,"HIT",ctx)

## After a primary blow landed: the attacker's lifesteal and second shot,
## then the target's counter and reflection.
static func after_hit(s, target: Dictionary, attacker: Dictionary, form: String, lost: int) -> void:
	if not alive(attacker) or target.is_empty(): return
	var ctx := context(s,attacker,target,form)
	ctx.lost = lost; ctx.phase = "after"
	if lost > 0:
		attacker.effect_target = int(target.get("id",-1)); attacker.effect_hit_round = int(s.time)/100
		fire(s,"HIT",ctx)
	if not bool(ctx.spell) and form == "physical" and alive(target) and bool(ctx.ranged) and not has(attacker,"ORC_THROW"): second_shot(s,attacker,target)
	fire(s,"STRUCK",ctx)

## 오크 투척병 and 원딜 6: one more ranged attack, once an action.
static func second_shot(s, attacker: Dictionary, target: Dictionary) -> void:
	var odds := 0
	odds = EffectEngine.modifier(s,"second_shot_chance",attacker)
	if TagSets.bracket(attacker,"RANGED") == 6: odds = 100-(100-odds)*85/100
	if not chance(s,attacker,target,"double",odds) or not s.Reactions.once(s,attacker,"DOUBLE"): return
	proc(s,attacker.pos,"연사!","buff","haste")
	s.CombatRules.attack(s,attacker,target)

## A felling blow on a 묘지기 stone: once a fight it rises at thirty percent.
static func lethal(s, target: Dictionary, amount: int) -> int:
	if amount < int(target.get("hp",0)): return amount
	var ctx := {"target":target,"amount":amount}
	fire(s,"LETHAL",ctx)
	return int(ctx.amount)

static func on_kill(s, killer: Dictionary, victim: Dictionary, facts: Dictionary = {}) -> void:
	var ctx := context(s,killer,victim)
	ctx.merge(facts,true); ctx.killer = killer; ctx.victim = victim
	ctx.killer_is_crit = bool(facts.get("critical",false))
	if alive(killer) and not s.Downed.is_downed(victim):
		fire(s,"KILL",ctx); fire(s,"ALLY_KILL",ctx)
		if bool(ctx.get("primary",true)) and bool(victim.get("enemy",false)):
			if TagSets.bracket(killer,"MELEE") == 6: heal(s,killer,int(killer.max_hp)*5/100)
		if bool(killer.get("summoned",false)): fire(s,"PET_KILL",ctx)
	fire(s,"DEATH_NEAR",ctx)

static func round_start(s, actor: Dictionary) -> void:
	if not alive(actor): return
	Stacks.expire(actor,"round",int(s.time))
	fire(s,"ROUND_START",{"actor":actor})
	if TagSets.bracket(actor,"MAGIC") == 4 and actor.has("max_mp"): actor.mp = mini(int(actor.max_mp),int(actor.get("mp",0))+2)

	if TagSets.bracket(actor,"SUPPORT") == 6:
		for ally in allies_beside(s,actor):
			var harmful: Array = ally.get("statuses",{}).keys().filter(func(k): return k in HARMFUL)
			if harmful.is_empty() or not chance(s,actor,ally,"support_cleanse",25): continue
			harmful.sort_custom(func(a,b): return int(ally.statuses[a]) > int(ally.statuses[b]) if int(ally.statuses[a]) != int(ally.statuses[b]) else str(a) < str(b))
			ally.statuses.erase(harmful[0]); proc(s,ally.pos,"정화!","heal","cleanse",actor.pos)

## 신전 뱀: half the harmful statuses that would land slide off.
static func shed(s, victim: Dictionary, status: String, source: Dictionary) -> bool:
	var ctx := {"target":victim,"source":source,"status":status,"cancelled":false}
	fire(s,"STATUS_TAKEN",ctx)
	return bool(ctx.cancelled)

## A fight begins: the once-a-fight rising and the running tallies are fresh.
static func battle_start(s) -> void:
	for actor in s.party+s.npcs+s.enemies:
		actor.revived = false; actor.raging = false; actor.erase("latch")
		actor.effect_attacks = 0; actor.effect_hit_round = -1; actor.effect_moved_round = -1
		Stacks.reset(actor); actor.effect_mods = {}; actor.erase("blood_ward"); actor.erase("blood_ward_until")
		actor.moved_since_attack = false; actor.effect_struck_round = -99
		actor.gear_crisis_used = false; actor.repeat_reaction = false
		fire(s,"BATTLE_START",{"actor":actor})

static func fire(s, when: String, ctx: Dictionary) -> void:
	ctx["when"] = when
	EffectEngine.fire(s,when,ctx)

static func modifier(s, key: String, actor: Dictionary, ctx: Dictionary = {}) -> int:
	return EffectEngine.modifier(s,key,actor,ctx)

static func context(s, attacker: Dictionary, target: Dictionary, damage_element: String = "physical") -> Dictionary:
	return {"attacker":attacker,"source":attacker,"target":target,"form":str(s.blow_form),
		"element":str(s.Reactions.element_of(damage_element)),"damage_element":damage_element,
		"hit_form":s.Reactions.HIT_FORM,"spell":casting(s),"ranged":ranged(s,attacker,target),"primary":true}
