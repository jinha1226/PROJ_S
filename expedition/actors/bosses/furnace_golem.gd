extends RefCounted
## 6층 용광로 골렘 (spec §7.2): 불과 물. Heat climbs every round and with every
## step, and the cells it leaves catch fire. At a hundred it announces a blast.
## Water from a lever's channel, or any ice, cools it thirty and cracks its
## plates open for two of its turns: no armour, and blows land harder.
const Common = preload("res://expedition/actors/bosses/boss_common.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const HEAT_MAX := 100
const HEAT_PER_STEP := 10
const HEAT_PER_ROUND := 5
const TRAIL_FIRE := 50
const BLAST_RADIUS := 3
const BLAST_DAMAGE := 24
const BLAST_FIRE := 60
const HEAT_AFTER_BLAST := 30
const COOLING := 30
const CRACK_TURNS := 2
const CRACK_TICKS := 200
const WET_ENOUGH := 20
const LEVER_TICKS := 400

static func spawn(_s, boss: Dictionary, _room: Dictionary, _depth: int) -> void:
	boss.heat = 0; boss.blasting = false; boss.cracked_until = 0

static func turn(s, boss: Dictionary) -> void:
	if boss.statuses.has("cracked") and int(boss.turns) >= int(boss.cracked_until): boss.statuses.erase("cracked")
	if bool(boss.blasting):
		var landed: Dictionary = Common.count_down(s,boss)
		if landed.is_empty(): return
		for cell in landed.cells: s.tile(cell).fire = mini(100,int(s.tile(cell).fire)+BLAST_FIRE)
		boss.blasting = false; boss.heat = HEAT_AFTER_BLAST
		s.message("%s · 폭발!" % boss.name)
		return
	cool_if_wet(s,boss)
	boss.heat = mini(HEAT_MAX,int(boss.heat)+HEAT_PER_ROUND)
	if int(boss.heat) >= HEAT_MAX:
		start_blast(s,boss); return
	var foe: Dictionary = Common.target(s,boss)
	if foe.is_empty(): return
	if s.melee_reach(boss.pos,foe.pos):
		Common.swing(s,boss,foe); return
	if s.status_blocks(boss,"MOVE"): return
	var was: Vector2i = boss.pos
	Common.step_toward(s,boss,foe)
	if boss.pos == was: return
	s.tile(was).fire = mini(100,int(s.tile(was).fire)+TRAIL_FIRE)
	boss.heat = mini(HEAT_MAX,int(boss.heat)+HEAT_PER_STEP)
	cool_if_wet(s,boss)
	if s.melee_reach(boss.pos,foe.pos): Common.swing(s,boss,foe)

static func start_blast(s, boss: Dictionary) -> void:
	boss.blasting = true
	Common.announce(boss,Common.cells_within(s,boss.pos,BLAST_RADIUS),Abilities.scaled(boss,BLAST_DAMAGE),"GOLEM_BLAST",2)
	s.message("%s · 과열! 폭발이 임박했습니다" % boss.name)

static func cool_if_wet(s, boss: Dictionary) -> void:
	var ground: Dictionary = s.tile(boss.pos)
	if str(ground.terrain) == "water" or int(ground.wet) >= WET_ENOUGH: cool(s,boss,"물")

## Heat −30 and the plates crack for two turns. A cracked golem does not
## crack again until its plates have closed.
static func cool(s, boss: Dictionary, cause: String) -> void:
	if boss.statuses.has("cracked"): return
	boss.heat = maxi(0,int(boss.heat)-COOLING)
	boss.statuses["cracked"] = int(s.time)+CRACK_TICKS
	boss.cracked_until = int(boss.turns)+CRACK_TURNS
	s.message("%s · %s에 식어 갑옷이 갈라졌습니다" % [boss.name,cause])

static func on_damaged(s, boss: Dictionary, form: String) -> void:
	if form.to_lower() == "ice": cool(s,boss,"냉기")

static func lever_ready(s, actor: Dictionary, point: Vector2i) -> bool:
	var feature: Dictionary = s.floor_state.features.get(point,{})
	if str(feature.get("kind","")) != "lever": return false
	if int(actor.hp) <= 0 or int(actor.ap) <= 0 or Common.reach(actor.pos,point) != 1: return false
	return int(s.time) >= int(feature.get("ready_at",0))

## Every cell of the lever's channel runs wet; the lever rests four rounds.
static func pull_lever(s, actor: Dictionary, point: Vector2i) -> bool:
	if not lever_ready(s,actor,point): return false
	var feature: Dictionary = s.floor_state.features[point]
	var channel: int = int(feature.channel)
	var flooded := 0
	for cell in s.floor_state.features:
		var row: Dictionary = s.floor_state.features[cell]
		if str(row.get("kind","")) == "channel" and int(row.get("channel",0)) == channel:
			s.tile(cell).wet = 100; flooded += 1
	feature.ready_at = int(s.time)+LEVER_TICKS
	actor.ap -= 1
	s.message("%s · 수로 레버 · 물이 %d칸을 적십니다" % [actor.name,flooded])
	return true
