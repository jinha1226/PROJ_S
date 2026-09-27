extends RefCounted
## Session-scoped automatic soulstones. Legacy effects and monsters keep their engine.
const Essences = preload("res://expedition/progression/essences.gd")
const Conditions = preload("res://expedition/progression/effect_conditions.gd")
const PROFILE := "attack_wait_v1"
const ROLE_NAMES := {"OFFENSE":"공격형","DEFENSE":"방어형","CHAIN":"연쇄형"}
const EVENTS := ["ATTACK","HIT","WAIT"]
const OPS := ["status","status_area","burst","spread","extend","damage","lightning","extra","prepare","bless","attack_prep","aim","threat","ally_guard","heal_self","heal_ally","drain","cleanse","regen","summon","pet_focus","pet_bond","pet_extend","pet_buff","pet_bless","pet_burst","push","attack_bonus"]
const MAX_EVENTS := 512
static var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/attack_wait_effects.json"))

static func person(actor: Dictionary) -> bool:
	return not actor.is_empty() and not bool(actor.get("enemy",false)) and not bool(actor.get("summoned",false))

static func active(actor: Dictionary) -> bool:
	return person(actor) and str(actor.get("combat_profile","legacy")) == PROFILE

static func enable(s, profile: String) -> bool:
	if profile not in ["legacy",PROFILE]: return false
	s.combat_profile = profile
	for actor in s.party+s.npcs+s.roster:
		if not person(actor): continue
		actor.combat_profile = profile
		actor.erase("aw_state")
		Essences.sync_spells(actor)
		s.StatSheet.refresh_pools(s,actor)
	return true

static func effect_id(stone: String) -> String:
	var legacy: String = str(Essences.row(stone).get("effect",Essences.base_of(stone)))
	var variant: String = Essences.variant_element(stone)
	return str(data.variants.get(variant,{}).get(legacy,data.bindings.get(legacy,data.bindings.get(Essences.base_of(stone),""))))

## Only authored variants, rather than six copies of every stone.
static func catalog() -> Array:
	var ids: Array = Essences.catalog()
	for element in data.variants:
		for stone in Essences.catalog():
			var legacy: String = str(Essences.row(str(stone)).get("effect",Essences.base_of(str(stone))))
			if data.variants[element].has(legacy): ids.append(str(stone)+"@"+str(element))
	return ids

static func row(stone: String) -> Dictionary:
	return data.effects.get(effect_id(stone),{})

static func effects(actor: Dictionary) -> Array:
	var result: Array = []
	for stone in Essences.equipped(actor):
		var id := effect_id(str(stone))
		if not id.is_empty() and id not in result: result.append(id)
	result.sort()
	return result

static func state(actor: Dictionary) -> Dictionary:
	return actor.get_or_add("aw_state",{"preps":{},"attack_preps":{},"cooldowns":{},"uses":{},"encounters":[],"foes":[],"waits":0,"aim":0,"hits":{}})

static func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x-b.x),absi(a.y-b.y))

