# 주인공 파티 전투불능 10턴 · 부축 도주 · 구조 후 대화 구현 계획

- 작성일: 2026-09-15
- 상태: 기존 코드 조사 및 구현 계획. 게임 코드 변경 전.
- 조사 기준: `living-world-legacy-integration`, commit `856b879`.
- 대상 경로: `project.godot` → `playtest/entry_router.gd`의 기본 `party_encounter_sandbox.tscn` → `PartyPlaytestSession` → `FieldTurnSystem`.
- `--rebuilt-demo`와 `--prototype-combat`는 별도 경로다. 기본 런타임에 붙이고 별도 데모에 중복 구현하지 않는다.
- 기존 추적 파일은 조사 시작 시 변경 없음. 다수의 미추적 import/UID/아트 파일은 보존한다.
- 사용자 요구: HP가 0이 되면 10턴 유예를 두고, 그 안에 적이 화면에서 사라지거나 동료를 부축해 도망갈 수 있게 한다. 기존 시스템부터 조사하고 구현 계획서를 먼저 작성한다.
- 이전 논의 포함: 주인공 영구 사망 시 회차 종료, 실제 구조 사건을 근거로 한 기억·성격 반응·휴식 대화. 이전 제안의 '부축 시작 즉시 무기한 안정화'는 이번 요구에 자동 적용하지 않는다.

## 1. 조사 결론

생명 상태·시간 처리·시야·동료 조작·감정/기억은 이미 있다. 단순히 상태 이름을 추가하는 작업이 아니다. 주인공 즉사와 동료 자동 회복을 바꾸고, 2인 이동 및 사망/저장 검증을 함께 수정해야 한다.

| 기능 | 현재 코드 근거 | 재사용/변경 |
|---|---|---|
| 생명 상태 | `sim/combatant_state.gd:4`의 ACTIVE/DOWNED/DEAD, downed_at/resolve_at/source_event_id | 상태 3종 재사용, 신 규칙·부축 연결 상태 추가 |
| HP 0 | `sim/systems/damage_system.gd:35`의 주인공 terminal_target; 치명상 시 downed 직후 died | 주인공 파티는 즉사를 없애고 유예 진입 |
| 다른 피해 경로 | `sim/systems/melee_combat_system.gd:298`, `sim/simulator.gd:633`, `sim/systems/environment_system.gd:309`, `sim/systems/status_lifecycle_system.gd:85` | 근접만 고치지 말고 모든 즉사 산출 경로에 공통 정책 적용 |
| 동료 자동 회복 | `sim/systems/status_lifecycle_system.gd:150`; 기존 deadline은 다음 100 경계 +100, HP 약 10% 회복 | 신규 파티는 안전 이탈 회복 또는 10턴 만료 사망으로 교체 |
| 시간제 턴 | `sim/systems/field_turn_system.gd:35`, `sim/systems/field_actor_queue.gd`, `docs/FIELD_TURN_COMBAT.ko.md` | 행동별 시간·사건 순서·전체 롤백 재사용 |
| 사망/파티 패배 | `sim/party_survival_rules.gd`, `sim/systems/party_encounter_coordinator.gd:91` | 현재 태그에 따라 주인공 비ACTIVE/전원 비ACTIVE를 패배 처리. DOWNED 유예와 영구 사망 분리 |
| 직접 조작 전환 | `playtest/party_playtest_session.gd:7209`, `sim/party_survival_rules.gd:8` | 전투불능 조작자 대신 생존 동료 선택. busy_until 대기도 처리 |
| 파티 공유 시야 | `sim/field_turn_rules.gd`, `sim/party_perception_registry.gd:29`, `sim/combat_kernel.gd` | 카메라 대신 시뮬레이션 LOS 재사용. DOWNED 때문에 관측자 0명이 되는 특수 사례 보완 |
| 기존 후퇴 | `playtest/party_playtest_session.gd:7330` | RETREAT 지시를 재사용하되 부축 대상과 이동 제약 추가 |
| 휴식 회복 | `sim/party_recovery_rules.gd`, `sim/exploration_recovery_rules.gd` | ACTIVE용 자연회복. 전투불능 회복과 분리하고 중복 회복 방지 |
| 기억/관계/판단 | `sim/party_memory_model.gd:45`, `sim/party_relationship_model.gd`, `sim/party_companion_appraisal.gd:70` | ALLY_DOWNED/ALLY_LOST/AID_RECEIVED 및 도움에 따른 보호 선호가 이미 존재 |
| 기억 표시 | `playtest/party_memory_presenter.gd` | 기존 기억 상세 보기를 재사용. 사건별 휴식 대화는 신규 |
| 영입용 구조 | `playtest/party_playtest_session.gd:4890` | 실제 life_state는 ACTIVE, 서사 상태만 COLLAPSED_STORY. 전투 중 구조 서비스로 사용 금지 |
| 저장/재생/검증 | `sim/world_state.gd:2315`, `playtest/party_playtest_session.gd:8194` 이후 | deadline 공식·주인공 사망·이벤트 인과를 엄격히 검증하므로 함께 버전 분기 |

