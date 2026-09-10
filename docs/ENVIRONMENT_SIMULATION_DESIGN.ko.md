# 재료·원소·환경 시뮬레이션 설계 및 실행 protocol

상태: 구현 전 기준선  
실험 ID: `SOL-MEDIUM-ENV-001`  
기준 commit: `b1674f3`  
작업 브랜치: `feat/hero-turn-combat`

## 질문과 완료 판정

현실 물리의 수치 재현이 아니라 타일에서 원인과 결과를 읽을 수 있는 결정론적 근사 모델을 만든다. 기본 소재, 제한된 표면층, 대기 상태와 현재 열 상태를 분리하고 기존 필드 시간·피해·신체·저장 경로에 연결한다. 같은 시드, 초기 상태와 명령열의 최종 snapshot 및 event ledger가 같아야 한다.

완료 판정은 작업 요청서의 재료·상변화·열·연소·기체·압력·전기·폭발 시나리오, 저장/재실행, preview 비변이성, 기존 회귀 검사와 실제 실행 가능한 성능 시나리오가 통과하는 것이다. 결과와 측정 한계는 `docs/ENVIRONMENT_SIMULATION_RESULTS.ko.md`에 기록한다.

## 현재 구현 조사

- `SimWorldState`는 권위 있는 `world_time`과 100 단위의 `system.environment_tick`/`system.actor_tick`을 유지한다. 같은 시각에는 priority 100인 환경이 priority 200인 actor보다 먼저 실행된다. 렌더 프레임은 이 시간을 진행시키지 않는다.
- `SimTile`은 terrain, `flammability`, `base_conductivity`, `wetness`, `fire`와 원인 event/피해 가능 시각을 저장한다. 동적 타일의 sparse index가 환경 처리와 rollback memento에 쓰인다.
- `EnvironmentSystem`은 동시 tick 시작 시의 burning set을 기준으로 불을 감쇠·확산하고, 물로 불을 줄이며, `effective_conductivity()` 기준 BFS 방전을 처리한다. 방전은 즉시 끝나며 persistent charge는 없다.
- IGNITE/POUR_WATER/DISCHARGE 명령은 동일 환경 시스템에 들어오지만 기존 스킬의 환경 점화 연결은 없다.
- fire/electric은 `DamageSystem`을 거쳐 HP와 기존 body element injury 경로를 함께 사용한다. 물리 방어구 수치는 원소 피해에 재적용되지 않는다. 현재 환경 원소 경로에는 부위별 방어구의 소재·젖음·절연 모델이 없다.
- public snapshot은 exact-key v11이고 모든 tile을 저장한다. rollback은 지형을 캐시하고 fire/wetness 동적 scalar만 sparse하게 저장한다. restore 후 의미 검증과 event 원인 검증이 엄격하다.
- 위험 sample은 현재 불의 다음 tick 확정 피해를 공용 pure kernel로 계산한다. 전기는 persistent charge가 없으므로 예측값 0이다. 조회는 RNG와 상태를 바꾸지 않는다.
- 기존 DCSS 관련 표시는 README, 설계 문서의 링크/설명, `DCSS-style` 주석과 테스트 명칭에서 확인했다. 이번 조사만으로 과거 전체 구현의 독립성을 증명하지 않는다. 이번 환경 구현에는 해당 코드나 알고리즘을 편입하지 않는다.

## 데이터 모델

모든 계산값은 현실 측정값이 아닌 무차원 게임용 정수다. 단위가 다른 값을 직접 더하지 않는다.

- 바탕 소재 `material_id`: `STONE`, `WOOD`, `IRON`, `RUBBER`. 소재 registry가 열전도, 열용량, 전기전도, 가연성, 점화온도, 연소열, 기계저항을 제공한다. 기존 terrain은 소재를 하나 지정한다.
- 표면층: `surface_id` (`NONE`, `WATER`, `OIL`, `ICE`)와 `surface_amount` 0..1000. 한 타일에는 한 종류만 두어 제한된 상태 공간을 유지한다. WATER↔ICE와 WATER→STEAM은 동일 양을 이동시킨다.
- 대기: `gas_amount`, `smoke_amount`, `steam_amount`, `flammable_gas_amount`를 각각 0..1000으로 저장한다. smoke와 flammable gas는 별도다. 압력은 저장 권위가 아니라 `gas total × absolute temperature / effective volume`에서 계산하는 파생값이다.
- 현재 상태: `temperature`(게임 온도), `fuel_amount`, `fire`, `wetness` 및 원인 event ID. 기존 `wetness`는 표면 WATER로부터 계산되는 접촉 효과로 유지하여 기존 이동·피해 호출을 깨지 않게 한다.
- 경계: wall은 흐름을 막는다. 맵 가장자리는 외부로 열린 경계이며 기체와 열이 명시적으로 빠져나간다. 문 지형은 `door_closed`/`door_open`으로 구분한다.

중앙 설정과 소재 registry에만 임계값·속도·피해 배율을 둔다. 실제 물성 데이터는 사용하지 않는다.

## tick과 결정론

한 환경 tick은 이전 상태를 읽어 정렬된 타일 index 순서로 flux와 transition을 모은 뒤 일괄 반영한다.

1. 활성 타일과 이웃의 열 flux 계산
2. 융해·결빙·증발·응결과 물질량 이동
3. 점화·연소·연료 소모·열·연기 생성
4. smoke/steam/flammable gas의 벽 인식 확산과 열린 경계 배출
5. 파생 압력과 용기 파열 판정
6. fire 및 환경 노출 피해 적용
7. epsilon 아래 평형 타일 비활성화

