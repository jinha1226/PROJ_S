extends RefCounted
## Only effects whose ordering/state is specific to the existing combat core.
const Stacks = preload("res://expedition/progression/stacks.gd")
const NAMES := ["revive_once","second_shot","counter","reflect","cancel_status","leech_prepare","gnoll_rage","ambush","wraith_kill","part_special","immune_poison","gear_special"]

static func run(s, code: String, owner: Dictionary, rule: Dictionary, ctx: Dictionary) -> void:
	var other: Dictionary = ctx.get("target",{})
	match code:
		"gear_special": gear_special(s,owner,ctx,str(rule.get("args",{}).get("effect","")))
		"part_special": part_special(s,owner,ctx,str(rule.get("args",{}).get("effect","")))
		"immune_poison": ctx.cancelled = true
		"revive_once":
			if bool(owner.get("revived",false)) or int(ctx.get("amount",0)) < int(owner.get("hp",0)): return
			if not s.Reactions.once(s,owner,"REVIVE"): return
			var before: int = int(owner.hp)
			owner.revived = true; owner.hp = maxi(1,int(owner.max_hp)*int(rule.get("args",{}).get("percent",30))/100)
			if not s.effect_source.is_empty(): s.EffectReport.note(s,int(s.effect_source.owner),str(s.effect_source.effect),"heal",maxi(0,int(owner.hp)-before))
			ctx.amount = 0; s.StoneEffects.proc(s,owner.pos,"부활!","heal")
		"second_shot": s.StoneEffects.second_shot(s,owner,other)
		"counter":
			other = ctx.get("attacker",{})
			if other.is_empty() or not s.StoneEffects.chance(s,owner,other,"counter",25) or not s.Reactions.once(s,owner,"COUNTER"): return
			var amount: int = maxi(1,int(s.CombatStats.stats(s,owner).damage)*60/100)
			s.StoneEffects.proc(s,owner.pos,"반격!","buff"); s.message("%s 반격" % str(owner.get("name","")))
			s.CombatRules.damage(s,owner,other,amount,"physical",0,s.Reactions.COUNTER_FORM)
		"reflect":
			other = ctx.get("attacker",{})
			if int(other.get("hp",0)) <= 0 or int(ctx.get("lost",0)) <= 0: return
			s.StoneEffects.proc(s,owner.pos,"반사!","buff")
			s.damage(other,maxi(1,int(ctx.lost)*30/100),int(owner.id),"RETALIATE")
		"cancel_status":
			if s.StoneEffects.chance(s,ctx.get("source",{}),owner,"shed",50):
				ctx.cancelled = true
				if owner.has("pos"): s.StoneEffects.proc(s,owner.pos,"면역!","buff")
		"leech_prepare":
			var held: Dictionary = owner.get("latch",{})
			var count := 0
			if int(held.get("target",-1)) == int(other.get("id",-2)):
				count = mini(4,Stacks.count(owner,"latch",int(s.time))+1)
				if count > int(held.get("stacks",0)): s.StoneEffects.proc(s,other.pos,"+15%","buff")
			owner.latch = {"target":int(other.get("id",-1)),"stacks":count}
			Stacks.clear(owner,"latch"); Stacks.add(owner,"latch",count,4,"battle",int(s.time))
			ctx.attack_percent = int(ctx.get("attack_percent",0))+15*count
		"gnoll_rage":
			var active: bool = int(owner.hp)*2 <= int(owner.max_hp)
			if active and not bool(owner.get("raging",false)): s.StoneEffects.proc(s,owner.pos,"분노!","buff")
			owner.raging = active
		"ambush":
			ctx.amount = int(ctx.get("amount",0))*2
			s.StoneEffects.proc(s,other.pos,"기습!","buff")
		"wraith_kill":
			if not other.has("pos"): return
			for foe in s.party+s.npcs+s.enemies:
				if int(foe.hp) <= 0 or s.side_of(foe) == s.side_of(owner) or maxi(absi(foe.pos.x-other.pos.x),absi(foe.pos.y-other.pos.y)) > 2: continue
				if s.Statuses.apply(s,foe,"confuse",100,owner): s.StoneEffects.proc(s,foe.pos,"혼란!","debuff")

