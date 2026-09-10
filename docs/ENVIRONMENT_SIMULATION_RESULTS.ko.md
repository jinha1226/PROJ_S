# 재료·원소·환경 시뮬레이션 결과

실험 ID: `SOL-MEDIUM-ENV-001`

설계 기준 commit: `b1674f3`

구현 commit: `920a351`

실행 환경: Linux 컨테이너, Godot `4.6.2-stable (official)`

## 판정

타일 기반 소재·표면층·대기·열 상태와 결정론적 환경 tick을 구현했다. 열전달과 냉각, 연료를 소비하는 연소, 물/얼음/수증기 상변화, 벽과 문을 고려한 기체 확산, 파생 압력과 파열, 표면 물에 따른 전기 경로, 유한 queue 폭발, FIREBOLT의 공용 열 적용, 저장·rollback·관측·오버레이 연결까지 동작한다.

요청 전체가 완료된 상태는 아니다. 폭발의 권위 있는 밀쳐냄과 지형 파괴, 연기에 의한 실제 LOS 축소, 장비의 부위별 coverage·소재·젖음에 따른 환경 피해 차이는 아직 구현하지 않았다. 현재 장비 wire에는 소재와 부위 coverage가 없으므로 기존 `DamageSystem`과 body element 경로를 그대로 사용해 저항을 중복 적용하지 않았다. 이 세 항목은 데이터 계약을 먼저 추가하는 후속 작업이다.

## 구현 결과

- `STONE`, `WOOD`, `IRON`, `RUBBER` 소재를 무차원 정수 게임 계수로 정의했다. 열전도, 열용량, 전기전도, 가연성, 점화온도, 연소열, 연료량, 기계저항을 서로 다른 축으로 유지한다.
- 바탕 소재와 별도로 `WATER`, `OIL`, `ICE` 단일 표면층과 양을 저장한다. 돌 위 기름은 기름만 소비하며 돌에 연료를 만들지 않는다.
- 일반 기체, 연기, 수증기, 가연성 기체를 별도 양으로 저장한다. flux는 tick 시작 상태를 읽어 delta를 일괄 반영하고 내부 확산에서 합계가 복제되지 않게 한다.
- 압력은 기체 총량, 절대 온도 근사치와 밀폐 유효 부피로 계산한다. 열린 경계에는 명시적인 기체·열 손실을 적용한다. 고압 파열은 `rupture`, 가연성 기체 점화는 `combustion` 사건으로 구분한다.
- 폭발은 재귀가 아닌 상한이 있는 queue로 전파하고 거리 및 비통과 지형의 엄폐 손실을 적용한다. 현재 combustion 폭발의 열/화염 피해만 기존 HP/body 경로를 사용한다.
- 환경 갱신은 화면과 무관한 100 world-time 고정 tick에서 활성 타일과 이웃만 처리한다. 환경 tick은 actor tick보다 먼저 실행된다.
- 조사 sample은 표면, 온도, 연기, 수증기, 가연성 기체, 압력 tier, 시야 방해량을 pure 값으로 제공한다. 관측된 연기/가스는 기존 AI 위험 점수에 연결된다. MEMORY와 UNSEEN DTO에는 실시간 환경값을 노출하지 않는다.
- snapshot은 exact-key v12와 `tile-environment-v1` ruleset을 사용하고 rollback memento는 v5 sparse 환경 scalar를 저장한다.

## 의도적인 근사

- 모든 물성치는 현실 측정값이 아닌 조정 가능한 게임용 정수다. 실제 단위나 물질 데이터로 해석하지 않는다.
- 한 타일은 바탕 소재 하나와 표면층 하나만 가진다. 다층 유체, 개별 입자, 화학 종 전체와 CFD는 계산하지 않는다.
- 열과 기체는 cardinal 이웃 사이의 정수 flux이고, 열린 맵 가장자리는 외부 reservoir로 취급한다.
- 전기는 persistent charge 없이 명령 시 BFS로 전파된다. 마른 고무는 차단하고 표면 물은 접촉 전도 경로를 만든다.
- 연기 관측값은 AI 위험과 UI cue에는 반영하지만 현재 FOV/LOS 기하 자체는 바꾸지 않는다.

## 라이선스와 출처 점검

이번 구현에는 SS14, The Powder Toy, Sandboxels, DCSS의 코드·소재 정의·반응표·에셋·데이터를 복사하거나 번역·개작해 넣지 않았다. 물성 계수도 외부 데이터가 아니라 자체 게임 가정값이다. 따라서 이번 변경으로 추가된 제3자 고지는 없다.

