# 물약·두루마리 소모품과 미감정 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기존 5칸 `supplies` 배열을 SPD식 물약 8종·두루마리 8종 카탈로그로 바꾸고, 미감정 상태로 바닥·조사물에서 나와 사용하거나 감정 두루마리로 정체를 알게 한다.

**Architecture:** `data/content/consumables.json`이 카탈로그·외관 풀·가중치를 들고, 정적 모듈 `expedition/items/consumables.gd`가 지급·줍기·감정·사용 동사 전부를 맡는다(`Gear`가 파츠·장비를 맡는 것과 같은 자리). 세션은 `bag`·`known`·`appearances`·`pending_choice` 네 필드와 얇은 래퍼만 가진다. 바닥 아이템은 층 생성기가 놓는 `kind == "item"` feature이고, `act_as`의 `MOVE`가 줍는다.

**Tech Stack:** Godot 4.6 GDScript, 헤드리스 테스트(`godot --headless --path . --script res://tests/<suite>.gd`), JSON 콘텐츠.

**Spec:** `docs/superpowers/specs/2026-09-24-consumables-identification-design.md`

## Global Constraints

- 테스트 실행 전 임포트: `godot --headless --path . --editor --import --quit` (한 번이면 충분).
- 모든 스위트는 `push_error`가 하나도 없고 종료 코드 0이어야 통과. `SCRIPT ERROR:`·`^ERROR:` 줄이 로그에 있으면 실패(CI 규칙).
- 결정성: 게임 코드의 무작위는 `Hexaco.sample(seed, key, lane, modulus)`(세션) 또는 생성기의 `rng`(층 생성)만 쓴다. `randi()` 금지.
- 메시지·라벨은 한국어. 외관 라벨 형식: 물약 `"%s 물약"`, 두루마리 `"'%s' 두루마리"`.
- 커밋 메시지 끝에 `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- 파일 스타일: 기존처럼 한 줄에 여러 문장을 `;`로 잇는 압축 스타일을 따라도 되지만, 새 파일은 함수 하나가 한 가지 일만 하게 쓴다.
- 작업 트리에 이 기능과 무관한 미커밋 변경(`main.gd mark_selected`, `floor_hud`, `start_screen`, `tests/continuous_floor.gd`, `tests/start_kit.gd`, `docs/superpowers/plans/2026-09-23-model-b-combat-mastery-ui.md`)이 있다. 건드리지 말고, 커밋할 때는 이 계획의 파일만 `git add`한다.

---

## File Structure

| 파일 | 역할 |
|---|---|
| `data/content/consumables.json` (신규) | 16종 카탈로그(`kinds`), 외관 풀(`appearances`) |
| `expedition/items/consumables.gd` (신규) | 카탈로그 조회, 외관 셔플, 라벨, 드롭 추첨, 지급·줍기·감정, 사용(마시기·던지기·읽기), 선택 완료 |
| `expedition/run/session.gd` | 새 필드 4개, `Consumables` preload, 래퍼 5개, `act`의 선택 대기 거부, `MOVE` 줍기 훅, `supplies` 관련 삭제 |
| `expedition/run/descent.gd` | `depart`에서 가방 초기화·외관 셔플 |
| `expedition/items/gear.gd` | `grant_supply`·`use_supply` 삭제 |
| `expedition/items/curios.gd` | 소모품 지급을 새 풀로 |
| `expedition/combat/combat_stats.gd` | `str_bonus` 반영 |
| `expedition/actors/monster_ai.gd` | `sleep_until` 잠·깸 |
| `expedition/level/floor_generator.gd` | 바닥 아이템 배치 |
| `data/content/floor_themes.json` | `items` 범위 |
| `data/content/combat.json` | `summons.mirror` 행 |
| `expedition/art/map_icons.gd` | `potion`·`scroll` 아이콘 |
| `expedition/ui/board.gd` | item feature 아이콘 선택 |
| `expedition/ui/screens/popups.gd` | 가방 행·상세창·선택 팝업 |
| `expedition/ui/screens/floor_hud.gd` | 소모품 바 삭제, `choose_item(kind)` |
| `expedition/ui/main.gd` | `pending_item: String`, 선택 팝업 호출 |
| `expedition/sim/encounter_runner.gd`, `expedition/sim/bot_policy.gd` | 가방 API로 |
| `tests/consumables.gd` (신규) | 이 기능의 스위트 |
| `tests/mobile_actions.gd`, `run_start.gd`, `solo_floor.gd`, `curios.gd`, `arena_mode.gd`, `abilities_growth.gd`, `autobattle.gd`, `floor_generator.gd` | API 변경 반영 |
| `.github/workflows/deploy-pages.yml`, `README.md`, `docs/systems-overview.ko.md`, `docs/inventory-ui.md` | 등록·문서 |

테스트 스위트 뼈대(모든 태스크가 같은 파일에 함수를 더한다):

```gdscript
extends SceneTree
## 물약·두루마리: 카탈로그, 외관 셔플, 바닥 드롭·줍기, 사용 감정, 감정·강화 선택,
## 광역 투척, 잠·분노·거울상 (스펙 docs/superpowers/specs/2026-09-24-consumables-identification-design.md §7).
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Consumables = preload("res://expedition/items/consumables.gd")
const Generator = preload("res://expedition/level/floor_generator.gd")
const Floor = preload("res://expedition/level/continuous_floor.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

## A lone hero on an open floor, every monster dead, one action in hand.
func solo(seed: int = 41) -> Dictionary:
	var s = Session.new_run(seed); var c: Vector2i = Fixture.arena(s,8)
	for enemy in s.enemies: enemy.hp = 0
	s.party[0].ap = 1
	return {"s":s,"c":c}

func run() -> void:
	catalog()
	appearances()
	print("Consumables: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
```

`Session.new_run(seed)`은 수동 모드(`manual_mode = true`)의 1인 Run이다. 수동 모드에서 `use_item`은 `Scheduler.advance(s,100)`로 시간을 흘린다.

---

### Task 1: 카탈로그 JSON과 모듈의 조회·외관·추첨

**Files:**
- Create: `data/content/consumables.json`
- Create: `expedition/items/consumables.gd`
- Create: `tests/consumables.gd`

**Interfaces:**
- Produces: `Consumables.content: Dictionary`, `definition(kind) -> Dictionary`, `kinds() -> Array[String]`, `of_class(cls) -> Array`, `shuffle_appearances(seed) -> Dictionary`, `random_kind(seed, key) -> String`, `random_kind_rng(rng) -> String`, `total_weight() -> int`.

- [ ] **Step 1: 카탈로그 JSON 작성**

`data/content/consumables.json`:

```json
{
  "kinds": {
    "healing": {"class": "potion", "name": "치유 물약", "description": "HP +20 · 출혈 해제", "weight": 15, "area": false},
    "strength": {"class": "potion", "name": "힘의 물약", "description": "힘 +3 영구 · 최대 HP +5", "weight": 3, "area": false},
    "haste": {"class": "potion", "name": "가속 물약", "description": "가속 300틱", "weight": 5, "area": false},
    "liquid_flame": {"class": "potion", "name": "액체 화염", "description": "던지면 3×3 점화·화상 · 마시면 자기 발밑", "weight": 6, "area": true},
    "frost": {"class": "potion", "name": "냉기 물약", "description": "던지면 3×3 빙결·바닥 물기 · 마시면 자신 빙결", "weight": 5, "area": true},
    "toxic_gas": {"class": "potion", "name": "독가스 물약", "description": "던지면 3×3 중독 · 마시면 자신 중독", "weight": 6, "area": true},
    "experience": {"class": "potion", "name": "경험의 물약", "description": "레벨 1 상승", "weight": 3, "area": false},
    "calm": {"class": "potion", "name": "정신 안정제", "description": "스트레스 -25", "weight": 8, "area": false},
    "identify": {"class": "scroll", "name": "감정 두루마리", "description": "미감정 종류 하나를 골라 감정", "weight": 20},
    "upgrade": {"class": "scroll", "name": "강화 두루마리", "description": "장착 중인 무기나 방어구 강화 +1", "weight": 4},
    "magic_mapping": {"class": "scroll", "name": "마법 지도", "description": "이 층 전체를 드러낸다", "weight": 6},
    "teleportation": {"class": "scroll", "name": "순간이동 두루마리", "description": "멀리 떨어진 빈 칸으로 이동", "weight": 6},
    "mirror_image": {"class": "scroll", "name": "거울상 두루마리", "description": "거울상 2체를 300틱 소환", "weight": 5},
    "lullaby": {"class": "scroll", "name": "자장가 두루마리", "description": "시야 안의 몬스터를 300틱 재운다", "weight": 5},
    "rage": {"class": "scroll", "name": "분노 두루마리", "description": "층의 모든 몬스터가 깨어나 가속한다", "weight": 4},
    "recharging": {"class": "scroll", "name": "재충전 두루마리", "description": "MP 전부 회복", "weight": 5}
  },
  "appearances": {
    "potion": ["붉은", "푸른", "검은", "탁한", "빛나는", "끈적한", "김이 나는", "보랏빛", "은빛", "흐린"],
    "scroll": ["ZELGO MER", "JUYEDO", "KIRJE", "XIXAXA", "PRATYAVAYAH", "DAIYEN FOOELS", "ELBIB YLOH", "VERR YED HORRE", "VENZAR BORGAVVE", "THARR"]
  }
}
```

- [ ] **Step 2: 실패하는 테스트 작성**

`tests/consumables.gd`를 위 뼈대로 만들고 두 함수를 추가:

```gdscript
## Eight potions, eight scrolls, ten looks apiece, every weight positive.
func catalog() -> void:
	check(Consumables.of_class("potion").size() == 8 and Consumables.of_class("scroll").size() == 8,"eight potions and eight scrolls")
	check(Consumables.kinds().size() == 16,"sixteen kinds")
	for kind in Consumables.kinds():
		var def: Dictionary = Consumables.definition(kind)
		check(int(def.weight) > 0 and not str(def.name).is_empty() and str(def["class"]) in ["potion","scroll"],"kind %s is well formed" % kind)
	check(Consumables.content.appearances.potion.size() == 10 and Consumables.content.appearances.scroll.size() == 10,"ten looks per class")
	check(Consumables.total_weight() == 106,"weights sum as the spec lists them")
	var tally: Dictionary = {}
	for key in range(400):
		var kind: String = Consumables.random_kind(7,key)
		tally[kind] = int(tally.get(kind,0))+1
	check(tally.get("identify",0) > tally.get("strength",0),"identify drops more than strength")
	check(tally.size() >= 12,"most kinds show up in 400 rolls (%d)" % tally.size())
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	check(Consumables.random_kind_rng(rng) in Consumables.kinds(),"rng draw picks a kind")

## Same seed, same looks; every kind wears a different one; another seed differs somewhere.
func appearances() -> void:
	var a: Dictionary = Consumables.shuffle_appearances(11)
	var b: Dictionary = Consumables.shuffle_appearances(11)
	var c: Dictionary = Consumables.shuffle_appearances(12)
	check(a == b,"same seed, same appearances")
	check(a != c,"another seed shuffles differently")
	check(a.size() == 16,"every kind has a look")
	check(a.values().size() == a.values().reduce(func(acc,v): return acc if v in acc else acc+[v],[]).size(),"no two kinds share a look")
	check(str(a.healing).ends_with(" 물약") and str(a.identify).begins_with("'") and str(a.identify).ends_with("' 두루마리"),"potion and scroll label formats")
```

- [ ] **Step 3: 실패 확인**

```bash
godot --headless --path . --script res://tests/consumables.gd
```
Expected: 파싱 오류(`res://expedition/items/consumables.gd` 없음) 또는 실패 다수, 종료 코드 1.

- [ ] **Step 4: 모듈 작성**

`expedition/items/consumables.gd`:

```gdscript
extends RefCounted
## Potions and scrolls: the catalog, the looks a run gives them, and the verbs —
## drop, pick up, identify, drink, throw, read. The session keeps `bag`,
## `known`, `appearances` and `pending_choice`; this file is the only writer.
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
static var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/consumables.json"))

static func definition(kind: String) -> Dictionary:
	return content.kinds.get(kind,{})

static func kinds() -> Array:
	return content.kinds.keys()

static func of_class(cls: String) -> Array:
	return kinds().filter(func(k): return str(content.kinds[k]["class"]) == cls)

static func total_weight() -> int:
	var total := 0
	for kind in kinds(): total += int(content.kinds[kind].weight)
	return total

## One drop from the whole catalog, weight for weight.
static func random_kind(seed: int, key: int) -> String:
	return kind_at(Hexaco.sample(seed,key,"item_kind",total_weight()))

## The generator's own rng draws the same way, so a floor is one seed's floor.
static func random_kind_rng(rng: RandomNumberGenerator) -> String:
	return kind_at(rng.randi_range(0,total_weight()-1))

static func kind_at(roll: int) -> String:
	var left := roll
	for kind in kinds():
		left -= int(content.kinds[kind].weight)
		if left < 0: return kind
	return kinds()[0]

## Every kind gets a look from its class's pool: a Fisher–Yates shuffle keyed
## on the seed, so the same seed always dresses the same bottles.
static func shuffle_appearances(seed: int) -> Dictionary:
	var result: Dictionary = {}
	for cls in ["potion","scroll"]:
		var pool: Array = content.appearances[cls].duplicate()
		for i in range(pool.size()-1,0,-1):
			var j: int = Hexaco.sample(seed,i,"appearance_"+cls,i+1)
			var swap = pool[i]; pool[i] = pool[j]; pool[j] = swap
		var members: Array = of_class(cls)
		for k in range(members.size()):
			result[members[k]] = ("%s 물약" % pool[k]) if cls == "potion" else ("'%s' 두루마리" % pool[k])
	return result
```

- [ ] **Step 5: 통과 확인**

```bash
godot --headless --path . --script res://tests/consumables.gd
```
Expected: `Consumables: N checks, 0 failures`, 종료 코드 0.

- [ ] **Step 6: 커밋**

```bash
git add data/content/consumables.json expedition/items/consumables.gd tests/consumables.gd
git commit -m "Add potion and scroll catalog with per-run appearances

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: 세션 가방·감정·마시기(단일 대상 물약)

**Files:**
- Modify: `expedition/items/consumables.gd`
- Modify: `expedition/run/session.gd` (필드는 `var supplies` 근처 104행, 래퍼는 `grant_supply` 근처 300행, `act` 437행)
- Modify: `expedition/run/descent.gd:8-35` (`depart`)
- Modify: `expedition/combat/combat_stats.gd:20-42`
- Test: `tests/consumables.gd`

**Interfaces:**
- Consumes: Task 1의 조회 함수.
- Produces: 세션 `bag`, `known`, `appearances`, `pending_choice`; `Session.grant_item(kind, count=1, known=false)`, `use_item(kind, target=Vector2i(-1,-1), recipient=-1) -> bool`, `identify_item(kind)`, `item_label(kind) -> String`, `resolve_choice(option) -> bool`; `Consumables.label(s,kind)`, `description(s,kind)`, `grant`, `identify`, `use`, `unknown_kinds(s, exclude="") -> Array`; 효과 코드 상수 `REFUSED=0, APPLIED=1, WASTED=2`; 액터 필드 `str_bonus`.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/consumables.gd`의 `run()`에 `drinking()`을 추가하고:

```gdscript
## A bottle nobody has tasted wears its colour; the first sip names it.
func drinking() -> void:
	var f := solo(); var s = f.s; var hero: Dictionary = s.party[0]
	check(s.bag.is_empty() and s.known.is_empty() and s.appearances.size() == 16,"a run starts with an empty bag and dressed bottles")
	s.grant_item("healing")
	check(s.bag.healing == 1 and not s.known.has("healing"),"an unknown bottle joins the bag")
	check(s.item_label("healing") == s.appearances.healing and s.log_lines.back() == s.appearances.healing+" 획득","the pickup line uses the look")
	check(not s.use_item("healing") and s.bag.healing == 1,"full health refuses the potion and keeps it")
	hero.hp = 30; hero.statuses["bleed"] = s.time+500
	var before_time: int = s.time
	check(s.use_item("healing"),"the hero drinks")
	check(hero.hp == 50 and not hero.statuses.has("bleed"),"healing heals and stops bleeding")
	check(s.known.has("healing") and s.item_label("healing") == "치유 물약","the sip identifies the kind")
	check(s.log_lines.any(func(l): return l == s.appearances.healing+"은 치유 물약이었다"),"the log names what it was")
	check(not s.bag.has("healing") and s.time == before_time+100,"the bottle is spent and time passes")
	check(not s.use_item("healing"),"an empty stack refuses")
	s.grant_item("calm",2,true)
	check(s.known.has("calm") and s.item_label("calm") == "정신 안정제" and s.log_lines.back() == "정신 안정제 ×2 획득","a known grant uses the name")
	check(not s.use_item("calm"),"no stress, no sip")
	hero.stress = 40; s.party[0].ap = 1
	check(s.use_item("calm") and hero.stress == 15 and s.bag.calm == 1,"calm eases stress")
	s.grant_item("strength",1,true); s.grant_item("haste",1,true); s.grant_item("experience",1,true)
	var max_before: int = hero.max_hp; var damage_before: int = Session.CombatStats.stats(s,hero).damage
	hero.hp = 10
	check(s.use_item("strength") and hero.max_hp == max_before+5 and hero.hp == 15 and int(hero.get("str_bonus",0)) == 3,"strength is permanent")
	check(Session.CombatStats.stats(s,hero).damage >= damage_before,"strength never lowers damage")
	check(s.use_item("haste") and hero.statuses.has("haste"),"haste hangs its status")
	var level_before: int = hero.level
	check(s.use_item("experience") and hero.level == level_before+1,"experience is one level")
	check(not s.use_item("nonsense"),"unknown kinds are refused")
	check(not s.use_item("calm",Vector2i(-1,-1),5),"a recipient outside the party is refused")
	s.phase = "CAMP"; hero.stress = 30
	check(s.use_item("calm") and hero.stress == 5,"potions work at camp")
```

- [ ] **Step 2: 실패 확인**

```bash
godot --headless --path . --script res://tests/consumables.gd
```
Expected: `grant_item` 없음으로 실패.

- [ ] **Step 3: 세션 필드와 래퍼**

`expedition/run/session.gd` — `var supplies: Array = [0,0,0,0,0]` 바로 아래에:

```gdscript
## Potions and scrolls: counts by kind, the kinds this run has named, the look
## each kind wears this run, and a choice a scroll is waiting on (§2 of the
## consumables spec). `Consumables` is the only writer.
var bag: Dictionary = {}
var known: Dictionary = {}
var appearances: Dictionary = {}
var pending_choice: Dictionary = {}
const Consumables = preload("res://expedition/items/consumables.gd")
```

`_init`의 `reset_battle_stats()` 앞줄에 `appearances = Consumables.shuffle_appearances(seed_value)` 추가(depart 전에도 라벨이 나오도록).

`func grant_supply(slot: int) -> void: Gear.grant_supply(self,slot)` 아래에:

```gdscript
func grant_item(kind: String, count: int = 1, p_known: bool = false) -> void: Consumables.grant(self,kind,count,p_known)
func use_item(kind: String, target: Vector2i = Vector2i(-1,-1), recipient: int = -1) -> bool: return Consumables.use(self,kind,target,recipient)
func identify_item(kind: String) -> void: Consumables.identify(self,kind)
func resolve_choice(option: String) -> bool: return Consumables.resolve_choice(self,option)
func item_label(kind: String) -> String: return Consumables.label(self,kind)
```

`func act(kind: String, target: Vector2i) -> bool:` 첫 줄에 `if not pending_choice.is_empty(): return false` 추가.

- [ ] **Step 4: depart 초기화**

`expedition/run/descent.gd` `depart`의 `s.reset_battle_stats()` 앞에:

```gdscript
	s.bag = {}; s.known = {}; s.pending_choice = {}
	s.appearances = s.Consumables.shuffle_appearances(s.seed_value)
```

- [ ] **Step 5: 힘 보정**

`expedition/combat/combat_stats.gd` `stats`에서 `var spec: Dictionary = species(actor)` 바로 뒤에 `var strength: int = int(spec.str)+int(actor.get("str_bonus",0))`를 넣고, 그 아래 세 곳의 `int(spec.str)`을 `strength`로 바꾼다(`result.damage = 4 + strength / 6`, `+ strength / 6`, `int(armour_def.enc) - strength / 5`).

- [ ] **Step 6: 모듈에 라벨·지급·감정·사용 추가**

`expedition/items/consumables.gd`에 preload와 상수 추가. `Spells`·`Statuses`·`Scheduler`는 preload하지 않고 `curios.gd`처럼 세션 상수(`s.Spells`, `s.Statuses`, `s.Scheduler`)로 부른다 — 생성기가 이 모듈을 preload하므로 순환 preload를 피한다.

```gdscript
const Body = preload("res://game/rebuilt/body_bridge.gd")
const REFUSED := 0
const APPLIED := 1
const WASTED := 2
```

그리고 함수들:

```gdscript
static func label(s, kind: String) -> String:
	if s.known.has(kind): return str(definition(kind).get("name",kind))
	return str(s.appearances.get(kind,kind))

static func description(s, kind: String) -> String:
	if s.known.has(kind): return str(definition(kind).get("description",""))
	return "마셔 보거나 감정해야 정체를 안다" if str(definition(kind).get("class","")) == "potion" else "읽어 보거나 감정해야 정체를 안다"

static func grant(s, kind: String, count: int = 1, p_known: bool = false) -> void:
	if not content.kinds.has(kind) or count <= 0: return
	if p_known: s.known[kind] = true
	s.bag[kind] = int(s.bag.get(kind,0))+count
	s.message(label(s,kind)+(" 획득" if count == 1 else " ×%d 획득" % count))

## Naming a kind: once per run, with the line that says what the look was.
static func identify(s, kind: String) -> void:
	if s.known.has(kind) or not content.kinds.has(kind): return
	var look: String = label(s,kind)
	s.known[kind] = true
	s.message("%s은 %s이었다" % [look,label(s,kind)])

static func unknown_kinds(s, exclude: String = "") -> Array:
	return s.bag.keys().filter(func(k): return k != exclude and int(s.bag[k]) > 0 and not s.known.has(k))

## The one verb the UI calls. A potion with a target is thrown, otherwise the
## recipient (default: the selected member) drinks it; a scroll is read by the
## selected member. Returns false without consuming when the item cannot act.
static func use(s, kind: String, target: Vector2i = Vector2i(-1,-1), recipient: int = -1) -> bool:
	var def: Dictionary = definition(kind)
	if def.is_empty() or int(s.bag.get(kind,0)) <= 0: return false
	if s.phase not in ["EXPLORE","BATTLE","CAMP"] or not s.pending_choice.is_empty(): return false
	if recipient < -1 or recipient >= s.party.size(): return false
	var user: Dictionary = s.party[s.selected]
	var actor: Dictionary = s.party[s.selected if recipient == -1 else recipient]
	if user.hp <= 0 or actor.hp <= 0 or (s.on_floor() and user.ap <= 0): return false
	var cls: String = str(def["class"])
	var thrown: bool = cls == "potion" and target.x >= 0
	var result: int = REFUSED
	var verb := ""
	if thrown:
		if not s.on_floor() or not can_throw(s,user,target): return false
		result = throw(s,kind,user,target); verb = "던짐"
	elif cls == "potion":
		result = drink(s,kind,actor); verb = "마심"
	else:
		result = read(s,kind,user); verb = "읽음"
	if result == REFUSED: return false
	s.message("%s · %s %s" % [actor.name if not thrown and cls == "potion" else user.name,label(s,kind),verb])
	s.bag[kind] = int(s.bag[kind])-1
	if s.bag[kind] <= 0: s.bag.erase(kind)
	if result == APPLIED: identify(s,kind)
	spend_action(s,user)
	return true

## Using an item costs the same beat a supply always did: one action on the
## floor, a 100-tick step in manual play, nothing at camp.
static func spend_action(s, user: Dictionary) -> void:
	if not s.on_floor(): return
	user.ap -= 1
	if s.manual_mode:
		user.ap = 1; s.Scheduler.advance(s,100)
	else: s.finish_player_action()

static func drink(s, kind: String, actor: Dictionary) -> int:
	match kind:
		"healing":
			if actor.hp >= actor.max_hp: return REFUSED
			actor.hp = mini(actor.max_hp,actor.hp+20); actor.statuses.erase("bleed"); Body.heal(actor)
		"calm":
			if actor.stress == 0: return REFUSED
			s.stress(actor,-25)
		"strength":
			actor.str_bonus = int(actor.get("str_bonus",0))+3
			actor.max_hp += 5; actor.hp = mini(actor.max_hp,actor.hp+5)
		"haste": s.Statuses.apply(s,actor,"haste",300)
		"experience":
			var level: int = int(actor.get("level",1))
			s.gain_level_xp(actor,maxi(1,level*level*65-int(actor.get("level_xp",0))))
		_: return REFUSED
	return APPLIED

static func can_throw(_s, _user: Dictionary, _target: Vector2i) -> bool:
	return false

static func throw(_s, _kind: String, _user: Dictionary, _target: Vector2i) -> int:
	return REFUSED

static func read(_s, _kind: String, _user: Dictionary) -> int:
	return REFUSED

static func resolve_choice(_s, _option: String) -> bool:
	return false
```

`can_throw`·`throw`·`read`·`resolve_choice`는 다음 태스크들이 채운다(지금은 거부만).

- [ ] **Step 7: 통과 확인**

```bash
godot --headless --path . --script res://tests/consumables.gd
```
Expected: 0 failures. 아울러 기존 스위트가 깨지지 않았는지:

```bash
for suite in run_start mobile_actions model_b_combat; do godot --headless --path . --script "res://tests/${suite}.gd" 2>&1 | tail -1; done
```
Expected: 각각 `0 failures`.

- [ ] **Step 8: 커밋**

```bash
git add expedition/items/consumables.gd expedition/run/session.gd expedition/run/descent.gd expedition/combat/combat_stats.gd tests/consumables.gd
git commit -m "Give the session a potion bag that names a kind on the first sip

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: 광역 물약 — 던지기와 자기 발밑 마시기

**Files:**
- Modify: `expedition/items/consumables.gd` (`can_throw`, `throw`, `drink`의 3종)
- Test: `tests/consumables.gd`

**Interfaces:**
- Consumes: `s.Spells.burst_cells(s, target, radius) -> Array`, `s.Statuses.apply(s, victim, status, ticks)`, `s.at(cell)`, `s.tile(cell)`, `s.floor_state.visible`, `sim/combat_kernel.gd sees(a, b, blocked: Callable)`.
- Produces: `Consumables.splash(s, kind, center) -> void`(3종 광역 효과 공용), `can_throw(s, user, target) -> bool`.

- [ ] **Step 1: 실패하는 테스트 작성**

`run()`에 `throwing()` 추가:

```gdscript
## Flame, frost and gas splash where they land; a thrown healing potion just breaks.
func throwing() -> void:
	var f := solo(43); var s = f.s; var c: Vector2i = f.c; var hero: Dictionary = s.party[0]
	var foe: Dictionary = s.enemies[0]; foe.hp = 20; foe.max_hp = 20; foe.pos = c+Vector2i(3,0); foe.alert = true
	s.tile(c+Vector2i(3,0)).terrain = "wood"; s.tile(c+Vector2i(4,1)).terrain = "wood"
	s.floor_state.observe(s)
	s.grant_item("liquid_flame",3); s.grant_item("frost",1); s.grant_item("toxic_gas",1); s.grant_item("healing",1)
	check(not s.use_item("liquid_flame",c+Vector2i(5,0)) and s.bag.liquid_flame == 3,"range 5 is too far")
	s.tile(c+Vector2i(2,2)).terrain = "wall"
	check(not s.use_item("liquid_flame",c+Vector2i(2,2)),"a wall is no target")
	s.tile(c+Vector2i(2,2)).terrain = "stone"
	check(s.use_item("liquid_flame",c+Vector2i(3,0)) and s.bag.liquid_flame == 2,"a flame in range is thrown")
	check(s.tile(c+Vector2i(3,0)).fire > 0 and s.tile(c+Vector2i(4,1)).fire > 0 and s.tile(c+Vector2i(2,0)).fire == 0,"wood in the splash catches, stone does not")
	check(foe.statuses.has("burn") and not hero.statuses.has("burn"),"the foe burns, the thrower does not")
	check(s.known.has("liquid_flame"),"a visible splash names the bottle")
	hero.ap = 1
	check(s.use_item("frost",c+Vector2i(3,0)) and foe.statuses.has("freeze") and s.tile(c+Vector2i(3,1)).wet >= 70,"frost freezes and wets")
	hero.ap = 1
	check(s.use_item("toxic_gas",c+Vector2i(3,0)) and foe.statuses.has("poison"),"gas poisons")
	hero.ap = 1
	check(s.use_item("healing",c+Vector2i(1,0)) and not s.bag.has("healing") and not s.known.has("healing"),"a thrown healing potion breaks unnamed")
	check(s.log_lines.any(func(l): return l.ends_with("깨졌다")),"the log says it broke")
	hero.ap = 1; s.tile(c).terrain = "wood"
	check(s.use_item("liquid_flame") and hero.statuses.has("burn") and s.tile(c).fire > 0,"drinking liquid flame burns the drinker's own cell")
	s.phase = "CAMP"
	check(not s.use_item("liquid_flame",c+Vector2i(1,0)),"nothing is thrown at camp")
```

- [ ] **Step 2: 실패 확인**

```bash
godot --headless --path . --script res://tests/consumables.gd
```
Expected: "a flame in range is thrown" 등 실패.

- [ ] **Step 3: 구현**

`consumables.gd`에 preload 추가:

```gdscript
const Kernel = preload("res://sim/combat_kernel.gd")
const THROW_RANGE := 4
```

`can_throw`·`throw`를 교체하고 `splash`를 더한다:

```gdscript
## Four cells, in sight, not into a wall — the reach the old fire scroll had.
static func can_throw(s, user: Dictionary, target: Vector2i) -> bool:
	if not s.inside(target) or s.distance(user.pos,target) > THROW_RANGE: return false
	if s.tile(target).terrain == "wall" or not s.floor_state.visible.has(target): return false
	return Kernel.sees(user.pos,target,func(p): return s.tile(p).terrain == "wall")

static func throw(s, kind: String, _user: Dictionary, target: Vector2i) -> int:
	if not bool(definition(kind).get("area",false)):
		s.message(label(s,kind)+"이 깨졌다"); return WASTED
	splash(s,kind,target)
	return APPLIED

## The 3×3 an area potion covers, whether it lands there or is drunk there.
static func splash(s, kind: String, center: Vector2i) -> void:
	for cell in s.Spells.burst_cells(s,center,1):
		var tile: Dictionary = s.tile(cell)
		if tile.terrain == "wall": continue
		if kind == "liquid_flame" and tile.terrain == "wood": tile.fire = mini(100,int(tile.fire)+35)
		if kind == "frost": tile.wet = mini(100,int(tile.wet)+70)
		var victim: Dictionary = s.at(cell)
		if victim.is_empty(): continue
		match kind:
			"liquid_flame": s.Statuses.apply(s,victim,"burn",100)
			"frost": s.Statuses.apply(s,victim,"freeze",100)
			"toxic_gas": s.Statuses.apply(s,victim,"poison",300)
```

`drink`의 `match`에 세 가지를 추가(`_: return REFUSED` 앞):

```gdscript
		"liquid_flame", "frost", "toxic_gas":
			if not s.on_floor(): return REFUSED
			splash(s,kind,actor.pos)
```

`_s`로 이름 붙였던 `throw`의 미사용 인자 경고는 없어야 한다(`_user`만 남긴다).

- [ ] **Step 4: 통과 확인**

```bash
godot --headless --path . --script res://tests/consumables.gd
```
Expected: 0 failures.

- [ ] **Step 5: 커밋**

```bash
git add expedition/items/consumables.gd tests/consumables.gd
git commit -m "Let area potions be thrown or drunk on the spot

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: 두루마리 1 — 감정·강화 선택, 마법 지도, 순간이동, 재충전

**Files:**
- Modify: `expedition/items/consumables.gd` (`read`, `resolve_choice`)
- Test: `tests/consumables.gd`

**Interfaces:**
- Consumes: `s.pending_choice`, `s.floor_state.explored`, `s.floor_state.discoveries`, `s.is_free(cell)`, `Hexaco.sample`.
- Produces: `pending_choice` 형식 `{"kind":"identify"|"upgrade","options":Array[String],"actor":int}`; `resolve_choice(s, option) -> bool`.

- [ ] **Step 1: 실패하는 테스트 작성**

`run()`에 `identify_scroll()`, `upgrade_scroll()`, `mapping_and_teleport()` 추가:

```gdscript
## An unread identify scroll names itself, then asks which bottle to name.
func identify_scroll() -> void:
	var f := solo(45); var s = f.s; var hero: Dictionary = s.party[0]
	s.grant_item("identify",2); s.grant_item("healing",1); s.grant_item("frost",1)
	check(s.use_item("identify") and s.known.has("identify") and s.bag.identify == 1,"reading names the scroll and spends it")
	check(s.pending_choice.get("kind","") == "identify" and s.pending_choice.options.size() == 2 and "identify" not in s.pending_choice.options,"the choice lists the two unknown bottles")
	check(not s.act("WAIT",hero.pos) and not s.use_item("healing"),"nothing else happens while a choice waits")
	check(not s.resolve_choice("identify") and not s.resolve_choice("nonsense"),"only a listed option resolves")
	check(s.resolve_choice("frost") and s.known.has("frost") and s.pending_choice.is_empty(),"the chosen bottle is named")
	hero.ap = 1
	check(s.use_item("identify") and s.pending_choice.get("kind","") == "identify" and s.pending_choice.options == ["healing"],"the second read asks again")
	check(s.resolve_choice("healing"),"and names the last one")
	s.grant_item("identify",1); hero.ap = 1
	check(s.use_item("identify") and s.pending_choice.is_empty() and s.log_lines.any(func(l): return l == "감정할 것이 없다"),"nothing unknown: the scroll is spent with a note")

## Upgrade asks weapon or armour and writes the enchant.
func upgrade_scroll() -> void:
	var f := solo(46); var s = f.s; var hero: Dictionary = s.party[0]
	s.grant_item("upgrade",2,true)
	check(s.use_item("upgrade") and s.pending_choice.get("kind","") == "upgrade" and s.pending_choice.options == ["weapon","armour"] and int(s.pending_choice.actor) == 0,"upgrade offers both worn pieces")
	check(s.resolve_choice("weapon") and int(hero.gear.weapon.enchant) == 1 and int(hero.gear.armour.enchant) == 0,"the weapon gains one")
	hero.gear.armour = {}; hero.ap = 1
	check(s.use_item("upgrade") and s.pending_choice.options == ["weapon"],"a missing piece is not offered")
	check(s.resolve_choice("weapon") and int(hero.gear.weapon.enchant) == 2,"stacks")
	hero.gear.weapon = {}; hero.ap = 1; s.grant_item("upgrade",1,true)
	check(not s.use_item("upgrade") and s.bag.upgrade == 1,"nothing to upgrade: refused, kept")

## Magic mapping bares the floor; teleportation lands far off; recharging fills MP.
func mapping_and_teleport() -> void:
	var s = Session.new_run(47); var hero: Dictionary = s.party[0]
	for enemy in s.enemies: enemy.hp = 0
	s.grant_item("magic_mapping",1); s.grant_item("teleportation",1); s.grant_item("recharging",2,true)
	var floor_cells := 0
	for y in range(s.BOARD_SIDE):
		for x in range(s.BOARD_SIDE):
			if s.tile(Vector2i(x,y)).terrain != "wall": floor_cells += 1
	check(s.floor_state.explored.keys().filter(func(p): return s.tile(p).terrain != "wall").size() < floor_cells,"the floor starts mostly unknown")
	check(s.use_item("magic_mapping") and s.known.has("magic_mapping"),"the map is read")
	var explored_floor: int = s.floor_state.explored.keys().filter(func(p): return s.tile(p).terrain != "wall").size()
	check(explored_floor == floor_cells and s.floor_state.discoveries.size() >= floor_cells,"every floor cell is now explored")
	var from: Vector2i = hero.pos; hero.ap = 1
	check(s.use_item("teleportation") and s.distance(from,hero.pos) >= 12 and s.is_free(from),"teleportation carries the hero at least twelve cells")
	check(s.floor_state.visible.has(hero.pos),"sight follows the hero")
	hero.ap = 1
	check(not s.use_item("recharging") and s.bag.recharging == 2,"full MP refuses recharging")
	hero.mp = 3
	check(s.use_item("recharging") and hero.mp == hero.max_mp and s.bag.recharging == 1,"recharging fills MP")
```

- [ ] **Step 2: 실패 확인**

```bash
godot --headless --path . --script res://tests/consumables.gd
```
Expected: 새 세 함수의 검사 실패.

- [ ] **Step 3: 구현**

`consumables.gd`의 `read`·`resolve_choice`를 교체:

```gdscript
static func read(s, kind: String, user: Dictionary) -> int:
	match kind:
		"identify":
			var options: Array = unknown_kinds(s,kind)
			if options.is_empty(): s.message("감정할 것이 없다")
			else: s.pending_choice = {"kind":"identify","options":options,"actor":s.selected}
		"upgrade":
			var options: Array = ["weapon","armour"].filter(func(slot): return not user.gear.get(slot,{}).is_empty())
			if options.is_empty(): return REFUSED
			s.pending_choice = {"kind":"upgrade","options":options,"actor":s.selected}
		"magic_mapping": reveal_floor(s)
		"teleportation":
			if not s.on_floor(): return REFUSED
			teleport(s,user)
		"recharging":
			if user.mp >= user.max_mp: return REFUSED
			user.mp = user.max_mp
		_: return REFUSED
	return APPLIED

## Every floor cell becomes remembered, with the same discovery record
## `observe` writes, so the minimap and the log see one kind of memory.
static func reveal_floor(s) -> void:
	var state = s.floor_state
	for y in range(s.BOARD_SIDE):
		for x in range(s.BOARD_SIDE):
			var p := Vector2i(x,y)
			if s.tile(p).terrain == "wall" or state.explored.has(p): continue
			state.explored[p] = true
			var feature: Dictionary = state.features.get(p,{})
			if feature.get("kind","") == "curio": state.discovered_curios += 1
			state.discoveries.append({"position":[x,y],"terrain_id":s.tile(p).terrain,"visibility_state":"MEMORY","marker":"EXIT" if feature.get("kind","") == "entry" else "STAIRS" if feature.get("kind","") == "stairs" else ""})

## A far free cell, twelve or more away when the floor has one; the farthest otherwise.
static func teleport(s, user: Dictionary) -> void:
	var far: Array = []; var best: Vector2i = user.pos; var best_distance := 0
	for y in range(s.BOARD_SIDE):
		for x in range(s.BOARD_SIDE):
			var p := Vector2i(x,y)
			if not s.is_free(p): continue
			var d: int = s.distance(user.pos,p)
			if d >= 12: far.append(p)
			if d > best_distance: best = p; best_distance = d
	user.pos = far[Hexaco.sample(s.seed_value,s.time+s.depth*100000,"teleport",far.size())] if not far.is_empty() else best
	user.reservation = {}
	s.floor_state.observe(s)

static func resolve_choice(s, option: String) -> bool:
	var choice: Dictionary = s.pending_choice
	if choice.is_empty() or option not in choice.options: return false
	match str(choice.kind):
		"identify": identify(s,option)
		"upgrade":
			var actor: Dictionary = s.party[int(choice.actor)]
			actor.gear[option].enchant = int(actor.gear[option].get("enchant",0))+1
			s.message("%s · %s 강화 +%d" % [actor.name,"무기" if option == "weapon" else "방어구",int(actor.gear[option].enchant)])
	s.pending_choice = {}
	return true
```

- [ ] **Step 4: 통과 확인**

```bash
godot --headless --path . --script res://tests/consumables.gd
```
Expected: 0 failures.

- [ ] **Step 5: 커밋**

```bash
git add expedition/items/consumables.gd tests/consumables.gd
git commit -m "Add identify, upgrade, mapping, teleport and recharge scrolls

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: 두루마리 2 — 거울상, 자장가, 분노

**Files:**
- Modify: `expedition/items/consumables.gd` (`read`)
- Modify: `data/content/combat.json` (`summons.mirror`)
- Modify: `expedition/actors/monster_ai.gd:70-85` (`turn`), `:55-57` (`on_hit`)
- Test: `tests/consumables.gd`

**Interfaces:**
- Consumes: `s.Spells.summon(s, caster, cell, kind) -> Dictionary`, `s.npcs`, `s.enemies`, `s.DIRECTIONS`, `MonsterAI.turn(s, enemy)`.
- Produces: 몬스터 필드 `sleep_until: int`.

- [ ] **Step 1: 실패하는 테스트 작성**

`run()`에 `mirror_lullaby_rage()` 추가:

```gdscript
## Mirrors fight beside the hero, lullaby stills what the hero sees, rage wakes the floor.
func mirror_lullaby_rage() -> void:
	var f := solo(48); var s = f.s; var c: Vector2i = f.c; var hero: Dictionary = s.party[0]
	s.grant_item("mirror_image",1); s.grant_item("lullaby",1); s.grant_item("rage",1)
	check(s.use_item("mirror_image"),"the mirror scroll is read")
	var mirrors: Array = s.npcs.filter(func(n): return n.get("summon_kind","") == "mirror" and n.hp > 0)
	check(mirrors.size() == 2 and mirrors.all(func(m): return not m.enemy and maxi(absi(m.pos.x-hero.pos.x),absi(m.pos.y-hero.pos.y)) == 1 and m.name == "거울상"),"two friendly mirrors stand beside the hero")
	var near: Dictionary = s.enemies[0]; near.hp = 20; near.max_hp = 20; near.pos = c+Vector2i(3,0); near.alert = true; near.home = near.pos
	var far: Dictionary = s.enemies[1]; far.hp = 20; far.max_hp = 20; far.pos = c+Vector2i(0,7); far.alert = false; far.home = far.pos
	s.tile(c+Vector2i(0,6)).terrain = "wall"
	s.floor_state.observe(s); hero.ap = 1
	check(s.floor_state.visible.has(near.pos) and not s.floor_state.visible.has(far.pos),"one foe in sight, one behind a wall")
	check(s.use_item("lullaby") and int(near.get("sleep_until",0)) > s.time and not near.alert,"the seen foe sleeps")
	check(int(far.get("sleep_until",0)) == 0,"the unseen foe does not")
	var before: Vector2i = near.pos
	Floor.MonsterAI.turn(s,near)
	check(near.pos == before and not near.alert,"a sleeping foe skips its turn even with the hero in view")
	s.damage(near,3,hero.id,"SLASH")
	check(int(near.get("sleep_until",0)) == 0,"a hit wakes it")
	hero.ap = 1
	check(s.use_item("rage") and s.enemies.filter(func(e): return e.hp > 0).all(func(e): return e.alert and e.statuses.has("haste")),"rage wakes and hastens every living foe")
```

- [ ] **Step 2: 실패 확인**

```bash
godot --headless --path . --script res://tests/consumables.gd
```
Expected: "the mirror scroll is read" 등 실패.

- [ ] **Step 3: 소환 행**

`data/content/combat.json`의 `"summons"` 객체에 `"mirror": {"name": "거울상", "hp": 12, "power": 6, "speed": 100, "duration": 300}` 추가(파일은 python이나 편집기로 JSON 형식을 지키며 넣는다; 키 순서는 무관).

- [ ] **Step 4: 몬스터 잠**

`expedition/actors/monster_ai.gd` `turn`에서 `if s.status_blocks(enemy,"ATTACK"): return` 바로 뒤에:

```gdscript
	# A lullaby holds the monster where it stands; it neither looks nor walks
	# until the clock runs out or something hits it (`on_hit`).
	if s.time < int(enemy.get("sleep_until",0)): return
```

`on_hit`의 첫 줄(`if enemy.get("boss",false): return` 앞)에 `enemy.sleep_until = 0`.

- [ ] **Step 5: 읽기 효과**

`consumables.gd` `read`의 `match`에 추가(`_: return REFUSED` 앞):

```gdscript
		"mirror_image":
			if not s.on_floor(): return REFUSED
			var placed := 0
			for d in s.DIRECTIONS:
				if placed >= 2: break
				var cell: Vector2i = user.pos+d
				if not s.is_free(cell): continue
				s.Spells.summon(s,user,cell,"mirror"); placed += 1
			if placed == 0: return REFUSED
		"lullaby":
			if not s.on_floor(): return REFUSED
			for enemy in s.enemies:
				if enemy.hp <= 0 or not s.floor_state.visible.has(enemy.pos): continue
				enemy.sleep_until = s.time+300; enemy.alert = false
		"rage":
			if not s.on_floor(): return REFUSED
			for enemy in s.enemies:
				if enemy.hp <= 0: continue
				enemy.alert = true; enemy.sleep_until = 0; s.Statuses.apply(s,enemy,"haste",200)
```

- [ ] **Step 6: 통과 확인**

```bash
godot --headless --path . --script res://tests/consumables.gd
for suite in enemy_turns monster_roles continuous_floor; do godot --headless --path . --script "res://tests/${suite}.gd" 2>&1 | tail -1; done
```
Expected: 모두 0 failures.

- [ ] **Step 7: 커밋**

```bash
git add expedition/items/consumables.gd data/content/combat.json expedition/actors/monster_ai.gd tests/consumables.gd
git commit -m "Add mirror image, lullaby and rage scrolls

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: 바닥 드롭 — 생성기 배치, 줍기, 조사물, 지도 아이콘

**Files:**
- Modify: `data/content/floor_themes.json` (두 테마에 `items`)
- Modify: `expedition/level/floor_generator.gd:480-515` (`place_features`)
- Modify: `expedition/run/session.gd:~552` (`act_as`의 `MOVE`)
- Modify: `expedition/items/curios.gd:39-44`
- Modify: `expedition/art/map_icons.gd` (`paint`)
- Modify: `expedition/ui/board.gd:334-341`
- Modify: `expedition/items/consumables.gd` (`pickup`)
- Test: `tests/consumables.gd`, `tests/floor_generator.gd`

**Interfaces:**
- Consumes: `Generator.generate(theme, seed, depth)`, `Floor.theme_for(depth)`, `free_cell` 클로저(생성기 안), `Consumables.random_kind_rng`.
- Produces: feature `{"kind":"item","item_id":String,"label":String,"used":false}`; `Consumables.pickup(s, actor)`.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/consumables.gd` `run()`에 `floor_drops()` 추가:

```gdscript
## Four to six bottles and scrolls lie in the branch rooms; walking onto one takes it.
func floor_drops() -> void:
	for seed in range(20):
		var theme: Dictionary = Floor.theme_for(1)
		var layout: Dictionary = Generator.generate(theme,seed*7919+101,1)
		var items: Array = layout.features.keys().filter(func(p): return layout.features[p].kind == "item")
		check(items.size() >= 4 and items.size() <= 6,"seed %d lays four to six items (%d)" % [seed,items.size()])
		for p in items:
			var f: Dictionary = layout.features[p]
			check(Consumables.definition(str(f.item_id)).size() > 0 and str(f.label) == str(Consumables.definition(str(f.item_id)).name),"item feature carries a kind and its name")
			var owner: Array = layout.rooms.filter(func(r): return r.rect.has_point(p))
			check(owner.size() == 1 and owner[0].kind == "plain" and not owner[0].spine,"items sit in branch plain rooms (seed %d)" % seed)
			check(owner[0].doors.all(func(d): return maxi(absi(p.x-d.x),absi(p.y-d.y)) > 1),"items keep off doorways")
	var f := solo(49); var s = f.s; var c: Vector2i = f.c; var hero: Dictionary = s.party[0]
	var cell: Vector2i = c+Vector2i.RIGHT
	s.floor_state.features[cell] = {"kind":"item","item_id":"haste","label":"가속 물약","used":false}
	s.floor_state.observe(s)
	check(s.act("MOVE",cell),"the hero steps onto the bottle")
	check(hero.pos == cell and s.bag.get("haste",0) == 1 and not s.floor_state.features.has(cell),"the bottle is picked up and the cell cleared")
	check(s.log_lines.any(func(l): return l == s.appearances.haste+" 획득"),"the log names the look")
	var wanderer: Dictionary = s.enemies[0]; wanderer.hp = 10; wanderer.pos = c+Vector2i(3,3)
	s.floor_state.features[c+Vector2i(3,4)] = {"kind":"item","item_id":"calm","label":"정신 안정제","used":false}
	wanderer.pos = c+Vector2i(3,4)
	check(s.floor_state.features.has(c+Vector2i(3,4)) and not s.bag.has("calm"),"a monster standing on an item does not take it")
```

`tests/floor_generator.gd`의 kinds 집계 뒤(`check(kinds.get("camp",0) == 1,...)` 다음 줄)에:

```gdscript
		check(kinds.get("item",0) >= theme.items[0] and kinds.get("item",0) <= theme.items[1],"item count in theme range (%d)" % kinds.get("item",0))
```

- [ ] **Step 2: 실패 확인**

```bash
godot --headless --path . --script res://tests/consumables.gd
godot --headless --path . --script res://tests/floor_generator.gd 2>&1 | tail -3
```
Expected: item 개수 0으로 실패.

- [ ] **Step 3: 테마와 생성기**

`data/content/floor_themes.json`의 `F1_RUINS`·`F2_MINES` 각각 `"curios"` 객체 옆에 `"items": [4, 6]` 추가.

`expedition/level/floor_generator.gd` 상단 preload에 `const Consumables = preload("res://expedition/items/consumables.gd")` 추가. `place_features`에서 조사물 `for id in [...]` 루프가 끝난 뒤, `layout.features = features` 앞에:

```gdscript
	# Bottles and scrolls lie loose in the branch rooms, off the doorways, the
	# same rooms the curios use so a fight room never hides one under a pack.
	var item_range: Array = theme.get("items",[0,0])
	var item_target: int = rng.randi_range(int(item_range[0]),int(item_range[1]))
	var placed := 0; var item_guard := 0
	while placed < item_target and not branch_plain.is_empty() and item_guard < 40:
		item_guard += 1
		var cell: Vector2i = free_cell.call(branch_plain[rng.randi_range(0,branch_plain.size()-1)],false)
		if cell.x < 0: continue
		var kind: String = Consumables.random_kind_rng(rng)
		features[cell] = {"kind":"item","item_id":kind,"label":str(Consumables.definition(kind).name),"used":false}
		placed += 1
```

- [ ] **Step 4: 줍기**

`consumables.gd`에:

```gdscript
## The item lying where a party member just stepped goes into the bag.
static func pickup(s, actor: Dictionary) -> void:
	var feature: Dictionary = s.floor_state.features.get(actor.pos,{})
	if feature.get("kind","") != "item": return
	s.floor_state.features.erase(actor.pos)
	grant(s,str(feature.get("item_id","")))
```

`session.gd` `act_as`의 `"MOVE"` 분기, `actor.hit_and_run = false` 다음 줄에 `if actor in party: Consumables.pickup(self,actor)`.

- [ ] **Step 5: 조사물**

`expedition/items/curios.gd` `resolve`에서 두 곳의
`s.grant_supply(s.Hexaco.sample(s.seed_value,key,"curio_supply",s.supplies.size()))`
를 `s.grant_item(s.Consumables.random_kind(s.seed_value,key))`로 바꾼다.

- [ ] **Step 6: 지도 아이콘**

`expedition/art/map_icons.gd` `paint`의 `match`에 `"loot"` 앞에:

```gdscript
		"potion":
			canvas.draw_rect(Rect2(center+Vector2(-radius*0.25,-radius),Vector2(radius*0.5,radius*0.55)),color)
			canvas.draw_circle(center+Vector2(0,radius*0.3),radius*0.7,Color("6d2f8f"))
			canvas.draw_arc(center+Vector2(0,radius*0.3),radius*0.7,0,TAU,16,color,2)
		"scroll":
			var sheet := Rect2(center-Vector2(radius*0.6,radius*0.8),Vector2(radius*1.2,radius*1.6))
			canvas.draw_rect(sheet,Color("e8dcb5"))
			canvas.draw_rect(sheet,color,false,2)
			canvas.draw_line(center+Vector2(-radius*0.3,-radius*0.3),center+Vector2(radius*0.3,-radius*0.3),color,1)
			canvas.draw_line(center+Vector2(-radius*0.3,radius*0.1),center+Vector2(radius*0.3,radius*0.1),color,1)
```

`expedition/ui/board.gd` 336행 `var icon: String = session.Curios.definition(feature).get("icon",feature.kind)` 다음 줄에:

```gdscript
				if feature.kind == "item": icon = "potion" if str(session.Consumables.definition(str(feature.get("item_id",""))).get("class","")) == "potion" else "scroll"
```

- [ ] **Step 7: 통과 확인**

```bash
godot --headless --path . --script res://tests/consumables.gd
for suite in floor_generator curios integration solo_floor mobile_exploration; do godot --headless --path . --script "res://tests/${suite}.gd" 2>&1 | tail -1; done
```
Expected: 모두 0 failures. `integration`·`solo_floor`는 100시드 층 검증이라 몇 분 걸릴 수 있다.

- [ ] **Step 8: 커밋**

```bash
git add data/content/floor_themes.json expedition/level/floor_generator.gd expedition/run/session.gd expedition/items/curios.gd expedition/art/map_icons.gd expedition/ui/board.gd expedition/items/consumables.gd tests/consumables.gd tests/floor_generator.gd
git commit -m "Lay unidentified potions and scrolls on the floor

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: UI — 가방 행·상세창·던지기·선택 팝업, 소모품 바 제거

**Files:**
- Modify: `expedition/ui/screens/popups.gd:283-372` (`inventory_rows`, `show_item_detail`, 새 `show_choice`)
- Modify: `expedition/ui/screens/floor_hud.gd:84-87` (바 삭제), `:258-264` (`choose_item`)
- Modify: `expedition/ui/main.gd:43` (`pending_item`), `:223`, `:365`, `:413`, `:452`, `refresh()` 끝
- Test: `tests/abilities_growth.gd:74-98`, `tests/consumables.gd`

**Interfaces:**
- Consumes: Task 2·4의 세션 API.
- Produces: 가방 행 id `"item:<kind>"`, 필드 `kind`, `class`, `known`, `area`; `ui.choose_item(kind: String)`; `Popups.show_choice(ui)`; `ui.pending_item: String`.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/abilities_growth.gd` 74~98행을 아래로 바꾼다(다른 줄은 그대로):

```gdscript
	scene.inventory_filter = "전체"; scene.show_supplies()
	s.grant_item("healing",1,true); s.grant_item("frost",1); scene.show_supplies()
	for frame in range(3): await process_frame
	check(scene.inventory_slots.size() >= 12,"inventory displays grid slots")
	for slot in scene.inventory_slots:
		check(slot.size.x >= 44 and slot.size.y >= 44,"inventory touch targets")
	check(scene.inventory_slots.any(func(slot): return slot.row.get("id","") == "item:frost" and str(slot.row.label).ends_with(" · 미감정")),"an unknown bottle says so in the bag")
	scene.show_item_detail("item:healing")
	await process_frame
	check(scene.item_popup.visible and scene.item_popup.size.x <= root.size.x,"item detail popup fits")
	check(scene.item_popup.get_parent() == scene.details_popup and scene.item_popup.transient and scene.item_popup.exclusive,"item details belong above inventory modal")
	var detail_buttons: Array = scene.item_detail.find_children("*","Button",true,false).map(func(b): return str(b.text))
	check(detail_buttons.any(func(t): return t.ends_with(" 마신다")) and not detail_buttons.any(func(t): return t.begins_with("던진다")),"a known plain potion offers drinking only")
	scene.show_item_detail("item:frost"); await process_frame
	detail_buttons = scene.item_detail.find_children("*","Button",true,false).map(func(b): return str(b.text))
	check(detail_buttons.any(func(t): return t.begins_with("던진다")),"an unknown potion may be thrown")
	scene.item_popup.hide(); scene.inventory_filter = "파츠"; scene.show_supplies()
	check(scene.inventory_slots.all(func(slot): return slot.row.is_empty() or slot.row.category == "파츠"),"category filter contains only parts")
	for viewport in [Vector2i(360,800),Vector2i(390,844),Vector2i(430,844)]:
		root.size = viewport; scene.show_supplies()
		for frame in range(3): await process_frame
		check(scene.details_popup.size.x <= root.size.x and scene.details_popup.size.y <= root.size.y,"inventory fits mobile viewport")
	var supply_test = arena()
	supply_test.grant_item("healing",2,true)
	supply_test.party[1].hp = 20; supply_test.enemies[0].recovery = 30
	var turn: int = supply_test.round_number
	check(supply_test.use_item("healing",Vector2i(-1,-1),1),"shared potion can target companion")
	check(supply_test.party[1].hp == 40 and supply_test.selected == 0 and supply_test.round_number == turn+1 and supply_test.bag.healing == 1,"recipient healing keeps leader and consumes one turn and item")
	supply_test.party[1].hp = supply_test.party[1].max_hp
	check(not supply_test.use_item("healing",Vector2i(-1,-1),1) and supply_test.bag.healing == 1,"invalid recipient effect does not consume")
	check(not supply_test.use_item("healing",Vector2i(-1,-1),99),"invalid recipient rejected")
```

`tests/consumables.gd`에 선택 팝업 UI 검사 `choice_popup()`을 추가하고 `run()`에서 다른 함수들 뒤에 `await choice_popup()`으로 부른다(`run()`을 `func run() -> void:`로 두고 안에서 `await`하면 된다):

```gdscript
## Reading an identify scroll in the HUD raises the choice popup; picking closes it.
func choice_popup() -> void:
	var scene = load("res://expedition/ui/main.tscn").instantiate(); root.add_child(scene); await process_frame
	var s = Session.new_run(50); scene.session = s
	for enemy in s.enemies: enemy.hp = 0
	s.grant_item("identify",1,true); s.grant_item("healing",1)
	scene.refresh(); await process_frame
	check(scene.pending_item == "","no throw pending at start")
	scene.run_action(func(): return s.use_item("identify")); await process_frame
	check(not s.pending_choice.is_empty() and scene.details_popup.visible,"the choice popup opens")
	var buttons: Array = scene.modal_content.find_children("*","Button",true,false)
	var pick: Array = buttons.filter(func(b): return str(b.text) == s.appearances.healing)
	check(pick.size() == 1,"the popup lists the unknown bottle by its look")
	if not pick.is_empty(): pick[0].pressed.emit(); await process_frame
	check(s.pending_choice.is_empty() and s.known.has("healing"),"picking names it and clears the choice")
	scene.choose_item("healing"); await process_frame
	check(scene.pending_item == "healing" and scene.notice.begins_with("치유 물약"),"choosing a potion arms a throw with its name")
	scene.queue_free(); await process_frame
```

- [ ] **Step 2: 실패 확인**

```bash
godot --headless --path . --script res://tests/abilities_growth.gd 2>&1 | tail -3
godot --headless --path . --script res://tests/consumables.gd 2>&1 | tail -3
```
Expected: 실패(`item:healing` 행 없음, `pending_item` 타입 등).

- [ ] **Step 3: main.gd**

- 43행 `var pending_item := -1` → `var pending_item := ""`.
- 223행과 365행의 `pending_item = -1` → `pending_item = ""`.
- 413행 `if pending_item >= 0: run_action(func(): return session.use_supply(pending_item,point)); return` → `if not pending_item.is_empty(): run_action(func(): return session.use_item(pending_item,point)); return`.
- 452행 `func choose_item(slot: int) -> void: FloorHud.choose_item(self,slot)` → `func choose_item(kind: String) -> void: FloorHud.choose_item(self,kind)`.
- `refresh()` 끝의 두 줄을 이렇게 바꾼다:

```gdscript
	if session.phase == "CAMP": CampScreen.build_camp_screen(self); show_choice_if_pending(); return
	if session.phase == "DEFEAT": ResultCard.build_result_card(self); return
	FloorHud.build(self,elapsed,impact_elapsed)
	show_choice_if_pending()

## A scroll waiting on an answer keeps its popup up until one is given.
func show_choice_if_pending() -> void:
	if session != null and not session.pending_choice.is_empty(): Popups.show_choice(self)
```

- [ ] **Step 4: floor_hud.gd**

84~87행(`var shared := HBoxContainer.new()`부터 `ui.item_buttons.append(item)`까지 네 줄) 삭제.

`choose_item`을 교체:

```gdscript
static func choose_item(ui, kind: String) -> void:
	ui.stop_navigation()
	ui.reservation_actor = -1
	ui.pending_attack = {}
	ui.mode = ""; ui.pending_item = kind
	ui.notice = ui.session.item_label(kind)+" · 대상 칸 선택"; ui.refresh()
```

- [ ] **Step 5: popups.gd**

`inventory_rows`의 `descriptions` 줄과 `for i in range(5):` 두 줄을 아래로:

```gdscript
	for kind in Session.Consumables.kinds():
		var count: int = int(session.bag.get(kind,0))
		if count <= 0: continue
		var def: Dictionary = Session.Consumables.definition(kind)
		var is_known: bool = session.known.has(kind)
		rows.append({"id":"item:"+kind,"label":session.item_label(kind)+("" if is_known else " · 미감정"),"quantity":count,"category":"소모품","kind":kind,"class":str(def["class"]),"known":is_known,"area":bool(def.get("area",false)),"description":Session.Consumables.description(session,kind),"icon":Art.ui_icon(6 if str(def["class"]) == "potion" else 9)})
```

`show_item_detail`의 `if row.category == "소모품":` 블록을:

```gdscript
	if row.category == "소모품":
		var usable: bool = session.phase in ["EXPLORE","BATTLE","CAMP"]
		if row["class"] == "potion":
			for i in range(session.party.size()):
				ui.button(ui.item_detail,session.party[i].name+" 마신다",func(): ui.item_popup.hide(); ui.details_popup.hide(); ui.run_action(func(): return session.use_item(row.kind,Vector2i(-1,-1),i)),usable and session.party[i].hp > 0)
			if row.area or not row.known:
				ui.button(ui.item_detail,"던진다 · 바닥 선택",func(): ui.item_popup.hide(); ui.details_popup.hide(); ui.choose_item(row.kind),session.on_floor())
		else:
			ui.button(ui.item_detail,"읽는다",func(): ui.item_popup.hide(); ui.details_popup.hide(); ui.run_action(func(): return session.use_item(row.kind)),usable)
```

파일 끝에 선택 팝업:

```gdscript
## The question a scroll left open: which bottle to name, or which piece to
## sharpen. No close button — the scroll is already spent.
static func show_choice(ui) -> void:
	var session = ui.session
	var choice: Dictionary = session.pending_choice
	if choice.is_empty(): return
	ui.stop_navigation(); ui.clear(ui.modal_content)
	ui.label(ui.modal_content,"감정할 것을 고르시오" if choice.kind == "identify" else "강화할 장비를 고르시오",18)
	for option in choice.options:
		var caption: String = session.item_label(option) if choice.kind == "identify" else gear_name(ui,session.party[int(choice.actor)].gear[option],option)
		ui.button(ui.modal_content,caption,func(): pick_choice(ui,option))
	ui.details_popup.popup_centered()

static func pick_choice(ui, option: String) -> void:
	if ui.session.resolve_choice(option): ui.details_popup.hide(); ui.refresh()
```

- [ ] **Step 6: 통과 확인**

```bash
for suite in abilities_growth consumables mobile_hud autobattle model_b_spells parts ui_smoke character_ui; do godot --headless --path . --script "res://tests/${suite}.gd" 2>&1 | tail -1; done
```
Expected: 모두 0 failures. `autobattle`은 아직 `s.supplies[0] = 1`을 쓰므로 여기서는 통과해야 한다(배열은 Task 8까지 남는다).

- [ ] **Step 7: 커밋**

```bash
git add expedition/ui/main.gd expedition/ui/screens/floor_hud.gd expedition/ui/screens/popups.gd tests/abilities_growth.gd tests/consumables.gd
git commit -m "Show potions and scrolls in the bag with drink, throw, read and choice popups

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: 옛 `supplies` 제거 — 세션·gear·시뮬·테스트

**Files:**
- Modify: `expedition/run/session.gd:104,107,300,822`
- Modify: `expedition/items/gear.gd:95-126` (`grant_supply`, `use_supply` 삭제)
- Modify: `expedition/sim/encounter_runner.gd:66-67`, `expedition/sim/bot_policy.gd:10`
- Modify: `tests/mobile_actions.gd:11-22,32-33`, `tests/run_start.gd:15`, `tests/solo_floor.gd:152-162`, `tests/curios.gd:63-80`, `tests/arena_mode.gd:34`, `tests/autobattle.gd:330`

**Interfaces:**
- Consumes: Task 2·3의 `grant_item`, `use_item`, `bag`.
- Produces: `supplies`·`SUPPLY_NAMES`·`grant_supply`·`use_supply`가 어디에도 없다.

- [ ] **Step 1: 테스트를 새 API로 바꾼다**

`tests/mobile_actions.gd` 11~22행:

```gdscript
	s.grant_item("healing",2,true)
	check(not s.use_item("healing") and s.bag.healing == 2,"full HP potion stays in bag")
	s.party[0].hp = 30
	check(s.use_item("healing") and s.party[0].hp == 50 and s.bag.healing == 1,"healing potion")
	s.selected = 1; s.party[1].hp = 30
	check(s.use_item("healing") and not s.bag.has("healing"),"shared potion stack")
	check(not s.use_item("healing"),"empty stack")
	s.selected = 0; s.party[0].ap = 2
	var before: int = s.party[0].ap
	s.grant_item("liquid_flame",1,true)
	check(not s.use_item("liquid_flame",c+Vector2i(7,7)) and s.bag.liquid_flame == 1 and s.party[0].ap == before,"out-of-range throw does not consume")
	s.tile(c+Vector2i(0,3)).terrain = "wood"
	check(s.use_item("liquid_flame",c+Vector2i(0,3)) and not s.bag.has("liquid_flame") and s.tile(c+Vector2i(0,3)).fire > 0,"thrown flame burns wood")
```

32~33행:

```gdscript
	s.phase = "CAMP"; s.grant_item("calm",1,true); s.party[0].stress = 40
	check(s.use_item("calm") and s.party[0].stress == 15,"calming potion at camp")
```

`tests/run_start.gd` 15행:

```gdscript
	check(s.bag.is_empty() and s.known.is_empty() and s.appearances.size() == 16,"an empty bag, nothing named, every kind dressed")
```

`tests/solo_floor.gd` `persistence`:

```gdscript
	s.grant_part("BOMB"); s.grant_item("healing"); s.grant_item("identify",1,true)
	actor.stress = 44
	var parts: Dictionary = s.parts_bag.duplicate(true)
	var bag: Dictionary = s.bag.duplicate(); var known: Dictionary = s.known.duplicate(); var looks: Dictionary = s.appearances.duplicate()
```
와 `check(s.supplies == supplies,"the supplies follow")` → `check(s.bag == bag and s.known == known and s.appearances == looks,"the bag, what it knows and how it looks follow")`.

`tests/curios.gd`: 파일 상단 `check` 아래에 헬퍼를 두고,

```gdscript
func bag_total(s) -> int:
	return s.bag.values().reduce(func(a,b): return a+b,0)
```
`dead_adventurer`의 `s.supplies.reduce(func(a,b): return a+b,0)` 두 곳 → `bag_total(s)`; `broken_chest`의 두 곳도 같게.

`tests/arena_mode.gd` 34행: `c.enemies.size() == 2 and c.supplies.size() == 5 and c.party.size() == 1` → `c.enemies.size() == 2 and c.party.size() == 1`.

`tests/autobattle.gd` 330행: `s.supplies[0] = 1; scene.check_stop(); scene.refresh()` → `s.grant_item("healing",1,true); scene.check_stop(); scene.refresh()`.

- [ ] **Step 2: 바뀐 스위트가 아직 통과하는지 확인**

```bash
for suite in run_start mobile_actions solo_floor curios arena_mode autobattle; do godot --headless --path . --script "res://tests/${suite}.gd" 2>&1 | tail -1; done
```
Expected: 전부 0 failures — 새 API는 이미 있고 옛 배열은 아직 남아 있으므로 여기서 실패하면 Step 1의 오타다.

- [ ] **Step 3: 세션·gear·시뮬에서 제거**

`session.gd`: `var supplies: Array = [0,0,0,0,0]`, `const SUPPLY_NAMES = [...]`, `func grant_supply(...)`, `func use_supply(...)` 네 줄 삭제.

`gear.gd`: `static func grant_supply` ~ `use_supply` 끝(`return true`)까지 삭제. `Scheduler` preload는 다른 곳에서 쓰지 않으면 함께 지운다(`grep -n Scheduler expedition/items/gear.gd`로 확인).

`encounter_runner.gd` 66~67행:

```gdscript
	# The experiment's five-slot supply row survives in the JSON: slot 0 is
	# healing, slot 1 calm, the retired slots are ignored. The arena knows its bottles.
	var row: Array = config.get("supplies",[])
	if row.size() > 0 and int(row[0]) > 0: s.grant_item("healing",int(row[0]),true)
	if row.size() > 1 and int(row[1]) > 0: s.grant_item("calm",int(row[1]),true)
```

`bot_policy.gd` 10행: `if hero.hp < 14 and s.supplies[0] > 0 and s.use_supply(0): return "HEAL"` → `if hero.hp < 14 and int(s.bag.get("healing",0)) > 0 and s.use_item("healing"): return "HEAL"`.

- [ ] **Step 4: 남은 참조 검사**

```bash
grep -rn "supplies\[\|SUPPLY_NAMES\|grant_supply\|use_supply\|\.supplies\b" --include=*.gd expedition tests sim | grep -v "config.supplies\|ex.supplies\|\"supplies\":"
```
Expected: 출력 없음(실험 config의 `supplies` 키만 남는다).

- [ ] **Step 5: 통과 확인**

```bash
for suite in run_start mobile_actions solo_floor curios arena_mode autobattle encounter_sim expedition_skills action_economy consumables abilities_growth integration playthrough camping floor_descent boss_floor; do godot --headless --path . --script "res://tests/${suite}.gd" 2>&1 | tail -1; done
```
Expected: 전부 0 failures.

- [ ] **Step 6: 커밋**

```bash
git add expedition/run/session.gd expedition/items/gear.gd expedition/sim/encounter_runner.gd expedition/sim/bot_policy.gd tests/mobile_actions.gd tests/run_start.gd tests/solo_floor.gd tests/curios.gd tests/arena_mode.gd tests/autobattle.gd
git commit -m "Retire the five-slot supply array

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: CI 등록과 문서

**Files:**
- Modify: `.github/workflows/deploy-pages.yml:38`
- Modify: `README.md`(소모품 문장), `docs/systems-overview.ko.md:12,53`, `docs/inventory-ui.md`
- Modify: `docs/superpowers/specs/2026-09-24-consumables-identification-design.md:3` (상태)

- [ ] **Step 1: CI**

38행의 스위트 목록 끝 `spellbooks` 뒤에 ` consumables` 추가.

- [ ] **Step 2: README**

"소모품은 치유 물약, 정신 안정제, 활력 물약, 화염 두루마리, 물 두루마리의 5종입니다." 문장을:

> 물약 8종과 두루마리 8종이 미감정 상태로 방 바닥과 조사물에서 나옵니다. 외관(색·제목)은 Run마다 섞이며, 마시거나 읽으면 그 종류가 감정되고 감정 두루마리로 하나를 골라 감정할 수도 있습니다. 액체 화염·냉기·독가스는 던질 수 있고, 독가스·분노처럼 해로운 것도 섞여 있습니다.

- [ ] **Step 3: 시스템 개요**

12행 파일 목록의 `items/gear.gd` 옆에 `items/consumables.gd`를 더하고, 53행을:

> - **소모품** `expedition/items/consumables.gd` + `data/content/consumables.json`: 물약 8(치유·힘·가속·액체 화염·냉기·독가스·경험·정신 안정제)·두루마리 8(감정·강화·마법 지도·순간이동·거울상·자장가·분노·재충전). Run마다 외관 셔플, 사용 또는 감정 두루마리로 감정. 층당 4~6개 바닥 드롭 + 조사물. 세션 `bag`·`known`·`appearances`·`pending_choice`.

- [ ] **Step 4: inventory-ui.md**

목록의 "소모품은 주인공 또는 동료에게 사용 가능…" 항목과 "두루마리는 상세창을 닫고…" 항목을:

> - 소모품 행은 세션 `bag`에서 만든다. 미감정이면 외관 라벨에 " · 미감정"이 붙고 설명은 정체를 모른다고만 말한다. 물약은 대원별 "마신다", 광역 물약이거나 미감정 물약이면 "던진다 · 바닥 선택"(층 위에서만), 두루마리는 "읽는다".
> - 던지기는 상세창을 닫고 전장의 칸 선택으로 이어진다(사거리 4, 시선 필요).
> - 감정·강화 두루마리는 읽는 즉시 소비되고 선택 팝업이 뜬다. 닫기 버튼이 없고 고르면 닫힌다.
> - 오토배틀 HUD의 5칸 소모품 바는 없어졌다. 가방 버튼이 유일한 입구다.

- [ ] **Step 5: 스펙 상태**

스펙 3행의 `상태: 승인됨, 구현 전 · 구현 계획: (writing-plans로 작성)` → `상태: 구현됨 · 구현 계획: [consumables 계획](../plans/2026-09-24-consumables-identification.md)`.

- [ ] **Step 6: 마지막 전체 확인**

```bash
godot --headless --path . --editor --import --quit
for suite in layout_guard start_kit run_start camping floor_descent boss_floor integration playthrough ui_smoke mobile_actions enemy_turns companion_tactics abilities_growth character_ui continuous_floor mobile_exploration curios monster_roles solo_floor solo_balance mobile_hud floor_templates encounter_builder floor_generator encounter_sim skill_archetypes skill_rule_conditions test_loadout protect parts autobattle battle_presentation companion_intent_ui stances arena_mode utility npc_roster npc_sense npc_behaviour recruit model_b_combat model_b_scheduler model_b_mastery model_b_mastery_ui model_b_parts_ui model_b_spells model_b_runner spellbooks consumables; do
  godot --headless --path . --script "res://tests/${suite}.gd" 2>&1 | tee "/tmp/${suite}.log" | tail -1
  grep -E 'SCRIPT ERROR:|^ERROR:' "/tmp/${suite}.log" && echo "!! ${suite} has script errors"
done
```
Expected: 모든 줄이 `0 failures`, `!!` 줄 없음. (이 계획과 무관한 기존 미커밋 변경이 만든 실패가 있으면 그 사실을 보고하고 고치지 않는다.)

- [ ] **Step 7: 커밋**

```bash
git add .github/workflows/deploy-pages.yml README.md docs/systems-overview.ko.md docs/inventory-ui.md docs/superpowers/specs/2026-09-24-consumables-identification-design.md
git commit -m "Document potions, scrolls and identification

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```
