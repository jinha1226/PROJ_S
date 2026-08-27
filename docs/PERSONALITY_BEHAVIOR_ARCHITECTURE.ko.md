# 개인 성향·자율행동 아키텍처 조사와 구현 계획

> 상태: Phase 3 이후 개인 AI의 장기 기준 문서
> 현재 구현 프롬프트: `PHASE3_DUNGEON_PERSONALITY_LAB_IMPLEMENTATION_PROMPT.ko.md`

## 1. 결론

게임 업계에 개인 성향을 처리하는 단 하나의 표준 알고리즘은 없다. 잘 알려진 시뮬레이션 게임들은 대체로 다음을 조합한다.

```text
안정적인 개인차
  성격 facet / 명명된 trait / 가치관
          ↓
현재 상태
  욕구 / 감정 / 스트레스 / 체력
          ↓
개인이 알고 있는 상황
  지각 / 기억 / 관계 / 명령 / 역할
          ↓
행동 선택
  우선 계층 + hard gate + utility score + 전환 억제
          ↓
행동 실행
  작은 상태기계 / Job runner / 공통 SimCommand
```

우리 프로젝트에는 **계층형 Utility 선택 + 작은 실행 상태기계 + 결정론적 heartbeat**가 가장 적합하다. 범용 GOAP나 거대한 behavior tree는 아직 도입하지 않는다.

성격은 보통 행동을 직접 명령하지 않는다.

```text
나쁜 예: cowardly이면 언제나 FLEE

좋은 예:
위협을 목격함
→ 객관적 위험을 개인의 지식으로 평가
→ boldness와 composure가 공포·위험 감각을 편향
→ 명령, 동료 관계, 부상, 퇴로와 함께 후보를 비교
→ 정상 상태에서는 ENGAGE/PROTECT/FLEE/COVER/HOLD 중 선택
→ 공황 임계치를 넘으면 PANIC 모드에서 FLEE/FREEZE 중 선택
```

## 2. 참고 게임에서 확인한 구조

### RimWorld

RimWorld는 소수의 읽기 쉬운 Trait, Need, Thought, Mood, Skill/Passion, Work priority, Mental state를 분리한다. 평상시 행동은 강한 우선순위 트리와 Job 실행기로 처리하고, 일부 지점만 점수화한다. 낮은 기분이 오래 지속될 때 발생하는 mental break는 평상시 선택을 잠시 대체하는 별도 모드다.

가져올 점:

- 성격, 능력, 역할/명령, 현재 감정을 같은 필드로 합치지 않는다.
- 흔한 수치 보정은 데이터로 두고, 새로운 세계 질의와 행동 실행은 등록형 코드 전략으로 둔다.
- 공황·광분·기절 같은 제어권 상실은 일반 Utility 후보가 아니라 상위 상태 전환으로 다룬다.
- Trait은 많기보다 적고 눈에 잘 띄어야 한다.

공식 설명은 인물이 배고픔, 피로, 죽음, 시체, 부상, 어둠 등을 관찰해 감정을 만들고 스트레스에서 무너질 수 있다고 설명한다. 내부 ThinkTree/Job 구조에 관한 세부 내용은 정식 API 문서가 아니라 커뮤니티 문서와 역공학 자료임을 구분해야 한다.

### Dwarf Fortress

Dwarf Fortress는 종족·문화 경향, 개인 personality facets, values, preferences, needs, 감정, stress/focus, 제한된 기억을 분리한다. 같은 사건도 성격과 가치관에 따라 다른 감정을 만들며, 강한 기억은 나중에 다시 스트레스에 영향을 주거나 드물게 장기 성격 변화를 남긴다.

가져올 점:

- `base personality`, 영구 변화, 임시 상태를 절대 같은 값에 덮어쓰지 않는다.
- 모든 사건을 저장하지 않고 강도와 범주를 이용해 제한된 기억만 남긴다.
- 사건의 객관적 사실과 각 인물이 알고 있는 사실을 분리한다.
- 성격 설명은 실제 행동·감정·관계에 연결될 때만 서사가 된다.
- 소비처가 없는 수십 개의 성격 수치는 깊이가 아니라 잡음이 된다.

