# Utility 프로필 튜닝 기록

`data/content/tactics_profiles.json`의 가중치는 [설계 §4](../superpowers/specs/2026-09-24-utility-lookahead-design.md)의
출발값에서 시작한다. 계약 테스트·게이트를 통과시키려고 바꾼 값은 전부 여기에 이유와 함께 적는다.

## Task 1 — 효용 핵심 (태세 후보)

| 변경 | 값 | 이유 |
| --- | --- | --- |
| `ally_delta`를 **모든 태세의 모든 MOVE 태그**에 0으로 추가 (`approach`·`sidestep`·`escape`·`disengage`·`block`·`advance`·`rejoin`) | 0 | 설계 §4의 `personality` 표에는 `ally_delta`(cohesion × 0.10)가 있지만 어떤 프로필에도 들어 있지 않아 `cohesion` 노브가 아무 후보에도 닿지 않았다. 기본 가중치 0이면 노브가 0일 때 순위에 영향이 없고, 노브를 켜면 모든 이동 후보가 함께 반응한다. |
| `GUARDIAN`에 `MOVE:approach`·`MOVE:sidestep` 열 추가 (CHARGER 값 복사) | CHARGER와 동일 | `Stances.candidates`는 호위 대상이 없는 호위형에게 돌격형 프로그램을 돌린다. 열이 없으면 그 후보들이 조용히 0점이 되어 이름 순으로 뽑힌다. `tests/utility.gd`의 (태세, 태그) 커버리지 검사가 이제 이 구멍을 잡는다. |

### `ally_delta`가 예전 `cohesion_shift`와 같지 않다는 점

같은 노브를 쓰지만 모양이 다르다. 숨기지 말고 Task 4에서 이 값을 기준으로 다시 잰다.

- 예전: `signi(delta) × cohesion × 0.10` → cohesion 100에서 `{−10, 0, +10}`, 폭 20.
  **접촉을 끊는 이동에 음의 값**이 붙었다.
- 지금: 유효 가중치 `0 + cohesion × 0.10`에 입력 `(delta+1)/2 ∈ {0, 0.5, 1}` → cohesion 100에서
  `{0, +5, +10}`, 폭 10. 벌점은 없고 보상만 있으며, 0.5의 상수 항은 같은 태그의 모든 후보에
  똑같이 실리므로 순위에는 영향을 주지 않는다.
- 즉 **부호는 같고 폭은 절반이며 이탈 벌점이 없다.** 스케일 0.10은 설계 §5가 못 박은 값이라
  이번 태스크에서는 건드리지 않는다.

### Task 1에서 파츠는 아직 효용 밖이다

파츠·밀치기·엄호는 여전히 `rule_choice`의 선점으로 뽑힌다(설계 §1의 제거 대상이지만 Task 2의 일이다).
그래서 이번에 삭제한 `attack_shift`(피해 파츠 + posture × 0.15)와 엄호의 cohesion 가산(+ cohesion × 0.20)은
**대체물이 없는 상태**다 — Task 2가 `PART` 프로필을 파이프라인에 넣을 때까지 파츠 선택은 성격을 읽지 않는다.

바꾸지 않은 것: 나머지 가중치는 설계 §4 그대로다. `la_*` 입력은 이 태스크에서 중립값(1.0/0.0)이라
`la_self_hit`·`la_ally_hit`는 아직 태그마다 상수를 더할 뿐이고(순위에 영향 없음), `la_enemy_hit`는 `damage`와 같은 값이다.
Task 3의 예측기가 들어오면 다시 잰다.

## 계약 테스트 결과 (Task 1)

| 스위트 | 결과 |
| --- | --- |
| `utility` | 85 checks, 0 failures (신규) |
| `stances` | 98 checks, 0 failures (변경 전과 같은 검사 수) |
| `autobattle` | 109 checks, 0 failures |
| `protect` | 38 checks, 0 failures |
| `skill_rule_conditions` | 962 checks, 0 failures |
| `companion_tactics` | 0 failures |
| `encounter_sim` | 0 failures |
| `parts` | 338 checks, 0 failures |
| `solo_balance` | 0 failures; 3/8 완주 (기준 ≥ 3/8) |

### 재측정 (검토 1차 수정 뒤)

| 스위트 | 결과 |
| --- | --- |
| `utility` | 127 checks, 0 failures (커버리지·commitment·in_band 검사 추가) |
| `stances` | 98 checks, 0 failures |
| `autobattle` | 109 · `protect` 38 · `skill_rule_conditions` 962 · `companion_tactics` · `encounter_sim` · `parts` 338 | 모두 0 failures |
| `solo_balance` | 0 failures; **4/8 완주** (3/8 → 4/8) |

솔로 완주가 하나 늘어난 것은 호위형이 호위 대상 없이 돌격형으로 돌 때 후보가 0점으로 뭉개지지 않게
됐고(`MOVE:approach`·`MOVE:sidestep` 열), `in_band`가 생성기와 같은 거리 척도를 쓰게 된 결과다.
가중치 자체는 설계 §4에서 더 움직이지 않았다.

## Task 2 — 파츠가 같은 풀로 들어오다

### `rule_ready`는 등급형이다 (설계 §2 수정)

`rule_choice`를 지우면 그 안에 있던 두 가지 약속이 같이 사라진다: **규칙 목록의 순위**와
**대상 선호**(`LOWEST_HP`/`NEAREST`/`ALLY`). 둘 다 계약 테스트가 지키는 것이라
(`skill_rule_conditions.gd`의 "follows the wound, not the order") 불리언 하나로는 표현할 수 없다.
그래서 `rule_ready`를 0..1 **등급**으로 바꿨다.

