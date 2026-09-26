extends RefCounted
## The statuses an actor wears: what they stop, how a spell hangs one, and the
## boundary tick that bites and then drops the ones whose clock has run out.
## `statuses` keeps the clock; anything a status needs beyond that lives in
## `status_power`, which this file writes and clears together with the clock.
const Rules = preload("res://expedition/combat/combat_rules.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
const StoneEffects = preload("res://expedition/progression/stone_effects.gd")
const Reactions = preload("res://expedition/combat/reactions.gd")
const Forms = preload("res://expedition/combat/forms.gd")
const HARMFUL := ["confuse","slow","freeze","bind","burn","weak","brittle","distort","vulnerable","dominate","bleed","poison","taunted","stun","fracture","exposed"]

## What a spell's own burn does per boundary tick, told apart from the single
## point the fire mastery's burn has always done.
const BURN_DAMAGE := 4

## 빙결 and 속박 stop the feet; only 빙결 also stops the arms.
static func blocks(actor: Dictionary, kind: String) -> bool:
	var statuses: Dictionary = actor.get("statuses",{})
	if statuses.has("stun"): return true
	if kind == "MOVE": return statuses.has("freeze") or statuses.has("bind") or statuses.has("shield_stance")
	if kind in ["ATTACK","RESCUE"]: return statuses.has("freeze")
	return false

## A status a spell hangs on somebody. `statuses` keeps the clock; anything the
## status needs to know beyond that goes in `status_power`, which the scheduler
## reads and drops when the status runs out.
static func resisted_ticks(s, victim: Dictionary, status: String, ticks: int) -> int:
	if status not in TagSets.WILL_STATUSES: return ticks
	var will: int = maxi(0,StatSheet.value(s,victim,"res_will"))
	return ticks*(100-will)/100

static func apply(s, victim: Dictionary, status: String, ticks: int, source: Dictionary = {}) -> bool:
	if status in HARMFUL and victim.get("statuses",{}).has("immune"): return false
	ticks = resisted_ticks(s,victim,status,ticks)
	if ticks <= 0 or StoneEffects.shed(s,victim,status,source): return false
	var already: bool = victim.get("statuses",{}).has(status)
	victim.statuses[status] = s.time+ticks
	victim.get_or_add("status_sources",{})[status] = {"id":int(source.get("id",-1)),"depth":int(s.depth)}
	if status == "burn": victim.get_or_add("status_power",{})["burn"] = BURN_DAMAGE
	if status in HARMFUL:
		StoneEffects.fire(s,"STATUS_GIVEN",{"source":source,"target":victim,"victim":victim,"status":status,"status_already":already})
	Reactions.status_react(s,victim,source,"","STATUS")
	return true

## One boundary tick of every status in play: the expired ones go, the ones
## that bite bite.
static func tick(s) -> void:
	for actor in s.party + s.npcs + s.enemies:
		if actor.hp <= 0: continue
		var payload: Dictionary = actor.get("status_power",{})
		var sources: Dictionary = actor.get("status_sources",{})
		for status in actor.get("statuses",{}).keys():
			var until: int = int(actor.statuses[status])
			if until < s.time:
				if status == "furnace": furnace_burst(s,actor)
				actor.statuses.erase(status); payload.erase(status); sources.erase(status); continue
			var was: String = Forms.begin(s,Forms.of_dot(status))
			var lost := 0
			var origin: Dictionary = sources.get(status,{})
			var source: Dictionary = s.actor_by_id(int(origin.get("id",-1))) if int(origin.get("depth",-1)) == int(s.depth) else {}
			if status == "bleed": lost = Rules.damage(s,{},actor,2+StoneEffects.modifier(s,"bleed_tick",source,{"target":actor}),"physical")
			# A spell's burn says how hard it bites; the old mastery burn keeps
			# the single point it always did.
			elif status == "burn": lost = Rules.damage(s,{},actor,int(payload.get("burn",1)),"fire")
			elif status == "poison": lost = Rules.damage(s,{},actor,2+StoneEffects.modifier(s,"poison_tick",source,{"target":actor}),"poison")
			if lost > 0: StoneEffects.fire(s,"DOT_TICK",{"target":actor,"victim":actor,"status":status,"amount":lost})
			Forms.end(s,was)
			if until <= s.time:
				if status == "furnace": furnace_burst(s,actor)
				actor.statuses.erase(status); payload.erase(status); sources.erase(status)

static func furnace_burst(s, actor: Dictionary) -> void:
	for other in s.party+s.npcs+s.enemies:
		if other.hp <= 0 or other.id == actor.id or s.side_of(other) == s.side_of(actor): continue
		if maxi(absi(other.pos.x-actor.pos.x),absi(other.pos.y-actor.pos.y)) <= 1: Rules.damage(s,actor,other,12,"fire")
