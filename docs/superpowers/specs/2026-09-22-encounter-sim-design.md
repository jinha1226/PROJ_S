# 조우 시뮬레이터 · 행동 경제 실험 설계

작성일: 2026-09-22 · 상태: 설계 확정(밸런스 방법론 §8 1단계) · 구현 계획: `docs/superpowers/plans/2026-09-22-encounter-sim.md`
근거: [밸런스 방법론](../../balance-method.ko.md) §1·§3·§8 · 선행: [1층 절차 생성기](2026-09-22-floor-generator-design.md)

## 0. 목표

1. 절차 맵 없이 **고정 아레나**에서 `조우 구성 × 파티 인원 × 빌드 × 봇 정책 × 행동 규칙`을 같은 시드 묶음으로 돌려 표를 만드는 도구.
2. 그 도구로 **행동 경제 세 안(현행 / A / B)** 을 1·2·3인에서 비교하고, 사전 고정된 결정 규칙에 따라 하나를 채택하는 보고서 `docs/balance/action-economy.md`.

범위 밖: 원정 단위 시뮬(기존 `solo_balance.gd`), 환산표 채우기(2단계), 승인 구성 목록(3단계), UI.

## 1. 원칙

- 전투 규칙을 복제하지 않는다. 실제 `Session`·`MonsterAI`·`EncounterBuilder`·`continuous_floor` 경로를 그대로 호출한다.
- 모든 실행은 `(config, seed)`로 결정론적이다. 같은 시드의 반복은 새 표본이 아니다.
- 실험 규칙(행동 경제)은 **세션 규칙 딕셔너리**로 켜고 끈다. 기본값은 현행과 동일하며, 규칙 미지정 세션은 지금과 한 바이트도 다르게 동작하지 않는다(기존 24개 스위트로 확인).
- 결정 규칙은 실측 전에 문서에 고정한다(§6). 결과가 나온 뒤 규칙을 바꾸지 않는다.

## 2. 세션 확장

### 2.1 파티 인원

`Session._init(p_seed, p_boss_trial, p_companions, p_floor, p_party_size := 0)`.
`p_party_size > 0`이면 그 수(1~3)만큼 `make_actor`하고 `companions = p_party_size > 1`. `0`이면 기존 규칙(2 if companions else 1 if boss_trial else 3). 이름 배열 `["아린","브란","세라"]`를 그대로 쓴다.

### 2.2 규칙 딕셔너리

```gdscript
var rules_config: Dictionary = {"solo_actions": 1, "solo_max_members": 0}
```

| 키 | 값 | 효과 |
| --- | --- | --- |
| `solo_actions` | 1(현행) / 2(A안) | 연속 층에서 파티 인원이 1일 때 `action_budget()`이 이 값을 돌려준다. 2일 때 `finish_player_action()`은 선택 배우의 `ap`가 0이 되었을 때만 `end_round()`를 부른다(중간 행동 후에는 관측·기습만 갱신). |
| `solo_max_members` | 0(제한 없음, 현행) / 2(B안) | `EncounterBuilder.fill(rng, depth, budget, ood, max_members := MAX_MEMBERS)`에 넘길 상한. 파티 인원 1일 때 `continuous_floor.build()`가 이 값을 사용한다. 0이면 `MAX_MEMBERS`. |

`rules_config`는 `depart()` 전에 설정하고 출정 중 바꾸지 않는다. UI는 이번 범위에서 노출하지 않는다.

`solo_actions == 2`일 때의 주의: `use_supply()`·`Curios.resolve()`·`Objective.pickup()`은 `ap -= 1` 후 `finish_player_action()`을 부르므로 그대로 두면 라운드가 끝나지 않고 두 번째 행동을 기다린다 — 의도된 동작. 동료(`companions`)의 행동은 라운드 종료 직전에 한 번 처리되는 현행 구조를 유지한다.

### 2.3 `continuous_floor.build()` 분리

