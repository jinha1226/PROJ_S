# Dark Fantasy Expedition System 개발 계획서

> 기준 브랜치: `feat/srpg-stage-campaign`  
> 문서 버전: v0.1  
> 목표: 기존 8×8 SRPG를 유지하면서 Darkest Dungeon식 원정/소모 구조와 Into the Breach식 적 Intent를 결합한다.

## 1. 게임의 핵심

**짧은 전술 전투를 해결하면서, 망가져가는 파티를 던전 끝까지 데려가는 로그라이크.**

- 전투: 8×8, 3~5턴 중심의 짧고 읽을 수 있는 전술전투
- 원정: 6~10개 Room을 통과하며 HP, Stress, Injury, 관계가 누적
- 적 행동: 라운드 시작 시 Intent를 공개하고 해당 라운드 동안 고정
- 파티: 캐릭터의 성격, 기억, 관계가 위기 반응과 행동에 영향을 줌
- 목표: 매 전투의 승리보다 “누구를 어떤 상태로 귀환시키는가”까지 포함

## 2. 기존 구현에서 유지할 것

현재 SRPG 브랜치의 다음 기반은 재사용한다.

- 8×8 Room
- Deployment phase
- 개별 Initiative / turn
- 이동, 공격, Range, LOS
- Terrain movement cost
- Injury 기반 이동 페널티
- Stress / Morale
- Emotion / HEXACO / Memory / Relationship
- Equipment / Skill / Item
- Room objective (전멸 외 목표 포함)
- Reinforcement
- 3×3 = 9 Room floor map
- Loot → 다음 Room
- `PartyPlaytestSession`

새 게임을 별도로 만드는 대신 이 구조 위에 원정 상태와 Intent 계층을 추가한다.

## 3. 전체 게임 루프

```
거점
 → 파티 편성
 → 장비/소모품 준비
 → 던전 진입
 → Room 선택
 → 8×8 전투/이벤트
 → HP·Stress·Injury·Relationship 누적
 → Loot / Camp / Proceed / Retreat
 → 다음 Room
 → Boss 또는 Exit
 → 생존자 귀환
 → 치료/성장/다음 원정
```

기본 원정은 기존 9 Room 구조를 우선 사용한다. 플레이 타임 목표는 약 15~30분.

## 4. 상태 모델

### ExpeditionState

```text
floor_id
current_room
visited_rooms
cleared_rooms
supplies
party[]
expedition_turn
retreat_state
```

### PartyMemberState

```text
hp / max_hp
stress
dying_tokens
injuries[]
conditions[]
traits[]
equipment[]
skills[]
relationships{}
memories[]
```

HP, Stress, Injury, Relationship은 Room 종료 시 초기화하지 않는다.

## 5. HP / DYING / Death

HP가 0 이하가 되면 즉시 사망시키지 않고 `DYING` 상태로 전환한다.

초기 구현은 확률형 Death Save보다 예측 가능한 **Death Token** 방식을 사용한다.

```
HP <= 0
 → DYING

DYING 상태에서 추가 피해
 → Death Token +1

Death Token 3
 → Death
```

회복으로 DYING에서 빠져나올 수 있지만 누적된 Injury와 Stress는 유지한다. Token 수와 회복 규칙은 밸런스 단계에서 조정한다.

## 6. Stress

초기 범위는 0~100.

- 피격: +3~8
- 치명타: +8
- 동료 DYING: +15
- 동료 사망: +30
- 함정: +5~15
- 특정 적 스킬: +10 이상
- Camp/Skill/Event/Relationship interaction으로 감소

단계:

```
0–49   Stable
50–79  Strained
80–99  Breaking
100    Crisis
```

수치는 데이터화하여 코드에 하드코딩하지 않는다.

## 7. Crisis + HEXACO

Stress 100은 단순 디버프가 아니라 `Crisis`를 발생시킨다.

후보 반응:

- Panic
- Aggression
- Withdrawal
- Self-Preservation
- Despair
- Resolve
- Protective
- Focused
- Rally

선택은 완전 랜덤이 아니라 다음 입력을 사용한다.

```
HEXACO
+ 현재 Relationship
+ 관련 Memory
+ 현재 전투 상황
→ appraisal
→ Crisis Reaction
```

예: Emotionality가 높고 가까운 동료가 DYING이면 Panic 확률이 커질 수 있고, 높은 신뢰/친화 관계와 특정 성향 조합에서는 Protective 반응이 커질 수 있다.

원시 HEXACO 수치는 플레이어에게 직접 노출하지 않고 읽을 수 있는 trait/행동으로 표현한다.

## 8. Relationship / Memory

초기 내부 관계 축:

```
Trust
Affinity
Respect
Fear
```

