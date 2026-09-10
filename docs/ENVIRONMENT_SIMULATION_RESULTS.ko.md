# 재료·원소·환경 시뮬레이션 결과

후속 검토에서 확인한 증발 경계 오류·자연 발화·물 붓기 연결 및 정지 상태 성능 수정은
[검토 후 마무리 기록](ENVIRONMENT_SIMULATION_REVIEW_FIXES.ko.md)을 참조한다.
아래 수치는 해당 구현 당시의 기록이며 후속 검증 결과를 대체하지 않는다.

실험 ID: `SOL-MEDIUM-ENV-001`

보완 실험 ID: `SOL-MEDIUM-ENV-002`

설계 기준 commit: `b1674f3`

구현 commit: `920a351`

보완 구현 commit: `4728468`

실행 환경: Linux 컨테이너, Godot `4.6.2-stable (official)`

## 판정

타일 기반 소재·표면층·대기·열 상태와 결정론적 환경 tick을 구현했다. 열전달과 냉각, 연료를 소비하는 연소, 물/얼음/수증기 상변화, 벽과 문을 고려한 기체 확산, 파생 압력과 파열, 표면 물에 따른 전기 경로, 유한 queue 폭발, FIREBOLT의 공용 열 적용, 저장·rollback·관측·오버레이 연결까지 동작한다.

`SOL-MEDIUM-ENV-002`에서 1차 판정의 누락 항목을 보완했다. 폭발의 기계 충격·밀쳐냄·지형 파괴, 연기의 실제 LOS 차단, 장비의 부위별 coverage·소재·젖음에 따른 환경 피해 차이가 권위 상태와 event 검증에 연결됐다. 현재 정의된 장비 범위와 저장 v12 계약에서 요청한 핵심 현상은 구현됐다.

## 구현 결과

- `STONE`, `WOOD`, `IRON`, `RUBBER` 소재를 무차원 정수 게임 계수로 정의했다. 열전도, 열용량, 전기전도, 가연성, 점화온도, 연소열, 연료량, 기계저항을 서로 다른 축으로 유지한다.
- 바탕 소재와 별도로 `WATER`, `OIL`, `ICE` 단일 표면층과 양을 저장한다. 돌 위 기름은 기름만 소비하며 돌에 연료를 만들지 않는다.
- 일반 기체, 연기, 수증기, 가연성 기체를 별도 양으로 저장한다. flux는 tick 시작 상태를 읽어 delta를 일괄 반영하고 내부 확산에서 합계가 복제되지 않게 한다.
- 압력은 기체 총량, 절대 온도 근사치와 밀폐 유효 부피로 계산한다. 열린 경계에는 명시적인 기체·열 손실을 적용한다. 고압 파열은 `rupture`, 가연성 기체 점화는 `combustion` 사건으로 구분한다.
- 폭발은 재귀가 아닌 상한이 있는 queue로 전파하고 거리 및 비통과 지형의 엄폐 손실을 적용한다. combustion의 열/화염과 combustion·rupture 공통 기계 충격은 기존 HP/body 경로를 사용한다.
- 환경 갱신은 화면과 무관한 100 world-time 고정 tick에서 활성 타일과 이웃만 처리한다. 환경 tick은 actor tick보다 먼저 실행된다.
- 조사 sample은 표면, 온도, 연기, 수증기, 가연성 기체, 압력 tier, 시야 방해량을 pure 값으로 제공한다. 관측된 연기/가스는 기존 AI 위험 점수에 연결된다. MEMORY와 UNSEEN DTO에는 실시간 환경값을 노출하지 않는다.
- snapshot은 exact-key v12와 `tile-environment-v1` ruleset을 사용하고 rollback memento는 v5 sparse 환경 scalar를 저장한다.

## 보완 구현 결과

