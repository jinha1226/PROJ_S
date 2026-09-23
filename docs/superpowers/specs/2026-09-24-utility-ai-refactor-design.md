# 동료 AI Utility 정식화 리팩터링 설계 (Codex 작업 지시서)

작성일: 2026-09-24 · 상태: 설계 확정 · 담당: Codex · 검수: Claude
근거: [태세 설계](2026-09-23-stances-design.md) · [전술 단순화](2026-09-24-simple-tactics-arena-design.md) · Dave Mark, *Infinite Axis Utility System* (GDC 2010/2013)

## 0. 목표와 비목표

**목표**: `expedition/tactical_action_selector.gd` + `expedition/stances.gd`의 손으로 쓴 점수(100+피해, 80, 60, 40…)를 **데이터로 정의된 고려 사항(consideration)·곡선·태세별 가중치**로 바꾼다. 그래서
1. 태세 하나 추가 = JSON 파일 하나,
2. 튜닝 = 숫자 편집(코드 수정 없음),
3. 모든 선택에 **설명**(상위 고려 사항 3개)이 붙어 결과 카드·로그·시뮬 보고서에서 "왜 그랬나"를 읽을 수 있고,
4. 성격·노브가 가중치 곱으로 한 자리에 모인다.

**비목표(절대 하지 않음)**:
- 행동을 바꾸지 않는다. 이것은 **구조 리팩터링**이다. 아래 §7의 동치 하네스와 기존 스위트가 회귀망이다.
- 규칙 목록(파츠 사용 순위·조건)·명령·후퇴선·실수 판정의 **단계 순서**는 바꾸지 않는다(§1).
- 파츠 수치, 몬스터 AI(`monster_ai.gd`), 세션 API, UI는 건드리지 않는다.
- 학습/모델 호출 없음. 결정론·정수 산술·모바일 성능 유지.

## 1. 현재 구조 (바꾸지 않는 뼈대)

`Tactics.choose(s, actor)`:
```
0. (호출자 auto_step) 명령 command_choice → 있으면 그것
1. 후퇴선: hp% ≤ retreat_hp → 거리 벌리기 MOVE(150) / 회복 파츠(+150) 중 최고
2. 실수: Stances.mistaken → HESITATE(WAIT) / RECKLESS(돌격 프로그램, posture 100) / REVERT(기본 태세로 4단계)
3. 규칙: rule_candidates(PUSH·GUARD·파츠) → rule_choice → 매칭되면 그것
   (거리형이 근접 접촉 중이면 range ≥ 3 파츠는 풀에서 제외)
4. 태세: Stances.candidates(s, actor, stance, knobs) → cohesion_shift → 최고 점수
```
리팩터링 대상은 **4단계 안쪽**(`Stances.candidates`의 charger/skirmisher/guardian과 점수)과 4단계에 더해지는 노브 조정(`cohesion_shift`, `attack_shift`)이다. 1~3단계는 그대로.

현재 4단계 점수 상수(보존해야 할 행동의 근거):

| 태세 | 후보 | 점수 |
| --- | --- | --- |
| CHARGER | 불 위 → 비-불 인접 칸 MOVE(즉시 반환) | 150 |
| | posture ≤ −60 & 예고 칸 위 → 안전 칸 MOVE(즉시 반환) | 60 |
| | 인접 적(자기 방어 우선, 공통 표적 우선) ATTACK | 100 + 피해 + posture·15/100 |
| | 표적 인접 칸으로 MOVE(경로 없으면 불 허용 → 최근접 적) | 80 |
| SKIRMISHER | 위험 회피 MOVE(예고·불 감소 칸) | 200 |
| | (원거리 파츠) 접촉 중 → 이탈 MOVE | 120 |
| | (원거리 파츠) 2..R → 인접 적 ATTACK / WAIT | 60 / 50 |
| | (원거리 파츠) > R → 접근 MOVE(접촉 칸 제외) | 80 |
| | (파츠 없음) hit_and_run → 이탈 MOVE | 120 |
| | (파츠 없음) 인접 ATTACK / 접근 MOVE | 100 / 80 |
| GUARDIAN | 위협 있음: 인접 위협 ATTACK | 100 + posture·15/100 |
| | 위협 있음: 가로막기 칸 MOVE | 130(치명) / 90 |
| | 위협 없음: 인접 적 ATTACK / 동반 전진 MOVE / WAIT | 60 / 50 / 40 |
| | 위협 없음, 보호 대상과 떨어짐: 합류 MOVE | 80 |
| 공통 | 모든 MOVE에 cohesion_shift = sign(Δ인접 아군)·cohesion·10/100 | |

