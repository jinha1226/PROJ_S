# Phase 3 구현 프롬프트 — 던전 성격 반응 실험실

## 0. 현재 단일 목표

동일한 던전 조우를 **성격만 다른 네 캐릭터**에게 동시에 제시하고, 왜 서로 다른 반응을 골랐는지 비교할 수 있는 결정론적 실험 화면을 구현한다.

```text
같은 방 구조·종족·체력·장비·동료 관계·몬스터·거리
+ personality_seed로 생성된 성격 차이
→ 동일한 객관적 위협을 서로 다르게 평가
→ NORMAL에서는 교전 / 보호 / 도주 / 엄폐 / 버티기 중 하나 선택
→ 공황 임계치를 넘으면 PANIC으로 전환해 도주 / 동결 중 하나 선택
→ 선택 및 탈락 후보의 점수 기여를 UI에서 비교
```

마을의 일과보다 이 실험을 먼저 만드는 이유는 인과를 분리하기 위해서다. 위치·직업·배고픔 때문에 결과가 달라지는 상황을 제거하고, 성격이 판단과 행동에 실제로 연결되는지를 먼저 검증한다.

이 문서가 현재 Phase 3의 canonical 구현 계약이다. 장기 계층, 연구 근거, 확장 규칙은 `docs/PERSONALITY_BEHAVIOR_ARCHITECTURE.ko.md`를 따른다. 충돌할 경우 이 문서의 Phase 3 범위와 수치 계약이 우선하고, 새로운 설계 판단은 장기 아키텍처 문서에 먼저 반영한다.

핵심 구현 방식은 다음 조합으로 고정한다.

```text
계층형 Utility 선택
+ NORMAL/PANIC의 작은 상태기계
+ MOVE/ATTACK/HOLD/FREEZE 공통 executor
+ 결정론적 actor heartbeat
```

범용 GOAP와 거대한 behavior tree는 이번 단계에서 구현하지 않는다.

## 1. 기존 미완성 마을 변경의 처리

현재 작업 트리에는 중단된 마을 구현이 미커밋 상태로 남아 있다. 새로 처음부터 겹쳐 만들지 말고 아래처럼 안전하게 피벗한다.

### 유지

- snapshot v4와 두 cadence를 위한 기반
- 8방향 MOVE와 엄격한 diagonal flank 차단
- pure weighted pathfinder
- 같은 pre-action projection을 읽는 batch coordinator 골격
- `busy_until`, intent, last decision, bounded diagnostics 개념
- 15×15 grid와 pause/step/auto observer 기반
- 기존 `DamageSystem`, species prior, 방향성 personal relation

### 새 목표에 맞게 변경

- `system.npc_tick`은 lead·ally·threat 모두 처리하는 `system.actor_tick`으로 이름을 일반화한다.
- `AgentState`에서 마을 profile·욕구·routine을 제거하고 controller·chamber·성격·감정·위협 인지 상태를 넣는다.
- `NpcCoordinator`를 `ActorCoordinator` 또는 동등한 일반 이름으로 바꾸고 반응 실험 batch를 처리한다.
- 활동 timing은 WORK/EAT/REST/SOCIALIZE 대신 MOVE/ATTACK/HOLD/FREEZE/ESCAPE를 다룬다.
- Session과 UI의 village roster/needs/routine을 chamber comparison/reaction inspector로 교체한다.
- ruleset은 `phase3-dungeon-personality-lab-v1`로 다시 고정한다.

### 제거 또는 교체

- 마을 좌표·직업·일과용 `AgentProfileRegistry`
- hunger/fatigue/social_need 루프
- conversation 전용 `NpcMemory`와 familiarity 확장
- 24×24 마을 fixture와 10명 roster
- 마을 전용 inspector 문구

마을 설계 문서는 future backlog로 보존할 수 있지만 Phase 3 기준으로 참조하면 안 된다.

## 2. 이번 단계의 구현 범위

반드시 구현한다.

- 15×15, 2×2 controlled encounter chamber
- lead 4명 + passive ally 4명 + 동일 melee threat 4마리
- 별도 `world_seed`와 `personality_seed`
- seed 기반 성격 4축 생성과 snapshot 저장
- versioned `PersonalityFacetDef`, `MentalModeDef`, `ActionDef`, `GateDef`, `ConsiderationDef`, `CurveDef`
- threat appearance와 chamber-local perception
- fear/anger 상태와 순수 ThreatAppraisal
- `NORMAL ↔ PANIC` mode transition과 hysteresis
- NORMAL의 `ENGAGE`, `PROTECT`, `FLEE`, `TAKE_COVER`, `HOLD`
- PANIC의 `FLEE`, `FREEZE`
- hard gate + fixed-point Utility + commitment/cooldown
- 8방향 이동, weighted path, 근접 공격·물리 피해·명시적 ESCAPE
- actor tick batch decide/resolve/commit
- 후보 점수와 기여 항목을 보여주는 15×15 DEBUG LAB UI
- save/load/journal replay와 동일 seed 재현
- mirrored chamber·trait 단조성·100 personality seed 회귀

이번 단계에서는 구현하지 않는다.

- 마을 일과·직업·욕구
- 범용 플레이어 FOV, 미니맵, 먼 타일 auto-walk
- 소문·평판·장기 episodic memory
- 장비·방어력·명중·회피·스킬을 포함한 완전 전투
- 랜덤 명중이나 랜덤 피해
- 여러 종의 몬스터 생태·먹이·영역·무리
- 완전 동시 이동, 자리 교환, 이동 chain
- archetype 이름에서 행동을 직접 고르는 scripted AI
- trait 이름을 검사하는 중앙 `if`/`match` 선택기
- GOAP, behavior tree, ECS, 비동기 core Timer

## 3. 실험 통제 원칙

성격 이외의 조건은 네 chamber에서 같아야 한다.

- lead의 species, max HP, current HP, attack power, 위치가 같다.
- ally의 species, HP, lead→ally 관계와 위치가 같다.
- threat의 species, HP, attack power, target policy와 위치가 같다.
- 방의 terrain, cover, retreat, engage, protect 위치가 chamber-local 좌표에서 같다.
- 위협은 같은 world time에 한 번씩 나타난다.
- 첫 판단은 같은 activation projection을 읽는다.
- 방 사이 entity는 서로 인식·목표 지정·경로 탐색·관계 형성을 하지 않는다.
- 행동 선택에는 RNG를 쓰지 않는다.

