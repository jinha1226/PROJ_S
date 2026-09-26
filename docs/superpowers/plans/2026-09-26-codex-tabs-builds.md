# 도감 3탭과 예시 빌드 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 도감 탭을 영혼석·아이템·빌드 셋으로 바꾸고, 예시 빌드를 빌드 탭에서 보여 주며 전투 시험(아레나)에서 바로 끼워 싸울 수 있게 한다.

**Architecture:** 새 모듈 `expedition/progression/example_builds.gd`가 `data/content/example_builds.json`을 읽고 `apply(s, actor, id)`로 인물에 빌드를 입힌다. 도감 화면(`codex_screen.gd`)은 탭 셋으로 다시 짠다: 영혼석 탭이 몬스터 머리줄을 품고, 아이템 탭은 장비 목록·본 옵션·찾은 고정 아티팩트, 빌드 탭은 예시 빌드와 파티. 아레나 설정은 인물마다 예시 빌드를 고르는 칸을 더한다.

**Tech Stack:** Godot 4 GDScript, `extends SceneTree` 테스트.

**Spec:** `docs/superpowers/specs/2026-09-26-codex-tabs-builds-design.md`
**선행:** 도감(`2026-09-26-codex.md`), 읽히게 만들기(`2026-09-26-legibility.md`), 역할군(`2026-09-26-role-groups.md`)이 커밋된 뒤. 역할군이 아직이면 `group`·`subtype` 표시만 옛 이름으로 두고 진행해도 된다.

## Global Constraints

- 탭 id: `stones`, `items`, `builds`. 노드 `CodexTab_stones`·`CodexTab_items`·`CodexTab_builds`. 옛 `monsters`·`unrands` 탭은 없앤다(`show_codex("monsters", key)` 호출은 영혼석 탭의 그 종족 상세로).
- 예시 빌드는 도감에 기록하지 않는다. `apply`는 가방·`essence_seen`·도감을 건드리지 않는다.
- 도감 파일에 `affixes` 절을 더한다(`{옵션 id: {"found": n}}`). 모르는 절 보존 규칙은 그대로.
- 아레나 인물 수 최대 3. 파티 예시는 3인.
- 커밋은 각 Task 파일만 `git add <경로>`. 판단이 어려우면 멈추고 묻는다.

## Review Focus

- **옛 진입점**: 적 정보 창의 "도감" 버튼(`show_codex("monsters", key)`)이 새 구성에서도 그 몬스터 상세로 간다. Task 2 테스트.
- **예시 빌드가 원정 상태를 오염하지 않음**: `apply` 뒤 `parts_bag`, `essence_seen`, `s.codex`가 그대로. Task 1 테스트.
- **양손 무기 빌드**: 활·지팡이 빌드에 왼손이 비어 있고 `apply`가 왼손을 비운다. Task 1 테스트.
- **도감 파일이 옛 버전(affixes 없음)**: 읽을 때 빈 `affixes`로 채우고 오류 없음. Task 3 테스트.

---

### Task 1: `example_builds.gd`

**Files:**
- Create: `expedition/progression/example_builds.gd`
- Test: `tests/example_builds.gd`

**Interfaces:**
- Consumes: `Essences.canonical`, `Essences.has`, `Essences.put`, `Essences.sync_spells`, `Essences.spell_choices(actor, id)`, `Essences.school(id)`, `Equipment`(칸·양손 판정), `StatSheet.refresh_pools(s, actor)`, `TagSets.bracket(actor, role)`
- Produces: `ExampleBuilds.data: Dictionary`, `ExampleBuilds.build(id) -> Dictionary`, `ExampleBuilds.party(id) -> Dictionary`, `ExampleBuilds.apply(s, actor: Dictionary, id: String) -> bool`

- [ ] **Step 1: 실패하는 테스트** — `tests/example_builds.gd`

