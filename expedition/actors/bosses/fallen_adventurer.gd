extends RefCounted
## 12층 타락한 모험가 (spec §7.4): 동료와 NPC. A roster NPC this run left
## behind comes back as the last boss with its own name, weapon, stance, nature
## and essences, the empty slots filled with more stones. It stays an NPC on
## the floor's list, hostile and a boss, so every rule that dresses a member —
## the stat sheet, sets, headline effects, spells — dresses it too.
const Common = preload("res://expedition/actors/bosses/boss_common.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const NpcEssences = preload("res://expedition/actors/npc_essences.gd")
const BOSS_ID := 950
## What it remembers most of the hero picks its lines: [start, half, fall].
const LINES := {
	"ATTACKED_BY_PLAYER":["네 칼끝을 아직 기억한다.","그때처럼 쉽진 않을 거다.","이번에도... 네가 이겼군."],
	"DECLINED_BY_PLAYER":["날 거절했지. 이제 네 차례다.","혼자서도 여기까지 왔다!","함께였다면... 달랐을까."],
	"AID_RECEIVED":["네가 살려 준 목숨이다. 돌려주마.","은혜는... 잊었다!","고맙다고... 말할 걸 그랬어."],
	"RECRUITED":["함께 걷던 길이 여기서 끝난다.","동료였던 걸 잊었나!","잘 가라, 친구."],
	"LEFT_BY_PARTNER":["모두 날 두고 갔지.","다시는 버려지지 않아!","이제야... 쉬는구나."],
	"ALLY_LOST":["잃는다는 게 뭔지 알려 주마.","아직 잃을 게 남았나?","다들... 거기 있었구나."],
	"":["묘역이 나를 불렀다.","아직 끝나지 않았다!","드디어... 조용하군."]}
const MEMORY_KINDS := ["ATTACKED_BY_PLAYER","DECLINED_BY_PLAYER","AID_RECEIVED","RECRUITED","LEFT_BY_PARTNER","ALLY_LOST"]
const FOND := 30
const SHAKEN := 40
const HIGH := 600
const LOW := 400

static func opinion_of_hero(s, npc: Dictionary) -> int:
	return int(npc.get("opinions",{}).get(int(s.party[0].id),0))

## The dead roster NPC who felt most strongly about the hero; else the living
## one outside the party who likes the hero least; else a new roster's first.
static func pick(s) -> Dictionary:
	var dead: Array = s.roster.filter(func(n): return str(n.get("state","")) == "DEAD")
	if not dead.is_empty():
		dead.sort_custom(func(a,b):
			var oa: int = absi(opinion_of_hero(s,a))
			var ob: int = absi(opinion_of_hero(s,b))
			return oa > ob if oa != ob else int(a.id) < int(b.id))
		return dead[0]
	var living: Array = s.roster.filter(func(n): return str(n.get("state","")) != "DEAD" and int(n.hp) > 0 and not s.party.any(func(p): return int(p.id) == int(n.id)))
	if not living.is_empty():
		living.sort_custom(func(a,b):
			var oa: int = opinion_of_hero(s,a)
			var ob: int = opinion_of_hero(s,b)
			return oa < ob if oa != ob else int(a.id) < int(b.id))
		return living[0]
	var fresh: Array = s.NpcRoster.generate(s)
	return fresh[0] if not fresh.is_empty() else {}

static func spawn(s, room: Dictionary, depth: int) -> void:
	var source: Dictionary = pick(s)
	if source.is_empty(): return
	var boss: Dictionary = source.duplicate(true)
	boss.merge({"id":BOSS_ID,"roster_id":int(source.id),"npc":true,"enemy":false,"hostile":true,"awake":true,
		"boss":true,"fallen":true,"boss_kind":"fallen","state":"BOSS","activity":"적대 중","mode":"","partner":-1,
		"room_template":str(room.template_id),"room_sealed":false,"turns":0,"telegraph":{},
		"set_boost":false,"boosted":false,"defeated":false},true)
	boss.level = Essences.MAX_LEVEL
	boss.statuses = {}; boss.cooldowns = {}; boss.usage = {}; boss.rules = []
	boss.pos = s.Floor.Generator.room_anchor(room)
	boss.max_hp = Common.boss_hp(depth); boss.hp = boss.max_hp
	boss.pool_bonus = {"hp":0,"mp":0}
	boss.essences = boss.get("essences",{}).duplicate()
	boss.equipped_abilities = []
	Essences.sync_slots(boss)
	fill(boss)
	NpcEssences.choose(s,boss)
	boss.ready_at = int(s.time)+100
	s.npcs.append(boss)

## Tops the essences up to ten with floor species' essences, each absorbed,
## chosen by the same nature-and-sets score an NPC uses for its own slots.
static func fill(boss: Dictionary) -> void:
	var pool: Array = Abilities.droppable().filter(func(id): return Essences.has(str(id)) and not boss.essences.has(str(id)))
	while boss.essences.size() < Essences.slot_count(boss) and not pool.is_empty():
		var best := ""
		var best_score := -(1 << 30)
		for entry in pool:
			var id: String = str(entry)
			var score: int = NpcEssences.preference(boss,id)+NpcEssences.SET_BONUS*NpcEssences.continuing(boss.essences.keys(),id)
			if score > best_score or score == best_score and id < best: best = id; best_score = score
		boss.essences[best] = 1
		pool.erase(best)

static func line(boss: Dictionary, moment: int) -> String:
	var row: Dictionary = {}
	if boss.get("memory") != null: row = boss.memory.strongest(MEMORY_KINDS)
	var rows: Array = LINES.get(str(row.get("kind","")),LINES[""])
	return str(rows[clampi(moment,0,2)])

## The fight begins: its first line, and a friend of it in the party shaken.
static func begin(s, boss: Dictionary) -> void:
	Common.say(s,boss,line(boss,0))
	for ally in s.alive():
		if int(ally.get("opinions",{}).get(int(boss.roster_id),0)) >= FOND:
			ally.stress = mini(200,int(ally.stress)+SHAKEN)
			ally.condition = "붕괴" if ally.stress >= 150 else "불안" if ally.stress >= 100 else "평온"

static func turn(s, boss: Dictionary) -> void:
	if not bool(boss.boosted) and int(boss.hp)*2 < int(boss.max_hp):
		boss.boosted = true; boss.set_boost = true
		StatSheet.refresh_pools(s,boss)
		Common.say(s,boss,line(boss,1))
	var foes: Array = Common.victims(s,boss)
	if foes.is_empty(): return
	var profile = boss.profile
	var adjacent: bool = foes.any(func(f): return s.melee_reach(boss.pos,f.pos))
	if int(profile.value("C")) >= HIGH and adjacent and guard_up(s,boss): return
	var foe: Dictionary = choose_target(s,boss,foes)
	if int(profile.value("E")) >= HIGH and int(boss.hp)*2 < int(boss.max_hp) and s.melee_reach(boss.pos,foe.pos) and back_off(s,boss,foe): return
	if use_active(s,boss,foe): return
	if cast(s,boss,foe): return
	if s.attack_reach(boss,foe.pos,int(s.CombatStats.stats(s,boss).range)) and s.act_as(boss,"ATTACK",foe.pos,false): return
	if not s.status_blocks(boss,"MOVE"): Common.step_toward(s,boss,foe)

## Low 원만성 hunts the weakest; everyone else the nearest.
static func choose_target(_s, boss: Dictionary, foes: Array) -> Dictionary:
	var ranked: Array = foes.duplicate()
	if int(boss.profile.value("A")) < LOW:
		ranked.sort_custom(func(a,b):
			var ra: float = float(a.hp)/maxf(1.0,float(a.max_hp))
			var rb: float = float(b.hp)/maxf(1.0,float(b.max_hp))
			return ra < rb if ra != rb else int(a.id) < int(b.id))
	else:
		ranked.sort_custom(func(a,b):
			var da: int = Common.reach(a.pos,boss.pos)
			var db: int = Common.reach(b.pos,boss.pos)
			return da < db if da != db else int(a.id) < int(b.id))
	return ranked[0]

## High 성실성 raises a self-targeted technique first when a foe is close.
static func guard_up(s, boss: Dictionary) -> bool:
	for id in Essences.equipped(boss):
		if not Abilities.has(str(id)) or str(Abilities.definition(str(id)).target) != "SELF": continue
		if Abilities.legal(s,boss,str(id),boss.pos): return Abilities.execute(s,boss,str(id),boss.pos)
	return false

static func use_active(s, boss: Dictionary, foe: Dictionary) -> bool:
	for id in Essences.equipped(boss):
		if not Abilities.has(str(id)) or str(Abilities.definition(str(id)).target) != "ENEMY": continue
		if Abilities.legal(s,boss,str(id),foe.pos): return Abilities.execute(s,boss,str(id),foe.pos)
	return false

static func cast(s, boss: Dictionary, foe: Dictionary) -> bool:
	for spell in boss.get("prepared",[]):
		if s.Spells.can_cast(s,boss,str(spell),foe.pos): return s.Spells.cast(s,boss,str(spell),foe.pos)
	return false

## High 정서성, below half and in reach: the free step that puts the most
## distance between it and the foe.
static func back_off(s, boss: Dictionary, foe: Dictionary) -> bool:
	var best := Vector2i(-1,-1)
	var far: int = Common.reach(boss.pos,foe.pos)
	for direction in s.DIRECTIONS:
		var cell: Vector2i = boss.pos+direction
		if not s.can_step(boss.pos,cell): continue
		if Common.reach(cell,foe.pos) > far: best = cell; far = Common.reach(cell,foe.pos)
	if best.x < 0: return false
	boss.pos = best
	return true

## Its last line, its first slotted essence (or, wearing none, the first it
## absorbed) to the party, and the run is won.
static func defeated(s, boss: Dictionary) -> void:
	Common.say(s,boss,line(boss,2))
	var worn: Array = Essences.equipped(boss)
	var best: String = str(worn[0]) if not worn.is_empty() else str(boss.get("essences",{}).keys()[0]) if not boss.get("essences",{}).is_empty() else ""
	if not best.is_empty(): s.grant_part(best)
	s.victory()
