# 역할군 5개와 세부 유형 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 영혼석 역할 6개(무리·광폭·기습·수호·사수·술사)를 역할군 5개(탱커·근딜·원딜·마딜·지원)로, 효과 빌드군 12개를 세부 유형 17개로 바꾼다. 보너스는 역할군 조합(2·4·6)에만 있다.

**Architecture:** 새 정적 모듈 `expedition/progression/subtypes.gd`가 세부 유형 id·이름·역할군, 효과 → 세부 유형 조회, 옛 빌드군 번호 대응을 한곳에 둔다. `families`를 읽던 모든 곳은 이 모듈을 부른다. 동료 AI의 목표 적합도는 세부 유형 → 옛 빌드군 번호 대응(`LEGACY_FAMILY`)으로 기존 로직을 그대로 쓴다. 역할군은 `essences.json`의 `role` 값만 바꾸고, 역할 조합 수치 상수와 `TagSets.ROLE_TEXT`를 새 id로 옮긴다.

**Tech Stack:** Godot 4 GDScript, Python 3(데이터 이전 스크립트), `extends SceneTree` 테스트.

**Spec:** `docs/superpowers/specs/2026-09-26-role-groups-design.md`
**선행:** 도감(`2026-09-26-codex.md`)과 읽히게 만들기(`2026-09-26-legibility.md`)가 **커밋된 뒤** 시작한다. 두 작업이 `families`를 쓰는 화면(도감 거르기)을 만들기 때문이다.

## Global Constraints

- 역할군 id: `TANK` 탱커, `MELEE` 근딜, `RANGED` 원딜, `MAGIC` 마딜, `SUPPORT` 지원.
- 세부 유형 id(역할군): `DEFENSE` 방어·`EVASION` 회피·`REGEN` 재생·`REFLECT` 반사(TANK) / `BLEED` 출혈·`CRUSH` 분쇄·`VITAL` 급소·`FURY` 광폭(MELEE) / `SNIPE` 저격·`VOLLEY` 연사·`VENOM` 맹독(RANGED) / `ELEMENT` 원소·`SUMMON` 소환·`DEATH` 사령(MAGIC) / `HEAL` 회복·`HEX` 저주·`BOOST` 강화(SUPPORT).
- 효과 데이터 필드: `families`(배열)를 지우고 `subtype`(문자열 하나)을 둔다.
- **몬스터 수치는 바뀌지 않는다.** 몬스터 체력·공격 배율은 `floor_monsters.json`의 `role`(PACK 등)을 `Bestiary.monster_stats`가 읽는다. 이 파일의 `role`은 건드리지 않는다.
- 옛 역할 id(PACK 등)를 영혼석 쪽에서 읽는 곳은 모두 새 id로 바꾼다. 호환 별칭은 두지 않는다(테스트도 새 id로 옮긴다).
- 역할군 조합 수치는 스펙 §2.2 그대로.
- 기존 테스트 검사 수를 줄이지 않는다. 계약 수치(stances 113 · utility 154 · protect 38 · parts 338)를 유지한다.
- 커밋은 각 Task 파일만 `git add <경로>`. 남의 진행 중 변경이 섞였으면 `git add -p`. 판단이 어려우면 멈추고 묻는다.

## Review Focus

- **몬스터가 바뀌지 않음**: 같은 시드의 층 몬스터 체력·공격·방어가 이전과 같다. Task 2 테스트(`Bestiary.monster_stats` 값 스냅샷).
- **동료 AI 행동이 바뀌지 않음**: 세부 유형 → 옛 빌드군 대응으로 목표 적합도가 같게 나온다. `build_ai`·`stances`·`utility` 검사 수와 결과 유지. Task 1 테스트.
- **옛 id로 만든 시험 장비·NPC 초기 장비**: `grant_test_loadout`, NPC 명부, 아레나 구성이 오류 없이 새 역할군을 읽는다. Task 2 회귀.
- **지원 조합이 파티 전체에 한 번만**: 지원 4를 둘이 가져도 파티 공격력 +8%는 한 번. Task 2 테스트.
- **세부 유형이 없는 효과**: 장비·고정 아티팩트 효과 중 세부 유형이 없는 것도 오류 없이 "없음"으로 처리. Task 1 테스트.

