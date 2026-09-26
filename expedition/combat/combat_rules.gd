extends RefCounted
const TagSets = preload("res://expedition/progression/tag_sets.gd")
const Reactions = preload("res://expedition/combat/reactions.gd")
const Stats = preload("res://expedition/combat/combat_stats.gd")
const Turns = preload("res://sim/turn_engine.gd")
const Hunt = preload("res://expedition/progression/hunt.gd")
const StoneEffects = preload("res://expedition/progression/stone_effects.gd")
const Forms = preload("res://expedition/combat/forms.gd")
## A monster's shot loses aim with distance: each tile past contact adds this
## much to the target's dodge, up to RANGED_DODGE_CAP.
const RANGED_DODGE_PER_TILE := 6
const RANGED_DODGE_CAP := 60

static func roll(s, source: Dictionary, target: Dictionary, lane: String, modulus: int) -> int:
	if modulus <= 1: return 0
	# The target and roll ordinal keep simultaneous cleave/brand rolls independent.
	s.roll_serial += 1
	return s.Hexaco.sample(s.seed_value, s.time * 37 + int(source.get("id", -1)) * 997 + int(target.get("id", -1)) * 17 + s.roll_serial, lane, modulus)

static func attack(s, source: Dictionary, target: Dictionary) -> Dictionary:
	var out := {"hit":false, "evaded":false, "blocked":false, "damage":0}
	if target.is_empty() or int(target.hp) <= 0: return out
	source["physical_blow"] = true
	Stats.Equipment.attack_noise(s,source)
	if not bool(source.get("enemy",false)) and bool(target.get("enemy",false)):
		Hunt.record(source,int(target.id))
	var offense: Dictionary = Stats.stats(s, source)
	var defense: Dictionary = Stats.stats(s, target)
	# 왜곡 takes thirty points off whatever the attacker can still aim.
	# 회피 % from the soul stones rides on the evasion's own two percent a point.
	var dodge := clampi(int(defense.ev) * 2 + int(defense.get("dodge", 0)) - StoneEffects.modifier(s,"accuracy",source), 5, 45)
	var gap: int = maxi(absi(source.pos.x - target.pos.x), absi(source.pos.y - target.pos.y))
	if bool(source.get("enemy", false)) and gap > 1: dodge = mini(RANGED_DODGE_CAP, dodge + RANGED_DODGE_PER_TILE * (gap - 1))
	if StoneEffects.modifier(s,"zero_dodge",target) > 0: dodge = 0
	if source.get("statuses", {}).has("distort"): dodge = mini(95, dodge + 30)
	if roll(s, source, target, "dodge", 100) < dodge:
		StoneEffects.fire(s,"DODGE",StoneEffects.context(s,source,target))
		out.evaded = true; s.message(str(target.name) + " 회피")
		s.effects.append({"kind":"MISS","from":source.pos,"cell":target.pos,"text":"회피","enemy":bool(target.get("enemy",false)) or bool(target.get("hostile",false))})
		return out
	if roll(s, source, target, "block", 100) < int(defense.sh):
		StoneEffects.fire(s,"BLOCK",StoneEffects.context(s,source,target))
		out.blocked = true; s.message(str(target.name) + " 방패 방어")
		s.effects.append({"kind":"MISS","from":source.pos,"cell":target.pos,"text":"막음","enemy":bool(target.get("enemy",false)) or bool(target.get("hostile",false))})
		if StoneEffects.has(target,"SHIELD_STANCE"): StoneEffects.proc(s,target.pos,"막음!","buff")
		return out
	var form: String = Forms.of_actor(source)
	var unscaled := int(offense.damage)
	var recipient: Dictionary = s.protection_recipient(target)
	var raw := Forms.scale(unscaled,form,recipient,source,s)
	if offense.trait == "stab" and (target.get("statuses", {}).has("confuse") or not bool(target.get("alert", true))): raw *= 2
	var ac := Forms.armour(int(Stats.stats(s,recipient).ac),form,source,s)
	var physical: Dictionary = Turns.physical(raw, 950, 0, roll(s, source, target, "absorb", ac + 1))
	out.hit = true
	var was: String = Forms.begin(s,form)
	out.damage = damage(s, source, target, int(physical.damage), "physical")
	if target.hp > 0:
		match str(offense.brand):
			"fire", "ice": out.damage += damage(s, source, target, 4, str(offense.brand),0,Reactions.EXTRA_FORM)
			"venom":
				if int(defense.res.get("poison", 0)) < 100: s.Statuses.apply(s,target,"poison",StoneEffects.status_ticks(source,"poison",300,s),source)
			"drain": StoneEffects.heal(s,source,3,source,true)
		if offense.trait == "cleave":
			for other in s.party + s.npcs + s.enemies:
				if other.id != target.id and other.hp > 0 and s.side_of(other) != s.side_of(source) and s.melee_reach(source.pos, other.pos):
					var taker: Dictionary = s.protection_recipient(other)
					var cleave_raw := Forms.scale(unscaled/2,form,taker,source,s)
					damage(s,source,other,maxi(1,cleave_raw-Forms.armour(int(Stats.stats(s,taker).ac),form,source,s)),"physical")
	Forms.end(s,was)
	return out