```gdscript
func build(s) -> void:            # 기존: generate 후 apply
	var theme := Generator.theme(theme_id)
	apply(s, theme, Generator.generate(theme, s.seed_value+s.expedition_number*7919, int(theme.depth)))

func apply(s, theme: Dictionary, p_layout: Dictionary) -> void:   # 레이아웃 소비만
```

`apply`는 지금 `build`의 본문 전체(타일·적·feature·파티 배치·`Objective.register`·`rooms`·`phase`·`observe`·`ambush`)다. `layout.relic`이 `(-1,-1)`이면 `Objective.register`를 건너뛰고 `s.objective = {}`로 둔다(아레나에는 유물이 없다).

## 3. 아레나 (`expedition/sim/encounter_arena.gd`)

정적 함수 `layout(spec: Dictionary, theme: Dictionary) -> Dictionary`가 §7 계약과 같은 딕셔너리를 만든다.

입력 `spec`:

```json
{"size": 20, "room": [5, 5, 9, 9], "door": [9, 4], "pillars": [[8, 8], [10, 10]],
 "party_entry": [9, 5], "light": 90,
 "members": [{"species_id": "dcss_hobgoblin", "role": "MELEE", "pos": [9, 12]}, ...]}
```

- `terrain`: 전부 `wall`, `room` 사각형(내부 좌표·크기) 안은 `stone`, `pillars`는 `wall`, `door`와 `party_entry`에서 방까지의 직선 통로는 `stone`.
- `rooms`: 방 하나(`kind:"fight"`, `doors:[door]`, `tier:"deep"`, `spine:true`).
- `encounters`: 하나. `members`는 `EncounterBuilder.member(row, role)`로 만들어 `display_name`·`max_health`·`threat`를 채우고 `pos`를 그대로 쓴다. `pos`가 없으면 `EncounterBuilder.place()`로 배치한다.
- `entry`: `party_entry`. `relic`: `(-1,-1)`. `features`: `{}`. `stats`: 0.

파티는 `entry`에서 시작하고(`apply`가 `entry+(0,i)`로 세운다), 밝기는 `s.light = spec.light`로 세션에 직접 넣는다.

파티는 방 안 첫 줄(문 열 아래)에서 시작하고, 적이 보이지 않으면 봇이 방 중앙 쪽으로 한 칸씩 접근한다 — 실제 플레이에서 기둥 뒤의 적을 찾아 방으로 들어서는 행동을 모델링한다.

## 4. 봇 정책 (`expedition/sim/bot_policy.gd`)

한 라운드의 플레이어 행동을 실행하는 정적 함수. 세션의 공개 행동 API만 쓴다.

| 정책 | 행동 |
| --- | --- |
| `simple` | 보이는 적이 있으면 `auto_attack()`, 실패 시 `act("WAIT")`. 회복·스킬 없음. |
| `tactical` | `solo_balance.gd`의 전투 중 규칙을 옮긴다: HP<14 물약(`use_supply(0)`), HP<10 붕대(`use_supply(5)`), 아니면 `auto_attack()`; 추가로 적이 2마리 이상 인접하면 `GUARD`(`act("GUARD", pos)`)를 한 라운드에 한 번 사용. 회복품은 spec의 `supplies`로 준다. |

공통: 보이는 적이 없으면 조우 방 중앙으로 한 칸 이동(`TurnCore.path`). 두 정책 모두 이 단계를 먼저 거친다(전술 정책은 회복·방어 판단 뒤).

정책은 `step(s) -> bool`(행동을 수행했으면 true)만 제공하고, 라운드 진행은 세션이 한다. 동료는 세션의 기존 자동 행동을 따른다.

## 5. 실행기와 통계 (`expedition/sim/encounter_runner.gd`)

```gdscript
static func run_one(config: Dictionary, seed: int) -> Dictionary
static func run_many(config: Dictionary, seeds: Array) -> Dictionary
```