---

## File Structure

| 파일 | 책임 |
| --- | --- |
| `expedition/progression/subtypes.gd` (새) | 세부 유형 표, 조회, 옛 빌드군 대응 |
| `tools/migrate_subtypes.py` (새) | `stone_effects.json`의 `families` → `subtype` |
| `data/content/stone_effects.json` | `subtype` |
| `data/content/essences.json` | `role`을 역할군으로 |
| `expedition/progression/essences.gd` | `ROLES` |
| `expedition/progression/bestiary.gd` | `ROLE_POINTS`(영혼석 기본 스탯) 새 id, `ROLES` 목록 |
| `expedition/progression/tag_sets.gd` | `ROLE_TEXT`, `GUARD_*`→`TANK_*`, 사거리 |
| `expedition/progression/stone_effects.gd` | 역할군 조합 계산 |
| `expedition/ai/build_sense.gd`, `tactical_action_selector.gd`, `stances.gd` | 세부 유형 읽기, 이유 문구, 기본 태세 |
| `expedition/actors/npc_essences.gd` | 성격 선호·같은 빌드 판정 |
| `expedition/items/randart.gd` | 빌드 맞춤 가중치, 반지 옵션 구역 제한 |
| `expedition/progression/codex.gd`, `expedition/ui/screens/codex_screen.gd`, `essence_tab.gd` | 표시·거르기 |
| `tests/subtypes.gd`, `tests/role_groups.gd` (새), 기존 테스트 | 아래 |

---

### Task 1: 세부 유형

**Files:**
- Create: `expedition/progression/subtypes.gd`, `tools/migrate_subtypes.py`
- Modify: `data/content/stone_effects.json`
- Modify: `expedition/ai/build_sense.gd`, `expedition/ai/tactical_action_selector.gd`, `expedition/actors/npc_essences.gd`, `expedition/items/randart.gd`, `expedition/progression/codex.gd`, `expedition/ui/screens/essence_tab.gd`, `expedition/ui/screens/codex_screen.gd`
- Test: `tests/subtypes.gd`, 기존 `effect_data`, `build_sense`, `build_ai`, `npc_essences`, `randarts`, `gear_affixes`, `codex`, `codex_ui`

**Interfaces:**
- Produces:
  - `Subtypes.IDS: Array` (17개, 표 순서)
  - `Subtypes.NAMES: Dictionary` id → 한국어 이름
  - `Subtypes.GROUP: Dictionary` id → 역할군 id
  - `Subtypes.GROUP_NAMES: Dictionary` 역할군 id → 한국어
  - `Subtypes.LEGACY_FAMILY: Dictionary` id → 옛 빌드군 번호(1~12)
  - `Subtypes.of(effect_id: String) -> String` (없으면 `""`)
  - `Subtypes.label(subtype: String) -> String` ("탱커 · 방어탱" 꼴은 `long_label`)

- [ ] **Step 1: 실패하는 테스트** — `tests/subtypes.gd`

