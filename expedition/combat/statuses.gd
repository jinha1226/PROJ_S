extends RefCounted
## The statuses an actor wears: what they stop, how a spell hangs one, and the
## boundary tick that bites and then drops the ones whose clock has run out.
## `statuses` keeps the clock; anything a status needs beyond that lives in
## `status_power`, which this file writes and clears together with the clock.
const Rules = preload("res://expedition/combat/combat_rules.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")

## What a spell's own burn does per boundary tick, told apart from the single
## point the fire mastery's burn has always done.
const BURN_DAMAGE := 4

## 빙결 and 속박 stop the feet; only 빙결 also stops the arms.
static func blocks(actor: Dictionary, kind: String) -> bool:
	var statuses: Dictionary = actor.get("statuses",{})
	if kind == "MOVE": return statuses.has("freeze") or statuses.has("bind")
	if kind == "ATTACK": return statuses.has("freeze")
	return false

## A status a spell hangs on somebody. `statuses` keeps the clock; anything the
## status needs to know beyond that goes in `status_power`, which the scheduler
## reads and drops when the status runs out.
static func resisted_ticks(s, victim: Dictionary, status: String, ticks: int) -> int:
	if status not in TagSets.WILL_STATUSES: return ticks
	var will: int = maxi(0,StatSheet.value(s,victim,"res_will"))
	return ticks*(100-will)/100

static func apply(s, victim: Dictionary, status: String, ticks: int) -> void:
	ticks = resisted_ticks(s,victim,status,ticks)
	if ticks <= 0: return
	victim.statuses[status] = s.time+ticks
	if status == "burn": victim.get_or_add("status_power",{})["burn"] = BURN_DAMAGE

## One boundary tick of every status in play: the expired ones go, the ones
## that bite bite.
static func tick(s) -> void:
	for actor in s.party + s.npcs + s.enemies:
		if actor.hp <= 0: continue
		var payload: Dictionary = actor.get("status_power",{})
		for status in actor.get("statuses",{}).keys():
			var until: int = int(actor.statuses[status])
			if until < s.time:
				actor.statuses.erase(status); payload.erase(status); continue
			if status == "bleed": Rules.damage(s,{},actor,2,"physical")
			# A spell's burn says how hard it bites; the old mastery burn keeps
			# the single point it always did.
			elif status == "burn": Rules.damage(s,{},actor,int(payload.get("burn",1)),"fire")
			elif status == "poison": Rules.damage(s,{},actor,2,"poison")
			if until <= s.time: actor.statuses.erase(status); payload.erase(status)
