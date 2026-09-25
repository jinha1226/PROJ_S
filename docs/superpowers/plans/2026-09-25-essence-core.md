# 이능 성장 핵심 규칙 구현 계획 (1/3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 숙련 10축·옛 성장·주문서를 없애고, 레벨(최대 10, 레벨마다 슬롯 1칸)과 이능(기본 스탯·패시브·액티브·역할/속성 태그·1~3단계)으로 성장하게 한다. 방어·회피·막기·속성 저항 5종을 스탯으로 드러내고, 주문은 주문 이능에서 얻는다.

**Architecture:** 새 정적 모듈 셋이 규칙을 맡는다. `essences.gd`는 이능 카탈로그(`data/content/essences.json`)와 흡수·장착·단계·주문 선택을, `tag_sets.gd`는 태그 세트 판정과 전투 훅을, `stat_sheet.gd`는 모든 전투 수치를 출처와 함께 계산한다. `combat_stats.gd`는 숙련 대신 스탯 시트를 읽고, `hunt.gd`가 숙련 사용 기록 대신 사냥 참여만 기록한다. 기존 파츠(`abilities.gd`)는 이능의 패시브·액티브로 그대로 쓰인다.

**Tech Stack:** Godot 4.6 GDScript, 헤드리스 테스트(`godot --headless --path . --script res://tests/<suite>.gd`), JSON 콘텐츠.

**Spec:** `docs/superpowers/specs/2026-09-25-bestiary-progression-design.md`

**연계 계획:** 2/3 `2026-09-25-essence-content.md`(주문 종족 5종, 보스 이능, 속성 변종, 깊은 층 보정), 3/3 `2026-09-25-essence-ui-npc.md`(이능 화면, 배너, 스탯 화면, NPC 선택, 난이도 게이트). 이 계획이 먼저 끝나야 한다.

## Global Constraints