Tarn Adams가 정리한 시뮬레이션 원칙도 이에 맞는다. 모델을 처음부터 과도하게 크게 만들지 말고, 플레이어가 보는 층 또는 그 한 층 아래까지만 구현하며, 기본 요소를 분리한 뒤 상호작용으로 결과를 만들라고 권한다.

### The Sims

The Sims 계열은 욕구와 현재 상태를 바탕으로 가능한 interaction의 효용을 비교한다. 객체는 자신이 제공하는 행동과 충족 효과를 데이터로 제공하고, 공통 AI가 이를 소비한다. The Sims 3는 후보 탐색을 `장소 → 대상 → interaction`처럼 계층화하고, commodity에서 관련 interaction으로 역색인해 전 세계의 모든 행동을 매번 평가하지 않는다.

가져올 점:

- 음식, 침대, 작업대 같은 세계 객체가 `Affordance`를 광고하게 하면 새 콘텐츠를 AI 중앙 코드 수정 없이 확장할 수 있다.
- 후보 생성과 후보 점수화를 분리한다.
- 위험·굶주림처럼 급한 목적을 먼저 고른 뒤 그 목적을 만족시키는 대상만 비교한다.
- 이 구조는 마을의 EAT/REST/WORK 단계에서 도입하되, 던전 성격 실험에서는 인터페이스만 보존한다.

### Crusader Kings

Crusader Kings는 소수의 표시 가능한 성격 trait와 관계/opinion이 AI 가중치를 바꾸게 한다. CK3는 인물을 읽기 쉽게 만들기 위해 핵심 personality trait 수를 제한했고, 자기 성격에 거스르는 선택을 무조건 금지하기보다 stress 비용으로 표현한다.

가져올 점:

- 내부 수치가 많아져도 UI에는 1~3개의 지배적인 설명을 보여준다.
- 성격과 반대되는 행동도 상황이 강하면 가능해야 하며, 필요하면 후속 stress를 남긴다.
- 성격은 사건과 관계가 실제 결과를 낳도록 연결되어야 한다.

### 업계의 행동 선택 알고리즘

FSM, behavior tree, Utility AI, GOAP, HTN은 서로 배타적인 표준이 아니다.

| 기법 | 잘하는 일 | 이번 프로젝트의 사용 |
|---|---|---|
| FSM/HFSM | 공황, 기절, 전투처럼 명확한 모드와 전환 | `NORMAL ↔ PANIC`, leaf 실행 상태에 사용 |
| Behavior tree / priority tree | 긴급 행동과 규칙적 우선순위 | 상위 행동 계층을 작게 유지할 때 참고 |
| Utility AI | 여러 합리적인 후보를 연속 입력으로 비교 | 정상 반응과 같은 계층 내부 선택에 사용 |
| GOAP/HTN | 여러 단계의 대체 행동열 계획 | 잠긴 문·열쇠·제작·우회 계획이 생길 때까지 보류 |

Utility AI의 관행은 후보마다 정규화된 입력을 response curve로 변환하고 결합하는 것이다. hard gate, cooldown, runtime, commitment/inertia가 없으면 행동이 매 틱 뒤집히거나 같은 행동만 반복되기 쉽다.

## 3. 프로젝트의 장기 계층

### 3.1 안정적인 정체성

```text
Species / Culture / Faction prior
PersonalityFacetProfile
ValueProfile                 # 후속 단계
TraitSet                     # 희소한 예외 특성, 후속 단계
Skill / Role / Duty          # 성격과 별도
```

초기 facet은 네 개만 구현한다.

| facet | 뜻 | 중복을 피하는 경계 |
|---|---|---|
| `boldness` | 계산된 위험을 감수하는 정도 | 감정을 억제하는 능력은 아님 |
| `aggression` | 위협에 접근하고 공격으로 해결하려는 정도 | 용기나 전투 실력은 아님 |
| `altruism` | 타인의 안전을 자기 안전보다 중시하는 정도 | 특정 대상과의 관계값은 아님 |
| `composure` | 강한 감정 속에서도 계획을 유지하는 정도 | 위험을 좋아하는 정도는 아님 |

