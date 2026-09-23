# 동료 AI: Utility 선택기 + 예고 룩어헤드 설계 (v2)

작성일: 2026-09-24 · 상태: 설계 확정 · 구현 계획: `docs/superpowers/plans/2026-09-24-utility-lookahead.md`
대체: `2026-09-24-utility-ai-refactor-design.md`(v1, "행동 보존" 전제)는 이 문서로 **폐기**한다. v1의 결함(동치표가 동치가 아님, 즉시 반환을 점수로 대체, 1~3단계에서 쓰는 헬퍼 삭제, 설명을 `reason`에 덧붙임)은 Codex 검토에서 지적된 대로이며 여기서 고쳤다.
근거: [태세 설계](2026-09-23-stances-design.md) · [전술 단순화](2026-09-24-simple-tactics-arena-design.md) · Dave Mark, Infinite Axis Utility (GDC 2010/2013) · Pennycook `godot-utility-ai`(구조 참고) · 턴제 전술 AI의 시뮬레이션 기반 평가

## 0. 결정 사항과 원칙

1. **행동 보존이 아니라 전환이다.** 손으로 쓴 점수(100+피해·80·60·40…)를 **고려 사항 × 곡선 × 태세 가중치**로 바꾸고, 행동이 바뀌는 곳은 **바뀐 이유를 테스트로 다시 쓴다.** 회귀망은 동치 하네스가 아니라 (a) 행동 계약 테스트(`tests/stances.gd`·`autobattle`·`protect`), (b) 태세 구분 게이트(G7·솔로), (c) 전투 시험 모드에서 눈으로 확인, 이 셋이다.
2. **유지하는 단계 순서**: 명령 → 후퇴선 → 실수 → **효용 선택(태세 후보 + 파츠 후보를 한 풀에서)**. 파츠 규칙의 "무조건 선점"은 없앤다 — 파츠는 후보로 경쟁하고, 파츠 데이터의 `rule_when`은 **강한 고려 사항**으로 작동한다(엄호는 아군 치명 위기일 때, 밀치기는 적이 예고 중일 때 점수가 급등). 플레이어 규칙 편집은 이미 UI에서 빠졌으므로 `actor.rules`는 파츠별 조건 데이터로만 남는다.
3. **룩어헤드는 고려 사항이다.** 후보 행동을 취한 뒤 "예고(intent)대로 한 라운드가 흘렀을 때" 나·아군·적의 예상 피해를 **예측기**로 계산해 고려 사항 값으로 넣는다. 세션 복제 없이(§3) 결정론·저비용. 완전 시뮬 복제는 후속 옵션.
4. **화면은 짧게, 설명은 데이터로.** `reason`은 기존 짧은 행동명 그대로. `explain`(상위 고려 사항 3개)은 `choice`와 `battle_stats`에 싣고 시뮬 보고서·진단 로그가 쓴다. UI는 이 문서 범위 밖.
5. **성격·태세가 선택에 실제로 영향을 준다**(Codex의 "모두 비슷해짐" 경고): 태세별 가중치 프로필이 다르고, 노브는 가중치 곱, 실수는 그대로. 태세 3종이 화면에서 구분되는지가 게이트다.
6. **왔다갔다 방지**: 직전 행동과 같은 종류·방향이면 가산(commitment). 진동 테스트(A-B-A-B 금지)를 둔다.
7. 결정론·정수 산술·모바일 성능 유지. 학습/모델 호출 없음(오프라인 튜닝은 별도).
8. 즉시 반환 규칙(불 위 탈출, 신중 돌격형의 예고 회피, 후퇴선, 실수)은 **효용 이전 단계**로 남긴다 — 점수로 흉내 내지 않는다.

범위 밖: UI 변경, 파츠 수치, 몬스터 AI, 세션 복제형 완전 시뮬 룩어헤드(§3.4에 후속으로 명시).

## 1. 파이프라인 (`Tactics.choose`)

```
0. 명령 command_choice (호출자 auto_step)                      [불변]
1. 불 위면 비-불 인접 칸으로 이동 (모든 태세)                     [기존 돌격형 규칙을 공통으로 승격]
2. 후퇴선: hp% ≤ retreat_hp → 후퇴 풀(거리 벌리기·회복 파츠)     [불변]
3. 실수: HESITATE→WAIT / RECKLESS→돌격 프로필·posture 100 / REVERT→기본 태세로 4단계  [불변]
4. 후보 풀 = Stances.candidates(태세 프로그램, 태그 부착) ∪ Parts.candidates(장착 파츠·밀치기·엄호, 태그 PART)
5. 점수 = Utility.score(profile[stance], actor, candidate, knobs, ctx) → 정수; 동률은 rank(kind+cell) [불변]
6. 최고 후보 반환. choice.explain = 상위 3 고려 사항.
```