```gdscript
extends SceneTree
## Example builds (codex tabs spec §4–5): every build is legal, applying one
## dresses a member fully and touches nothing else.
const Session = preload("res://expedition/run/session.gd")
const Builds = preload("res://expedition/progression/example_builds.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Equipment = preload("res://expedition/items/equipment.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var combat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/combat.json"))
	for b in Builds.data.builds:
		var stones: Array = b.stones
		check(stones.size() == 10,"%s has ten stones" % b.id)
		check(stones.all(func(id): return Essences.has(str(id)) and Essences.canonical(str(id)) == str(id)),"%s stones are canonical and real" % b.id)
		var seen := {}
		for id in stones: seen[id] = true
		check(seen.size() == 10,"%s repeats no stone" % b.id)
		check(combat.weapons.has(b.weapon) and combat.armours.has(b.armour),"%s wears real gear" % b.id)
		if int(combat.weapons[b.weapon].get("hands",1)) == 2: check(str(b.offhand).is_empty(),"%s leaves the off hand free for a two-handed weapon" % b.id)
		elif not str(b.offhand).is_empty(): check(combat.offhands.has(b.offhand),"%s has a real off hand" % b.id)
		check(b.flow.size() >= 2,"%s explains its flow" % b.id)
	for p in Builds.data.parties:
		check(p.members.size() == 3 and p.members.all(func(m): return not Builds.build(str(m)).is_empty()),"%s is three known builds" % p.id)
	var s = Session.new_run(731)
	s.codex = {"version":1}; var bag_before: Dictionary = s.parts_bag.duplicate(true); var seen_before: Dictionary = s.essence_seen.duplicate(true)
	var hero: Dictionary = s.party[0]
	check(Builds.apply(s,hero,"wall"),"the wall applies")
	check(int(hero.level) == 10 and Essences.equipped(hero).size() == 10,"level ten, ten stones worn")
	check(str(Equipment.worn(hero).get("offhand",{}).get("type","")) == "shield","the shield is in the off hand")
	check(s.parts_bag == bag_before and s.essence_seen == seen_before and s.codex == {"version":1},"nothing else changes")
	check(Builds.apply(s,hero,"elementalist") and Equipment.worn(hero).get("offhand",{}).is_empty(),"a staff build empties the off hand")
	check(not hero.prepared.is_empty(),"the caster build readies spells")
	check(not Builds.apply(s,hero,"no_such"),"an unknown build is refused")
	print("Example builds: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
```

(`combat.offhands`·`Equipment.worn`의 실제 이름이 다르면 장비 구현에 맞춘다.)

- [ ] **Step 2: 구현** — `example_builds.gd`

```gdscript
extends RefCounted
## Example builds (codex tabs spec §4): finished loadouts for the codex's build
## tab and the battle test. Applying one never touches the bag, the kill
## record or the codex.
const Essences = preload("res://expedition/progression/essences.gd")
static var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/example_builds.json"))

static func build(id: String) -> Dictionary:
	for b in data.get("builds",[]):
		if str(b.id) == id: return b
	return {}

static func party(id: String) -> Dictionary:
	for p in data.get("parties",[]):
		if str(p.id) == id: return p
	return {}

static func apply(s, actor: Dictionary, id: String) -> bool:
	var b := build(id)
	if b.is_empty(): return false
	actor.level = int(b.get("level",10))
	actor.essences = {}; actor.essence_spells = {}; actor.equipped_abilities = []; actor.rules = []
	Essences.sync_slots(actor)
	for i in range(b.stones.size()):
		var stone: String = str(b.stones[i])
		actor.essences[stone] = 1
		Essences.put(actor,i,stone)
	for stone in b.get("schools",{}):
		var choices: Array = Essences.spell_choices(actor,str(stone))
		if not choices.is_empty(): actor.essence_spells[str(stone)] = str(choices[choices.size()-1])
	Essences.sync_spells(actor)
	actor.gear.weapon = {"type":str(b.weapon),"tier":"base","enchant":0}
	actor.gear.offhand = {} if str(b.get("offhand","")).is_empty() else {"type":str(b.offhand),"tier":"base","enchant":0}
	actor.gear.armour = {"type":str(b.armour),"tier":"base","enchant":0}
	actor.gear.ring1 = {}; actor.gear.ring2 = {}
	if s != null and str(b.get("stance","")) != "": actor.stance = str(b.stance)
	if s != null: s.StatSheet.refresh_pools(s,actor); actor.hp = int(actor.max_hp); actor.mp = int(actor.get("max_mp",0))
	return true
```

(장비 사전의 칸 이름·등급 필드는 장비 구현(`Equipment`)의 실제 모양에 맞춘다. `s.StatSheet`가 세션 상수로 없으면 `preload`.)

- [ ] **Step 3: 확인·Commit**

Run: `godot --headless --path . --script res://tests/example_builds.gd` → `0 failures`.

```bash
git add expedition/progression/example_builds.gd tests/example_builds.gd data/content/example_builds.json
git commit -m "Add eleven example builds and three-member parties that dress a member in one call"
```

---

### Task 2: 도감 탭 셋