static func hostile(s, a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty() or int(a.id) == int(b.id): return false
	# Dungeon strangers are not allies merely because both are side zero.
	if bool(a.get("summoned",false)):
		var owner: Dictionary = s.actor_by_id(int(a.get("summoner",-1)))
		if not owner.is_empty(): return hostile(s,owner,b)
	if bool(b.get("summoned",false)):
		var owner: Dictionary = s.actor_by_id(int(b.get("summoner",-1)))
		if not owner.is_empty(): return hostile(s,a,owner)
	if bool(a.get("enemy",false)) and s.wanderer(b): return true
	if bool(b.get("enemy",false)) and s.wanderer(a): return true
	return s.side_of(a) != s.side_of(b)

static func allied(s, a: Dictionary, b: Dictionary) -> bool:
	if int(a.id) == int(b.id): return true
	if a in s.party and b in s.party: return true
	if bool(b.get("summoned",false)): return int(b.get("summoner",-1)) == int(a.id)
	if bool(a.get("summoned",false)): return int(a.get("summoner",-1)) == int(b.id)
	return s.wanderer(a) and s.wanderer(b) and int(a.get("partner",-1)) == int(b.id)

static func line(s, a: Vector2i, b: Vector2i, reach: int) -> bool:
	return s.Floor.MonsterAI.line(s,a,b,reach)

static func valid(s, owner: Dictionary, target: Dictionary, centre: Vector2i, radius: int) -> bool:
	if s.free_movement:
		if int(target.get("hp",0)) <= 0 or not hostile(s,owner,target): return false
		if owner == s.party[0] and not s.floor_state.visible.has(target.pos): return false
		var origin: Vector2 = s.Free.point(s,centre,owner)
		return s.Free.sees(s,origin,s.Free.position(target),radius) and s.Free.sees(s,s.Free.position(owner),s.Free.position(target),6)
	if int(target.get("hp",0)) <= 0 or not hostile(s,owner,target) or distance(centre,target.pos) > radius: return false
	if owner == s.party[0] and not s.floor_state.visible.has(target.pos): return false
	# NPCs use their own perception; a hop cannot reveal a whole floor.
	if owner != s.party[0] and not line(s,owner.pos,target.pos,6): return false
	return line(s,centre,target.pos,radius)

static func targets(s, owner: Dictionary, centre: Vector2i, radius: int, count: int = 0) -> Array:
	var result: Array = (s.party+s.npcs+s.enemies).filter(func(t): return valid(s,owner,t,centre,radius))
	result.sort_custom(func(a,b):
		var da := distance(centre,a.pos); var db := distance(centre,b.pos)
		return da < db if da != db else int(a.id) < int(b.id))
	if count > 0: return result.slice(0,count)
	# All-target area effects have stable ID order, not absorption order.
	result.sort_custom(func(a,b): return int(a.id) < int(b.id))
	return result

static func allies(s, owner: Dictionary, radius: int) -> Array:
	var result: Array = (s.party+s.npcs).filter(func(t): return int(t.hp) > 0 and allied(s,owner,t) and ((s.Free.gap(owner,t) <= radius and s.Free.sees(s,s.Free.position(owner),s.Free.position(t),radius)) if s.free_movement else (distance(owner.pos,t.pos) <= radius and line(s,owner.pos,t.pos,radius))))
	result.sort_custom(func(a,b):
		var ha := float(a.hp)/maxi(1,int(a.max_hp)); var hb := float(b.hp)/maxi(1,int(b.max_hp))
		return ha < hb if ha != hb else int(a.id) < int(b.id))
	return result

static func ready(s, owner: Dictionary, id: String, r: Dictionary) -> bool:
	var st: Dictionary = owner.get("aw_state",{})
	if int(st.get("cooldowns",{}).get(id,0)) > int(s.time): return false
	if r.has("uses") and int(st.get("uses",{}).get(id,0)) >= int(r.uses): return false
	if r.get("combat",false) and not encounter_active(s,owner): return false
	return true

static func encounter_foes(s, owner: Dictionary) -> Array:
	return (s.party+s.npcs+s.enemies).filter(func(t): return int(t.hp) > 0 and hostile(s,owner,t) and line(s,owner.pos,t.pos,6))

static func encounter_active(s, owner: Dictionary) -> bool:
	if not encounter_foes(s,owner).is_empty(): return true
	return owner.get("aw_state",{}).get("foes",[]).any(func(id):
		var foe: Dictionary = s.actor_by_id(int(id)); return not foe.is_empty() and int(foe.hp) > 0)

static func track_encounter(s, owner: Dictionary) -> void:
	var st := state(owner)
	if int(st.get("depth",-1)) != int(s.depth):
		st.depth = int(s.depth); st.uses = {}; st.foes = []; st.encounters = []
	var seen: Array = encounter_foes(s,owner)
	var ids: Array = seen.map(func(t): return int(t.id))
	var remaining: bool = st.foes.any(func(id):
		var foe: Dictionary = s.actor_by_id(int(id)); return not foe.is_empty() and int(foe.hp) > 0)
	if not remaining and not ids.is_empty() and not ids.any(func(id): return id in st.encounters):
		st.uses = {}; st.foes = []
	for id in ids:
		if id not in st.foes: st.foes.append(id)
		if id not in st.encounters: st.encounters.append(id)
	if not remaining and ids.is_empty(): st.waits = 0

static func begin(s, owner: Dictionary, kind: String, intentional: bool = true) -> void:
	if not active(owner): return
	var st := state(owner)
	track_encounter(s,owner)
	st.preps = {}
	# Successful normal action releases shared CC immunity; forced skips do not.
	if intentional and not owner.get("statuses",{}).has("freeze") and not owner.get("statuses",{}).has("stun"): owner.erase("aw_cc_locked")
	if kind != "WAIT" or not intentional: st.waits = 0
	if kind in ["MOVE","SWAP"]: st.aim = 0
	if not intentional: st.aim = 0; st.attack_preps = {}

static func skip(owner: Dictionary) -> void:
	if not active(owner): return
	var st := state(owner)
	st.preps = {}; st.waits = 0; st.aim = 0; st.attack_preps = {}

static func push(s, event: String, owner: Dictionary, ctx: Dictionary = {}) -> void:
	if not active(owner) or event not in EVENTS: return
	s.aw_sequence += 1
	s.aw_queue.append({"event":event,"owner":owner,"ctx":ctx.duplicate(),"root":int(s.action_serial),"id":int(s.aw_sequence),"parent":int(s.aw_parent)})
	if s.aw_hold == 0 and not s.aw_running: drain(s)

static func fire(s, event: String, ctx: Dictionary) -> void:
	if event not in EVENTS: return
	for owner in s.StoneEffects.EffectEngine.owners(s,event,ctx):
		var facts := ctx.duplicate()
		if event in ["KILL","PET_KILL"] and not hostile(s,owner,ctx.get("victim",ctx.get("target",{}))): continue
		if event in ["DODGE","BLOCK"]:
			facts.target = ctx.get("attacker",ctx.get("source",{}))
			facts.victim_statuses = facts.target.get("statuses",{}).duplicate(true)
		push(s,event,owner,facts)

static func drain(s) -> void:
	if s.aw_running: return
	s.aw_running = true
	var handled := 0
	while not s.aw_queue.is_empty():
		var e: Dictionary = s.aw_queue.pop_front()
		handled += 1
		if handled > MAX_EVENTS:
			s.aw_overflows += 1; s.aw_queue.clear(); push_error("Automatic soulstone event budget exceeded"); break
		var owner: Dictionary = e.owner
		if int(owner.get("hp",0)) <= 0: continue
		s.aw_parent = int(e.id)
		resolve(s,owner,str(e.event),e.ctx,e)
	s.aw_parent = 0; s.aw_running = false

static func resolve(s, owner: Dictionary, event: String, ctx: Dictionary, e: Dictionary) -> void:
	var ids := effects(owner)
	# Two shatter stones do not consume the same frozen target twice.
	if "ice_crush" in ids and conditions(s,owner,data.effects.ice_crush,ctx): ids.erase("ice_shatter")
	ids.sort_custom(func(a,b):
		var ra: Dictionary = data.effects[a]; var rb: Dictionary = data.effects[b]
		var pa := 1 if str(ra.role) == "CHAIN" else 0; var pb := 1 if str(rb.role) == "CHAIN" else 0
		return pa < pb if pa != pb else str(a) < str(b))
	var chain_ctx: Dictionary = {}
	for id in ids:
		var r: Dictionary = data.effects[id].duplicate(true)
		r.id = str(id)
		if str(r.event) != event or not ready(s,owner,str(id),r): continue
		if str(r.role) == "CHAIN" and chain_ctx.is_empty():
			chain_ctx = ctx.duplicate()
			# Copy only the condition snapshot, keep real actors for mutation.
			chain_ctx.merge(ctx,true)
			chain_ctx.chain_statuses = ctx.get("target",{}).get("statuses",ctx.get("victim_statuses",{})).duplicate(true)
		var facts: Dictionary = chain_ctx if str(r.role) == "CHAIN" else ctx
		if not conditions(s,owner,r,facts): continue
		var gate := "%d:%d:%s:%s" % [int(e.root),int(owner.id),str(id),event]
		if int(s.aw_fired.get(gate,0)) >= int(r.limit): continue
		# Reserve before mutation; only real success spends cooldown and uses.
		s.aw_fired[gate] = int(s.aw_fired.get(gate,0))+1
		var previous: Dictionary = s.effect_source
		s.effect_source = {"owner":int(owner.id),"effect":"aw:"+str(id),"policy":PROFILE}
		var success := execute(s,owner,r,facts)
		s.effect_source = previous
		if not success: continue
		var st := state(owner)
		if r.has("cooldown"): st.cooldowns[id] = int(s.time)+int(r.cooldown)
		if r.has("uses"): st.uses[id] = int(st.uses.get(id,0))+1
		s.EffectReport.note(s,int(owner.id),"aw:"+str(id),"procs",1)
		s.aw_trace.append({"root":e.root,"parent":e.parent,"event_id":e.id,"owner":owner.id,"effect":id,"event":event,"target":int(ctx.get("target",{}).get("id",-1))})
		if s.aw_trace.size() > 128: s.aw_trace.pop_front()
		s.StoneEffects.proc(s,owner.pos,str(r.name),"buff",str(r.vfx))

static func conditions(s, owner: Dictionary, r: Dictionary, ctx: Dictionary) -> bool:
	var target: Dictionary = ctx.get("target",ctx.get("victim",{}))
	var statuses: Dictionary = ctx.get("chain_statuses",target.get("statuses",ctx.get("victim_statuses",{})))
	if int(target.get("hp",1)) <= 0: statuses = ctx.get("victim_statuses",statuses)
	for name in r.get("requires",[]):
		if not statuses.has(name): return false
	for name in r.get("self_requires",[]):
		if not owner.get("statuses",{}).has(name) and not ctx.get("self_statuses",{}).has(name): return false
	if r.get("needs_pet",false) and s.Spells.Summons.summons_of(s,owner).is_empty(): return false
	return true

static func status(s, owner: Dictionary, target: Dictionary, name: String, ticks: int) -> bool:
	if target.is_empty() or int(target.get("hp",0)) <= 0: return false
	var until: int = int(target.get("statuses",{}).get(name,0))
	if until >= int(s.time)+ticks: return false
	return s.Statuses.apply(s,target,name,ticks,owner)

static func damage(s, owner: Dictionary, target: Dictionary, r: Dictionary, amount: int = -1, form: String = "MOBILE_EXTRA") -> int:
	if target.is_empty() or int(target.get("hp",0)) <= 0: return 0
	if not bool(owner.get("enemy",false)) and bool(target.get("enemy",false)): s.Hunt.record(owner,int(target.id))
	return s.CombatRules.damage(s,owner,target,maxi(1,int(r.get("damage",3)) if amount < 0 else amount),str(r.get("element","physical")),0,form)

static func prepare(s, owner: Dictionary, key: String, r: Dictionary) -> bool:
	state(owner).preps[key] = {"rule":r.duplicate(true),"effects":effects(owner),"owner":int(owner.id)}
	return true

static func execute(s, owner: Dictionary, r: Dictionary, ctx: Dictionary) -> bool:
	var target: Dictionary = ctx.get("target",ctx.get("victim",{}))
	var st := state(owner)
	var ticks := int(r.get("ticks",300))
	match str(r.op):
		"status":
			var applied := status(s,owner,target,str(r.status),ticks)
			if r.has("damage") and int(target.get("hp",0)) > 0:
				var dealt := damage(s,owner,target,r)
				if dealt > 0 and r.get("direct_element",false): ctx.get_or_add("direct_elements",[]).append(str(r.element))
				applied = applied or dealt > 0
			return applied
		"status_area":
			var success := false
			for foe in targets(s,owner,owner.pos,int(r.radius),int(r.get("count",0))):
				success = status(s,owner,foe,str(r.status),ticks) or success
				if int(r.get("damage",0)) > 0: success = damage(s,owner,foe,r) > 0 or success
			return success
		"burst", "pet_burst":
			if str(r.op) == "pet_burst":
				var pet: Dictionary = ctx.get("pet",{})
				if not bool(ctx.get("died",false)) or str(pet.get("summon_kind","")) != "skeleton" or not bool(ctx.get("hostile_death",false)): return false
				target = pet
			if target.is_empty(): return false
			var success := false
			for foe in targets(s,owner,target.pos,int(r.radius)):
				success = damage(s,owner,foe,r) > 0 or success
				if r.has("status"): status(s,owner,foe,str(r.status),ticks)
			return success
		"spread", "extend":
			if target.is_empty(): return false
			var worn: Dictionary = ctx.get("chain_statuses",ctx.get("victim_statuses",target.get("statuses",{})))
			var duration := maxi(0,int(worn.get(r.status,0))-int(s.time))
			if duration <= 0: return false
			var success := false
			var count: int = int(r.get("count",0))
			var foes := targets(s,owner,target.pos,int(r.radius))
			foes = foes.filter(func(t): return int(t.id) != int(target.id))
			foes.sort_custom(func(a,b): return distance(target.pos,a.pos) < distance(target.pos,b.pos) if distance(target.pos,a.pos) != distance(target.pos,b.pos) else int(a.id) < int(b.id))
			if count > 0: foes = foes.slice(0,count)
			for foe in foes:
				if str(r.op) == "extend":
					if foe.statuses.has(r.status): foe.statuses[r.status] = int(foe.statuses[r.status])+int(r.extend); success = true
				else: success = status(s,owner,foe,str(r.status),duration) or success
			return success
		"damage":
			if r.has("consume"): target.get("statuses",{}).erase(r.consume)
			return damage(s,owner,target,r) > 0
		"lightning":
			if target.is_empty(): return false
			if r.has("consume"): target.get("statuses",{}).erase(r.consume)
			var current: Dictionary = target; var visited: Array = []; var success := false
			for _hop in range(int(r.count)):
				visited.append(int(current.id))
				success = damage(s,owner,current,r) > 0 or success
				var next: Array = targets(s,owner,current.pos,int(r.radius)).filter(func(t): return int(t.id) not in visited)
				next.sort_custom(func(a,b): return distance(current.pos,a.pos) < distance(current.pos,b.pos) if distance(current.pos,a.pos) != distance(current.pos,b.pos) else int(a.id) < int(b.id))
				if next.is_empty(): break
				current = next[0]
			return success
		"extra":
			if target.is_empty() or not valid(s,owner,target,owner.pos,int(s.CombatStats.stats(s,owner).range)): return false
			# An additional attack rolls hit/block normally, but carries no new HIT.
			var attack: Dictionary = s.CombatStats.stats(s,owner)
			s.CombatRules.attack(s,owner,target,maxi(1,int(attack.damage)*int(r.get("damage_percent",35))/100),"MOBILE_EXTRA")
			return true
		"prepare":
			var receiver: Dictionary = target if str(r.event) in ["HEALED","CLEANSED"] and not target.is_empty() else owner
			var key: String = str(r.get("key","guard"))
			prepare(s,receiver,key,r)
			state(receiver).preps[key].owner = int(owner.id)
			state(receiver).preps[key].effects = effects(owner)
			return true
		"bless":
			status(s,owner,owner,"blessing",ticks)
			st.attack_preps.blessing = r.duplicate(true)
			return true
		"attack_prep": st.attack_preps[str(r.get("key","power"))] = r.duplicate(true); return true
		"threat":
			if not encounter_active(s,owner): return false
			st.waits = 1; return true
		"ally_guard":
			var mates := allies(s,owner,int(r.get("radius",2)))
			if str(r.event) == "BLOCK": mates = mates.filter(func(a): return int(a.id) != int(owner.id))
			if int(r.get("count",0)) > 0: mates = mates.slice(0,int(r.count))
			for mate in mates:
				prepare(s,mate,"divine_guard",r)
				state(mate).preps.divine_guard.effects = effects(owner)
				state(mate).preps.divine_guard.owner = int(owner.id)
			return not mates.is_empty()
		"heal_self": return s.StoneEffects.heal(s,owner,int(r.heal),owner) > 0
		"drain": return int(ctx.get("lost",0)) > 0 and s.StoneEffects.heal(s,owner,mini(int(r.cap),maxi(1,int(ctx.lost)*int(r.percent)/100)),owner) > 0
		"heal_ally":
			var mates := allies(s,owner,int(r.radius)).filter(func(t): return int(t.hp) < int(t.max_hp))
			return not mates.is_empty() and s.StoneEffects.heal(s,mates[0],int(r.heal),owner) > 0
		"cleanse":
			for mate in allies(s,owner,int(r.radius)):
				for name in s.Statuses.HARMFUL:
					if not mate.statuses.has(name): continue
					mate.statuses.erase(name); push(s,"CLEANSED",owner,{"target":mate,"status":name}); s.StoneEffects.Vfx.emit(s,"cleanse",mate.pos,owner.pos); return true
			return false
		"regen":
			if int(owner.hp) >= int(owner.max_hp): return false
			st.regen = {"left":int(r.pulses),"heal":int(r.heal),"at":int(s.time)+100,"effect":str(r.get("id",""))}; return true
		"summon":
			var pets: Array = s.Spells.Summons.summons_of(s,owner)
			var cells: Array = s.Spells.Summons.summon_cells(s,owner)
			if pets.size() >= int(r.cap) or cells.is_empty(): return false
			var pet: Dictionary = s.Spells.Summons.summon(s,owner,cells[0],str(r.kind))
			pet.aw_pet = true; pet.aw_guard = bool(r.get("guard",false)); pet.aw_origin_policy = PROFILE
			pet.expires_at = int(s.time)+300
			return true
		"pet_focus":
			var pets: Array = s.Spells.Summons.summons_of(s,owner)
			for pet in pets: pet.aw_focus = int(target.get("id",-1))
			return not pets.is_empty()
		"pet_bond":
			var pet: Dictionary = ctx.get("pet",{})
			if pet.is_empty() or int(st.get("last_target",-1)) != int(target.get("id",-2)): return false
			pet.aw_attack_percent = int(r.percent); return true
		"pet_buff":
			var pets: Array = s.Spells.Summons.summons_of(s,owner)
			for pet in pets: pet.aw_attack_percent = int(r.percent)
			return not pets.is_empty()
		"pet_extend":
			var pets: Array = s.Spells.Summons.summons_of(s,owner)
			for pet in pets: pet.expires_at = mini(int(s.time)+500,int(pet.expires_at)+int(r.extend))
			return not pets.is_empty()
		"pet_bless":
			var pets: Array = s.Spells.Summons.summons_of(s,owner)
			for pet in pets:
				pet.aw_attack_percent = int(r.percent); status(s,owner,pet,"blessing",ticks)
			return not pets.is_empty()
		"push": return shove(s,owner,target,r,ctx)
		"attack_bonus":
			ctx.attack_percent = int(ctx.get("attack_percent",0))+int(r.percent)
			if r.has("consume"): target.statuses.erase(r.consume)
			return true
	return false

static func shove(s, owner: Dictionary, target: Dictionary, r: Dictionary, ctx: Dictionary) -> bool:
	if target.is_empty() or int(target.get("hp",0)) <= 0 or bool(target.get("boss",false)): return false
	if state(target).preps.values().any(func(p): return preparation_valid(s,p) and bool(p.rule.get("push_resist",false))): return false
	if s.free_movement:
		var from: Vector2 = s.Free.position(target)
		var goal: Vector2 = from+(from-s.Free.position(owner)).normalized()
		if s.Free.segment(s,from,goal,s.Free.RADIUS,target,true):
			s.Free.place(target,goal); s.Floor.MonsterAI.interrupt(s,target); return true
		if int(r.get("blocked_damage",0)) > 0: damage(s,owner,target,r,int(r.blocked_damage))
		return false
	var next: Vector2i = target.pos+Vector2i(signi(target.pos.x-owner.pos.x),signi(target.pos.y-owner.pos.y))
	if s.can_step(target.pos,next):
		target.pos = next; s.Floor.MonsterAI.interrupt(s,target)
		push(s,"PUSHED",owner,{"target":target,"ranged":ctx.get("ranged",false)})
		return true
	if s.inside(next) and str(s.tile(next).terrain) == "wall":
		if int(r.get("blocked_damage",0)) > 0: damage(s,owner,target,r,int(r.blocked_damage))
		push(s,"COLLISION",owner,{"target":target}); return true
	return false

static func prepare_attack(s, owner: Dictionary, target: Dictionary, ctx: Dictionary) -> void:
	if not active(owner):
		if bool(owner.get("aw_pet",false)):
			ctx.attack_percent = int(owner.get("aw_attack_percent",0)); owner.erase("aw_attack_percent")
		return
	var st := state(owner)
	ctx.self_statuses = owner.statuses.duplicate(true)
	ctx.moved = bool(owner.get("moved_since_attack",false)); ctx.aim = int(st.aim)
	ctx.attack_percent = int(st.aim)*10 if bool(ctx.get("ranged",false)) else 0
	ctx.preps = st.attack_preps.duplicate(true)
	for prep in st.attack_preps.values():
		if str(prep.get("id","")) in effects(owner): ctx.attack_percent += int(prep.get("percent",0))
	ctx.preps = ctx.preps.duplicate(true)
	for key in ctx.preps.keys():
		if str(ctx.preps[key].get("id","")) not in effects(owner): ctx.preps.erase(key)
	st.aim = 0; st.attack_preps = {}
	# ATTACK modifiers must resolve now, before computing basic damage.
	var e := {"root":int(s.action_serial),"id":0,"parent":0}
	resolve(s,owner,"ATTACK",ctx,e)

static func landed(s, owner: Dictionary, target: Dictionary, ctx: Dictionary) -> void:
	if not active(owner):
		if bool(owner.get("aw_pet",false)) and int(ctx.get("lost",0)) > 0:
			push(s,"PET_HIT",s.actor_by_id(int(owner.get("summoner",-1))),{"target":target,"pet":owner})
		return
	if int(ctx.get("lost",0)) <= 0 or not hostile(s,owner,target): return
	for prep in ctx.get("preps",{}).values():
		if prep.has("status"): status(s,owner,target,str(prep.status),int(prep.get("ticks",300)))
		if prep.get("push",false): shove(s,owner,target,{},ctx)
		if prep.has("extra") and int(target.hp) > 0: execute(s,owner,{"op":"extra","damage_percent":30},ctx)
	ctx.previous_target = int(state(owner).get("last_target",-1))
	push(s,"HIT",owner,ctx)
	state(owner).last_target = int(target.id)

static func preparation_valid(s, p: Dictionary) -> bool:
	var giver: Dictionary = s.actor_by_id(int(p.get("owner",-1)))
	return not giver.is_empty() and int(giver.hp) > 0 and str(p.rule.get("id","")) in effects(giver)

static func modifier(s, key: String, actor: Dictionary) -> int:
	if not active(actor): return 0
	var total := 0
	for p in actor.get("aw_state",{}).get("preps",{}).values():
		if not preparation_valid(s,p) or p.rule.get("ranged_only",false): continue
		total += int(p.rule.get("mods",{}).get(key,0))
	return total

static func incoming(s, target: Dictionary, source: Dictionary, amount: int, hit_form: String) -> int:
	if not active(target) or hit_form not in ["HIT"] or source.is_empty() or not hostile(s,target,source): return amount
	var st := state(target)
	var reduction := 0
	for key in st.preps.keys():
		var p: Dictionary = st.preps[key]
		if not preparation_valid(s,p): st.preps.erase(key); continue
		reduction = maxi(reduction,int(p.rule.get("reduction",0)))
		if p.rule.has("share"):
			var pets: Array = s.Spells.Summons.summons_of(s,target)
			if not pets.is_empty():
				var share := mini(int(pets[0].hp),amount*int(p.rule.share)/100)
				if share > 0: damage(s,source,pets[0],{},share,"MOBILE_SHARE"); amount -= share
			st.preps.erase(key)
	return maxi(0,amount*(100-reduction)/100)

static func struck(s, owner: Dictionary, attacker: Dictionary, ctx: Dictionary) -> void:
	if not active(owner) or int(owner.get("hp",0)) <= 0 or int(ctx.get("lost",0)) <= 0 or attacker.is_empty() or not hostile(s,owner,attacker): return
	var st := state(owner)
	for key in st.preps.keys():
		var prep: Dictionary = st.preps[key]; var r: Dictionary = prep.rule
		if not r.has("reaction"): continue
		if not preparation_valid(s,prep): st.preps.erase(key); continue
		if not valid(s,owner,attacker,owner.pos,int(r.get("reach",1))): continue
		st.preps.erase(key)
		var reaction: Dictionary = r.duplicate(true); reaction.op = str(r.reaction)
		var previous: Dictionary = s.effect_source; s.effect_source = {"owner":int(owner.id),"effect":"aw:"+key,"policy":PROFILE}
		if str(r.reaction) == "reflect": damage(s,owner,attacker,r,maxi(1,int(ctx.lost)*int(r.percent)/100),"MOBILE_REFLECT")
		else: execute(s,owner,reaction,{"target":owner if str(r.reaction) == "burst" else attacker})
		s.effect_source = previous
	push(s,"STRUCK",owner,{"target":attacker,"attacker":attacker,"lost":ctx.lost})

static func ranged_dodge(s, target: Dictionary, source: Dictionary) -> int:
	if not active(target) or distance(source.pos,target.pos) <= 1: return 0
	var amount := 0
	for p in target.get("aw_state",{}).get("preps",{}).values():
		if p.rule.get("ranged_only",false) and preparation_valid(s,p): amount += int(p.rule.get("mods",{}).get("dodge",0))
	return amount

## A mobile-origin confusion impairs aim without changing allegiance or
## manufacturing a forced WAIT. Legacy confusion keeps its existing contract.
static func confusion_penalty(actor: Dictionary) -> int:
	if not actor.get("statuses",{}).has("confuse"): return 0
	return 20 if str(actor.get("status_sources",{}).get("confuse",{}).get("policy","legacy")) == PROFILE else 0

static func attempted(target: Dictionary) -> void:
	if not active(target): return
	var preps: Dictionary = state(target).preps
	for key in preps.keys():
		if preps[key].rule.get("on_attempt",false): preps.erase(key)

static func tick(s) -> void:
	for actor in s.party+s.npcs:
		if not active(actor): continue
		if int(actor.hp) <= 0: skip(actor); continue
		var st := state(actor); var regen: Dictionary = st.get("regen",{})
		if not regen.is_empty() and int(regen.at) <= int(s.time):
			if str(regen.effect) in effects(actor):
				var previous: Dictionary = s.effect_source
				s.effect_source = {"owner":int(actor.id),"effect":"aw:"+str(regen.effect),"policy":PROFILE}
				s.StoneEffects.heal(s,actor,int(regen.heal),actor)
				s.effect_source = previous
			regen.left -= 1; regen.at = int(s.time)+100
			if int(regen.left) <= 0: st.erase("regen")
		if not encounter_active(s,actor) or "defense_threat" not in effects(actor): st.waits = 0

static func threat(s, observer: Dictionary, target: Dictionary) -> int:
	if not active(target) or int(target.hp) <= 0 or not line(s,observer.pos,target.pos,5): return 0
	if "defense_threat" not in effects(target): return 0
	return int(data.effects.defense_threat.get("amount",9)) if int(target.get("aw_state",{}).get("waits",0)) > 0 else 0

## Pure prediction: no state(), RNG or target mutation in UI/AI queries.
static func estimate(s, actor: Dictionary, kind: String, target: Dictionary = {}) -> int:
	if not active(actor): return 0
	var value := 0
	var event := "WAIT" if kind == "WAIT" else "HIT" if kind == "ATTACK" else ""
	for id in effects(actor):
		var r: Dictionary = data.effects[id]
		if str(r.event) != event or not ready(s,actor,str(id),r): continue
		var ctx := {"target":target,"ranged":not target.is_empty() and distance(actor.pos,target.pos) > 1}
		if not conditions(s,actor,r,ctx): continue
		if str(r.op) == "status_area": value += targets(s,actor,actor.pos,int(r.radius),int(r.get("count",0))).size()*5
		elif str(r.op) == "heal_ally":
			var injured := allies(s,actor,int(r.radius)).filter(func(t): return int(t.hp) < int(t.max_hp))
			if not injured.is_empty(): value += mini(int(r.heal),int(injured[0].max_hp)-int(injured[0].hp))*2
		elif str(r.op) == "summon":
			if s.Spells.Summons.summons_of(s,actor).size() < int(r.cap) and not s.Spells.Summons.summon_cells(s,actor).is_empty(): value += 12
		elif str(r.op) == "prepare":
			if not encounter_active(s,actor): continue
			value += int(r.get("reduction",0))/5
			var reaction_value := 10 if str(r.get("status","")) == "stun" else int(r.get("damage",3))
			if r.has("reaction"): value += reaction_value
			value += int(r.get("mods",{}).get("armour",0))+int(r.get("mods",{}).get("dodge",0))/5
		else: value += 4
	return mini(45,value)

static func summary(actor: Dictionary) -> String:
	var lines: Array = []
	for group in [["공격",["ATTACK","HIT"]],["대기",["WAIT"]]]:
		var texts: Array = []
		for id in effects(actor):
			var r: Dictionary = data.effects[id]
			if str(r.event) in group[1]: texts.append(str(r.text))
		if not texts.is_empty(): lines.append(str(group[0])+" · "+" / ".join(texts))
	return "\n".join(lines)

static func validate() -> Array:
	var errors: Array = []
	for stone in Essences.catalog():
		if row(str(stone)).is_empty(): errors.append("unmapped stone: "+str(stone))
	for id in data.effects:
		var r: Dictionary = data.effects[id]
		if str(r.get("event","")) not in EVENTS: errors.append(str(id)+": event")
		if str(r.get("op","")) not in OPS: errors.append(str(id)+": operation")
		if str(r.get("role","")) not in ROLE_NAMES: errors.append(str(id)+": role")
		if int(r.get("limit",0)) < 1: errors.append(str(id)+": unbounded rule")
		if str(r.get("text","")) == "": errors.append(str(id)+": label")
		var prerequisites: int = r.get("requires",[]).size()+r.get("self_requires",[]).size()+int(r.get("needs_pet",false))
		if prerequisites > 1 or (str(r.role) == "CHAIN") != (prerequisites == 1): errors.append(str(id)+": simple prerequisite")
		for key in ["hp_below","moved","ranged","ranged_only","aimed","form","damage_element","min_distance","monster","needs_effect","same_target","chance","requires_before","on_attempt"]:
			if r.has(key): errors.append(str(id)+": retired condition "+str(key))
	return errors
