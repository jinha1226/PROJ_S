# 던전 2인 판단 시뮬레이터 행동 카탈로그

## 목적과 경계

첫 제품 범위는 두 인물이 같은 상황을 각자 독립적으로 평가하고, 선택한 두 행동을 동시에 해결하는 판단 실험실이다. 성격은 고정 archetype이 아니라 seed로 생성한 연속 HEXACO 여섯 축(H/E/X/A/C/O)으로만 저장한다. 감정 taxonomy를 새로 확정하지 않으며, `HELPED`, `HARMED`, `EXILED`는 상대에 대한 방향성 있는 사건 기억이다.

종족 관계 prior는 장기 기반값이다. 개인 기억 modifier는 `HELPED +15`, `HARMED -35`, `EXILED -55`, `NONE 0`으로 제한된다. 예를 들어 human↔goblin prior `-75`는 한 번 도움받은 `+15`보다 우세하다.

Registry에는 아래 다섯 intent만 등록된다. 각 definition은 base, legal term, score term, target role, 원자 동사로 구성된다. 중앙 selector는 action ID를 분기하지 않고 모든 definition을 같은 평가기로 처리한다. 결정론적 jitter는 `(seed, actor_id, turn, action_id)`마다 정확히 한 번, `-15..15` 범위로 더한다.

## 실행 중인 intent

| stable action_id | 원자 동사 | legal / 거절 사유 | 대상·자원 | 비용·기간 | 주요 점수 입력 | 관계 영향 | 동시 해결 | 상태 |
|---|---|---|---|---|---|---|---|---|
| `APPROACH` | `MOVE` | 거리 > 1 / 이미 공격 가능한 거리 | 상대, 상대 방향 | 한 턴에 거리 1 감소 | X, O, 종족 prior, 개인 기억, 현재 거리 | 직접 변경 없음 | 양쪽 이동 제안을 함께 적용하며 겹치면 인접에서 멈춤 | 구현·테스트됨 |
| `ENGAGE` | `MELEE` | 거리 ≤ 1, 무장, 상대 생존 / 거리·무장·생존 사유 | 상대, 무기 | 한 번의 근접 피해 | X(+), A(-), E(-), HP, 전력, 종족 prior, 기억, 적대도, 위협 | 피격자의 기억을 `HARMED`로 변경 | 상호 공격은 같은 선행 상태에서 피해를 산출한 뒤 함께 반영. 공격↔도주는 공격 후 생존한 도주자가 이동 | 구현·테스트됨 |
| `FLEE` | `MOVE` | 도주 공간, 상대 생존 / 공간·생존 사유 | 상대, 반대 방향 | 한 턴에 거리 1 증가 | E(+), X(-), 부상, 전력 열세, 종족 prior, 기억, 위협 | 직접 변경 없음 | 공격 피해를 먼저 함께 반영하고 생존자만 이동 | 구현·테스트됨 |
| `HOLD` | `WAIT` | 항상 합법 | 없음 | 한 턴 대기 | C(+), X(-), 불확실성, 관계 중립성 | 없음 | 다른 인물 행동에 간섭하지 않음 | 구현·테스트됨 |
| `SELF_TREAT` | `USE_ITEM` | 치료 도구 ≥ 1, 치료 필요도 ≥ 250 / 도구·필요도 사유 | 자신, 치료 도구 1개 | HP 12 회복, DOT 잔여 2 감소 후 같은 턴 DOT | C, E, 부상·DOT, 위협(-) | 없음 | 동시 공격 피해 이후, DOT tick 이전에 실행 | 구현·테스트됨 |

## 원자 동사

| stable verb | 입력 | 세계 효과 | 사건 |
|---|---|---|---|
| `MOVE` | target role `OTHER`, direction `TOWARD/AWAY` | 두 위치와 거리의 단일 canonical projection 갱신 | `ACTION`, `MOVE` |
| `WAIT` | target role `NONE` | 공간·HP·기억 변화 없음 | `ACTION` |
| `MELEE` | target role `OTHER`, 인접·무장 조건 | 결정론적 피해, HP/생존, 피격 기억 갱신 | `ACTION`, `DAMAGE`, `MEMORY`, 필요 시 `DEATH` |
| `USE_ITEM` | target role `SELF`, 치료 도구 | 자원 소비, HP 회복, DOT 잔여 감소 | `ACTION`, `HEAL`, 이후 필요 시 `STATUS_TICK` |

Definition validation은 원자 동사별 target 의미, 알려진 입력 ID, 최소 한 개 score term을 요구한다. 따라서 target 없는 `MELEE`, 자기 위치로 향하는 무의미한 `MOVE`, 알 수 없는 입력 오타, score가 없는 placeholder는 등록할 수 없다. 등록 시 definition을 deep-copy하므로 호출자가 원본을 바꿔도 catalog는 변하지 않는다.

## 점수 DTO

`decision_breakdowns()`는 인물마다 다섯 candidate를 반환한다. 각 candidate에는 다음이 들어간다.

- `legal`, 한국어 `rejection_reason`
- `base`
- `hexaco_terms`, `state_terms`, `relation_terms`, `context_terms`
- 각 term의 `input_value`, `weight_milli`, `contribution`
- action당 한 번의 `jitter`
- 모든 항의 합인 `total`
- `selected`, 한국어 `selected_reason_ko`

Preview는 snapshot, event, journal을 바꾸지 않는다. 같은 seed·turn·상태라면 두 인물의 후보표와 선택은 항상 같다.

## 상태이상과 사건 순서

지원 DOT는 `BLEEDING`, `POISONED`뿐이다. 둘 다 `tick_damage`, `remaining_quanta`를 가진 같은 단순 규칙으로 진행한다. 매 턴 순서는 `선택 기록 → 동시 MELEE 피해 → 생존 MOVE → SELF_TREAT → DOT tick → 사망 판정`이다. 장기 timer, 임의 생존 roll, 별도 전역 resentment 축은 없다.

## Future — registry 미등록

아래 항목은 설계 후보일 뿐 현재 코드 registry에 없고 실행되지 않는다. 필요해질 때 기존 입력 allowlist와 원자 동사로 완전히 표현할 수 있는지 먼저 확인하고, 불가능한 경우에만 protocol을 확장한다.

- `INVESTIGATE`, `SCAVENGE`
- `SEEK_HELP`, `AID`
- `HIDE`, `PURSUE`, `GUARD`
- 다턴 intent, 50인 population, 원거리 scheduler, event-queue LOD

placeholder definition은 등록하지 않는다.