**Files:**
- Modify: `expedition/ui/screens/codex_screen.gd`, `expedition/progression/codex.gd`(`affixes`, 항목 함수), `expedition/ui/main.gd`(`show_codex` 기본 탭), 장비를 줍는 곳(`expedition/items/curios.gd` 또는 `Randart.make` 결과를 가방에 넣는 곳)
- Test: `tests/codex_ui.gd`, `tests/codex.gd`

**Interfaces:**
- Produces: `CodexScreen.show(ui, tab := "stones", focus := "", filter := "")`(filter는 역할군 id 또는 세부 유형 id), `Codex.note_affix(s, id)`, `Codex.item_rows(data) -> Array`(묶음별 행), 노드 `CodexSpecies_<종족>`, `CodexMonsterDetail`, `CodexItems_<묶음>`, `CodexBuild_<id>`, `CodexBuildDetail`, `CodexTryBuild`, `CodexParty_<id>`, `CodexTryParty`

- [ ] **Step 1: 테스트 고치기** — `tests/codex_ui.gd`를 새 탭으로:
  - `show_codex()` → `CodexTab_stones` 눌림, `CodexSpecies_dcss_rat`(봤음, 그림)과 `CodexSpecies_cave_spider`(못 봄, 실루엣 메타 `known == false`).
  - `show_codex("monsters","dcss_rat")` → 영혼석 탭에서 `CodexMonsterDetail`(메타 `key == "dcss_rat"`).
  - `show_codex("items")` → `CodexItems_weapons`에 7행, `CodexItems_unrands`에 찾은 것만 이름, 나머지 "???", `CodexItems_affixes`에 본 옵션만.
  - `show_codex("builds")` → `CodexBuild_wall`, 누르면 `CodexBuildDetail`에 부위 10줄과 흐름 줄, `CodexTryBuild` 버튼.
  - `CodexTryBuild` 누름 → 아레나 설정 화면이 열리고 1번 인물 설정의 `build == "wall"`.
  - 옛 검사 수 유지(바뀐 탭 이름에 맞춰 옮긴다).
  - `tests/codex.gd`에: 옛 파일(`affixes` 없음) 읽기 → 빈 `affixes`, `note_affix` 기록·보존.

- [ ] **Step 2: `codex.gd`** — `empty()`와 `SECTIONS`에 `affixes`. `note_affix(s, id)`(다른 `note_*`와 같은 모양, 기록 꺼짐이면 무시). 장비를 가방에 넣는 곳에서 옵션(`item.affix`)이 있으면 `note_affix`, 고정 아티팩트면 `note_unrand`(이미 있으면 그대로).
  `item_rows(data)`: `[{"group":"weapons","rows":[{"name","form","damage","delay","hands"}]}, {"group":"offhands",…}, {"group":"armours",…}, {"group":"rings",…}, {"group":"affixes","rows":[본 옵션: name, text, subtype]}, {"group":"unrands","rows":[찾으면 name·slot·text·cost, 못 찾으면 slot과 "???"]}]`. 옵션 이름·문구는 `stone_effects.json`의 효과 행(`source == "gear"`), 고정 아티팩트는 `unrands.json` 행.

- [ ] **Step 3: `codex_screen.gd` 다시 짜기**
  - 헤더(제목·닫기), 완성률 한 줄, 탭 셋, 스크롤 목록 — 지금 구조 유지.
  - `stones`: 구역 제목 → 종족마다 `CodexSpecies_<종족>`(가로: 그림 48px, 이름, 역할군, "처치 n") 버튼 → 누르면 `CodexMonsterDetail`(지금의 몬스터 상세 내용) + "← 목록". 그 아래 부위 셋(지금의 영혼석 항목, 세부 유형·키워드 칩). 위쪽 거르기(역할군 → 세부 유형). `focus`가 종족이면 바로 상세.
  - `items`: `item_rows`의 묶음마다 제목(`CodexItems_<group>`)과 행.
  - `builds`: 예시 빌드 카드(`CodexBuild_<id>`: 이름, "역할군 · 세부 유형", 무기, 흐름 첫 줄) → 상세(`CodexBuildDetail`): 장비 한 줄, 부위 10줄(`Essences.title` · 세부 유형 · 효과 문구, 도감에 모았으면 ✓·아니면 흐리게), 흐름 전부, 역할군 조합("탱커 6개 · 6구간" — 빌드의 부위 역할군을 세서), 버튼 `CodexTryBuild`. 아래 파티 예시(`CodexParty_<id>`) 카드와 버튼 `CodexTryParty`.
  - 옛 `monsters`·`unrands` 탭 이름으로 들어오면: `monsters` → `stones` + 그 종족 상세, `unrands` → `items`.

- [ ] **Step 4: 확인·Commit**