## 2. 목표 구조

```
Consideration(id, input(s, actor, action) -> float 0..1, curve)   # 순수 함수
Action(kind, cell, tags[])                                         # 후보
Profile(stance) = { action_tag: { consideration_id: weight } }     # JSON
score(action) = Σ weight_i · curve_i(input_i)   (정수화: ×100 반올림)
personality multiplier: weight_i ×= mult(actor, consideration_id)  # 노브·성격
explain(action) = 상위 3 (consideration_id, input, contribution)
```

- **후보 생성기는 남긴다**(태세별로 "어떤 행동이 가능한가"는 프로그램 로직: 이탈 칸 계산, 가로막기 칸, 동반 전진 제약). 바뀌는 건 **점수 매기기**뿐이다. 즉 `Stances.candidates`는 후보에 `tags`를 달아 내고, 점수는 `Utility.score(profile, actor, action)`가 매긴다.
- **즉시 반환 규칙**(불 위 탈출, 신중 돌격형의 예고 회피)은 "게이트" 고려 사항으로 표현한다: 가중치가 매우 큰(≥ 1000) 단일 항 → 사실상 즉시 반환과 같다. 하네스로 동일성을 검증한다.
- 실수·후퇴선·규칙은 손대지 않는다.

## 3. 데이터 스키마 (`data/content/tactics_profiles.json`)

```json
{
  "content_schema_version": 1,
  "curves": {
    "linear": {"type": "linear"},
    "inverse": {"type": "linear", "invert": true},
    "step_1": {"type": "step", "at": 1.0},
    "quad_in": {"type": "poly", "power": 2}
  },
  "considerations": {
    "fire_here":        {"input": "tile_fire_here",      "curve": "step_1",  "doc": "내 칸이 불이면 1"},
    "telegraph_here":   {"input": "intent_on_me",        "curve": "step_1"},
    "target_adjacent":  {"input": "adjacent_to_target",  "curve": "step_1"},
    "any_foe_adjacent": {"input": "adjacent_to_any_foe", "curve": "step_1"},
    "damage":           {"input": "preview_damage_norm", "curve": "linear",  "doc": "예상 피해/40"},
    "closes_distance":  {"input": "distance_delta_norm", "curve": "linear",  "doc": "표적까지 거리 감소량/2"},
    "opens_distance":   {"input": "distance_gain_norm",  "curve": "linear"},
    "in_band":          {"input": "in_ranged_band",      "curve": "step_1",  "doc": "2..R 안이면 1"},
    "cell_danger":      {"input": "danger_at_cell_norm", "curve": "inverse", "doc": "도착 칸 위험/20, 뒤집음"},
    "ally_delta":       {"input": "adjacent_ally_delta", "curve": "linear",  "doc": "-1..1 → 0..1"},
    "protectee_gap":    {"input": "between_threat_and_protectee", "curve": "step_1"},
    "protectee_lethal": {"input": "protectee_lethal",    "curve": "step_1"},
    "protectee_near":   {"input": "protectee_within_keep","curve": "step_1"},
    "hp_ratio":         {"input": "own_hp_ratio",        "curve": "linear"}
  },
  "profiles": {
    "CHARGER": {
      "MOVE:fire_escape":  {"fire_here": 1500},
      "MOVE:sidestep":     {"telegraph_here": 60},
      "ATTACK":            {"any_foe_adjacent": 100, "damage": 40, "posture": 15},
      "MOVE:approach":     {"closes_distance": 80}
    },
    "SKIRMISHER": { "...": "§5 표대로" },
    "GUARDIAN":   { "...": "§5 표대로" }
  },
  "personality": {
    "cell_danger":  {"knob": "posture", "scale": -0.3},
    "ally_delta":   {"knob": "cohesion", "scale": 0.1},
    "damage":       {"knob": "posture", "scale": 0.15}
  }
}
```

- `action_tag`는 `kind` 또는 `kind:subtag`(후보 생성기가 붙임: `fire_escape`, `sidestep`, `approach`, `disengage`, `hold`, `rejoin`, `advance`, `block`). 프로필에 없는 태그의 후보는 점수 0.
- `posture`/`cohesion`은 고려 사항이 아니라 **노브 곱셈**: `personality[cid].knob`의 값(−100..100)을 `scale`로 곱해 가중치에 더한다(`weight += knob·scale`). 현재 `attack_shift = posture·15/100`, `cohesion_shift = sign(Δ)·cohesion·10/100`와 같은 값이 나오도록 맞춘다.
- 실수의 RECKLESS는 `posture = 100`으로 CHARGER 프로필을 쓰는 것으로 그대로 표현된다.