- 테스트 실행 전 임포트: `godot --headless --path . --editor --import --quit` (한 번이면 충분). 새 `.gd` 파일을 만든 뒤에도 한 번 더 돌린다.
- 모든 스위트는 `push_error`가 없고 종료 코드 0이어야 통과. 로그에 `SCRIPT ERROR:`나 `^ERROR:` 줄이 있으면 실패.
- 결정성: 무작위는 `Hexaco.sample(seed, key, lane, modulus)` 또는 `CombatRules.roll(...)`만 쓴다. `randi()` 금지.
- 메시지·라벨은 한국어.
- 최대 레벨 10. 슬롯 수 = 레벨(1~10). 레벨 곡선 `65 × L²` 누적, 레벨업마다 HP +4, MP +2.
- 이능 드롭: 그 종족을 이번 판에 처음 잡으면 100%, 그 뒤로 25%. 파티가 참여한 사냥만.
- 이능 단계: 같은 이능을 다시 흡수하면 단계 +1, 최대 3. 단계는 흡수한 인물이 가진다. 흡수한 이능은 가방으로 돌아가지 않는다. 기본 스탯은 단계배, 액티브 위력은 `×(1 + 0.25 × (단계 − 1))`.
- 주문 이능 단계별 주문 레벨 상한: 1단계 3, 2단계 6, 3단계 10. 준비된 주문은 최대 5개.
- 주문 실패율: `8 + 주문 레벨 × 9 + 갑옷 부담 × 5 − 정신 − 주문 이능 단계 × 10 − (술사 세트 3이면 10)`, 0~85%.
- 저항 합계 상한 80%. 막기 확률 상한 50%, 방패가 없으면 막기 절반. 회피 확률 = 회피 × 2%, 5~45%(기존 공식).
- 체력 종족 기본값 10, 이능·세트로 오른 체력 1당 최대 HP +3. 이능·세트로 오른 정신 1당 최대 MP +1.
- 이능 교체·흡수는 `IDLE`, `CAMP`, 또는 `EXPLORE`이면서 `floor_state.safe(s)`일 때만.
- 커밋 메시지 끝에 `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. 커밋은 `git commit -m ... -- <이 작업의 파일들>`처럼 경로를 명시한다. 다른 세션의 미커밋 변경을 건드리지 않는다.
- **깨져도 되는 스위트**: Task 2~6 사이에는 숙련·옛 성장·주문서를 검사하는 옛 스위트(`model_b_mastery`, `model_b_mastery_ui`, `abilities_growth`, `character_ui`, `spellbooks`, `start_kit`, `model_b_spells`, `parts`, `integration`, `npc_progression`, `run_start`, `solo_balance`, `test_loadout`, `model_b_scheduler`)가 깨질 수 있다. 각 작업의 "기존 스위트" 단계에 적힌 것만 그 작업에서 고친다. Task 7이 끝나면 전부 통과해야 한다. 그 밖의 스위트는 매 작업마다 통과해야 한다.
- 검사 수를 줄이지 않는다. 지운 검사보다 새로 만든 검사가 많아야 한다(Task 7 마지막 단계에서 센다).

---

## File Structure

| 파일 | 역할 |
|---|---|
| `data/content/essences.json` (신규) | 이능 행: 기본 스탯, 역할 태그, 속성 태그, 주문 계열, 종족 |
| `expedition/progression/essences.gd` (신규) | 카탈로그 조회(변종 id `기본@속성` 해석), 단계, 슬롯, 흡수·장착·해제, 주문 선택과 동기화, 드롭 확률 |
| `expedition/progression/tag_sets.gd` (신규) | 태그 개수·세트 단계·세트 설명, 스탯 보너스, 전투 훅 |
| `expedition/progression/stat_sheet.gd` (신규) | 능력치 4, 방어 수치 3, 저항 5의 합계와 출처, 저항 상한, HP·MP 보너스 갱신, 옛 오토배틀용 위력 |
| `expedition/progression/hunt.gd` (신규) | 사냥 참여 기록(`usage`) |
| `expedition/combat/combat_stats.gd` | 스탯 시트를 읽어 피해·지연·방어·회피·막기·저항 계산 |
| `expedition/combat/combat_rules.gd` | 숙련 효과 제거, 확정 명중, 속성 세트 피해·상태이상 |
| `expedition/combat/statuses.gd` | 의지 저항이 변이 계열 상태이상을 줄임 |
| `expedition/combat/passives.gd` | 세트 훅 연결 |
| `expedition/items/abilities.gd` | 액티브 위력을 스탯과 단계로, 참여 기록 |
| `expedition/items/gear.gd` | 흡수·장착·해제, 드롭 규칙, 옛 성장 제거 |
| `expedition/run/descent.gd` | 최대 레벨 10, 슬롯 동기화, 시작 이능 |
| `expedition/run/session.gd` | 새 필드와 래퍼, 이벤트 큐, 숙련·성장 호출 제거 |
| `expedition/run/camp.gd` | 주문 배우기·준비·주문서 제거 |
| `expedition/spells/spells.gd` | 실패율·위력을 정신과 이능 단계로, 주문서 제거 |
| `expedition/items/curios.gd` | 주문서 보상을 주문 이능으로 |
| `expedition/actors/npc_roster.gd`, `expedition/spells/summons.gd`, `expedition/sim/*.gd`, `expedition/actors/floor_tactics_adapter.gd`, `expedition/ai/parts_candidates.gd` | 슬롯·성장 호출 정리 |
| `expedition/ui/screens/character_folio.gd`, `popups.gd`, `camp_screen.gd`, `expedition/ui/main.gd` | 숙련 탭·성장 투자·주문 배우기 제거, 파츠 탭을 슬롯 수에 맞춤 |
| `expedition/progression/mastery.gd`, `mastery_effects.gd`, `growth.gd`, `data/content/mastery.json` | 삭제 |
| `data/content/combat.json` | `books`, `loot.books` 삭제, 주문 행의 `book` 삭제, 독 저항 반지 80 |
| `tests/essences.gd`, `tests/stats_resist.gd`, `tests/tag_sets.gd`, `tests/essence_spells.gd` (신규) | 새 규칙 검사 |

---

### Task 1: 이능 카탈로그와 태그 세트 판정

**Files:**
- Create: `data/content/essences.json`
- Create: `expedition/progression/essences.gd`
- Create: `expedition/progression/tag_sets.gd`
- Test: `tests/essences.gd` (신규)

**Interfaces:**
- Consumes: `Abilities.DEFINITIONS`, `Abilities.droppable()` (기존)
- Produces:
  - `Essences.ROLES: Dictionary`, `Essences.ELEMENTS: Dictionary`, `Essences.MAX_TIER := 3`, `Essences.MAX_LEVEL := 10`, `Essences.READY_SPELLS := 5`, `Essences.CASTER_BY_SCHOOL: Dictionary`
  - `Essences.base_of(id: String) -> String`, `variant_element(id) -> String`, `has(id) -> bool`, `row(id) -> Dictionary` (`name, stats, role, element, school, species`), `title(id) -> String`, `stats(id, tier: int) -> Dictionary`, `role(id) -> String`, `element(id) -> String`, `school(id) -> String`, `tier(actor, id) -> int`, `equipped(actor) -> Array`, `slot_count(actor) -> int`, `spell_cap(tier) -> int`, `active_power(tier, base) -> int`
  - `TagSets.TEXT`, `TagSets.WILL_STATUSES: Array`, `TagSets.counts(actor) -> Dictionary`, `level(actor, tag) -> int` (0/2/3), `active(actor) -> Array` of `{"tag","name","level","text"}`, `stat_bonus(actor) -> Dictionary` (키: `ac, sh, ev, mp, res_<속성>`)

- [ ] **Step 1: 실패하는 테스트 쓰기**

`tests/essences.gd`:

```gdscript
extends SceneTree
## Essences: the catalog every monster and caster leaves behind, the tiers a
## member absorbs, the slots a level opens, and the drops a hunt yields.
const Session = preload("res://expedition/run/session.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	catalog()
	sets()
	print("Essences: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func catalog() -> void:
	for id in Abilities.DEFINITIONS: check(Essences.has(id),"every part is an essence: "+id)
	for id in Abilities.droppable():
		var row: Dictionary = Essences.row(id)
		check(str(row.role) in Essences.ROLES,"%s has a role tag" % id)
		check(str(row.species) == str(Abilities.DEFINITIONS[id].species),"%s belongs to its species" % id)
		check(not (row.stats as Dictionary).is_empty(),"%s gives base stats" % id)
	for school in Essences.CASTER_BY_SCHOOL:
		var id: String = str(Essences.CASTER_BY_SCHOOL[school])
		check(Essences.has(id) and Essences.school(id) == school,"%s gives the %s school" % [id,school])
		check(Essences.role(id) == "CASTER","%s is a caster" % id)
		check(not Essences.title(id).is_empty(),"%s is named" % id)
	check(Essences.element("FIRE_CALLER") == "fire" and Essences.element("GOBLIN_HEXER") == "will","caster element tags follow the school")
	var variant: Dictionary = Essences.row("GOBLIN_SHIV@fire")
	check(variant.element == "fire" and int(variant.stats.res_fire) == 10 and int(variant.stats.dex) == 2,"a variant is the base plus its element")
	check(variant.role == "AMBUSH","a variant keeps the base role")
	check(Essences.title("GOBLIN_SHIV@fire").begins_with("화염"),"a variant's title names its element")
	check(not Essences.has("GOBLIN_SHIV@lava") and not Essences.has("NOPE") and not Essences.has(""),"unknown ids are not essences")
	check(int(Essences.stats("ORC_CLEAVER",1).str) == 2 and int(Essences.stats("ORC_CLEAVER",3).str) == 6,"base stats scale with the tier")
	check(int(Essences.stats("ORC_CLEAVER",9).str) == 6,"the tier stops at three")
	check(Essences.spell_cap(1) == 3 and Essences.spell_cap(2) == 6 and Essences.spell_cap(3) == 10,"spell level caps by tier")
	check(Essences.active_power(1,20) == 20 and Essences.active_power(2,20) == 25 and Essences.active_power(3,20) == 30,"active power +25% a tier")
	var actor := {"level":4,"equipped_abilities":["RAT_GNAW","",""],"essences":{}}
	check(Essences.tier(actor,"RAT_GNAW") == 1,"a slotted essence nobody absorbed counts as tier one")
	check(Essences.tier(actor,"ORC_CLEAVER") == 0,"an unknown essence has no tier")
	actor.essences = {"RAT_GNAW":3}
	check(Essences.tier(actor,"RAT_GNAW") == 3,"an absorbed essence has its own tier")
	check(Essences.equipped(actor) == ["RAT_GNAW"],"empty slots are not essences")
	check(Essences.slot_count(actor) == 4 and Essences.slot_count({"level":15}) == 10 and Essences.slot_count({}) == 1,"slots follow the level, one to ten")

func sets() -> void:
	var actor := {"level":5,"essences":{},"equipped_abilities":["RAT_GNAW","RIVER_RAT_SPLASH","FIRE_CALLER","",""]}
	var counts: Dictionary = TagSets.counts(actor)
	check(int(counts.PACK) == 2 and int(counts.CASTER) == 1 and int(counts.fire) == 1,"roles and elements are counted apart")
	check(TagSets.level(actor,"PACK") == 2 and TagSets.level(actor,"CASTER") == 0,"two of a tag switch a set on")
	actor.equipped_abilities[3] = "RAT_GNAW@ice"
	check(TagSets.level(actor,"PACK") == 3,"three of a tag is the second step")
	var active: Array = TagSets.active(actor)
	check(active.size() == 1 and active[0].tag == "PACK" and int(active[0].level) == 3 and str(active[0].text).contains("받는 피해"),"active sets carry their text")
	var guard := {"level":3,"essences":{},"equipped_abilities":["LIZARD_TAIL","HOB_CLUB",""]}
	var bonus: Dictionary = TagSets.stat_bonus(guard)
	check(int(bonus.ac) == 2 and int(bonus.sh) == 5,"수호 2 gives armour and block")
	var burning := {"level":3,"essences":{},"equipped_abilities":["LIZARD_TAIL@fire","HOB_CLUB@fire",""]}
	check(int(TagSets.stat_bonus(burning).res_fire) == 20,"화염 2 gives fire resistance")
	var casters := {"level":2,"essences":{},"equipped_abilities":["FIRE_CALLER","FROST_IMP"]}
	check(int(TagSets.stat_bonus(casters).mp) == 5,"술사 2 gives MP")
	var hexers := {"level":2,"essences":{},"equipped_abilities":["GOBLIN_HEXER","GNOLL_SUMMONER"]}
	check(int(TagSets.stat_bonus(hexers).res_will) == 20,"의지 2 gives will")
	var ambush := {"level":3,"essences":{},"equipped_abilities":["GOBLIN_SHIV","GOBLIN_SHIV@fire","GOBLIN_SHIV@ice"]}
	check(int(TagSets.stat_bonus(ambush).ev) == 5,"기습 3 gives evasion")
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --editor --import --quit; godot --headless --path . --script res://tests/essences.gd`
Expected: FAIL — `essences.gd`를 불러올 수 없다는 파싱 오류.

- [ ] **Step 3: 카탈로그 데이터 쓰기**

`data/content/essences.json`:

```json
{
  "version": 1,
  "rows": {
    "PUSH": {"stats": {}, "role": "", "element": "", "school": "", "species": ""},
    "GUARD": {"stats": {}, "role": "", "element": "", "school": "", "species": ""},
    "SHOCKWAVE": {"stats": {}, "role": "", "element": "", "school": "", "species": ""},
    "BOMB": {"stats": {}, "role": "", "element": "", "school": "", "species": ""},
    "IRON_HIDE": {"stats": {}, "role": "", "element": "", "school": "", "species": ""},
    "HEAVY_STRIKE": {"stats": {}, "role": "", "element": "", "school": "", "species": ""},
    "THROWING_KNIFE": {"stats": {}, "role": "", "element": "", "school": "", "species": ""},
    "FIELD_DRESSING": {"stats": {}, "role": "", "element": "", "school": "", "species": ""},
    "LUNGE": {"stats": {}, "role": "", "element": "", "school": "", "species": ""},
    "RAT_GNAW": {"stats": {"ev": 1}, "role": "PACK", "element": "", "school": "", "species": "dcss_rat"},
    "LIZARD_TAIL": {"stats": {"ac": 1, "res_poison": 10}, "role": "GUARD", "element": "", "school": "", "species": "dcss_frilled_lizard"},
    "KOBOLD_SLING": {"stats": {"dex": 1}, "role": "ARCHER", "element": "", "school": "", "species": "kobold"},
    "GOBLIN_SHIV": {"stats": {"dex": 2}, "role": "AMBUSH", "element": "", "school": "", "species": "goblin"},
    "HOB_CLUB": {"stats": {"con": 1, "sh": 5}, "role": "GUARD", "element": "", "school": "", "species": "dcss_hobgoblin"},
    "ORC_CLEAVER": {"stats": {"str": 2, "con": 2}, "role": "BERSERK", "element": "", "school": "", "species": "dcss_orc"},
    "GNOLL_SPEAR": {"stats": {"con": 2}, "role": "BERSERK", "element": "", "school": "", "species": "dcss_gnoll"},
    "RIVER_RAT_SPLASH": {"stats": {"con": 1, "res_air": 10}, "role": "PACK", "element": "", "school": "", "species": "dcss_river_rat"},
    "FIRE_CALLER": {"name": "화염술사의 불씨", "stats": {"int": 2, "res_fire": 10}, "role": "CASTER", "element": "fire", "school": "fire", "species": "kobold_firecaller"},
    "FROST_IMP": {"name": "서리 도깨비의 숨", "stats": {"int": 2, "res_ice": 10}, "role": "CASTER", "element": "ice", "school": "ice", "species": "frost_imp"},
    "STORM_BAT": {"name": "폭풍 박쥐의 날개", "stats": {"dex": 1, "int": 1, "res_air": 10}, "role": "CASTER", "element": "air", "school": "air", "species": "storm_bat"},
    "GOBLIN_HEXER": {"name": "주술사의 부적", "stats": {"int": 2, "res_will": 10}, "role": "CASTER", "element": "will", "school": "hex", "species": "goblin_hexer"},
    "GNOLL_SUMMONER": {"name": "소환사의 뼈피리", "stats": {"int": 1, "con": 1}, "role": "CASTER", "element": "will", "school": "summon", "species": "gnoll_summoner"}
  }
}
```

- [ ] **Step 4: `essences.gd` 카탈로그 부분 쓰기**

`expedition/progression/essences.gd`:

```gdscript
extends RefCounted
## Essences: what a monster leaves behind and a member absorbs. Every catalog
## part is one; the caster essences have no part and give a spell instead.
## A variant id is "<BASE>@<element>": the base row with that element's tag
## and ten more points of that element's resistance.
const Abilities = preload("res://expedition/items/abilities.gd")
const ROLES := {"PACK":"무리","BERSERK":"광폭","AMBUSH":"기습","GUARD":"수호","ARCHER":"사수","CASTER":"술사"}
const ELEMENTS := {"fire":"화염","ice":"냉기","air":"전기","poison":"독","will":"의지"}
const MAX_TIER := 3
const MAX_LEVEL := 10
## How many spells stand ready at once: the floor HUD draws this many buttons.
const READY_SPELLS := 5
const FIRST_KILL_PERCENT := 100
const REPEAT_PERCENT := 25
const CASTER_BY_SCHOOL := {"fire":"FIRE_CALLER","ice":"FROST_IMP","air":"STORM_BAT","hex":"GOBLIN_HEXER","summon":"GNOLL_SUMMONER"}
const SPELL_CAP := {1:3,2:6,3:10}
static var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/essences.json"))
static var combat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/combat.json"))

static func base_of(id: String) -> String:
	return id.get_slice("@",0)

static func variant_element(id: String) -> String:
	return id.get_slice("@",1) if id.contains("@") else ""

static func has(id: String) -> bool:
	if id.is_empty() or not content.rows.has(base_of(id)): return false
	var element := variant_element(id)
	return element.is_empty() or ELEMENTS.has(element)

static func row(id: String) -> Dictionary:
	if not has(id): return {}
	var base: Dictionary = content.rows[base_of(id)]
	var result := {"name":str(base.get("name","")),"stats":(base.get("stats",{}) as Dictionary).duplicate(),
		"role":str(base.get("role","")),"element":str(base.get("element","")),
		"school":str(base.get("school","")),"species":str(base.get("species",""))}
	var element := variant_element(id)
	if not element.is_empty():
		result.element = element
		var key := "res_"+element
		result.stats[key] = int(result.stats.get(key,0))+10
	return result

## The part's item name for a part essence, the row's own name for a caster.
static func title(id: String) -> String:
	if not has(id): return ""
	var name: String = str(row(id).name)
	if name.is_empty(): name = str(Abilities.DEFINITIONS.get(base_of(id),{}).get("item",base_of(id)))
	var element := variant_element(id)
	return name if element.is_empty() else "%s %s" % [ELEMENTS[element],name]

static func stats(id: String, tier: int) -> Dictionary:
	var result: Dictionary = {}
	var base: Dictionary = row(id).get("stats",{})
	for key in base: result[key] = int(base[key])*clampi(tier,1,MAX_TIER)
	return result

static func role(id: String) -> String: return str(row(id).get("role",""))

static func element(id: String) -> String: return str(row(id).get("element",""))

static func school(id: String) -> String: return str(row(id).get("school",""))

## The absorbed tier; an essence put straight into a slot (fixtures, sims)
## counts as tier one.
static func tier(actor: Dictionary, id: String) -> int:
	if id.is_empty(): return 0
	var known: int = int(actor.get("essences",{}).get(id,0))
	if known > 0: return mini(known,MAX_TIER)
	return 1 if id in actor.get("equipped_abilities",[]) else 0

static func equipped(actor: Dictionary) -> Array:
	return actor.get("equipped_abilities",[]).filter(func(id): return has(str(id)))

static func slot_count(actor: Dictionary) -> int:
	return clampi(int(actor.get("level",1)),1,MAX_LEVEL)

static func spell_cap(tier: int) -> int:
	return int(SPELL_CAP[clampi(tier,1,MAX_TIER)])

static func active_power(tier: int, base: int) -> int:
	return base*(100+25*(clampi(tier,1,MAX_TIER)-1))/100
```

- [ ] **Step 5: `tag_sets.gd` 판정 부분 쓰기**

`expedition/progression/tag_sets.gd`:

```gdscript
extends RefCounted
## Sets: two or three equipped essences sharing a tag switch a bonus on.
## Role tags come from the species, element tags from a variant or a caster;
## the two are counted apart.
const Essences = preload("res://expedition/progression/essences.gd")
const TEXT := {
	"PACK":{2:"인접 아군당 피해 +1",3:"인접 아군당 피해 +2, 받는 피해 −1"},
	"BERSERK":{2:"체력 절반 미만이면 공격 지연 −15",3:"처치하면 HP 5 회복"},
	"AMBUSH":{2:"첫 공격 피해 +30%",3:"회피 +5, 첫 공격이 확정 명중"},
	"GUARD":{2:"방어 +2, 막기 +5",3:"인접 아군 방어 +2"},
	"ARCHER":{2:"원거리 사거리 +1",3:"원거리 공격 지연 −15"},
	"CASTER":{2:"최대 MP +5",3:"주문 실패율 −10"},
	"fire":{2:"화염 저항 +20, 화염 피해 +20%",3:"공격이 15% 확률로 화상"},
	"ice":{2:"냉기 저항 +20, 냉기 피해 +20%",3:"공격이 15% 확률로 둔화"},
	"air":{2:"전기 저항 +20, 전기 피해 +20%",3:"젖은 칸의 적에게 피해 +30%"},
	"poison":{2:"독 저항 +20, 독 피해 +20%",3:"공격이 15% 확률로 중독"},
	"will":{2:"의지 저항 +20, 상태이상 지속 +30%",3:"공격이 10% 확률로 혼란"}}
## The statuses a will resists and a will set lengthens: the hex school's.
const WILL_STATUSES := ["confuse","slow","bind","weak","brittle","distort","vulnerable","dominate"]

static func counts(actor: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id in Essences.equipped(actor):
		for tag in [Essences.role(id),Essences.element(id)]:
			if not str(tag).is_empty(): result[tag] = int(result.get(tag,0))+1
	return result

static func step(count: int) -> int:
	return 3 if count >= 3 else 2 if count >= 2 else 0

static func level(actor: Dictionary, tag: String) -> int:
	return step(int(counts(actor).get(tag,0)))

static func active(actor: Dictionary) -> Array:
	var result: Array = []
	var tally := counts(actor)
	for tag in TEXT:
		var reached := step(int(tally.get(tag,0)))
		if reached == 0: continue
		var lines := PackedStringArray([TEXT[tag][2]])
		if reached == 3: lines.append(TEXT[tag][3])
		result.append({"tag":tag,"name":str(Essences.ROLES.get(tag,Essences.ELEMENTS.get(tag,tag))),"level":reached,"text":" · ".join(lines)})
	return result

## What the sets add to the stat sheet and to the MP pool.
static func stat_bonus(actor: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if level(actor,"GUARD") >= 2: result.ac = 2; result.sh = 5
	if level(actor,"AMBUSH") >= 3: result.ev = 5
	if level(actor,"CASTER") >= 2: result.mp = 5
	for element in Essences.ELEMENTS:
		if level(actor,element) >= 2: result["res_"+element] = 20
	return result
```

- [ ] **Step 6: 통과 확인**

Run: `godot --headless --path . --editor --import --quit; godot --headless --path . --script res://tests/essences.gd`
Expected: `Essences: N checks, 0 failures`, 종료 코드 0.

- [ ] **Step 7: 커밋**

```bash
git add data/content/essences.json expedition/progression/essences.gd expedition/progression/tag_sets.gd tests/essences.gd
git commit -m "Add the essence catalog and tag set tallies

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- data/content/essences.json expedition/progression/essences.gd expedition/progression/tag_sets.gd tests/essences.gd
```

---

### Task 2: 스탯 시트와 전투 수치

**Files:**
- Create: `expedition/progression/stat_sheet.gd`
- Modify: `expedition/combat/combat_stats.gd` (전체 `stats` 함수와 preload)
- Modify: `expedition/combat/statuses.gd` (`apply`)
- Modify: `expedition/spells/spells.gd` (`strike`의 지배 시간)
- Modify: `data/content/combat.json` (`rings.poison.value`)
- Test: `tests/stats_resist.gd` (신규)

**Interfaces:**
- Consumes: Task 1의 `Essences.equipped/stats/tier/title`, `TagSets.stat_bonus`, `TagSets.WILL_STATUSES`
- Produces:
  - `StatSheet.KEYS`, `StatSheet.NAMES`, `StatSheet.RES := ["fire","ice","air","poison","will"]`, `RES_CAP := 80`, `BLOCK_CAP := 50`, `SHIELD_BLOCK := 15`, `CON_BASE := 10`, `HP_PER_CON := 3`
  - `StatSheet.sheet(s, actor) -> Dictionary` `{key: {"total": int, "parts": [{"from": String, "value": int}]}}` (`s`는 null이어도 된다)
  - `StatSheet.value(s, actor, key) -> int`, `StatSheet.bonus(actor, key) -> int`(이능·세트 몫만), `StatSheet.refresh_pools(s, actor) -> void`, `StatSheet.legacy_power(actor, axis: String, base: int) -> int`
  - `CombatStats.stats(s, actor)`의 `res`에 `will` 키가 생긴다.
  - `Statuses.resisted_ticks(s, victim, status, ticks) -> int`
  - 액터 필드 `pool_bonus: {"hp": int, "mp": int}`(없으면 0으로 본다)

- [ ] **Step 1: 실패하는 테스트 쓰기**

`tests/stats_resist.gd`:

```gdscript
extends SceneTree
## Every number a fight reads, where it came from, and the caps on it.
const Session = preload("res://expedition/run/session.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const Stats = preload("res://expedition/combat/combat_stats.gd")
const Rules = preload("res://expedition/combat/combat_rules.gd")
const Statuses = preload("res://expedition/combat/statuses.gd")
const Essences = preload("res://expedition/progression/essences.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	attributes()
	defence()
	resistance()
	monsters()
	print("Stats and resistance: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func hero_run():
	var s = Session.new_run(731,"sword")
	return s

func slot(actor: Dictionary, ids: Array, tier: int = 1) -> void:
	actor.level = maxi(int(actor.level),ids.size())
	actor.equipped_abilities = ids.duplicate()
	actor.essences = {}
	for id in ids: actor.essences[id] = tier

func attributes() -> void:
	var s = hero_run(); var hero: Dictionary = s.party[0]
	var sheet: Dictionary = StatSheet.sheet(s,hero)
	for key in StatSheet.KEYS: check(sheet.has(key) and StatSheet.NAMES.has(key),"sheet and names carry "+key)
	check(int(sheet.str.total) == 12 and sheet.str.parts[0].from == "종족","a human's strength is the species' twelve")
	check(int(sheet.con.total) == 10,"constitution starts at ten")
	var sword: Dictionary = Stats.content.weapons.sword
	check(int(Stats.stats(s,hero).damage) == int(sword.damage)+12/6,"a sword hits for its damage plus strength / 6")
	check(int(Stats.stats(s,hero).delay) == int(sword.delay),"no mastery shortens the swing")
	var hp: int = hero.max_hp; var mp: int = hero.max_mp
	slot(hero,["ORC_CLEAVER"]); StatSheet.refresh_pools(s,hero)
	sheet = StatSheet.sheet(s,hero)
	check(int(sheet.str.total) == 14 and sheet.str.parts.any(func(p): return p.from == Essences.title("ORC_CLEAVER") and int(p.value) == 2),"an essence adds strength under its own name")
	check(int(hero.max_hp) == hp+6 and int(hero.hp) == hp+6,"two constitution is six more HP")
	check(int(Stats.stats(s,hero).damage) == int(sword.damage)+14/6,"strength feeds the sword")
	slot(hero,["ORC_CLEAVER"],3); StatSheet.refresh_pools(s,hero)
	check(int(StatSheet.value(s,hero,"str")) == 18 and int(hero.max_hp) == hp+18,"tier three triples the essence")
	slot(hero,[""]); StatSheet.refresh_pools(s,hero)
	check(int(hero.max_hp) == hp and int(hero.hp) <= hp,"taking it off returns the HP")
	slot(hero,["FIRE_CALLER"]); StatSheet.refresh_pools(s,hero)
	check(int(hero.max_mp) == mp+2,"two mind is two more MP")
	check(int(hero.pool_bonus.mp) == 2 and int(hero.pool_bonus.hp) == 0,"the pools remember what they were given")
	slot(hero,["GOBLIN_SHIV"],3)
	check(int(StatSheet.value(s,hero,"ev")) == 18/3,"evasion is one per three dexterity")
	check(StatSheet.legacy_power(hero,"RANGED",10) == 10+2*6,"the old auto path reads essence dexterity")

func defence() -> void:
	var s = hero_run(); var hero: Dictionary = s.party[0]
	check(int(Stats.stats(s,hero).ac) == int(Stats.content.armours.robe.ac),"the robe's armour")
	slot(hero,["HOB_CLUB"])
	check(int(Stats.stats(s,hero).sh) == 2,"block without a shield is halved")
	hero.gear.shield = {"type":"shield"}
	check(int(Stats.stats(s,hero).sh) == StatSheet.SHIELD_BLOCK+5,"a shield adds its fifteen")
	slot(hero,["HOB_CLUB","HOB_CLUB@fire","HOB_CLUB@ice"],3)
	check(int(Stats.stats(s,hero).sh) == StatSheet.BLOCK_CAP,"block stops at fifty")

func resistance() -> void:
	var s = hero_run(); var hero: Dictionary = s.party[0]
	check(Stats.stats(s,hero).res.has("will"),"the will is a resistance")
	check(int(Stats.content.rings.poison.value) == 80,"the poison ring stops at eighty")
	hero.gear.ring = {"type":"fire"}
	slot(hero,["FIRE_CALLER"],3)
	check(int(Stats.stats(s,hero).res.fire) == StatSheet.RES_CAP,"sixty and thirty stop at eighty")
	var hp: int = hero.hp
	Rules.damage(s,{},hero,100,"fire")
	check(int(hero.hp) == hp-20,"eighty percent of a fire hit is turned")
	slot(hero,["GOBLIN_HEXER"],3)
	Statuses.apply(s,hero,"confuse",1000)
	check(int(hero.statuses.confuse) == int(s.time)+700,"thirty will shortens confusion by thirty percent")
	Statuses.apply(s,hero,"burn",1000)
	check(int(hero.statuses.burn) == int(s.time)+1000,"a burn is not the will's business")
	check(Statuses.resisted_ticks(s,hero,"dominate",100) == 70,"domination is shortened too")

func monsters() -> void:
	var s = hero_run()
	var foe: Dictionary = s.enemies[0]
	foe.ac = 3; foe.ev = 5; foe.sh = 90; foe.res = {"fire":50}
	var values: Dictionary = Stats.stats(s,foe)
	check(int(values.ac) == 3 and int(values.ev) == 5,"a monster's armour and evasion are its own")
	check(int(values.sh) == StatSheet.BLOCK_CAP,"a monster's block stops at fifty too")
	check(int(values.res.fire) == 50 and int(values.res.will) == 0,"a monster's resistances are its own")
	check(StatSheet.sheet(s,foe).ac.parts[0].from == "몬스터","a monster's numbers say so")
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --editor --import --quit; godot --headless --path . --script res://tests/stats_resist.gd`
Expected: FAIL — `stat_sheet.gd`를 불러올 수 없음.

- [ ] **Step 3: `stat_sheet.gd` 쓰기**

`expedition/progression/stat_sheet.gd`:

```gdscript
extends RefCounted
## Every number a fight reads, each with where it came from: the species, the
## gear, the essences and their sets. A monster carries its own numbers.
const Essences = preload("res://expedition/progression/essences.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
static var combat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/combat.json"))
const KEYS := ["str","dex","int","con","ac","ev","sh","res_fire","res_ice","res_air","res_poison","res_will"]
const NAMES := {"str":"근력","dex":"민첩","int":"정신","con":"체력","ac":"방어","ev":"회피","sh":"막기",
	"res_fire":"화염 저항","res_ice":"냉기 저항","res_air":"전기 저항","res_poison":"독 저항","res_will":"의지 저항"}
const RES := ["fire","ice","air","poison","will"]
const RES_CAP := 80
const BLOCK_CAP := 50
const SHIELD_BLOCK := 15
const CON_BASE := 10
const HP_PER_CON := 3
## What a monster's mind is taken to be when a spell asks.
const MONSTER_MIND := 12

static func species_row(actor: Dictionary) -> Dictionary:
	return combat.species.get(str(actor.get("species_id","human")),combat.species.human)

static func sheet(s, actor: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in KEYS: result[key] = {"total":0,"parts":[]}
	if bool(actor.get("enemy",false)):
		add(result,"ac","몬스터",int(actor.get("ac",0)))
		add(result,"ev","몬스터",int(actor.get("ev",3)))
		add(result,"sh","몬스터",int(actor.get("sh",0)))
		add(result,"int","몬스터",int(actor.get("int",MONSTER_MIND)))
		var res: Dictionary = actor.get("res",{})
		for element in RES: add(result,"res_"+element,"몬스터",int(res.get(element,0)))
		finish(result)
		return result
	var spec := species_row(actor)
	add(result,"str","종족",int(spec.str)); add(result,"dex","종족",int(spec.dex))
	add(result,"int","종족",int(spec.int)); add(result,"con","종족",int(spec.get("con",CON_BASE)))
	add(result,"str","물약",int(actor.get("str_bonus",0)))
	gear(result,actor)
	for id in Essences.equipped(actor):
		var values: Dictionary = Essences.stats(id,Essences.tier(actor,id))
		for key in values:
			if key in KEYS: add(result,key,Essences.title(id),int(values[key]))
	var sets: Dictionary = TagSets.stat_bonus(actor)
	for key in sets:
		if key in KEYS: add(result,key,"세트",int(sets[key]))
	# Dexterity lends evasion: one point for every three.
	add(result,"ev","민첩",total_of(result,"dex")/3)
	finish(result)
	return result

static func gear(result: Dictionary, actor: Dictionary) -> void:
	var worn: Dictionary = actor.get("gear",{})
	var armour: Dictionary = worn.get("armour",{})
	var armour_def: Dictionary = combat.armours.get(str(armour.get("type","")),{})
	if not armour_def.is_empty():
		var armour_name: String = str(armour_def.get("name","갑옷"))
		add(result,"ac",armour_name,int(armour_def.ac)+int(armour.get("enchant",0)))
		add(result,"ev",armour_name,-int(armour_def.ev_penalty))
	if not worn.get("shield",{}).is_empty(): add(result,"sh","방패",SHIELD_BLOCK)
	var ring: Dictionary = worn.get("ring",{})
	var ring_def: Dictionary = combat.rings.get(str(ring.get("type","")),{})
	if ring_def.is_empty(): return
	var stat: String = str(ring_def.stat)
	if stat == "ev": add(result,"ev",str(ring_def.name),int(ring_def.value))
	elif stat in RES: add(result,"res_"+stat,str(ring_def.name),int(ring_def.value))

static func add(result: Dictionary, key: String, from: String, amount: int) -> void:
	if amount != 0: result[key].parts.append({"from":from,"value":amount})

static func total_of(result: Dictionary, key: String) -> int:
	var total := 0
	for part in result[key].parts: total += int(part.value)
	return total

static func finish(result: Dictionary) -> void:
	for key in KEYS:
		var total := total_of(result,key)
		if key.begins_with("res_"): total = mini(RES_CAP,total)
		result[key].total = total

static func value(s, actor: Dictionary, key: String) -> int:
	return int(sheet(s,actor)[key].total)

## Only what essences and sets add: what the pools and the old auto path read.
static func bonus(actor: Dictionary, key: String) -> int:
	var total := 0
	for id in Essences.equipped(actor): total += int(Essences.stats(id,Essences.tier(actor,id)).get(key,0))
	return total+int(TagSets.stat_bonus(actor).get(key,0))

## Brings max HP and MP in line with the essences worn now. Only the change
## since the last call is applied, so level-ups and potions stay where they are.
static func refresh_pools(_s, actor: Dictionary) -> void:
	if bool(actor.get("enemy",false)): return
	var hp_bonus: int = bonus(actor,"con")*HP_PER_CON
	var mp_bonus: int = bonus(actor,"int")+int(TagSets.stat_bonus(actor).get("mp",0))
	var old: Dictionary = actor.get("pool_bonus",{})
	var hp_change: int = hp_bonus-int(old.get("hp",0))
	var mp_change: int = mp_bonus-int(old.get("mp",0))
	actor.max_hp = maxi(1,int(actor.max_hp)+hp_change)
	if int(actor.hp) > 0: actor.hp = clampi(int(actor.hp)+maxi(0,hp_change),1,int(actor.max_hp))
	actor.max_mp = maxi(0,int(actor.get("max_mp",0))+mp_change)
	actor.mp = clampi(int(actor.get("mp",0))+maxi(0,mp_change),0,int(actor.max_mp))
	actor.pool_bonus = {"hp":hp_bonus,"mp":mp_bonus}

## The old auto-battle path: a base number plus two per essence point of the
## attribute the axis reads.
static func legacy_power(actor: Dictionary, axis: String, base: int) -> int:
	var key: String = {"MELEE":"str","RANGED":"dex","MAGIC":"int"}.get(axis,"str")
	return base+2*bonus(actor,key)
```

- [ ] **Step 4: `combat_stats.gd`의 `stats`를 스탯 시트로 바꾸기**

파일 머리의 `const Mastery = preload("res://expedition/progression/mastery.gd")`를 다음 두 줄로 바꾼다.

```gdscript
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
```

`static func stats(_session, actor: Dictionary) -> Dictionary:`부터 반지 처리(`else: result.res[ring_def.stat] = int(ring_def.value)`)까지를 다음으로 바꾼다. 그 아래 `var statuses ...`부터 `return result`까지는 그대로 둔다.

```gdscript
static func stats(session, actor: Dictionary) -> Dictionary:
	var sheet: Dictionary = StatSheet.sheet(session, actor)
	var result := {"damage":int(actor.get("power", 7)), "delay":100, "ac":int(sheet.ac.total), "ev":int(sheet.ev.total), "sh":mini(StatSheet.BLOCK_CAP, int(sheet.sh.total)), "enc":0, "range":1, "brand":"", "trait":"", "res":{}, "power":0}
	for element in StatSheet.RES: result.res[element] = int(sheet["res_"+element].total)
	if not bool(actor.get("enemy", false)):
		var strength: int = int(sheet.str.total)
		var dexterity: int = int(sheet.dex.total)
		var gear: Dictionary = actor.get("gear", {})
		var weapon: Dictionary = gear.get("weapon", {})
		var weapon_def: Dictionary = content.weapons.get(str(weapon.get("type", "")), {})
		result.damage = 4 + strength / 6
		if not weapon_def.is_empty():
			result.trait = str(weapon_def.trait)
			# A bow is drawn with the hand's quickness; everything else is swung.
			var drive: int = dexterity if result.trait == "ranged" else strength
			result.damage = int(weapon_def.damage) + int(weapon.get("enchant", 0)) + drive / 6
			result.delay = int(weapon_def.delay)
			result.range = int(weapon_def.range) + (TagSets.range_bonus(actor) if result.trait == "ranged" else 0)
			result.brand = str(weapon.get("brand", ""))
			if result.trait == "focus": result.power += 4
		# A summoned creature carries no gear at all: it fights with the power
		# its own row in `combat.json.summons` gave it.
		if bool(actor.get("summoned", false)) and weapon_def.is_empty(): result.damage = int(actor.get("power", 7))
		var armour: Dictionary = gear.get("armour", {})
		var armour_def: Dictionary = content.armours.get(str(armour.get("type", "")), {})
		if not armour_def.is_empty(): result.enc = maxi(0, int(armour_def.enc) - strength / 5)
		var shield: bool = not gear.get("shield", {}).is_empty() and result.trait not in ["ranged", "focus"]
		if shield: result.enc += 2
		result.sh = mini(StatSheet.BLOCK_CAP, int(sheet.sh.total) if shield else int(sheet.sh.total) / 2)
		var ring: Dictionary = gear.get("ring", {})
		var ring_def: Dictionary = content.rings.get(str(ring.get("type", "")), {})
		if not ring_def.is_empty() and str(ring_def.stat) == "power": result.power += int(ring_def.value)
```

`TagSets.range_bonus`는 Task 4에서 만든다. 이 작업에서는 `tag_sets.gd` 끝에 다음 함수를 먼저 넣는다.

```gdscript
## 사수 2: a bow reaches one cell farther.
static func range_bonus(actor: Dictionary) -> int:
	return 1 if level(actor,"ARCHER") >= 2 else 0
```

- [ ] **Step 5: 의지 저항을 상태이상에 적용**

`expedition/combat/statuses.gd` 머리에 추가:

```gdscript
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
```

`apply`를 다음으로 바꾸고, 바로 위에 `resisted_ticks`를 둔다.

```gdscript
## A will turns the hex school's statuses aside: each point of 의지 저항 takes
## a percent off how long one lasts.
static func resisted_ticks(s, victim: Dictionary, status: String, ticks: int) -> int:
	if status not in TagSets.WILL_STATUSES: return ticks
	var will: int = maxi(0,StatSheet.value(s,victim,"res_will"))
	return ticks*(100-will)/100

static func apply(s, victim: Dictionary, status: String, ticks: int) -> void:
	ticks = resisted_ticks(s,victim,status,ticks)
	if ticks <= 0: return
	victim.statuses[status] = s.time+ticks
	if status == "burn": victim.get_or_add("status_power",{})["burn"] = BURN_DAMAGE
```

`expedition/spells/spells.gd`의 `strike` 안 지배 줄을 바꾼다.

```gdscript
	if status == "dominate" and ticks > 0: victim["dominated_until"] = s.time+Statuses.resisted_ticks(s,victim,"dominate",ticks)
```

- [ ] **Step 6: 독 저항 반지 80**

`data/content/combat.json`의 `"poison": {"name": "독 저항 반지", "stat": "poison", "value": 100}`에서 `100`을 `80`으로 바꾼다.

- [ ] **Step 7: 통과 확인**

Run: `godot --headless --path . --editor --import --quit; for t in stats_resist essences combat_basics model_b_combat enemy_turns; do godot --headless --path . --script "res://tests/$t.gd" 2>&1 | tail -1; done`
Expected: `stats_resist`와 `essences`는 0 failures. `combat_basics`, `model_b_combat`, `enemy_turns`도 0 failures. 이 셋이 숙련 등급을 더하던 피해·지연 값을 검사해서 깨지면, 기대값을 "무기 피해 + 근력/6", "무기 지연"으로 고친다(검사를 지우지 않는다).

- [ ] **Step 8: 커밋**

```bash
git commit -m "Read combat numbers from a stat sheet with sources and caps

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- expedition/progression/stat_sheet.gd expedition/progression/tag_sets.gd expedition/combat/combat_stats.gd expedition/combat/statuses.gd expedition/spells/spells.gd data/content/combat.json tests/stats_resist.gd
```

(앞 단계에서 고친 기존 테스트 파일이 있으면 경로를 이 목록에 더한다.)

---

### Task 3: 레벨 10, 슬롯, 흡수와 단계, 드롭, 이벤트

**Files:**
- Modify: `expedition/progression/essences.gd` (관리 함수 추가)
- Modify: `expedition/items/gear.gd` (`equip_part`, `unequip_part`, `grant_part`, `roll_part`, 새 `absorb_essence`)
- Modify: `expedition/run/descent.gd` (`gain_level_xp`, `depart`)
- Modify: `expedition/run/session.gd` (필드, `make_actor`, 래퍼, `push_event`)
- Modify: `expedition/actors/npc_roster.gd`, `expedition/spells/summons.gd`
- Test: `tests/essences.gd` (함수 추가)

**Interfaces:**
- Consumes: Task 1·2 전부
- Produces:
  - `Essences.can_manage(s) -> bool`, `sync_slots(actor)`, `absorb(s, actor, id) -> String`, `equip(s, actor, slot, id) -> bool`, `unequip(s, actor, slot) -> bool` (둘 다 `can_manage` 검사), `put(actor, slot, id) -> bool`, `take(actor, slot) -> bool` (장소·시점 검사 없음, NPC용), `spell_choices(actor, id) -> Array`, `choose_spell(s, actor, id, spell_id) -> bool`, `sync_spells(actor)`, `caster_tier(actor, school) -> int`, `drop_chance(s, species_id) -> int`
  - `Session.essence_seen: Dictionary`, `Session.events: Array`, `Session.push_event(event: Dictionary)`, `Session.absorb_essence(index, id) -> String`, `Session.choose_essence_spell(index, essence_id, spell_id) -> bool`
  - 이벤트 모양: `{"kind":"LEVEL_UP","actor":int,"level":int}`, `{"kind":"ESSENCE","id":String,"new":bool}`
  - 액터 필드: `essences: {id: tier}`, `essence_spells: {essence_id: spell_id}`, `equipped_abilities`는 길이 = 슬롯 수

- [ ] **Step 1: 실패하는 테스트 추가**

`tests/essences.gd`의 `run()`에서 `sets()` 다음 줄에 `levels()`, `absorbing()`, `drops()`를 넣고, 파일 끝에 붙인다.

```gdscript
func levels() -> void:
	var s = Session.new_run(731,"sword"); var hero: Dictionary = s.party[0]
	check(hero.equipped_abilities == [""],"a first-level hero has one slot")
	s.events.clear()
	check(s.gain_level_xp(hero,65) == 1 and hero.equipped_abilities.size() == 2,"level two opens a second slot")
	check(s.events.any(func(e): return e.kind == "LEVEL_UP" and int(e.level) == 2 and int(e.actor) == int(hero.id)),"a level-up is announced")
	s.gain_level_xp(hero,999999)
	check(int(hero.level) == 10 and hero.equipped_abilities.size() == 10,"level ten is the top, with ten slots")
	check(s.gain_level_xp(hero,999999) == 0,"nothing past ten")

func absorbing() -> void:
	var s = Session.new_run(731,"sword"); var hero: Dictionary = s.party[0]
	s.phase = "CAMP"
	s.parts_bag = {"ORC_CLEAVER":4}
	var hp: int = hero.max_hp
	check(s.absorb_essence(0,"ORC_CLEAVER") == "" and int(hero.essences.ORC_CLEAVER) == 1 and int(s.parts_bag.ORC_CLEAVER) == 3,"absorbing takes one from the bag")
	check(s.absorb_essence(0,"ORC_CLEAVER") == "" and s.absorb_essence(0,"ORC_CLEAVER") == "" and int(hero.essences.ORC_CLEAVER) == 3,"absorbing again raises the tier")
	check(s.absorb_essence(0,"ORC_CLEAVER") == "최고 단계" and int(s.parts_bag.ORC_CLEAVER) == 1,"the fourth is refused and stays in the bag")
	check(s.absorb_essence(0,"GOBLIN_SHIV") == "가방에 없음","nothing absorbed from an empty bag")
	check(int(hero.max_hp) == hp,"absorbing alone changes no pool")
	check(s.equip_part(0,0,"ORC_CLEAVER") and hero.equipped_abilities == ["ORC_CLEAVER"],"an absorbed essence fills a slot")
	check(int(hero.max_hp) == hp+18,"a tier-three orc is six constitution")
	check(not s.equip_part(0,1,"GOBLIN_SHIV"),"no second slot at level one")
	check(s.unequip_part(0,0) and hero.equipped_abilities == [""] and int(s.parts_bag.ORC_CLEAVER) == 1,"taking it off keeps it absorbed, not bagged")
	check(int(hero.max_hp) == hp and int(hero.essences.ORC_CLEAVER) == 3,"the pools drop, the tier stays")
	s.parts_bag["GOBLIN_SHIV"] = 1
	check(s.equip_part(0,0,"GOBLIN_SHIV") and int(hero.essences.GOBLIN_SHIV) == 1 and int(s.parts_bag.GOBLIN_SHIV) == 0,"equipping from the bag absorbs on the way")
	check(hero.rules.any(func(r): return r.skill == "GOBLIN_SHIV"),"a part essence brings its rule")
	s.phase = "BATTLE"
	s.parts_bag["RAT_GNAW"] = 1
	check(s.absorb_essence(0,"RAT_GNAW") == "전투 중" and not s.unequip_part(0,0),"nothing changes hands in a fight")
	check(Essences.put(hero,0,"ORC_CLEAVER") and hero.equipped_abilities[0] == "ORC_CLEAVER","the unchecked put works mid-fight, for NPCs")
	check(Essences.take(hero,0) and hero.equipped_abilities[0] == "","and so does take")
	s.phase = "EXPLORE"
	check(Essences.can_manage(s) == s.floor_state.safe(s),"a quiet corridor counts as safe")

func drops() -> void:
	var s = Session.new_run(731,"sword"); var hero: Dictionary = s.party[0]
	s.essence_seen.clear(); s.events.clear(); s.parts_bag.clear()
	var foe: Dictionary = s.enemies[0]
	foe.part_id = "GOBLIN_SHIV"; foe.species_id = "goblin"
	check(Essences.drop_chance(s,"goblin") == 100,"the first goblin always leaves its essence")
	s.damage(foe,9999,int(hero.id),"SLASH")
	check(int(s.parts_bag.get("GOBLIN_SHIV",0)) == 1,"the first kill drops it")
	check(s.essence_seen.has("goblin") and Essences.drop_chance(s,"goblin") == 25,"after that, one in four")
	check(s.events.any(func(e): return e.kind == "ESSENCE" and e.id == "GOBLIN_SHIV" and bool(e.new)),"a new essence is announced")
	s.parts_bag.clear()
	var dropped := 0
	for seed_value in range(40):
		var t = Session.new_run(seed_value,"sword")
		t.essence_seen["goblin"] = true; t.parts_bag.clear()
		var other: Dictionary = t.enemies[0]
		other.part_id = "GOBLIN_SHIV"; other.species_id = "goblin"
		t.damage(other,9999,int(t.party[0].id),"SLASH")
		dropped += int(t.parts_bag.get("GOBLIN_SHIV",0))
	check(dropped > 0 and dropped < 40,"repeat drops are seeded, not certain (%d of 40)" % dropped)
	var npc_only = Session.new_run(733,"sword")
	npc_only.parts_bag.clear()
	var lone: Dictionary = npc_only.enemies[0]
	lone.part_id = "GOBLIN_SHIV"; lone.species_id = "goblin"; lone.hp = 0
	npc_only.roll_part(lone,[])
	check(npc_only.parts_bag.is_empty(),"a hunt without the party drops nothing into the bag")
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/essences.gd`
Expected: FAIL — `events`, `absorb_essence`, `essence_seen`이 세션에 없음.

- [ ] **Step 3: `essences.gd`에 관리 함수 추가**

파일 끝에 붙인다.

```gdscript
## Essences change hands in town, at camp, or in a corridor with no foe in sight.
static func can_manage(s) -> bool:
	if s.phase in ["IDLE","CAMP"]: return true
	return s.phase == "EXPLORE" and s.floor_state.safe(s)

## Grows the slot row to the level. A level never falls, so slots never close.
static func sync_slots(actor: Dictionary) -> void:
	var slots: Array = actor.get("equipped_abilities",[])
	while slots.size() < slot_count(actor): slots.append("")
	actor.equipped_abilities = slots

## One from the bag into the member: a new essence at tier one, a known one a
## tier higher. The bag loses it for good.
static func absorb(s, actor: Dictionary, id: String) -> String:
	if not has(id): return "없는 이능"
	if int(s.parts_bag.get(id,0)) <= 0: return "가방에 없음"
	if int(actor.hp) <= 0: return "쓰러짐"
	if not can_manage(s): return "전투 중"
	var known: Dictionary = actor.get_or_add("essences",{})
	var before: int = int(known.get(id,0))
	if before >= MAX_TIER: return "최고 단계"
	s.parts_bag[id] = int(s.parts_bag[id])-1
	known[id] = before+1
	var chosen: Dictionary = actor.get_or_add("essence_spells",{})
	if not school(id).is_empty() and not chosen.has(id):
		var choices := spell_choices(actor,id)
		if not choices.is_empty(): chosen[id] = choices[0]
	sync_spells(actor)
	return ""

static func equip(s, actor: Dictionary, slot: int, id: String) -> bool:
	if not can_manage(s) or int(actor.hp) <= 0: return false
	return put(actor,slot,id)

static func unequip(s, actor: Dictionary, slot: int) -> bool:
	if not can_manage(s) or int(actor.hp) <= 0: return false
	return take(actor,slot)

## The slot change itself, with no question of where or when: NPCs re-slot on
## their own in the middle of a floor (plan 3/3), the player only through
## `equip`/`unequip`.
static func put(actor: Dictionary, slot: int, id: String) -> bool:
	sync_slots(actor)
	if slot < 0 or slot >= slot_count(actor): return false
	if int(actor.get("essences",{}).get(id,0)) <= 0 or id in actor.equipped_abilities: return false
	if not str(actor.equipped_abilities[slot]).is_empty(): take(actor,slot)
	actor.equipped_abilities[slot] = id
	actor.reservation = {}
	if Abilities.DEFINITIONS.has(id) and not actor.get("rules",[]).any(func(r): return r.skill == id):
		actor.get_or_add("rules",[]).append(Abilities.default_rule(id))
	sync_spells(actor)
	return true

static func take(actor: Dictionary, slot: int) -> bool:
	var slots: Array = actor.get("equipped_abilities",[])
	if slot < 0 or slot >= slots.size() or str(slots[slot]).is_empty(): return false
	var old: String = str(slots[slot])
	slots[slot] = ""
	actor.rules = actor.get("rules",[]).filter(func(r): return r.skill != old)
	actor.reservation = {}
	sync_spells(actor)
	return true

## The school's spells this essence's tier reaches, lowest level first.
static func spell_choices(actor: Dictionary, id: String) -> Array:
	var wanted := school(id)
	if wanted.is_empty(): return []
	var cap := spell_cap(maxi(1,tier(actor,id)))
	var result: Array = []
	for spell_id in combat.spells:
		var spell: Dictionary = combat.spells[spell_id]
		if str(spell.get("shape","")).is_empty(): continue
		if str(spell.get("school","")) == wanted and int(spell.level) <= cap: result.append(str(spell_id))
	result.sort_custom(func(a,b): return int(combat.spells[a].level) < int(combat.spells[b].level) or int(combat.spells[a].level) == int(combat.spells[b].level) and a < b)
	return result

static func choose_spell(s, actor: Dictionary, id: String, spell_id: String) -> bool:
	if not can_manage(s) or int(actor.get("essences",{}).get(id,0)) <= 0: return false
	if spell_id not in spell_choices(actor,id): return false
	actor.get_or_add("essence_spells",{})[id] = spell_id
	sync_spells(actor)
	return true

## `spells` is every spell an absorbed caster essence has chosen; `prepared`
## is the ones in a slot now, at most READY_SPELLS, in slot order.
static func sync_spells(actor: Dictionary) -> void:
	var chosen: Dictionary = actor.get("essence_spells",{})
	var known: Array = []
	for id in actor.get("essences",{}):
		var spell: String = str(chosen.get(id,""))
		if not school(str(id)).is_empty() and not spell.is_empty() and spell not in known: known.append(spell)
	var ready: Array = []
	for id in actor.get("equipped_abilities",[]):
		var spell: String = str(chosen.get(str(id),""))
		if not school(str(id)).is_empty() and not spell.is_empty() and spell not in ready and ready.size() < READY_SPELLS: ready.append(spell)
	actor.spells = known
	actor.prepared = ready

## The best tier among the slotted caster essences of that school.
static func caster_tier(actor: Dictionary, wanted: String) -> int:
	var best := 0
	for id in equipped(actor):
		if school(id) == wanted: best = maxi(best,tier(actor,id))
	return best

static func drop_chance(s, species_id: String) -> int:
	return REPEAT_PERCENT if s.essence_seen.has(species_id) else FIRST_KILL_PERCENT
```

- [ ] **Step 4: `gear.gd` 바꾸기**

머리의 `const Hexaco = ...` 아래에 추가:

```gdscript
const Essences = preload("res://expedition/progression/essences.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
```

`equip_part`, `unequip_part`, `grant_part`, `roll_part` 네 함수를 통째로 다음으로 바꾸고, `absorb_essence`, `choose_essence_spell`을 새로 둔다.

```gdscript
## A slot takes an essence the member has absorbed. One still in the bag is
## absorbed on the way at tier one, so the bag's one-tap equip keeps working.
static func equip_part(s, index: int, slot: int, id: String) -> bool:
	if index < 0 or index >= s.party.size() or not Essences.has(id): return false
	var actor: Dictionary = s.party[index]
	if not Essences.can_manage(s) or int(actor.hp) <= 0: return false
	Essences.sync_slots(actor)
	if slot < 0 or slot >= Essences.slot_count(actor) or id in actor.equipped_abilities: return false
	if int(actor.get("essences",{}).get(id,0)) <= 0 and not absorb_essence(s,index,id).is_empty(): return false
	if not Essences.equip(s,actor,slot,id): return false
	StatSheet.refresh_pools(s,actor)
	return true

## The slot empties; the essence stays absorbed and can be slotted again.
static func unequip_part(s, index: int, slot: int) -> bool:
	if index < 0 or index >= s.party.size(): return false
	var actor: Dictionary = s.party[index]
	if not Essences.unequip(s,actor,slot): return false
	StatSheet.refresh_pools(s,actor)
	return true

static func absorb_essence(s, index: int, id: String) -> String:
	if index < 0 or index >= s.party.size(): return "없는 인물"
	var actor: Dictionary = s.party[index]
	var reason: String = Essences.absorb(s,actor,id)
	if not reason.is_empty(): return reason
	StatSheet.refresh_pools(s,actor)
	s.message("%s · %s %d단계" % [actor.name,Essences.title(id),int(actor.essences[id])])
	return ""

static func choose_essence_spell(s, index: int, essence_id: String, spell_id: String) -> bool:
	if index < 0 or index >= s.party.size(): return false
	return Essences.choose_spell(s,s.party[index],essence_id,spell_id)

static func grant_part(s, id: String) -> void:
	if not Essences.has(id): return
	s.parts_bag[id] = int(s.parts_bag.get(id,0))+1
	s.message(Essences.title(id)+" 획득")

## Level XP to every hunter; the essence only to a hunt the party joined. The
## first of a species this run always leaves it, the rest one time in four.
static func roll_part(s, enemy: Dictionary, reward_actors: Variant = null) -> void:
	if not enemy.enemy or enemy.hp > 0 or enemy.get("part_rolled",false): return
	enemy.part_rolled = true
	var recipients: Array = s.alive() if reward_actors == null else reward_actors
	for actor in recipients:
		if s.gain_level_xp(actor,18+s.depth*8) > 0 and (actor in s.party or s.floor_state.visible.has(actor.pos)): s.message(actor.name+" · 레벨 %d" % actor.level)
	if not recipients.any(func(a): return a in s.party): return
	var id: String = str(enemy.get("part_id",""))
	if not Essences.has(id): return
	var species: String = str(enemy.get("species_id",""))
	var chance: int = Essences.drop_chance(s,species)
	s.essence_seen[species] = true
	if Hexaco.sample(s.seed_value,s.depth*10000+enemy.id,"essence",100) >= chance: return
	var fresh: bool = not s.party.any(func(a): return int(a.get("essences",{}).get(id,0)) > 0)
	s.parts_bag[id] = int(s.parts_bag.get(id,0))+1
	s.battle_stats.drops[id] = int(s.battle_stats.drops.get(id,0))+1
	s.message(Essences.title(id)+" 획득")
	s.push_event({"kind":"ESSENCE","id":id,"new":fresh})
```

`roll_part`의 옛 오토배틀 분기(`elif Growth.gain(...)`)는 위 코드에서 이미 빠졌다. 옛 모드도 레벨 경험치를 받는다.

- [ ] **Step 5: `descent.gd` 바꾸기**

머리에 추가:

```gdscript
const Essences = preload("res://expedition/progression/essences.gd")
```

`gain_level_xp`를 통째로 바꾼다.

```gdscript
static func gain_level_xp(s, actor: Dictionary, amount: int) -> int:
	var before := int(actor.get("level",1))
	actor.level_xp = int(actor.get("level_xp",0))+maxi(0,amount)
	while actor.level < Essences.MAX_LEVEL and actor.level_xp >= actor.level*actor.level*65:
		actor.level += 1
		actor.max_hp += 4; actor.hp = mini(actor.max_hp,actor.hp+4)
		actor.max_mp += 2; actor.mp = mini(actor.max_mp,actor.mp+2)
		if actor in s.party: s.push_event({"kind":"LEVEL_UP","actor":int(actor.id),"level":int(actor.level)})
	Essences.sync_slots(actor)
	return int(actor.level)-before
```

`depart`의 `s.bag.clear(); s.known.clear(); s.pending_choice.clear()` 줄 바로 아래에 추가:

```gdscript
	s.essence_seen.clear(); s.events.clear()
```

- [ ] **Step 6: `session.gd` 바꾸기**

`var parts_bag: Dictionary = {}` 아래에 추가:

```gdscript
## Species whose essence this run has already rolled for: the first kill of
## each always drops (`Essences.drop_chance`).
var essence_seen: Dictionary = {}
## What the UI should announce: level-ups and essences found. Newest last.
var events: Array = []
```

`make_actor`의 `"equipped_abilities":["",""],"cooldowns":{},"iron_guard":false,` 줄을 다음으로 바꾼다.

```gdscript
		"equipped_abilities":[""],"cooldowns":{},"iron_guard":false,
		"essences":{},"essence_spells":{},"pool_bonus":{"hp":0,"mp":0},
```

`func grant_part(id: String) -> void: Gear.grant_part(self,id)` 아래에 추가:

```gdscript
func push_event(event: Dictionary) -> void:
	events.append(event)
	while events.size() > 32: events.pop_front()

func absorb_essence(index: int, id: String) -> String: return Gear.absorb_essence(self,index,id)

func choose_essence_spell(index: int, essence_id: String, spell_id: String) -> bool: return Gear.choose_essence_spell(self,index,essence_id,spell_id)
```

- [ ] **Step 7: NPC와 소환수의 슬롯**

`expedition/actors/npc_roster.gd`에서

```gdscript
		actor.equipped_abilities = ["",""]; actor.rules = []
		if Hexaco.sample(s.seed_value,id,"npc_part",100) < 40:
			var parts: Array = Abilities.droppable()
			var part: String = parts[Hexaco.sample(s.seed_value,id,"npc_part_id",parts.size())]
			actor.equipped_abilities[0] = part; actor.rules = [Abilities.default_rule(part)]
```

를 다음으로 바꾼다.

```gdscript
		actor.equipped_abilities = [""]; actor.rules = []; actor.essences = {}
		if Hexaco.sample(s.seed_value,id,"npc_part",100) < 40:
			var parts: Array = Abilities.droppable()
			var part: String = parts[Hexaco.sample(s.seed_value,id,"npc_part_id",parts.size())]
			actor.essences[part] = 1
			actor.equipped_abilities[0] = part; actor.rules = [Abilities.default_rule(part)]
```

`expedition/spells/summons.gd`의 `pet.equipped_abilities = ["",""]; pet.rules = []`를 `pet.equipped_abilities = []; pet.rules = []`로 바꾼다.

- [ ] **Step 8: 통과 확인**

Run: `godot --headless --path . --script res://tests/essences.gd`
Expected: 0 failures.

- [ ] **Step 9: 기존 스위트에서 이 작업이 고칠 것**

Run: `for t in run_start test_loadout solo_balance npc_roster npc_behaviour recruit; do godot --headless --path . --script "res://tests/$t.gd" 2>&1 | tail -1; done`

다음 네 곳을 고친다.

- `tests/run_start.gd`의 `check(s.party[0].equipped_abilities == ["",""],"empty ability slots")` → `check(s.party[0].equipped_abilities == [""],"one empty slot at level one")`
- `tests/test_loadout.gd`의 `check(s.equip_part(0,0,"PUSH") and s.equip_part(0,1,"GUARD"),"granted parts can be equipped")` 바로 위에 `s.gain_level_xp(s.party[0],65)` 한 줄을 넣는다(두 번째 슬롯).
- `tests/solo_balance.gd`의 두 곳 `s.equip_part(0,0,"PUSH"); s.equip_part(0,1,"GUARD"); s.end_camp()` 앞에 각각 `s.gain_level_xp(s.party[0],65); ` 를 붙인다. 두 파츠 로드아웃으로 재던 균형 측정을 그대로 유지하기 위해서다.
- 나머지 스위트는 통과해야 한다. `npc_roster`, `npc_behaviour`, `recruit`가 NPC 슬롯 길이 2를 가정해 깨지면, 그 기대값을 레벨에 맞춘 길이로 고친다.

- [ ] **Step 10: 커밋**

```bash
git commit -m "Level cap ten with a slot per level; absorb essences in tiers; first kills always drop

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- expedition/progression/essences.gd expedition/items/gear.gd expedition/run/descent.gd expedition/run/session.gd expedition/actors/npc_roster.gd expedition/spells/summons.gd tests/essences.gd tests/run_start.gd tests/test_loadout.gd tests/solo_balance.gd
```

---

### Task 4: 태그 세트 전투 훅

**Files:**
- Modify: `expedition/progression/tag_sets.gd` (훅 추가)
- Modify: `expedition/combat/passives.gd`, `expedition/combat/combat_rules.gd`, `expedition/progression/stat_sheet.gd`, `expedition/spells/spells.gd`, `expedition/run/session.gd`
- Test: `tests/tag_sets.gd` (신규)

**Interfaces:**
- Consumes: Task 1~3
- Produces: `TagSets.fresh(target) -> bool`, `outgoing(s, attacker, target, amount) -> int`, `incoming(s, target, amount) -> int`, `sure_hit(attacker, target) -> bool`, `element_damage(source, element, amount) -> int`, `on_hit(s, attacker, target)`, `attack_delay(actor, cost, ranged) -> int`, `on_kill(s, killer)`, `status_ticks(caster, status, ticks) -> int`, `ally_guard(s, actor) -> int`, `ELEMENT_STATUS`. `Session.TagSets`, `Session.StatSheet`, `Session.Essences` 상수.

- [ ] **Step 1: 실패하는 테스트 쓰기**

`tests/tag_sets.gd`:

```gdscript
extends SceneTree
## What the sets do in a fight: every role and element step, wired into the
## hooks the fight already runs.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const Stats = preload("res://expedition/combat/combat_stats.gd")
const Rules = preload("res://expedition/combat/combat_rules.gd")
const Passives = preload("res://expedition/combat/passives.gd")
const Spells = preload("res://expedition/spells/spells.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	pack(); ambush(); elements(); berserk(); archer(); casters(); guard()
	print("Tag sets: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

## Hero at c, ally beside at c+(0,1), a fresh foe at c+(1,0) with no part.
func duo() -> Dictionary:
	var s = Session.new(731,false,true,true,2); s.depart(); s.manual_mode = true
	var c: Vector2i = Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 40; foe.max_hp = 40; foe.pos = c+Vector2i(1,0); foe.part_id = ""; foe.species_id = ""
	foe.res = {}; foe.statuses = {}; foe.sh = 0
	s.floor_state.observe(s)
	return {"s":s,"c":c,"hero":s.party[0],"ally":s.party[1],"foe":foe}

func slot(actor: Dictionary, ids: Array) -> void:
	actor.level = maxi(int(actor.level),ids.size())
	actor.equipped_abilities = ids.duplicate(); actor.essences = {}
	for id in ids: actor.essences[id] = 1

func pack() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["RAT_GNAW","RIVER_RAT_SPLASH"])
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 11,"무리 2: one more per adjacent ally")
	slot(d.hero,["RAT_GNAW","RIVER_RAT_SPLASH","RAT_GNAW@ice"])
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 12,"무리 3: two more per adjacent ally")
	check(Passives.outgoing(s,d.hero,d.foe,10) == 13,"the passives run the set too (rat passive +1, set +2)")
	check(TagSets.incoming(s,d.hero,5) == 4 and Passives.incoming(s,d.hero,5) == 4,"무리 3: one less taken")
	check(TagSets.outgoing(s,d.foe,d.hero,10) == 10,"a monster wears no set")

func ambush() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["GOBLIN_SHIV","GOBLIN_SHIV@fire"])
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 13,"기습 2: a fresh foe takes thirty percent more")
	d.foe.hp = 39
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 10,"a wounded foe does not")
	check(not TagSets.sure_hit(d.hero,d.foe),"기습 2 is no sure hit")
	slot(d.hero,["GOBLIN_SHIV","GOBLIN_SHIV@fire","GOBLIN_SHIV@ice"])
	check(int(StatSheet.value(s,d.hero,"ev")) >= 5 and StatSheet.sheet(s,d.hero).ev.parts.any(func(p): return p.from == "세트" and int(p.value) == 5),"기습 3 lends evasion")
	d.foe.sh = 100
	var clean := true
	for i in range(20):
		d.foe.hp = 40; d.foe.statuses = {}
		var out: Dictionary = Rules.attack(s,d.hero,d.foe)
		if bool(out.get("evaded",false)) or bool(out.get("blocked",false)): clean = false
	check(clean,"기습 3: the first blow on a fresh foe always lands")

func elements() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["LIZARD_TAIL@fire","HOB_CLUB@fire"])
	Rules.damage(s,d.hero,d.foe,10,"fire")
	check(int(d.foe.hp) == 28,"화염 2: fire hits a fifth harder")
	d.foe.hp = 40
	Rules.damage(s,d.hero,d.foe,10,"ice")
	check(int(d.foe.hp) == 30,"and only fire")
	slot(d.hero,["LIZARD_TAIL@fire","HOB_CLUB@fire","RAT_GNAW@fire"])
	var burns := 0
	for i in range(80):
		d.foe.hp = 40; d.foe.statuses = {}
		TagSets.on_hit(s,d.hero,d.foe)
		if d.foe.statuses.has("burn"): burns += 1
	check(burns > 0 and burns < 80,"화염 3: some blows set a burn (%d of 80)" % burns)
	slot(d.hero,["LIZARD_TAIL@air","HOB_CLUB@air","RAT_GNAW@air"])
	d.foe.hp = 39
	s.tile(d.foe.pos).wet = 50
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 13,"전기 3: a wet foe takes thirty percent more")
	s.tile(d.foe.pos).wet = 0
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 10,"a dry one does not")
	slot(d.hero,["GOBLIN_HEXER","GNOLL_SUMMONER"])
	check(TagSets.status_ticks(d.hero,"confuse",100) == 130 and TagSets.status_ticks(d.hero,"burn",100) == 100,"의지 2 lengthens the hex statuses only")
	d.foe.statuses = {}
	Spells.strike(s,d.hero,d.foe,{"school":"hex","status":"confuse","element":"physical"},0,0,100)
	check(int(d.foe.statuses.get("confuse",0)) == int(s.time)+130,"and a spell carries it")

func berserk() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["ORC_CLEAVER","GNOLL_SPEAR"])
	check(TagSets.attack_delay(d.hero,120,false) == 120,"광폭 2 waits for the wound")
	d.hero.hp = int(d.hero.max_hp)/2-1
	check(TagSets.attack_delay(d.hero,120,false) == 105,"광폭 2: a wounded swing is quicker")
	check(int(s.action_cost(d.hero,"ATTACK",d.foe.pos)) == int(Stats.stats(s,d.hero).delay)-15,"the session's attack cost reads it")
	slot(d.hero,["ORC_CLEAVER","GNOLL_SPEAR","ORC_CLEAVER@fire"])
	d.hero.hp = 20; d.foe.hp = 1
	s.damage(d.foe,5,int(d.hero.id),"SLASH")
	check(int(d.foe.hp) <= 0 and int(d.hero.hp) == 25,"광폭 3: a kill heals five")

func archer() -> void:
	var d := duo(); var s = d.s
	d.hero.gear.weapon = {"type":"bow","enchant":0}
	var bow: Dictionary = Stats.content.weapons.bow
	slot(d.hero,["KOBOLD_SLING","KOBOLD_SLING@ice"])
	check(int(Stats.stats(s,d.hero).range) == int(bow.range)+1,"사수 2: a bow reaches one farther")
	slot(d.hero,["KOBOLD_SLING","KOBOLD_SLING@ice","KOBOLD_SLING@fire"])
	check(TagSets.attack_delay(d.hero,int(bow.delay),true) == int(bow.delay)-15,"사수 3: a quicker draw")
	check(TagSets.attack_delay(d.hero,120,false) == 120,"but not for a sword")
	check(int(s.action_cost(d.hero,"ATTACK",d.foe.pos)) == int(bow.delay)-15,"the session's attack cost reads it")

func casters() -> void:
	var d := duo(); var s = d.s
	var mp: int = d.hero.max_mp
	slot(d.hero,["FIRE_CALLER","FROST_IMP"]); StatSheet.refresh_pools(s,d.hero)
	check(int(d.hero.max_mp) == mp+2+2+5,"술사 2: five more MP on top of the mind")

func guard() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["LIZARD_TAIL","HOB_CLUB","LIZARD_TAIL@fire"])
	check(StatSheet.sheet(s,d.ally).ac.parts.any(func(p): return p.from == "수호 세트" and int(p.value) == 2),"수호 3 covers the adjacent ally")
	check(not StatSheet.sheet(s,d.hero).ac.parts.any(func(p): return p.from == "수호 세트"),"but not the wearer")
	d.ally.pos = d.c+Vector2i(0,4)
	check(not StatSheet.sheet(s,d.ally).ac.parts.any(func(p): return p.from == "수호 세트"),"nor an ally out of reach")
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/tag_sets.gd`
Expected: FAIL — `TagSets.outgoing` 없음.

- [ ] **Step 3: `tag_sets.gd`에 훅 추가**

파일 끝에 붙인다.

```gdscript
const ELEMENT_STATUS := {"fire":"burn","ice":"slow","poison":"poison","will":"confuse"}

## A foe still at full health: what 기습 calls a first blow.
static func fresh(target: Dictionary) -> bool:
	return int(target.hp) >= int(target.max_hp)

static func outgoing(s, attacker: Dictionary, target: Dictionary, amount: int) -> int:
	if bool(attacker.get("enemy",false)) or target.is_empty(): return amount
	var pack := level(attacker,"PACK")
	if pack > 0: amount += (1 if pack == 2 else 2)*int(s.Passives.adjacent_allies(s,attacker))
	if level(attacker,"AMBUSH") >= 2 and fresh(target): amount = amount*13/10
	if level(attacker,"air") >= 3:
		var ground: Dictionary = s.tile(target.pos)
		if ground.terrain == "water" or int(ground.wet) > 0: amount = amount*13/10
	return amount

static func incoming(_s, target: Dictionary, amount: int) -> int:
	if level(target,"PACK") >= 3: return maxi(1,amount-1)
	return amount

static func sure_hit(attacker: Dictionary, target: Dictionary) -> bool:
	return not bool(attacker.get("enemy",false)) and level(attacker,"AMBUSH") >= 3 and fresh(target)

static func element_damage(source: Dictionary, element: String, amount: int) -> int:
	var key := element.to_lower()
	if not source.is_empty() and key in ["fire","ice","air","poison"] and level(source,key) >= 2: return amount*12/10
	return amount

## Element step three: a landed blow may hang the element's own status.
static func on_hit(s, attacker: Dictionary, target: Dictionary) -> void:
	if bool(attacker.get("enemy",false)) or int(target.hp) <= 0: return
	for element in ELEMENT_STATUS:
		if level(attacker,element) < 3: continue
		var chance := 10 if element == "will" else 15
		if s.CombatRules.roll(s,attacker,target,"set_"+element,100) < chance:
			s.Statuses.apply(s,target,ELEMENT_STATUS[element],200 if element == "will" else 300)

static func attack_delay(actor: Dictionary, cost: int, ranged: bool) -> int:
	if level(actor,"BERSERK") >= 2 and int(actor.hp)*2 < int(actor.max_hp): cost -= 15
	if ranged and level(actor,"ARCHER") >= 3: cost -= 15
	return maxi(40,cost)

static func on_kill(_s, killer: Dictionary) -> void:
	if bool(killer.get("enemy",false)) or int(killer.hp) <= 0 or level(killer,"BERSERK") < 3: return
	killer.hp = mini(int(killer.max_hp),int(killer.hp)+5)

static func status_ticks(caster: Dictionary, status: String, ticks: int) -> int:
	if status in WILL_STATUSES and level(caster,"will") >= 2: return ticks*13/10
	return ticks

## 수호 3 on an adjacent friend lends this actor two armour; it never stacks.
static func ally_guard(s, actor: Dictionary) -> int:
	if s == null or bool(actor.get("enemy",false)) or not actor.has("pos"): return 0
	for other in s.party+s.npcs:
		if int(other.id) == int(actor.id) or int(other.hp) <= 0 or s.side_of(other) != s.side_of(actor): continue
		if s.melee_reach(actor.pos,other.pos) and level(other,"GUARD") >= 3: return 2
	return 0
```

- [ ] **Step 4: 훅 연결**

`expedition/combat/passives.gd` 머리에 `const TagSets = preload("res://expedition/progression/tag_sets.gd")`를 넣는다. `outgoing`의 마지막 `return amount`를 `return TagSets.outgoing(s,attacker,target,amount)`로, `incoming`의 마지막 `return amount`를 `return TagSets.incoming(s,target,amount)`로 바꾼다.

`expedition/combat/combat_rules.gd` 머리에 `const TagSets = preload("res://expedition/progression/tag_sets.gd")`를 넣는다. `attack` 안에서

```gdscript
	var dodge := clampi(int(defense.ev) * 2, 5, 45)
	if source.get("statuses", {}).has("distort"): dodge = mini(95, dodge + 30)
	if roll(s, source, target, "dodge", 100) < dodge:
```

를 다음으로 바꾸고,

```gdscript
	var sure: bool = TagSets.sure_hit(source, target)
	var dodge := clampi(int(defense.ev) * 2, 5, 45)
	if source.get("statuses", {}).has("distort"): dodge = mini(95, dodge + 30)
	if not sure and roll(s, source, target, "dodge", 100) < dodge:
```

`if roll(s, source, target, "block", 100) < int(defense.sh):`를 `if not sure and roll(s, source, target, "block", 100) < int(defense.sh):`로 바꾼다. `Effects.on_attack(s,source,target,out)` 줄 바로 아래에 `TagSets.on_hit(s,source,target)`를 넣는다.

같은 파일 `damage`에서

```gdscript
	var amount := raw
	if element not in ["physical", "SLASH", "IMPACT", "RETALIATE"]:
		var resistance: int = maxi(0,int(Stats.stats(s, target).res.get(element.to_lower(), 0))-penetration)
		amount = maxi(0, raw * (100 - resistance) / 100)
```

를 다음으로 바꾼다.

```gdscript
	var amount: int = TagSets.element_damage(source, element, raw)
	if element not in ["physical", "SLASH", "IMPACT", "RETALIATE"]:
		var resistance: int = maxi(0,int(Stats.stats(s, target).res.get(element.to_lower(), 0))-penetration)
		amount = maxi(0, amount * (100 - resistance) / 100)
```

`expedition/progression/stat_sheet.gd`의 `sheet`에서 세트 루프(`for key in sets: ...`) 바로 아래에 넣는다.

```gdscript
	add(result,"ac","수호 세트",TagSets.ally_guard(s,actor))
```

`expedition/spells/spells.gd` 머리에 `const TagSets = preload("res://expedition/progression/tag_sets.gd")`를 넣는다. `strike`와 `mark` 두 함수 안에 있는 `var status: String = str(spell.get("status",""))` 줄 바로 아래에 각각 넣는다.

```gdscript
	ticks = TagSets.status_ticks(caster,status,ticks)
```

`expedition/run/session.gd` 상수 목록(`const Statuses = ...` 아래)에 넣는다.

```gdscript
const Essences = preload("res://expedition/progression/essences.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
```

`action_cost`의 `"ATTACK":` 분기에서 검술 7등급 연속 공격 줄(`if manual_mode and actor.get("last_action_kind","") == "ATTACK" and ... Mastery.rank(actor,"sword") >= 7: cost = maxi(60,cost-20)`)을 다음으로 바꾼다.

```gdscript
			cost = TagSets.attack_delay(actor,cost,str(CombatStats.stats(self,actor).trait) == "ranged")
```

`after_damage`의 처치 분기에서 `Mastery.award(hunters,int(target.id),18+depth*8)` 줄 바로 아래에 넣는다.

```gdscript
		if not attacker.is_empty(): TagSets.on_kill(self,attacker)
```

- [ ] **Step 5: 통과 확인**

Run: `godot --headless --path . --editor --import --quit; for t in tag_sets essences stats_resist combat_basics model_b_combat parts; do godot --headless --path . --script "res://tests/$t.gd" 2>&1 | tail -1; done`
Expected: `tag_sets`, `essences`, `stats_resist`, `combat_basics`, `model_b_combat`는 0 failures. `parts`는 Task 5에서 고칠 두 줄 말고는 통과해야 한다.

- [ ] **Step 6: 커밋**

```bash
git commit -m "Wire role and element sets into the fight

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- expedition/progression/tag_sets.gd expedition/progression/stat_sheet.gd expedition/combat/passives.gd expedition/combat/combat_rules.gd expedition/spells/spells.gd expedition/run/session.gd tests/tag_sets.gd
```

---

### Task 5: 숙련·옛 성장 대신 스탯과 사냥 참여 기록

**Files:**
- Create: `expedition/progression/hunt.gd`
- Modify: `expedition/combat/combat_rules.gd`, `expedition/items/abilities.gd`, `expedition/spells/spells.gd`, `expedition/run/session.gd`, `expedition/items/gear.gd`, `expedition/actors/floor_tactics_adapter.gd`, `expedition/ai/parts_candidates.gd`
- Modify (기존 테스트): `tests/integration.gd`, `tests/parts.gd`
- Test: `tests/essences.gd` (함수 추가)

**Interfaces:**
- Consumes: Task 1~4
- Produces: `Hunt.record(actor, enemy_id)`. `Abilities.power(s, actor, def, id: String = "") -> int`(기존 호출은 그대로 동작). `Spells.failure`가 정신과 주문 이능 단계를 읽는다. `Spells.mind_bonus(s, caster) -> int`.

- [ ] **Step 1: 실패하는 테스트 추가**

`tests/essences.gd`의 `run()`에 `actives()`를 더하고 파일 끝에 붙인다. 머리에 `const StatSheet = preload("res://expedition/progression/stat_sheet.gd")`, `const Stats = preload("res://expedition/combat/combat_stats.gd")`, `const Spells = preload("res://expedition/spells/spells.gd")`, `const Hunt = preload("res://expedition/progression/hunt.gd")`를 더한다.

```gdscript
func actives() -> void:
	var s = Session.new_run(731,"sword"); var hero: Dictionary = s.party[0]
	var club: Dictionary = Abilities.DEFINITIONS.HOB_CLUB
	hero.level = 1; hero.equipped_abilities = ["HOB_CLUB"]; hero.essences = {"HOB_CLUB":1}
	check(Abilities.power(s,hero,club,"HOB_CLUB") == int(club.damage)+(12-10)/2,"a part hits for its damage plus half the strength over ten")
	hero.essences.HOB_CLUB = 3
	check(Abilities.power(s,hero,club,"HOB_CLUB") == Essences.active_power(3,int(club.damage)+1),"tier three hits half again as hard")
	check(Abilities.power(s,hero,club) == int(club.damage)+1,"without an id the part counts as tier one")
	var sling: Dictionary = Abilities.DEFINITIONS.KOBOLD_SLING
	hero.equipped_abilities = ["GOBLIN_SHIV"]; hero.essences = {"GOBLIN_SHIV":3}
	check(Abilities.power(s,hero,sling,"KOBOLD_SLING") == int(sling.damage)+(18-10)/2,"a ranged part reads dexterity")
	var foe: Dictionary = s.enemies[0]
	check(Abilities.power(s,foe,club,"HOB_CLUB") == int(club.damage),"a monster hits for the listed damage")
	hero.skill_xp = {"sword":2500}
	hero.equipped_abilities = [""]; hero.essences = {}
	check(int(Stats.stats(s,hero).damage) == int(Stats.content.weapons.sword.damage)+2,"old sword mastery adds nothing any more")
	Hunt.record(hero,int(foe.id))
	check(hero.usage.has(int(foe.id)),"a strike marks the member as a hunter")
	check(s.hunt_recipients(foe,{}).has(hero),"and the hunt counts them")
	hero.essences = {"FIRE_CALLER":2}; hero.equipped_abilities = ["FIRE_CALLER"]
	var enc: int = int(Stats.stats(s,hero).enc)
	check(Spells.failure(s,hero,"fire_4") == clampi(8+4*9+enc*5-(12+4)-20,0,85),"failure reads mind and the caster tier")
	s.manual_mode = false
	hero.essences = {"ORC_CLEAVER":1}; hero.equipped_abilities = ["ORC_CLEAVER"]
	check(StatSheet.legacy_power(hero,"MELEE",18) == 22,"the old auto path reads essence strength")
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/essences.gd`
Expected: FAIL — `hunt.gd` 없음.

- [ ] **Step 3: `hunt.gd` 쓰기**

`expedition/progression/hunt.gd`:

```gdscript
extends RefCounted
## Who took part in bringing a monster down: whoever struck, shot or cast at it.
## `Session.hunt_recipients` reads this to share the kill's level XP and loot.
static func record(actor: Dictionary, enemy_id: int) -> void:
	if enemy_id < 0: return
	if not actor.has("usage"): actor.usage = {}
	actor.usage[enemy_id] = int(actor.usage.get(enemy_id,0))+1
```

- [ ] **Step 4: 전투 규칙에서 숙련 효과 빼기**

`expedition/combat/combat_rules.gd`:
- 머리의 `const Mastery = ...`, `const Effects = ...` 두 줄을 `const Hunt = preload("res://expedition/progression/hunt.gd")` 한 줄로 바꾼다.
- `Mastery.record(source,int(target.id),Mastery.weapon_axis(str(source.get("gear",{}).get("weapon",{}).get("type","sword"))))`를 `Hunt.record(source,int(target.id))`로 바꾼다.
- `Effects.on_dodge(s,target,source)`, `raw = Effects.attack_raw(s,source,target,raw)`, `Effects.on_attack(s,source,target,out)` 세 줄을 지운다(검술 출혈·반격·치명타와 검·화염 융합은 없어진다).

`expedition/items/abilities.gd`:
- 머리에 넣는다.

```gdscript
const Essences = preload("res://expedition/progression/essences.gd")
const Hunt = preload("res://expedition/progression/hunt.gd")
```

- `power`를 통째로 바꾼다.

```gdscript
## A monster hits for the listed damage. A member adds half of the reading
## attribute over ten, then the essence's tier: +25% a tier.
static func power(s, actor: Dictionary, def: Dictionary, id: String = "") -> int:
	if actor.enemy: return int(def.damage)
	var key: String = {"RANGED":"dex","MAGIC":"int"}.get(str(def.axis),"str")
	var base: int = int(def.damage)+maxi(0,s.StatSheet.value(s,actor,key)-10)/2
	return Essences.active_power(maxi(1,Essences.tier(actor,id)),base)
```

- `execute`의 숙련 기록 블록

```gdscript
	if s.manual_mode and not actor.enemy:
		var axis: String = "bow" if DEFINITIONS[id].axis == "RANGED" else "hex" if DEFINITIONS[id].axis == "MAGIC" else ""
		if not axis.is_empty():
			var affected: Array = cells(s,actor,id,target)
			for foe in s.enemies:
				if foe.hp > 0 and foe.pos in affected:
					s.Mastery.record(actor,int(foe.id),axis)
```

를 다음으로 바꾼다.

```gdscript
	if not actor.enemy:
		var affected: Array = cells(s,actor,id,target)
		for foe in s.enemies:
			if foe.hp > 0 and foe.pos in affected: Hunt.record(actor,int(foe.id))
```

- `resolve` 안의 `power(s,actor,def)` 세 곳을 모두 `power(s,actor,def,id)`로 바꾼다.

`expedition/spells/spells.gd`:
- 머리의 `const Mastery = ...`, `const Effects = ...`를 다음으로 바꾼다.

```gdscript
const Hunt = preload("res://expedition/progression/hunt.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
```

- `failure`를 통째로 바꾸고, 바로 아래에 `mind_bonus`를 둔다.

```gdscript
static func failure(s, caster: Dictionary, id: String) -> int:
	var spell: Dictionary = definition(id)
	if spell.is_empty(): return 100
	var mind: int = StatSheet.value(s,caster,"int")
	var tier: int = Essences.caster_tier(caster,str(spell.school))
	var focus: int = 10 if TagSets.level(caster,"CASTER") >= 3 else 0
	return clampi(8 + int(spell.level) * 9 + int(Stats.stats(s,caster).enc) * 5 - mind - tier * 10 - focus, 0, 85)

## Half the mind over ten: what a caster adds to a spell's power.
static func mind_bonus(s, caster: Dictionary) -> int:
	return maxi(0,StatSheet.value(s,caster,"int")-10)/2
```

- `Mastery.rank(caster,school)`가 들어간 위력 세 줄을 바꾼다.
  - `shaped_cast`: `if power > 0: power += Mastery.rank(caster,school) + int(Stats.stats(s,caster).power)` → `if power > 0: power += mind_bonus(s,caster) + int(Stats.stats(s,caster).power)`
  - `mark`: `var force: int = power + Mastery.rank(caster,school) + int(Stats.stats(s,caster).power)` → `var force: int = power + mind_bonus(s,caster) + int(Stats.stats(s,caster).power)`
  - `relic_cast`: `var power: int = int(spell.power) + Mastery.rank(caster,school) + int(Stats.stats(s,caster).power)` → `var power: int = int(spell.power) + mind_bonus(s,caster) + int(Stats.stats(s,caster).power)`
- `power = Effects.fire_power(caster,power)` 줄(`shaped_cast`의 `"fire":` 분기)과 `if school == "fire": power = Effects.fire_power(caster,power)` 줄(`relic_cast`)을 지운다.
- `relic_cast`의 `var penetration := 20 if Mastery.rank(caster,"fire") >= 7 else 0`을 `var penetration := 0`으로 바꾼다.
- `if bool(victim.enemy): Mastery.record(caster,int(victim.id),school)`(`strike`, `mark`)와 `if victim.enemy: Mastery.record(caster,int(victim.id),school)`(`relic_cast`)를 `Hunt.record(caster,int(victim.id))`로 바꾼다. 앞의 `if`는 그대로 둔다.
- `if school == "fire": Effects.on_spell_hit(s,caster,victim,school)`(`strike`)와 `Effects.on_spell_hit(s,caster,victim,school)`(`relic_cast`)를 지운다.
- `learnable`의 `if Mastery.rank(actor, str(spell.school)) < int(spell.level) - 1: return "숙련 부족"` 줄을 지운다(함수 전체는 Task 6에서 지운다).

`expedition/run/session.gd`:
- `attack_preview`의 옛 모드 줄 `var old_hit := TurnCore.physical(Growth.power(old_actor,"MELEE",18) * old_actor.attack_factor / 100, 1000, 0, 2)`에서 `Growth.power(old_actor,"MELEE",18)`을 `StatSheet.legacy_power(old_actor,"MELEE",18)`로 바꾼다.
- `act_as`의 옛 모드 공격 두 줄을 바꾼다.

```gdscript
				if not actor.enemy and victim.enemy: Hunt.record(actor,int(victim.id))
				var hit := TurnCore.physical(StatSheet.legacy_power(actor,"MELEE",18) * actor.attack_factor / 100, 1000, 0, 2)
```

- 상수 목록에 `const Hunt = preload("res://expedition/progression/hunt.gd")`를 넣는다.
- `if not manual_mode and not target.enemy: amount = Growth.incoming(target,amount)` 줄을 지운다(방어 투자는 없어졌다).
- `Mastery.award(hunters,int(target.id),18+depth*8)` 줄을 지운다.

`expedition/items/gear.gd`의 `equip_gear` 안 숙련 따라잡기 네 줄을 지운다.

```gdscript
	if slot == "weapon" and not previous.is_empty():
		var old_axis := Mastery.weapon_axis(str(previous.type))
		var new_axis := Mastery.weapon_axis(str(item.type))
		if old_axis != new_axis and Mastery.rank(actor,old_axis) > 0: Mastery.catchup(actor,new_axis)
```

`expedition/actors/floor_tactics_adapter.gd`의 `s.Growth.power(actor,"MELEE",18)`을 `s.StatSheet.legacy_power(actor,"MELEE",18)`로, `expedition/ai/parts_candidates.gd`의 `s.Growth.power(actor,"MELEE",8)`을 `s.StatSheet.legacy_power(actor,"MELEE",8)`로 바꾼다.

- [ ] **Step 5: 기존 테스트 세 줄 고치기**

- `tests/integration.gd`의 `var shove: int = int(Session.Abilities.DEFINITIONS.PUSH.damage)+Session.Mastery.rank(hero,"sword")`와 그 위 주석을 다음으로 바꾼다.

```gdscript
	# The shove carries the hero's strength: half of it over ten.
	var shove: int = Session.Abilities.power(s,hero,Session.Abilities.DEFINITIONS.PUSH,"PUSH")
```

- `tests/parts.gd`의 `check(d.hero.hp == hp-s.Growth.incoming(d.hero,14),"club lands for its announced damage")` → `check(d.hero.hp == hp-14,"club lands for its announced damage")`
- `tests/parts.gd`의 `d.foe.hp == foe_hp-s.Growth.power(d.hero,"MELEE",14)` → `d.foe.hp == foe_hp-Abilities.power(s,d.hero,Abilities.DEFINITIONS.HOB_CLUB,"HOB_CLUB")`

- [ ] **Step 6: 통과 확인**

Run: `godot --headless --path . --editor --import --quit; for t in essences stats_resist tag_sets integration combat_basics model_b_combat enemy_turns companion_tactics autobattle; do godot --headless --path . --script "res://tests/$t.gd" 2>&1 | tail -1; done`
Expected: 모두 0 failures. `model_b_mastery`와 `model_b_spells`의 숙련·배우기 검사는 이 단계에서 깨질 수 있다(Task 6·7).

- [ ] **Step 7: 커밋**

```bash
git commit -m "Grow blows and spells from stats and tiers; keep only hunt participation from mastery

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- expedition/progression/hunt.gd expedition/combat/combat_rules.gd expedition/items/abilities.gd expedition/spells/spells.gd expedition/run/session.gd expedition/items/gear.gd expedition/actors/floor_tactics_adapter.gd expedition/ai/parts_candidates.gd tests/essences.gd tests/integration.gd tests/parts.gd
```

---

### Task 6: 주문은 주문 이능에서, 주문서 없애기

**Files:**
- Modify: `expedition/run/descent.gd` (`depart`의 시작 장비)
- Modify: `expedition/run/camp.gd`, `expedition/run/session.gd`, `expedition/spells/spells.gd`, `expedition/items/curios.gd`, `expedition/ui/screens/camp_screen.gd`
- Modify: `data/content/combat.json` (`books`, `loot.books`, 주문 행의 `book`)
- Modify (기존 테스트): `tests/spellbooks.gd`, `tests/start_kit.gd`, `tests/model_b_spells.gd`
- Test: `tests/essence_spells.gd` (신규)

**Interfaces:**
- Consumes: Task 1~5, 특히 `Essences.CASTER_BY_SCHOOL`, `sync_spells`, `spell_choices`, `choose_spell`, `caster_tier`
- Produces: 마법 킷의 주인공은 `essences = {<계열 주문 이능>: 1}`, 첫 슬롯에 그 이능, `essence_spells`에 킷 주문, `prepared = [킷 주문]`. `Camp.PREPARED_SLOTS == Essences.READY_SPELLS`. 세션에서 `learn_spell`, `prepare_spell`, `grant_book`, `book_tier`, `random_book`이 사라진다.

- [ ] **Step 1: 실패하는 테스트 쓰기**

`tests/essence_spells.gd`:

```gdscript
extends SceneTree
## Spells come from caster essences: the tier sets the reach, the mind and the
## tier set the failure, and no book is left anywhere.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Spells = preload("res://expedition/spells/spells.gd")
const Stats = preload("res://expedition/combat/combat_stats.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	kits(); tiers(); failure(); casting(); no_books()
	print("Essence spells: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func kits() -> void:
	for school in Essences.CASTER_BY_SCHOOL:
		var s = Session.new_run(7,school); var hero: Dictionary = s.party[0]
		var essence: String = str(Essences.CASTER_BY_SCHOOL[school])
		check(int(hero.essences.get(essence,0)) == 1 and hero.equipped_abilities[0] == essence,"the %s kit starts with its caster essence slotted" % school)
		check(hero.prepared == ["%s_1" % school] and hero.spells == ["%s_1" % school],"the %s kit has its first spell ready" % school)
		check(not hero.has("books"),"the %s kit carries no book" % school)
	var sword = Session.new_run(7,"sword")
	check(sword.party[0].essences.is_empty() and sword.party[0].prepared.is_empty(),"a swordsman starts with no essence and no spell")
	var fire = Session.new_run(7,"fire")
	check(int(fire.party[0].max_mp) == 18+2,"the fire kit's essence lends two MP")

func tiers() -> void:
	var s = Session.new_run(7,"fire"); var hero: Dictionary = s.party[0]
	s.phase = "CAMP"
	check(Essences.spell_choices(hero,"FIRE_CALLER") == ["fire_1","fire_2","fire_3"],"tier one reaches the third level")
	check(not s.choose_essence_spell(0,"FIRE_CALLER","fire_4"),"the fourth is out of reach")
	check(s.choose_essence_spell(0,"FIRE_CALLER","fire_3") and hero.prepared == ["fire_3"],"a chosen spell is the one ready")
	s.parts_bag["FIRE_CALLER"] = 1
	check(s.absorb_essence(0,"FIRE_CALLER") == "" and Essences.spell_choices(hero,"FIRE_CALLER").size() == 6,"tier two reaches the sixth")
	check(s.choose_essence_spell(0,"FIRE_CALLER","fire_6") and hero.prepared == ["fire_6"],"and takes it")
	s.parts_bag["GOBLIN_HEXER"] = 1
	check(s.absorb_essence(0,"GOBLIN_HEXER") == "" and hero.essence_spells.GOBLIN_HEXER == "hex_1","a new caster essence picks its first spell")
	check("hex_1" in hero.spells and "hex_1" not in hero.prepared,"known, but not ready until it is slotted")
	s.gain_level_xp(hero,65)
	check(s.equip_part(0,1,"GOBLIN_HEXER") and hero.prepared == ["fire_6","hex_1"],"slotted, it is ready in slot order")
	check(s.unequip_part(0,0) and hero.prepared == ["hex_1"],"unslotted, its spell goes")
	check(not s.choose_essence_spell(0,"FROST_IMP","ice_1"),"an essence the hero never absorbed has no choice")
	s.gain_level_xp(hero,999999)
	for id in ["FIRE_CALLER","FROST_IMP","STORM_BAT","GNOLL_SUMMONER","FIRE_CALLER@ice","FROST_IMP@fire"]:
		hero.essences[id] = maxi(1,int(hero.essences.get(id,0)))
		hero.essence_spells[id] = Essences.spell_choices(hero,id)[0]
	hero.equipped_abilities = ["FIRE_CALLER","FROST_IMP","STORM_BAT","GNOLL_SUMMONER","FIRE_CALLER@ice","FROST_IMP@fire","GOBLIN_HEXER","","",""]
	Essences.sync_spells(hero)
	check(hero.prepared.size() == Essences.READY_SPELLS and s.PREPARED_SLOTS == Essences.READY_SPELLS,"no more than five stand ready")

func failure() -> void:
	var s = Session.new_run(7,"fire"); var hero: Dictionary = s.party[0]
	hero.essences = {"FIRE_CALLER":2}; hero.equipped_abilities = ["FIRE_CALLER"]
	check(Spells.failure(s,hero,"fire_6") == 8+54-16-20,"level six at tier two with sixteen mind")
	hero.level = 3; hero.essences = {"FIRE_CALLER":2,"FROST_IMP":1,"STORM_BAT":1}
	hero.equipped_abilities = ["FIRE_CALLER","FROST_IMP","STORM_BAT"]
	check(Spells.failure(s,hero,"fire_6") == 8+54-19-20-10,"술사 3 takes ten more off")
	hero.essences = {"FIRE_CALLER":3}; hero.equipped_abilities = ["FIRE_CALLER","",""]
	check(Spells.failure(s,hero,"fire_1") == 0,"a mastered caster never fumbles an easy spell")
	check(Spells.failure(s,hero,"ice_1") == clampi(8+9-18,0,85),"another school has no tier to lean on")

func casting() -> void:
	var s = Session.new_run(7,"fire"); var hero: Dictionary = s.party[0]
	var c: Vector2i = Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 30; foe.max_hp = 30; foe.pos = c+Vector2i(2,0)
	s.floor_state.observe(s)
	hero.essences.FIRE_CALLER = 3
	check(Spells.can_cast(s,hero,"fire_1",foe.pos),"the kit spell casts with no book")
	check(s.cast("fire_1",foe.pos) and int(foe.hp) < 30,"and burns the foe")

func no_books() -> void:
	check(not Stats.content.has("books") and not Stats.content.loot.has("books"),"no books in the data")
	check(Stats.content.spells.values().all(func(row): return not row.has("book")),"no spell names a book")
	var s = Session.new_run(9,"fire")
	for method in ["learn_spell","prepare_spell","grant_book","book_tier","random_book"]:
		check(not s.has_method(method),"the session has no "+method)
	var source: String = FileAccess.get_file_as_string("res://expedition/spells/spells.gd")
	check(not source.contains("func learnable") and not source.contains("func book"),"spells have no book helpers")
	s.grant_part("FROST_IMP")
	check(int(s.parts_bag.get("FROST_IMP",0)) == 1 and s.log_lines[-1].contains(Essences.title("FROST_IMP")),"a caster essence can be found like any other")
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --editor --import --quit; godot --headless --path . --script res://tests/essence_spells.gd`
Expected: FAIL — 마법 킷이 아직 주문서로 시작함.

- [ ] **Step 3: 시작 장비를 주문 이능으로**

`expedition/run/descent.gd`의 `depart`에서

```gdscript
	s.party[0].skill_xp[str(kit.axis)] = 25
	var kit_spell: String = str(kit.get("spell",""))
	s.party[0].books = []; s.party[0].buffs = {}
	s.party[0].spells = []; s.party[0].prepared = []
	if not kit_spell.is_empty():
		# A magic kit leaves with its school's primer and the first spell in it.
		s.party[0].spells = [kit_spell]
		s.party[0].prepared = [kit_spell]
		s.party[0].books = [str(Spells.definition(kit_spell).get("book",""))]
```

를 다음으로 바꾼다. 머리에 `const StatSheet = preload("res://expedition/progression/stat_sheet.gd")`를 넣는다.

```gdscript
	var hero: Dictionary = s.party[0]
	var kit_spell: String = str(kit.get("spell",""))
	hero.buffs = {}; hero.spells = []; hero.prepared = []
	hero.essences = {}; hero.essence_spells = {}; hero.equipped_abilities = [""]
	if not kit_spell.is_empty():
		# A magic kit leaves with its school's caster essence, its first spell chosen.
		var essence: String = str(Essences.CASTER_BY_SCHOOL.get(str(kit.axis),""))
		hero.essences[essence] = 1
		hero.essence_spells[essence] = kit_spell
		Essences.sync_slots(hero)
		hero.equipped_abilities[0] = essence
		Essences.sync_spells(hero)
	StatSheet.refresh_pools(s,hero)
```

`const Spells = preload(...)` 줄은 더 쓰이지 않으면 지운다.

- [ ] **Step 4: 야영과 세션에서 주문서·배우기·준비 지우기**

`expedition/run/camp.gd`:
- 머리의 `const Mastery = ...`, `const Spells = ...`를 지우고 `const Essences = preload("res://expedition/progression/essences.gd")`를 넣는다.
- `const PREPARED_SLOTS := 5`를 `const PREPARED_SLOTS := Essences.READY_SPELLS`로 바꾸고 주석을 "How many spells stand ready at once: the caster essences in slots decide which."로 바꾼다.
- `prepare_spell`, `learn_spell`, `grant_book`, `book_tier`, `random_book` 다섯 함수를 지운다. 파일 머리 주석을 "Camp: rest, and the cooldowns it resets."로 바꾼다.

`expedition/run/session.gd`:
- `prepare_spell`, `learn_spell`, `grant_book`, `book_tier`, `random_book` 다섯 래퍼를 지운다.
- `make_actor`에서 `"books":[],`를 지운다.
- 보스 처치 분기의 `grant_book(random_book(depth*1000+int(target.id),true))` 줄을 지운다.

`expedition/spells/spells.gd`: `book`, `book_spells`, `learnable` 세 함수와 그 위 주석을 지운다.

`expedition/items/curios.gd`의

```gdscript
	if int(outcome.get("spellbook_chance",0)) > 0 and s.Hexaco.sample(s.seed_value,key,"spellbook",100) < int(outcome.spellbook_chance):
		s.grant_book(s.random_book(key))
```

를 다음으로 바꾼다(데이터의 `spellbook_chance` 키 이름은 그대로 둔다).

```gdscript
	# What used to be a spellbook is now a caster's essence of any school.
	if int(outcome.get("spellbook_chance",0)) > 0 and s.Hexaco.sample(s.seed_value,key,"spellbook",100) < int(outcome.spellbook_chance):
		var casters: Array = s.Essences.CASTER_BY_SCHOOL.values()
		s.grant_part(str(casters[s.Hexaco.sample(s.seed_value,key,"spell_essence",casters.size())]))
```

`expedition/ui/screens/camp_screen.gd`: `ui.button(actions,"주문 준비",func(): show_prepare(ui,i))`, `ui.button(actions,"주문 배우기",func(): show_learn(ui,i))` 두 줄과 `show_prepare`, `show_learn` 두 함수를 지운다(주문 선택 화면은 계획 3/3의 이능 탭이 맡는다).

- [ ] **Step 5: 데이터에서 주문서 지우기**

Run:

```bash
python3 - <<'EOF'
import json
p='data/content/combat.json'
d=json.load(open(p,encoding='utf-8'))
d.pop('books',None)
d['loot'].pop('books',None)
for row in d['spells'].values(): row.pop('book',None)
json.dump(d,open(p,'w',encoding='utf-8'),ensure_ascii=False,indent=2)
open(p,'a',encoding='utf-8').write('\n')
EOF
git diff --stat data/content/combat.json
```

Expected: `combat.json`에서 삭제만 있다. 들여쓰기 방식이 바뀌어 줄 수가 크게 달라지면 `git diff -w`로 삭제 외 변경이 없는지 확인한다.

- [ ] **Step 6: 기존 테스트 고치기**

`tests/start_kit.gd`:
- `check(kits.map(func(k): return str(k.id)) == Mastery.AXES,"kit ids are the mastery axes in order")` → `check(kits.map(func(k): return str(k.id)) == ["sword","spear","mace","axe","bow","fire","ice","air","hex","summon"],"ten kits in their old order")`
- `check(int(hero.skill_xp.get(str(kit.axis),0)) == 25,...)`와 `check(Mastery.rank(hero,str(kit.axis)) == 1,...)` 두 줄을 다음으로 바꾼다.

```gdscript
		var caster: String = str(Essences.CASTER_BY_SCHOOL.get(str(kit.axis),""))
		check(caster.is_empty() == str(kit.spell).is_empty(),"%s has a caster essence exactly when it has a spell" % id)
		check(caster.is_empty() or int(hero.essences.get(caster,0)) == 1,"%s starts its caster essence at tier one" % id)
```

- 머리의 `const Mastery = ...`를 `const Essences = preload("res://expedition/progression/essences.gd")`로 바꾼다.
- `hero.skill_xp[str(Stats.content.spells[spell].school)] = 2500`과 그 위 주석을 다음으로 바꾼다.

```gdscript
	# A tier-three caster never fumbles a first-level spell, so what the spell
	# does is what the check below reads.
	hero.essences[str(Essences.CASTER_BY_SCHOOL[str(Stats.content.spells[spell].school)])] = 3
```

`tests/model_b_spells.gd`의

```gdscript
	# The port's own spells belong to no book: nothing teaches them any more.
	for id in ["blast","blink","mend","passwall","ward","turret"]:
		check(not s.learn_spell(0,id),"no book teaches the relic "+id)
		hero.spells.append(id)
	s.phase = "CAMP"
	check(s.prepare_spell(0,"blast",true) and s.prepare_spell(0,"mend",true) and s.prepare_spell(0,"blink",true),"prepare three spells")
	check(s.prepare_spell(0,"passwall",true) and s.prepare_spell(0,"ward",true),"prepare five spells")
	check(not s.prepare_spell(0,"turret",true),"sixth spell refused")
```

를 다음으로 바꾼다(검사 수는 그대로 여덟 개).

```gdscript
	# The port's own spells belong to no caster essence: nothing offers them.
	for id in ["blast","blink","mend","passwall","ward","turret"]:
		check(Essences.CASTER_BY_SCHOOL.values().all(func(e): return id not in Essences.spell_choices({"essences":{e:3}},e)),"no essence offers the relic "+id)
		hero.spells.append(id)
	s.phase = "CAMP"
	hero.prepared = ["blast","mend","blink"]
	check(hero.prepared.size() == 3 and "blink" in hero.prepared,"three relics stand ready")
	hero.prepared.append_array(["passwall","ward"])
	check(hero.prepared.size() == s.PREPARED_SLOTS,"five relics fill the ready row")
	check(not s.has_method("prepare_spell"),"readying is the essences' business now")
```

머리에 `const Essences = preload("res://expedition/progression/essences.gd")`를 넣는다.

`tests/spellbooks.gd`:
- 머리의 `const Mastery = ...`를 `const Essences = preload("res://expedition/progression/essences.gd")`로 바꾼다.
- `data()`의 `check(str(row.book) == "%s_%d" % [school,tier],"%s sits in the right book" % id)`를 `check(Essences.spell_cap(tier) >= level and (tier == 1 or Essences.spell_cap(tier-1) < level),"%s needs a tier-%d caster essence" % [id,tier])`로 바꾼다.
- `data()`의 `check(Stats.content.books.size() == 15,"fifteen books")`부터 그 아래 `for school in SCHOOLS: for tier in [1,2,3]: ...` 블록 끝까지를 다음으로 바꾼다.

```gdscript
	check(not Stats.content.has("books"),"no books any more")
	for school in SCHOOLS:
		var caster: String = str(Essences.CASTER_BY_SCHOOL[school])
		for tier in [1,2,3]:
			var reach: Array = Essences.spell_choices({"essences":{caster:tier}},caster)
			check(not reach.is_empty() and reach.all(func(id): return str(rows[id].school) == school),"%s tier %d reaches only its school" % [school,tier])
			check(reach.size() == Essences.spell_cap(tier),"%s tier %d reaches its band" % [school,tier])
```

- `start()`를 통째로 바꾼다.

```gdscript
func start() -> void:
	for school in SCHOOLS:
		var s = Session.new_run(7,school)
		var hero: Dictionary = s.party[0]
		check(hero.equipped_abilities[0] == Essences.CASTER_BY_SCHOOL[school],"the %s kit wears its caster essence" % school)
		check(hero.spells == ["%s_1" % school],"the %s kit knows its first spell" % school)
		check(hero.prepared == ["%s_1" % school],"the %s kit has it ready" % school)
	var sword = Session.new_run(7,"sword")
	check(sword.party[0].essences.is_empty() and sword.party[0].spells.is_empty(),"a swordsman departs with no spell")
```

- `learning()`을 통째로 바꾼다.

```gdscript
func learning() -> void:
	var s = Session.new_run(7,"fire")
	var hero: Dictionary = s.party[0]
	s.phase = "CAMP"
	check("fire_1" in Essences.spell_choices(hero,"FIRE_CALLER"),"the kit spell is in reach")
	check("fire_2" in Essences.spell_choices(hero,"FIRE_CALLER"),"so is the second")
	check("fire_3" in Essences.spell_choices(hero,"FIRE_CALLER"),"and the third")
	check("fire_4" not in Essences.spell_choices(hero,"FIRE_CALLER"),"but not the fourth")
	check(not s.choose_essence_spell(0,"FIRE_CALLER","fire_4"),"a spell out of reach is refused")
	check(hero.essence_spells.FIRE_CALLER == "fire_1","and the choice stands")
	check(s.choose_essence_spell(0,"FIRE_CALLER","fire_3"),"a spell in reach is chosen at camp")
	check(hero.prepared == ["fire_3"],"and is the one ready")
	check(hero.spells == ["fire_3"],"one essence, one spell")
	s.parts_bag["FIRE_CALLER"] = 2
	check(s.absorb_essence(0,"FIRE_CALLER") == "","a second copy raises the tier")
	check(Essences.tier(hero,"FIRE_CALLER") == 2,"to two")
	check("fire_6" in Essences.spell_choices(hero,"FIRE_CALLER"),"tier two reaches the sixth")
	check("fire_7" not in Essences.spell_choices(hero,"FIRE_CALLER"),"not the seventh")
	check(s.absorb_essence(0,"FIRE_CALLER") == "","a third copy")
	check("fire_10" in Essences.spell_choices(hero,"FIRE_CALLER"),"tier three reaches the tenth")
	check(s.absorb_essence(0,"FIRE_CALLER") != "","and there is no fourth tier")
	check(not s.choose_essence_spell(0,"FROST_IMP","ice_1"),"another school needs its own essence")
	s.parts_bag["FROST_IMP"] = 1
	check(s.absorb_essence(0,"FROST_IMP") == "","found in the dungeon, it is absorbed")
	check(hero.essence_spells.FROST_IMP == "ice_1","its first spell is chosen")
	check("ice_1" in hero.spells,"a second school begins")
	check("ice_1" not in hero.prepared,"but only a slotted essence readies its spell")
	s.phase = "BATTLE"
	check(not s.choose_essence_spell(0,"FIRE_CALLER","fire_2"),"nothing is chosen in a fight")
	check(hero.essence_spells.FIRE_CALLER == "fire_3","the choice stands")
	s.phase = "CAMP"
	check(s.choose_essence_spell(0,"FIRE_CALLER","fire_2"),"back at camp it is chosen")
	s.gain_level_xp(hero,65)
	check(s.equip_part(0,1,"FROST_IMP"),"the second slot takes the frost essence")
	check(hero.prepared == ["fire_2","ice_1"],"two spells ready, in slot order")
	check(s.unequip_part(0,1),"unslotted")
	check(hero.prepared == ["fire_2"],"its spell goes")
	check(hero.spells.has("ice_1"),"but it is still known")
	check(s.PREPARED_SLOTS == 5,"five stand ready at most")
	check(Essences.READY_SPELLS == 5,"the essences agree")
```

- `drops()`를 통째로 바꾼다.

```gdscript
## A boss leaves its essence every time; a curio's old book is now a caster's
## essence, which teaches nothing until it is absorbed.
func drops() -> void:
	var boss = Session.new_run(5,"fire")
	Fixture.arena(boss,10)
	boss.depth = 6
	var target: Dictionary = boss.enemies[0]
	target.boss = true; target.part_id = "PUSH"
	target.hp = 60; target.max_hp = 60
	boss.parts_bag.clear()
	boss.damage(target,9999,0,"physical")
	check(target.hp <= 0,"the boss falls")
	check(int(boss.parts_bag.get("PUSH",0)) == 1,"a boss always leaves its essence")
	check(not boss.party[0].has("books"),"and never a book")
	var found: Dictionary = {}
	for key in range(40):
		var curio = Session.new_run(key,"fire")
		curio.parts_bag.clear()
		var casters: Array = Essences.CASTER_BY_SCHOOL.values()
		curio.grant_part(str(casters[key % casters.size()]))
		for id in curio.parts_bag: found[id] = true
	check(found.size() == 5,"every school's caster essence can be found")
	var curio = Session.new_run(9,"fire")
	var known: int = curio.party[0].spells.size()
	curio.grant_part("GOBLIN_HEXER")
	check(int(curio.parts_bag.GOBLIN_HEXER) == 1,"a found essence joins the bag")
	check(curio.party[0].spells.size() == known,"and teaches nothing on its own")
```

- [ ] **Step 7: 통과 확인**

Run: `godot --headless --path . --editor --import --quit; for t in essence_spells spellbooks start_kit model_b_spells curios camping essences; do godot --headless --path . --script "res://tests/$t.gd" 2>&1 | tail -1; done`
Expected: 모두 0 failures.

- [ ] **Step 8: 커밋**

```bash
git commit -m "Spells come from caster essences; books are gone

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- expedition/run/descent.gd expedition/run/camp.gd expedition/run/session.gd expedition/spells/spells.gd expedition/items/curios.gd expedition/ui/screens/camp_screen.gd data/content/combat.json tests/essence_spells.gd tests/spellbooks.gd tests/start_kit.gd tests/model_b_spells.gd
```

---

### Task 7: 숙련·옛 성장 파일 삭제, 화면 정리, 옛 스위트 교체

**Files:**
- Delete: `expedition/progression/mastery.gd`, `mastery_effects.gd`, `growth.gd` (+ 각 `.uid`), `data/content/mastery.json`, `tests/model_b_mastery.gd`, `tests/model_b_mastery_ui.gd` (+ `.uid`)
- Modify: `expedition/run/session.gd`, `expedition/items/gear.gd`, `expedition/sim/model_b_runner.gd`, `expedition/sim/encounter_runner.gd`, `expedition/ui/screens/character_folio.gd`, `expedition/ui/screens/popups.gd`, `expedition/ui/main.gd`
- Modify (기존 테스트): `tests/abilities_growth.gd`, `tests/character_ui.gd`, `tests/npc_progression.gd`, `tests/parts.gd`, `tests/model_b_scheduler.gd`
- Test: 전체 스위트

**Interfaces:**
- Consumes: Task 1~6
- Produces: 캐릭터 폴리오 탭 `["상태","성격","기억","파츠"]`, 파츠 탭 제목 `"파츠 슬롯 %d / %d"`(장착 수 / 슬롯 수). 계획 3/3이 "파츠"를 "이능"으로 바꾼다. 액터에서 `growth`, `skill_xp`가 사라진다.

- [ ] **Step 1: 남은 참조 찾기**

Run: `grep -rn "Mastery\|Growth\|mastery_effects\|mastery.json\|skill_xp\|\.growth\b\|spend_growth\|show_mastery_detail\|\"숙련\"" expedition tests --include=*.gd`
Expected: 이 작업의 파일 목록 안에서만 나온다. 목록 밖에서 나오면 그 파일도 이 작업에서 같은 방식으로 고친다.

- [ ] **Step 2: 세션·장비·시뮬레이터 정리**

`expedition/run/session.gd`:
- `const Growth = ...`, `const Mastery = ...` 두 줄을 지운다.
- `make_actor`에서 `"growth":Growth.create(),`와 `"skill_xp":{},`를 지운다.
- `func spend_growth(...)` 래퍼를 지운다.

`expedition/items/gear.gd`: `const Growth = ...`, `const Mastery = ...`와 `spend_growth` 함수를 지운다.

`expedition/sim/model_b_runner.gd`의 `"skills":s.party[0].skill_xp.duplicate(true)}`를 `"essences":s.party[0].essences.duplicate(true)}`로 바꾼다.

`expedition/sim/encounter_runner.gd`의 두 줄을 지운다.

```gdscript
		for axis in row.get("ranks",{}): actor.growth.ranks[axis] = int(row.ranks[axis])
		for stat in row.get("stats",{}): actor.growth.stats[stat] = int(row.stats[stat])
```

- [ ] **Step 3: 화면 정리**

`expedition/ui/screens/character_folio.gd`:
- 머리의 `const Growth = ...`, `const Mastery = ...`, `static var mastery_data ...`, `const Emblem = ...` 네 줄을 지우고 `const Essences = preload("res://expedition/progression/essences.gd")`를 넣는다.
- 탭 목록 `for name in ["상태","성격","기억","숙련","파츠"]:`를 `for name in ["상태","성격","기억","파츠"]:`로 바꾼다.
- 제목 줄을 다음으로 바꾼다.

```gdscript
	var member: Dictionary = ui.session.party[ui.tactics_actor]
	var heading := Label.new(); heading.text = "파츠 슬롯 %d / %d" % [Essences.equipped(member).size(),Essences.slot_count(member)] if tab == "파츠" else "현재 상태" if tab == "상태" else tab
```

- `status`의 `if ui.session.manual_mode:` 분기 안 내용만 남기고, 분기 조건과 그 아래 옛 성장 부분(`var vitals := card(list,"Lv.%d · %s" % [actor.growth.level,...` 부터 함수 끝까지)을 지운다. 남은 본문은 들여쓰기를 한 단계 줄이고 마지막 `return`을 지운다.
- `can_invest`, `mastery`, `mastery_detail`, `preview` 네 함수를 지운다.
- `parts`를 통째로 바꾼다.

```gdscript
## One card per slot the level has opened: what is slotted and how to swap it.
static func parts(ui, list: VBoxContainer, actor: Dictionary) -> void:
	var town: bool = Essences.can_manage(ui.session) and actor.hp > 0
	Essences.sync_slots(actor)
	for slot in range(actor.equipped_abilities.size()):
		var id: String = str(actor.equipped_abilities[slot])
		var box := card(list,""); box.get_parent().name = "PartSlot"+str(slot)
		box.get_parent().custom_minimum_size.y = 132
		var row := HBoxContainer.new(); box.add_child(row)
		var info := VBoxContainer.new(); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(info)
		var actions := VBoxContainer.new(); row.add_child(actions)
		if id.is_empty():
			text(info,"빈 슬롯",20)
			ui.button(actions,"장착",func(): replace(ui,slot),town)
			continue
		var def: Dictionary = ui.Session.Abilities.DEFINITIONS.get(id,{})
		text(info,"%s · %d단계" % [Essences.title(id),Essences.tier(actor,id)],20)
		if not def.is_empty(): text(info,str(def.description),13)
		ui.button(actions,"교체",func(): replace(ui,slot),town)
		ui.button(actions,"해제",func(): ui.session.unequip_part(ui.tactics_actor,slot); ui.refresh(); ui.show_character(ui.tactics_actor,"파츠"),town)
```

- `replace`의 목록 루프를 바꾼다. 흡수한 이능을 먼저, 가방의 이능을 그다음에 보여 준다.

```gdscript
	var count := 0
	var town: bool = Essences.can_manage(ui.session) and actor.hp > 0
	for id in actor.get("essences",{}):
		if id in actor.equipped_abilities: continue
		count += 1
		ui.button(list,"%s · %d단계" % [Essences.title(id),Essences.tier(actor,id)],func():
			if ui.session.equip_part(index,slot,id):
				ui.item_popup.hide(); ui.refresh(); ui.show_character(index,"파츠"),town)
	for id in ui.session.parts_bag:
		if int(ui.session.parts_bag[id]) <= 0 or actor.get("essences",{}).has(id): continue
		count += 1
		ui.button(list,"%s ×%d · 흡수" % [Essences.title(id),ui.session.parts_bag[id]],func():
			if ui.session.equip_part(index,slot,id):
				ui.item_popup.hide(); ui.refresh(); ui.show_character(index,"파츠"),town)
	if count == 0: text(list,"이능 없음")
```

(기존 `var count := 0`부터 `if count == 0: text(list,"가방에 파츠 없음")`까지를 이것으로 바꾼다.)

`expedition/ui/screens/popups.gd`:
- `show_character`의 `"숙련": CharacterUI.mastery(ui,list,actor)` 줄을 지운다.
- `show_mastery_detail` 함수를 지운다.
- NPC 팝업의 두 줄

```gdscript
	var axis: String = Session.Mastery.weapon_axis(str(npc.get("gear",{}).get("weapon",{}).get("type","sword")))
	ui.label(words,"Lv.%d · %s %d" % [int(npc.get("level",1)),Session.Mastery.NAMES[axis],Session.Mastery.rank(npc,axis)],13)
```

를 `ui.label(words,"Lv.%d" % int(npc.get("level",1)),13)`로 바꾼다.
- 가방의 파츠 분기 `for slot in range(2):`를 `for slot in range(Session.Essences.slot_count(member)):`로 바꾼다.

`expedition/ui/main.gd`의 `func show_mastery_detail(index: int, axis: String) -> void: Popups.show_mastery_detail(self,index,axis)`를 지운다.

- [ ] **Step 4: 파일 삭제**

```bash
git rm -q expedition/progression/mastery.gd expedition/progression/mastery.gd.uid expedition/progression/mastery_effects.gd expedition/progression/mastery_effects.gd.uid expedition/progression/growth.gd expedition/progression/growth.gd.uid data/content/mastery.json tests/model_b_mastery.gd tests/model_b_mastery.gd.uid tests/model_b_mastery_ui.gd tests/model_b_mastery_ui.gd.uid
godot --headless --path . --editor --import --quit
```

- [ ] **Step 5: 옛 스위트 고치기**

`tests/model_b_scheduler.gd`: `hero.skill_xp = {}` 줄을 지운다.

`tests/abilities_growth.gd`:
- `exercise()`의 네 검사를 바꾼다.

```gdscript
		check(int(s.party[0].level_xp) == 18+s.depth*8 and int(s.party[1].level_xp) == 18+s.depth*8,"shared XP without last-hit competition")
		check(int(s.party[0].level) == 1 and s.party[0].max_hp == 55,"one floor kill does not skip a level")
		s.roll_part(enemy); s.damage(enemy,999,0,"SLASH")
		check(s.parts_bag.get(enemy.part_id,0) == count and int(s.party[0].level_xp) == 18+s.depth*8,"death cannot reward twice")
	check(dropped == 30,"the first of a species always drops (%d of 30)" % dropped)
```

- `arena()` 다음, `s.parts_bag = {"SHOCKWAVE":2,"BOMB":1,"IRON_HIDE":1}` 바로 위에 `s.gain_level_xp(s.party[1],65)` 한 줄을 넣는다(두 번째 슬롯).
- `check(s.equip_part(1,0,"SHOCKWAVE") and s.parts_bag.SHOCKWAVE == 1,"equipping takes exactly one part from the bag")`는 그대로 둔다.
- 옛 성장 다섯 검사(`s.Growth.gain(s.party[0],400)`부터 `invalid growth choices rejected`까지)를 다음으로 바꾼다.

```gdscript
	s.gain_level_xp(s.party[0],65*1+65*4)
	check(int(s.party[0].level) == 3 and s.party[0].equipped_abilities.size() == 3,"three levels, three slots")
	check(not s.has_method("spend_growth"),"no points to spend any more")
	s.parts_bag["ORC_CLEAVER"] = 1
	check(s.equip_part(0,2,"ORC_CLEAVER") and int(s.StatSheet.value(s,s.party[0],"str")) == 14,"an essence raises strength")
	check(s.Abilities.power(s,s.party[0],s.Abilities.DEFINITIONS.HEAVY_STRIKE,"HEAVY_STRIKE") == int(s.Abilities.DEFINITIONS.HEAVY_STRIKE.damage)+2,"strength raises a part's blow")
	check(not s.equip_part(0,5,"ORC_CLEAVER") and not s.equip_part(-1,0,"ORC_CLEAVER"),"invalid slots and members rejected")
```

`tests/character_ui.gd`:
- 두 곳의 탭 목록 `["상태","성격","기억","숙련","파츠"]`를 `["상태","성격","기억","파츠"]`로, `for tab in ["파츠","숙련","상태"]:`를 `for tab in ["파츠","상태"]:`로 바꾼다.
- `if tab == "숙련": check(scene.modal_content.find_child("MasteryGrid",true,false).columns == 2,"two-column mastery cards")`를 `if tab == "파츠": check(scene.modal_content.find_children("PartSlot*","PanelContainer",true,false).size() == Essences.slot_count(scene.session.party[member]),"one card per open slot")`로 바꾼다. 머리에 `const Essences = preload("res://expedition/progression/essences.gd")`를 넣는다.
- 옛 투자 블록(`scene.session.party[1].growth.points = 2`부터 `check(scene.session.party[0].growth.ranks.MELEE == 0,"hero unaffected")`까지)을 다음으로 바꾼다(검사 5 → 5).

```gdscript
	scene.session.gain_level_xp(scene.session.party[1],65)
	scene.show_character(1,"파츠")
	await process_frame
	var slots: Array = scene.modal_content.find_children("PartSlot*","PanelContainer",true,false)
	check(slots.size() == 2,"a second level opens a second slot card")
	var heading: Array = scene.modal_content.find_children("*","Label",true,false).filter(func(l): return l.text.begins_with("파츠 슬롯"))
	check(not heading.is_empty() and heading[0].text.ends_with("/ 2"),"the heading counts the open slots")
	check(scene.session.party[1].equipped_abilities.size() == 2,"the companion's row grew")
	check(scene.session.party[0].equipped_abilities.size() == 1,"hero unaffected")
	check(not scene.modal_content.find_children("*","Button",true,false).any(func(b): return b.text.contains("투자")),"nothing to invest")
```

- `scene.session.party[1].equipped_abilities = ["PUSH","GUARD"]` 줄은 그대로 둔다. `check(scene.session.party[0].equipped_abilities == ["",""],"other members keep their own slots")`를 `check(scene.session.party[0].equipped_abilities == [""],"other members keep their own slots")`로 바꾼다.

`tests/npc_progression.gd`:
- 머리의 `const Mastery = ...`를 지운다.
- `solo_hunts()`의 `var axis: String = Mastery.weapon_axis(str(npc.gear.weapon.type))`를 지운다.
- `check(int(npc.skill_xp.get(axis,0)) == 3*(18+s.depth*8),"NPC gains weapon mastery from its hunts")`를 `check(npc.equipped_abilities.size() >= int(npc.level),"the NPC's slot row keeps up with its level")`로 바꾼다.
- `check(int(npc.skill_xp.get(Mastery.weapon_axis(str(npc.gear.weapon.type)),0)) > 0,"shared kill grants NPC mastery by contribution")`를 `check(npc.usage.is_empty() or not npc.usage.has(int(foe.id)),"the finished hunt is wiped from the record")`로 바꾼다.
- `legacy_hunt()`의 두 검사를 바꾼다.

```gdscript
	check(int(npc.level_xp) == 18+s.depth*8,"legacy hunt grants the NPC the same level XP")
	check(s.party.all(func(a): return int(a.level_xp) == 0),"legacy NPC hunt gives no party XP")
```

`tests/parts.gd`:
- `ui()`: `"파츠 슬롯 0 / 2"` → `"파츠 슬롯 0 / 1"`, `check(cards.size() == 2,"two slot cards")` → `check(cards.size() == 1,"one slot card at level one")`, `check(buttons.filter(func(b): return b.text == "장착").size() == 2,"empty slots offer 장착")` → `== 1`, `"파츠 슬롯 1 / 2"` → `"파츠 슬롯 1 / 1"`. 선택 창 검사 `"밀치기 ×1" in picks and "엄호 ×1" in picks`는 `picks.any(func(p): return p.begins_with("밀치기 요령 ×1")) and picks.any(func(p): return p.begins_with("엄호 요령 ×1"))`로 바꾼다.
- `basic_parts()`: `hero.equipped_abilities == ["",""]` → `hero.equipped_abilities == [""]`, `legacy.party[0].equipped_abilities == ["",""]` → `legacy.party[0].equipped_abilities == [""]`.
- `bag()`의 `s.phase = "CAMP"`부터 `check(not s.equip_part(0,0,"PUSH") and not s.unequip_part(0,1),"slots are locked outside camp")`까지를 다음으로 바꾼다(검사 12 → 12).

```gdscript
	s.phase = "CAMP"
	check(not s.equip_part(0,1,"PUSH") and not s.equip_part(0,0,"BOMB") and not s.equip_part(0,0,"NOPE"),"closed slot, empty bag and unknown id refused")
	check(s.equip_part(0,0,"PUSH") and s.party[0].equipped_abilities[0] == "PUSH" and s.parts_bag.PUSH == 0,"equip absorbs the part out of the bag")
	check(s.party[0].rules.size() == 1 and s.party[0].rules[0].skill == "PUSH","equip adds the default rule")
	s.gain_level_xp(s.party[0],65)
	check(not s.equip_part(0,1,"PUSH"),"same part twice on one member refused")
	check(not s.equip_part(1,0,"PUSH"),"bag empty for the second member")
	s.parts_bag.PUSH = 1
	check(s.equip_part(1,0,"PUSH"),"another member may hold the same part")
	check(s.equip_part(0,0,"GUARD") and s.parts_bag.get("PUSH",0) == 0 and int(s.party[0].essences.PUSH) == 1 and s.party[0].equipped_abilities[0] == "GUARD","replacing keeps the old part absorbed")
	check(s.party[0].rules.size() == 1 and s.party[0].rules[0].skill == "GUARD","replacing swaps the rule")
	check(s.unequip_part(0,0) and s.party[0].equipped_abilities[0] == "" and s.parts_bag.get("GUARD",0) == 0 and s.party[0].rules.is_empty(),"unequip empties the slot and the rule, not into the bag")
	check(not s.unequip_part(0,0),"empty slot cannot be unequipped")
	check(s.equip_part(0,0,"PUSH") and s.equip_part(0,1,"GUARD"),"both slots from what was absorbed")
	s.phase = "BATTLE"
	check(not s.equip_part(0,0,"PUSH") and not s.unequip_part(0,1),"slots are locked in a fight")
```

- `bag()`의 드롭 검사 `check(got,"some monster in the roster drops its part (%d tried)" % tries)`는 그대로 둔다(첫 처치는 반드시 떨어진다).

- [ ] **Step 6: 전체 스위트**

Run:

```bash
godot --headless --path . --editor --import --quit
fails=0; for f in tests/*.gd; do n=$(basename $f .gd); case $n in floor_fixture|model_b_runner|difficulty_gate) continue;; esac; out=$(timeout 600 godot --headless --path . --script "res://tests/$n.gd" 2>&1); code=$?; if [ $code -ne 0 ] || echo "$out" | grep -q "SCRIPT ERROR\|^ERROR:"; then echo "FAIL $n"; fails=$((fails+1)); fi; done; echo "failing suites: $fails"
```

Expected: `failing suites: 0`. `ui_smoke`가 이 계획 전부터 깨져 있었다면(이전 세션에서 확인됨), 깨끗한 작업 트리(`git stash` 없이 `git worktree add`)에서 같은 실패가 나는지 확인하고, 같으면 이 계획과 무관한 실패로 적어 둔다.

- [ ] **Step 7: 검사 수 비교**

Run: `git diff --stat $(git merge-base HEAD origin/main) -- tests | tail -1; for f in essences stats_resist tag_sets essence_spells; do grep -c "check(" tests/$f.gd; done`
Expected: 새 네 스위트의 `check(` 합계가 지운 두 스위트(`model_b_mastery` 15줄, `model_b_mastery_ui` 10줄)와 옛 성장 검사(약 10줄)를 합친 것보다 많다.

- [ ] **Step 8: 커밋**

```bash
git commit -m "Remove mastery axes and point growth; the folio shows the level's slots

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- expedition/run/session.gd expedition/items/gear.gd expedition/sim/model_b_runner.gd expedition/sim/encounter_runner.gd expedition/ui/screens/character_folio.gd expedition/ui/screens/popups.gd expedition/ui/main.gd expedition/progression data/content/mastery.json tests/model_b_mastery.gd tests/model_b_mastery.gd.uid tests/model_b_mastery_ui.gd tests/model_b_mastery_ui.gd.uid tests/abilities_growth.gd tests/character_ui.gd tests/npc_progression.gd tests/parts.gd tests/model_b_scheduler.gd
```

---

## 스펙 대응표

| 스펙 | 작업 |
|---|---|
| §0.1 숙련·이정표 삭제 | Task 5, 7 |
| §0.2 재생성 없음, 첫 처치 규칙·층 상한 없음 | 변경 없음(코드에 재생성이 없다). Task 3이 층 상한을 만들지 않는다 |
| §1 레벨 곡선, 최대 10, 슬롯 = 레벨 | Task 3 |
| §2.1~2.3 능력치·방어 수치·저항, 상한 | Task 2 |
| §2.4 몬스터 스탯표 | Task 2(읽기). 몬스터 데이터의 막기·저항 값과 길게 눌러 보기는 계획 2/3, 3/3 |
| §3.1~3.3 이능 구성, 얻기, 단계, 교체 | Task 1, 3, 5 |
| §3.4 역할·속성 태그 세트 | Task 1, 4 |
| §3.5 주문 이능 | Task 3, 5, 6 |
| §3.6~3.7 종족·변종·보스 | 계획 2/3 (Task 1이 변종 id 해석과 주문 이능 행을 미리 둔다) |
| §3.8 시작 장비 | Task 6 |
| §3.9 NPC | Task 3(명부 NPC의 흡수 기록), 선택 규칙은 계획 3/3 |
| §4 알림과 화면 | Task 3(이벤트 큐), 화면은 계획 3/3 |
| §5 난이도 | 계획 2/3(깊은 층 보정), 3/3(게이트) |
| §6 바뀌는 코드, §7 테스트 | Task 1~7 |