```gdscript
extends SceneTree
## Sub-types (role groups spec §1, §4): one per part effect, seventeen ids in
## five role groups, the old build families mapped for the companion AI.
const Subtypes = preload("res://expedition/progression/subtypes.gd")
const Essences = preload("res://expedition/progression/essences.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	check(Subtypes.IDS.size() == 17,"seventeen sub-types")
	for id in Subtypes.IDS:
		check(Subtypes.GROUP.get(id,"") in ["TANK","MELEE","RANGED","MAGIC","SUPPORT"],"%s belongs to a role group" % id)
		check(int(Subtypes.LEGACY_FAMILY.get(id,0)) in range(1,13),"%s maps to an old family" % id)
	var effects: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/stone_effects.json")).effects
	for id in effects:
		check(not effects[id].has("families"),"%s has no families left" % id)
	for stone in Essences.catalog():
		var effect: String = str(Essences.row(str(stone)).get("effect",""))
		if effect.is_empty() or not effects.has(effect): continue
		check(Subtypes.of(effect) in Subtypes.IDS,"%s (%s) has a sub-type" % [effect,stone])
	var sample := {"RAT_GNAW":"BOOST","LIZARD_TAIL":"REFLECT","HOB_TAUNT":"DEFENSE","ORC_THROW":"VOLLEY","TOAD_SPIT":"VENOM","GRAVEKEEPER":"DEATH","GOBLIN_HEXER":"HEX","VAMPIRE_BITE":"REGEN"}
	for effect in sample: check(Subtypes.of(effect) == sample[effect],"%s is %s" % [effect,sample[effect]])
	check(Subtypes.of("NO_SUCH") == "","an unknown effect has none")
	check(Subtypes.long_label("DEFENSE") == "탱커 · 방어탱","a long label")
	print("Subtypes: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
```

- [ ] **Step 2: 실패 확인** → 모듈 없음.

- [ ] **Step 3: `subtypes.gd`**

```gdscript
extends RefCounted
## Sub-types (role groups spec §1): what a part effect is for, sixteen of them
## in five role groups. No bonus rides on them; they name a build, steer the
## companion AI (through the old family numbers), filter the codex and pick
## gear amplifiers.
const IDS := ["DEFENSE","EVASION","REGEN","REFLECT","BLEED","CRUSH","VITAL","FURY","SNIPE","VOLLEY","VENOM","ELEMENT","SUMMON","DEATH","HEAL","HEX","BOOST"]
const NAMES := {"DEFENSE":"방어탱","EVASION":"회피탱","REGEN":"재생탱","REFLECT":"반사탱",
	"BLEED":"출혈","CRUSH":"분쇄","VITAL":"급소","FURY":"광폭",
	"SNIPE":"저격","VOLLEY":"연사","VENOM":"맹독",
	"ELEMENT":"원소","SUMMON":"소환","DEATH":"사령",
	"HEAL":"회복","HEX":"저주","BOOST":"강화"}
const GROUP := {"DEFENSE":"TANK","EVASION":"TANK","REGEN":"TANK","REFLECT":"TANK",
	"BLEED":"MELEE","CRUSH":"MELEE","VITAL":"MELEE","FURY":"MELEE",
	"SNIPE":"RANGED","VOLLEY":"RANGED","VENOM":"RANGED",
	"ELEMENT":"MAGIC","SUMMON":"MAGIC","DEATH":"MAGIC",
	"HEAL":"SUPPORT","HEX":"SUPPORT","BOOST":"SUPPORT"}
const GROUP_NAMES := {"TANK":"탱커","MELEE":"근딜","RANGED":"원딜","MAGIC":"마딜","SUPPORT":"지원"}
## The companion AI's target fit was written per old family (build-aware AI
## spec §3); each sub-type reads the family it came from.
const LEGACY_FAMILY := {"BLEED":1,"CRUSH":2,"VITAL":3,"FURY":4,"DEFENSE":5,"EVASION":5,"REGEN":5,"REFLECT":5,
	"SNIPE":6,"VOLLEY":6,"ELEMENT":7,"HEX":8,"VENOM":9,"SUMMON":10,"DEATH":11,"HEAL":12,"BOOST":12}
static var effects: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/stone_effects.json")).effects

static func of(effect_id: String) -> String:
	var value: String = str(effects.get(effect_id,{}).get("subtype",""))
	return value if value in IDS else ""

static func label(subtype: String) -> String:
	return str(NAMES.get(subtype,""))

static func long_label(subtype: String) -> String:
	if not NAMES.has(subtype): return ""
	return "%s · %s" % [GROUP_NAMES[GROUP[subtype]],NAMES[subtype]]
```

(스펙 §1 기준 17개: 탱커 4 + 근딜 4 + 원딜 3 + 마딜 3 + 지원 3.)

