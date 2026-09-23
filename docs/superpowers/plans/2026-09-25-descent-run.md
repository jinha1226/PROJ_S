# 하강 Run · 야영 · 보스 층 Implementation Plan (Plan A)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 마을·귀환·횃불·빛·방 모드를 걷어내고, 1층에서 혼자 시작해 계단으로 내려가며 식량으로 야영하는 단일 하강 Run을 만든다. 3층마다 보스가 계단을 지킨다. NPC(Plan B)는 이 위에 얹는다.

**Architecture:** `Session`은 연속 층 전용이 된다(`floor_mode` 분기 삭제). 새 진입점 `depart()`가 Run 시작(1층 생성)이고, `descend()`가 다음 층을 만든다. 야영은 `CAMP` 단계로 세션에 들어가고, 파츠 장착 조건이 TOWN → CAMP로 바뀐다. 보스 패턴은 `boss_ai.gd`로 옮겨 층 몬스터와 같은 `intents` 형식을 쓴다. UI는 시작 화면·야영 화면·결과 화면 세 장만 새로 그리고 HUD는 식량·야영 버튼만 바뀐다.

**Tech Stack:** Godot 4.6 GDScript, headless tests (`godot --headless --path . --script res://tests/<name>.gd`), import check (`godot --headless --path . --editor --import --quit`), CI list in `.github/workflows/deploy-pages.yml`.

**Spec:** `docs/superpowers/specs/2026-09-25-run-camp-npc-design.md` §0–§4, §6–§8 (NPC §5는 Plan B).

## Global Constraints