UI에는 수치 대신 “신뢰함”, “불편해함”, “존경함”, “두려워함” 등으로 표현한다.

전투 이벤트가 Memory와 Relationship을 동시에 생성/변경한다.

예:

- A가 B를 Guard → B→A Trust 증가
- A가 B를 Heal → Affinity 증가
- 위험한 B를 방치하고 이탈 → Trust 감소
- 반복적으로 위험을 해결 → Respect 변화

핵심 루프:

```
Combat Event
 → Memory
 → Relationship
 → 이후 appraisal/behavior
```

## 9. Injury

HP와 별도인 원정 지속 손상.

초기 예시:

- Cracked Rib: Max HP 감소
- Sprained Ankle: Move -1
- Wounded Arm: Damage 감소
- Concussion: Stress gain 증가
- Deep Wound: Room 종료 시 추가 HP 손실

주요 발생원:

- Critical hit
- DYING 진입
- Trap
- 특정 Enemy Skill

Room 종료 후에도 유지하며 Camp 또는 거점 치료의 주요 대상이 된다.

## 10. Enemy Intent

Into the Breach식 전투 가독성의 핵심 시스템.

### 원칙

1. 라운드 시작 시 적 Intent를 계산한다.
2. Intended move, target, attack line/area, damage, stress, 특수효과를 표시한다.
3. 플레이어 캐릭터 한 명이 행동할 때마다 재계산하지 않는다.
4. 해당 라운드 동안 Intent는 freeze한다.
5. 명시적인 Interrupt/Retarget 효과가 있을 때만 Intent 상태를 변경한다.

예:

```
Skeleton Archer
MOVE → (5,3)
TARGET → (5,6)
Damage 4
Stress 3
```

플레이어 대응 수단:

- Dodge
- Block
- Guard / Intercept
- Stun / Interrupt
- Kill
- Swap
- Forced Retarget
- Line blocking

기존 기획상 knockback은 핵심 대응 수단으로 사용하지 않는다.

## 11. Stress × Intent

HP 피해만 예고하지 않는다.

```
Damage 6
Stress +10
Injury Risk
Target: Mage
```

Stress가 높은 캐릭터를 노리는 공격, Injury를 유발하는 공격, 관계를 흔드는 공격 등을 Intent로 명확히 보여준다.

이 계층이 “전술 퍼즐”과 “원정 소모”를 연결한다.

## 12. Room / Expedition Map

기존 3×3 / 9 Room 구조를 첫 버전에서 유지한다.

Room type 후보:

- COMBAT
- ELITE
- EVENT
- HAZARD
- TREASURE
- CAMP
- BOSS
- EXIT

진입 전에는 제한된 정보만 보여준다.

```
Combat
Danger ??
Reward ?
```

Room 진입 후 8×8 board, enemy composition, Intent가 완전히 공개된다.

## 13. Camp

Camp는 무료 완전회복이 아니라 제한된 Camp Point를 소비하는 선택 시스템으로 구현한다.

예: 6 CP

- Treat Wound: 2
- Reduce Stress: 2
- Repair Armor: 2
- Talk: 1
- Scout: 2
- Cook: 1

`Talk`은 단순 flavor가 아니라 Memory/Relationship 변화의 실제 시스템 진입점으로 사용한다.

## 14. Retreat

Room 종료 시 기본 선택:

```
Proceed
Camp (가능한 경우)
Retreat
```

Retreat 시 일부 Loot를 보존하고 생존 캐릭터를 귀환시킨다. Injury와 일정 Stress는 유지한다. 사망 캐릭터는 복구하지 않는다.

철수는 실패 버튼이 아니라 원정 리스크 관리의 정상적인 전략으로 취급한다.

## 15. 코드 아키텍처 목표

장기적으로 다음 책임 분리를 목표로 한다. 실제 경로/클래스명은 기존 코드와 충돌 여부를 확인한 뒤 단계별로 적용한다.

```
game/
  expedition/
    expedition_state.gd
    expedition_manager.gd
    room_generator.gd
    room_state.gd

  combat/
    combat_manager.gd
    initiative_manager.gd
    intent/
      intent.gd
      intent_builder.gd
      intent_resolver.gd

  character/
    character_state.gd
    stress/
      stress_system.gd
      crisis_system.gd
    injury/
      injury.gd
      injury_system.gd
    personality/
      appraisal_system.gd
    relationship/
      relationship_state.gd
      relationship_system.gd
    memory/
      memory_event.gd
      memory_system.gd

  camp/
    camp_manager.gd
    camp_action.gd
```

### 중요한 구현 원칙

Combat 코드에 Stress, Relationship, HEXACO 로직을 직접 결합하지 않는다.

