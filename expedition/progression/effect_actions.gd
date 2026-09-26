extends RefCounted
const Stacks = preload("res://expedition/progression/stacks.gd")
const Conditions = preload("res://expedition/progression/effect_conditions.gd")
const NAMES := ["damage_percent","extra_damage","apply_status","extend_status","spread_status","burst","push","heal","gain_mp","stack","clear_stack","buff","cooldowns","redirect","revive","raise_dead","summon","notice","modify"]

static func operation(action: Dictionary) -> String:
	for key in action:
		if key in NAMES: return str(key)
	return str(action.keys()[0]) if not action.is_empty() else ""

static func recipients(s, owner: Dictionary, selector: String, ctx: Dictionary) -> Array:
	match selector:
		"self": return [owner]
		"adjacent_allies": return Conditions.near(s,owner,true)
		"self_and_allies": return [owner]+Conditions.near(s,owner,true)
		"party": return s.StoneEffects.side(s,owner)
		"attacker":
			var attacker: Dictionary = ctx.get("attacker",ctx.get("source",{}))
			return [attacker] if not attacker.is_empty() else []
		"ally": return [ctx.ally] if ctx.has("ally") and not ctx.ally.is_empty() else []
	var target := Conditions.target(ctx)
	return [target] if not target.is_empty() else []

static func amount(spec: Variant, to: Dictionary, ctx: Dictionary) -> int:
	if spec is Dictionary:
		if spec.has("max_hp%"): return int(to.get("max_hp",0))*int(spec["max_hp%"]) / 100
		if spec.has("dealt%"): return int(ctx.get("lost",0))*int(spec["dealt%"]) / 100
		if spec.has("victim_max_hp%"):
			return int(Conditions.target(ctx).get("max_hp",0))*int(spec["victim_max_hp%"]) / 100
		return int(spec.get("amount",0))
	return int(spec)

