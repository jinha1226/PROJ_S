extends RefCounted
## Data effects own their rules; combat owns the immutable event facts.
const Essences = preload("res://expedition/progression/essences.gd")
const Conditions = preload("res://expedition/progression/effect_conditions.gd")
const Actions = preload("res://expedition/progression/effect_actions.gd")
const Code = preload("res://expedition/progression/effect_code.gd")
const Stacks = preload("res://expedition/progression/stacks.gd")
const EVENTS := ["ATTACK","HIT","STRUCK","DODGE","BLOCK","CRIT","KILL","ALLY_KILL","DEATH_NEAR","LETHAL","ALLY_LETHAL","STATUS_GIVEN","STATUS_TAKEN","WOUND","REACTION","CAST","SUMMON","SUMMON_END","PET_KILL","ALLY_CRISIS","ROUND_START","BATTLE_START","MOVED","DOT_TICK","HEALED"]
const MODIFIERS := ["attack_percent","taken_percent","crit_chance","crit_damage","wound_chance","wound_chance.SLASH","wound_chance.IMPACT","wound_chance.PIERCE","status_ticks","speed","range","max_hp_percent","block","armour","dodge","res.fire","res.ice","res.air","res.poison","res.will","summon_count","summon_power","summon_hp","summon_ticks","reaction_percent","bleed_tick","poison_tick","heal_taken_percent","will_save","second_shot_chance"]
const MAX_DEPTH := 2
static var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/stone_effects.json"))

static func effects(actor: Dictionary) -> Array:
	if actor.is_empty() or bool(actor.get("boss",false)): return []
	var ids: Array = Essences.equipped(actor)
	if bool(actor.get("enemy",false)):
		# Monsters always use their species' headline, never a drop's other part.
		var part: String = str(actor.get("part_id",""))
		ids = [Essences.base_of(part)+("@"+Essences.variant_element(part) if not Essences.variant_element(part).is_empty() else "")]
		if not Essences.has(str(ids[0])):
			ids = []
			for id in Essences.content.rows:
				if str(Essences.content.rows[id].get("species","")) == str(actor.get("species_id","")) and not str(actor.get("species_id","")).is_empty(): ids.append(id); break
	var result: Array = []
	for id in ids:
		var effect: String = str(Essences.row(str(id)).get("effect",""))
		if not effect.is_empty() and effect not in result: result.append(effect)
	return result

static func owners(s, when: String, ctx: Dictionary) -> Array:
	if ctx.has("owner"): return [ctx.owner] if not ctx.owner.is_empty() else []
	var to := Conditions.target(ctx)
	var source: Dictionary = ctx.get("attacker",ctx.get("source",ctx.get("killer",ctx.get("caster",ctx.get("healer",ctx.get("actor",{}))))))
	if when in ["STRUCK","DODGE","BLOCK","LETHAL","STATUS_TAKEN"]: return [to] if not to.is_empty() else []
	if when in ["ALLY_KILL","ALLY_LETHAL","ALLY_CRISIS","DEATH_NEAR","DOT_TICK"]:
		var anchor: Dictionary = source if when == "ALLY_KILL" else to
		if anchor.is_empty() or not anchor.has("pos"): return []
		return (s.party+s.npcs+s.enemies).filter(func(o):
			if int(o.hp) <= 0 or int(o.id) == int(anchor.id): return false
			if when == "DEATH_NEAR": return Conditions.radius(o.pos,anchor.pos) <= 3
			if when == "DOT_TICK": return s.side_of(o) != s.side_of(anchor) and Conditions.radius(o.pos,anchor.pos) <= 2
			if s.side_of(o) != s.side_of(anchor): return false
			return when == "ALLY_KILL" or s.melee_reach(o.pos,anchor.pos))
	if when == "PET_KILL":
		var caster: Dictionary = s.actor_by_id(int(source.get("summoner",-1)))
		return [caster] if not caster.is_empty() else []
	return [source] if not source.is_empty() else []

static func fire(s, when: String, ctx: Dictionary) -> void:
	if when not in EVENTS or int(s.effect_depth) >= MAX_DEPTH: return
	s.effect_depth += 1
	var seen: Dictionary = {}
	for owner in owners(s,when,ctx):
		if int(owner.get("hp",0)) <= 0: continue
		if seen.has(int(owner.get("id",-1))): continue
		seen[int(owner.get("id",-1))] = true
		for effect in effects(owner):
			var row: Dictionary = content.effects.get(effect,{})
			var eligible: Array = []
			for rule in row.get("rules",[]):
				if str(rule.get("when","")) != when: continue
				if when == "ATTACK" and not rule.has("phase") and str(ctx.get("phase","scaled")) != "scaled": continue
				if when == "HIT" and not rule.has("phase") and str(ctx.get("phase","proc")) != "proc": continue
				if rule.has("phase") and str(rule.phase) != str(ctx.get("phase","")): continue
				if Conditions.matches(s,rule.get("if",[]),owner,ctx,str(rule.get("lane","fx_"+str(effect)))): eligible.append(rule)
			if eligible.is_empty(): continue
			var limited: bool = str(row.get("limit","action")) != "event"
			if limited and not s.Reactions.once(s,owner,"fx:"+str(effect)+":"+when): continue
			for rule in eligible:
				if rule.has("code"): Code.run(s,str(rule.code),owner,rule,ctx)
				else: Actions.run(s,owner,rule.get("do",[]),ctx)
	s.effect_depth -= 1