- `rule_choice`·`rule_candidates`의 선점은 제거. `Rules.matches`는 고려 사항 `rule_ready`의 입력으로 재사용(§2).
- 거리형 접촉 중 `range ≥ 3` 파츠 제외 규칙은 고려 사항 `contact_penalty`(접촉 중이면 1)로 표현하되 가중치를 크게(−1000) 둔다 — "제외"와 같은 효과, 데이터로.

## 2. 고려 사항 카탈로그

입력은 전부 `0..1`(정규화), 순수 함수 `Utility.inputs(s, actor, action, ctx) -> Dictionary`. `ctx`는 액터당 한 번 계산한 공통값(공통 표적, 보호 대상, 위협 목록, 내 HP%, 룩어헤드 기준선).

| id | 입력 | 뜻 |
| --- | --- | --- |
| `target_adjacent` | 도착/현재 칸에서 공통 표적에 인접 | 돌격형의 핵심 |
| `any_foe_adjacent` | 도착 칸에서 어떤 적이든 인접 | 자기 방어·접촉 |
| `damage` | 이 행동의 예상 피해 / 40 (ATTACK 미리보기, 파츠 정의 피해) | |
| `kill` | 예상 피해 ≥ 대상 HP | 처치 |
| `closes_distance` | (현재 거리 − 도착 거리) / 2, 표적 기준 | 접근 |
| `opens_distance` | (도착 − 현재) / 2 | 이탈 |
| `in_band` | 원거리 파츠가 있고 도착 칸이 2..R | 거리형 |
| `cell_danger` | 도착 칸 위험(예고 피해 + 불) / 20, 뒤집음(안전할수록 1) | 예고 회피 |
| `ally_delta` | 도착 칸 인접 아군 수 − 현재, −1..1 → 0..1 | 협동 |
| `protectee_near` | 도착 칸이 보호 대상과 Chebyshev ≤ keep | 호위 |
| `protectee_gap` | 도착 칸이 보호 대상과 위협 사이(가로막기 칸) | 호위 |
| `protectee_lethal` | 보호 대상이 치명 위기 | 엄호·가로막기 |
| `rule_ready` | 이 파츠의 규칙 조건(`Rules.matches`)이 지금 참 | 파츠 타이밍 |
| `contact_penalty` | 근접 접촉 중이고 파츠 range ≥ 3 | 거리형 제약 |
| `same_as_last` | 직전 라운드와 같은 kind이고, MOVE면 같은 방향(부호) | commitment |
| `la_self_hit` | 룩어헤드: 이 행동 뒤 내가 받을 예상 피해 / 내 HP, 뒤집음 | §3 |
| `la_ally_hit` | 룩어헤드: 아군 총 예상 피해 / 아군 총 HP, 뒤집음 | §3 |
| `la_enemy_hit` | 룩어헤드: 이 행동이 적에게 주는 피해 / 40 (damage와 같되 파츠 범위·밀치기 낙하 피해 포함) | §3 |
| `la_lethal_saved` | 룩어헤드: 이 행동으로 치명 위기에서 벗어나는 아군 수 / 3 (엄호·가로막기·밀치기 취소) | §3 |

> **`rule_ready` 수정 (Task 2·3 판정)** — 불리언이 아니라 등급이다: 목록에서 처음 맞는 규칙의 순위(`1.0 − 0.02·min(index,4)`, 스케일이 아니라 동점 처리) × 대상 선호(선호 대상 1.0, 아니면 0.8), 맞는 규칙이 없으면 0. 장착하지 않은 파츠의 규칙은 순위를 세기 전에 건너뛴다. 곡선은 `step`이 아니라 `linear`.
>
> **`cell_danger`·`la_self_hit`·`la_ally_hit` 수정 (Task 3 판정)** — 절대값이 아니라 **제자리 대비 부호 있는 차이**(곡선 `signed`, −1..1, 중립 0)다: 안전한 칸에 가만히 있는 것은 더 이상 보너스를 받지 못하고, 더 위험한 칸으로 가는 것이 실제 벌점이 된다. `docs/balance/utility-tuning.md` Task 3.

곡선: `linear`, `inverse`(1−x), `step`(x ≥ 1), `quad`(x²), `sqrt`, `signed`(−1..1로만 클램프). 각 고려 사항의 기본 곡선은 JSON에.

## 3. 룩어헤드 예측기 (`expedition/lookahead.gd`)

세션을 복제하지 않고, **공개 정보만으로** 한 라운드 뒤를 예측한다.

```
predict(s, actor, action) -> {"self": int, "allies": int, "enemies": int, "lethal_saved": int}
```