`config` = `{"arena": spec, "party_size": 1..3, "build": build_id, "policy": "simple"|"tactical", "rules": rules_config, "supplies": [..6], "max_rounds": 60}`.

`run_one`:
1. `Session.new(seed, true, party_size > 1, true, party_size)`; `s.rules_config = config.rules`; 빌드 적용(§5.1); `s.supplies = config.supplies`.
2. `Floor.apply(s, theme, Arena.layout(config.arena, theme))`; `s.light = spec.light`.
3. 라운드 루프: `while s.phase == "BATTLE" and s.round_number <= max_rounds`: 정책 `step(s)`; 정책이 false를 두 번 연속 돌려주면 `act("WAIT")`. 적이 모두 죽으면 `WIN`으로 종료(연속 층은 승리로 phase가 바뀌지 않으므로 `s.enemies.all(hp<=0)`를 검사). `s.phase != "BATTLE"`이면 `DEFEAT`. `max_rounds` 초과는 `TIMEOUT`.
4. 결과: `{"result", "rounds", "damage_taken": [개인별], "hp_end": [개인별], "deaths": [id...], "first_death_round", "heals_used", "guards_used", "damage_before_first_action", "enemy_damage_dealt": {enemy_id: amount}}`.
   `damage_taken`은 `damage()`가 남기는 `effects`를 라운드마다 수거해 합산한다(시작 HP−종료 HP가 아니라 실제 누적 피해).

`run_many`: 시드마다 `run_one`, 집계: 결과별 개수, 승률과 Wilson 95% 신뢰구간, 피해·라운드의 평균·표준편차·중앙값·p90·p95(결과별과 전체), 개인별 평균 피해, 사망 분포, 회복 사용 평균.

### 5.1 기준 빌드 (`data/content/reference_builds.json`)

```json
{"builds": [
 {"id": "starter", "label": "시작 장비형", "ranks": {}, "stats": {}, "equipped": ["PUSH","GUARD"], "learned": []},
 {"id": "melee_1", "label": "근접형", "ranks": {"MELEE": 1}, "stats": {}, "equipped": ["PUSH","GUARD"], "learned": []}
]}
```

적용: 파티 전원에게 `actor.growth.ranks`/`stats`를 덮어쓰고 `learned_abilities`/`equipped_abilities`를 설정한다. 이번 단계는 빌드 2개만 정의한다(4개는 2단계).

### 5.2 기준 조우 (`data/content/balance_experiments.json`)

`action_economy` 실험 하나를 정의한다.

```json
{"experiments": {"action_economy": {
  "seed_set": {"id": "S1", "start": 1000, "count": 200},
  "party_sizes": [1, 2, 3],
  "builds": ["starter", "melee_1"],
  "policies": ["tactical"],
  "rules": {"current": {"solo_actions": 1, "solo_max_members": 0},
            "A":       {"solo_actions": 2, "solo_max_members": 0},
            "B":       {"solo_actions": 1, "solo_max_members": 2}},
  "supplies": [1, 0, 0, 0, 0, 1],
  "arenas": {
    "early_hob":   {"tier": "early", "members": [["dcss_hobgoblin","MELEE"]]},
    "early_pair":  {"tier": "early", "members": [["kobold","MELEE"],["dcss_rat","MELEE"]]},
    "deep_mixed":  {"tier": "deep",  "members": [["dcss_hobgoblin","MELEE"],["goblin","RANGED"],["kobold","MELEE"]]},
    "deep_caster": {"tier": "deep",  "members": [["dcss_orc","MELEE"],["goblin","CASTER"]]},
    "opt_archers": {"tier": "optional", "members": [["kobold","RANGED"],["goblin","RANGED"],["dcss_rat","MELEE"]]},
    "opt_gnoll":   {"tier": "optional", "members": [["dcss_gnoll","MELEE"],["dcss_rat","MELEE"],["dcss_rat","MELEE"]]}
  }}}}
```