최근의 이능 동시 제공 계획도 같은 party schema와 session journal을 변경할 예정이다. schema 번호를 지금 예약하거나 덮어쓰지 말고 구현 착수 시 최신 commit에 맞춰 합친다.

## 2. 사용자 확정 사항과 이 계획의 제안 사항

### 확정 사항

1. 주인공 파티의 HP 0은 즉시 사망이 아니다.
2. 유예는 10턴이다. 임의로 2턴/5턴 등으로 줄이지 않는다.
3. 그 사이 적이 화면에서 사라지는 이탈 조건과 부축 도주가 필요하다.
4. 죽은 인물은 부활하지 않는다. 주인공의 실제 사망은 회차 종료다.
5. 구현 전 조사·계획서가 이번 작업의 산출물이다.

### 아래는 구현 가능한 초안이며 사용자 확정 수치와 구분한다

| 미정 항목 | 계획서 기본안 | 이유/영향 |
|---|---|---|
| 10턴 시간 단위 | 기본 행동 100 ×10 = 1,000 world_time. 쓰러진 시각에 deadline=T+1000 | 기존 속도/지형 시간제 유지. '플레이어 입력 10회'와 다르므로 질문 전달함 |
| 화면에서 사라짐 | 카메라 밖이 아니라 파티의 공통 가시 적 목록이 비는 것 | 화면 회전·줌·UI 설정으로 회복되지 않도록 함 |
| 시야 이탈의 결과 | HP 1로 ACTIVE 회복, 부축 해제. 이후 기존 휴식 회복 적용 | 부축 시작만으로 회복시키지 않는다. 1HP는 초기 제안 |
| 부축 개시 | 인접 동료를 선택하는 ASSIST, 기본 100시간 | 이동과 별개로 한 행동 사용. 실행 시작 시 관계 연결 |
| 부축 이동 | 정상 이동 시간의 150%, 올림 | 도주 비용과 동료 구조의 선택을 만듦. 수치는 조정 가능 |
| 부축 중 유예 | 계속 감소; 개시·해제·교대로 리셋하지 않음 | 안전한 곳으로 데려가는 행위가 필요 |
| 전투불능 중 피해 | 신규 파티 DOWNED는 추가 피해로 유예를 단축하거나 즉사시키지 않음 | '10턴 유예'를 보장하는 기본안. 상태 만료와 피해 연출/기록은 별도 정합성 처리 |
| 환경 위험 중 회복 | 불/유해 지형 위에서는 안전 회복 보류 | 적이 없어도 즉시 재다운되는 반복 방지. 적 이탈 조건 외에 추가하는 제안임 |