- 폭발 wave 탐색 중 피해·밀쳐냄·파괴 후보를 먼저 고정한 뒤 정렬 적용한다. 이 때문에 밀린 개체가 같은 폭발에서 다시 맞거나 먼저 무너진 벽이 같은 폭발의 엄폐 계산을 바꾸지 않는다.
- 기계 충격은 `environment.explosion_impact`가 원인 wave, 종류, 원래 힘, 적용 방어 수치를 고정하고 기존 `combat.physical_damage`와 impact body injury 경로로 전달한다. rupture는 화염 피해 없이 기계 충격을 준다.
- 거리 1 이상에서 세기가 임계값 이상인 wave는 원점 반대 방향의 통과 가능하고 비어 있는 cardinal 한 칸으로 개체를 최대 한 번 민다. `environment.knockback`은 위치 history, party 배치 history와 rollback 검증에 포함된다.
- wave 세기가 소재의 기계저항을 초과하면 벽, 닫힌 문, 나무·고무 바닥을 rubble로 바꾼다. 파괴 전 지형이 엄폐 계산에 쓰이고, 열·표면·대기 상태는 보존된다. 지형 rollback baseline과 표시 topology cache는 파괴 사건에 맞춰 갱신된다.
- 장비 wire를 바꾸지 않고 `ARMOR_LEATHER`, `ARMOR_PADDED`, `SHIELD_WOOD`에 자체 환경 방어 registry를 연결했다. 한 번 선택한 피격 부위에 coverage가 있을 때 가장 강한 한 장비만 적용한다. 감소 후 피해를 HP와 body가 함께 사용하므로 감소가 중복되지 않는다.
- 전기 절연은 타일 젖음에 따라 약해진다. 검사 fixture에서 원래 전기 피해 80은 마른 padded 36, 마른 leather 56, 젖은 padded 69가 됐다. coverage 밖인 머리는 감소하지 않았다.
- 중간 타일의 연기가 600 이상이면 terrain과 별도로 LOS를 막는다. 연기 타일 자체는 볼 수 있고, 적 인지와 표시 FOV가 `EnemyPerceptionRegistry.has_line_of_sight()`를 공유한다.
- 증발·응결량을 도착 상태의 남은 용량으로 제한해 1,000 상한에서 clamp로 물질량이 사라지던 경계 조건을 수정했다.

## 의도적인 근사

- 모든 물성치는 현실 측정값이 아닌 조정 가능한 게임용 정수다. 실제 단위나 물질 데이터로 해석하지 않는다.
- 한 타일은 바탕 소재 하나와 표면층 하나만 가진다. 다층 유체, 개별 입자, 화학 종 전체와 CFD는 계산하지 않는다.
- 열과 기체는 cardinal 이웃 사이의 정수 flux이고, 열린 맵 가장자리는 외부 reservoir로 취급한다.
- 전기는 persistent charge 없이 명령 시 BFS로 전파된다. 마른 고무는 차단하고 표면 물은 접촉 전도 경로를 만든다.
- 연기는 단일 정수 임계값으로 중간 LOS를 완전히 차단한다. 농도별 부분 투과나 시야 거리 연속 감쇠는 계산하지 않는다.

## 라이선스와 출처 점검

이번 구현에는 SS14, The Powder Toy, Sandboxels, DCSS의 코드·소재 정의·반응표·에셋·데이터를 복사하거나 번역·개작해 넣지 않았다. 물성 계수도 외부 데이터가 아니라 자체 게임 가정값이다. 따라서 이번 변경으로 추가된 제3자 고지는 없다.

기존 저장소에서 DCSS 관련 문자열은 참고 링크가 있는 문서, 설명 주석과 테스트 명칭에서 확인했다. 이 조사는 문자열과 관련 문서 및 git 이력의 제한된 점검이며 저장소 전체의 독립 구현이나 출시 라이선스 적합성을 증명하지 않는다. 직접 이식으로 판단할 구체적 근거는 이번 범위에서 찾지 못했지만, 과거 코드의 전면 provenance 감사는 남아 있다.

## 자동 검사