아레나 공통: `size 20`, `room [5,5,9,9]`, `door [9,4]`, `pillars [[8,8],[10,10]]`, `party_entry [9,5]`, `light 90`. `members`의 `pos`는 `EncounterBuilder.place()`가 정한다(앵커 없음 → 문에서 가장 먼 칸). B안에서는 3마리 구성의 마지막 멤버를 잘라 2마리로 만든다(`solo_max_members`가 조우 생성이 아니라 주어진 구성에 적용되는 경우의 규칙; 파티 인원 1일 때만).

솔로 HP 스케일(`SOLO_HP_PERCENT` 등)은 파티 인원 1일 때 `apply`에서 현행대로 적용된다. 이는 실험 조건의 일부이며 표 머리말에 기록한다.

## 6. 실험 보고서와 결정 규칙

`tests/action_economy.gd`(수동 실행 도구, CI 제외)가 §5.2 행렬 전체를 돌려 `docs/balance/action-economy.md`와 `docs/balance/action-economy.json`을 쓴다. 보고서 구성:

1. 머리말: 커밋, 날짜, 시드 묶음, 솔로 HP 스케일, 봇 정책 버전, 아레나 정의.
2. 표 1 — 규칙 × 인원 × 아레나: 승률(CI), 평균 개인별 피해, p95 피해, 평균 라운드, 첫 사망 라운드 중앙값.
3. 표 2 — 규칙별 결정 규칙 판정.
4. 채택안과 근거, 또는 보류와 추적 계획.

**결정 규칙(사전 고정, 밸런스 방법론 §8-1과 동일)**: 후보 규칙은 아래를 모두 만족해야 한다.
- (a) 솔로(1인) 심부 아레나 2개의 승률이 각각 ≥ 70% (tactical 정책, melee_1 빌드).
- (b) 2인 파티의 개인별 평균 피해가 같은 아레나의 솔로보다 낮다(심부 2개 모두).
- (c) 3인 파티의 심부 승률이 각각 ≥ 90%.
만족하는 후보가 여럿이면 현행과의 변경 폭이 작은 순(현행 > B > A)으로 채택한다. 없으면 **보류**로 기록하고, 사망 원인(순간 피해·행동 순서·회복 시점)을 표 1의 첫 사망 라운드·p95 피해로 서술한다. 도구는 판정을 자동 계산해 출력하되 **채택 확정은 사람이 보고서를 읽고 한다**.

## 7. 검증

- `tests/encounter_sim.gd`(CI): 아레나 레이아웃이 §7 계약 키를 갖고 `validate()`의 방 도달성 검사 대상이 아님(방 하나·문 하나)을 확인; `run_one`이 결정론적(같은 시드 두 번 = 같은 결과 딕셔너리); `rules_config` 기본값 세션이 현행과 동일(기존 스위트 통과로 확인 + `action_budget()` 값 검사); `solo_actions=2`에서 두 행동 뒤에만 라운드가 넘어감; `solo_max_members=2`가 3마리 구성을 2마리로 자름; `party_size` 1·2·3 생성; 통계 함수(Wilson CI, 백분위) 고정 입력 검사; `simple`/`tactical` 정책이 아레나에서 30라운드 안에 끝남(TIMEOUT 아님). 실행 시간 목표 30초 이내(표본 20).
- `tests/action_economy.gd`(수동): 전체 행렬. 실행 시간을 보고서 머리말에 기록.
- 기존 24개 스위트 회귀 없음.

## 8. 범위 밖·후속

빌드 4개와 환산표(2단계), 승인 구성 목록과 생성기 연결(3단계), 부상·스트레스 시작 상태 변수, 통로·우회 아레나, UI에서의 규칙 노출. 채택된 규칙을 기본값으로 바꾸는 것은 보고서 승인 뒤 별도 커밋으로 한다.