10턴을 입력 10회로 선택하면 actor 수와 무관한 별도 카운터가 필요하다. 이동·공격·WAIT·아이템의 성공한 시간 소비 입력만 1회, 선택/실패/대화 0회, 쓰러진 입력은 차감하지 않는 방식으로 계약을 바꿔야 한다. 이 대안은 world_time deadline과 동시에 적용하지 않는다.

## 3. 생명 상태와 사건 순서

```text
ACTIVE --HP 0--> DOWNED(deadline=T+1000)
DOWNED --deadline 전에 안전 이탈--> ACTIVE(HP 1)
DOWNED --유예 만료--> DEAD
DEAD --> 복구 없음

ASSIST는 DOWNED의 이동 연결이다. 생명 상태를 별도로 바꾸지 않는다.
```

- 부축 없이 적을 모두 처치하거나 적이 물러나서 시야가 비어도 안전 회복 가능하다.
- 부축으로 이동했어도 아직 적이 보이면 구조 완료가 아니다.
- 자연 이탈/적 처치에 따른 회복에는 가짜 구조자 ID를 붙이지 않는다.
- 안전 이탈로 회복한 직후 동일 행동 처리 중 새 피해를 받으면 새 DOWNED 사건을 생성한다. 사건별 구조 보상은 각각 중복 방지한다.
- 기본 시간안에서 T=250에 쓰러졌으면 1250에 만료한다. 100의 배수로 당기거나 뒤로 밀지 않는다.
- 새 deadline을 actor queue가 고를 수 있는 별도 lifecycle occurrence로 노출한다. 기존 100 cadence만 기다리면 1250 마감을 정확히 처리할 수 없다.
- 동일 시각 T+1000에는 만료가 행동/안전 회복보다 먼저다. T+999 이하에 안전 이탈을 완료해야 한다. 기존 환경 우선 순서와 신규 마감 priority를 명시해 테스트한다.
- 안전 판정은 MOVE 두 인물 이동과 공격 피해 등의 원자적 효과 완료 후, 패배 판정 전에 수행한다. 부분 이동/프레임 업데이트에서 판정하지 않는다.
- 실제 주인공 사망 이후에는 이후 동료/적 행동을 불필요하게 진행하지 않고 거래를 정착시킨다. DEAD 처리·시체 이벤트·회차 종료는 1회씩이다.

## 4. 시야와 전원 전투불능

현재 `visible_party_members`는 `can_act`가 false인 인물을 제외한다. 따라서 전원 DOWNED면 목록이 비어 자동 회복하는 버그가 생길 수 있다.

신규 규칙에 `rescue_threat_observation`을 둔다:

1. 현재 층의 적, 기존 동일 반경/LOS 규칙을 사용한다. 카메라 bounds는 받지 않는다.
2. 일반 활동 파티원의 관측에 더해 **구조 판정과 위기 표시에서만** 전투불능 인물의 현 위치를 관측점으로 포함한다. 부축 이동 시 그 인물의 실제 위치를 사용한다.
3. 쓰러진 인물의 관측을 공격 가능 표적 획득에 악용하지 않도록 일반 targeting API와 구분한다. UI에는 구조를 막는 적을 설명할 수 있어야 한다.
4. 모든 관측자가 사라졌다고 안전 판정하지 않는다. DEAD/다른 층 인물은 관측자가 아니다.
5. 기존 자연 회복의 HUNTING/SEARCHING 조건을 그대로 붙이지 않는다. 사용자가 제안한 '보이지 않으면 이탈'과 다른 규칙이기 때문이다. 시야 밖 추격 때문에 회복을 막으려면 별도 설계 변경으로 다룬다.

주인공 DOWNED면 활동 가능한 동료로 조작을 넘긴다. 원래 주인공 ID는 바꾸지 않는다. 동료가 아직 busy이면 그 준비 시각까지 사건을 처리할 수 있어야 한다.