RNG가 필요한 점화 경쟁은 기존 정렬 규칙과 world RNG를 사용한다. 폭발과 전기는 재귀 대신 정렬된 큐를 사용한다. 처리량이나 벽시계 시간으로 tick을 중단하지 않는다. 활성 집합에는 상태가 있는 타일과 flux를 받을 이웃을 남긴다.

## 전투·신체 연결

스킬은 환경 impulse API에 heat/electric/impact를 전달하고 환경 명령도 같은 API를 호출한다. 대상 개체 피해는 계속 `DamageSystem` 한 경로만 사용한다. 기존 body element resolver가 부위를 결정하고 피부·연조직·뼈 상태를 갱신한다.

환경용 방어 계수는 실제 장비 registry가 제공하는 부위 coverage와 소재가 존재할 때만 적용한다. 기존 단일 `armor_flat`을 원소 피해에 다시 적용하지 않는다. 전기는 접촉 중인 표면 물, 장비 절연성, 전류 경로로 계산하며 금속이라는 이유만으로 일괄 증폭하지 않는다. 현재 장비 데이터가 이 계약을 표현하지 못하면 이번 구현에서는 기본 무방어 연결만 보존하고 장비 소재 확장은 후속 과제로 명시한다.

## 사건과 관측

열·상변화·연소·기체 이동·파열·폭발은 원인 event를 가진다. 폭발은 `combustion`과 `rupture` 원인을 구분한다. 조사 sample에는 관측 가능한 온도, 표면, fire, smoke, steam, gas 위험과 pressure tier만 노출한다. AI는 기존 시야/인지로 관측한 sample만 위험 점수에 포함한다. preview는 pure projection이며 RNG, 시간, active set, event ID를 소비하지 않는다.

화면은 기존 pixel overlay 위에 물/기름/얼음, 가열, 불, smoke, gas 위험을 작은 색/문양으로 표현한다. 대규모 신규 이미지 생성은 하지 않는다.

## 저장 호환성과 rollback

tile wire shape와 의미가 바뀌므로 snapshot을 v12, 환경 ruleset을 `tile-environment-v1`로 올린다. 현행 정책대로 v11을 추정 변환하지 않고 `unsupported_snapshot_version`으로 거부한다. 새 필드와 환경 ruleset ID를 exact-key 검증하고 범위·sentinel·물질 상태 불변식을 검사한다.

rollback memento는 새 동적 scalar를 packed row에 추가한다. `material_id`는 terrain registry에서 재구성하는 bootstrap-static 값이다. 표면·대기·온도·연료가 기본값이 아닌 타일은 sparse active set에 포함한다.

## 구현 순서

1. 중앙 설정, 소재 registry, tile 상태와 snapshot/rollback v12
2. 동시 열·상변화·기체 flux kernel 및 활성 집합
3. 연소 연료 모델, 전기 접촉 규칙, 압력/파열과 폭발 queue
4. 기존 명령·피해·body와 연결하고 skill impulse 연결점 제공
5. 비변이 위험 sample과 최소 overlay/조사 정보
6. 자동 검사, 기존 회귀, 100×100 성능 측정, 결과 및 라이선스 문서

각 단계는 테스트 가능한 상태에서 커밋한다. 실패한 실험도 수치와 한계를 결과 문서에 남긴다.

## 라이선스와 출처 관리

이번 구현은 외부 프로젝트의 소스, 소재 정의, 반응표, 이미지, 음원, 폰트, 데이터베이스를 사용하지 않는다. SS14, The Powder Toy, Sandboxels, DCSS 링크는 개념 비교의 탐색 출발점일 뿐 구현 입력으로 사용하지 않는다. 모든 계수는 `gameplay assumption`으로 주석과 문서에 표시한다. 따라서 이번 변경에 새 제3자 고지는 없다.

기존 DCSS 관련 문구를 찾은 범위는 문자열, 관련 문서, git log의 출처 표시에 한정된다. 전체 라이선스 감사를 완료했다고 주장하지 않는다. 직접 복사·번역 이식의 구체적 근거가 이후 발견되면 해당 범위를 격리해 보고하며 원본을 보고 재작성하지 않는다.

## 검증 시나리오

- 돌+기름과 젖은 나무의 연료/점화 차이
- WATER/ICE/STEAM 전환 전후 질량 합계
- 물·철 전도와 고무/닫힌 문 차단
- smoke 벽 차단 및 문 개방 뒤 확산
- 밀폐 가열의 압력 증가, 열린 경계 배출
- rupture와 combustion event 구분
- 폭발 거리·엄폐 감쇠와 유한 연쇄
- 환경 원소 피해의 공용 HP/body 경로와 저항 중복 부재
- snapshot JSON round trip, midpoint replay, preview 비변이
- 기존 전체 테스트
- 정지 지도, 국소 화재, 넓은 화재/기체, 밀집 노출, 연쇄 폭발을 실제 맵과 100×100에서 측정

측정값에는 Godot 버전, 실행 명령, 지도 크기, tick 수, 활성 타일 수, 환경 tick 시간, 전체 turn 시간과 가능한 범위의 메모리를 기록한다. 데스크톱/컨테이너 측정은 모바일 실측으로 표현하지 않는다.
