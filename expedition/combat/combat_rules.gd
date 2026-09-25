extends RefCounted
const TagSets = preload("res://expedition/progression/tag_sets.gd")
const Reactions = preload("res://expedition/combat/reactions.gd")
const Stats = preload("res://expedition/combat/combat_stats.gd")
const Turns = preload("res://sim/turn_engine.gd")
const Hunt = preload("res://expedition/progression/hunt.gd")
const StoneEffects = preload("res://expedition/progression/stone_effects.gd")

static func roll(s, source: Dictionary, target: Dictionary, lane: String, modulus: int) -> int:
	if modulus <= 1: return 0
	# The target and roll ordinal keep simultaneous cleave/brand rolls independent.
	s.roll_serial += 1
	return s.Hexaco.sample(s.seed_value, s.time * 37 + int(source.get("id", -1)) * 997 + int(target.get("id", -1)) * 17 + s.roll_serial, lane, modulus)

static func attack(s, source: Dictionary, target: Dictionary) -> Dictionary:
	var out := {"hit":false, "evaded":false, "blocked":false, "damage":0}
	if target.is_empty() or int(target.hp) <= 0: return out
	if not bool(source.get("enemy",false)) and bool(target.get("enemy",false)):
		Hunt.record(source,int(target.id))
	var offense: Dictionary = Stats.stats(s, source)
	var defense: Dictionary = Stats.stats(s, target)
	# 왜곡 takes thirty points off whatever the attacker can still aim.
	# 회피 % from the soul stones rides on the evasion's own two percent a point.
	var dodge := clampi(int(defense.ev) * 2 + int(defense.get("dodge", 0)), 5, 45)
	if source.get("statuses", {}).has("distort"): dodge = mini(95, dodge + 30)
	if roll(s, source, target, "dodge", 100) < dodge:
		out.evaded = true; s.message(str(target.name) + " 회피")
		s.effects.append({"kind":"MISS","from":source.pos,"cell":target.pos,"text":"회피","enemy":bool(target.get("enemy",false)) or bool(target.get("hostile",false))})
		return out
	if roll(s, source, target, "block", 100) < int(defense.sh):
		out.blocked = true; s.message(str(target.name) + " 방패 방어")
		s.effects.append({"kind":"MISS","from":source.pos,"cell":target.pos,"text":"막음","enemy":bool(target.get("enemy",false)) or bool(target.get("hostile",false))})
		if StoneEffects.has(target,"SHIELD_STANCE"): StoneEffects.proc(s,target.pos,"막음!","buff")
		return out
	var raw := int(offense.damage)
	if offense.trait == "stab" and (target.get("statuses", {}).has("confuse") or not bool(target.get("alert", true))): raw *= 2
	var ac := int(defense.ac) / 2 if offense.trait == "pierce" else int(defense.ac)
	var physical: Dictionary = Turns.physical(raw, 950, 0, roll(s, source, target, "absorb", ac + 1))
	out.hit = true
	out.damage = damage(s, source, target, int(physical.damage), "physical")
	if target.hp <= 0: return out
	match str(offense.brand):
		"fire", "ice": out.damage += damage(s, source, target, 4, str(offense.brand),0,Reactions.EXTRA_FORM)
		"venom":
			if int(defense.res.get("poison", 0)) < 100: target.statuses["poison"] = s.time + 300
		"drain": source.hp = mini(int(source.max_hp), int(source.hp) + 3)
	if offense.trait == "cleave":
		for other in s.party + s.npcs + s.enemies:
			if other.id != target.id and other.hp > 0 and s.side_of(other) != s.side_of(source) and s.melee_reach(source.pos, other.pos):
				damage(s, source, other, maxi(1, raw / 2 - int(Stats.stats(s, other).ac)), "physical")
	return out

## Every damage in the game. `hit_form` says what kind of blow this is: a
## landed hit, a set's extra, a reaction or a counter. Only hits and extras
## react; the secondary forms reach `after_damage` under their own name so
## passives stay out of them.
static func damage(s, source: Dictionary, target: Dictionary, raw: int, element: String, penetration: int = 0, hit_form: String = "HIT") -> int:
	if target.hp <= 0 or raw <= 0: return 0
	var amount: int = TagSets.element_damage(source,element,raw)
	if element not in ["physical", "SLASH", "IMPACT", "RETALIATE", "REACTION", "COUNTER", "EXTRA"]:
		var listed: int = int(Stats.stats(s,target).res.get(element.to_lower(),0))
		var resistance: int = listed if listed <= 0 else maxi(0,listed-penetration)
		amount = maxi(0, amount * (100 - resistance) / 100)
	# 취약화 is read after resistance: everything that still lands lands harder.
	if target.get("statuses", {}).has("vulnerable"): amount = amount * 13 / 10
	if bool(target.get("morale_broken",false)): amount = amount * 13 / 10
	if target.get("statuses",{}).has("cracked") and element in ["physical","SLASH","IMPACT"]: amount = amount * 13 / 10
	if target.get("statuses",{}).has("marked"): amount = amount * 12 / 10
	var form: String = element if hit_form == Reactions.HIT_FORM else hit_form
	var lost: int = s.after_damage(target, amount, int(source.get("id", 999)), form)
	if hit_form in [Reactions.HIT_FORM, Reactions.EXTRA_FORM]: Reactions.on_hit(s, source, target, element, lost, hit_form)
	# The stones' status procs come after the reactions, like the element sets'
	# own, so a blow never shatters the ice its own proc just laid.
	if hit_form == Reactions.HIT_FORM: StoneEffects.procs(s, source, target, lost)
	return lost

static func move_time(s, actor: Dictionary, cell: Vector2i) -> int:
	var value := maxi(int(actor.get("speed", 100)), int(Stats.content.move_cost.get(str(s.tile(cell).terrain), 100)))
	if bool(s.tile(cell).get("ice",false)): value = value * 3 / 2
	var statuses: Dictionary = actor.get("statuses", {})
	if statuses.has("slow"): value = value * 3 / 2
	if statuses.has("haste"): value = value * 2 / 3
	return maxi(40, value)
