# SETTLEMENT-MVP-01 구현 protocol

2026-09-13. 사용자 `구현해봐` 지시로 이 세션에서 구현한다. 기준 게임 e569b8c, 계획 28c5740. 기존 미추적 import/uid를 보존하며 메인 푸시는 하지 않는다.

## 상태와 호환성

- 기존 단일 작업 서비스는 레거시 명령/저장 재생용으로 유지한다. 새 명령은 version=2를 저널에 기록한다. 진행 중 레거시 작업은 기존 경로에서 완료/취소 후 전환한다.
- 새 정규 상태는 `base.settlement_work_changed` 이벤트의 작업/주민 변경행과 논리 tick이다. world metadata의 증분 인덱스는 재생성 가능한 캐시이며 snapshot에 별도 상태를 숨기지 않는다. rollback/world 교체 시 재생성한다.
- 자재 묶음은 작업당 하나이며 STORAGE/CARRIED/SITE/RECOVERY/CONSUMED로 위치를 기록한다. 창고 물리량과 가용량을 구분한다. 소비는 완료 때만, 취소한 현장 자재는 반환 운반 완료 때만 가용량에 합산한다.
- 작업당 시설 접근 슬롯 하나를 예약한다. 경로는 기존 16×16 통로를 사용하며 청사진 footprint도 차단한다. 작업 선택은 유휴/무효화/필수 휴식 때 수행한다.

## 선택과 시간

- 운반/건설/생산 우선순위 0~3. 사용자 우선순위를 최상위로, 대기 시간/거리 및 기존 HEXACO C 또는 레거시 conscientiousness의 작은 보정으로 동률을 정한다. 실제 필드·범위는 구현 후 결과에 명시한다.
- 기존 stress/emotion으로 필수 휴식을 판정한다. 허기/피로를 새로 가정하지 않는다. 휴식은 기존 숙소 효과와 비용을 사용한다.
- 거점 0.5초 논리 tick, 비활성/종료 중 catch-up 없음. 원정의 성공한 시간 행동 경계에서 동일 advance를 호출한다. 중첩 item 행동은 바깥 transaction 저널에 포함하며 실패 rollback으로 tick도 철회된다.
- 원정 배정/출발 시 작업자를 해제하고 자재는 마지막 거점 위치에서 회수한다. 잔류 주민만 원정 중 작업한다.

## 검증

- baseline `godot --headless --path . --script tests/base_work_acceptance.gd`: 기존 테스트의 `return to base`, `reachable construction footprint` 실패 확인(현재 frontier/solo 시작 정책과 fixture 불일치). 수치 계약을 조용히 바꾸지 않고 fixture 시작 상태를 명시한다.
- 기존 frontier/base_work/base_settlement_build/base_production/base_rest/character_views 회귀 및 새 자원 보존·동시 작업·이탈·save/replay 수용 테스트. exit code와 SCRIPT ERROR/FAIL 모두 확인한다.
- 1/4/12 주민 × 0/8/32 작업, 10,000 tick p50/p95/max, 이벤트·경로 수, 메모리 표본. 동일 환경 초/후반 비교. 기존 이동 성능 probe 전후 비교.
- 360×640 및 390×844 지도 선택/확대/청사진/우선순위/스크롤 점검. 실기기 검증 여부는 별도 표시한다.
- 외부 코드 반입 없음. S0~S4 이후 농업/습격 등 확장하지 않는다.

결과: `docs/settlement-development-result.md` 및 관련 코드/테스트 commit.

## 구현 중 확인한 검증 경계

거점 tick은 던전 지형/전투/HP/인벤토리를 변경하지 않는다. 전체 world memento(전체 이벤트 배열 복사) 및 전역 party wire 검증을 매 tick 수행하면 과거 길이/세계 크기에 따라 비용이 증가한다. 거점 거래는 이벤트 suffix·next ID·party revision·휴식이 변경할 emotion/stress를 제한적으로 캡처하고, 정규 작업/자원 불변식·새 이벤트 ID/시간/인과·변경된 emotion wire를 검증한다. 실패 시 suffix와 해당 필드를 원자적으로 복원한다. 저장/복원과 통합 테스트에서 기존 전체 world audit을 유지한다. 원정은 기존 상위 transaction의 memento와 검증을 사용한다.