전원 DOWNED여도 즉시 GAME OVER로 처리하지 않는다. 살아 있는 인물이 없어서 일반 명령을 낼 수 없는 동안에는 **'시간 진행' 위기 입력**으로 100시간씩 처리한다. UI 프레임마다 시간이 흐르지 않는다. 적 이탈/안전 회복 또는 마감 사망까지 진행할 수 있다. 주인공 실제 사망 시 종료한다. 단독 주인공도 같은 규칙이다.

## 5. 부축 이동: 기존 점유를 보존하는 안

한 타일에 두 명을 합치는 운반 상태보다, 두 인물이 인접한 채 같이 이동하는 방식을 먼저 구현한다.

- `ASSIST(helper,target)`: 둘 다 현재 파티원, helper는 행동 가능, target은 DOWNED, 인접하며 벽을 사이에 두지 않는다. 한 명은 한 명만 부축하고 부축받는다. 서로 부축/연쇄 부축 불가.
- 이동 시 helper는 목적지로, target은 helper의 출발 칸으로 이동한다. 둘의 이동 가능성·벽 모서리·점유를 모두 검사한 뒤 한 번에 commit한다.
- target 칸으로의 단순 위치 교환, 제3 인물 점유 칸, 불가능한 두 번째 이동은 첫 버전에서 거부한다. 거부 시 위치·시간·사건 모두 무변경이다.
- target은 스스로 행동하거나 독립 AI 이동하지 않는다. `can_act`는 false 유지, 두 인물의 점유는 계속 각각 유지한다.
- target도 실제 이동 위치에서 환경 노출을 계산한다. 순간이동·층간 원격 끌어오기 불가.
- helper가 DOWNED/DEAD가 되면 연결을 해제하고 target을 현재 위치에 남긴다. target의 기존 deadline 유지.
- 부축 중 공격/시전은 자동 해제하지 않고 거부 + 설명한다. 별도의 RELEASE 행동(초기 100시간 제안) 후 가능. 화면의 버튼 상태로 예고한다.
- 다른 helper로 교대하면 연결 소유자만 변경하되 추가 중복 기억 보상·유예 재설정 없음.
- 귀환/층 이동/파티 교체/추방 전에 DOWNED와 연결을 검사한다. 최초 구현은 미해결 DOWNED가 있는 층 이동·귀환을 이유와 함께 거부해 기존 순간이동/회복 경로의 우회를 막는다. 안전 이탈 후 정상 귀환 가능.
- RETREAT 지시는 연결된 둘의 유효 이동을 우선한다. 자동 경로가 안전을 보장한다고 표시하지 않는다.

명령과 AI는 같은 `assist_assessment`와 이동 커밋을 사용한다. 초기 자동 구조는 도달 가능성, 잔여 시간, helper 자체 위험을 먼저 제한한 뒤 기존 성격·관계 평가로 후보를 정한다. 주인공이 쓰러졌을 때는 동료 직접 조작으로 구조를 수행할 수도 있다.

## 6. 기억과 휴식 대화

부축 시작과 실제 구조 완료를 구분하는 이벤트를 만든다:

- `party.assist_started`: helper, target, 원본 entity.downed ID, 시작 시각/위치.
- `party.assist_ended`: 해제·helper 전투불능·대상 사망·안전 이탈 등 원인.
- `party.rescue_completed`: 안전 회복과 연결, 원본 downed ID 및 유효 helper/assist 사건 ID.
- 단순 시야 이탈은 `entity.recovered`의 회복 원인으로 기록하고 도움받은 기억을 만들지 않는다.
- 마지막 부축자가 실제로 한 칸 이상 이동한 경우만 '데리고 빠져나왔다'로 표현한다. 부축만 했거나 실패했다면 별도 사실 수준의 표현을 쓴다. 적을 대신 맞았다는 대사는 생성하지 않는다.
- 원본 DOWNED 1건당 구조 완료 1회, 관계 반영 1회, 휴식 대화 소비 1회. 저장/로드로 다시 지급하지 않는다.