종족 간 신뢰·공포·적대 prior는 personality facet보다 별도이며 우세한 입력으로 유지한다. 인간이 고블린을 한 번 도운 사건이나 높은 altruism 하나가 강한 종간 적대를 즉시 뒤집어서는 안 된다.

### 3.2 동적 심리 상태

```text
AffectState    fear, anger                     # Phase 3
StressState    acute / long_term               # 후속
NeedState      hunger, fatigue, social...       # 마을 단계
MentalMode     NORMAL / PANIC / ...             # Phase 3
TemporaryModifier                                # 후속
```

`base facet`을 현재 공포나 술, 부상 때문에 직접 수정하지 않는다. 유효값은 항상 다음처럼 투영한다.

```text
effective facet
= base facet
 + explicit permanent change records
 + bounded temporary modifiers
```

### 3.3 지각·기억·관계

의사결정은 실제 세계 전체가 아니라 해당 인물이 아는 정보만 읽는다.

```text
objective event
→ PerceptionRecord
→ EventAppraisal
→ Thought/Affect
→ 선택적으로 bounded MemoryRecord
→ 관계·stress·장기 변화
```

Phase 3은 현재 보이는 위협과 직접 관계만 쓴다. 기억, 소문, 장기 성격 변화는 계약만 분리하고 구현하지 않는다.

### 3.4 선택과 실행

```text
DecisionContext
→ DecisionTier 선택
→ CandidateProvider가 action/target 후보 생성
→ GateEvaluator가 불가능한 후보 제거
→ ConsiderationEvaluator가 점수와 근거 계산
→ hysteresis 적용
→ deterministic selector
→ ReactionIntent
→ leaf Executor가 공통 MOVE/ATTACK/HOLD/FREEZE/ESCAPE 명령으로 실행
```

선택기는 “왜 무엇을 할지”만 정한다. 선택된 reaction은 intent builder가 실제 leaf action으로 변환한다.

```text
ReactionIntent
  reaction_id       ENGAGE / PROTECT / ...
  leaf_action_id    MOVE / MELEE_ATTACK / HOLD / FREEZE / ESCAPE
  target entity/position
```

경로 찾기, 공격, 물건 사용 같은 “어떻게 실행할지”는 공통 leaf executor가 담당한다. 같은 돌진 기술도 공격용과 퇴각용 후보로 각각 평가한 뒤 하나의 실행기를 재사용할 수 있어야 한다.

## 4. 확장 가능한 정의 계약

문자열 ID 자체가 문제인 것은 아니다. 자유형 `Dictionary<String, Variant>` 하나가 정의, 실행 상태, 저장 형식을 모두 겸하는 것이 문제다.

### 4.1 정의 타입

```text
PersonalityFacetDef
  def_version
  facet_id
  min_value / neutral_value / max_value
  low_label / high_label
  generation_rule_id

ActionDef
  def_version
  action_id
  decision_tier
  allowed_mode_ids
  tie_break_rank
  commitment_duration
  cooldown_duration
  switch_margin
  candidate_provider_id
  gates: Array[GateDef]
  considerations: Array[ConsiderationDef]
  intent_builder_id
  interrupt_policy_id
  base_score

MentalModeDef
  def_version
  mode_id
  candidate_action_ids
  tie_break_rank
  transition_policy_id

GateDef
  gate_id
  evaluator_id
  typed_config

ConsiderationDef
  consideration_id
  evaluator_id
  input_id
  curve_id
  signed_weight_milli
  typed_config

CurveDef
  curve_id
  ordered integer control points
```

규칙:

- 모든 ID는 안정적인 문자열이고 versioned registry에 등록한다.
- snapshot wire format은 ID로 정렬된 typed row 배열을 사용한다.
- 중복 ID, 알 수 없는 ID, 알 수 없는 필드, 범위 밖 값은 조용히 무시하지 않고 거부한다.
- 자유형 config는 decode 경계에서 evaluator별 typed config로 변환한다.
- evaluator registry는 `evaluator_id → pure evaluator`만 연결하며 중앙 selector는 구체적인 facet이나 세계 질의를 알지 않는다.
- transition policy registry는 `transition_policy_id → pure mode transition strategy`만 연결한다. Phase 3의 NORMAL/PANIC은 둘 다 `panic-hysteresis-v1`을 사용한다.
- mode가 참조하는 모든 action은 등록돼 있고 그 mode를 `allowed_mode_ids`에 포함해야 한다. action/mode의 tie-break rank는 ruleset 안에서 중복될 수 없다.
- 정의는 snapshot에 통째로 복사하지 않고 `ruleset_id`와 인스턴스 값만 저장한다.
- curve, weight, tie-break를 바꾸면 AI ruleset version을 올린다.