Combat은 의미 있는 사건을 발행한다.

```gdscript
EventBus.emit("ally_entered_dying", actor_id, target_id)
```

각 시스템은 이벤트를 구독한다.

- StressSystem → Stress 변경
- MemorySystem → Memory 생성
- RelationshipSystem → 관계 변경
- Appraisal/CrisisSystem → 성격/상황 기반 반응 결정

이를 통해 전투 규칙과 NPC 시뮬레이션을 독립적으로 테스트할 수 있게 한다.

## 16. 단계별 구현

### Phase 1 — Persistent Attrition

- Room 간 HP 유지
- Stress 0~100
- Stress 발생/감소 이벤트
- Room 종료 후 상태 보존
- HUD에 HP/Stress 표시

**완료 조건:** 첫 전투의 피해와 Stress가 두 번째 Room에서도 정확히 유지된다.

### Phase 2 — Frozen Enemy Intent

- Intent data model
- Round 시작 시 Intent build
- Move/Target/Attack preview
- 라운드 중 freeze
- Intent resolution
- Interrupt/Retarget hook

**완료 조건:** 플레이어 행동 후에도 적 Intent가 임의로 재계산되지 않으며 화면 표시와 실제 적 행동이 일치한다.

### Phase 3 — DYING + Injury

- DYING state
- Death Token
- Death
- Injury 발생
- Injury modifier 적용
- Room 간 Injury 유지

**완료 조건:** 0 HP → DYING → 구조 또는 추가 피해 → Death 흐름이 동작하고 Injury가 다음 Room에 영향을 준다.

### Phase 4 — Full 9-Room Expedition

- 기존 stage map과 persistent state 연결
- Room type
- Loot
- Proceed / Retreat
- Boss/Exit
- Autosave at room boundary

**완료 조건:** 3명 파티로 시작해 여러 Room을 거쳐 탈출/완주할 수 있다.

### Phase 5 — Camp / Supplies

- Camp Point
- 치료/Stress 감소
- Scout
- Talk
- Supplies

### Phase 6 — Memory / Relationship

- Combat event → Memory
- 관계 축 변화
- 관계 UI
- Camp Talk

### Phase 7 — HEXACO Crisis

- Appraisal
- Stress 100 Crisis
- 성격/관계/기억 기반 reaction
- Panic/Protective/Rally 등 실제 전투 효과

### Phase 8 — Hub / Permanent Consequences

- 생존자 귀환
- 사망 처리
- 치료
- 장비/보상
- 다음 원정 준비

### Phase 9 — Content / Balance

- Enemy archetype
- Intent 다양화
- Room events
- Injuries
- Camp actions
- Boss
- 난이도/수치 조정

## 17. 첫 Vertical Slice

복잡한 NPC 시스템보다 먼저 다음 한 사이클을 완성한다.

```
3인 파티
 → 8×8 Room
 → 적 Intent 확인
 → 3~5턴 전투
 → HP/Stress 누적
 → 다음 Room
 → DYING/Injury 가능
 → Proceed / Camp / Retreat
 → 여러 Room 통과
 → Exit
```

이 Vertical Slice가 재미있는지를 먼저 검증한다. Relationship/HEXACO는 이 기반이 검증된 뒤 확장한다.

## 18. 테스트 원칙

각 Phase는 가능한 한 deterministic test를 추가한다.

특히 다음 회귀 테스트는 필수다.

- Intent freeze regression
- Intent preview == resolved action
- Room transition persistence
- DYING / Death Token
- Injury modifier persistence
- Stress threshold / Crisis trigger
- Relationship event direction
- save/load at room boundary

기존 SRPG acceptance/regression test는 삭제하지 않고 유지한다.

## 19. 비목표

첫 구현에서는 다음을 하지 않는다.

- Darkest Dungeon의 시스템/수치/콘텐츠를 1:1 복제
- 대규모 Hub 경영
- 수십 개 Affliction
- 완전 자유 생성형 NPC 대화
- 복잡한 실시간 이탈 NPC 시뮬레이션
- 전투 중 매 행동마다 적 AI가 Intent를 다시 최적화
- 그래픽 리뉴얼을 시스템 구현과 동시에 진행

## 20. 개발 판단 기준

각 기능은 아래 질문을 통과해야 한다.

1. 플레이어가 다음 위험을 읽을 수 있는가?
2. 대응 선택이 최소 2개 이상 존재하는가?
3. 선택의 결과가 다음 Room까지 남는가?
4. 파티 상태 때문에 Proceed/Retreat 고민이 생기는가?
5. NPC 성격/관계가 숫자 장식이 아니라 행동 차이를 만드는가?

이 다섯 가지를 게임의 시스템 설계 기준으로 사용한다.
