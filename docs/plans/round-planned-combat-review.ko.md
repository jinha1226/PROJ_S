# 계획 라운드 전투 구현 검토

검토일: 2026-09-14

검토 기준 HEAD: `cfab0d9`. `e097f4e`, `22e490c`, `cfab0d9`와 작업 트리의 미커밋 UI 변경을 함께 확인했다. 사용자 요청은 검토 후 푸시이며, 이번 검토에서는 제품 코드를 수정하지 않았다.

## 판정: 메인 푸시 보류

아래는 최초 검토 시점의 판정이다. 후속 사용자 승인으로 수정했으며 맨 아래 재검증 절을 참고한다.

### P1 — 로컬 UI 스크립트가 컴파일되지 않음

- 위치: `playtest/party_encounter_sandbox.gd:3002`, `_validate_battle_targeting`.
- `var valid_phase:=session.round_active() or ...`에서 반환 타입이 정적으로 정해지지 않아 Godot가 bool 타입을 추론하지 못한다.
- 재현: `godot --headless --path . --script tests/solo_start_acceptance.gd`.
- 실제 출력: `Parse Error: Cannot infer the type of "valid_phase" variable because the value doesn't have a set type.` 이후 sandbox 의존 스크립트 컴파일 실패와 `.new()` 호출 오류.
- 영향: 현재 로컬 작업 트리로 제품 화면을 정상 생성할 수 없다. 라운드 시스템 단위 검사가 통과해도 모바일 빌드 준비가 되었다고 볼 수 없다.
- 권고: 명시적인 bool 타입과 조건 우선순위를 정리한 뒤, 제품 UI를 preload/생성하는 검사 및 웹 내보내기를 다시 수행한다.

### P1 — 중단된 계획을 다시 편집하면 소진한 이동 예산이 복구됨

- 위치: `sim/round_plan_service.gd:78–82`.
- 중단 상태에서 `candidate.move_budget=maxi(1, old_budget-spent)`로 남은 예산 0을 1로 올리고, `slot_spent=0`으로 초기화한다.
- 재현 fixture: `tests/round_combat_fixture.gd`로 라운드를 생성. 미완료 주인공을 INTERRUPTED 상태, move_budget=3, slot_spent=3으로 설정. 빈 경로/HOLD로 편집한 다음 인접 1칸 경로로 다시 편집한다.
- 두 편집 모두 accepted=true이며 최종 budget=1, spent=0이 된다. 임시 진단 스크립트 `/tmp/round_review_budget.gd`에서 재현했다. 이는 합성 경계 상태 검사이며 실제 탐험을 통한 재현과 구별한다.
- 영향: 새 적 발견으로 마지막 이동 칸에서 중단된 뒤 계획을 편집하면 같은 라운드에서 무료 이동을 더 할 수 있다.
- 권고: 소비 누계와 전체 예산을 편집 draft와 독립적으로 보존하거나, 남은 0을 표현하도록 상태 스키마까지 수정한다. 동일 중단 상태 반복 편집, 0칸 남은 공격/대기, 저장 복구 후 반복 편집 회귀를 추가한다.

### P1 — 커밋된 구현과 제품 UI가 분리되어 있음

- `playtest/party_encounter_sandbox.gd`, `playtest/party_grid_view.gd`는 미커밋 수정 상태다.
- `playtest/round_order_bar.gd`는 미추적 파일이며 HEAD에 없다.
- 새 `[진행]`/`[계속 진행]` 버튼 연결과 순서창 생성은 미커밋 UI 쪽에 있다.
- 커밋된 부분만 push하면 새 라운드 엔진은 포함되지만 합의된 UI는 누락된다. 반대로 미커밋 부분을 그대로 묶으면 위 파싱 오류도 배포된다.
- 결과 문서 자체도 UI 검증·커밋 단계가 남았다고 명시하고 있다.
- 권고: 기존 사용자 변경을 보존하면서 UI 컴파일/입력 검증을 완료하고 순서창 파일까지 명시적으로 커밋한다. 아직 검토하지 않은 import/uid/cache 파일을 일괄 stage하지 않는다.

## 이번에 실행한 검사

| 검사 | 결과 |
|---|---|
| `round_combat_core.gd` | PASS |
| `round_combat_interruptions.gd` | PASS |
| `/tmp/round_review_budget.gd` | 위 이동 예산 복구 결함 재현: 첫 편집/두 번째 편집 모두 accepted=true |
| `solo_start_acceptance.gd` | UI parse/compile 오류. 오류 후 종료되지 않은 프로세스는 중단 |

실제 모바일 터치, 전체 이능, 100라운드 성능 검증은 이번 검토에서 실행하지 않았다. 이 문서는 통과한 개별 테스트를 전체 구현 완료로 간주하지 않는다. 경험치 오사 정책은 실행 protocol에 별도 사용자 승인으로 기록되어 있으므로 이전 계획과 다르다는 이유만으로 결함으로 분류하지 않았다.

## 다음 작업

위 세 항목을 수정·커밋하고, 이동 예산 경계 회귀 및 시작/UI/라운드/중단·저장 검사를 재실행한 뒤 메인에 푸시한다. 현재 검토에서는 코드 수정 및 원격 푸시를 하지 않았다.

## 후속 수정 — 2026-09-14

사용자의 수정·푸시 승인 및 아이소매트릭 선택 테두리 요청에 따라 다음을 변경했다.

- `valid_phase`를 명시적 bool로 선언하고 조건 그룹을 정리했다. 추가로 발견된 `round_order_bar.gd`의 내장 `Skin` 클래스명 충돌을 `PixelSkin` 별칭으로 해결했다.
- 중단된 계획 편집은 원래 총 이동 예산과 사용량을 유지하고 경로 진행 인덱스만 초기화한다. 반복 편집으로 0 잔여 예산이 1로 늘어나지 않는다. 상태 스키마는 변경하지 않았다.
- 기존 미커밋 UI 변경을 보존하면서 순서창·진행·동료 선택을 통합했다. 전투 요약에 필요한 `type_label`, `automatic_suggestion`, `reason`을 round overlay에 추가했다.
- 적 조회와 아군 공격 계획 편집을 구별했다. 공격 선택 상태가 아닌 적 터치는 계획 revision을 바꾸지 않는다.
- 캐릭터 선택 테두리는 아이소매트릭 타일 polygon의 네 변으로 그린다. 기존 노란색/얇은 선을 유지하고 이동 보간 중심에 맞춰 이동한다. 평면 모드의 모서리 괄호 표시는 유지한다.
- 회귀 검사 추가: `round_combat_interruptions.gd`의 예산 소진 후 반복 편집/저장 복구, `tactical_overlay_regression.gd`의 마름모 선택/보간/평면 호환, `round_combat_ui.gd`의 360/390폭 화면·순서창·적 조회·동료 계획 수정·진행 연결.

확인된 통과: `solo_start_acceptance.gd`, `tactical_overlay_regression.gd`, `round_combat_interruptions.gd`, `round_combat_advanced.gd`. 실제 휴대전화 시각·터치 검사와 100라운드 성능 측정은 이번 수정 범위에서 완료했다고 주장하지 않는다.

최종 추가 확인: `round_combat_ui.gd` PASS(360×800 / 390×844 headless 입력 연결), Web release 내보내기 성공, `/tmp/round-ui-web-check`에서 원본 프로젝트 없이 `--main-pack index.pck --quit-after 5` 실행 성공. 최종 실행 로그에 스크립트 오류가 없음을 확인했다. 초기 UI 검사에서 나온 추가 필드 누락은 보완 후 새 프로세스로 재검사했다.
