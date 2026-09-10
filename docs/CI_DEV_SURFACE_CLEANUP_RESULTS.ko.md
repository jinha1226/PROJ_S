# CI·DEV 표면 정리 결과

- 작업 ID: `CI-DEV-CLEANUP-001`
- Pages workflow의 직렬 테스트 3단계를 제거했다.
- 스크립트 import, Web export, export pack runtime 검증과 배포는 유지했다.
- 제품 메뉴의 4인 전투 lab과 환경 시험 4종 진입점 및 menu handler 라우팅을 제거했다.
- 핵심 테스트 소스와 내부 전투·환경 구현은 보존해 필요할 때 로컬에서 실행할 수 있다.
- 제거된 환경 시험 메뉴만 검증하던 `environment_tools_acceptance.gd`와 전투 lab의 제품 메뉴 진입 검증은 함께 제거했다. 전투 lab 자체의 독립 smoke와 환경 핵심 회귀는 보존했다.

## 기대 효과

최근 성공 run `34495549850`에서 제거 대상은 7분 6초를 사용했다. 같은 run의 다운로드·import·export·pack 검증·업로드 시간은 유지되므로 네트워크 편차를 제외한 build job은 약 8분 33초에서 약 1분 27초 수준으로 줄어드는 것이 기대값이다.

## 검증

- workflow 내 `tests/` 실행 부재를 확인했다.
- 제품 메뉴 문자열과 개발용 menu ID 라우팅 부재를 확인했다.
- `godot --headless --path . --editor --quit`: 통과.
- `godot --headless --path . --script tests/solo_start_acceptance.gd`: 통과(`SOLO START: []`).
- `godot --headless --path . --script tests/active_combat_lab_smoke.gd`: 독립 lab smoke 통과(0 failures).