### 4.2 초기 프로필 상태

```text
PersonalityProfile
  profile_schema_version
  generation_ruleset_id
  facet_rows: [
    {facet_id, base_value}
  ]  # facet_id 오름차순, 중복 금지
```

현재 네 facet만 요구한다. `values`, `traits`, `needs`를 빈 필드로 미리 넣지 않는다. 실제 소비처가 생길 때 별도 typed component와 명시적 snapshot migration으로 추가한다.

이 선택은 확장성을 포기하는 것이 아니다. 핵심 selector가 facet 이름을 모르는 상태에서 stable ID와 등록된 evaluator만 소비하도록 만드는 것이 확장성의 중심이다.

Godot 구현은 사용자 정의 generic mega-registry를 흉내 내지 않는다. 첫 단계에는 `PersonalityDefinitionRegistry`, `DecisionRulesetRegistry` 두 구체 registry와 공통 validation/fixed-point helper만 만들고, 정의를 typed `RefCounted` 객체로 노출한다. 외부 규칙 DSL과 범용 definition editor는 실제 요구가 생길 때까지 보류한다.

### 4.3 입력과 response curve

모든 consideration 입력과 curve 출력은 `0..1000` 고정소수 정수다.

```text
raw input
→ clamp/normalize 0..1000
→ versioned piecewise-linear curve 0..1000
→ signed weight 적용
→ contribution
```

Phase 3의 결합기는 설명 가능성과 단조성 검증을 위해 다음 하나만 제공한다.

```text
score = clamp(base_score + sum(contribution), SCORE_MIN, SCORE_MAX)
```

결합기는 `score_combiner_id = weighted-sum-v1` 전략 뒤에 숨긴다. 이후 필요하면 곱셈형 Utility를 새 ruleset으로 추가할 수 있지만, 첫 단계에 여러 결합기를 동시에 구현하지 않는다.

`curve_output × signed_weight_milli ÷ 1000`의 음수 나눗셈과 반올림 규칙은 helper 하나로 명시하고 테스트한다. 64비트 중간값의 허용 범위를 정의해 overflow가 가능한 definition은 registry 검증에서 거부한다.

초기 curve palette도 작게 제한한다.

```text
linear_up
linear_down
threshold_up
threshold_down
```

대부분은 단조 curve를 사용한다. 비단조 curve는 “너무 가깝지도 멀지도 않은 거리”처럼 실제 소비처가 생길 때만 추가한다.

### 4.4 평가 결과

Evaluator는 순수 함수이며 다음을 반환한다.

```text
raw_input
normalized_input
curve_output
contribution
veto / rejection_reason
evidence_ids
```

평가 중 world, RNG, ID, event를 바꾸지 않는다. UI가 보여주는 이유와 실제 선택 계산은 같은 결과 DTO를 사용한다.

## 5. 행동 선택 규칙

### 5.1 계층과 gate

Phase 3의 순서는 다음과 같다.

```text
1. 사망·기절처럼 행동 불가능한 상태
2. MentalMode 전환 검사
3. 현재 mode에서 허용된 reaction 후보 생성
4. hard gate: 인지, 경로, target, 사거리, 점유, 명령
5. 같은 tier 안의 integer utility 비교
6. commitment/switch rule
7. 고정 tie-break
```

`HOLD`는 정상 상태의 항상 합법인 fallback이다. PANIC 상태에서는 최소 하나의 `FLEE` 또는 `FREEZE`가 합법이어야 한다.

### 5.2 공황은 별도 모드

```text
NORMAL
  candidates: ENGAGE, PROTECT, FLEE, TAKE_COVER, HOLD

PANIC
  candidates: FLEE, FREEZE
```