- 액터의 규칙을 목록 순서로 훑어 이 후보에 `Rules.matches`가 처음 참이 되는 규칙을 찾는다.
- 기본값 = `1.0 − 0.1 × min(index, 4)` — 1순위 1.0, 2순위 0.9, 5순위 이하 0.6.
- 그 규칙이 **고를 법한 대상**이면 ×1.0, 아니면 ×0.8. 선호는 같은 파츠의 형제 후보끼리만 비교한다
  (`LOWEST_HP`/`ALLY` → 최저 HP, 그 외 → 최단 거리, 동률은 칸 이름 오름차순).
- 맞는 규칙이 없으면 0.0.

형제 후보는 `Utility.context(s, actor, pool)`이 `ctx.pool`로 실어 나른다. 후보 하나를 재는 비용은
O(풀) — 라운드당 후보 20개면 무시할 수준이다.

**곡선도 같이 바뀐다.** 설계 §4의 `rule_ready` 곡선은 `step`이었는데, `step`은 `x ≥ 1`만 통과시켜
0.9·0.8 같은 등급을 전부 0으로 깎는다. `linear`로 바꿨다.

### 가중치: `PART` 열의 `rule_ready`

| 태세 | 설계 §4 | Task 2 | 왜 |
| --- | --- | --- | --- |
| CHARGER | 120 | **200** | 돌격형의 `ATTACK`은 `any_foe_adjacent` 100 + 피해/처치/`la_*`로 140~210이 나온다. 피해가 0인 파츠(밀치기·엄호)는 120으로는 기본 공격을 이길 수 없어 `parts.gd`·`protect.gd`의 "조건이 참이면 그 파츠" 계약이 깨진다. |
| SKIRMISHER | 140 | **320** | 거리형의 `MOVE:escape`는 `cell_danger` 200 + `la_self_hit` 60이고, posture가 신중할수록(−100) 320까지 오른다. `companion_tactics.gd`의 "a matched skill policy outranks the stance"가 이 값을 요구한다 — 예고 칸에서 도망치는 대신 밀쳐서 예고를 끊는 선택이다. |
| GUARDIAN | 150 | **200** | 돌격형과 같은 이유. 호위형 `PART` 열은 `la_ally_hit` 60이 중립값 1.0으로 상수처럼 붙어 있어 실질은 260이다. |

이 값들은 **Task 3 이전의 임시값**이다. `la_lethal_saved`·`la_ally_hit`가 실제 값을 내기 시작하면
엄호·밀치기가 스스로 점수를 벌게 되므로 `rule_ready`를 설계 §4의 120~150 쪽으로 다시 내리며 재측정한다.

### 잃어버린 것: 밀치기의 `benefit`/불 보너스

옛 `rule_candidates`는 밀치기에 `40 + benefit + bonus`를 매겼다(위협 감소량, 밀려난 칸의 불 차이,
밀 곳이 없을 때의 피해 8). Task 2는 이 수치를 **점수에서 뺐다** — 설계 §5대로 `la_ally_hit`·
`la_lethal_saved`가 대신할 자리이기 때문이다. 그 둘이 중립인 동안 밀치기는 `rule_ready` 하나로만
점수를 받는다. `benefit` 계산 자체는 남아 있다: "다른 아군의 사거리에서 적을 끌어내지 말 것"이라는
안전 검사의 절반이 그 값이다. 밀 곳이 없을 때의 피해 8은 후보의 `damage`로 들어가
`damage`·`kill`·`la_enemy_hit` 열이 읽는다.

### 계약 테스트는 한 줄도 지우지 않았다

`skill_rule_conditions`(962) · `parts`(338) · `protect`(38) · `stances`(98)는 **검사 수정 없이**
그대로 통과한다. `reason`에서 `"n순위 · "` 접두사가 사라졌지만 이를 읽는 검사는 없었다.

`tests/utility.gd`의 신규 `parts()`만 설계 브리프의 원문에서 한 줄을 고쳤다: 아군 치명 위기 장면에서
`f.foes[0].charging = true`를 뺐다. 예고 중인 적은 **밀치기의 기본 규칙(`CHARGING`)도** 참으로 만들고,
밀치기 규칙이 목록 1순위라 등급형 `rule_ready`에서는 밀치기(1.0)가 엄호(0.9)를 이긴다 — 규칙 순위가
지켜야 할 약속이므로 이쪽이 옳다. 예고 없이도 인접한 근접 적 + 예고 피해 9로 아군은 치명 위기이므로
장면의 뜻("아군이 죽을 상황이면 엄호")은 그대로다.

### 계약 테스트 결과 (Task 2)

| 스위트 | 결과 |
| --- | --- |
| `utility` | 134 checks, 0 failures (`parts()` 7 checks 추가) |
| `stances` | 98 checks, 0 failures |
| `autobattle` | 109 checks, 0 failures |
| `protect` | 38 checks, 0 failures |
| `skill_rule_conditions` | 962 checks, 0 failures |
| `parts` | 338 checks, 0 failures |
| `companion_tactics` | 0 failures |
| `encounter_sim` | 0 failures |
| `solo_balance` | 0 failures; **4/8 완주** (기준 ≥ 3/8, 기준선 4/8 유지) |

## 눈으로 보는 체크리스트 (사용자 확인 항목)

전투 시험 모드에서 세 태세 × 아레나 3개를 보고 채운다. Task 4 이후에 기록한다.

- [ ] 돌격형이 표적에 붙어서 계속 때리는가
- [ ] 거리형이 접촉을 끊고 띠 안에 머무는가
- [ ] 호위형이 보호 대상과 위협 사이에 서는가
