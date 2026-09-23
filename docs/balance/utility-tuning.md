# Utility 프로필 튜닝 기록

`data/content/tactics_profiles.json`의 가중치는 [설계 §4](../superpowers/specs/2026-09-24-utility-lookahead-design.md)의
출발값에서 시작한다. 계약 테스트·게이트를 통과시키려고 바꾼 값은 전부 여기에 이유와 함께 적는다.

## Task 1 — 효용 핵심 (태세 후보)

| 변경 | 값 | 이유 |
| --- | --- | --- |
| `ally_delta` 를 모든 MOVE 태그에 0으로 추가 (`CHARGER/MOVE:approach`, `SKIRMISHER/MOVE:approach`, `GUARDIAN/MOVE:advance`, `GUARDIAN/MOVE:rejoin`) | 0 | 설계 §4의 `personality` 표에는 `ally_delta`가 있지만 어떤 프로필에도 들어 있지 않아 `cohesion` 노브가 아무 후보에도 닿지 않았다. 기본 가중치 0 + `cohesion × 0.10`이면 예전 `cohesion_shift`(cohesion ±100에서 ±10)와 같은 크기·같은 부호로 동률 걸음을 가른다. |

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

## 눈으로 보는 체크리스트 (사용자 확인 항목)

전투 시험 모드에서 세 태세 × 아레나 3개를 보고 채운다. Task 4 이후에 기록한다.

- [ ] 돌격형이 표적에 붙어서 계속 때리는가
- [ ] 거리형이 접촉을 끊고 띠 안에 머무는가
- [ ] 호위형이 보호 대상과 위협 사이에 서는가