BERSERK, SURRENDER, CALL_FOR_HELP 같은 후속 mode는 정의 행만 추가한다고 자동으로 작동하지 않는다. 필요한 pure transition strategy를 등록하고 `MentalModeDef.transition_policy_id`로 연결해야 한다. 이때 mode별 후보를 읽는 중앙 selector와 leaf executor는 바꾸지 않는다.

공황 진입과 해제에는 서로 다른 threshold를 둔다.

```text
panic_pressure >= enter_threshold  → PANIC
panic_pressure <= exit_threshold   → NORMAL
exit_threshold < enter_threshold
```

이 hysteresis가 임계값 근처에서 NORMAL/PANIC이 매 틱 오가는 것을 막는다. composure는 진입 압력과 회복 속도를 편향하지만, 공황을 영원히 불가능하게 만드는 절대 면역은 기본 규칙으로 두지 않는다.

### 5.3 행동 전환 억제

`busy_until`은 leaf 행동을 실행할 수 없는 시각이고, `commitment_until`은 현재 의도를 쉽게 바꾸지 않는 시각이다. 둘을 분리한다.

전환 조건:

```text
현재 행동이 불법/실패/완료       → 즉시 재선택
상위 emergency tier 발생          → 즉시 중단 가능
commitment_until 이전             → 현재 행동 유지
그 이후 challenger >= current + switch_margin → 전환
그 외                              → 현재 행동 유지
```

행동별 cooldown과 bounded repeat count를 둔다. 이 상태는 snapshot에 저장한다.

지속 reaction의 연속 실행이 자기 cooldown에 막혀서는 안 된다. 현재 reaction을 계속 평가할 때는 그 action 자신의 cooldown gate를 건너뛰고, challenger와 현재 reaction의 점수를 동일한 frozen projection에서 다시 계산한다. cooldown은 leaf를 한 번 실행할 때마다 시작하지 않고 reaction이 완료되거나 다른 reaction으로 전환될 때 `now + cooldown_duration`으로 시작한다. `HOLD`와 `FREEZE`의 cooldown은 0이다.

action history의 `last_committed_time`과 `consecutive_commit_count`는 후보가 선택된 시점이 아니라 충돌 해결과 leaf legality 재검증 뒤 실제 leaf action commit이 성공했을 때만 갱신한다. 첫 commit은 count 1, 같은 reaction의 성공적인 후속 leaf commit은 bounded increment다. reaction을 나갔다가 다시 진입한 첫 성공 commit은 count를 1로 재설정한다. `cooldown_until`은 위의 reaction 종료/전환 시점에만 갱신한다.

### 5.4 선택의 무작위성

Phase 3 비교 실험은 최고 점수의 deterministic argmax를 사용한다. 다양성은 personality seed에서만 온다.

후속 production 모드에서만 상위 점수대 내 seeded weighted choice를 검토한다. 그때도 전역 RNG 호출 순서에 의존하지 않고 `(world_seed, actor_id, decision_event_id, action_id, rng_ruleset)` keyed stream을 사용하며, 선택 결과를 사건으로 남긴다.

## 6. 성격 생성

### 실험용 생성기

던전 실험의 Latin-hypercube는 네 비교군의 차이를 보장하기 위한 **실험 설계**다. 일반 세계의 인구 생성 관행이 아니다.

```text
personality-lab-latin-hypercube-v1
```

- world seed와 personality seed를 분리한다.
- actor/slot/facet별 `sha256-u31-v1` keyed hash를 사용하고 Godot `hash()`에 의존하지 않는다.
- 네 lead는 각 facet의 네 구간을 한 번씩 사용한다.
- 생성된 base facet은 snapshot에 직접 저장한다.

### 일반 세계 생성기

향후 production 생성기는 다음을 사용한다.

```text
species/culture distribution prior
+ 생애 배경 modifier
+ 상관관계가 있는 개인 편차
+ 소수의 희귀 trait
```

대부분의 인물은 중간 범위에 두고 소수의 outlier만 강하게 읽히게 한다. 서로 모순되는 희귀 trait은 생성 규칙에서 거부한다. 실험용 LHS와 production 분포는 서로 다른 ruleset으로 유지한다.

