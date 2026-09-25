extends RefCounted
## Four bosses, one a zone, each a test of that zone's own system (spec §7).
## This file is the shared frame: the spawn into the zone's boss room, the
## round each boss takes, the sealed room and its banner, the hooks the session
## calls, and the reward. A boss's own round lives in `bosses/`.
const Abilities = preload("res://expedition/items/abilities.gd")
const Zones = preload("res://expedition/level/zones.gd")
const Common = preload("res://expedition/actors/bosses/boss_common.gd")
const Chief = preload("res://expedition/actors/bosses/goblin_chief.gd")
const Golem = preload("res://expedition/actors/bosses/furnace_golem.gd")
const Eater = preload("res://expedition/actors/bosses/soul_eater.gd")
const Fallen = preload("res://expedition/actors/bosses/fallen_adventurer.gd")
const KINDS := ["chief","golem","eater","fallen"]
const NAMES := {"chief":"고블린 족장","golem":"용광로 골렘","eater":"영혼 포식자"}
const SPECIES := {"chief":"goblin_chief","golem":"furnace_golem","eater":"soul_eater"}
const ESSENCES := {"chief":"GOBLIN_CHIEF","golem":"FURNACE_HEART","eater":"SOUL_EATER"}
const FAMILIES := {"chief":"goblin","golem":"elemental","eater":"undead"}
## Which floor species' picture each boss is drawn from, three tiles tall.
const SPRITES := {"chief":"dcss_hobgoblin","golem":"ore_golem","eater":"wraith"}
const HINTS := {
	"chief":"지휘 부하",
	"golem":"수로 레버",
	"eater":"영혼 흡수",
	"fallen":"영혼석 전술"}
const STATS := {
	"chief":{"ac":2,"ev":3,"sh":10,"res":{}},
	"golem":{"ac":8,"ev":0,"sh":0,"res":{"fire":80,"ice":-25}},
	"eater":{"ac":3,"ev":4,"sh":0,"res":{"will":50}}}

static func spawn(s, layout: Dictionary, depth: int) -> void:
	var zone: int = int(Zones.zone_of(depth))
	var kind: String = KINDS[clampi(zone-1,0,KINDS.size()-1)]
	var room: Dictionary = {}
	for row in layout.rooms:
		if str(row.template_id) == str(Zones.boss_template(zone)): room = row; break
	if room.is_empty(): return
	if kind == "fallen": Fallen.spawn(s,room,depth); return
	var boss: Dictionary = s.make_actor(900+depth,NAMES[kind],true)
	boss.pos = s.Floor.Generator.room_anchor(room)
	boss.hp = Common.boss_hp(depth); boss.max_hp = boss.hp
	boss.base_attack = Common.boss_attack(depth); boss.power = boss.base_attack; boss.attack_percent = 100
	boss.speed = 100; boss.ready_at = int(s.time)+int(boss.speed)
	boss.boss = true; boss.boss_kind = kind; boss.room_template = str(room.template_id)
	boss.species_id = SPECIES[kind]; boss.part_id = ESSENCES[kind]
	boss.family = FAMILIES[kind]; boss.sprite_species = SPRITES[kind]
	boss.alert = false; boss.charging = false; boss.role = "MELEE"
	boss.telegraph = {}; boss.turns = 0; boss.room_sealed = false
	var stats: Dictionary = STATS[kind]
	boss.ac = int(stats.ac); boss.ev = int(stats.ev); boss.sh = int(stats.sh); boss.res = (stats.res as Dictionary).duplicate()
	s.enemies.append(boss)
	match kind:
		"chief": Chief.spawn(s,boss,room,depth)
		"golem": Golem.spawn(s,boss,room,depth)
		"eater": Eater.spawn(s,boss,room,depth)

## The board's warning cells: whatever the boss has announced and not landed.
static func plan(s, boss: Dictionary) -> void:
	if s.alive().is_empty(): return
	Common.emit(s,boss)

static func turn(s, boss: Dictionary) -> void:
	if int(boss.hp) <= 0: return
	# A frozen boss spends its turn where it stands; a bound one still swings.
	if s.status_blocks(boss,"ATTACK"): return
	if not bool(boss.get("room_sealed",false)): open_fight(s,boss)
	if not bool(boss.get("room_sealed",false)): return
	boss.turns = int(boss.get("turns",0))+1
	match str(boss.get("boss_kind","")):
		"chief": Chief.turn(s,boss)
		"golem": Golem.turn(s,boss)
		"eater": Eater.turn(s,boss)
		"fallen": Fallen.turn(s,boss)
		_: plain_round(s,boss)