기존 저장소에서 DCSS 관련 문자열은 참고 링크가 있는 문서, 설명 주석과 테스트 명칭에서 확인했다. 이 조사는 문자열과 관련 문서 및 git 이력의 제한된 점검이며 저장소 전체의 독립 구현이나 출시 라이선스 적합성을 증명하지 않는다. 직접 이식으로 판단할 구체적 근거는 이번 범위에서 찾지 못했지만, 과거 코드의 전면 provenance 감사는 남아 있다.

## 자동 검사

- 환경 전용: `godot --headless --path . --script tests/run_environment_simulation_tests.gd` → 12 tests, 0 failed.
- 기존 원소 회귀: 임시 단일-file runner로 `tests/test_elements.gd` → 16 tests, 0 failed.
- 지형 registry 회귀 → 11 tests, 0 failed.
- body injury 회귀 → 4 tests, 0 failed.
- world body lifecycle 회귀 → 5 tests, 0 failed.
- Phase 5 회귀 → 70 tests, 3 failed. 세 실패는 작업 전 기준 실행에도 있던 party emotion source/processed-step owner/raw-health allowlist 항목이다.
- 작업 전 전체 기준선은 705 tests, 40 failed였다. 구현 후 전체 실행 도중 별도 세션이 UI·movement 소스를 수정해 동일 revision 비교가 성립하지 않아 실행을 중단했다. 따라서 환경 변경과 무관한 전체 실패 수의 전후 비교는 확정하지 않는다.

환경 검사는 돌+기름, 젖은 나무, 상변화 질량, 벽/문 연기, 밀폐 압력과 파열 구분, 물/금속/고무 전도, 폭발 감쇠와 chain 상한, 공용 fire/body 피해, 소재별 열전달, 내부 기체 합계, v12 JSON round trip, 명령 재실행, preview 비변이, fog-safe overlay, sparse rollback을 포함한다.

## 성능 측정

`godot --headless --path . --script tests/environment_performance_probe.gd`로 측정했다. 시간은 한 번의 컨테이너 headless 실행값이며 모바일 실측이나 안정적인 benchmark 분포가 아니다. 메모리는 Godot static usage 값이다.

| 시나리오 | tick | 활성 타일 전→후 | 환경 tick 평균 | 전체 turn 평균 | 메모리 전→후 | 사건 수 |
|---|---:|---:|---:|---:|---:|---:|
| 기존 96×96 정지 지도 | 3 | 0→0 | 25 µs | 29,145 µs | 58,165,599→58,250,647 B | 3 |
| 기존 96×96 국소 화재 | 3 | 1→14 | 324 µs | 27,442 µs | 58,170,267→58,276,803 B | 15 |
| 100×100 넓은 화재+가스 | 3 | 100→1,060 | 37,278 µs | 84,878 µs | 60,004,163→64,715,819 B | 2,433 |
| 100×100 밀집 개체 노출 | 3 | 256→460 | 9,309 µs | 101,611 µs | 66,517,547→71,295,447 B | 3 |
| 100×100 연쇄 폭발 | 1 | 10→88 | 5,604 µs | 39,725 µs | 59,947,367→60,561,631 B | 271 |

모든 성능 시나리오는 명령을 수락했고 `world_state_error()`가 비어 있었다. 구현 전에는 `environment.tick` 구간 계측이 없어 구성요소의 직접 전후 비교값은 없다. 정지 지도에서 활성 집합 비용은 작지만 넓은 화재/가스는 1,060개 활성 타일과 2,433개 사건으로 증가하므로 모바일 목표를 정하기 전에 반복 측정과 event 양 최적화가 필요하다.

## 저장 호환성

v12 tile wire에는 소재, 온도, 연료, 표면, 대기, 밀폐 상태가 추가됐다. 현행 exact-version 정책에 따라 v11 이하는 `unsupported_snapshot_version`으로 거부하며 자동 migration은 제공하지 않는다. 이미 배포된 v11 저장을 유지해야 한다면 별도의 명시적 migration과 golden fixture가 필요하다.

## 남은 작업

1. 지형 변경 event와 점유/대형 불변식을 포함하는 폭발 파괴 및 밀쳐냄 규칙
2. 장비 정의에 소재·부위 coverage·상태를 추가한 뒤 동일 피격 부위에서 환경 저항 차이와 중복 감소 부재를 검증하는 검사
3. 연기 농도를 실제 FOV/LOS에 적용하고 memory·AI 인지 회귀 검사 추가
4. v11 저장 migration 여부 결정 및 배포 fixture 검증
5. 고정 장비의 모바일 기기에서 반복 성능 측정과 넓은 가스 사건량 최적화
