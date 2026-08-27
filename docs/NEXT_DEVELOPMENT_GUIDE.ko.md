# 다음 개발 가이드

## 현재 완료 기준

시간·지형·MOVE·노출 코어는 다음 계약을 만족한 상태에서만 다음 단계의 기반으로 본다.

> 아래의 snapshot v3·4방향 MOVE는 마지막 안정 baseline의 완료 계약이다. 현재 작업 트리의 snapshot v4·8방향·actor cadence는 Phase 3용 미완성 변경이며, 기존 회귀 92개가 다시 모두 통과하기 전에는 완료 상태로 간주하지 않는다.

- 유효한 플레이어 결정 수 `step_index`와 실제 경과 `world_time`이 분리됨
- 행동은 시작 시 commit되고 `(start, end]` 예약을 완전히 처리한 뒤 정착됨
- 환경 cadence가 절대시간 100 배수에서 drift 없이 실행됨
- `preview()`는 공개 예약만 표시하고 상태·RNG·ID를 바꾸지 않음
- snapshot v3가 registry ID·예약 큐·화재 eligibility와 모든 64비트 시간/ID 참조를 보존함
- 거부 입력과 overflow가 commit 전 전체 무변경으로 끝남
- terrain registry가 통과·점유·이동 비용의 유일한 authority임
- MOVE가 시작 시 commit되고 행동 구간의 환경 틱이 새 위치를 봄
- ExposureSample과 종족 affinity 평가가 세계를 바꾸지 않는 detached projection임

## 현재 고정 개발 순서

```text
시간 코어·타임라인 (완료)
→ TerrainRegistry·MOVE (완료)
→ ExposureSample·종족 affinity (완료)
→ Playtest Sandbox 유지·각 단계 시나리오 추가
→ 던전 성격 반응 실험실 + 8방향 경로 + 15×15 비교 UI (Phase 3)
→ 한 공간의 파티 조우·관계 기반 보호/이탈
→ 플레이어 FOV·미니맵·먼 타일 auto-walk
→ 범용 위험 인지·종족 affinity 기반 안전 경로
→ 몬스터 먹이·영역·무리 생태
→ 10명 NPC 자율 마을·일과·욕구
→ 목격·도움·피해·faction·소문
→ 독·DOT와 원소 상호작용 확장
→ 동료 1명에서 최대 3명
```

Phase 3의 구현 계약과 테스트 기준은 `docs/PHASE3_DUNGEON_PERSONALITY_LAB_IMPLEMENTATION_PROMPT.ko.md`를 단일 기준으로 삼는다. 개인 성향·행동 AI의 연구 근거와 장기 확장 규칙은 `docs/PERSONALITY_BEHAVIOR_ARCHITECTURE.ko.md`를 따른다. 마을 구현 문서는 보류된 backlog다. 기존 아래 절 번호는 장기 설계 원칙으로 유지하되, 실제 구현 우선순위는 위 순서를 따른다.

### 1. TerrainRegistry·MOVE (완료)

- 타일의 통과 가능성·이동 비용·점유 규칙을 데이터 registry로 분리한다.
- `MOVE`는 플레이어와 NPC가 같은 명령 검증·실행 경로를 사용한다.
- 행동 비용은 `ActionTimingTable`에서만 정하고 명령이 임의 비용을 주입하지 못하게 한다.
- 경계 밖, 벽, 죽은 actor, 점유 충돌은 commit 전 무변경 거부한다.
- 동일 시각 다중 actor의 목표 충돌은 아직 player-step 비범위이며, 후속 자율 AI coordinator에서 예약 순서와 독립적인 명시적 동점 규칙을 먼저 고정한다.
- preview에는 이동 종료 시각과 이미 공개 가능한 예약만 표시한다.

안정 baseline 완료 상태: registry v1, 점유 producer/restore 대칭, 네 방향 MOVE, 지형 비용, start-commit, snapshot v3·timeline·JSON 재개 회귀로 고정했다. 8방향 MOVE와 snapshot v4는 Phase 3 정착 항목이다.

### 2. ExposureSample·종족 affinity (완료)

불만을 위한 특수 회피 코드를 만들지 않는다. 타일의 위험을 아래처럼 정규화된 자료로 샘플링한다.

```text
ExposureSample
  position
  sampled_step_index
  sampled_world_time
  next_environment_time
  terrain_id / passable / move_time_cost
  fire_intensity
  known_fire_damage_at_next_tick
  terrain_water_exposure / wetness / water_exposure
  conductivity
  electric_risk / electric_certainty
  poison_intensity       # 아직 0
  source_event_ids
```

종족·개체 성향은 위험 자체를 바꾸지 않고 해석을 바꾼다.

```text
HazardAffinity
  fire_tolerance
  water_tolerance
  electric_tolerance
  poison_tolerance
```

예를 들어 물에 강한 종족은 젖은 길을 낮은 위험으로, 물에 약한 종족은 높은 위험으로 평가한다. affinity는 이동 가능성이나 world-time 비용을 바꾸지 않는다. 최종 위험 점수는 정수 연산만 사용한다.

완료 상태: 동일한 ExposureSample을 human/amphibian/dwarf가 다르게 평가하고, shared fire projection·정적 물·동적 젖음·전도성 진단을 원본 환경 상태와 분리했다.

### 3. Playtest Sandbox 유지·시나리오 추가