Run: `for t in codex codex_ui inspect_ui ui_smoke; do echo "== $t"; godot --headless --path . --script res://tests/$t.gd 2>&1 | grep -E "failures|ERROR" | head -3; done` → 모두 `0 failures`.

```bash
git add expedition/ui/screens/codex_screen.gd expedition/progression/codex.gd expedition/ui/main.gd expedition/items/curios.gd tests/codex_ui.gd tests/codex.gd
git commit -m "Split the codex into soul stone, item and build tabs"
```

(장비 줍기 경로가 다른 파일이면 그 파일을 `git add`.)

---

### Task 3: 아레나에서 예시 빌드

**Files:**
- Modify: `expedition/ui/screens/arena_setup.gd`(인물 카드), `expedition/run/arena_test.gd`(`arena_test`), `expedition/ui/main.gd`(`arena_config` 기본값, `show_arena_setup_with(builds: Array)`)
- Modify: `.github/workflows/deploy-pages.yml`
- Test: `tests/arena_mode.gd`

**Interfaces:**
- Consumes: Task 1 `ExampleBuilds.apply`, `ExampleBuilds.data.builds`
- Produces: `arena_config.members[i].build: String`(빈 문자열이면 빌드 없음), `main.show_arena_setup_with(ids: Array)` — 인원 = `ids.size()`, 각 인물 `build` 설정 후 아레나 설정 화면

- [ ] **Step 1: 테스트** — `tests/arena_mode.gd`에:
  - `show_arena_setup_with(["wall"])` → 인원 1, 1번 `build == "wall"`, 인물 카드에 `ArenaBuild_0`(선택 "철벽").
  - 시작하면 주인공이 `wall` 빌드(장착 10, 방패)로 싸운다.
  - `show_arena_setup_with(["bone_breaker","hawk_eye","hexer"])` → 인원 3, 각 빌드.
  - 빌드를 고른 인물 카드에는 파츠 두 칸 선택(`ArenaPart_i_*`)이 없다.
  - 기존 검사 수 유지.

- [ ] **Step 2: `arena_setup.gd`** — 인물 카드에 `OptionButton` `ArenaBuild_<i>`("예시 빌드 없음" + 빌드 이름들). 선택하면 `ui.arena_config.members[i].build = id` 후 화면 다시 그림. `build`가 있으면 파츠 선택 줄을 그리지 않고 "빌드: <이름> · <역할군 · 세부 유형>" 한 줄.

- [ ] **Step 3: `arena_test.gd`** — 인물마다 `setup.build`가 있으면 파츠 두 칸 처리 대신 `ExampleBuilds.apply(s, actor, setup.build)`. 태세는 설정의 태세가 있으면 그것, 없으면 빌드의 `stance`(1인 전투의 수호형 → 돌격형 규칙은 그대로).

- [ ] **Step 4: `main.gd`** — `arena_config` 멤버 기본값에 `"build":""`. `show_arena_setup_with(ids)`: 인원·빌드를 채우고 `show_arena_setup()`. 도감의 `CodexTryBuild`·`CodexTryParty`가 이것을 부른다(Task 2에서 버튼만 만들었으면 여기서 연결).

- [ ] **Step 5: CI와 전체 확인** — 스위트 목록에 `example_builds`. 전체:

```bash
fail=0; for suite in $(sed -n 's/.*for suite in \(.*\); do/\1/p' .github/workflows/deploy-pages.yml); do out=$(godot --headless --path . --script "res://tests/${suite}.gd" 2>&1); if echo "$out" | grep -q "SCRIPT ERROR\|ERROR"; then echo "FAIL $suite"; fail=1; fi; done; echo "fail=$fail"
```

Expected: `fail=0`.

- [ ] **Step 6: Commit**

```bash
git add expedition/ui/screens/arena_setup.gd expedition/run/arena_test.gd expedition/ui/main.gd expedition/ui/screens/codex_screen.gd tests/arena_mode.gd .github/workflows/deploy-pages.yml
git commit -m "Try any example build or party straight from the codex in the battle test"
```

---

## 끝난 뒤 확인

- 메인 화면 → 도감 → 빌드 → 철벽 → 전투 시험에서 해보기 → 철벽 장비로 싸움.
- 도감 → 영혼석 → 쥐 머리줄 → 몬스터 상세. 아이템 탭에서 무기 7종과 찾은 고정 아티팩트.
- 스펙 대응: §1 → Task 2, §2 → Task 2, §3 → Task 2·3, §4 → Task 1·3, §5 → 데이터(이미 있음), §6 → 각 Task.