기존 AID_RECEIVED는 health.restored에 연결돼 있다. 새 사건을 가짜 치료 이벤트로 포장하지 말고 RESCUED_BY 같은 명시 기억 종류를 추가하고 `party_companion_appraisal`의 도움 기억 조회에 포함한다. 기억·관계 history validator와 presenter도 함께 확장한다.

초기 휴식 대화는 한 사건의 짧은 분기만 구현한다:

1. 안전한 휴식 때 완료된 구조 사건 1개를 선택한다.
2. 기존 성격 프로필을 이용해 감사/도움받은 부담 등 표현을 선택한다. 임의 성격 수치를 새로 생성하지 않는다.
3. 플레이어는 응답하거나 대화를 닫을 수 있다. 닫았다고 벌점을 주지 않는다.
4. '다음에는 서로 챙기자' 응답은 별도 약속 기록으로 남기고 향후 구조 후보 평가에 제한된 우선순위를 준다. 명령/행동 가능성/위험 제한을 무시하지 않는다. 점수는 기존 appraisal 스케일에 맞춰 구현 시 기록한다.
5. 전원과 대화해야 이득을 얻는 반복 루틴은 만들지 않는다. 대화·도움 점수는 같은 사건으로 반복 획득 불가.

생명주기와 부축을 먼저 완성한 뒤 이 단계를 구현한다. 자유 입력 대화·LLM·일반 NPC 대화 엔진은 필요하지 않다.

## 7. 코드 변경 묶음

### A. 공통 생명주기 정책과 저장 계약

- 새 `sim/party_rescue_rules.gd`에 적용 대상, deadline, 안전 이탈, 상태 전이 평가를 집중한다.
- `DamageSystem`, 근접/스킬/환경/상태 피해 호출자의 terminal 판단을 공통화한다. 몬스터와 다른 원정 NPC에 신규 주인공 파티 규칙을 전파하지 않는다.
- `CombatantState` 또는 별도 party rescue state에 deadline/부축 연결/사건 원인을 저장한다. 위치를 별도 그림자 상태에 중복 저장하지 않는다.
- `StatusLifecycleSystem`, `FieldActorQueue`, `FieldTurnSystem`에 정확한 마감 occurrence와 안전 판정을 연결한다.
- `party_survival_rules`에서 제어 인물 선택, 전원 무력화, 주인공 영구 사망을 별도 질의로 나눈다.
- `WorldState`의 기존 deadline 공식, 주인공 DOWNED 금지, 상태/사건 검증을 신 규칙에 맞게 분기한다. 최대 시간 overflow와 event headroom도 갱신한다.
- 구 저장은 구 ruleset으로 읽고 동일 journal을 재생한다. 신 회차만 신 규칙을 기본 적용한다. 과거 사망 인물을 자동 부활시키거나 과거 사건의 시간 계약을 바꾸지 않는다.

### B. 부축과 위기 입력

- `PartyActionCommand`에 ASSIST/RELEASE 추가, 정확한 wire 키와 target 검증 확장.
- `MovementSystem` 및 party action commit에 2인 원자 이동 추가. occupancy index/rollback/postcondition 동시 갱신.
- Session API·command journal·재생·잘못된 명령 검증에 새 입력을 추가.
- 전원 DOWNED의 위기 시간 진행은 살아 있는 actor의 HOLD로 위장하지 않고 별도 검증된 journal 입력으로 만든다.
- 이동 대형/자동 탐험이 부축 대상을 독립 이동시키지 않도록 하고, 새 DOWNED/연결 해제 때 자동 이동·휴식을 중단한다.

### C. UI와 후퇴

- 맵과 초상화에 '전투불능 · 남은 10턴' 표시. 시간안은 `ceil(remaining_time/100)`과 기본 턴 단위 설명 사용.
- 시체와 쓰러진 인물을 시각적으로 구분하고 클릭 가능하게 한다.
- 동료 선택 시 부축/놓기, 불가능한 이유, 부축 대상 표시.
- 주인공 DOWNED 시 생존 동료 제어와 상태 설명, 전원 DOWNED 시 시간 진행 버튼 제공.
- 기존 후퇴 버튼은 부축 이동을 고려한다. 렌더/줌/카메라에서 안전 판정을 하지 않는다.