- Godot 창을 절대 띄우지 않는다. 헤드리스만.
- 전투 AI(`stances.gd`, `utility.gd`, `lookahead.gd`, `tactical_action_selector.gd`, `parts_candidates.gd`, `tactic_rules.gd`, `tactics_profiles.json`)는 손대지 않는다. 어둠 보정(`Floor.enemy_bonus`) 호출만 지운다.
- `Session.new(seed, p_boss_trial, p_companions, p_floor, p_party_size)` 시그니처와 `depart()`는 유지한다(테스트 픽스처 호환). 2·4번째 인자는 무시된다.
- 계약 테스트는 지우지 않는다: 삭제 대상 스위트(`boss_trial`, `terrain_layouts`, `torch_vision`, `torch_tradeoff`, `solo_provisioning`, `expedition_settlement`, `solo_recovery`) 외에는 검사 수를 줄이지 않는다. 지운 기능(횃불·빛·자금·유물·마을)을 검사하던 개별 check만 삭제하고, 그 파일에 새 흐름 검사를 같은 수 이상 추가한다.
- 커밋은 `jinha1226 <jinha1226@gmail.com>`, 트레일러 `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- `docs/superpowers/specs/2026-09-25-run-camp-npc-design.md`가 규범이다. 계획과 어긋나면 스펙을 따른다.

## 파일 구조

| 파일 | 책임 | 변화 |
| --- | --- | --- |
| `expedition/session.gd` | Run 상태·전투·야영·하강 | 방 모드/마을/횃불/자금 삭제, `depart`→Run 시작, `descend`, `camp`, `score` |
| `expedition/continuous_floor.gd` | 층 적용·시야·조사물 상호작용 | 빛 삭제(시야 고정 5), 계단·보스 처리, `depth` 시드 |
| `expedition/floor_generator.gd` | 층 생성 | 복도 폭 2, `npc_rooms`, `descent`/`boss_lair` 필수 템플릿, 조사물 4종 배치 |
| `expedition/floor_templates.gd` + `data/content/floor_templates.json` | 템플릿 | `>` 계단, `Y` 전력탑, 새 템플릿 2개, `*`·`@`·`C`·`A` 의미 변경 |
| `data/content/floor_themes.json` | 테마 수치 | 크기·방 수·복도 폭·조사물 수 |
| `expedition/curios.gd` + `data/content/exploration_curios.json` | 조사물 | 도구 삭제, 4종 재정의, 식량·소모품·파츠 결과 |
| `expedition/boss_ai.gd` (신규) | 보스 세 패턴 | `boss_trial.gd`에서 이식 |
| `expedition/monster_ai.gd` | 몬스터 차례 | 고정 시야, 보스 위임 |
| `expedition/main.gd` | 화면 | 시작·야영·결과 화면, HUD 식량/야영, 마을·상점·유물 UI 삭제 |
| `expedition/character_ui.gd` | 성격/파츠 탭 | 장착 조건 CAMP |
| `expedition/board.gd`, `map_view.gd`, `mobile_art.gd` | 렌더 | 계단·전력탑 표시, 방 모드 분기 삭제 |
| `expedition/sim/encounter_runner.gd`, `encounter_arena.gd`, `data/content/balance_experiments.json` | 시뮬 | `light` 삭제 |
| 삭제 | `dungeon_map.gd`, `boss_trial.gd`, `expedition_objective.gd`, `settlement_hub.gd`, `docs/boss-trial.md`, `docs/terrain-layouts.md` |
| 테스트 | 신규 `run_start`, `camping`, `floor_descent`, `boss_floor`; 갱신 다수(아래 Task 8) |

---

### Task 1: 세션 정리 — 방 모드·마을·횃불·빛·자금 삭제, Run 시작

**Files:**
- Modify: `expedition/session.gd`, `expedition/continuous_floor.gd`, `expedition/monster_ai.gd`, `expedition/curios.gd`, `expedition/sim/encounter_runner.gd`, `expedition/sim/encounter_arena.gd`, `data/content/balance_experiments.json`, `expedition/board.gd`, `expedition/map_view.gd`, `expedition/character_ui.gd`
- Delete: `expedition/dungeon_map.gd`, `expedition/boss_trial.gd`(Task 5에서 이식 후 삭제 — 이 Task에서는 참조만 끊는다), `expedition/expedition_objective.gd`, `expedition/settlement_hub.gd`
- Test: `tests/run_start.gd` (신규)

**Interfaces:**
- Produces: `Session.depart() -> bool`(Run 시작: 1층 생성, `depth = 1`), `s.depth: int`, `s.score: int`, `s.food`(시작 2), `Session.SUPPLY_NAMES`(5종), `Floor.SIGHT_RADIUS := 5.0`, `MonsterAI.sight(s) -> 5`. `s.floor_mode`는 삭제 — 모든 `if floor_mode:` 분기는 참 쪽만 남긴다.
- Consumes: 없음.

- [ ] **Step 1: 실패하는 테스트 — `tests/run_start.gd`**

```gdscript
extends SceneTree
## Run start: no town, one hero on floor 1, food 2, empty slots, basics in the bag.
const Session = preload("res://expedition/session.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func run() -> void:
	solo_start()
	fixture_start()
	no_town_api()
	print("Run start: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func solo_start() -> void:
	var s = Session.new(731,false,false,true,1)
	check(s.phase == "TOWN" and s.party.size() == 1,"before depart the session is idle with one hero")
	check(s.depart(),"depart starts the run")
	check(s.phase == "BATTLE" and s.depth == 1 and s.round_number == 1,"floor 1, battle phase (exploration is the safe battle phase)")
	check(s.food == 2,"food starts at 2")
	check(s.party[0].equipped_abilities == ["",""],"slots start empty")
	check(int(s.parts_bag.get("PUSH",0)) == 1 and int(s.parts_bag.get("GUARD",0)) == 1,"basics in the bag")
	check(s.supplies.size() == 5 and s.supplies.all(func(n): return n == 0),"five supply kinds, none owned")
	check(Session.SUPPLY_NAMES.size() == 5 and "붕대" not in Session.SUPPLY_NAMES,"no bandage")
	check(not ("torches" in s) and not ("light" in s) and not ("bank" in s) and not ("hunger" in s),"torch, light, funds and hunger fields are gone")
	check(s.score == 0,"score starts at 0")
	check(s.floor_state.sight_radius() == 5.0,"fixed sight radius")

func fixture_start() -> void:
	# The battle suites' fixture: three members, depart, arena. Must keep working.
	var s = Session.new(731,true,true,true,3); s.depart()
	check(s.party.size() == 3 and s.phase == "BATTLE","three-member fixture still departs onto the floor")

func no_town_api() -> void:
	var s = Session.new(1,false,false,true,1); s.depart()
	check(not s.has_method("return_home") and not s.has_method("finish_expedition") and not s.has_method("rest_town") and not s.has_method("buy") and not s.has_method("use_torch"),"town, shop, return and torch APIs removed")
	check(not s.has_method("travel") and not s.has_method("enter_room"),"room-mode APIs removed")
```

- [ ] **Step 2: 실행 → 실패 확인.** `godot --headless --path . --script res://tests/run_start.gd`

- [ ] **Step 3: `session.gd` 정리.** 아래를 순서대로.

1. 상수·필드 삭제: `Dungeon` preload, `BOARD_SIDE := Dungeon.ROOM_SIDE` → `var BOARD_SIDE := 64`; `floor_mode`, `BossTrial` preload·`boss_trial`, `Objective` preload·`objective`, `STARTING_FUNDS`, `MIN_KIT`, `SHOP`, `purchases`, `PROVISION_SELL_PERCENT`, `ABANDON_STRESS`, `free_provisions`, `torches`, `light`, `loot`, `bank`, `hunger`, `exploration_tools`, `expedition_number`, `rooms`, `room`, `visited`, `snapshot`, `result`. 추가: `var depth := 0`, `var score := 0`. `food := 2`. `SUPPLY_NAMES = ["치유 물약","정신 안정제","활력 물약","화염 두루마리","물 두루마리"]`, `supplies: Array = [0,0,0,0,0]`.
2. `_init`: 인자 유지, 본문은
```gdscript
func _init(p_seed: int = 731, _p_boss_trial: bool = false, p_companions: bool = false, _p_floor: bool = true, p_party_size: int = 0) -> void:
	seed_value = p_seed
	companions = (p_party_size > 1) if p_party_size > 0 else p_companions
	floor_state = Floor.new(); BOARD_SIDE = floor_state.size
	parts_bag = STARTING_PARTS.duplicate(true)
	var count: int = clampi(p_party_size,1,3) if p_party_size > 0 else (2 if companions else 1)
	for i in range(count): party.append(make_actor(i, ["아린", "브란", "세라"][i], false))
	formation = range(count)
	reset_battle_stats()
```
3. `depart()`:
```gdscript
## Run start: floor 1, nothing bought, nothing to return to.
func depart() -> bool:
	if phase != "TOWN" or alive().is_empty(): return false
	depth = 1; score = 0
	for actor in party: actor.hit_and_run = false; actor.important_memories = {}
	reset_battle_stats()
	auto.prev_threats = 0; auto.prev_low = []; auto.prev_alive = alive().size()
	auto.stops_log = []; auto.last_stop = {"reason":"","round":-99}
	floor_state.build(self); message("%d층 진입" % depth); return true
```
4. 삭제 함수: `can_travel`, `travel`, `enter_room`, `doors`, `use_torch`, `use_food`, `camp`(Task 3에서 새로 씀), `event_choice`, `interact_room`, `retreat`, `objective_text`, `pickup_relic`, `return_error`, `return_home`, `abandon_error`, `abandon`, `actor_snapshot`, `actor_restore`, `take_snapshot`, `restore_snapshot`, `injury_count`, `finish_expedition`, `refit`, `top_up_kit`, `provision_stock`, `provision_sale_value`, `price`, `stock`, `add_stock`, `buy`, `refund`, `loot_scaled`, `rest_town`, `grant_test_loadout`의 `phase != "TOWN"` 조건(→ `party.is_empty()`만).
5. `start_battle`: 방 모드 본문 삭제 → `phase = "BATTLE"; round_number = 1; for actor in party: actor.reservation = {}; actor.ap = action_budget(actor); actor["guarded"] = false; actor["protected_by"] = -1; selected = party.find(alive()[0]); plan_enemies()`. (연속 층은 `Floor.apply`가 직접 BATTLE로 들어가므로 호출처는 테스트뿐이다.)
6. `combat_enemies()` → `floor_state.threats(self)`. `in_combat()` → `phase == "BATTLE" and not floor_state.safe(self)`. `act_as`: `if floor_mode and not floor_state.visible.has(target) and not following` → `if not floor_state.visible.has(target) and not following`; `boss_trial and kind == "PYLON"` 블록 삭제(Task 5가 `PYLON`을 층 기능으로 다시 넣는다). `finish_player_action`: `if phase != "BATTLE" or resolving_companions: return; floor_state.observe(self); ...` (boss_trial 조건 삭제).
7. `stress()`: `if amount > 0 and floor_mode and party.size() == 1` → `party.size() == 1`.
8. `damage()`: `boss_trial and target.enemy and rooms[room].shield` 블록 삭제(Task 5가 `target.get("shield",false)`로 대체); `floor_mode and` 조건 제거; 처치 시 `score += 10`.
9. `plan_enemies()` → `Floor.MonsterAI.plan(self)`. `_enemy_attack_turn` → `if phase != "BATTLE" or enemy.hp <= 0 or alive().is_empty(): return; floor_state.enemy_turn(self,enemy)`.
10. `end_round()`: `for enemy in enemies` 루프 뒤 `if alive().is_empty(): check_battle_end(); return true`; 스트레스 줄 `stress(actor, 2 if light >= 35 else 5)` → `if not floor_state.safe(self): stress(actor,2)`; `round_number % 4`·`% 20` 블록 전부 삭제; 마지막 `floor_state.observe(self)`만(`ambush` 삭제).
11. `check_battle_end()`: `if alive().is_empty(): phase = "DEFEAT"; message("원정대가 전멸했습니다.")` 만.
12. `roll_part`: `Floor.drop_percent(light)` → `Abilities.DROP_PERCENT`.
13. `use_supply`: `supplies.size()` 5로; slot 5(붕대) 분기 삭제; slot 2: `if actor.stress == 0 and actor.hp >= actor.max_hp: return false` → `stress(actor,-10); actor.hp = mini(actor.max_hp,actor.hp+5)`; `add_stock` 호출 → `supplies[slot] -= 1`; `free_provisions` 관련 삭제; `phase not in ["EXPLORE","BATTLE"]` → `phase not in ["BATTLE","CAMP"]`.
14. `equip_part/unequip_part`: `phase != "TOWN"` → `phase != "CAMP"`. (Task 3까지 CAMP가 없으므로 이 Task의 테스트는 장착을 검사하지 않는다.)
15. `arena_test`: `s.light = spec.light` 줄과 `spec.light` 줄 삭제.
16. `remember_important`: key의 `expedition_number` → `depth`. `curios.gd`의 `s.expedition_number*10000` → `s.depth*10000`.

- [ ] **Step 4: `continuous_floor.gd` 정리.**

`Objective` preload·`TIERS`·`light_tier/tier_label/loot_percent/drop_percent/enemy_bonus/sight_side/darkness_strength` 삭제. 추가 `const SIGHT_RADIUS := 5.0`, `func sight_radius() -> float: return SIGHT_RADIUS`(인스턴스), `static func sight_side() -> int: return ceili(SIGHT_RADIUS)*2+1`. `build(s)`: `Generator.generate(theme,s.seed_value+s.depth*7919,int(theme.depth))` — 테마는 Task 4에서 깊이별로 고르니 지금은 `F1_RUINS` 고정. `apply()`: `state.epoch = str(s.seed_value)+"/"+str(s.depth)`; relic/Objective 줄 삭제; `s.rooms = [...]`·`s.room = 0` 삭제; 마지막 `state.observe(s)`만. `observe()`: `var radius := SIGHT_RADIUS`; relic 분기 삭제; discoveries의 `"PORTAL" if relic` 삭제(계단은 Task 4). `ambush()` 삭제. `interact()`: entry 분기·`s.loot`·`s.light`·`add_stock` 줄 삭제 → camp 특징은 `for actor in s.alive(): actor.hp = mini(actor.max_hp,actor.hp+10)`, loot 특징은 `s.food += 2; s.score += 5`, altar는 `s.score += 10`. `enemy_turn`은 그대로.

- [ ] **Step 5: 나머지 참조 정리.**

- `monster_ai.gd`: `sight(s)` → `return ceili(s.Floor.SIGHT_RADIUS)`; `LEGACY_SIGHT` 삭제.
- `tactic_rules.gd lethal_threat`, `lookahead.gd threat_after`: `var bonus: int = s.Floor.enemy_bonus(s.light)` → `var bonus := 0`(한 줄만; 다른 로직 불변). `bonus if s.floor_mode` → `bonus`.
- `encounter_runner.gd`: `s.light = …` 줄 삭제(`s.supplies = config.supplies.duplicate()`는 유지, 배열 길이 5로 — `balance_experiments.json`의 `supplies`가 6칸이면 5칸으로 자른다). `encounter_arena.gd DEFAULT_SPEC`에서 `"light":90` 삭제. `balance_experiments.json` 아레나의 `light` 키 삭제(`ARENA_PRESETS` 로더의 `light` 필드도).
- `board.gd`: `session.boss_trial`·`session.floor_mode`·`room.shield` 참조 삭제(`floor_mode` 조건은 참으로 간주). `map_view.gd`: 방 지도 그리기(`rooms`) 분기 삭제, 연속 층 미니맵만. `character_ui.gd`: 161행 `editable` → `ui.session.phase == "CAMP"`; 224·241·256행 `TOWN` → `CAMP`.
- `main.gd`: 이 Task에서는 컴파일만 되게 최소 수정: `SettlementHub` preload 삭제, `session.floor_mode`/`boss_trial` 참조를 참/거짓 상수로 치환, `show_relic/show_return/show_goal/show_objective/start_return_walk/show_infirmary/show_town_roster/show_town_settings/show_shop/confirm_abandon/build_result_card/on_room`을 삭제하고 호출처는 `pass`. 시작·결과 화면은 Task 7.
- `dungeon_map.gd`, `expedition_objective.gd`, `settlement_hub.gd` 삭제. `boss_trial.gd`는 남기되 어디서도 preload하지 않는다.
- `docs/boss-trial.md`, `docs/terrain-layouts.md` 삭제.

- [ ] **Step 6: 실행.** `run_start` 통과. 임포트 검사 0 오류(삭제한 preload가 남아 있으면 여기서 잡힌다). `autobattle`, `stances`, `utility`, `parts`, `protect`, `skill_rule_conditions`, `companion_tactics`, `encounter_sim`, `arena_mode`, `floor_generator`, `continuous_floor`, `solo_floor` 실행 — 실패는 이 Task에서 고치지 말고 실패 목록을 보고서에 적는다(Task 8이 정리). 단 **컴파일 오류(SCRIPT ERROR)** 는 이 Task에서 없애야 한다.

- [ ] **Step 7: 커밋.** `refactor(run): drop town, room mode, torches, light and funds; the run starts on floor 1`

---

### Task 2: 식량·조사물·소모품

**Files:**
- Modify: `data/content/exploration_curios.json`, `expedition/curios.gd`, `expedition/floor_templates.gd`(글리프), `expedition/floor_generator.gd place_features`, `data/content/floor_themes.json curios`, `expedition/session.gd damage()`(짐승 드롭), `data/content/floor_monsters.json`(짐승 태그)
- Test: `tests/curios.gd`(재작성)

**Interfaces:**
- Produces: 조사물 id `SUPPLY_CACHE`, `MUSHROOMS`, `DEAD_ADVENTURER`, `BROKEN_CHEST`; `Curios.resolve(s, point, "SEARCH")`; 몬스터 `beast: true` → 25% 식량. 테마 `curios: {"supply_cache":[1,2],"mushrooms":[1,2],"dead_adventurer":[0,1],"broken_chest":[1,1]}`.

- [ ] **Step 1: 실패하는 테스트 — `tests/curios.gd`** (기존 파일을 통째로 교체; 검사 수는 기존 이상)

```gdscript
extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Curios = preload("res://expedition/curios.gd")
const Templates = preload("res://expedition/floor_templates.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func place(s, id: String) -> Vector2i:
	var p: Vector2i = s.party[0].pos+Vector2i(1,0)
	s.floor_state.features[p] = {"kind":"curio","curio_id":id,"label":Curios.content.curios[id].name,"used":false}
	s.floor_state.observe(s); s.party[0].ap = 1
	return p

func run() -> void:
	var s = Session.new(5,false,false,true,1); s.depart(); Fixture.arena(s,8)
	check(Curios.content.curios.keys() == ["SUPPLY_CACHE","MUSHROOMS","DEAD_ADVENTURER","BROKEN_CHEST"],"four curios, no tools")
	check(not Curios.content.has("tools"),"tool table removed")
	# Supply cache: food 2..3 and sometimes a supply.
	var food: int = s.food
	var p := place(s,"SUPPLY_CACHE")
	check(Curios.error(s,p,"SEARCH").is_empty() and Curios.resolve(s,p,"SEARCH"),"cache searched")
	check(s.food-food >= 2 and s.food-food <= 3,"cache gives 2-3 food")
	check(s.floor_state.features[p].used and Curios.error(s,p,"SEARCH") == "조사 완료","cache is spent")
	# Mushrooms: 1..2 food, 30% poison (-4 hp). Sample many seeds for both outcomes.
	var poisoned := 0; var fed := 0
	for seed in range(40):
		var t = Session.new(seed,false,false,true,1); t.depart(); Fixture.arena(t,8)
		var q := place(t,"MUSHROOMS"); var hp: int = t.party[0].hp; var f: int = t.food
		check(Curios.resolve(t,q,"SEARCH"),"mushrooms searched")
		if t.party[0].hp < hp: poisoned += 1
		if t.food > f: fed += 1
	check(poisoned >= 4 and poisoned <= 20,"poison happens on roughly a third of seeds (%d/40)" % poisoned)
	check(fed == 40,"mushrooms always feed")
	# Dead adventurer: food 1, sometimes a part, sometimes a supply.
	var parts := 0; var supplies := 0
	for seed in range(40):
		var t = Session.new(100+seed,false,false,true,1); t.depart(); Fixture.arena(t,8)
		var q := place(t,"DEAD_ADVENTURER"); var bag: int = t.parts_bag.values().reduce(func(a,b): return a+b,0); var sup: int = t.supplies.reduce(func(a,b): return a+b,0)
		check(Curios.resolve(t,q,"SEARCH") and t.food == 3,"adventurer gives food 1")
		if t.parts_bag.values().reduce(func(a,b): return a+b,0) > bag: parts += 1
		if t.supplies.reduce(func(a,b): return a+b,0) > sup: supplies += 1
	check(parts >= 4 and parts <= 20 and supplies >= 4 and supplies <= 20,"parts %d and supplies %d out of 40" % [parts,supplies])
	# Broken chest: a part or a supply, never nothing.
	for seed in range(10):
		var t = Session.new(200+seed,false,false,true,1); t.depart(); Fixture.arena(t,8)
		var q := place(t,"BROKEN_CHEST")
		var before: int = t.parts_bag.values().reduce(func(a,b): return a+b,0)+t.supplies.reduce(func(a,b): return a+b,0)
		check(Curios.resolve(t,q,"SEARCH"),"chest searched")
		check(t.parts_bag.values().reduce(func(a,b): return a+b,0)+t.supplies.reduce(func(a,b): return a+b,0) == before+1,"chest gives exactly one item")
	# Rules: not in reach, enemy visible, no ap.
	var u = Session.new(9,false,false,true,1); u.depart(); Fixture.arena(u,8)
	var far := place(u,"SUPPLY_CACHE"); u.floor_state.features[far+Vector2i(3,0)] = u.floor_state.features[far]; u.floor_state.features.erase(far)
	check(Curios.error(u,far+Vector2i(3,0),"SEARCH") == "거리 초과","too far")
	var near := place(u,"SUPPLY_CACHE"); u.enemies[0].hp = 30; u.enemies[0].pos = u.party[0].pos+Vector2i(0,2); u.floor_state.observe(u)
	check(Curios.error(u,near,"SEARCH") == "주변에 적 있음","enemy in sight blocks")
	# Beast drop: rats feed 25% of the time.
	var fed_by_rat := 0
	for seed in range(40):
		var t = Session.new(300+seed,false,false,true,1); t.depart(); Fixture.arena(t,8)
		var foe: Dictionary = t.enemies[0]; foe.hp = 1; foe.species_id = "dcss_rat"; foe.pos = t.party[0].pos+Vector2i(1,0); t.floor_state.observe(t)
		var f: int = t.food
		t.damage(foe,5,0,"SLASH")
		if t.food > f: fed_by_rat += 1
	check(fed_by_rat >= 3 and fed_by_rat <= 20,"rat drops food on about a quarter of kills (%d/40)" % fed_by_rat)
	# Generator places the four kinds within the theme's counts.
	var theme: Dictionary = preload("res://expedition/floor_generator.gd").theme("F1_RUINS")
	for seed in range(20):
		var layout: Dictionary = preload("res://expedition/floor_generator.gd").generate(theme,seed,1)
		var counts := {}
		for p2 in layout.features:
			var f2: Dictionary = layout.features[p2]
			if f2.kind == "curio": counts[f2.curio_id] = int(counts.get(f2.curio_id,0))+1
		for id in theme.curios:
			var n: int = int(counts.get(id.to_upper(),0))
			check(n >= theme.curios[id][0] and n <= theme.curios[id][1],"%s count %d within %s (seed %d)" % [id,n,theme.curios[id],seed])
	print("Curios: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
```

- [ ] **Step 2: 실패 확인.**

- [ ] **Step 3: 데이터.** `exploration_curios.json` 전체 교체:

```json
{"curios": {
  "SUPPLY_CACHE": {"name": "버려진 보급 상자", "icon": "loot", "description": "누군가 두고 간 상자. 마른 빵과 육포가 남아 있다.",
    "options": {"SEARCH": {"label": "뒤진다", "chance": 100, "success": {"food": [2,3], "supply_chance": 20, "text": "식량을 챙겼습니다."}}}},
  "MUSHROOMS": {"name": "버섯 군락", "icon": "dirt", "description": "축축한 벽에 버섯이 자란다. 먹을 수 있는 것도, 아닌 것도 있다.",
    "options": {"SEARCH": {"label": "채집한다", "warning": "독성 30% · 피해 4", "chance": 70, "success": {"food": [1,2], "text": "먹을 만한 버섯을 땄습니다."}, "failure": {"food": [1,2], "damage": 4, "text": "독버섯이 섞여 있었습니다."}}}},
  "DEAD_ADVENTURER": {"name": "죽은 모험가", "icon": "loot", "description": "얼마 전까지 살아 있었다. 짐이 그대로다.",
    "options": {"SEARCH": {"label": "수색한다", "chance": 100, "success": {"food": [1,1], "part_chance": 30, "supply_chance": 30, "text": "짐을 뒤졌습니다."}}}},
  "BROKEN_CHEST": {"name": "부서진 궤짝", "icon": "loot", "description": "자물쇠는 이미 누가 부쉈다. 바닥에 뭔가 남아 있다.",
    "options": {"SEARCH": {"label": "살펴본다", "chance": 100, "success": {"item": true, "text": "쓸 만한 것을 찾았습니다."}}}}}}
```

`floor_themes.json` 두 테마의 `curios` → `{"supply_cache":[1,2],"mushrooms":[1,2],"dead_adventurer":[0,1],"broken_chest":[1,1]}`. `floor_monsters.json`의 `dcss_rat`, `dcss_frilled_lizard`, `dcss_river_rat`에 `"beast": true`.

- [ ] **Step 4: `curios.gd resolve`.** 도구 검사 삭제. 결과 처리:

```gdscript
	var range_of := func(v) -> int:
		if v is Array: return int(v[0])+s.Hexaco.sample(s.seed_value,s.depth*10000+point.y*100+point.x,"curio_amount",int(v[1])-int(v[0])+1)
		return int(v)
	var got_food: int = range_of.call(outcome.get("food",0))
	s.food += got_food
	if outcome.has("damage"): s.damage(actor,int(outcome.damage),999,"IMPACT")
	if outcome.has("stress"): s.stress(actor,int(outcome.stress))
	var roll2: int = s.Hexaco.sample(s.seed_value,s.depth*10000+point.y*100+point.x,"curio_bonus",100)
	if roll2 < int(outcome.get("part_chance",0)): s.grant_part(s.Abilities.droppable()[s.Hexaco.sample(s.seed_value,point.y*100+point.x,"curio_part",s.Abilities.droppable().size())])
	elif roll2 < int(outcome.get("part_chance",0))+int(outcome.get("supply_chance",0)): s.grant_supply(s.Hexaco.sample(s.seed_value,point.y*100+point.x,"curio_supply",s.supplies.size()))
	if outcome.get("item",false):
		if roll2 < 50: s.grant_part(s.Abilities.droppable()[s.Hexaco.sample(s.seed_value,point.y*100+point.x,"curio_part",s.Abilities.droppable().size())])
		else: s.grant_supply(s.Hexaco.sample(s.seed_value,point.y*100+point.x,"curio_supply",s.supplies.size()))
	if got_food > 0: s.message("식량 %d 획득" % got_food)
	s.score += 5
```

`session.gd`에 `func grant_part(id: String) -> void: parts_bag[id] = int(parts_bag.get(id,0))+1; message(Abilities.DEFINITIONS[id].item+" 획득")`, `func grant_supply(slot: int) -> void: supplies[slot] += 1; message(SUPPLY_NAMES[slot]+" 획득")`. `Curios.error`의 `floor_mode` 조건 삭제.

- [ ] **Step 5: 생성기 배치.** `floor_templates.gd GLYPH_FEATURE`: `"$"` → `BROKEN_CHEST`, `"^"` → `MUSHROOMS`, 추가 `"&":{"kind":"curio","curio_id":"SUPPLY_CACHE"}`, `"!":{"kind":"curio","curio_id":"DEAD_ADVENTURER"}`(`GLYPH_TERRAIN`에도 `"&":"stone","!":"stone"`). `place_features`: `chest`/`dirt` 두 루프를 네 종 루프로 일반화 — `for id in ["supply_cache","mushrooms","dead_adventurer","broken_chest"]: var target = rng.randi_range(theme.curios[id][0],theme.curios[id][1]); var glyph = {"supply_cache":"&","mushrooms":"^","dead_adventurer":"!","broken_chest":"$"}[id]; var rooms_for = dead_end_plain if id == "broken_chest" and not dead_end_plain.is_empty() else branch_plain; while count.call("curio",id.to_upper()) < target and not rooms_for.is_empty() and guard < 20: …` (`mushrooms`는 `corner = true`).

- [ ] **Step 6: 짐승 드롭.** `session.damage()`의 처치 분기(`target.enemy and target.hp <= 0`)에 `if bool(Abilities.species_row(target.get("species_id","")).get("beast",false)) and Hexaco.sample(seed_value,depth*1000+target.id,"beast_food",100) < 25: food += 1; message("고기 획득 · 식량 +1")`. `Abilities.species_row(id)`가 없으면 `floor_monsters.json`의 species 배열에서 id로 찾는 static helper를 `abilities.gd`에 추가(캐시).

- [ ] **Step 7: 실행 → 통과.** `curios`, `floor_generator`(조사물 수 검사가 있으면 새 id로 갱신), `run_start`.

- [ ] **Step 8: 커밋.** `feat(run): food from four floor curios and beast kills; supplies found, never bought`

---

### Task 3: 야영(CAMP)

**Files:**
- Modify: `expedition/session.gd`
- Test: `tests/camping.gd` (신규)

**Interfaces:**
- Produces: `s.can_camp() -> String`(빈 문자열이면 가능, 아니면 이유), `s.camp() -> bool`(CAMP 진입 + 효과), `s.end_camp() -> bool`(→ BATTLE, 탐험 계속), 단계 `"CAMP"`. 장착 `equip_part/unequip_part`는 CAMP에서만.

- [ ] **Step 1: 실패하는 테스트 — `tests/camping.gd`**

```gdscript
extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func party(n: int, food: int) -> Dictionary:
	var s = Session.new(11,true,n > 1,true,n); s.depart(); Fixture.arena(s,8)
	s.food = food; return {"s":s}

func run() -> void:
	var s = party(3,2).s
	check(s.can_camp() == "식량 3 필요","not enough food for three")
	s.food = 3
	check(s.can_camp().is_empty(),"three food for three members")
	s.enemies[0].hp = 30; s.enemies[0].pos = s.party[0].pos+Vector2i(0,3); s.floor_state.observe(s)
	check(s.can_camp() == "적이 보임","an enemy in sight blocks camping")
	s.enemies[0].hp = 0; s.floor_state.observe(s)
	for a in s.party: a.hp = 10; a.stress = 80; a.cooldowns = {"PUSH":2}
	check(s.camp() and s.phase == "CAMP" and s.food == 0,"camp consumes one food per member and enters CAMP")
	check(s.party.all(func(a): return a.hp == 10+ceili(a.max_hp*0.5) and a.stress == 50 and a.cooldowns.get("PUSH",0) == 0),"half max hp back, -30 stress, cooldowns cleared")
	check(not s.camp(),"cannot camp inside camp")
	# Parts only at camp.
	check(s.equip_part(0,0,"PUSH") and s.party[0].equipped_abilities[0] == "PUSH","equip at camp")
	check(s.unequip_part(0,0) and s.party[0].equipped_abilities[0] == "","unequip at camp")
	check(s.end_camp() and s.phase == "BATTLE","camp ends back into exploration")
	check(not s.equip_part(0,0,"PUSH"),"no equipping outside camp")
	# Healing is capped and a full party still pays.
	var t = party(1,5).s; t.party[0].hp = t.party[0].max_hp; t.party[0].stress = 0
	check(t.camp() and t.party[0].hp == t.party[0].max_hp and t.party[0].stress == 0 and t.food == 4,"full member still eats")
	# Supplies usable at camp.
	t.supplies[1] = 1; t.party[0].stress = 40
	check(t.use_supply(1) and t.party[0].stress == 15 and t.supplies[1] == 0,"potion at camp")
	# Auto-run must be off and the stop event log untouched.
	check(not t.auto.running,"camp never runs auto")
	print("Camping: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
```

- [ ] **Step 2: 실패 확인.**

- [ ] **Step 3: 구현** (`session.gd`, `retreat()`가 있던 자리):

```gdscript
## 야영: the only use of food. Everybody eats, everybody heals a little.
func can_camp() -> String:
	if phase != "BATTLE": return "지금은 불가"
	if not floor_state.safe(self): return "적이 보임"
	var needed: int = alive().size()
	if food < needed: return "식량 %d 필요" % needed
	return ""

func camp() -> bool:
	if not can_camp().is_empty(): return false
	auto.running = false
	food -= alive().size()
	for actor in alive():
		actor.hp = mini(actor.max_hp,actor.hp+ceili(actor.max_hp*0.5))
		stress(actor,-30)
		for id in actor.cooldowns: actor.cooldowns[id] = 0
	phase = "CAMP"; intents.clear()
	message("야영 · 식량 -%d" % alive().size()); return true

func end_camp() -> bool:
	if phase != "CAMP": return false
	phase = "BATTLE"
	for actor in alive(): actor.ap = action_budget(actor)
	floor_state.observe(self); return true
```

`stress()`의 음수 경로는 배율 없이 그대로 더한다(기존 코드가 그렇다 — 확인). `use_supply`의 단계 조건은 Task 1에서 `["BATTLE","CAMP"]`로 바꿨다.

- [ ] **Step 4: 실행 → 통과.** `camping`, `parts`(장착 검사가 TOWN을 가정하면 픽스처를 `s.camp()` 뒤로 옮기되 검사 수 유지).

- [ ] **Step 5: 커밋.** `feat(run): camping — food feeds the party, heals, and is the only place parts are equipped`

---

### Task 4: 계단·하강·테마 순환·파티 기준 층 크기

**Files:**
- Modify: `data/content/floor_templates.json`(`descent` 신규, `relic_vault` 삭제), `expedition/floor_templates.gd`(`>` 글리프), `data/content/floor_themes.json`, `expedition/floor_generator.gd`(복도 폭, `npc_rooms`, `relic`→`stairs`), `expedition/continuous_floor.gd`(테마 선택, 계단 상호작용), `expedition/session.gd descend()`, `expedition/board.gd`/`map_view.gd`(계단 표시)
- Test: `tests/floor_descent.gd`(신규), `tests/floor_generator.gd`(갱신)

**Interfaces:**
- Produces: `s.descend() -> bool`, `Floor.theme_for(depth) -> Dictionary`(예산 배율 적용), layout 키 `stairs: Vector2i`(`relic` 대체), `layout.npc_rooms: Array[int]`, 테마 `corridor.width`.

- [ ] **Step 1: 실패하는 테스트 — `tests/floor_descent.gd`**

```gdscript
extends SceneTree
const Session = preload("res://expedition/session.gd")
const Floor = preload("res://expedition/continuous_floor.gd")
const Generator = preload("res://expedition/floor_generator.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func run() -> void:
	themes(); descend(); sizes()
	print("Floor descent: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func themes() -> void:
	check(Floor.theme_for(1).id == "F1_RUINS" and Floor.theme_for(2).id == "F2_MINES" and Floor.theme_for(3).id == "F1_RUINS" and Floor.theme_for(4).id == "F2_MINES","themes alternate by depth")
	var base: Dictionary = Generator.theme("F2_MINES")
	var deep: Dictionary = Floor.theme_for(6)
	check(deep.monsters.budget.mid == roundi(base.monsters.budget.mid*2.0),"depth 6 doubles the mines budget (1 + 0.25*4)")

func descend() -> void:
	var s = Session.new(21,true,true,true,3); s.depart()
	var stairs: Vector2i = s.floor_state.layout.stairs
	check(stairs.x >= 0 and s.floor_state.features.get(stairs,{}).get("kind","") == "stairs","floor 1 has stairs")
	check(not s.descend(),"cannot descend away from the stairs")
	s.food = 4; s.parts_bag["HOB_CLUB"] = 1; s.party[1].hp = 12; s.party[2].stress = 60
	s.serial += 1; s.remember_important(s.party[0],"ALLY_DOWNED",2,101,700)
	for a in s.party: a.pos = stairs; 
	s.party[1].pos = stairs+Vector2i(1,0); s.party[2].pos = stairs+Vector2i(0,1); s.floor_state.observe(s)
	for e in s.enemies: e.hp = 0
	var old_layout: Dictionary = s.floor_state.layout
	check(s.descend() and s.depth == 2 and s.phase == "BATTLE","descend to floor 2")
	check(s.floor_state.layout != old_layout and s.floor_state.layout.theme_id == "F2_MINES","new mines layout")
	check(s.party[0].pos == s.floor_state.layout.entry,"party stands at the new entry")
	check(s.food == 4 and s.parts_bag.get("HOB_CLUB",0) == 1 and s.party[1].hp == 12 and s.party[2].stress == 60,"food, bag, hp and stress carry over")
	check(s.party[0].memory.records.size() == 1,"memories carry over")
	check(s.enemies.size() > 0 and s.enemies.all(func(e): return e.hp > 0),"fresh roster")
	# Stairs need a clear field of view.
	var t = Session.new(22,false,false,true,1); t.depart()
	var st: Vector2i = t.floor_state.layout.stairs; t.party[0].pos = st
	t.enemies[0].hp = 30; t.enemies[0].pos = st+Vector2i(0,2); t.floor_state.observe(t)
	check(not t.descend(),"enemy in sight blocks the stairs")

func sizes() -> void:
	for id in ["F1_RUINS","F2_MINES"]:
		var theme: Dictionary = Generator.theme(id)
		check(theme.size == 80 and theme.rooms.count == [13,16] and theme.corridor.width == 2,"%s sized for a party" % id)
		for seed in range(20):
			var layout: Dictionary = Generator.generate(theme,seed,int(theme.depth))
			check(Generator.validate(layout,theme).is_empty(),"%s seed %d valid" % [id,seed])
			check(layout.npc_rooms.size() >= 3 and layout.npc_rooms.size() <= 5,"npc rooms 3-5 (seed %d)" % seed)
			check(layout.stairs.x >= 0 and layout.get("relic",Vector2i(-1,-1)) == Vector2i(-1,-1),"stairs placed, relic gone")
```

- [ ] **Step 2: 실패 확인.**

- [ ] **Step 3: 템플릿·테마.** `floor_templates.json`: `relic_vault` 항목을 삭제하고 추가

```json
{"id": "descent", "label": "내려가는 길", "tags": ["ruins", "mines", "descent"], "depth": [1, 9], "orient": true,
 "rows": ["###########", "#.........#", "#..%...%..#", "#....>....#", "#..%...%..#", "#.........#", "#....,....#", "#####+#+###"]}
```

`floor_templates.gd`: `GLYPH_TERRAIN[">"] = "stone"`, `GLYPH_FEATURE[">"] = {"kind":"stairs","label":"내려가는 길"}`; `"*"`·relic 항목 삭제; `"@"` label → `"입구"`. `floor_themes.json` 두 테마: `size 80`, `rooms.count [13,16]`, `plain_size [[6,6],[9,8]]`, `fight_size [[10,10],[13,11]]`, `corridor {"wiggle":2,"extra_links":[2,3],"width":2}`, `templates.required ["entry_camp","descent","sealed_treasury"]`.

- [ ] **Step 4: 생성기.**
- `carve()`: 경로를 판 뒤 폭 2로 넓힌다 — 각 경로 칸 `p`에 대해 방향 `d = path[i+1]-path[i]`의 수직 방향 칸 `p+perp(d)`도 벽이고 `protected`가 아니면 바닥으로(`perp(Vector2i(x,y)) = Vector2i(-y,x)`). `theme.corridor.get("width",1) >= 2`일 때만.
- `place_features`: `relic` → `stairs`(`layout.stairs`). `layout` 초기 dict의 `relic` 키를 `stairs`로, `stats.relic_distance` → `stairs_distance`. `validate`: `layout.entry.x < 0 or layout.stairs.x < 0`; 복도 폭 검사 추가 — `theme.corridor.get("width",1) >= 2`이면 방 밖 바닥 칸마다 4방향 중 적어도 하나의 이웃이 방 밖 바닥이어야 한다(`"corridor width at %s"`).
- `attempt_layout` 끝: `layout.npc_rooms = rooms.filter(func(r): return r.kind == "plain" and r.template_id == "" and not layout.encounters.any(func(e): return e.room == r.id))` 를 입구 거리 내림차순으로 정렬해 앞 3~5개의 id(`rng.randi_range(3,5)`, 부족하면 있는 만큼). encounter에 `room` 필드가 없으면 `build_encounters`에서 넣는다.

- [ ] **Step 5: 층·세션.** `continuous_floor.gd`:

```gdscript
static func theme_for(depth: int) -> Dictionary:
	var theme: Dictionary = Generator.theme("F1_RUINS" if depth % 2 == 1 else "F2_MINES")
	if depth >= 3:
		var scale: float = 1.0+0.25*(depth-2)
		for key in theme.monsters.budget: theme.monsters.budget[key] = roundi(theme.monsters.budget[key]*scale)
	theme.depth = depth
	return theme

func build(s) -> void:
	var theme: Dictionary = theme_for(s.depth)
	apply(s,theme,Generator.generate(theme,s.seed_value+s.depth*7919,s.depth))
```

`observe()` discoveries marker: `"STAIRS" if feature.kind == "stairs"`. `interact()`: `stairs` 분기는 `return false`(명시적 선택 — UI 팝업이 `s.descend()`를 부른다). `session.gd`:

```gdscript
## Down the stairs: same party, same bag, a new floor.
func descend() -> bool:
	if phase != "BATTLE" or not floor_state.safe(self): return false
	var stairs: Vector2i = floor_state.layout.get("stairs",Vector2i(-1,-1))
	if stairs.x < 0 or not alive().any(func(a): return distance(a.pos,stairs) <= 1): return false
	depth += 1; score += 20
	for actor in party: actor.reservation = {}; actor.hit_and_run = false
	end_battle_orders()
	reset_battle_stats()
	floor_state.build(self); message("%d층 진입" % depth); return true
```

- [ ] **Step 6: 렌더.** `board.gd`: 특징 `stairs`를 `Art.STAIRS`(없으면 `Art.ALTAR`를 임시로 재사용하고 `mobile_art.gd`에 `STAIRS` 상수 추가 — 32×32 단색 삼각형을 코드로 그린 텍스처, 그림 파일 없음). `map_view.gd`: marker `"STAIRS"`를 밝은 점으로.

- [ ] **Step 7: 실행 → 통과.** `floor_descent`, `floor_generator`(64→80, `relic`→`stairs`, 필수 템플릿 이름 검사 갱신; 검사 수 유지), `continuous_floor`, `run_start`, `camping`.

- [ ] **Step 8: 커밋.** `feat(run): stairs and descent, alternating themes with scaled budgets, party-sized floors`

---

### Task 5: 보스 층

**Files:**
- Create: `expedition/boss_ai.gd`
- Modify: `data/content/floor_templates.json`(`boss_lair`), `expedition/floor_templates.gd`(`Y`), `expedition/floor_generator.gd`(depth%3 필수 템플릿), `expedition/continuous_floor.gd apply`(보스 생성), `expedition/monster_ai.gd turn/plan`(위임), `expedition/session.gd`(`act_as PYLON`, `descend` 봉인, `damage` 보호막), `expedition/board.gd`(전력탑·보스 스프라이트)
- Delete: `expedition/boss_trial.gd`
- Test: `tests/boss_floor.gd`(신규); `tests/boss_trial.gd` 삭제

**Interfaces:**
- Produces: `BossAI.spawn(s, layout, depth)`, `BossAI.plan(s, boss)`, `BossAI.turn(s, boss)`, `BossAI.disable_pylon(s, point) -> bool`; 보스 액터 필드 `boss: true, pattern: 0|1|2, fuse, recovery, cooldown, shield, overloaded, pylon: Vector2i`; 층 특징 `{"kind":"pylon"}`; intents `{"id","cell","damage":16,"kind":"BOSS"}`.

- [ ] **Step 1: 실패하는 테스트 — `tests/boss_floor.gd`**

```gdscript
extends SceneTree
const Session = preload("res://expedition/session.gd")
const Floor = preload("res://expedition/continuous_floor.gd")
const Generator = preload("res://expedition/floor_generator.gd")
const BossAI = preload("res://expedition/boss_ai.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

## A session already standing on the boss floor of the given depth.
func on_boss_floor(seed: int, depth: int) -> Dictionary:
	var s = Session.new(seed,true,true,true,3); s.depart()
	s.depth = depth-1; s.food = 9
	# Jump: the stairs test lives in floor_descent; here we rebuild directly.
	s.depth = depth; s.floor_state.build(s)
	var boss: Dictionary = s.enemies.filter(func(e): return e.get("boss",false))[0]
	return {"s":s,"boss":boss}

func run() -> void:
	generation(); sealed_stairs(); goo(); assassin(); giant()
	print("Boss floor: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func generation() -> void:
	for depth in [3,6,9]:
		var theme: Dictionary = Floor.theme_for(depth)
		check("boss_lair" in theme.templates.required and "descent" not in theme.templates.required,"depth %d requires the lair" % depth)
		var layout: Dictionary = Generator.generate(theme,7,depth)
		check(layout.stairs.x >= 0 and layout.features.values().any(func(f): return f.kind == "pylon"),"lair has stairs and a pylon")
		check(layout.npc_rooms.is_empty(),"no npc rooms on a boss floor")
	check("boss_lair" not in Floor.theme_for(4).templates.required,"depth 4 is ordinary")
	var f := on_boss_floor(1,3); var s = f.s; var boss: Dictionary = f.boss
	check(boss.pattern == 0 and boss.name.begins_with("수렁 포식자") and boss.hp == 64,"depth 3: goo at 64")
	check(on_boss_floor(1,6).boss.pattern == 1 and on_boss_floor(1,6).boss.hp == 72,"depth 6: assassin at 72")
	check(on_boss_floor(1,9).boss.pattern == 2,"depth 9: giant")
	check(s.enemies.filter(func(e): return not e.get("boss",false)).size() > 0,"ordinary encounters still spawn")

func sealed_stairs() -> void:
	var f := on_boss_floor(2,3); var s = f.s; var boss: Dictionary = f.boss
	var stairs: Vector2i = s.floor_state.layout.stairs
	for e in s.enemies: if not e.get("boss",false): e.hp = 0
	s.party[0].pos = stairs; boss.pos = stairs+Vector2i(6,0); s.floor_state.observe(s)
	check(not s.descend() and s.stairs_sealed(),"stairs sealed while the boss lives")
	boss.hp = 0
	check(not s.stairs_sealed() and s.descend() and s.depth == 4,"boss dead: stairs open")

func goo() -> void:
	var f := on_boss_floor(3,3); var s = f.s; var boss: Dictionary = f.boss
	for e in s.enemies: if not e.get("boss",false): e.hp = 0
	boss.pos = s.party[0].pos+Vector2i(1,0); boss.alert = true; boss.cooldown = 0; s.floor_state.observe(s)
	s.plan_enemies()
	check(boss.charging and s.intents.any(func(i): return i.id == boss.id and i.kind == "BOSS" and i.cell == s.party[0].pos),"goo announces a radius-2 blast on the floor's intents")
	check(s.intents.filter(func(i): return i.id == boss.id).size() == 25-4,"radius 2 Chebyshev ring minus nothing: 21 cells inside 5x5 with distance<=2 (Manhattan)")
	var hp: int = s.party[0].hp
	s.end_round(); s.end_round()
	check(s.party[0].hp < hp,"blast lands after the fuse")

func assassin() -> void:
	var f := on_boss_floor(4,6); var s = f.s; var boss: Dictionary = f.boss
	for e in s.enemies: if not e.get("boss",false): e.hp = 0
	boss.pos = s.party[0].pos+Vector2i(3,0); boss.alert = true; boss.cooldown = 0; s.floor_state.observe(s)
	s.plan_enemies()
	check(s.intents.filter(func(i): return i.id == boss.id).size() == 9,"3x3 bomb around the target")
	var before: Vector2i = boss.pos
	s.end_round(); s.end_round()
	check(boss.pos != before,"assassin relocates after the blast")

func giant() -> void:
	var f := on_boss_floor(5,9); var s = f.s; var boss: Dictionary = f.boss
	for e in s.enemies: if not e.get("boss",false): e.hp = 0
	boss.pos = s.party[0].pos+Vector2i(1,0); boss.alert = true; s.floor_state.observe(s)
	boss.hp = boss.max_hp/2
	s.plan_enemies()
	check(boss.shield and boss.pylon.x >= 0,"giant raises its shield at half health")
	var hp: int = boss.hp
	s.damage(boss,10,0,"SLASH")
	check(boss.hp == hp,"shield blocks damage")
	s.party[0].pos = boss.pylon+Vector2i(1,0); s.party[0].ap = 1; s.floor_state.observe(s)
	check(s.act_as(s.party[0],"PYLON",boss.pylon,false) and not boss.shield,"pylon tap drops the shield")
```

- [ ] **Step 2: 실패 확인.**

- [ ] **Step 3: 템플릿.** `floor_templates.json` 추가:

```json
{"id": "boss_lair", "label": "보스의 소굴", "tags": ["boss"], "depth": [3, 9], "orient": false,
 "rows": ["##############", "#............#", "#..~~........#", "#..~~....M...#", "#............#", "#......Y.....#", "#............#", "#............#", "#.....>......#", "#............#", "######+##+####"]}
```

`GLYPH_TERRAIN["Y"] = "stone"`, `GLYPH_FEATURE["Y"] = {"kind":"pylon","label":"전력탑"}`, `"~"`는 기존 water.

- [ ] **Step 4: 생성기·층.** `Floor.theme_for(depth)`: `if depth % 3 == 0: theme.templates.required = ["entry_camp","boss_lair","sealed_treasury"]`, `npc_rooms`는 빈 배열(생성기 `attempt_layout`에서 `theme.get("boss",false)`이면 `[]` — `theme_for`가 `theme.boss = depth % 3 == 0`을 넣는다). `Floor.apply()` 끝(observe 전): `if theme.get("boss",false): BossAI.spawn(s,layout,int(theme.depth))`.

- [ ] **Step 5: `boss_ai.gd`.** `boss_trial.gd`의 `NAMES/HINTS/target/plan/turn/disable_pylon`을 옮기되:
- `spawn(s, layout, depth)`: `pattern = ((depth/3)-1) % 3`; 보스 = `s.make_actor(900+depth, NAMES[pattern], true)`; `hp = max_hp = 64+8*((depth/3)-1)`; `pos` = `boss_lair` 방의 anchor(`M`); `boss = true, pattern, cooldown = 4, recovery = 0, shield = false, overloaded = false, fuse = 0`; `pylon` = 층 특징 중 `pylon` 칸; `alert = false`; `role = "MELEE"`; `part_id = Abilities.droppable()[pattern % size]`; `MonsterAI.configure`는 부르지 않는다(이름 접미사 없음). `s.enemies.append(boss)`.
- `plan(s, boss)`: `rooms[room]` 대신 `boss` 필드; intents에 `"kind":"BOSS"`; 거인 보호막 시 `boss.pylon`은 이미 층 특징이므로 옮기지 않는다(`pylon` 칸이 점유돼 있어도 탭은 인접에서 하므로 무관).
- `turn(s, boss)`: `s.alive()` 표적 그대로; 폭발은 `s.enemy_attack_effect` + intents 순회(기존); 암살자 순간이동 후보는 방 안 빈 모서리 대신 "보스로부터 거리 ≥ 3인 `boss_lair` 방 바닥 칸 중 첫 번째"(`s.floor_state.layout.rooms`에서 template_id로 방을 찾아 `Generator.floor_cells`).
- `disable_pylon(s, point)`: `boss.shield`를 끄고 `hero.ap -= 1`.
- `monster_ai.gd`: `plan()` 루프에서 `if enemy.get("boss",false): BossAI.plan(s,enemy); continue`(단 `s.intents.clear()`는 한 번만, `BossAI.plan`은 clear하지 않도록 수정); `turn()` 첫 줄 `if enemy.get("boss",false): return BossAI.turn(s,enemy)` — 단 시야·경계(`alert`) 판정은 공통 코드를 먼저 통과시킨다(보스도 파티를 봐야 움직인다).
- `session.gd`: `act_as`에 `if kind == "PYLON": if not BossAI.disable_pylon(self,target): return false; …capture…; return true`(Task 1에서 지운 블록을 `boss_trial` 조건 없이 복구); `damage()`: `if target.get("shield",false): message(target.name+"의 보호막이 막았습니다."); return`; `func stairs_sealed() -> bool: return enemies.any(func(e): return e.get("boss",false) and e.hp > 0)`; `descend()` 첫 조건에 `or stairs_sealed()`; 보스 처치 시 파츠 드롭 100%(`roll_part` 앞에서 `if target.get("boss",false): grant_part(target.part_id); score += 100`).
- `board.gd`: `Art.BOSS` for `actor.get("boss",false)`; 특징 `pylon`을 `Art.PYLON`(기존 보스 시련 전력탑 아트가 있으면 재사용, 없으면 `STAIRS`처럼 코드 텍스처).
- `boss_trial.gd`, `tests/boss_trial.gd`, `docs/boss-trial.md` 삭제.

- [ ] **Step 6: 실행 → 통과.** `boss_floor`, `floor_descent`, `floor_generator`, `utility`·`stances`(intents 형식은 그대로라 통과해야 한다), `lookahead`가 `kind:"BOSS"` intents를 읽는지 `boss_floor`의 goo 검사로 확인(`Rules.lethal_threat` ≥ 16).

- [ ] **Step 7: 커밋.** `feat(run): boss floors every third depth; the three patterns move to boss_ai on the floor's intents`

---

### Task 6: HUD·야영 화면·시작·결과 화면

**Files:**
- Modify: `expedition/main.gd`, `expedition/battle_hud.gd`(필요 시), `expedition/character_ui.gd`(파츠 탭 CAMP 문구)
- Test: `tests/mobile_hud.gd`, `tests/ui_smoke.gd`(갱신), `tests/run_start.gd`에 `scene()` 추가

**Interfaces:**
- Produces: 노드 이름 `StartScreen`(`NewRun`, `ArenaButton`), `FoodLabel`, `CampButton`, `CampScreen`(`CampMember%d`, `CampEnd`), `StairsPopup`(`Descend`), `ResultCard`(`NewRun`), `Location` 텍스트 `"n층"`.

- [ ] **Step 1: 실패하는 테스트 — `tests/run_start.gd`에 추가**

```gdscript
func scene() -> void:
	var main = load("res://expedition/main.tscn").instantiate()
	root.add_child(main); await process_frame
	var names := func(node: Node) -> Array:
		var out: Array = []
		var stack: Array = [node]
		while not stack.is_empty():
			var n: Node = stack.pop_back(); out.append(n.name)
			for c in n.get_children(): stack.append(c)
		return out
	var found: Array = names.call(main)
	check("StartScreen" in found and "NewRun" in found and "ArenaButton" in found,"start screen with new run and arena")
	check(not ("TorchButton" in found) and not ("Funds" in found) and not ("SettlementHub" in found),"no torch, funds or town")
	main.new_run(); await process_frame
	found = names.call(main)
	check("FoodLabel" in found and "CampButton" in found and "AutoToggle" in found,"floor HUD with food and camp")
	check(main.session.depth == 1 and main.session.party.size() == 1,"solo on floor 1")
	var loc: Label = main.find_child("Location",true,false)
	check(loc != null and loc.text == "1층","location reads the depth")
	# Camp screen.
	main.session.food = 1; for e in main.session.enemies: e.hp = 0
	main.session.floor_state.observe(main.session); main.refresh(); await process_frame
	var camp: Button = main.find_child("CampButton",true,false)
	check(camp != null and not camp.disabled,"camp enabled with food and no foe")
	camp.pressed.emit(); await process_frame
	found = names.call(main)
	check(main.session.phase == "CAMP" and "CampScreen" in found and "CampMember0" in found and "CampEnd" in found,"camp screen")
	main.find_child("CampEnd",true,false).pressed.emit(); await process_frame
	check(main.session.phase == "BATTLE","back to the floor")
	# Result.
	main.session.party[0].hp = 0; main.session.check_battle_end(); main.refresh(); await process_frame
	found = names.call(main)
	check("ResultCard" in found and "NewRun" in found,"result card with new run")
	main.queue_free(); await process_frame
```

`run()`에 `await scene()` 추가.

- [ ] **Step 2: 실패 확인.**

- [ ] **Step 3: 구현 (`main.gd`).**
- `var session = null`(시작 화면에서는 세션 없음) — `refresh()` 첫 줄에서 `if session == null: build_start_screen(); return`. `func new_run() -> void: session = Session.new(randi(),false,false,true,1); session.depart(); stop_text = ""; battle_reported = false; check_stop(); refresh()`.
- `build_start_screen()`: `VBoxContainer` 이름 `StartScreen`; 제목 라벨; `button(...,"새 Run",new_run)` 이름 `NewRun`; `button(...,"전투 시험",show_arena_setup)` 이름 `ArenaButton`. 전투 시험은 `menu_session`(구 `town_session`) 없이: `leave_arena()`는 `session = null; refresh()`.
- HUD 헤더: `food_button`/`torch_button`/`funds` 삭제 → `var food_label := label(header,"식량 %d" % session.food,14); food_label.name = "FoodLabel"`; `place.text = "%d층" % session.depth`; `menu` 버튼은 로그/가방 팝업만.
- nav 줄: `auto_explore_button` 뒤에 `var camp := button(nav,"야영",func(): run_action(session.camp),session.can_camp().is_empty() and not session.auto.running); camp.name = "CampButton"; camp.tooltip_text = session.can_camp()`.
- `refresh()`에 `if session.phase == "CAMP": build_camp_screen(); return` — `CampScreen` VBox: 라벨 "야영 · 식량 %d"; 멤버 카드 `CampMember%d`(이름·HP·스트레스·태세 3버튼 `session.set_stance` 재사용·파츠 슬롯 2 — 슬롯 버튼은 `character_ui.gd`의 파츠 탭 위젯을 재사용: `CharacterUI.parts_row(self,index,box)`가 없으면 `show_character(index,"파츠")` 버튼으로 대체); 가방 버튼(`show_supplies`); `button(...,"야영 끝",func(): run_action(session.end_camp))` 이름 `CampEnd`.
- `on_cell`: 특징 `stairs`가 시야 안이고 선택 멤버와 인접이면 `show_stairs()`: 팝업 `StairsPopup`, 본문 "%d층으로 내려간다" / 봉인 시 "봉인됨 · 보스를 쓰러뜨려야 한다", 버튼 `Descend`(`run_action(session.descend)`, `session.stairs_sealed()`면 비활성) · "아직".
- `pylon` 특징 탭(인접, 보스 보호막 중) → `run_action(func(): return session.act("PYLON",point))`.
- `DEFEAT`: `build_result_card()` 재작성 — `ResultCard`: "%d층에서 쓰러졌다", 라운드 `session.world_time/100`, 점수, 동료 목록(`session.party` 1번부터: 이름·최후), 실수 합계(`battle_stats` 대신 `session.run_stats.mistakes` — `note_mistake`에서 `run_stats.mistakes += 1` 누적, `depart()`에서 0), 버튼 `NewRun`(`new_run`) · "시작 화면"(`session = null; refresh()`).
- `show_supplies`/`build_inventory`: 붕대 슬롯 삭제(5칸), 도구·구매 행 삭제.
- `character_ui.gd` 파츠 탭: 잠금 문구 "야영에서 장착".

- [ ] **Step 4: 실행 → 통과.** `run_start`(scene 포함), `mobile_hud`, `ui_smoke`, `arena_mode`(scene 검사가 `TownArena` 버튼을 찾으면 `ArenaButton`으로 갱신), `character_ui`.

- [ ] **Step 5: 커밋.** `feat(ui): start screen, floor HUD with food and camp, camp screen, stairs popup, run result`

---

### Task 7: 테스트 이주·CI·게이트·문서

**Files:**
- Delete: `tests/terrain_layouts.gd`, `tests/torch_vision.gd`, `tests/torch_tradeoff.gd`, `tests/solo_provisioning.gd`, `tests/expedition_settlement.gd`, `tests/solo_recovery.gd`(+ `.uid`)
- Modify: 나머지 33개 중 실패하는 스위트 전부, `.github/workflows/deploy-pages.yml`, `docs/balance/*`, `docs/balance-method.ko.md`, `README.md`
- Test: 전체 CI 목록

- [ ] **Step 1: 삭제 스위트 제거, CI 목록 갱신.** `for suite in …`에서 `boss_trial terrain_layouts torch_vision torch_tradeoff solo_provisioning expedition_settlement solo_recovery` 제거, `run_start curios camping floor_descent boss_floor` 추가(`curios`는 이미 있으면 그대로).

- [ ] **Step 2: 스위트별 이주.** 각 파일에서 지운 기능의 check만 삭제하고 같은 수 이상의 새 검사를 넣는다. 예상 지점: `autobattle.gd`(`light`/`torch` 정지 검사 → 식량·야영 검사), `mobile_hud.gd`·`ui_smoke.gd`·`mobile_actions.gd`(횃불·자금 위젯 → `FoodLabel`·`CampButton`), `playthrough.gd`·`integration.gd`(마을→출정→귀환 시나리오 → 시작→1층→계단→2층→야영), `solo_floor.gd`(`return_home`·`abandon`·`finish_expedition` 검사 → `descend`·`camp`), `continuous_floor.gd`(`ambush`·빛 시야 → 고정 시야·계단), `encounter_sim.gd`·`action_economy.gd`·`stance_gate.gd`·`skill_value.gd`·`solo_balance.gd`(`light` 설정 삭제), `expedition_skills.gd`·`abilities_growth.gd`(`TOWN` 장착 → `camp()` 뒤 장착), `parts.gd`(`shop part:` 검사 → 궤짝 드롭 검사; `equip only in town` → `only at camp`), `map_fixture.gd`(방 지도 → 층), `floor_templates.gd`(`relic`→`stairs`, `Y`/`>` 글리프), `monster_roles.gd`·`ranged_probe.gd`·`party_guard_probe.gd`(`light`), `character_ui.gd`(TOWN→CAMP), `test_loadout.gd`(`grant_test_loadout` 조건), `enemy_turns.gd`(방 모드 수문장 → 층 몬스터). 각 파일 첫 실행 결과를 보고서에 "before/after 검사 수"로 적는다.

- [ ] **Step 3: 게이트 재측정.** `solo_balance`(≥ 3/8), `stance_gate`, `ranged_probe`, `utility`. 어둠 보정이 사라져 수치가 움직이면 `floor_themes.json`의 몬스터 예산으로만 맞추고 `docs/balance/run-gates.md`에 기록(AI 가중치 불변).

- [ ] **Step 4: 문서.** `README.md`·`docs/balance-method.ko.md`·`docs/abilities-growth.md`·`docs/fantasy-mecha-concept.md`에서 마을·상점·횃불·유물·3×3 언급을 한 줄씩 새 흐름으로 고친다. `docs/superpowers/specs/2026-09-25-run-camp-npc-design.md` 상태를 "Plan A 구현됨(§5 제외)"로.

- [ ] **Step 5: 전체 CI 목록 + 임포트 검사 통과.** 커밋 `test(run): migrate suites to the descent run; gates re-measured`.

---

## 자기 검토

- 스펙 커버리지: §1 Run 구조(T1·T6) / §2 자원·소모품(T1·T2) / §3 야영(T3·T6) / §4.1 계단·4.2 크기·4.3 자동 이동(T4; 자동 이동은 `exploration_navigation.gd`가 이미 탭 경로 이동을 하므로 계단·조사물 인접 정지만 T6의 `on_cell`에서 확인) / §4.4 보스 층(T5) / §6 UI(T6) / §7 삭제(T1·T5·T7) / §8 검증(T1~T7). §5 NPC는 Plan B.
- 이름 일관성: `depart/descend/camp/end_camp/can_camp/stairs_sealed/grant_part/grant_supply/score/depth`, `Floor.theme_for/SIGHT_RADIUS/sight_radius`, `layout.stairs/npc_rooms`, `BossAI.spawn/plan/turn/disable_pylon`, 노드 `StartScreen/NewRun/ArenaButton/FoodLabel/CampButton/CampScreen/CampMember%d/CampEnd/StairsPopup/Descend/ResultCard`.
- 위험: Task 1의 삭제 폭이 커서 컴파일 오류가 남을 수 있다 — 임포트 검사가 게이트다. Task 7의 이주는 33개 파일이라 구현자가 검사 수를 줄이고 싶어질 것이다 — "삭제한 check 수 ≤ 추가한 check 수"를 보고서에 표로 요구한다.