- 환경 전용: `godot --headless --path . --script tests/run_environment_simulation_tests.gd` → 17 tests, 0 failed.
- 기존 원소 회귀: 임시 단일-file runner로 `tests/test_elements.gd` → 16 tests, 0 failed.
- 지형 registry 회귀 → 11 tests, 0 failed.
- body injury 회귀 → 4 tests, 0 failed.
- world body lifecycle 회귀 → 5 tests, 0 failed.
- world item lifecycle/operations/state 회귀 → 각각 8/8/7 tests, 모두 0 failed.
- 필드 턴 수용 검사 → `FIELD TURN: PASS []`.
- Phase 5 회귀 → 70 tests, 3 failed. 세 실패는 작업 전 기준 실행에도 있던 party emotion source/processed-step owner/raw-health allowlist 항목이다.
- 던전 맵 회귀 → 9 tests, 1 failed. 기존 field scenery material DTO가 `grass` 대신 빈 값을 반환하는 알려진 실패다.
- 작업 전 전체 기준선은 705 tests, 40 failed였다. 구현 후 전체 실행 도중 별도 세션이 UI·movement 소스를 수정해 동일 revision 비교가 성립하지 않아 실행을 중단했다. 따라서 환경 변경과 무관한 전체 실패 수의 전후 비교는 확정하지 않는다.

환경 검사는 돌+기름, 젖은 나무, 상변화 질량과 용량 경계, 벽/문 연기, 밀폐 압력과 파열 구분, 물/금속/고무 전도, 폭발 감쇠와 chain 상한, 기계 충격·밀쳐냄·파괴, rupture의 비연소 피해, 방어구 coverage·소재·젖음·단일 감소, 실제 smoke LOS, 공용 fire/body 피해, 소재별 열전달, 내부 기체 합계, v12 JSON round trip, 명령 재실행, preview 비변이, fog-safe overlay, sparse rollback을 포함한다.

## 성능 측정

`godot --headless --path . --script tests/environment_performance_probe.gd`로 측정했다. 시간은 한 번의 컨테이너 headless 실행값이며 모바일 실측이나 안정적인 benchmark 분포가 아니다. 메모리는 Godot static usage 값이다.

| 시나리오 | tick | 활성 타일 전→후 | 환경 tick 평균 | 전체 turn 평균 | 메모리 전→후 | 사건 수 |
|---|---:|---:|---:|---:|---:|---:|
| 기존 96×96 정지 지도 | 3 | 0→0 | 26 µs | 26,882 µs | 58,459,165→58,544,213 B | 3 |
| 기존 96×96 국소 화재 | 3 | 1→14 | 339 µs | 26,269 µs | 58,463,833→58,570,369 B | 15 |
| 100×100 넓은 화재+가스 | 3 | 100→1,060 | 28,928 µs | 73,957 µs | 60,297,729→65,009,385 B | 2,433 |
| 100×100 밀집 개체 노출 | 3 | 256→460 | 8,944 µs | 102,012 µs | 66,811,113→71,589,013 B | 3 |
| 100×100 연쇄 폭발 | 1 | 10→88 | 5,865 µs | 39,234 µs | 60,240,933→60,855,197 B | 271 |

모든 성능 시나리오는 명령을 수락했고 `world_state_error()`가 비어 있었다. 구현 전에는 `environment.tick` 구간 계측이 없어 구성요소의 직접 전후 비교값은 없다. 정지 지도에서 활성 집합 비용은 작지만 넓은 화재/가스는 1,060개 활성 타일과 2,433개 사건으로 증가하므로 모바일 목표를 정하기 전에 반복 측정과 event 양 최적화가 필요하다.

## 저장 호환성

v12 tile wire에는 소재, 온도, 연료, 표면, 대기, 밀폐 상태가 추가됐다. 현행 exact-version 정책에 따라 v11 이하는 `unsupported_snapshot_version`으로 거부하며 자동 migration은 제공하지 않는다. 이미 배포된 v11 저장을 유지해야 한다면 별도의 명시적 migration과 golden fixture가 필요하다.

## 남은 작업

1. 현재 registry에 없는 새 방어구를 추가할 때 소재·coverage·환경 계수를 함께 정의하는 content 절차
2. v11 저장 migration 여부 결정 및 배포 fixture 검증
3. 고정 장비의 모바일 기기에서 반복 성능 측정과 넓은 가스 사건량 최적화
4. 기존 DCSS 관련 코드의 저장소 전체 provenance 감사
