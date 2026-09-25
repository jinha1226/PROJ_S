extends RefCounted
## Family passives (zones spec §2.1). A monster has its species' family; a
## member has the families of the soul stones it wears, each counted once
## however many stones of it are slotted. None of them needs contact.
const Essences = preload("res://expedition/progression/essences.gd")
const Bestiary = preload("res://expedition/progression/bestiary.gd")
const PASSIVES := {
	"rat":{"name":"날랜 발","text":"이동 지연 −10"},
	"goblin":{"name":"선수","text":"전투의 첫 행동 지연 −30"},
	"reptile":{"name":"탈피","text":"받는 상태이상 지속 −30%"},
	"kobold":{"name":"비열","text":"체력 절반 미만 대상에게 모든 피해 +10%"},
	"orc":{"name":"전투 광기","text":"처치하면 액티브 재사용 대기 −1"},
	"elemental":{"name":"마력 샘","text":"라운드마다 MP +1"},
	"insect":{"name":"껍질","text":"방어 +2"},
	"gnoll":{"name":"재생","text":"라운드마다 HP +2"},
	"undead":{"name":"불사","text":"전투마다 한 번, 쓰러질 피해를 HP 1로 버팀"},
	"bat":{"name":"초음파","text":"시야 +2, 혼령 안개 무시"}}
const MOVE_CUT := 10
const FIRST_CUT := 30
const STATUS_CUT := 30
const DIRTY_PERCENT := 10
const REGEN := 2
const MANA := 1
const SHELL := 2
const ECHO := 2

static func of(actor: Dictionary) -> Array:
	var result: Array = []
	if bool(actor.get("enemy",false)):
		var own: String = str(Bestiary.species(str(actor.get("species_id",""))).get("family",""))
		if not own.is_empty(): result.append(own)
		return result
	for id in Essences.equipped(actor):
		var family: String = Essences.family(str(id))
		if not family.is_empty() and family not in result: result.append(family)
	return result

static func has(actor: Dictionary, family: String) -> bool:
	return family in of(actor)

static func move_delay(actor: Dictionary, cost: int) -> int:
	return maxi(40,cost-MOVE_CUT) if has(actor,"rat") else cost

## The first action after `battle_start`: a goblin's is thirty quicker. Every
## actor spends its first action here, goblin or not.
static func first_action_delay(actor: Dictionary, cost: int) -> int:
	if bool(actor.get("first_acted",true)): return cost
	actor.first_acted = true
	return maxi(40,cost-FIRST_CUT) if has(actor,"goblin") else cost

static func status_ticks(actor: Dictionary, ticks: int) -> int:
	return ticks*(100-STATUS_CUT)/100 if has(actor,"reptile") else ticks

static func outgoing(_s, attacker: Dictionary, target: Dictionary, amount: int) -> int:
	if target.is_empty() or amount <= 0 or not has(attacker,"kobold"): return amount
	if int(target.hp)*2 < int(target.max_hp): return amount+maxi(1,amount*DIRTY_PERCENT/100)
	return amount

static func on_kill(_s, killer: Dictionary) -> void:
	if int(killer.get("hp",0)) <= 0 or not has(killer,"orc"): return
	var cooldowns: Dictionary = killer.get("cooldowns",{})
	for id in cooldowns: cooldowns[id] = maxi(0,int(cooldowns[id])-1)

static func round_start(s, actor: Dictionary) -> void:
	if int(actor.get("hp",0)) <= 0: return
	if has(actor,"gnoll"):
		var before: int = int(actor.hp)
		actor.hp = mini(int(actor.max_hp),int(actor.hp)+REGEN)
		if int(actor.hp) > before: s.Body.heal(actor)
	if has(actor,"elemental") and actor.has("max_mp"): actor.mp = mini(int(actor.max_mp),int(actor.get("mp",0))+MANA)

static func armour_bonus(actor: Dictionary) -> int:
	return SHELL if has(actor,"insect") else 0

## 불사: once a fight, a blow that would fell an undead leaves it on one HP.
static func lethal(_s, actor: Dictionary, amount: int) -> int:
	if amount < int(actor.hp) or bool(actor.get("undying_used",false)) or not has(actor,"undead"): return amount
	actor.undying_used = true
	return maxi(0,int(actor.hp)-1)

static func vision_bonus(actor: Dictionary) -> int:
	return ECHO if not actor.is_empty() and has(actor,"bat") else 0

static func ignores_fog(actor: Dictionary) -> bool:
	return not actor.is_empty() and has(actor,"bat")

## A fight begins: the goblin head start and the undead's stand are fresh.
static func battle_start(s) -> void:
	for actor in s.party+s.npcs+s.enemies:
		actor.first_acted = false; actor.undying_used = false
