extends RefCounted
## The battle report and the run's own record: the rows, the explanations and
## the mistakes the result card reads.
## The last EXPLAIN_KEEP utility explanations of one member, oldest dropped
## first: why the selector picked what it picked, for the balance tools and the
## `--explain` frequency tables. Early returns (fire, hesitation, the retreat
## line) carry no `explain`, so the row is read with `.get`. The reason string
## is untouched by this (설계 §0.4) — this is statistics, not UI.
const EXPLAIN_KEEP := 20
## What the log calls each kind of mistake.
const MISTAKE_NAMES := {"HESITATE":"머뭇거림","RECKLESS":"무모함","REVERT":"자기 방식대로"}

## Who walked with the party this run: only those who actually joined, in
## roster order, each with the floor it joined on and whether it is still up.
static func companion_rows(s) -> Array:
	return s.roster.filter(func(r): return int(r.get("joined_floor",0)) > 0).map(
		func(r): return {"name":str(r.name),"joined_floor":int(r.joined_floor),"alive":(r.hp > 0 or bool(r.get("downed",false))) and r.state != "DEAD"})

## Clears the report and opens one row per member. The simulator calls this
## itself at the arena, where no BATTLE_START stop event runs.
static func reset_battle_stats(s) -> void:
	# The report is the party's own sight (T3-b), not every foe an npc dragged in.
	s.battle_stats = {"rounds":0,"enemies":s.party_enemies().size() if s.phase == "BATTLE" else 0,"kills":0,"members":{},
		"interrupts":0,"enemy_parts":{},"drops":{},"stops":[]}
	for actor in s.party:
		# A new battle starts with nothing to commit to: the utility selector's
		# `same_as_last` must not read the last battle's closing move.
		actor.last_action_kind = ""
		actor.last_action_dir = Vector2i.ZERO
		s.battle_stats.members[actor.id] = {"dealt":0,"taken":0,"guards":0,"covers":0,"redirected":0,
			"parts":{},"healed":0,"downed":false,"conflict":bool(actor.get("conflicted",false)),
			"mistakes":0,"role_rounds":{"in_role":0,"total":0},"explains":[]}

## The row of one member, empty for an id that is not in the party — which is
## what every tally below tests before it writes.
static func member_stats(s, id: int) -> Dictionary:
	if not s.battle_stats.has("members"): s.reset_battle_stats()
	return s.battle_stats.members.get(id,{})

static func note_explain(s, actor: Dictionary, choice: Dictionary) -> void:
	var row: Dictionary = s.member_stats(actor.id)
	if row.is_empty(): return
	var log: Array = row.get("explains",[])
	log.append({"round":int(s.battle_stats.get("rounds",0)),"kind":str(choice.get("kind","")),
		"cell":choice.get("cell",actor.pos),"explain":choice.get("explain",[])})
	while log.size() > EXPLAIN_KEEP: log.remove_at(0)
	row.explains = log

## One mistake by `actor` this round: tallied for the battle report, and
## announced once per battle so the log says why the round went sideways.
## Only auto_step calls this — a choice that was merely previewed costs nothing.
static func note_mistake(s, actor: Dictionary, kind: String) -> void:
	var row: Dictionary = s.member_stats(actor.id)
	if row.is_empty(): return
	var first: bool = int(row.get("mistakes",0)) == 0
	row.mistakes = int(row.get("mistakes",0))+1
	s.run_stats.mistakes = int(s.run_stats.mistakes)+1
	if first: s.message("%s · %s" % [actor.name,MISTAKE_NAMES.get(kind,"실수")])