static func modifier(s, key: String, actor: Dictionary, ctx: Dictionary = {}) -> int:
	if actor.is_empty(): return 0
	var context: Dictionary = ctx.duplicate()
	if not context.has("target"): context.target = actor
	var candidates: Array = [actor]
	if s != null:
		candidates.append_array(Conditions.near(s,actor,true))
		if bool(actor.get("summoned",false)):
			var caster: Dictionary = s.actor_by_id(int(actor.get("summoner",-1)))
			if not caster.is_empty(): candidates.append(caster)
	var seen: Dictionary = {}
	var groups: Dictionary = {}
	var total := 0
	for owner in candidates:
		var identity: int = int(owner.get("id",-1))
		if seen.has(identity): continue
		seen[identity] = true
		for effect in effects(owner):
			for rule in content.effects.get(effect,{}).get("rules",[]):
				if str(rule.get("when","")) != "ALWAYS" or not rule.get("mod",{}).has(key): continue
				var scope: String = str(rule.get("scope","self"))
				if scope == "self" and owner != actor: continue
				if scope == "allies" and owner == actor: continue
				if scope == "summoner" and (not bool(actor.get("summoned",false)) or identity != int(actor.get("summoner",-2))): continue
				if not Conditions.matches(s,rule.get("if",[]),owner,context): continue
				var amount := value(s,rule.mod[key],owner,rule.mod)
				var group: String = str(rule.get("group",""))
				if group.is_empty(): total += amount
				elif not groups.has(group) or absi(amount) > absi(int(groups[group])): groups[group] = amount
	for amount in groups.values(): total += int(amount)
	return total

static func value(s, spec: Variant, owner: Dictionary, mods: Dictionary = {}) -> int:
	var definition: Dictionary = spec if spec is Dictionary else mods
	var amount: int = int(spec.get("value",0)) if spec is Dictionary else int(spec)
	if definition.has("per_count"):
		amount *= Conditions.near(s,owner,str(definition.per_count) == "adjacent_allies").size()
	if definition.has("per_stack"):
		var stack: Array = definition.per_stack
		amount *= Stacks.count(owner,str(stack[0]),int(s.time) if s != null else 0)*int(stack[1])
	if definition.has("per_lost_hp"): amount *= (100-int(owner.get("hp",0))*100/maxi(1,int(owner.get("max_hp",1))))/maxi(1,int(definition.per_lost_hp))
	return amount

static func validate(data: Dictionary) -> Array:
	var errors: Array = []
	for id in data.get("effects",{}):
		var effect: Dictionary = data.effects[id]
		if str(effect.get("name","")).is_empty() or str(effect.get("text","")).is_empty(): errors.append(str(id)+": missing label")
		if str(effect.get("limit","action")) not in ["action","event"]: errors.append(str(id)+": bad limit")
		for rule in effect.get("rules",[]):
			var when: String = str(rule.get("when",""))
			if when not in EVENTS+["ALWAYS"]: errors.append(str(id)+": unknown event "+when)
			if when == "ALWAYS" and (not rule.has("mod") or rule.has("do") or rule.has("code")): errors.append(str(id)+": ALWAYS requires only modifiers")
			if when != "ALWAYS" and (rule.has("mod") or (not rule.has("do") and not rule.has("code"))): errors.append(str(id)+": event requires actions or handler")
			if str(rule.get("scope","self")) not in ["self","allies","summoner"]: errors.append(str(id)+": unknown scope")
			for clause in rule.get("if",[]):
				for key in clause:
					if key not in Conditions.KEYS: errors.append(str(id)+": unknown condition "+str(key))
					if key == "chance" and (when == "ALWAYS" or not (clause[key] is int or clause[key] is float) or float(clause[key]) < 0 or float(clause[key]) > 100): errors.append(str(id)+": invalid chance")
			for key in rule.get("mod",{}):
				if key not in MODIFIERS+["per_count","per_stack","per_lost_hp"]: errors.append(str(id)+": unknown modifier "+str(key))
			if rule.has("code") and str(rule.code) not in Code.NAMES: errors.append(str(id)+": unknown handler")
			var notice := false
			var needs_notice := false
			for clause in rule.get("if",[]):
				if clause.has("chance"): needs_notice = true
			for action in rule.get("do",[]):
				var op := Actions.operation(action)
				if op not in Actions.NAMES: errors.append(str(id)+": unknown action "+op)
				if op == "notice": notice = true
				if op in ["apply_status","buff","stack","spread_status"]: needs_notice = true
			if needs_notice and not notice and not rule.has("code"): errors.append(str(id)+": missing notice")
	return errors
