# 연속 원형 암흑·횃불 조명 결과

- 작업 ID: `RADIAL-DARKNESS-001`
- 기존 `NEAR / MID / EDGE` 3단계 명암을 유클리드 거리 기반 연속 감쇠로 교체했다.
- 캐릭터 중심의 암흑 오버레이를 18개 반경 × 48개 각도 조각으로 구성하고 vertex alpha를 보간해 타일보다 작은 해상도로 부드럽게 사라지도록 했다.
- 모든 조각을 하나의 `ArrayMesh` surface로 합쳐 프레임당 draw call 하나로 그린다. 투영·시야·횃불·층 상태가 바뀔 때만 mesh를 재구성한다.
- 점화한 휴대 횃불은 중심 암흑을 낮추고 원형 감쇠 반경을 넓힌다. 기존 따로 그리던 딱 잘린 두 개의 원은 제거했다.
- 원형 조각은 중심 표본이 `VISIBLE`인 곳에만 생성한다. 벽 뒤 `MEMORY`와 `UNSEEN`은 밝히지 않으며 적·아이템·입력 판정도 기존 권위를 유지한다.
- 1층, 2층, 3층 이상은 같은 연속 함수에서 중심 암흑·가장자리 암흑·무횃불 반경만 달라진다.

## 검증

- `tests/radial_darkness_acceptance.gd`: 통과. 중심→중간→외곽 단조 감쇠, 횃불 중심/반경, 360·450px 다중 고리, MEMORY 비조명, 단일 mesh surface를 확인했다.
- `tests/solo_start_acceptance.gd`: 통과(`SOLO START: []`).
- `tests/run_party_ascii_visual_tests.gd`: 새 연속 조명 검사는 통과했다. 전체 묶음은 이번 변경과 무관한 기존 asset/selection 기대 불일치 5개 test가 남아 있어 전체 통과로 기록하지 않는다.
- headless `frame_post_draw` 캡처는 렌더 신호 대기에서 완료되지 않아 중단했다. 수치·mesh·제품 시작 경로 검증은 정상 완료했다.

## 알려진 한계

- 가림 경계는 기존 타일 LOS 권위를 따르므로 벽 모서리에서 작은 부채꼴 단위의 feather가 보일 수 있다. 정보가 벽 너머로 노출되지는 않는다.
