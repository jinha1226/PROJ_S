# CI·DEV 표면 정리 protocol

- 작업 ID: `CI-DEV-CLEANUP-001`
- 기준 commit: `3a36b8f692c0db7e42a90758d1474adede88c914`
- 질문: Pages 배포 안전 검증을 유지하면서 장시간 테스트와 제품 메뉴의 개발용 진입점을 제거할 수 있는가?

## 변경 범위

- Pages workflow에서 필드·능력·환경 테스트를 실행하는 세 단계를 제거한다.
- 스크립트 import 검증, Web export, export pack runtime 검증과 Pages 배포는 유지한다.
- 제품 메뉴에서 `4인 전투 테스트 · 마법`과 환경 시험 4종을 제거한다.
- 제거된 메뉴 ID의 라우팅과 전투 lab 진입 함수도 제거한다.
- 테스트 파일, 전투·환경 시스템, 내부 balance 도구는 로컬 검증 자료로 보존한다.

## 판정과 종료

- workflow YAML에 `tests/` 실행이 남지 않아야 한다.
- 제품 메뉴와 handler에 개발용 ID `6`, `20`~`23`이 남지 않아야 한다.
- Godot import와 제품 UI의 기본 시작 smoke가 통과해야 한다.
- 추가 기능 삭제나 밸런스 변경 없이 종료한다.