- [ ] **Step 4: 이전 스크립트** — `tools/migrate_subtypes.py`

- 부위 효과 114개(있는 것만)는 스펙 §4 표의 값을 사전으로 옮겨 적는다(표를 그대로 `PART = {"RAT_GNAW":"BOOST", "RAT_INCISOR":"BLEED", …}` — 이 스크립트 안에 114줄).
- 그 밖의 효과(장비 옵션·고정 아티팩트·대가 효과)는 첫 번째 옛 빌드군으로: `{1:"BLEED",2:"CRUSH",3:"VITAL",4:"FURY",5:"DEFENSE",6:"SNIPE",7:"ELEMENT",8:"HEX",9:"VENOM",10:"SUMMON",11:"DEATH",12:"BOOST"}`. 빌드군이 없던 효과는 `subtype`을 두지 않는다.
- `families`를 지우고 `subtype`을 넣는다. 서식(들여쓰기)은 파일의 기존 서식 그대로(`json.dump(..., ensure_ascii=False, indent=<기존>)`, 키 순서 유지).
- 바꾼 목록(효과 id, 옛 빌드군, 새 세부 유형, 출처 PART/기본값)을 찍는다. **기본값으로 들어간 장비 효과 목록은 사람이 검토한다**(예: 회피·연사 증폭 옵션이 `DEFENSE`·`SNIPE`로 들어갔으면 `EVASION`·`VOLLEY`로).

```bash
python3 tools/migrate_subtypes.py data/content/stone_effects.json
```

- [ ] **Step 5: 소비처 바꾸기**

`families`를 읽던 곳을 모두 `Subtypes`로. 찾기: `grep -rn "families" --include=*.gd expedition`

- `build_sense.gd` `profile(actor)`: 효과마다 `Subtypes.of(id)` → `Subtypes.LEGACY_FAMILY[sub]`로 옛 빌드군 번호를 세어 **지금과 같은 모양**(`{int: float}`)을 돌려준다. 새로 `subtype_profile(actor) -> Dictionary`(`{세부 유형: 비율}`)를 더한다(화면용). `NAMES`는 옛 번호용으로 남기되, 화면에 쓰는 곳은 세부 유형 이름으로 바꾼다.
- `build_sense.gd` 원하는 부위(`wishes`)의 `families` 비교: 양쪽 효과의 `LEGACY_FAMILY`로 비교.
- `tactical_action_selector.gd` 이유 문구: 주 빌드의 가장 높은 세부 유형 이름(`Subtypes.label(top_subtype)`) + " 대상 우선".
- `npc_essences.gd`: 같은 빌드 판정은 두 효과의 `Subtypes.of`가 같을 때. 선호 점수의 빌드군 부분도 세부 유형으로.
- `randart.gd`: `families(s)` → `subtypes(s)`(파티가 끼운 세부 유형 목록), 옵션 행의 `subtype`과 비교. 반지 구역 제한 `int(f) > 6`은 "`GROUP[subtype] in ["MAGIC","SUPPORT"]`이면 구역 3부터"로.
- `codex.gd` `stone_entry`: `families` → `subtype`(문자열)과 `group`(역할군 id).
- `essence_tab.gd`: 빌드군 줄 → `Subtypes.long_label(sub)`.
- `codex_screen.gd` 거르기: 위 줄 역할군 5칩(`CodexGroup_<id>`), 역할군을 고르면 그 아래 세부 유형 칩(`CodexFilter_<세부 유형>`). 항목은 `entry.subtype == 고른 세부 유형` 또는 `entry.group == 고른 역할군`이면 보인다.

- [ ] **Step 6: 테스트 옮기기** — `families`를 기대하던 기존 테스트(`effect_data`, `build_sense`, `codex`, `codex_ui`의 `CodexFilter_<번호>`, `randarts`, `gear_affixes`, `npc_essences`)를 세부 유형으로. **검사 의도와 수를 유지한다.** `effect_data`에는 "부위 효과마다 `subtype`이 `Subtypes.IDS` 안" 검사를 더한다.