## 7. 저장과 인과

저장할 것:

```text
personality_ruleset_id / decision_ruleset_id
PersonalityProfile base facet rows
AffectState / MentalMode
active intent / target
busy_until / commitment_until
bounded action history rows: cooldown_until / last_committed_time / consecutive_commit_count
last_decision_event_id
후속: needs, memory, relation, permanent change records
```

저장하지 않을 것:

```text
현재 후보 목록
점수 projection
경로
FOV 결과
UI용 요약
```

실제 결정 당시의 점수 근거는 bounded `ai.decision_selected` 사건에 기록하고 `last_decision_event_id`로 참조한다. 같은 진단을 actor state와 event에 중복 저장하지 않는다.

Phase 3 실험은 비교를 위해 full trace를 남긴다. 다수 NPC production 단계로 가기 전에는 ruleset별 `FULL / SUMMARY` trace 정책과 결정론적 보존 한도를 추가해야 한다. 장기 사건에는 선택 action, 핵심 근거, cause만 남기고 모든 후보의 디버그 행을 무한히 축적하지 않는다.

장기 변화는 원래 base 값을 덮어쓰지 않고 다음 기록으로 남긴다.

```text
PersonalityChange
  change_id
  facet_id / value_id
  delta
  cause_memory_id
  occurred_time
  rule_id / rule_version
```

## 8. 구현 단계

### 단계 A — 현재 부분 구현 정리와 회귀 복구

- 미완성 마을 코드에서 8방향 MOVE, weighted pathfinder, batch 골격, 15×15 UI 기반만 보존한다.
- 마을 profile/욕구/routine/conversation 구현은 제거하거나 backlog로 격리한다.
- snapshot v4와 두 cadence를 새 ruleset에 맞춰 정착시킨다.
- 기존 92개 테스트를 먼저 모두 통과시킨다.

완료 기준: 기존 회귀 `92/92`, 미등록 schedule/정의/저장 행 0.

### 단계 B — 성향과 결정 정의 기반

- `PersonalityFacetDef`, `PersonalityProfile`을 구현한다.
- `MentalModeDef`, `ActionDef`, `GateDef`, `ConsiderationDef`, `CurveDef` registry를 구현한다.
- decode 시 typed validation, stable ordering, unknown/duplicate rejection을 구현한다.
- `weighted-sum-v1`과 네 개의 단조 curve만 구현한다.
- evaluator purity와 진단 DTO를 구현한다.

완료 기준: 정의 오류 테스트, curve endpoint/monotonicity, snapshot round trip, 평가 순수성 통과.

### 단계 C — 동적 심리와 모드 전환

- `fear`, `anger`, `panic_pressure` appraisal을 구현한다.
- `NORMAL ↔ PANIC` enter/exit hysteresis를 구현한다.
- `busy_until`, `commitment_until`, cooldown을 분리해 저장한다.

완료 기준: 임계값 진동 0, composure 단조성, save/load 중간 재개 동일.

### 단계 D — 통제된 던전 성격 실험

- 15×15의 동일한 네 chamber와 lead/ally/threat를 배치한다.
- 정상 후보 5개와 공황 후보 2개를 data definition으로 등록한다.
- candidate provider와 공통 MOVE/ATTACK/HOLD/FREEZE executor를 연결한다.
- 같은 pre-action projection에서 batch decide/resolve/commit한다.

완료 기준: 같은 personality 강제 주입 시 네 방 결과 동일, chamber 누출 0, 행동 진동 0.

### 단계 E — 설명 가능한 UI와 soak

- 선택 action뿐 아니라 gate 탈락 이유, raw input, curve, contribution, 전환 억제 이유를 표시한다.
- personality seed를 바꿔 같은 조우를 반복한다.
- 100 seed soak, journal replay, save/load continuation, 모바일 해상도 smoke를 수행한다.

완료 기준: UI에 표시한 계산을 trace에서 다시 합산하면 실제 점수와 정확히 일치한다.

### 후속 단계

