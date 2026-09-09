# LW-TOWN-SPRITE-01 — 본편 마을 주민 스프라이트 통합 프로토콜

## 기준과 질문

- 기준 브랜치/커밋: `origin/main` / `5d40ad2`
- 작업 화면: 본편 2D 마을 지도 `playtest/base_settlement_view.gd`
- 질문: 마을 지도에서 원과 사각형으로 임시 표현하던 주민을 기존 Pixel24 실제 캐릭터 자산으로 교체할 수 있는가?

## 승인 범위

1. 주민 DTO의 `species_id`를 `fixed_front_topdown_assets.gd`에 연결한다.
2. 캐릭터는 24×24 고정 정면 원본과 기존 장비 레이어 순서를 사용하고 nearest 필터를 유지한다.
3. 작업 중 강조, 휴식 침상, 선택·터치·카메라 동작은 보존한다.
4. `species_id`가 없는 이전 DTO는 `human`으로 호환하고, 지원하지 않는 종족만 안전한 기존형 표시로 폴백한다.

## 제외 범위

- 폐기하기로 한 3D 디오라마의 scene, GLB, 카메라, 전용 UI는 `main`에 포함하지 않는다.
- 주민 시뮬레이션, 이동 규칙, 마을 배치 및 건물 자산은 변경하지 않는다.
- 새 생성형 캐릭터 자산은 추가하지 않는다.

## 판정 기준

- 본편 마을의 지원 종족 주민은 `uses_actual_asset=true`인 24×24 캐릭터 텍스처로 그려진다.
- 장비 정보가 있으면 body → armor → offhand → weapon → foreground 순서를 유지한다.
- 작업 및 휴식 상태에서도 캐릭터 본체가 사라지지 않는다.
- 기존 마을 화면 시각/상호작용 smoke와 Pixel24 자산 검증이 통과한다.
- Web export와 export pack 독립 시작이 성공한다.

## 실행 및 산출물

- 집중 검증: `tests/town_resident_sprite_acceptance.gd`
- 회귀 검증: `tests/base_settlement_visual_smoke.gd`, `tests/pixel24_asset_acceptance.gd`, `tests/town_life_acceptance.gd`
- 결과 문서: `docs/results/town-resident-sprite-integration-result.md`
- 종료: 구현·검증·결과 문서를 커밋하고 최신 `main`에 푸시한다.