- [ ] **Step 7: 확인**

Run: `for t in subtypes effect_data effect_engine build_sense build_ai npc_essences randarts gear_affixes unrands codex codex_ui stances utility protect companion_tactics; do echo "== $t"; godot --headless --path . --script res://tests/$t.gd 2>&1 | grep -E "failures|ERROR" | head -3; done`
Expected: 모두 `0 failures`. `stances`·`utility`·`protect`는 검사 수가 이전과 같다(동료 AI 행동 불변).

- [ ] **Step 8: Commit**

```bash
git add expedition/progression/subtypes.gd tools/migrate_subtypes.py data/content/stone_effects.json expedition/ai/build_sense.gd expedition/ai/tactical_action_selector.gd expedition/actors/npc_essences.gd expedition/items/randart.gd expedition/progression/codex.gd expedition/ui/screens/essence_tab.gd expedition/ui/screens/codex_screen.gd tests/subtypes.gd tests/effect_data.gd tests/build_sense.gd tests/codex.gd tests/codex_ui.gd tests/randarts.gd tests/gear_affixes.gd tests/npc_essences.gd
git commit -m "Replace the twelve build families with seventeen sub-types in five role groups"
```

(실제로 고친 테스트 파일만 `git add`.)

---

### Task 2: 역할군과 조합

**Files:**
- Modify: `data/content/essences.json` (`role`)
- Modify: `expedition/progression/essences.gd` (`ROLES`), `bestiary.gd` (`ROLES`, `ROLE_POINTS`), `tag_sets.gd`, `stone_effects.gd`, `expedition/ai/stances.gd`, `expedition/actors/npc_essences.gd`
- Test: `tests/role_groups.gd` (새), 기존 `role_combos`, `tag_sets`, `bestiary`, `essences`, `stone_effects`, `crit`, `bosses`, `npc_essences`, `stat_sheet_ui`, `essence_ui`

**Interfaces:**
- Consumes: Task 1의 `Subtypes.GROUP_NAMES`
- Produces: `Essences.ROLES = Subtypes.GROUP_NAMES`와 같은 사전, `TagSets.ROLE_TEXT` 새 키, `StoneEffects.support_bracket(s, actor) -> int`(파티 최고 지원 구간, 옛 `pack_bracket` 대체)

- [ ] **Step 1: 실패하는 테스트** — `tests/role_groups.gd`