## 4. 코드 구조

| 파일 | 역할 |
| --- | --- |
| `expedition/utility.gd` (신규) | `load_profiles()`, `curve(name, x)`, `inputs(s, actor, action) -> Dictionary`(모든 input id 계산, 순수), `score(profile, actor, action, knobs) -> {score:int, explain:Array}` |
| `expedition/stances.gd` | 후보 생성만 남김(`candidates`가 `tags`를 붙인 후보 반환, 점수 없음). `party_target/protectee/threats_to/steps_toward/adjacent_foe/mistake_*`는 그대로 |
| `expedition/tactical_action_selector.gd` | 4단계에서 `Utility.score`로 점수·설명을 붙이고 `rank`로 선택. `cohesion_shift/attack_shift/KNOB` 삭제(프로필로 이동). 1~3단계 불변 |
| `data/content/tactics_profiles.json` | §3 |
| `tests/utility.gd` (신규, CI) | 곡선 수학, 프로필 로딩·스키마 검증(모든 태그·고려 사항 id가 존재), `inputs` 값(고정 상황), 설명이 상위 3개인지, 노브 곱셈이 기존 값과 동일 |
| `tests/selector_diff.gd` (신규, 수동) | §7 동치 하네스 |

`choice` 딕셔너리에 `explain: [{"id": "target_adjacent", "input": 1.0, "contrib": 100}, …]`를 싣는다(상위 3). `reason` 문자열은 유지하되 끝에 ` · ` + 상위 1개 id의 한국어 이름(`doc`)을 붙인다 — 결과 카드·로그가 바로 쓴다.

## 5. 현재 점수 → 프로필 매핑 (동치 보장표)

Codex는 이 표대로 프로필을 채우고, 하네스로 동일성을 확인한다. 값이 안 맞으면 **프로필을 고친다**(코드 상수 부활 금지).

| 현재 후보(점수) | 태그 | 프로필 항 |
| --- | --- | --- |
| CHARGER 불 탈출(150, 즉시) | `MOVE:fire_escape` | `fire_here` 1500 (게이트) |
| CHARGER 예고 회피(60, posture ≤ −60 즉시) | `MOVE:sidestep` | `telegraph_here` 60 + 게이트 조건은 후보 생성기가 유지(posture ≤ −60일 때만 후보 생성) |
| CHARGER ATTACK(100+피해+posture·15/100) | `ATTACK` | `any_foe_adjacent` 100, `damage` 40(피해/40×40 = 피해), personality `damage: posture×0.15` |
| CHARGER 접근(80) | `MOVE:approach` | `closes_distance` 80 |
| SKIRMISHER 위험 회피(200) | `MOVE:escape` | `cell_danger` 200 (도착 칸 위험 < 현재 위험일 때만 후보) |
| SKIRMISHER 이탈(120) | `MOVE:disengage` | `opens_distance` 120 |
| SKIRMISHER 반격(60)/유지(50) | `ATTACK:poke` / `WAIT:hold` | `any_foe_adjacent` 60 / `in_band` 50 |
| SKIRMISHER 접근(80) | `MOVE:approach` | `closes_distance` 80 |
| 치고 빠지기 타격(100)/이탈(120)/접근(80) | `ATTACK` / `MOVE:disengage` / `MOVE:approach` | 100 / 120 / 80 (같은 고려 사항) |
| GUARDIAN 인접 위협 ATTACK(100+posture·15/100) | `ATTACK:intercept` | `any_foe_adjacent` 100 + personality posture |
| GUARDIAN 가로막기(130/90) | `MOVE:block` | `protectee_gap` 90 + `protectee_lethal` 40 |
| GUARDIAN 인접 적(60)/전진(50)/대기(40) | `ATTACK` / `MOVE:advance` / `WAIT:hold` | 60 / 50 / 40 |
| GUARDIAN 합류(80) | `MOVE:rejoin` | `closes_protectee` 80 (고려 사항 추가) |
| 모든 MOVE cohesion_shift | (모든 `MOVE:*`) | personality `ally_delta: cohesion×0.1` (Δ의 부호만 → `ally_delta` input을 sign으로) |