## Effects needing a position snapshot, an overflow pool, or a delayed event.
static func part_special(s, owner: Dictionary, ctx: Dictionary, id: String) -> void:
	var target: Dictionary = ctx.get("target",{})
	var attacker: Dictionary = ctx.get("attacker",{})
	match id:
		"ARCHER_KNUCKLE":
			if not owner.has("pos") or not target.has("pos"): return
			var delta: Vector2i = target.pos-owner.pos
			var behind: Vector2i = target.pos+Vector2i(signi(delta.x),signi(delta.y))
			var foe: Dictionary = s.at(behind)
			if not foe.is_empty() and s.side_of(foe) != s.side_of(owner): s.CombatRules.damage(s,owner,foe,maxi(1,int(ctx.get("lost",0))/2),"physical",0,s.Reactions.EXTRA_FORM)
		"SHIELD_HIDE":
			if not attacker.is_empty(): s.CombatRules.damage(s,owner,attacker,maxi(1,int(s.CombatStats.stats(s,owner).damage)*60/100),"physical",0,s.Reactions.COUNTER_FORM)
		"SHIELD_HEART": wound_roll(s,owner,attacker,"IMPACT")
		"HOB_HIDE":
			owner.hp = maxi(1,int(owner.hp)-maxi(1,int(owner.max_hp)*2/100))
			ctx.amount = int(ctx.get("amount",0))*130/100
		"ORC_HIDE": s.CombatRules.damage(s,owner,target,(2+s.StoneEffects.modifier(s,"bleed_tick",owner,{"target":target}))*3,"physical",0,s.Reactions.EXTRA_FORM)
		"BEETLE_WING":
			owner.get_or_add("effect_mods",{})[id] = {"mods":{"armour":s.StoneEffects.EffectEngine.Conditions.near(s,owner,false).size()*2},"until":int(s.time)+100}
		"TOAD_TONGUE":
			var power: Dictionary = target.get_or_add("status_power",{})
			power.poison_bonus = mini(4+s.StoneEffects.modifier(s,"stack_max.poison",owner),int(power.get("poison_bonus",0))+1)
		"FROST_CLAW":
			for foe in s.party+s.npcs+s.enemies:
				if foe.hp > 0 and s.side_of(foe) != s.side_of(owner) and s.distance(foe.pos,target.pos) <= 1 and s.StoneEffects.chance(s,owner,foe,"frost_spread",20+s.StoneEffects.modifier(s,"kill_chance",owner)): s.Statuses.apply(s,foe,"freeze",100,owner)
		"GHOUL_JAW": s.effect_delays.append({"at":int(s.time)+100,"source":int(owner.id),"pos":target.pos,"damage":maxi(1,int(target.max_hp)/10),"radius":1,"side":s.side_of(owner),"report_source":s.effect_source.duplicate()})
		"VAMPIRE_HEART":
			owner.blood_ward = mini(int(owner.max_hp)*20/100,int(owner.get("blood_ward",0))+int(ctx.get("overheal",0)))
			owner.blood_ward_until = int(s.time)+300
		"GRAVEKEEPER_BONE":
			var pet: Dictionary = ctx.get("pet",{})
			if pet.has("pos"): s.effect_delays.append({"at":int(s.time),"source":int(owner.id),"pos":pet.pos,"damage":10,"radius":1,"side":s.side_of(owner),"report_source":s.effect_source.duplicate()})

static func wound_roll(s, owner: Dictionary, target: Dictionary, form: String) -> void:
	if target.is_empty() or int(target.get("hp",0)) <= 0: return
	var chance: int = s.Forms.wound_chance(form,target)+s.StoneEffects.modifier(s,"wound_chance."+form,owner)
	if not s.StoneEffects.chance(s,owner,target,"extra_wound",chance): return
	s.Forms.apply_wound(s,owner,target,form)

static func delayed(s) -> void:
	var due: Array = s.effect_delays.filter(func(e): return int(e.at) <= int(s.time))
	s.effect_delays = s.effect_delays.filter(func(e): return int(e.at) > int(s.time))
	for event in due:
		var previous: Dictionary = s.effect_source
		s.effect_source = event.get("report_source",{})
		for target in (s.party+s.npcs+s.enemies).duplicate():
			if target.hp > 0 and s.side_of(target) != event.side and s.distance(event.pos,target.pos) <= int(event.radius): s.CombatRules.damage(s,s.actor_by_id(int(event.source)),target,int(event.damage),"physical",0,s.Reactions.EXTRA_FORM)

		s.effect_source = previous

static func gear_special(s, owner: Dictionary, ctx: Dictionary, id: String) -> void:
	match id:
		"GEAR_COMP_CRISIS":
			if owner.get("gear_crisis_used",false): return
			owner.gear_crisis_used = true; s.Statuses.apply(s,owner,"ward",200,owner)
		"GEAR_COMP_SHOVE":
			var foes: Array = s.StoneEffects.EffectEngine.Conditions.near(s,owner,false)
			foes.sort_custom(func(a,b): return int(a.id) < int(b.id))
			if not foes.is_empty(): s.StoneEffects.EffectEngine.Actions.run(s,owner,[{"push":1}],{"target":foes[0]})
		"GEAR_COMP_OPENING": owner.get_or_add("effect_mods",{})[id] = {"mods":{"speed":30},"until":int(s.time)+100}
		"GEAR_COMP_CLEANSE": ctx.cancelled = true
		"UNRAND_SHIELD": wound_roll(s,owner,ctx.get("attacker",{}),"IMPACT")
		"UNRAND_ORB": owner.repeat_reaction = true
		"COST_HEX":
			if s.StoneEffects.EffectEngine.Conditions.harmful_count(s,ctx.get("target",{})) < 4: ctx.amount = int(ctx.get("amount",0))*85/100
		"UNRAND_PLAGUE":
			s.StoneEffects.EffectEngine.Actions.run(s,owner,[{"burst":2,"damage":4,"element":"poison"},{"spread_status":"poison","radius":2,"ticks":300}],ctx)

static func share_damage(s, target: Dictionary, source: Dictionary, amount: int) -> int:
	if amount <= 0: return amount
	for guard in s.StoneEffects.allies_beside(s,target):
		var percent: int = s.StoneEffects.modifier(s,"share_damage",guard)
		if percent <= 0: continue
		var split: int = amount*mini(100,percent)/100
		if split > 0: s.CombatRules.damage(s,source,guard,split,"physical",0,s.Reactions.EXTRA_FORM)
		return amount-split
	return amount
