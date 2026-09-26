extends RefCounted
## Only effects whose ordering/state is specific to the existing combat core.
const Stacks = preload("res://expedition/progression/stacks.gd")
const NAMES := ["revive_once","second_shot","counter","reflect","cancel_status","leech_prepare","gnoll_rage","ambush","wraith_kill"]

static func run(s, code: String, owner: Dictionary, rule: Dictionary, ctx: Dictionary) -> void:
	var other: Dictionary = ctx.get("target",{})
	match code:
		"revive_once":
			if bool(owner.get("revived",false)) or int(ctx.get("amount",0)) < int(owner.get("hp",0)): return
			if not s.Reactions.once(s,owner,"REVIVE"): return
			owner.revived = true; owner.hp = maxi(1,int(owner.max_hp)*int(rule.get("args",{}).get("percent",30))/100)
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