## Every damage in the game. `hit_form` says what kind of blow this is: a
## landed hit, a set's extra, a reaction or a counter. Only hits and extras
## react; the secondary forms reach `after_damage` under their own name so
## passives stay out of them.
static func damage(s, source: Dictionary, target: Dictionary, raw: int, element: String, penetration: int = 0, hit_form: String = "HIT") -> int:
	if target.hp <= 0 or raw <= 0: return 0
	# Direct physical attacks (boss sweeps and the legacy attack path) also carry
	# a form. Sourceless hazards and secondary damage never create a new blow.
	var previous: String = str(s.blow_form)
	if hit_form == Reactions.HIT_FORM and not source.is_empty() and int(s.casting) == 0:
		if previous.is_empty() and element in Forms.FORMS: Forms.begin(s,element)
		if element in ["physical","SLASH","IMPACT","PIERCE"]: source["physical_blow"] = true
	var amount: int = TagSets.element_damage(source,element,raw)
	if element not in ["physical", "SLASH", "IMPACT", "PIERCE", "RETALIATE", "REACTION", "COUNTER", "EXTRA"]:
		var listed: int = int(Stats.stats(s,target).res.get(element.to_lower(),0))
		var resistance: int = listed if listed <= 0 else maxi(0,listed-penetration)
		amount = maxi(0, amount * (100 - resistance) / 100)
	# 취약화 is read after resistance: everything that still lands lands harder.
	if target.get("statuses", {}).has("vulnerable"): amount = amount * 13 / 10
	if bool(target.get("morale_broken",false)): amount = amount * 13 / 10
	if target.get("statuses",{}).has("cracked") and element in ["physical","SLASH","IMPACT","PIERCE"]: amount = amount * 13 / 10
	if target.get("statuses",{}).has("marked"): amount = amount * 12 / 10
	var form: String = element if hit_form == Reactions.HIT_FORM else hit_form
	var received: Dictionary = {}
	var lost: int = s.after_damage(target, amount, int(source.get("id", 999)), form,received)
	var victim: Dictionary = received.get("target",target)
	if hit_form in [Reactions.HIT_FORM, Reactions.EXTRA_FORM]: Reactions.on_hit(s, source, victim, element, lost, hit_form)
	# The stones' status procs come after the reactions, like the element sets'
	# own, so a blow never shatters the ice its own proc just laid.
	if hit_form == Reactions.HIT_FORM:
		StoneEffects.procs(s, source, victim, lost,element,received)
		Forms.wound(s,source,victim,lost)
		Forms.supplemental(s,source,victim,lost)
	Forms.end(s,previous)
	return lost

static func move_time(s, actor: Dictionary, cell: Vector2i) -> int:
	var value := maxi(int(actor.get("speed", 100)), int(Stats.content.move_cost.get(str(s.tile(cell).terrain), 100)))
	if bool(s.tile(cell).get("ice",false)): value = value * 3 / 2
	var statuses: Dictionary = actor.get("statuses", {})
	if statuses.has("slow"): value = value * 3 / 2
	if statuses.has("haste"): value = value * 2 / 3
	return maxi(40, value)