### D. 구조 기억·대화·행동 반영

- `PartyMemoryState/Model/System/HistoryValidator`, 관계 반영, `PartyCompanionAppraisal`, `PartyMemoryPresenter` 확장.
- 사건별 대화 데이터와 consumed source ID, 약속 상태를 저장 가능한 형태로 추가.
- 실제 안전한 휴식 완료 지점에 이벤트 대화 UI 연결. 일반 회복과 구조 회복 이벤트 중복 처리 방지.

각 묶음은 코드와 검증 자료를 커밋한다. 구현 시작 전 이 계획의 제안값과 최종 사용자 응답을 protocol에 반영한다. 이번 작업에서는 실행 요청 queue를 보내거나 기존 두 세션의 역할을 변경하지 않는다.

## 8. 구현 후 필수 검증

| 검증 | 확인할 결과 |
|---|---|
| 주인공/동료 HP 0 | DOWNED 유지, 즉사·짧은 자동회복 없음 |
| 10턴 경계 | T+999 생존, T+1000 사망. T가 100 배수가 아니어도 동일 |
| 시간 소비 | 빠른/느린 행동, 동료 수, 아이템, 긴 WAIT, 조작 전환에도 정한 계약 유지 |
| 안전 이탈 | 마지막 적 처치·벽 뒤 이탈로 회복. 카메라 이동/줌으로는 불변 |
| 전원 DOWNED | 빈 시야로 자동 회복하지 않음. 위기 입력으로 정상 정착·사망 가능 |
| 부축 | 인접/벽/코너/점유/거리 제한, 원자적 2인 이동과 지형 비용 |
| 중단 | helper DOWNED/DEAD, RELEASE, 대상 사망, 교대 시 연결·deadline 정합성 |
| 피해 경로 | 근접·원거리/스킬·불·감전·출혈·신체 손상 경로에서 같은 파티 정책 |
| 제어 | 주인공 DOWNED 후 동료 조작, busy 동료 대기, 회복 후 제어 선택 |
| 귀환/저장 | 미해결 구조 우회 금지, 부축 도중 저장/재생, 옛 저장 동일 재생 |
| 사건 | downed/사망/드롭/구조 완료가 각각 한 번, helper 인과 보존 |
| 기억·대화 | 구조 성공/실패·자연 회복 구분, 성격별 반응, 재대화/로드 보상 중복 없음 |
| 행동 변화 | 같은 상황에서 구조 기억/약속 유무만 바꿔 후보 우선순위 차이 확인 |
| 롤백 | 두 번째 인물 이동 실패, 이벤트 budget 실패, 불량 save가 부분 상태를 남기지 않음 |
| 회귀 | 기존 field turn/시야/아이템/신체/기억 및 구 lifecycle tests 유지 |

신규 전용 acceptance fixture에서 피해를 실제 커밋해 사건 인과까지 검증한다. HP만 수동 변경한 화면 캡처로 구조 성공을 입증하지 않는다. UI는 기존 450×800 기준과 좁은 모바일 폭에서 조작 전환·잔여 시간·부축 버튼을 확인한다.

## 9. 이번 조사 검증

- `godot --headless --path . --script tests/field_lifecycle_acceptance.gd`: PASS, exit 0. 기존 전투불능 처리가 정착·상태 검증을 통과함을 확인했으며 신규 규칙 검증은 아니다.
- `godot --headless --path . --script tests/run_party_memory_tests.gd`: 6 tests, 0 failed, exit 0. 기억 저장/이전/재생, 성격별 강도, 이후 판단에 대한 영향의 기존 테스트 통과.
- 게임 코드 구현·새 규칙 플레이테스트·브라우저 UI 검증은 아직 수행하지 않았다.