비교용 default personality seed에서 여러 반응이 보이도록 seed 자체를 고를 수는 있다. 특정 slot이나 이름을 보고 행동 점수를 보정하는 예외 코드는 금지한다.

## 4. 15×15 mirrored chamber fixture

전체 world는 정확히 15×15다.

```text
외곽 벽: x=0, x=14, y=0, y=14
중앙 벽: x=7 전체, y=7 전체

NW interior: x=1..6,  y=1..6
NE interior: x=8..13, y=1..6
SW interior: x=1..6,  y=8..13
SE interior: x=8..13, y=8..13
```

각 chamber는 `trial_slot = 0..3`과 6×6 local coordinate를 가진다. 네 방은 반사 변환이 아니라 동일 local layout의 translation으로 만든다.

권장 local semantic fixture:

```text
threat_spawn  (3,1)
pillar_wall   (2,2)
cover_tile    (1,3)   # pillar가 threat의 직선·최단 접근을 끊는 이동 가능한 칸
intercept     (3,3)
lead_start    (2,4)
ally_start    (3,4)
retreat       (1,5)
```

모든 tie-break와 진단에는 가능한 한 전역 좌표 대신 `trial_slot`, semantic target ID, local coordinate를 사용한다. 동일 성격을 네 방에 복제했을 때 action class와 점수가 같아야 한다.

Actor bootstrap 순서는 slot마다 아래와 같이 고정한다.

```text
lead → ally → dormant threat
```

이름과 entity ID는 표시용일 뿐 판단 입력으로 쓰지 않는다.

## 5. 시간과 encounter phase

정착된 snapshot에는 아래 두 repeating schedule만 존재한다.

```text
system.environment_tick  priority=100  repeat=100
system.actor_tick        priority=200  repeat=100
```

100 world-time은 기존 abstract 1분이다. 같은 시각에는 환경이 먼저, actor batch가 다음이다.

lab phase는 snapshot에 저장한다.

```text
ARMED     T0, threat entity는 dormant
ACTIVE    첫 actor tick T100에서 네 threat 동시 활성화
COMPLETE  모든 lead가 사망/탈출했거나 명시적 종료 조건 충족
```

T100 actor tick:

1. 네 `encounter.threat_appeared`를 slot 순서로 emit한다.
2. 네 lead가 자기 chamber의 threat만 인지한다.
3. 네 `perception.threat_noticed`를 slot 순서로 emit한다.
4. 같은 activation projection에서 네 lead의 첫 반응을 계산한다.
5. 첫 tick에 threat와 ally는 `HOLD`하여 자극 출현 직후의 lead 반응을 분리한다.

T200부터:

- passive ally는 계속 HOLD한다.
- threat는 자기 chamber의 ally가 살아 있고 `encounter_status = ACTIVE`이면 ally에게 접근하고 인접 시 공격한다.
- ally가 죽으면 살아 있고 ACTIVE인 lead를 fallback target으로 삼고, lead도 ESCAPED이거나 죽었으면 HOLD한다.
- lead는 매 ready tick에 appraisal과 후보를 다시 계산한다.

`step_index`는 accepted 외부 WAIT/command 수만 증가한다. 내부 actor 행동은 추가로 증가시키지 않는다. schedule handler는 새 logical schedule을 만들지 않으며, 개체 행동 간격은 `busy_until`로 표현한다.

## 6. 성격 생성

### 6.1 정의와 `PersonalityProfile`

네 축을 `0..999` 정수로 저장하되, 코드 필드 네 개로 고정하지 않는다.

```text
boldness    위험을 감수하는 정도
aggression  위협에 접근·공격하려는 정도
altruism    동료 위험을 자기 안전보다 우선하는 정도
composure   공포 속에서도 계획된 행동을 유지하는 정도
```

UI가 보여주는 “대담함/호전적” 같은 label은 수치에서 파생한 설명일 뿐 AI 입력이 아니다.

정의 registry:

```text
PersonalityFacetDef
  def_version
  facet_id
  min_value / neutral_value / max_value
  low_label / high_label
```

snapshot instance:

```text
PersonalityProfile
  profile_schema_version
  generation_ruleset_id
  facet_rows: [{facet_id, base_value}]
```

- `facet_rows`는 `facet_id` 오름차순이며 중복을 허용하지 않는다.
- 이번 ruleset은 위 네 ID가 정확히 한 번씩 있어야 한다.
- selector는 `boldness` 같은 이름별 분기문을 갖지 않고 등록된 consideration input으로 조회한다.
- 알 수 없는 facet, 누락 facet, 중복 facet, 범위 밖 값은 snapshot restore에서 거부한다.
- values, categorical trait, needs를 사용하지도 않으면서 빈 범용 필드로 미리 넣지 않는다. 실제 소비처가 생길 때 별도 typed component와 명시적 migration으로 추가한다.
- `base_value`는 fear/anger나 임시 상태 때문에 변경하지 않는다.

### 6.2 facet의 의미 경계

- `boldness`는 계산된 위험 감수 성향이며 감정을 억제하는 능력이 아니다.
- `composure`는 감정 속 계획 유지 능력이며 위험을 좋아하는 정도가 아니다.
- `aggression`은 공격적 해결 선호이며 용기나 전투 실력이 아니다.
- `altruism`은 일반적인 타인 배려이며 lead→ally의 개인 관계나 duty가 아니다.
- species/culture/faction prior, 관계, skill, role/duty는 personality와 독립된 입력으로 유지한다.

### 6.3 별도 seed와 실험용 Latin-hypercube

- `world_seed`는 map, actor, threat 조건을 고정한다.
- `personality_seed`만 바꿔 성격을 다시 뽑는다.
- 성격 생성은 `world.rng`를 소비하지 않는다.
- Godot `hash()`를 사용하지 않고 아래 `sha256-u31-v1` keyed algorithm을 사용한다.
- 생성 결과는 snapshot에 직접 저장한다.

네 명이 우연히 모두 비슷해지는 것을 막기 위해 facet마다 네 strata를 한 번씩 사용한다.

```text
0..249, 250..499, 500..749, 750..999
```

`sha256-u31-v1`:

1. seed는 canonical decimal ASCII로 만든다.
2. 각 facet과 고정 domain slot `0..3`에 대해 `generator_id|seed|facet_id|slot|perm`의 UTF-8 SHA-256을 계산한다.
3. digest 첫 4바이트를 big-endian으로 읽고 최상위 비트를 지운 `u31`을 만든다.
4. 네 slot을 `(u31, slot)`로 정렬한 rank를 stratum으로 쓴다.
5. 같은 방식의 `...|jitter` key에서 `u31 % 250`을 구한다.
6. `base_value = stratum × 250 + jitter`다.

permutation domain은 실제 존재하는 actor 목록이 아니라 항상 semantic trial slot `0..3`이다. slot actor를 일시적으로 제거하거나 다른 controller를 추가해도 기존 profile이 바뀌지 않는다. slot을 순회하며 하나의 mutable RNG를 공유하지 않는다.

snapshot header의 `PERSONALITY_GENERATOR_RULESET_ID`와 각 profile의 `generation_ruleset_id`는 반드시 같아야 한다.

행동 결정 도중에는 personality RNG를 다시 읽지 않는다.

Latin-hypercube는 네 비교군의 차이를 보장하기 위한 실험 전용 생성기다. 이후 일반 세계 생성기는 `species/culture 분포 + 배경 modifier + 상관된 개인 편차 + 희귀 trait` 방식의 별도 ruleset을 사용한다. production 인구가 네 구간에 균등하게 나오도록 재사용하지 않는다.

## 7. authoritative 상태와 pure projection

### 7.1 snapshot 상태

`LabActorState` 또는 개편된 `AgentState`:

```text
entity_id
controller_kind       LEAD / PASSIVE_ALLY / MELEE_THREAT
trial_slot            0..3
encounter_status      ACTIVE / ESCAPED; DEAD는 entity health에서 파생
busy_until
current_activity
current_reaction
intent_target_entity_id
intent_target_position
intent_started_time

personality_profile   LEAD에만 definition-backed facet rows
fear                   0..2000
anger                  0..2000
emotion_updated_time
mental_mode            NORMAL / PANIC
mental_mode_since

active_threat_id
threat_notice_event_id
last_seen_position
last_seen_time

guarded_until
commitment_until
action_history_rows    action_id 정렬, cooldown_until/last_committed_time/consecutive_commit_count, bounded
last_decision_time
last_decision_event_id
```

snapshot wire에서는 `personality_profile` key를 LEAD row에만 요구하고 PASSIVE_ALLY/MELEE_THREAT row에서는 금지한다. 문자열 `none`, 빈 Dictionary, 임의 기본 profile을 저장하지 않는다. 메모리 객체가 nullable 필드를 쓰더라도 controller별 validator가 이 wire 계약을 강제한다.

`current_reaction`은 ENGAGE/PROTECT 같은 지속 의도이고 `current_activity`는 이번 commit의 MOVE/MELEE_ATTACK/HOLD/FREEZE/ESCAPE leaf다. 한 ENGAGE reaction이 여러 heartbeat의 MOVE 뒤 MELEE_ATTACK으로 바뀌어도 reaction과 leaf를 같은 필드에 덮어쓰지 않는다.

`EncounterLabState`:

```text
personality_seed
phase
activation_time
threat_profile_id
appearance_event_ids  slot 0..3
```

bootstrap에서 lead의 `fear = 0`, `anger = 0`, `mental_mode = NORMAL`, `current_reaction = NONE`, `emotion_updated_time = world_time`, `last_decision_event_id = -1`로 고정한다.

### 7.2 저장하지 않는 pure projection

```text
ThreatAppraisal
  objective_danger
  species_fear_term
  species_hostility_term
  ally_support
  boldness_relief
  composure_relief
  perceived_threat
  attack_drive
  ally_concern
  panic_pressure

ReactionCandidate
  reaction_id
  decision_tier
  legal
  target entity/semantic tile
  score
  rejection_reason
  gate rows
  consideration rows

ReactionIntent
  reaction_id
  leaf_action_id       MOVE / MELEE_ATTACK / HOLD / FREEZE / ESCAPE
  target entity/semantic tile

DecisionTrace
  context/appraisal summary
  mode transition evidence
  all bounded candidate evaluations
  selected reaction and target
  commitment/switch evidence
```

appraisal/candidate query, inspector DTO와 preview는 world, RNG, event, ID를 바꾸지 않는다. 실제 결정의 bounded `DecisionTrace`는 범용 `ai.decision_selected` event data에 한 번 기록하고 actor state는 `last_decision_event_id`만 참조한다. 점수·후보·경로를 authoritative actor state에 중복 저장하지 않는다.

## 8. 관계와 종족 prior

네 lead와 ally는 같은 species·같은 관계 조건을 가진다. threat도 네 방에서 같은 species다.

- lead→ally effective trust/fear/hostility가 네 방에서 같다.
- lead→threat species base fear/hostility가 네 방에서 같다.
- protect 점수는 `altruism + lead→ally relation + ally가 실제 표적인지`를 사용한다.
- engage와 perceived threat는 lead→threat species fear/hostility를 사용한다.
- `instigator_id`는 책임자이지 자동 인지 정보가 아니다.

effective relation은 기존 `RelationshipSystem`의 정확한 계약을 그대로 사용한다.

```text
trust = clamp(species base trust + personal delta[-40,+40], -100, 100)
fear = clamp(species base fear + personal delta[-30,+30], 0, 100)
hostility = clamp(species base hostility + grievance/5 - gratitude/10, 0, 100)
```

personality는 이 관계값을 수정하지 않고 Utility의 별도 입력으로만 들어간다. 따라서 강한 종간 prior를 한 번의 도움이나 personality 하나가 관계 단계에서 즉시 지우지 못한다.

Utility에서 relation input을 쓰는 단일 consideration의 절대 contribution은 최대 500, 단일 personality facet consideration은 최대 300으로 registry가 검증한다. 이는 모든 상황에서 종족이 행동을 강제한다는 뜻이 아니다. 부상, 경로, ally 위험, mental mode 등 다른 독립 입력을 합친 최종 행동은 달라질 수 있다.

이번 실험에서는 conversation/familiarity를 추가하지 않는다. 기존 aid/harm 관계는 보존하되 자동으로 모든 관찰자에게 적용하지 않는다.

## 9. 정의 기반 Utility와 단조성 계약

### 9.1 정의 타입