동률 규칙(`rank`: 점수 → `str(kind)+str(cell)`)은 그대로.

## 6. 성능·결정론

- 액터당 후보 ≤ 20, 고려 사항 ≤ 15 → 라운드당 수백 번의 곱셈. 문제없음. `inputs()`는 후보마다 한 번 계산하되 액터 공통 입력(`own_hp_ratio`, `intent_on_me`, `fire_here`)은 한 번만.
- 점수는 `int(round(Σ·1))`로 정수화; 부동소수 누적 순서를 고정(고려 사항 id 정렬 순).
- 프로필 JSON은 `static var`로 한 번 로드. 시뮬(수천 전투)에서 파일 I/O 반복 금지.

## 7. 검증 — 동치 하네스와 회귀망

1. **`tests/selector_diff.gd`(수동)**: 리팩터링 전 선택기를 `expedition/legacy/tactical_action_selector_v1.gd`로 복사해 두고, 아레나 6종 × 태세 빌드 4종(`stance_*`) × 시드 40 × 최대 40라운드에서 매 라운드·매 멤버의 `(kind, cell)`을 두 선택기로 계산해 비교. **동일률 ≥ 99.5%**, 차이는 `docs/balance/selector-diff.md`에 (아레나, 시드, 라운드, 멤버, 옛 선택, 새 선택, 새 explain) 표로 전부 기록. 차이가 있으면 프로필을 고쳐 없앤다. 100%가 목표이고 0.5%는 부동소수 동률 뒤집힘의 여유다.
2. 기존 CI 스위트 전부 통과(특히 `stances` 95+, `autobattle`, `protect`, `companion_tactics`, `skill_rule_conditions`, `encounter_sim`), `solo_balance` ≥ 3/8(현재 4/8, 같은 값이어야 정상).
3. `tests/utility.gd`(CI에 추가): §4의 항목.
4. 완료 후 `legacy/…_v1.gd`와 `selector_diff.gd`는 삭제하지 않는다(다음 튜닝 라운드의 회귀 도구).

## 8. 작업 순서 (Codex)

1. 옛 선택기 복사(`legacy/tactical_action_selector_v1.gd`, `stances_v1.gd`) + `selector_diff.gd` 하네스 먼저 — **리팩터링 전에 100% 동일이 나와야** 하네스가 맞는 것.
2. `utility.gd` + JSON + `tests/utility.gd`(곡선·로딩·입력값).
3. `Stances.candidates`에 태그 달기(점수 제거), `Tactics.choose` 4단계를 `Utility.score`로. `KNOB`·`cohesion_shift`·`attack_shift` 삭제.
4. 하네스 돌려 차이 0으로 수렴 → 보고서 → CI 전체 → 커밋.
5. `choice.explain`을 `battle_stats`에 실어 결과 카드에 "주요 판단" 한 줄(선택 사항; UI는 Claude가 Task 2·3에서 손대는 중이므로 **`battle_hud.gd`/`main.gd`는 건드리지 않고** 세션 데이터만 채운다).

## 9. 경계 (충돌 방지)

- Codex 소유: `expedition/utility.gd`, `expedition/stances.gd`(후보 생성 부분), `expedition/tactical_action_selector.gd`, `data/content/tactics_profiles.json`, `expedition/legacy/*_v1.gd`, `tests/utility.gd`, `tests/selector_diff.gd`, `docs/balance/selector-diff.md`.
- Claude가 동시에 편집 중(만지지 말 것): `expedition/main.gd`, `character_ui.gd`, `battle_hud.gd`, `settlement_hub.gd`, `expedition/arena_setup.gd`(신규), `session.gd`(`arena_test` 추가 예정 — Codex는 `session.gd`를 수정하지 않는다; 필요하면 `Utility`가 세션을 읽기만 한다), `tests/arena_mode.gd`.
- 공유 파일 `tests/stances.gd`: Codex는 **기존 검사를 바꾸지 않고**(행동 동일이므로 바꿀 이유가 없어야 함) 필요한 검사만 끝에 추가한다. 충돌 시 Claude가 머지한다.
- 브랜치: `feat/utility-ai`를 `origin/main`에서 분기, 완료 시 PR 또는 알림. 커밋 작성자 `jinha1226 <jinha1226@gmail.com>`.
- 실행은 헤드리스만(`godot --headless --path . --script res://tests/<name>.gd`). Godot 창을 띄우지 않는다.