```gdscript
extends SceneTree
## Role groups (role groups spec §2–3): species stones in five groups, base
## stats by group, the combos at two, four and six, monsters untouched.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Bestiary = preload("res://expedition/progression/bestiary.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
const StoneEffects = preload("res://expedition/progression/stone_effects.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

const EXPECTED := {"TANK":["LIZARD_TAIL","HOB_TAUNT","SHIELD_STANCE","BEETLE_CURL","SERPENT_SHED","SKELETON_WALL","THORN_ARMOUR","FURNACE_HEART"],
	"MELEE":["GOBLIN_SHIV","ORC_CLEAVER","GNOLL_SPEAR","RIVER_RAT_SPLASH","ORE_SLAM","LEECH_LATCH","GHOUL_CLAW","VAMPIRE_BITE"],
	"RANGED":["KOBOLD_SLING","STORM_BAT","GOBLIN_AIM","ORC_THROW","TOAD_SPIT","SKELETON_VOLLEY"],
	"MAGIC":["FIRE_CALLER","FROST_IMP","GNOLL_SUMMONER","GRAVEKEEPER","SOUL_EATER"],
	"SUPPORT":["RAT_GNAW","GOBLIN_HEXER","SPIDER_WEB","WATER_WAVE","WRAITH","GOBLIN_CHIEF"]}

func slot(actor: Dictionary, ids: Array) -> void:
	actor.level = maxi(int(actor.level),ids.size())
	actor.equipped_abilities = ids.duplicate(); actor.essences = {}
	for id in ids: actor.essences[id] = 1

func run() -> void:
	for group in EXPECTED:
		for id in EXPECTED[group]: check(Essences.role(id) == group,"%s is %s" % [id,group])
	check(Essences.ROLES.size() == 5 and Essences.ROLES.TANK == "탱커","five group names")
	check(Bestiary.essence_stats("TANK") == {"hp":20,"ac":3},"a tank stone's base stats")
	check(Bestiary.essence_stats("SUPPORT") == {"hp":10,"mp":6},"a support stone's base stats")
	# Monsters read floor_monsters.json and keep their old numbers.
	check(Bestiary.monster_stats("dcss_rat",1) == MONSTER_RAT,"a rat is the same monster as before")
	var s = Session.new(731,false,true,true,2); s.depart(); s.manual_mode = true
	var c: Vector2i = Fixture.arena(s,8)
	var hero: Dictionary = s.party[0]; var ally: Dictionary = s.party[1]
	slot(hero,["HOB_TAUNT","SHIELD_STANCE","BEETLE_CURL","SERPENT_SHED"])
	check(TagSets.bracket(hero,"TANK") == 4,"four tank stones reach bracket four")
	check(TagSets.stat_bonus(hero).get("ac",0) == 5 and TagSets.stat_bonus(hero).get("sh",0) == 10,"tank four: armour +5, block +10")
	slot(hero,["GOBLIN_SHIV","ORC_CLEAVER"])
	check(TagSets.bracket(hero,"MELEE") == 2,"two melee stones")
	slot(hero,["RAT_GNAW","GOBLIN_HEXER","SPIDER_WEB","WATER_WAVE"]); slot(ally,["RAT_GNAW","GOBLIN_HEXER","SPIDER_WEB","WATER_WAVE"])
	check(StoneEffects.support_bracket(s,hero) == 4 and StoneEffects.support_bracket(s,ally) == 4,"support four reaches the party")
	print("Role groups: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
```

`MONSTER_RAT`은 이 Task를 시작하기 **전에** `Bestiary.monster_stats("dcss_rat",1)`을 찍어 상수로 적어 둔다(예: `const MONSTER_RAT := {...}`). 몬스터 수치가 바뀌지 않았음을 고정하는 스냅샷이다.

- [ ] **Step 2: 실패 확인** → 역할이 옛 id라 실패.

- [ ] **Step 3: 데이터** — `essences.json`의 33행 `role`을 스펙 §3 표대로(위 `EXPECTED`와 같다). 파일 서식 유지.

- [ ] **Step 4: 상수**

`essences.gd`:

```gdscript
const ROLES := {"TANK":"탱커","MELEE":"근딜","RANGED":"원딜","MAGIC":"마딜","SUPPORT":"지원"}
```

`bestiary.gd`의 영혼석 쪽만(몬스터 쪽 `ROLE_HP`·`ROLE_ATTACK`은 **그대로**):

```gdscript
## A soul stone's fixed base stats by role group (role groups spec §2.1).
const ROLE_POINTS := {
	"TANK":{"hp":20,"ac":3},
	"MELEE":{"atk":4,"hp":8},
	"RANGED":{"atk":3,"speed":5},
	"MAGIC":{"spell":4,"mp":8},
	"SUPPORT":{"hp":10,"mp":6}}
```

`bestiary.gd`의 `const ROLES := [...]`는 몬스터 역할 목록이면 그대로 두고, 영혼석 역할군 목록을 쓰는 곳이 있으면 `Essences.ROLES.keys()`로.

- [ ] **Step 5: `tag_sets.gd`**

- `ROLE_TEXT`를 스펙 §2.2 문구로(키 `TANK`·`MELEE`·`RANGED`·`MAGIC`·`SUPPORT`).
- `GUARD_ARMOUR`·`GUARD_BLOCK` → `TANK_ARMOUR := {2:2,4:5,6:6}`, `TANK_BLOCK := {2:0,4:10,6:12}`, `stat_bonus`의 `bracket(actor,"GUARD")` → `"TANK"`.
- `range_bonus`: `bracket(actor,"ARCHER") == 2` → `"RANGED"`.