1. 행동 적용의 가상 효과: MOVE → 액터 위치를 도착 칸으로; ATTACK/파츠 → 대상 HP를 예상 피해만큼 감소(범위 파츠는 범위 내 전부, `allies_hit` 반영); PUSH → 대상 위치 이동 또는 8 피해, 대상의 intent 제거; GUARD → 대상의 `protected_by` = 나.
2. 그 가상 상태에서 각 파티원의 예상 피해 = `Rules.lethal_threat` 방식(예고 칸 피해 + 인접 근접 역할 피해 + 사선 안 원거리 피해 + 어둠 보너스) — 단 (1)에서 HP ≤ 0이 된 적은 제외, 엄호 재지정은 절반 계산.
3. `self` = 내 예상 피해, `allies` = 나 제외 파티원 합, `enemies` = (1)의 총 적 피해, `lethal_saved` = 행동 전 치명 위기였다가 행동 후 아니게 된 아군 수.
4. 비용: 후보당 O(파티 × 적). 라운드당 후보 ≤ 20 → 무시할 수준. `s.lookahead_enabled = true`가 기본; 시뮬 도구는 비교용으로 끌 수 있다.

**후속(범위 밖)**: 세션 복제 + `end_round` 실제 실행형 룩어헤드. 예측기와 결과 차이를 재는 하네스를 두면 언제든 교체 가능.

## 4. 프로필 데이터 (`data/content/tactics_profiles.json`)

```json
{
  "content_schema_version": 1,
  "considerations": { "<id>": {"curve": "linear"|"inverse"|"step"|"quad"|"sqrt", "doc": "…"} },
  "personality": {
    "cell_danger":  {"knob": "posture",  "scale": -0.30},
    "la_self_hit":  {"knob": "posture",  "scale": -0.30},
    "damage":       {"knob": "posture",  "scale":  0.15},
    "ally_delta":   {"knob": "cohesion", "scale":  0.10},
    "protectee_near": {"knob": "cohesion", "scale": 0.10}
  },
  "profiles": {
    "CHARGER": {
      "ATTACK":        {"any_foe_adjacent": 100, "damage": 40, "kill": 20, "la_enemy_hit": 20, "la_self_hit": 20, "same_as_last": 10},
      "MOVE:approach": {"closes_distance": 80, "cell_danger": 20, "la_self_hit": 20, "same_as_last": 10},
      "MOVE:sidestep": {"cell_danger": 60},
      "PART":          {"rule_ready": 120, "damage": 40, "kill": 20, "la_enemy_hit": 30, "la_lethal_saved": 200, "contact_penalty": -1000},
      "WAIT":          {}
    },
    "SKIRMISHER": {
      "MOVE:escape":    {"cell_danger": 200, "la_self_hit": 60},
      "MOVE:disengage": {"opens_distance": 120, "la_self_hit": 40},
      "MOVE:approach":  {"closes_distance": 80, "cell_danger": 40, "la_self_hit": 40},
      "ATTACK":         {"any_foe_adjacent": 60, "damage": 30, "kill": 20, "la_self_hit": 20},
      "WAIT:hold":      {"in_band": 50, "cell_danger": 20},
      "PART":           {"rule_ready": 140, "in_band": 40, "damage": 40, "kill": 20, "la_enemy_hit": 30, "la_lethal_saved": 200, "contact_penalty": -1000}
    },
    "GUARDIAN": {
      "ATTACK:intercept": {"any_foe_adjacent": 100, "damage": 30, "la_ally_hit": 40},
      "MOVE:block":       {"protectee_gap": 90, "protectee_lethal": 40, "la_ally_hit": 60, "la_lethal_saved": 100},
      "ATTACK":           {"any_foe_adjacent": 60, "damage": 20},
      "MOVE:advance":     {"closes_distance": 50, "protectee_near": 30, "la_ally_hit": 20},
      "MOVE:rejoin":      {"protectee_near": 80, "la_ally_hit": 20},
      "WAIT:hold":        {"protectee_near": 40},
      "PART":             {"rule_ready": 150, "la_lethal_saved": 300, "la_ally_hit": 60, "damage": 20, "contact_penalty": -1000}
    }
  }
}
```

- 태그는 후보 생성기가 붙인다: `MOVE:approach|sidestep|escape|disengage|block|advance|rejoin`, `ATTACK`, `ATTACK:intercept`, `WAIT:hold`, `PART`(kind는 파츠 id, tag는 `PART`; PUSH/GUARD도 PART).
- 가중치는 **출발값**이다. 계약 테스트와 게이트가 통과하도록 구현 태스크에서 조정하며, 바뀐 값은 커밋 메시지·`docs/balance/utility-tuning.md`에 기록한다.
- 노브 곱: `weight_eff = weight + knob·scale` (예: posture 100 → damage 40+15 = 55). 기존 `attack_shift(±15)`·`cohesion_shift(±10)`와 같은 크기.
- 점수 = `round(Σ weight_eff × curve(input))` 정수. 곱셈 집계(Dave Mark식)는 쓰지 않는다 — 우리 후보는 "해도 되는 것"이 이미 걸러져 있어 가산이 읽기 쉽다.