행동별 공식이나 facet 이름을 coordinator에 직접 쓰지 않는다.

```text
ActionDef
  action_id / decision_tier / base_score
  allowed_mode_ids / tie_break_rank
  commitment_duration / cooldown_duration / switch_margin
  candidate_provider_id
  gates: Array[GateDef]
  considerations: Array[ConsiderationDef]
  intent_builder_id / interrupt_policy_id

MentalModeDef
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

Phase 3에서 구현할 curve는 `linear_up`, `linear_down`, `threshold_up`, `threshold_down` 네 개뿐이다. 모든 입력과 curve 출력은 `0..1000` 고정소수 정수다.

Godot/GDScript에서는 범용 `Registry<T>`나 규칙 DSL을 만들지 않는다. `PersonalityDefinitionRegistry`와 `DecisionRulesetRegistry` 두 구체 registry, 그리고 공통 validation/fixed-point helper만 둔다. Phase 3 정의는 명시적 필드를 가진 typed `RefCounted` 객체로 노출한다. evaluator별 config가 필요하면 typed config 객체를 쓰며 자유형 Dictionary를 selector 안까지 전달하지 않는다. 외부 JSON 정의 로더나 에디터는 이번 범위가 아니다.

```text
raw input
→ versioned normalize/clamp
→ piecewise-linear curve
→ signed weight contribution

score = clamp(base_score + sum(contribution), SCORE_MIN, SCORE_MAX)
```

`score_combiner_id = weighted-sum-v1` 뒤에 결합을 격리한다. 곱셈형 Utility나 비단조 curve는 실제 소비처가 생긴 새 ruleset에서만 추가한다.

Phase 3 숫자 범위:

```text
SCORE_MIN = -1_000_000
SCORE_MAX =  1_000_000
base_score = -10_000..10_000
signed_weight_milli = -2_000..2_000
considerations per action <= 12
curve control points <= 8, x 오름차순, (0, y0)과 (1000, y1) 필수
```

`curve_output × signed_weight_milli ÷ 1000`은 64비트 중간값에서 `trunc_toward_zero`를 사용한다. piecewise interpolation도 `y0 + trunc_toward_zero((x-x0) × (y1-y0) / (x1-x0))`로 고정한다. 이 연산은 전용 integer helper 하나만 사용하고, 범위나 overflow 계약을 위반하는 definition은 registry decode에서 거부한다.

Gate는 점수를 크게 깎는 흉내를 내지 않고 후보를 명시적으로 불법 처리한다. 최소 gate:

- actor alive/ready
- 현재 mental mode에서 action 허용
- threat/ally를 실제로 인지함
- target이 같은 chamber에 존재하며 유효함
- 필요한 path/사거리/점유 조건 충족
- action cooldown 아님

Evaluator 반환값은 `raw_input`, `normalized_input`, `curve_output`, `contribution`, `veto/reason`, `evidence_ids`를 포함하며 완전 순수해야 한다.

### 9.2 ThreatAppraisal 입력

모든 계산은 정수와 versioned 상수만 사용한다. 최소 입력:

- threat profile power
- lead와 threat의 chamber-local 거리
- lead HP 손실
- threat가 ally를 target 중인지
- effective species fear/hostility
- lead→ally trust
- personality 4축
- 현재 fear/anger

appraisal은 action을 직접 선택하지 않고 consideration이 소비할 정규화 입력을 만든다. `DecisionContext`는 해당 actor의 perception, 관계, 상태만 읽으며 FOV 밖 실제 threat 위치나 다른 chamber의 객관 상태를 우회 참조하지 않는다.

### 9.3 AffectRules v1

fear/anger를 선언만 해두지 말고 다음 정수 규칙으로 모든 lead에 갱신한다. 관계의 effective fear/hostility는 기존 `0..100` 값을 `×10`해 정규화한다.

```text
distance_pressure = clamp(1000 - max(0, chebyshev_distance - 1) × 160, 0, 1000)
objective_danger = trunc_toward_zero((2 × threat_power_norm + distance_pressure) / 3)
hp_loss_norm = trunc_toward_zero((max_hp - hp) × 1000 / max_hp)

perceived_threat_target = clamp(
  objective_danger
  + relation_fear_norm / 2
  + hp_loss_norm / 2
  - boldness / 3,
  0, 2000)

anger_target = clamp(
  relation_hostility_norm
  + aggression / 2
  + (200 if observed threat currently targets ally else 0),
  0, 2000)

panic_pressure = clamp(fear + hp_loss_norm / 2 - composure / 2, 0, 2000)
PANIC_ENTER_THRESHOLD = 850
PANIC_EXIT_THRESHOLD = 500
```

`threat_power_norm`은 threat profile의 검증된 `0..1000` 값이다. 인지한 active threat가 없으면 두 target은 0으로 둔다.

heartbeat의 affect 접근 속도:

```text
elapsed_quanta = (now - emotion_updated_time) / 100