- [ ] **Step 6: `stone_effects.gd`**

| 옛 | 새 |
| --- | --- |
| `pack_bracket`(무리, 파티 최고) | `support_bracket`: `TagSets.bracket(x,"SUPPORT")`의 파티 최고. `PACK_ATTACK` → `SUPPORT_ATTACK := {4:8,6:10}`(2구간은 공격력 없음) |
| `hp_percent`의 무리 4 동료 최대 HP +15% | **삭제** |
| `BERSERK_ATTACK` | `MELEE_ATTACK := {2:12,4:25,6:30}` |
| 광폭 4 절반 이하 속도 +15(`speed`) | **삭제** |
| 광폭 6 처치 회복 6% | 근딜 6 처치 회복 5%(`on_kill`) |
| `AMBUSH_CRIT`, 기습 6 "가득한 대상 항상 치명", 기습 4+ 치명 피해 +40 | **삭제.** 근딜 치명: `MELEE_CRIT := {4:8,6:10}`를 `crit_chance`에 |
| 무리 6 처치 시 파티 HP 3% | **삭제** |
| `ARCHER_RANGED`, 사수 6 추가 사격 | `RANGED_*` 같은 값 |
| `CASTER_SPELL`, 술사 4 MP +2, 술사 6 실패 없음 | `MAGIC_*` 같은 값 |
| 수호 6 인접 동료 −15% (`incoming`) | 탱커 6 인접 동료 −10% |
| (새) 지원 회복·보호 | `SUPPORT_HEAL := {2:20,4:30,6:40}`: `heal`에서 회복하는 인물(`healer`)의 지원 구간만큼 회복량 +%, `status_ticks`에서 `ward`를 거는 인물의 지원 구간만큼 지속 +% |
| (새) 지원 6 정화 | `round_start`: 지원 6인 인물의 인접 동료마다 해로운 상태가 있으면 `chance(s,actor,ally,"support_cleanse",25)`로 하나(가장 오래 남은 것) 해제, 알림 "정화!"(`heal` 톤) |

`outgoing`에서 역할 조합을 더하던 줄은 `SUPPORT_ATTACK.get(support_bracket(s,attacker))`, `MELEE_ATTACK.get(TagSets.bracket(attacker,"MELEE"))`, 원거리면 `RANGED_*`로. 읽히게 만들기의 보정 몫을 쓰는 코드가 있으면 몫 이름도 `set:SUPPORT` 등으로.

- [ ] **Step 7: `stances.gd`, `npc_essences.gd`**

- `stances.gd` 43행: `Essences.role(str(id)) == "GUARD"` → `== "TANK"`(기본 태세 수호형). 다른 역할군은 지금처럼 성격 기본값(스펙 §5의 추천은 이번에 강제하지 않는다).
- `npc_essences.gd` `preference`: `"BERSERK","AMBUSH"` → `"MELEE"`, `"GUARD"` → `"TANK","SUPPORT"`(높은 C), `"CASTER"` → `"MAGIC"`(높은 O), 나머지(`RANGED`)는 `PLAIN`.

- [ ] **Step 8: 테스트 옮기기** — 옛 역할 id(`"PACK"`,`"BERSERK"`,`"AMBUSH"`,`"GUARD"`,`"ARCHER"`,`"CASTER"`)를 영혼석 쪽 의미로 쓰는 테스트를 찾아(`grep -rln '"PACK"\|"BERSERK"\|"AMBUSH"\|"GUARD"\|"ARCHER"\|"CASTER"' tests`) 새 id·새 수치로 옮긴다. 몬스터 쪽 의미(`floor_monsters.json`의 role, `monster_ai`의 CASTER 등)는 그대로. 파츠 id `GUARD`(엄호)는 역할이 아니므로 그대로. `role_combos.gd`는 새 5개 역할군의 2·4·6 구간 검사로 다시 쓰되 검사 수를 줄이지 않는다(삭제된 효과 검사 자리에 지원 조합 검사).