## 5. 후보 생성기 (`Stances.candidates` / `Parts.candidates`)

- 태세 프로그램의 **후보 목록**은 그대로(이탈 칸·가로막기 칸·동반 전진 제약·경로 대안). 점수 상수는 제거하고 태그만 남긴다. 접근은 동률 첫 걸음을 여러 개 낸다(cohesion이 고를 수 있게).
- `Parts.candidates(s, actor)`: 장착 파츠마다 `Abilities.legal`한 대상 칸 후보(밀치기의 이득 계산·엄호의 인접 아군 후보는 기존 `rule_candidates` 로직을 옮김; PUSH의 `benefit`은 `la_lethal_saved`·`la_ally_hit`로 대체). 범위 파츠의 아군 오사 후보는 생성하지 않는다(기존).
- 후보에 `last_action` 비교용으로 `dir`(MOVE의 방향 부호)을 싣는다.

## 6. 설명·계측

- `choice.explain = [{"id","input","weight","contrib"}, …3]`(contrib 내림차순). `reason`은 기존 짧은 이름.
- `auto_step`이 `battle_stats.members[id].explains`에 `{round, kind, cell, explain}`를 최근 20개까지 보관. 시뮬 러너 `run_one`에 `explains`(선택), `tests/skill_value.gd`/`stance_gate.gd`에 `--explain` 옵션으로 아레나별 상위 고려 사항 빈도 표 출력.
- UI는 건드리지 않는다(다음 단계에서 결과 카드 "주요 판단" 한 줄).

## 7. 검증

1. **행동 계약**: `tests/stances.gd`(109)·`autobattle`·`protect`·`skill_rule_conditions`·`companion_tactics`. 바뀌는 검사는 하나씩 "왜"를 커밋에 적는다. 예상되는 의도 변경: (a) 파츠가 규칙 선점이 아니라 경쟁 — `skill_rule_conditions`의 "규칙이 매칭되면 그 파츠를 쓴다"는 "규칙 조건이 참이면 파츠 점수가 가장 높다"로; (b) 예고 칸 회피가 태세별 가중치로(돌격형은 `cell_danger` 20 → posture ≤ −60 즉시 반환은 유지).
2. **새 테스트 `tests/utility.gd`(CI)**: 곡선 수학, 프로필 로딩·스키마 검증(모든 태그·id 존재, 태세 3종 전부), `inputs` 고정 상황 값, 점수 정수·결정론, explain 상위 3, 노브 곱이 ±15/±10과 동일, 룩어헤드 예측기(예고 칸으로 이동 → `la_self_hit` 하락, 엄호 → `la_lethal_saved` 1, 밀치기로 intent 취소 → `la_lethal_saved`), commitment(같은 방향 이동 가산), **진동 없음**(정지 상태 아레나에서 4라운드 A-B-A-B 금지).
3. **게이트**: `tests/stance_gate.gd`(혼합 ≥ 0.85 전 아레나 목표, 단일 태세 4/6 ≥ 0.6), `solo_balance ≥ 3/8`, `ranged_probe` 2인 결과가 이전(0.73/0.90/1.00) 이상. 미달 시 프로필 가중치만 조정(두 번), 기록.
4. **눈**: 전투 시험 모드에서 세 태세 × 아레나 3개를 보고 "역할이 보이는가" 체크리스트를 `docs/balance/utility-tuning.md`에 적는다(사용자 확인 항목).

## 8. 파일

| 파일 | 역할 |
| --- | --- |
| `expedition/utility.gd` (신규) | 곡선, 프로필 로딩, `inputs`, `score`, `explain` |
| `expedition/lookahead.gd` (신규) | `predict` |
| `expedition/parts_candidates.gd` (신규) | 파츠·밀치기·엄호 후보(기존 `rule_candidates` 이관) |
| `expedition/stances.gd` | 후보 태그화, 점수 제거 |
| `expedition/tactical_action_selector.gd` | 파이프라인 §1; `rule_choice`·`KNOB`·`attack_shift`·`cohesion_shift` 삭제(후퇴선의 회복 가중치는 상수로 남김) |
| `expedition/session.gd` | `last_action_kind/dir` 저장, `battle_stats.explains`, `lookahead_enabled` |
| `data/content/tactics_profiles.json` | §4 |
| `tests/utility.gd` 신규, 기존 스위트 수정, CI 목록 | §7 |
| `docs/balance/utility-tuning.md` | 가중치 변경 기록·게이트 결과·눈 체크리스트 |
