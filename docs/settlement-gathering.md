# 주변 채집과 모바일 거점 UI

2026-09-13. 기준 1daebbd. 사용자 승인 범위: 주변 채집 → 잔류 주민 작업 → 플레이어 원정 연계. 독립 주민 원정대는 후속 단계다.

## 구현 계약

- 기존 16×16 거점 외곽의 고정 숲/돌/약초 지점, 자원별 자동 채집 켜기/끄기와 주민별 채집 우선순위.
- 채집 정책은 기본 꺼짐. 켜면 자원별 작업 하나만 생성하며 채집 후 반드시 창고로 운반한 뒤 재고에 반영한다.
- 초기 매장량 목재 24, 돌 18, 약초 12. 이번 단계는 고갈형이며 무한 재생/희귀 원정 자원은 추가하지 않는다.
- 취소·작업자 이탈 중 이미 채집한 묶음은 회수 가능하며 창고 입고는 한 번만 한다. 정책 끄기는 다음 주문 생성을 멈추고 현재 주문은 작업 목록에서 별도 취소 가능하다.
- 기존 원정 행동당 거점 tick을 재사용한다. 파티에 편성되어 출발한 주민은 거점에서 일하지 않는다.
- 새로운 정책 필드는 정책 명령 이후에만 이벤트에 기록하여 기존 version=2 저장 재생을 보존한다. 외부 소스/에셋을 반입하지 않는다.
- UI는 지도와 자원 요약 아래 시설/채집/작업/주민 패널로 구분한다. 모바일 터치 대상 48px, 하단 상세 영역은 독립 스크롤이다.

## 검증

기존 settlement unit/acceptance, 주변 채집 → 창고 → 반복/정지/취소/원정 잔류/정확한 저장 재생 테스트. 모바일 크기에서 탭 전환·지도 보존·스크롤·작업 UI 부분 갱신 확인. 실제 모바일 성능과 별도 주민 원정대는 완료로 보고하지 않는다.

## 실제 연결

- 피난처 관리 → **채집** 탭에서 벌목/채석/약초를 켠다. **주민** 탭에서 채집·운반·건설·생산 우선순위를 정하고, 동료를 원정에 편성하거나 거점에 남긴다.
- 주변 채집은 일반 던전 자원 지점의 `base_gather()` 버튼 연결과 별개다. 이번에는 정착지 외곽 채집을 구현했으며 던전 채집 UI 누락까지 해결했다고 해석하지 않는다.
- 수확과 입고 이벤트를 분리하고 `수확량 = 창고 입고량 + 미입고 묶음`을 거래마다 검증한다. 자동 주문은 별도 원인 이벤트를 가져 같은 tick의 다른 작업 완료/휴식에 인과 관계가 잘못 붙지 않는다.
- 기존 논리 화면의 모바일 축소 배율을 반영하여 터치 높이를 계산한다. 자원 요약과 지도 아래 네 탭의 상세 영역을 독립 스크롤로 분리하고 탭/스크롤 전환은 지도 노드를 보존한다.
- 지도에 주변 숲·돌·약초 위치를 표시하고 잔량이 0이면 어둡게 표시한다. 자동 정책을 꺼도 이미 채집한 묶음은 작업 취소 시 반환 운반한다.

### 재현 명령

```bash
godot --headless --path . --log-file /tmp/settlement-unit.log --script tests/settlement_work_unit.gd
godot --headless --path . --log-file /tmp/settlement-legacy.log --script tests/settlement_work_acceptance.gd
godot --headless --path . --log-file /tmp/settlement-gather.log --script tests/settlement_gathering_acceptance.gd
godot --display-driver x11 --rendering-method gl_compatibility --path . --log-file /tmp/settlement-mobile.log --script tests/settlement_mobile_acceptance.gd
```

화면 테스트는 실제 shell에서 채집 정책 토글, 지도 노드 보존, 독립 스크롤, 360×640/390×844 표시 배율과 터치 높이를 확인한다. 스크린샷은 `/tmp/settlement-mobile-360.png`, `/tmp/settlement-mobile-390.png`에 저장한다. 렌더러는 개발 환경의 X11/소프트웨어 OpenGL이며 모바일 실기기 FPS 측정은 아니다.

[실제 거점 채집 화면](ui/settlement-gathering-mobile.png)

검증에서는 초기 재고에 주변 자원 전체를 더한 목재 28 / 돌 20 / 약초 14의 정확한 최종 입고량, 유한 자원 고갈 후 유휴 처리, 운반 중 취소 후 단일 반환을 확인한다. 여러 채집 정책을 저장하고 불러온 뒤에도 작업 생성 순서가 변하지 않도록 자원 ID를 정렬한다.

최종 결과: `settlement_work_unit`, `settlement_work_acceptance`, `settlement_gathering_acceptance`, `settlement_mobile_acceptance` 모두 PASS. 종료 코드와 SCRIPT ERROR/FAIL 출력을 함께 확인했다. 외부 코드·에셋 반입 없음. 실제 모바일 기기에서의 장시간 성능 측정은 미실행이다.