fear가 target보다 낮음  → quanta당 최대 240 상승
fear가 target보다 높음  → quanta당 최대 (80 + composure / 10) 하강
anger가 target보다 낮음 → quanta당 최대 180 상승
anger가 target보다 높음 → quanta당 최대 100 하강
```

값을 target을 지나치지 않게 접근시키고 `0..2000`으로 clamp한다. 처리한 정수 quanta만큼 `emotion_updated_time`을 전진시킨다.

순서는 아래로 고정한다.

```text
모든 actor 지각 갱신
→ 같은 pre-action projection 고정
→ 모든 lead의 ThreatStimulus 계산
→ busy/FREEZE 여부와 무관하게 elapsed-time fear/anger 갱신
→ 갱신된 affect로 ThreatAppraisal 계산
→ 모든 lead의 NORMAL/PANIC 전환 판정과 사건 사전 구성
→ ready lead만 reaction 후보 평가
```

mode 전환은 `commitment_until = now`로 만들고 `current_reaction = NONE`으로 지워 기존 의도를 무효화한다. 이미 start-commit된 `current_activity`와 `busy_until`은 중간 취소하지 않으며, ready가 된 다음 선택부터 새 mode 후보를 사용한다.

### 9.4 단조성

정확한 입력 정의, curve, weight는 registry에 모으고 아래를 자동 테스트로 고정한다.

- boldness 증가: ENGAGE 점수는 감소하지 않고 FLEE 점수는 증가하지 않는다.
- aggression 증가: ENGAGE 점수는 감소하지 않는다.
- altruism 증가: ally가 실제 위험할 때 PROTECT 점수는 감소하지 않는다.
- ally가 위험하지 않을 때 altruism만으로 PROTECT가 생성되면 안 된다.
- composure 증가: panic pressure, FREEZE 점수와 freeze duration은 증가하지 않는다.
- species fear 증가: perceived threat와 회피 압력이 감소하지 않는다.
- species hostility 증가: attack drive와 ENGAGE 점수가 감소하지 않는다.
- HP가 낮아지면 회피 압력이 감소하지 않는다.

점수 overflow를 막고 각 중간값을 명시 범위로 clamp한다. float와 `rand*()`를 사용하지 않는다.

## 10. mental mode, 반응 후보와 leaf 행동

### 10.1 두 단계 선택

모든 lead는 busy/FREEZE 여부와 무관하게 actor heartbeat마다 mode transition을 검사한다. 그중 ready lead만 전환 후 `MentalModeDef.candidate_action_ids`에 등록된 reaction 후보를 평가한다. `FLEE`처럼 두 mode에서 쓸 action은 `ActionDef.allowed_mode_ids`에 둘 다 등록한다.

```text
NORMAL candidates: ENGAGE, PROTECT, FLEE, TAKE_COVER, HOLD
PANIC candidates:  FLEE, FREEZE
```

공황에는 서로 다른 진입/해제 임계값을 둔다.

```text
panic_pressure >= PANIC_ENTER_THRESHOLD → PANIC
panic_pressure <= PANIC_EXIT_THRESHOLD  → NORMAL
PANIC_EXIT_THRESHOLD < PANIC_ENTER_THRESHOLD
```

mode 전환은 `ai.mental_mode_changed` 사건으로 남긴다. NORMAL과 PANIC은 `transition_policy_id = panic-hysteresis-v1`을 사용한다. 이번 단계에서 BERSERK/SURRENDER는 구현하지 않는다. 후속 mode에는 새 `MentalModeDef`/`ActionDef`뿐 아니라 등록된 pure transition strategy가 필요하지만, 후보 목록을 읽는 selector는 그대로 재사용해야 한다. 후보 목록과 tie-break rank를 coordinator의 mode별 `match`에 중복 작성하지 않는다.

### `ENGAGE`

- intent builder는 threat에 인접하면 `MELEE_ATTACK`, 아니면 path의 next hop 한 칸 `MOVE`를 만든다.
- aggression, hostility, boldness, anger가 주로 올리고 perceived threat가 내린다.

### `PROTECT`

- ally가 threat의 현재 target일 때만 합법.
- intent builder는 intercept semantic tile로 `MOVE`하거나, 이미 위협과 인접하면 `MELEE_ATTACK`을 만든다.
- altruism과 lead→ally 관계가 올리고 panic pressure가 내린다.

### `FLEE`

- retreat semantic tile까지는 next hop `MOVE`를 만든다.
- retreat tile에 이미 도착했으면 `ESCAPE`를 만들고 actor를 `ESCAPED`로 전환한다.
- perceived threat, 부상, fear가 올리고 boldness가 내린다.
- 퇴로가 없으면 불법과 이유를 기록한다.

`ESCAPE` commit은 `encounter.actor_escaped`를 emit하고 `encounter_status = ESCAPED`로 만든다. escaped actor는 snapshot의 역사적 entity로는 남지만 occupancy, path obstacle, target 후보, rendering, 이후 actor tick에서 제외한다. 모든 lead가 `ESCAPED`이거나 entity health상 죽었으면 lab phase를 `COMPLETE`로 전환한다.

### `TAKE_COVER`

- cover semantic tile까지는 `MOVE`를 만든다.
- cover에 이미 있으면 `HOLD`로 정착하고 방어 태세를 적용한다.
- path 불가/점유 시 불법 이유를 기록한다.

### `HOLD`

- intent builder는 제자리 `HOLD`를 만들고 `guarded_until`을 갱신한다.
- NORMAL의 항상 합법인 최소 fallback이어야 한다.

### `FREEZE`

- PANIC mode에서만 합법.
- `freeze_quanta = 1 + (999 - composure) / 250`으로 1..4를 계산한다.
- leaf `FREEZE`가 `current_activity = FREEZE`, `busy_until = now + freeze_quanta × 100`을 정하며 해당 시각 전에는 새 반응을 고르지 않는다.
- composure가 높을수록 FREEZE consideration과 duration이 증가하지 않아야 한다.

PANIC에서는 경로가 있는 FLEE나 FREEZE 중 최소 하나가 반드시 합법이어야 한다.

### 10.2 commitment와 cooldown

`busy_until`은 leaf 행동을 새로 실행할 수 없는 시각이고 `commitment_until`은 현재 의도를 쉽게 바꾸지 않는 시각이다.

```text
현재 reaction 불법/실패/완료     → 즉시 재선택
mental mode가 바뀜               → mode에 맞지 않는 reaction 즉시 중단
commitment_until 이전            → 현재 reaction 유지
challenger >= current + switch_margin → 전환
그 외                            → 현재 reaction 유지
```

action별 cooldown과 bounded repeat count를 저장해 매 tick 같은 행동을 재선택하거나 두 행동 사이를 진동하지 않게 한다. emergency mode transition은 정상 commitment를 중단할 수 있다.

Phase 3의 정의값은 world-time 단위로 다음과 같이 고정한다.

| reaction | commitment_duration | cooldown_duration | switch_margin |
|---|---:|---:|---:|
| ENGAGE | 200 | 100 | 100 |
| PROTECT | 200 | 100 | 100 |
| FLEE | 200 | 100 | 100 |
| TAKE_COVER | 200 | 200 | 100 |
| HOLD | 100 | 0 | 50 |
| FREEZE | 0 (`busy_until`이 동적 지속시간 담당) | 0 | 0 |

지속 reaction의 cooldown 계약은 다음으로 고정한다.

- 현재 reaction을 계속하는 후보는 자기 action의 cooldown gate를 무시한다. cooldown은 새로 그 reaction에 진입하려는 후보에만 gate로 적용한다.
- commitment가 끝난 뒤에는 현재 reaction과 challenger를 같은 frozen `DecisionContext`/projection에서 모두 다시 평가한다. 이전 decision trace의 점수를 current score로 재사용하지 않는다.
- 현재 reaction이 여전히 합법이면 `challenger_score >= current_score + current_action.switch_margin`일 때만 전환한다.
- cooldown은 매 leaf commit 때 시작하지 않는다. reaction이 완료되거나 다른 reaction으로 전환될 때, 떠나는 action row의 `cooldown_until = now + cooldown_duration`으로 시작한다.
- mode transition은 이 규칙보다 우선하며 기존 reaction을 종료하고 그 action의 cooldown을 시작한다. `HOLD`와 `FREEZE`는 cooldown 0이라 fallback을 봉쇄하지 않는다.
- 새 reaction의 `commitment_until`은 첫 leaf commit이 성공하는 atomic batch에서 `now + commitment_duration`으로 설정한다. 전환하려던 leaf commit이 충돌 또는 legality 재검증에서 실패하면 새 reaction 진입과 history를 commit하지 않으며, 기존 reaction·commitment·cooldown도 그대로 유지한다.

동점 규칙:

```text
score 내림차순
→ ActionDef.tie_break_rank 오름차순
→ semantic target ID
→ chamber-local y, x
→ actor ID
```

slot 번호, 이름, 전역 좌표를 점수 입력으로 쓰지 않는다.

## 11. 이동·batch·근접 전투

### 이동

- `0 < max(abs(dx), abs(dy)) == 1`인 8방향 한 칸 MOVE.
- 대각선 두 flank의 terrain과 살아 있는 점유가 모두 열려야 한다.
- 대각 비용은 목적지 terrain cost 그대로다.
- `WorldState.cardinal_neighbors()`는 환경 4방향 전파용으로 유지한다.
- path query는 pure이며 매 행동에서 next hop만 다시 검증한다.

### actor tick batch

```text
perceive all into staging
→ freeze pre-action projection
→ project affect updates and mental-mode transitions for all
→ decide all ready actors from the same projection
→ materialize ReactionIntent leaf actions
→ resolve destination conflict
→ accumulate and order attack damage requests
→ preflight every state/event/action/history mutation
→ atomically commit affect/mode/decision, resolved leaf actions, damage/death
```

- 방 사이 충돌은 구조상 없어야 하며 controller도 chamber filter를 강제한다.
- 같은 방 destination conflict는 decision tier, selected score, `ActionDef.tie_break_rank`, actor ID 순으로 푼다.
- 자리 교환과 pre-action 점유 칸 진입은 금지한다.
- attack legality는 pre-action position에서 판정하고 시작 시 commit한다.
- 같은 batch 시작 시 살아 있던 공격자는 그 batch의 committed 공격을 완료한다.
- damage request 적용 순서는 `(target_id, attacker_id, action_event_id)`로 고정한다.

### 최소 전투

별도 `MeleeCombatSystem`을 둔다.

- Chebyshev 1 인접만 공격 가능.
- 명중은 확정, damage는 threat/profile의 고정 정수.
- `action.melee_attack`을 먼저 emit한다.
- 기존 `DamageSystem.apply_damage(..., "physical", action_event.id)`를 사용한다.
- HOLD가 성공하면 `guarded_until = now + 200`이다.
- `now < guarded_until`인 actor가 받는 고정 피해는 `damage - floor(damage × 250 / 1000)`으로 25% 감소한다.
- cover의 물리적 이점은 mirrored `pillar_wall` 때문에 threat의 접근 경로가 길어지는 것이며, 별도의 보이지 않는 cover 보너스를 더하지 않는다.
- 사망한 entity는 다음 tick 후보에서 제외한다.

AI MOVE의 `action.move`에도 `ai.decision_selected` cause를 전달할 수 있게 movement commit API를 확장한다.

## 12. 사건 인과 계약

최소 chain:

```text
encounter.threat_appeared
→ perception.threat_noticed
→ 선택적으로 ai.mental_mode_changed
→ ai.decision_selected
→ action.move 또는 action.melee_attack / action.hold / action.freeze / encounter.actor_escaped
→ combat.physical_damage
→ entity.died
```

`ai.decision_selected.data`에는 bounded JSON-safe 진단을 넣는다.

```text
trial_slot
reaction_id
personality facet rows
appraisal summary
mental mode와 transition evidence
candidate별 gate 결과
candidate별 raw input / curve / contribution / score
commitment 유지 또는 switch 근거
semantic target
```

`AgentState.last_decision_event_id`는 이 사건을 가리킨다. 같은 candidate diagnostics를 actor state에 다시 복사하지 않는다. UI가 trace contribution을 다시 합산하면 실제 선택 점수와 정확히 같아야 한다.

trace의 bounded 계약:

```text
candidates <= 6
gates per candidate <= 8
considerations per candidate <= 12
evidence references per row <= 4
stable ID <= 64 ASCII bytes, [a-z0-9._-]
reason code <= 96 ASCII bytes
encoded ai.decision_selected.data <= 32 KiB
```

event/entity/time ID는 JSON number가 아니라 canonical decimal string으로 넣는다. `ai.decision_selected` 전용 payload validator는 row bounds뿐 아니라 actor 일치, 등록 definition, event/entity 참조, 같은 chamber target을 검사한다. restore 시 `last_decision_event_id`는 bootstrap의 canonical `-1`이거나 같은 actor의 실제 `ai.decision_selected`를 가리켜야 한다.

`action_history_rows`는 최대 8개의 희소 행이며 `action_id` 정렬, 중복 금지, 등록 action만 허용한다. `last_committed_time`과 `consecutive_commit_count`는 후보를 고른 순간이 아니라 destination conflict 해결과 leaf legality 재검증 뒤 실제 leaf action commit이 성공했을 때만 갱신한다. reaction 진입의 첫 성공 leaf는 count 1, 같은 reaction의 후속 성공 leaf는 bounded increment, 나갔다 재진입한 첫 성공 leaf는 다시 1이다. `cooldown_until`은 leaf마다가 아니라 reaction 완료/전환을 atomic commit할 때만 갱신한다.

appearance는 slot당 한 번, perception은 lead당 해당 appearance source에 한 번만 기록한다. 사건의 cause/instigator가 끊기거나 다른 chamber entity를 참조하면 실패다.

Simulator의 event headroom preflight는 한 actor tick에서 lead 4 + threat 4가 만들 수 있는 최악 사건 수를 보수적으로 포함한다.

actor batch는 모든 mode change, decision trace, intent, target, 사건 headroom을 staging 상태에서 먼저 검증한다. 한 actor의 event를 실제 world에 쓴 뒤 뒤쪽 actor의 오류로 중단하는 부분 commit은 금지한다. 사전 검증이 하나라도 실패하면 actor batch 전체가 무변경 실패해야 한다.

성공 batch의 event ID 배정 순서는 `appearance/perception의 trial_slot → mode change의 trial_slot → decision의 trial_slot → leaf action의 trial_slot → (target_id, attacker_id)`로 고정한다. cause ID는 staging에서 이 순서를 이용해 미리 해석하고 commit 시 다시 계산하지 않는다.

## 13. 버전과 snapshot

미완성 v4는 아직 배포되지 않았으므로 그대로 재기준화한다.

```text
SNAPSHOT_VERSION = 4
RULESET_VERSION = "phase3-dungeon-personality-lab-v1"
PERSONALITY_SCHEMA_ID = "personality-facets-v1"
PERSONALITY_GENERATOR_RULESET_ID = "personality-lab-latin-hypercube-v1"
KEYED_HASH_RULESET_ID = "sha256-u31-v1"
DECISION_RULESET_ID = "dungeon-hierarchical-utility-v1"
SCORE_COMBINER_ID = "weighted-sum-v1"
COMBAT_RULESET_ID = "fixed-melee-v1"
SESSION_FORMAT_VERSION = 2
SAVE_PATH = "user://living_world_personality_lab_v2.json"
```

snapshot v3과 village partial snapshot은 암묵 변환하지 않고 명시적으로 거부한다.

snapshot v4는 최소 다음을 보존·검증한다.

- world/personality seed
- personality schema/generator/hash/decision/combiner ruleset IDs
- 두 canonical schedule
- EncounterLabState
- controller kind, trial slot, definition-backed personality, emotion, mental mode, threat perception
- current reaction/intent, encounter status, busy/commitment/guard, bounded action history
- last decision event reference
- entities, health, relations, events, cause chain
- 모든 next ID와 64-bit canonical decimal string

경로, 현재 candidate/score projection, appraisal projection, comparison DTO, camera/selection/pause/speed는 저장하지 않는다. 결정 당시의 bounded trace는 `ai.decision_selected` 사건에만 저장한다.

## 14. Session detached API

UI는 simulator/world를 직접 읽지 않는다.

```gdscript
reset_lab(world_seed: int, personality_seed: int) -> bool
lab_status() -> Dictionary
observe_lab() -> Dictionary
lead_roster() -> Array[Dictionary]
inspect_reaction(entity_id: int) -> Dictionary
advance_ticks(count: int = 1) -> Dictionary
save_slot() / load_slot()
```

`advance_ticks()`는 우선 1과 10만 허용하고 각각 하나의 WAIT 100/1000을 제출한다. accepted 외부 command만 journal에 남긴다. actor 행동은 deterministic consequence이므로 journal에 중복 기록하지 않는다.

`observe_lab()`은 15×15=225 cells, sampled step/time, lab phase, four slot summary를 detached copy로 반환한다.

`inspect_reaction()`:

```text
identity / slot / position / HP
personality facet rows and derived display label
emotion fear/anger, mental mode와 전환 근거
threat and species base vs personal/effective relation
appraisal contribution breakdown
현재 mode candidates의 gate/score trace와 다른 mode action의 MODE_GATE 표시
selected reaction, target, action result
commitment/cooldown과 switch/retain 이유
recent causal events
```

DTO를 호출자가 변조해도 snapshot/RNG/event/ID가 바뀌면 안 된다.

## 15. 450×800 / 360×640 UI

- 15×15 전체 lab을 한 화면에 표시하고 camera 이동은 사용하지 않는다.
- lead glyph는 `1..4`, ally는 `a`, active threat는 `M`, dormant threat는 숨기거나 봉인 glyph로 구분한다.
- 화면 상단에 `DEBUG LAB · CONTROLLED STIMULUS`를 표시한다.
- 네 lead summary button을 1×4 또는 compact 2×2로 둔다.
- summary에는 dominant facets 1~2개, 현재 fear/mode, 선택 reaction을 짧게 표시한다.
- lead를 누르거나 grid lead를 누르면 inspector가 같은 entity ID를 선택한다.
- 선택 chamber의 테두리를 강조한다.

선택 inspector 최소 5줄:

```text
#slot 이름 · HP · 위치
대담/공격/이타/침착
공포/분노 · NORMAL/PANIC · 객관 위험/체감 위협
현재 mode 후보 점수 · 다른 mode 반응은 MODE_GATE
선택/유지 반응 → 목표 · 가장 큰 +/− 기여 또는 gate 이유
```

Drawer에는 raw input→curve→contribution 전체 행, gate와 rejection reason, commitment/cooldown, species base/personal/effective, 사건 chain, snapshot/journal을 표시한다.

controls:

```text
조우 시작/다음 tick   ▶/⏸   +10 tick   새 성격   리셋/저장
```

- 초기 PAUSED.
- auto는 wall clock이 아니라 timeout마다 `advance_ticks(1)`만 호출한다.
- focus loss, modal, save/load/reset 중 자동 일시정지한다.
- 백그라운드 복귀 catch-up은 하지 않는다.

## 16. 필수 테스트

### 기존 회귀 복구

- 기존 92개 테스트를 새 snapshot v4·두 cadence·8방향·15×15 계약에 정당하게 갱신한다.
- 테스트를 삭제하거나 실패를 무시하지 않는다.
- 먼저 현재 17 failures를 0으로 만든 뒤 새 기능 회귀를 완료한다.

### 정의 registry와 성격 생성

- facet/action/gate/consideration/curve의 unknown·duplicate·missing ID와 범위 밖 config 거부.
- MentalModeDef↔ActionDef cross-reference, allowed mode, unique tie-break rank, mode별 fallback 검증.
- facet row 순서를 바꿔 입력해도 canonical 정렬 결과가 같음.
- 네 curve의 endpoint, clamp, integer interpolation, 단조성 정확.
- 같은 personality seed/slot/facet은 항상 같은 값.
- 다른 personality seed는 world terrain/entity base 조건을 바꾸지 않음.
- 각 facet의 네 slot이 네 strata를 정확히 한 번씩 사용.
- 한 slot actor 추가/삭제가 다른 slot personality를 바꾸지 않음.
- generator/query가 world RNG를 바꾸지 않음.
- snapshot round trip 후 값 동일.

### 실험 대칭과 격리

- T100에 네 appearance와 네 perception이 정확히 한 번.
- 네 lead의 objective input이 local coordinate 기준 동일.
- 동일 personality 강제 주입 시 네 방의 appraisal/반응 class/점수가 같음.
- semantic target만 각 chamber translation과 일치.
- 다른 chamber entity는 perception, path, relation, candidate에 절대 등장하지 않음.

### 반응·관계 단조성

- boldness/aggression/altruism/composure와 species fear/hostility의 단조성 계약 전부 통과.
- ally가 표적이 아닐 때 altruism만으로 PROTECT 불가.
- 강한 species prior가 성격 한 축이나 한 번의 긍정 사건으로 즉시 반전되지 않음.
- default seed 첫 3 tick에 최소 3개 reaction class가 관찰되되 slot 예외 코드는 없음.
- 같은 evaluator trace를 합산한 점수와 selector가 사용한 점수가 정확히 같음.
- 관련 없는 새 facet definition을 기존 ruleset 바깥에 등록해도 기존 결과가 바뀌지 않음.

### mental mode와 전환 안정성

- busy/HOLD/FREEZE 중인 lead도 매 actor heartbeat에서 fear/anger와 `emotion_updated_time`이 갱신됨.
- AffectRules의 target 접근, clamp, integer quanta, save/load continuation이 정확.
- enter/exit threshold 사이에서 NORMAL/PANIC 진동 0.
- NORMAL에는 FREEZE가, PANIC에는 ENGAGE/PROTECT/COVER/HOLD가 후보로 생성되지 않음.
- PANIC에서 FLEE path가 없을 때 FREEZE fallback이 항상 합법.
- mode 전환은 기존 commitment를 올바르게 중단하고 cause event를 보존.
- switch margin 미만 challenger는 현재 반응을 뒤집지 않음.
- commitment 만료와 switch margin이 동일 projection의 재평가 점수로 작동.
- 지속 ENGAGE/FLEE가 자기 cooldown에 막히지 않고, cooldown은 reaction 완료/전환 시 정확한 world time부터 작동.
- HOLD/FREEZE의 cooldown 0이 fallback을 봉쇄하지 않음.
- `last_committed_time`/repeat count는 선택/충돌 패배 때가 아니라 실제 leaf commit 성공 때만 갱신되고, `cooldown_until`은 reaction 완료/전환 때만 갱신됨.

### 행동·전투

- 8방향 MOVE와 diagonal flank 규칙.
- 모든 이동은 한 칸이며 순간이동/중복 점유 0.
- path/appraisal/candidate query 완전 순수.
- threat는 자기 chamber ally만 target.
- ally 사망 뒤 threat는 같은 chamber ACTIVE lead만 fallback target으로 선택.
- attack→physical damage→death cause/instigator chain 정확.
- retreat 도착 후 ESCAPE는 정확히 한 번 발생하고 occupancy/target/render/tick에서 제외됨.
- 모든 lead가 죽었거나 ESCAPED이면 COMPLETE가 정확히 한 번 성립.
- pillar가 네 방에서 같은 path 차이를 만들고 guarded 25% 피해 감소가 같은 정수 결과를 냄.
- batch damage 순서와 save/load 결과 동일.
- FREEZE/HOLD/busy_until/commitment_until이 정확한 tick에 해제.

### 결정론·저장

- 같은 seed와 WAIT journal의 snapshot/event hash 동일.
- encounter 직전, perception 직후, move/attack 직후 save/load continuation 동일.
- UI ×1/×4 속도 최종 결과 동일.
- 100 personality seed × 최소 20 tick에서 unknown action, bad target, cross-room reference, out-of-bounds, duplicate occupancy 0.
- preview/inspector DTO가 RNG·ID·world를 바꾸지 않음.
- save wire에는 candidate/score projection 중복이 없고 `last_decision_event_id`가 유효한 trace를 가리킴.
- malformed/oversized decision trace와 cross-chamber evidence 참조는 restore에서 거부.
- batch의 마지막 actor preflight 실패를 주입해도 앞 actor의 mode/event/action/history가 하나도 부분 commit되지 않음.

### UI

- 15×15=225 cell.
- 네 chamber, 네 lead summary가 450×800/360×640에서 겹침·가로 overflow 없이 표시.
- grid/summary 선택이 같은 lead ID inspector를 엶.
- pause 중 timeout world 무변경.
- timer 1회당 settled tick 정확히 1회.
- modal/focus loss 중 진행 차단.
- headless scene load와 한 프레임 smoke 통과.

## 17. 구현 순서

```text
A. 새 문서를 기준으로 village partial을 keep/adapt/delete
B. snapshot v4 + environment/actor 두 cadence로 기존 92 tests 복구
C. 8방향 MOVE + weighted path tests 정착
D. typed facet/mode/action/gate/consideration/curve registry + validation
E. PersonalityProfile + slot-stable Latin-hypercube generator
F. pure ThreatStimulus/AffectRules/ThreatAppraisal + elapsed-time tests
G. fixed-point evaluator + bounded typed DecisionTrace
H. NORMAL/PANIC FSM + hysteresis/commitment/action-history tests
I. EncounterLabState + 15×15 chamber bootstrap + activation/perception
J. ReactionIntent + atomic batch resolution + shared leaf executors
K. MeleeCombatSystem + threat fallback + escape + damage cause chain
L. Session v2 detached DTO + replay/save/load
M. 15×15 comparison UI + controls/trace inspector
N. 100-seed soak, responsive UI, full headless suite
```

코어와 테스트를 먼저 정착시키고 UI를 연결한다. parse만 성공한 상태를 완료로 보고하지 않는다.

## 18. 완료 보고

- 실제 구현한 reaction과 비목표
- 부분 마을 변경에서 유지/제거한 파일
- snapshot/ruleset/session 버전
- 전체 테스트 수와 failure 수
- default seed의 네 personality와 첫 reaction
- 동일 personality symmetry 결과
- 100-seed soak 결과
- save/load continuation hash 결과
- 450×800/360×640 UI smoke 결과
- 남은 설계 위험

사용자가 요청하지 않은 commit/push/deploy는 하지 않는다.
