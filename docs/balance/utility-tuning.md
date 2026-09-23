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

## 눈으로 보는 체크리스트 (사용자 확인 항목)

전투 시험 모드에서 세 태세 × 아레나 3개를 보고 채운다. Task 4 이후에 기록한다.

- [ ] 돌격형이 표적에 붙어서 계속 때리는가
- [ ] 거리형이 접촉을 끊고 띠 안에 머무는가
- [ ] 호위형이 보호 대상과 위협 사이에 서는가