## What a boss does with no round of its own: close in and swing.
static func plain_round(s, boss: Dictionary) -> void:
	var foe: Dictionary = Common.target(s,boss)
	if foe.is_empty(): return
	if s.melee_reach(boss.pos,foe.pos): Common.swing(s,boss,foe); return
	if s.status_blocks(boss,"MOVE"): return
	Common.step_toward(s,boss,foe)
	if s.melee_reach(boss.pos,foe.pos): Common.swing(s,boss,foe)

static func room_of(s, boss: Dictionary) -> Dictionary:
	for row in s.floor_state.layout.rooms:
		if str(row.template_id) == str(boss.get("room_template","")): return row
	return {}

## The first round with a party member inside the room: the doors shut behind
## them and the boss is named. Until then the room stays open.
static func open_fight(s, boss: Dictionary) -> void:
	var room: Dictionary = room_of(s,boss)
	if room.is_empty() or not s.alive().any(func(a): return room.rect.has_point(a.pos)): return
	boss.room_sealed = true
	for door in room.doors:
		if not s.at(door).is_empty(): continue
		var cell: Dictionary = s.tile(door)
		cell.boss_door = true; cell.terrain = "wall"
	s.push_event({"kind":"BOSS","name":str(boss.name),"hint":str(HINTS.get(str(boss.boss_kind),""))})
	s.message("%s · 입구가 닫혔습니다" % boss.name)
	if str(boss.boss_kind) == "eater": Eater.wake(s,boss)
	if str(boss.boss_kind) == "fallen": Fallen.begin(s,boss)

static func unseal(s, boss: Dictionary) -> void:
	var room: Dictionary = room_of(s,boss)
	if room.is_empty(): return
	for door in room.doors:
		var cell: Dictionary = s.tile(door)
		if not bool(cell.get("boss_door",false)): continue
		cell.terrain = str(cell.source_terrain); cell.erase("boss_door")

## Any damage that reached a boss, by the form it came in.
static func on_damaged(s, boss: Dictionary, form: String) -> void:
	if str(boss.get("boss_kind","")) == "golem": Golem.on_damaged(s,boss,form)

## A monster died; the bosses that care hear of it.
static func on_monster_death(s, dead: Dictionary, killer: Dictionary) -> void:
	if bool(dead.get("boss",false)): return
	for boss in s.enemies:
		if int(boss.hp) > 0 and str(boss.get("boss_kind","")) == "eater": Eater.absorb(s,boss,dead)
	if killer.is_empty() or not bool(killer.get("devour_ready",false)): return
	var part: String = str(dead.get("part_id",""))
	if not Abilities.has(part): return
	killer.borrowed = part; killer.devour_ready = false
	s.message("%s · %s의 기술을 삼켰습니다" % [killer.name,dead.name])

static func on_boss_defeated(s, boss: Dictionary) -> void:
	unseal(s,boss)
	if str(boss.get("boss_kind","")) == "eater": Eater.release(s,boss)
	if str(boss.get("boss_kind","")) == "fallen": Fallen.defeated(s,boss)
	s.message("%s 처치" % boss.name)

## The party member a chief's order has marked for this minion, or {}.
static func focus_of(s, enemy: Dictionary) -> Dictionary:
	if not enemy.has("chief"): return {}
	var chief: Dictionary = s.actor_by_id(int(enemy.chief))
	if chief.is_empty() or int(chief.hp) <= 0 or int(enemy.get("focus_until",0)) <= int(chief.get("turns",0)): return {}
	var mark: Dictionary = s.actor_by_id(int(enemy.get("focus_id",-1)))
	return mark if not mark.is_empty() and int(mark.hp) > 0 else {}

static func lever_ready(s, actor: Dictionary, point: Vector2i) -> bool:
	return Golem.lever_ready(s,actor,point)

static func pull_lever(s, actor: Dictionary, point: Vector2i) -> bool:
	return Golem.pull_lever(s,actor,point)