- [ ] **Step 9: 확인**

Run: `for t in role_groups role_combos tag_sets bestiary essences stone_effects crit bosses npc_essences npc_roster stat_sheet_ui essence_ui stances utility protect difficulty_gate; do echo "== $t"; godot --headless --path . --script res://tests/$t.gd 2>&1 | grep -E "failures|ERROR" | head -3; done`
Expected: 모두 `0 failures`.

- [ ] **Step 10: Commit**

```bash
git add data/content/essences.json expedition/progression/essences.gd expedition/progression/bestiary.gd expedition/progression/tag_sets.gd expedition/progression/stone_effects.gd expedition/ai/stances.gd expedition/actors/npc_essences.gd tests/role_groups.gd tests/role_combos.gd tests/tag_sets.gd tests/bestiary.gd tests/essences.gd tests/stone_effects.gd tests/crit.gd tests/bosses.gd tests/npc_essences.gd
git commit -m "Group soul stones into tank, melee, ranged, magic and support with their own combos"
```

(실제로 고친 테스트 파일만.)

---

### Task 3: 화면 문구·CI·전체 확인

**Files:**
- Modify: 역할 이름을 보여 주는 화면(`essence_tab.gd`의 세트 목록, `character_folio.gd`, `popups.gd`의 적 정보 창 영혼석 줄, 읽히게 만들기의 연계·리포트 문구 중 역할 이름)
- Modify: `.github/workflows/deploy-pages.yml`
- Modify: `docs/systems-overview.ko.md`(역할 설명 한 줄)

- [ ] **Step 1: 문구** — 영혼석 카드 태그 줄 "탱커 · 방어탱"(`Essences.ROLES[role]` + `Subtypes.label`), 세트 목록 "탱커 3/4", 캐릭터 화면에 `BuildSense.subtype_profile` 상위 셋("방어탱 60% · 반사탱 30%"). 옛 역할 이름(무리·광폭·기습·수호·사수·술사)을 화면 문자열에서 찾아 모두 바꾼다: `grep -rn "무리\|광폭\|기습\|수호\|사수\|술사" --include=*.gd expedition/ui` (광폭은 세부 유형 이름으로 남을 수 있다 — 역할 의미로 쓴 것만).

- [ ] **Step 2: CI** — 스위트 목록에 `subtypes role_groups`.

- [ ] **Step 3: 전체 확인**

```bash
fail=0; for suite in $(sed -n 's/.*for suite in \(.*\); do/\1/p' .github/workflows/deploy-pages.yml); do out=$(godot --headless --path . --script "res://tests/${suite}.gd" 2>&1); if echo "$out" | grep -q "SCRIPT ERROR\|ERROR"; then echo "FAIL $suite"; fail=1; fi; done; echo "fail=$fail"
```

Expected: `fail=0`.

- [ ] **Step 4: 난이도 게이트 재측정** — `tests/difficulty_gate.gd`를 돌려 `docs/balance/difficulty-gate.md` 표를 갱신한다(역할 조합 수치가 바뀌었으므로). 합격선 판정이 크게 나빠지면 멈추고 보고한다.

- [ ] **Step 5: Commit**

```bash
git add expedition/ui .github/workflows/deploy-pages.yml docs/systems-overview.ko.md docs/balance/difficulty-gate.md docs/balance/difficulty-gate.json
git commit -m "Name role groups and sub-types on every screen and re-measure the gate"
```

---

## 끝난 뒤 확인

- 영혼석 탭에서 "탱커 · 방어탱", 세트 "탱커 4/6", 도감 역할군 → 세부 유형 거르기.
- 같은 시드 몬스터 수치 불변(Task 2 스냅샷).
- 스펙 대응: §1 → Task 1, §2 → Task 2, §3 → Task 2 데이터, §4 → Task 1 이전 스크립트, §5 → Task 1·2·3, §6 → 각 Task.
