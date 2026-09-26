extends RefCounted
const Stacks = preload("res://expedition/progression/stacks.gd")
const KEYS := ["form","element","ranged","spell","target_has","target_harmful_at_least","target_full","target_distance_at_least","self_hp_below","self_has","self_wet","status_is","adjacent_allies_at_least","adjacent_enemies_at_least","no_adjacent_enemy","stack_at_least","unarmed","first_attack","same_target_as_ally","moved_this_round","killer_is_crit","victim_had","owner_adjacent_to_target","status_already","chance","alive_target","alive_other","melee","damage_element","harmful","phase","primary","victim_enemy","reaction","school","died","target_has_any","source_has","target_wet","not_hit_last_round","moved_since_attack","external_heal","lifesteal","same_pet_target","pet_alive","self_hp_above","not_moved_last_round"]

static func radius(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x-b.x),absi(a.y-b.y))

static func target(ctx: Dictionary) -> Dictionary:
	return ctx.get("target",ctx.get("victim",ctx.get("ally",{})))

static func other(owner: Dictionary, ctx: Dictionary) -> Dictionary:
	var to := target(ctx)
	return ctx.get("attacker",ctx.get("source",{})) if int(to.get("id",-1)) == int(owner.get("id",-2)) else to

static func near(s, owner: Dictionary, friendly: bool) -> Array:
	if s == null or not owner.has("pos"): return []
	return (s.party+s.npcs+s.enemies).filter(func(o): return int(o.get("hp",0)) > 0 and int(o.id) != int(owner.get("id",-1)) and (s.side_of(o) == s.side_of(owner)) == friendly and s.melee_reach(owner.pos,o.pos))

static func harmful_count(s, actor: Dictionary) -> int:
	if s == null: return 0
	return actor.get("statuses",{}).keys().filter(func(k): return k in s.StoneEffects.HARMFUL).size()

static func matches(s, clauses: Array, owner: Dictionary, ctx: Dictionary, lane: String = "") -> bool:
	for clause in clauses:
		for key in clause:
			if not test(s,str(key),clause[key],owner,ctx,lane): return false
	return true

static func test(s, key: String, value: Variant, owner: Dictionary, ctx: Dictionary, lane: String = "") -> bool:
	var to := target(ctx)
	var counterpart := other(owner,ctx)
	var now: int = int(s.time) if s != null else 0
	match key:
		"form", "element", "phase", "damage_element", "reaction", "school": return str(ctx.get(key,"")) == str(value)
		"spell", "ranged", "status_already", "killer_is_crit", "primary", "died": return bool(ctx.get(key,false)) == bool(value)
		"target_has_any": return value.any(func(k): return to.get("statuses",{}).has(k))
		"source_has": return ctx.get("source",{}).get("statuses",{}).has(str(value))
		"target_wet": return s != null and s.Reactions.is_wet(s,to) == bool(value)
		"not_hit_last_round": return (int(owner.get("effect_struck_round",-99)) < now/100-1) == bool(value)
		"moved_since_attack": return bool(owner.get("moved_since_attack",false)) == bool(value)
		"external_heal", "lifesteal": return bool(ctx.get(key,false)) == bool(value)
		"pet_alive": return s != null and s.npcs.any(func(p): return p.get("summoned",false) and p.hp > 0 and int(p.get("summoner",-1)) == int(owner.id)) == bool(value)
		"same_pet_target":
			if s == null: return false
			var source: Dictionary = ctx.get("source",{})
			return s.npcs.filter(func(p): return p.get("summoned",false) and p.hp > 0 and int(p.get("summoner",-1)) == int(owner.id) and (p == source or int(p.get("effect_target",-2)) == int(to.get("id",-3)) and int(p.get("effect_hit_round",-99)) == now/100)).size() >= 2
		"self_hp_above": return int(owner.hp)*100 > int(owner.max_hp)*int(value)
		"target_has": return to.get("statuses",{}).has(str(value))
		"target_harmful_at_least": return harmful_count(s,to) >= int(value)
		"target_full": return (not to.is_empty() and int(to.get("hp",0)) >= int(to.get("max_hp",1))) == bool(value)
		"target_distance_at_least": return s != null and owner.has("pos") and to.has("pos") and s.distance(owner.pos,to.pos) >= int(value)
		"self_hp_below": return int(owner.get("hp",0))*100 <= int(owner.get("max_hp",1))*int(value)
		"self_has": return owner.get("statuses",{}).has(str(value))
		"self_wet": return s != null and s.Reactions.is_wet(s,owner) == bool(value)
		"status_is": return str(ctx.get("status","")) in value if value is Array else str(ctx.get("status","")) == str(value)
		"harmful": return bool(ctx.get("harmful",str(ctx.get("status","")) in s.StoneEffects.HARMFUL if s != null else false)) == bool(value)
		"adjacent_allies_at_least": return near(s,owner,true).size() >= int(value)
		"adjacent_enemies_at_least": return near(s,owner,false).size() >= int(value)
		"no_adjacent_enemy": return s != null and near(s,owner,false).is_empty() == bool(value)
		"stack_at_least": return Stacks.count(owner,str(value[0]),now) >= int(value[1])
		"unarmed": return owner.get("gear",{}).get("weapon",{}).is_empty() == bool(value)
		"first_attack": return (int(owner.get("effect_attacks",0)) == 0) == bool(value)
		"not_moved_last_round": return (now >= 100 and int(owner.get("effect_moved_round",-1)) != now/100-1) == bool(value)
		"moved_this_round": return (int(owner.get("effect_moved_round",-1)) == now/100) == bool(value)
		"same_target_as_ally":
			if s == null: return false
			return (s.party+s.npcs+s.enemies).any(func(o): return int(o.id) != int(owner.get("id",-1)) and s.side_of(o) == s.side_of(owner) and int(o.get("effect_target",-1)) == int(to.get("id",-2)) and int(o.get("effect_hit_round",-1)) == now/100) == bool(value)
		"victim_had":
			var worn: Dictionary = ctx.get("victim_statuses",{})
			return worn.keys().any(func(k): return k in s.StoneEffects.HARMFUL) if str(value) == "harmful" and s != null else worn.has(str(value))
		"owner_adjacent_to_target": return s != null and owner.has("pos") and to.has("pos") and int(owner.get("id",-1)) != int(to.get("id",-1)) and s.melee_reach(owner.pos,to.pos) == bool(value)
		"victim_enemy": return bool(to.get("enemy",false)) == bool(value)
		"alive_target": return (not to.is_empty() and int(to.get("hp",0)) > 0) == bool(value)
		"alive_other": return (not counterpart.is_empty() and int(counterpart.get("hp",0)) > 0) == bool(value)
		"melee": return s != null and owner.has("pos") and counterpart.has("pos") and s.melee_reach(owner.pos,counterpart.pos) == bool(value)
		"chance": return s != null and s.StoneEffects.chance(s,owner,counterpart,lane,int(value)+(s.StoneEffects.modifier(s,"kill_chance",owner) if str(ctx.get("when","")) == "KILL" else 0))
	return false