```text
관찰 기반 Thought/Memory + 관계 반응
→ Values와 duty/stress 비용
→ Needs + 객체 Affordance 기반 마을 생활
→ 문화 prior + 희귀 Trait 생성
→ 기억 통합과 드문 장기 성격 변화
→ 다단계 대체 계획이 필요할 때만 GOAP 검토
```

## 9. 확장성 검증 규칙

- 새 facet을 registry와 action definition에 추가해도 selector 코드는 바뀌지 않는다.
- 새 action이 기존 provider/executor를 재사용하면 데이터 추가만으로 동작한다.
- 새로운 세계 질의는 `evaluator_id` 구현 하나를 등록하고 중앙 selector에 trait 이름 분기를 추가하지 않는다.
- 관련 없는 facet이나 정의를 추가해도 기존 ruleset의 snapshot hash와 결정이 바뀌지 않는다.
- actor 순서나 다른 방 actor의 추가/삭제가 기존 actor의 personality 생성 결과를 바꾸지 않는다.
- 모든 score 변화는 trace의 contribution 또는 gate evidence로 설명 가능하다.
- 종족 prior, 개인 관계, 성격, 감정, 능력, 역할/명령을 각각 독립 입력으로 검사한다.
- 임시 감정이 base personality를 수정하지 않는다.
- 장기 변화는 source event/memory와 version을 반드시 가진다.

## 10. 피해야 할 구현

- trait 이름별 거대한 `match`/`if` 중앙 선택기
- `coward → flee`, `aggressive → attack`의 절대 매핑
- 수치가 실제 소비처 없이 설명문에만 존재하는 성격 시스템
- personality, mood, stress, need, skill, duty를 하나의 점수로 저장
- 매 heartbeat마다 전 세계의 모든 대상·행동 조합을 평가
- float 점수, 평가 중 RNG 소비, Dictionary 순회 순서 의존
- 임계값 하나만 사용해 행동이나 mental mode가 매 틱 진동
- 점수와 후보를 authoritative state에 중복 저장
- 첫 단계부터 범용 GOAP, 임의 곡선 편집기, 50개 facet을 구현

## 11. 주요 참고 자료

- [RimWorld 공식 게임 설명](https://rimworldgame.com/)
- [Ludeon: Alpha 6의 personality traits](https://ludeon.com/blog/2014/08/alpha-6-whole-new-world-released/)
- [Ludeon: Beta 18의 mental breaks](https://ludeon.com/blog/2017/11/rimworld-beta-18-a-world-of-story-is-released/)
- [RimWorld Wiki: Traits](https://rimworldwiki.com/wiki/Traits) — 커뮤니티 자료
- [RimWorld Wiki: Modding Tutorials](https://rimworldwiki.com/wiki/Modding_Tutorials) — 내부 구조는 비공식 역공학임
- [Bay 12: 2013 personality/value 개발 기록](https://www.bay12games.com/dwarves/dev_2013.html)
- [Bay 12: 2015 personality needs 개발 기록](https://www.bay12games.com/dwarves/dev_2015.html)
- [Bay 12: 2018 memory/stress 개발 기록](https://www.bay12games.com/dwarves/dev_2018.html)
- [Tarn Adams: Simulation Principles from Dwarf Fortress](https://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter41_Simulation_Principles_from_Dwarf_Fortress.pdf)
- [Tarn Adams: Secret Identities in Dwarf Fortress](https://cdn.aaai.org/ojs/12963/12963-52-16480-1-2-20201228.pdf)
- [Richard Evans: Modeling Individual Personalities in The Sims 3](https://media.gdcvault.com/gdc10/slides/Evans_Richard_ModelingIndividualPersonalitiesInTheSims3.pdf)
- [Henrik Fåhraeus: Emergent Stories in Crusader Kings II](https://media.gdcvault.com/GDC2014/Presentations/Fahraeus_Henrik_Emergent_Stories_in.pdf)
- [Game AI Pro: Behavior Selection Algorithms](https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter04_Behavior_Selection_Algorithms.pdf)
- [Game AI Pro 3: Choosing Effective Utility-Based Considerations](https://www.gameaipro.com/GameAIPro3/GameAIPro3_Chapter13_Choosing_Effective_Utility-Based_Considerations.pdf)
