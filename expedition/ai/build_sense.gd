extends RefCounted
## Build preferences read actual effects and legal actions, without changing session state.
const Effects = preload("res://expedition/progression/effect_engine.gd")
const Forms = preload("res://expedition/combat/forms.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Stats = preload("res://expedition/combat/combat_stats.gd")
const Lookahead = preload("res://expedition/ai/lookahead.gd")
const NAMES := {1:"출혈",2:"분쇄",3:"급소",4:"광폭",5:"수호",6:"사수",7:"원소",8:"저주",9:"독",10:"소환",11:"사령",12:"지원"}
const Subtypes = preload("res://expedition/progression/subtypes.gd")
const IDS := ["build_target","build_setup","build_hold","finish_form"]

static func subtype_profile(actor: Dictionary) -> Dictionary:
	var counts: Dictionary = {}; var total := 0.0
	for id in Effects.effects(actor):
		var subtype := Subtypes.of(str(id))
		if subtype.is_empty(): continue
		counts[subtype] = float(counts.get(subtype,0.0))+1.0; total += 1.0
	if total > 0:
		for subtype in counts: counts[subtype] = float(counts[subtype])/total
	return counts

static func profile(actor: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	var subtypes := subtype_profile(actor)
	for subtype in subtypes:
		var family: int = int(Subtypes.LEGACY_FAMILY[subtype])
		counts[family] = float(counts.get(family,0.0))+float(subtypes[subtype])
	return counts

static func top_subtype(actor: Dictionary) -> String:
	var p := subtype_profile(actor); var ids: Array = p.keys()
	ids.sort_custom(func(a,b): return float(p[a]) > float(p[b]) if float(p[a]) != float(p[b]) else Subtypes.IDS.find(a) < Subtypes.IDS.find(b))
	return str(ids[0]) if not ids.is_empty() else ""

static func main(actor: Dictionary) -> Array:
	var p := profile(actor)
	var result: Array = p.keys().filter(func(k): return float(p[k]) >= 0.3)
	result.sort_custom(func(a,b): return float(p[a]) > float(p[b]) if float(p[a]) != float(p[b]) else int(a) < int(b))
	return result.slice(0,2)

static func has(actor: Dictionary, id: String) -> bool:
	return id in Effects.effects(actor)

static func form(actor: Dictionary, action: Dictionary) -> String:
	return Forms.of_actor(actor) if str(action.kind) == "ATTACK" else Forms.of_part(Abilities.definition(str(action.kind))) if Abilities.has(str(action.kind)) else ""

static func elemental(actor: Dictionary, action: Dictionary) -> String:
	if Abilities.has(str(action.kind)): return str(Abilities.definition(str(action.kind)).get("element",""))
	var brand: String = str(actor.get("gear",{}).get("weapon",{}).get("brand",""))
	return "poison" if brand == "venom" else brand

static func can_attack(s, actor: Dictionary, target: Dictionary) -> bool:
	if s.status_blocks(actor,"ATTACK") or int(actor.get("hp",0)) <= 0: return false
	if int(actor.get("effect_moved_round",-1)) == int(s.time)/100 and Effects.modifier(s,"no_attack_after_move",actor) > 0: return false
	return s.attack_reach(actor,target.pos,int(Stats.stats(s,actor).range)) and s.floor_state.visible.has(target.pos)

static func fit(s, actor: Dictionary, action: Dictionary, family: int) -> float:
	if str(action.kind) in ["MOVE","WAIT","GUARD"]: return 0.0
	var target: Dictionary = s.at(action.cell)
	if target.is_empty() or s.side_of(target) == s.side_of(actor): return 0.0
	var statuses: Dictionary = target.get("statuses",{})
	var f := form(actor,action)
	var element := elemental(actor,action)
	match family:
		1: return 1.0 if statuses.has("bleed") else 0.5 if f == Forms.SLASH or has(actor,"RAT_INCISOR") and f == Forms.PIERCE else 0.0
		2: return 1.0 if ["fracture","stun","freeze"].any(func(k): return statuses.has(k)) else 0.5 if f == Forms.IMPACT else 0.0
		3: return 1.0 if statuses.has("exposed") else 0.5 if int(target.hp) >= int(target.max_hp) else 0.0
		11: return 1.0 if int(action.get("damage",0)) >= int(target.hp) else 0.5 if Effects.Conditions.harmful_count(s,target) > 0 else 0.0
		4: return 1.0 if int(action.get("damage",0)) >= int(target.hp) else 0.5 if int(target.hp)*2 <= int(target.max_hp) else 0.0
		6: return 1.0 if statuses.has("marked") or has(actor,"ARCHER_EYE") and s.distance(actor.pos,target.pos) >= 4 else 0.5
		7:
			if element.is_empty(): return 0.0
			var reactive: bool = element == "air" and s.Reactions.is_wet(s,target) or element == "ice" and statuses.has("burn") or element == "fire" and statuses.has("freeze")
			return 1.0 if reactive else 0.5 if statuses.is_empty() else 0.0
		8:
			var n: int = Effects.Conditions.harmful_count(s,target)
			return 1.0 if n >= 3 else 0.5 if n > 0 else 0.0
		9:
			return 1.0 if statuses.has("poison") else 0.5 if element == "poison" or has(actor,"TOAD_SPIT") else 0.0
		10:
			for pet in s.npcs:
				if int(pet.get("summoner",-1)) != int(actor.id) or pet.hp <= 0: continue
				if int(pet.get("effect_target",-1)) == int(target.id) and int(pet.get("effect_hit_round",-1)) == int(s.time)/100: return 1.0
				if s.melee_reach(pet.pos,target.pos): return 0.5
	return 0.0

static func inputs(s, actor: Dictionary, action: Dictionary) -> Dictionary:
	var result := {"build_target":0.0,"build_setup":0.0,"build_hold":0.0,"finish_form":0.0}
	var mains := main(actor)
	if mains.is_empty() or s.party_command == "ATTACK_TARGET": return result
	for family in mains: result.build_target = maxf(result.build_target,fit(s,actor,action,int(family)))
	var target: Dictionary = s.at(action.cell)
	var f := form(actor,action)
	if str(action.kind) not in ["MOVE","WAIT"] and not target.is_empty() and s.side_of(target) != s.side_of(actor):
		for ally in s.party:
			if ally.id == actor.id or ally.hp <= 0: continue
			for family in main(ally):
				var setup: bool = int(family) == 1 and applies(s,actor,action,"bleed") and not target.statuses.has("bleed") or int(family) == 2 and applies(s,actor,action,"fracture") and not target.statuses.has("fracture") or int(family) == 3 and applies(s,actor,action,"exposed") and not target.statuses.has("exposed")
				if int(family) == 7:
					var ally_element: String = elemental(ally,{"kind":"ATTACK"})
					setup = setup or (ally_element == "air" and applies(s,actor,action,"wet")) or (ally_element == "ice" and applies(s,actor,action,"burn")) or (ally_element == "fire" and applies(s,actor,action,"freeze"))
				if int(family) == 8: setup = setup or s.StoneEffects.HARMFUL.any(func(status): return not target.statuses.has(status) and applies(s,actor,action,str(status)))
				if setup: result.build_setup = 1.0
	var dest: Vector2i = action.cell if str(action.kind) == "MOVE" else actor.pos
	if 6 in mains and has(actor,"KOBOLD_HEART") and str(action.kind) != "MOVE" and s.combat_enemies().any(func(e): return can_attack(s,actor,e)): result.build_hold = 1.0
	if 5 in mains:
		if s.party.any(func(a): return a.id != actor.id and a.hp > 0 and s.melee_reach(dest,a.pos)): result.build_hold = 1.0
	if 12 in mains and Abilities.has(str(action.kind)) and str(Abilities.definition(str(action.kind)).get("effect","")) in ["HEAL","GUARD"]: result.build_hold = 1.0
	if 10 in mains and s.npcs.any(func(p): return p.hp > 0 and int(p.get("summoner",-1)) == int(actor.id) and not s.combat_enemies().is_empty() and s.distance(dest,s.combat_enemies()[0].pos) > s.distance(p.pos,s.combat_enemies()[0].pos)): result.build_hold = 1.0
	if s.aim_parts and not target.is_empty() and int(action.get("damage",0)) >= int(target.get("hp",1)) and int(target.get("hp",0)) > 0:
		var wishes := wishes(s,target)
		var part_index := Forms.FORMS.find(f)
		if part_index >= 0 and Forms.PARTS[part_index] in wishes: result.finish_form = 1.0
		elif not wishes.is_empty() and yield_to(s,actor,target,wishes): result.finish_form = -1.0
	return result

static func wishes(s, target: Dictionary) -> Array:
	var base: String = s.Essences.base_of(str(target.get("part_id","")))
	var row: Dictionary = s.Essences.content.rows.get(base,{})
	if not row.has("parts"): return []
	var explicit: Array = s.part_wishes.get(str(target.get("species_id","")),s.part_wishes.get(base,[]))
	if not explicit.is_empty(): return explicit.filter(func(p): return p in Forms.PARTS)
	var families: Array = []
	var owned: Array = s.parts_bag.keys().filter(func(id): return int(s.parts_bag[id]) > 0)
	for ally in s.party:
		owned.append_array(ally.get("essences",{}).keys())
		for family in main(ally):
			if family not in families: families.append(family)
	var result: Array = []
	for part in Forms.PARTS:
		if owned.any(func(id): return s.Essences.base_of(str(id)) == base and s.Essences.part_of(s.Essences.canonical(str(id))) == part): continue
		var effect: String = str(row.parts[part].get("effect",""))
		if int(Subtypes.LEGACY_FAMILY.get(Subtypes.of(effect),0)) in families: result.append(part)
	return result

static func yield_to(s, actor: Dictionary, target: Dictionary, desired: Array) -> bool:
	var key: String = "%d:%d" % [int(s.depth),int(target.id)]
	if s.finish_yielded.has(key): return false
	for member in s.friends():
		if Lookahead.threat_after(s,member,{},{},{},s.intents) >= int(member.hp): return false
	# An enemy able to hurt anybody or resolve a telegraph is never kept alive for loot.
	if s.intents.any(func(i): return int(i.id) == int(target.id)): return false
	if int(target.get("cast_recovery",0)) <= 0:
		var role: Dictionary = s.Floor.MonsterAI.ROLES.get(str(target.get("role","MELEE")),s.Floor.MonsterAI.ROLES.MELEE)
		if s.party.any(func(a): return a.hp > 0 and (s.melee_reach(a.pos,target.pos) or int(role.get("range",1)) > 1 and s.Floor.MonsterAI.line(s,target.pos,a.pos,int(role.range)))): return false
	for ally in s.party:
		if ally.id == actor.id or ally.hp <= 0 or not can_attack(s,ally,target): continue
		var form_index := Forms.FORMS.find(Forms.of_actor(ally))
		if form_index < 0 or Forms.PARTS[form_index] not in desired: continue
		if s.manual_mode and int(ally.get("ready_at",0)) >= int(target.get("ready_at",0)): continue
		if not s.manual_mode and (ally.ap <= 0 or s.party.find(ally) <= s.party.find(actor)): continue
		var preview: Dictionary = s.attack_preview(target.pos,s.party.find(ally))
		if conservative_damage(s,ally,target,preview) >= int(target.hp): return true
	return false

static func candidates(s, actor: Dictionary, options: Array) -> void:
	if main(actor).is_empty() or s.party_command == "ATTACK_TARGET": return
	# Ranged contact retreat belongs to the stance and outranks holding aim.
	if str(actor.get("stance","")) == "SKIRMISHER" and s.combat_enemies().any(func(e): return s.melee_reach(actor.pos,e.pos)): return
	var best: Dictionary = {}; var score := -1.0
	for enemy in s.combat_enemies():
		if not can_attack(s,actor,enemy): continue
		var action := {"kind":"ATTACK","cell":enemy.pos,"tag":"ATTACK","target_id":int(enemy.id),"damage":int(s.attack_preview(enemy.pos,s.party.find(actor)).get("damage",0)),"reason":"공격"}
		var value: float = float(inputs(s,actor,action).build_target)
		if best.is_empty() or value > score or value == score and int(enemy.id) < int(best.target_id): best = action; score = value
	if not best.is_empty() and not options.any(func(o): return str(o.kind) == "ATTACK" and o.cell == best.cell): options.append(best)
	if not best.is_empty():
		for candidate in options.duplicate():
			if str(candidate.get("tag","")) == "MOVE:approach": options.erase(candidate)
	if has(actor,"KOBOLD_HEART") and best.is_empty() and not options.any(func(o): return str(o.kind) == "WAIT"): options.append({"kind":"WAIT","cell":actor.pos,"tag":"WAIT:hold","reason":"조준 유지"})
	if not best.is_empty() and float(inputs(s,actor,best).finish_form) < 0.0: options.append({"kind":"WAIT","cell":actor.pos,"tag":"WAIT:yield","reason":"마무리 양보","yield_target":int(best.target_id)})

static func safe_options(s, actor: Dictionary, options: Array, ctx: Dictionary) -> Array:
	if main(actor).is_empty(): return options
	var safe: Array = []
	for action in options:
		var danger: Dictionary = Lookahead.predict(s,actor,action,ctx.get("before_lethal",{}))
		if int(danger.self) < int(actor.hp): safe.append(action)
	return safe if not safe.is_empty() else options

static func committed(s, choice: Dictionary) -> void:
	if choice.get("reason_code","") == "FINISH_YIELD" and choice.has("yield_target"): s.finish_yielded["%d:%d" % [int(s.depth),int(choice.yield_target)]] = true

static func applies(s, actor: Dictionary, action: Dictionary, status: String) -> bool:
	var kind: String = str(action.kind)
	if kind in ["WAIT","MOVE","GUARD"]: return false
	var f := form(actor,action)
	if (status == "bleed" and f == Forms.SLASH) or (status == "fracture" and f == Forms.IMPACT) or (status == "exposed" and f == Forms.PIERCE): return true
	if str(Abilities.definition(kind).get("status","")) == status: return true
	if status == "poison" and elemental(actor,action) == "poison": return true
	var victim: Dictionary = s.at(action.cell)
	var ctx := {"source":actor,"target":victim,"form":f,"element":elemental(actor,action),"ranged":not victim.is_empty() and s.distance(actor.pos,victim.pos) > 1,"spell":false}
	for effect in Effects.effects(actor):
		for rule in Effects.content.effects.get(effect,{}).get("rules",[]):
			if str(rule.get("when","")) not in ["HIT","ATTACK"]: continue
			var conditions: Array = []
			for clause in rule.get("if",[]):
				var copy: Dictionary = clause.duplicate(); copy.erase("chance"); conditions.append(copy)
			if not Effects.Conditions.matches(s,conditions,actor,ctx): continue
			if rule.get("do",[]).any(func(a): return str(a.get("apply_status","")) == status): return true
	return false

## Lower bound for a finishing blow: ignore favorable procs, retain penalties and protection.
static func conservative_damage(s, actor: Dictionary, target: Dictionary, preview: Dictionary) -> int:
	if target.get("shield",false) or s.protection_recipient(target) != target: return 0
	for id in Effects.effects(target):
		if not target.get("revived",false) and Effects.content.effects.get(id,{}).get("rules",[]).any(func(r): return str(r.get("code","")) == "revive_once"): return 0
	var ctx: Dictionary = s.StoneEffects.context(s,actor,target,"physical")
	ctx.form = Forms.of_actor(actor)
	var amount: int = int(preview.get("damage_min",0))
	amount = amount*(100+mini(0,Effects.modifier(s,"attack_percent",actor,ctx)))/100
	amount = amount*(100+mini(0,Effects.modifier(s,"noncrit_percent",actor,ctx)))/100
	if has(actor,"COST_HEX") and Effects.Conditions.harmful_count(s,target) < 4: amount = amount*85/100
	amount = amount*(100-Abilities.reduction(target))/100
	amount = mini(amount,s.StoneEffects.incoming(s,target,amount,actor))
	if int(target.get("blood_ward_until",0)) > int(s.time): amount -= int(target.get("blood_ward",0))
	return maxi(0,amount)