static func run(s, owner: Dictionary, actions: Array, ctx: Dictionary) -> void:
	var succeeded := true
	for action in actions:
		var op := operation(action)
		var targets := recipients(s,owner,str(action.get("target","target")),ctx)
		match op:
			"damage_percent": ctx.amount = int(ctx.get("amount",0))*(100+int(action[op]))/100
			"extra_damage":
				for to in targets:
					if int(to.get("hp",0)) > 0: s.CombatRules.damage(s,owner,to,amount(action[op],to,ctx),str(action.get("element","physical")),0,s.Reactions.EXTRA_FORM)
			"apply_status", "buff":
				succeeded = false
				for to in targets:
					if int(to.get("hp",0)) <= 0: continue
					var ticks: int = s.StoneEffects.status_ticks(owner,str(action[op]),int(action.get("ticks",100)),s)
					if s.Statuses.apply(s,to,str(action[op]),ticks,owner): succeeded = true
			"heal":
				for to in targets: s.StoneEffects.heal(s,to,maxi(int(action.get("minimum",0)),amount(action[op],to,ctx)),owner,bool(action.get("lifesteal",false)))
			"gain_mp": owner.mp = mini(int(owner.get("max_mp",0)),int(owner.get("mp",0))+int(action[op]))
			"stack":
				var cap: int = int(action.get("max",1))+s.StoneEffects.modifier(s,"stack_max",owner)+s.StoneEffects.modifier(s,"stack_max."+str(action[op]),owner)
				Stacks.add(owner,str(action[op]),int(action.get("add",1)),cap,action.get("until","battle"),int(s.time))
			"modify":
				for to in targets:
					var mods: Dictionary = to.get_or_add("effect_mods",{})
					var key: String = str(ctx.get("effect_id","modify"))
					var n: int = mini(int(action.get("cap",1)),int(mods.get(key,{}).get("n",0))+1) if int(mods.get(key,{}).get("until",0)) > int(s.time) else 1
					var values: Dictionary = {}
					for stat in action[op]: values[stat] = int(action[op][stat])*n
					mods[key] = {"mods":values,"n":n,"until":int(s.time)+int(action.get("ticks",100))}
			"clear_stack": Stacks.clear(owner,str(action[op]))
			"cooldowns":
				for key in owner.get("cooldowns",{}): owner.cooldowns[key] = maxi(0,int(owner.cooldowns[key])-int(action[op]))
			"extend_status":
				for to in targets:
					var until: int = int(to.get("statuses",{}).get(str(action[op]),0))
					if until > int(s.time): to.statuses[str(action[op])] = until+(until-int(s.time))*int(action.get("percent",50))/100
			"spread_status":
				var centre := Conditions.target(ctx)
				var worn: Dictionary = ctx.get("victim_statuses",centre.get("statuses",{}))
				succeeded = false
				if not centre.has("pos"): continue
				for to in s.party+s.npcs+s.enemies:
					if int(to.hp) <= 0 or s.side_of(to) == s.side_of(owner) or Conditions.radius(centre.pos,to.pos) > (int(action.get("radius",1))+s.StoneEffects.modifier(s,"radius",owner)): continue
					for status in worn:
						if str(action[op]) == str(status) or (str(action[op]) == "harmful" and status in s.StoneEffects.HARMFUL):
							if s.Statuses.apply(s,to,str(status),int(action.get("ticks",300)),owner): succeeded = true
					if succeeded and bool(action.get("one",false)): break
			"burst":
				var centre := Conditions.target(ctx)
				if not centre.has("pos"): continue
				for to in s.party+s.npcs+s.enemies:
					if int(to.hp) > 0 and s.side_of(to) != s.side_of(owner) and Conditions.radius(centre.pos,to.pos) <= int(action[op])+s.StoneEffects.modifier(s,"radius",owner):
						s.CombatRules.damage(s,owner,to,amount(action.get("damage",1),to,ctx),str(action.get("element","physical")),0,s.Reactions.REACTION_FORM)
			"push":
				for to in targets:
					if not owner.has("pos") or not to.has("pos") or int(to.get("hp",0)) <= 0: continue
					var direction := Vector2i(signi(to.pos.x-owner.pos.x),signi(to.pos.y-owner.pos.y))
					if direction == Vector2i.ZERO: continue
					for step in range(int(action[op])):
						var cell: Vector2i = to.pos+direction
						if not s.is_free(cell):
							s.CombatRules.damage(s,owner,to,int(action.get("blocked_damage",0)),"physical",0,s.Reactions.EXTRA_FORM); break
						to.pos = cell
			"redirect":
				var ally: Dictionary = ctx.get("ally",{})
				succeeded = ctx.get("when","") == "ALLY_LETHAL" and not ctx.has("redirector") and int(owner.get("hp",0)) > 0 and not ally.is_empty() and int(owner.id) != int(ally.id)
				if succeeded: ctx.redirector = owner
			"revive":
				if ctx.get("when","") == "LETHAL": owner.hp = maxi(1,int(owner.max_hp)*int(action[op])/100); ctx.amount = 0
			"summon", "raise_dead":
				var places: Array = s.Spells.Summons.summon_cells(s,owner)
				var corpse := Conditions.target(ctx)
				if op == "raise_dead" and int(corpse.get("hp",1)) <= 0 and corpse.has("pos") and s.is_free(corpse.pos): places = [corpse.pos]
				if s.Spells.Summons.summons_of(s,owner).filter(func(p): return int(p.get("summoner",-1)) == int(owner.id)).size() >= 3+s.StoneEffects.summon_extra(owner,s): continue
				if not places.is_empty():
					var pet: Dictionary = s.Spells.Summons.summon(s,owner,places[0],str(action[op]))
					if action.has("ticks"):
						var duration: int = int(action.ticks)+s.StoneEffects.modifier(s,"summon_ticks",owner)
						pet.expires_at = int(s.time)+maxi(40,duration*(100+s.StoneEffects.modifier(s,"summon_ticks_percent",owner))/100)
			"notice":
				if succeeded:
					var to: Dictionary = targets[0] if not targets.is_empty() else owner
					if to.has("pos"): s.StoneEffects.proc(s,to.pos,str(action[op]),str(action.get("tone","buff")))