- UI는 `PlaytestSession` detached API만 사용하고 simulator/world를 직접 읽지 않는다.
- 새 규칙을 추가할 때마다 작은 arena에 5분짜리 재현 시나리오와 상태·timeline 설명을 먼저 붙인다.
- 작은 32×48 arena는 최종 맵 크기 결정이 아니라 조작·카메라·규칙 검증 fixture로 유지한다.
- SAVE/LOAD와 seed·accepted command journal로 보고된 현상을 즉시 재현할 수 있게 한다.

완료 기준: 자동 회귀와 headless smoke가 통과하고, 5분 플레이 시나리오를 seed·journal·snapshot으로 다시 실행할 수 있다.

### 4. 범용 안전 타일 선택 AI

- 인접 후보를 `통과 가능성 → 예상 exposure → 목표 진척 → 고정 좌표/방향 동점` 순으로 평가한다.
- 불·물·전기별 별도 도망 함수를 만들지 않는다.
- 선택 결과뿐 아니라 후보 점수와 탈락 이유를 진단 DTO에 남긴다.
- 아직 인지 시스템이 없으므로 테스트 fixture가 제공한 관찰 범위만 평가한다.
- AI가 실제 행동할 때는 플레이어와 같은 `MOVE` command를 제출하고 실행 직전에 재검증한다.

완료 기준: 같은 snapshot에서 같은 개체가 같은 이유로 같은 안전 타일을 고르며, 위험 종류가 추가되어도 선택기 구조가 변하지 않는다.

### 5. 불·물·전기 exposure 연결 확장

- 기존 `ExposureSample` 계약을 유지하며 새 원소 상태와 source certainty를 필드 단위로 확장한다.
- 화재는 이미 현재 세기와 다음 환경 cadence의 확정 피해를 공유 kernel로 계산한다. 이후에도 확률적 확산 성공을 예언하지 않는다.
- 젖음은 현재 물 affinity와 conductivity 진단에 연결돼 있다. persistent charge를 도입할 때만 별도 확정 전기 위험으로 연결한다.
- 전기 위험은 실제 방전 전에는 확정 피해처럼 preview하지 않는다.
- 감지하지 못한 위험은 UI preview와 AI 관찰 양쪽에서 숨긴다.

완료 기준: 물에 강한 종족은 합리적으로 물길을 택할 수 있고, 물에 약하거나 전기에 취약한 종족은 같은 타일을 피한다.

### 6. 독·DOT

- 독 구름·오염 타일과 개체 상태 효과를 같은 예약 코어의 serializable kind로 추가한다.
- 새 handler가 행동 구간 안에 예약을 만들 수 있게 하기 전에 preview occurrence 병합·공개 정책을 먼저 계약한다.
- DOT 피해는 공통 `DamageSystem`만 사용한다.
- cadence 직전 저장, 여러 틱을 넘는 느린 행동, source/cause 상속을 테스트한다.

완료 기준: 독이 플레이어 명령 횟수가 아니라 절대 world time에 따라 진행되고 중간 저장에도 중복·누락이 없다.

### 7. 인지·관계·기억

- 객관적 사건, 개체가 관찰한 결과, 관계 변화, 기억을 서로 다른 계층으로 둔다.
- 보지 못한 개체는 구조·피해를 관계에 반영하지 않는다.
- `instigator_id`는 객관적 책임자이지 관찰자가 정체를 안다는 뜻이 아니다.
- 기억은 사건 ID, 관찰 시각, 주체·대상, 중요도와 신뢰도를 보존한다.
- 관계는 계속 `종족 prior + 제한된 faction 보정 + 제한된 personal 보정` 순서를 지킨다.
- 강한 적대 종족 prior는 일반 도움 몇 번으로 즉시 우호가 되지 않으며, 장벽 해제는 유대·화해 같은 명시 상태로만 한다.

완료 기준: 구조를 실제로 본 수혜자만 감사가 생기고 종족 prior는 여전히 지배적이며, 저장·복원 후 기억과 인과가 같다.

### 8. 자율 동료 1명 → 최대 3명

- 먼저 동료 한 명에게 추종 거리, 위험 허용도, 후퇴 체력, 보호 대상 정책을 준다.
- 동료는 자율 의도를 만들지만 실제 행동은 공통 command·scheduler를 사용한다.
- 이후 최대 세 명으로 늘리며 같은 시각의 이동·목표 충돌을 고정 규칙으로 해결한다.
- UI preview는 감지 가능한 동료의 확정 예약만 노출하고 내부 의도나 숨은 적 예약을 누설하지 않는다.

완료 기준: 플레이어 한 명은 완전 통제되고 동료는 예측 가능한 규칙 안에서 자율적으로 움직이며, 동일 seed/command journal 결과가 같다.

## 성능 단계

기능 순서가 끝나기 전 청크 축약부터 만들지 않는다. 먼저 `64×64`, 개체 `50..100`, 혼합 비용 10,000+ world-time 실행에서 다음을 확인한다.

- 동일 seed·명령열 최종 snapshot/event hash 일치
- 잘못된 cause/source 참조 0
- overdue 예약 0, cadence 중복·누락 0
- 범위 밖 개체와 중복 사망 0
- 한 step occurrence budget 초과 0

그 뒤에만 활성 청크 정밀 시뮬레이션과 먼 지역 축약 시뮬레이션을 분리한다.

## 계속 지킬 비목표

이 순서가 끝나기 전에는 범용 ECS, 규칙 DSL, GOAP, 연속 유체, 멀티스레딩, 비동기 Timer, 완전 이벤트 소싱, 확률 결과를 소비하는 preview를 도입하지 않는다.
