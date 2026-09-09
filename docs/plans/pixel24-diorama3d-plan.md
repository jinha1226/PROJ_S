# LW-D3D-01 — 현재 Pixel24 에셋 기반 실제 3D 탑뷰 프로토타입

작성일: 2026-09-09 KST. 상태: 계획 완료. 사용자가 새 세션에서 직접 실행을 지시할 예정이며 자동 실행은 중단했다.

## 역할과 전달

- 이번 작업의 설계·감독·결과 검토: 현재 사용자 대화 `01a08481-b273-7f32-8421-9f318803262e`.
- 사용자가 이번 대화에 계획·감독 역할을 명시적으로 지정했다. 저장소 전체 실험 역할표를 변경하는 요청은 아니다.
- 실행: 사용자가 새로 선택하여 직접 지시하는 세션. 기존 UUID나 협업 에이전트로 자동 전달하지 않는다.
- 사용자 지정 실행 설정: Sol / medium (`gpt-5.6-sol`, reasoning effort `medium`). 새 세션에서 사용자가 선택한다.
- 결과 반환: 실행 세션에서 사용자에게 결과 문서·이미지·commit을 직접 보고한다. 사용자가 이 설계 대화에 가져오면 감독·검토를 이어간다.
- 인수인계 문구: `docs/plans/pixel24-diorama3d-handoff.md`.

## 기준 저장소와 최신 푸시 확인

`git ls-remote --heads origin`과 `git fetch origin` 후 원격 ref를 확인했다.
원격: `https://github.com/jinha1226/PROJ_S.git`.
최신 원격 main과 일치하는 작업 폴더는 `/mnt/d/STARTU/living-world-sim-timeline`이다.
기준 commit: `29fcc26c42c427fa7de580603b94fe46e4c0afdb`.
커밋 시각: 2026-09-09 13:20:42 +09:00. 이는 커밋 시각이며 Git만으로 실제 push 시각을 단정하지 않는다.
제목: `feat(art): apply pixel24 item icons and staged settlement buildings`.

| 기존 폴더 | 로컬 HEAD | 확인 당시 상태 |
|---|---|---|
| living-world-sim | d5d6d27 | 별도 기능 브랜치, 사용자 미커밋 변경 다수 |
| living-world-sim-p2 | 9fa56b6 | origin/main보다 137 커밋 뒤 |
| living-world-sim-p3 | 35ec549 | 로컬 main이나 origin/main보다 37 커밋 뒤, 미커밋 변경 존재 |
| living-world-sim-ration | 8e7f9e1 | 배급 기능 브랜치 |
| living-world-sim-timeline | 29fcc26 | origin/main과 일치. 자체 원격 기능 브랜치보다 1 커밋 앞 |

작업 폴더: `/mnt/d/STARTU/living-world-sim-diorama3d`.
작업 브랜치: `feat/pixel24-diorama3d`.
위 기준 commit에서 만든 별도 worktree로 기존 미커밋 변경을 보존한다.
부모 checkpoint/hash: 학습 실험이 아니므로 checkpoint 없음. 부모 소스는 위 전체 Git hash.
원본 에셋의 크기·SHA-256 증거: `docs/plans/pixel24-diorama3d-source-audit.json`.

## 질문과 고정 조건

현재 게임의 Pixel24 색·형태를 실제 입체 에셋으로 재구성했을 때,
수직 탑뷰와 기본 한 칸 24픽셀에서 종족·물건·이동 공간을 식별할 수 있는가?

1. 실제 3D geometry, Godot Node3D / MeshInstance3D / Camera3D 기반이다.
2. 기본 카메라는 직교 투영, 수직 하향(-90도), 축 정렬, 자동 회전 없음.
3. 기준 게임 렌더 영역은 18×18칸, 432×432 렌더 픽셀. 지상 1칸=1 world unit=24 render pixels.
4. 1× 기준 화면에서 한 칸 24 화면 픽셀임을 측정한다. 2×/3× 정수 확대는 검토용이며 픽셀 밀도 계약과 구별한다.
5. 창 크기 변경 시 비정수 확대 대신 기준 렌더 영역을 유지하거나 정수 확대·여백으로 표시한다. HUD는 별도 영역이다.
6. 큰 물체는 여러 칸에 걸쳐도 된다. 나무 수관의 시각 크기와 줄기의 점유 칸을 구별한다.
7. 건물은 기존 STORAGE 3×3, ARMORY 3×2 footprint를 따른다. 이미지 캔버스와 게임 점유를 혼동하지 않는다.
8. 원본 Pixel24 PNG·manifest·기존 런타임 registry를 보존한다. 이번 범위는 별도 실행 가능한 시각·상호작용 실험실이다.

## 실제 사용하는 원본과 구현 참고

- 캐릭터: `playtest/fixed_front_topdown_assets.gd` → `assets/pixel24_v3/runtime/actors/base/`.
- 몬스터: 같은 registry → `assets/pixel24_v3/runtime/monsters/`.
- 현재 착용 장비: 같은 registry의 `assets/pixel24_v3/fit_v2/` 매핑. 오래된 장비 시트를 현행으로 오인하지 않는다.
- 지형: `playtest/topdown_tile_assets.gd` → `assets/pixel24_v3/runtime/terrain/floor1.png`, `floor2.png`; 각 96×96, 4×4개의 24px 셀.
- 건물: `playtest/pixel24_building_assets.gd`와 `assets/pixel24_v3/runtime/buildings/`.
- 건물 점유 정의: `sim/base_settlement_rules.gd`.
- 문서: `docs/plans/pixel24-art-integration.md`, `assets/pixel24_v3/ITEMS_BUILDINGS_INTEGRATION.md`.
- 시각 참고: `assets/pixel24_v3/review/nearest-composites-6x.png`, `terrain_floor1-6x.png`, `review/buildings-v2/nearest-contact-4x.png`.
- 기존 `playtest/low_poly_3d_lab.gd`는 이름과 달리 현재 평면 Sprite3D 기반이다. 이를 그대로 재사용해 실제 입체 에셋이라고 보고하지 않는다.
- 기존 `ascii_3d_lab`의 독립 viewport 및 입력 분리는 구조 참고만 한다.
- 외부 분위기 참고: https://cold-butterfly-ff60.mainstreams.workers.dev/exhibition-atlas?world=133#133 . 특정 종이 정글을 복제하는 요청이 아니다. 기존 게임의 어두운 흙·이끼·목재·광물 팔레트가 우선이다.

## 승인된 첫 구현 범위

하나의 작은 이끼 낀 폐허/목조 야영지 시험 구역을 구현한다.

- 입체 인간, 드워프, 고블린 각 1종. 짧은 체형, 머리/머리카락/수염/귀/옷 색을 원본에서 추출해 계승한다.
- 인간의 검 착용/해제 한 쌍. 장비 전체 종류·종족 전환은 이번 범위가 아니다.
- 창고 timber 3×3, 대장간 ARMORY timber 3×2 각 1종. 현재 건물 그림처럼 내부가 읽히는 개방형/지붕 생략 구조를 우선한다.
- 이끼 바닥, 돌길, 낮은 벽, 작은 물 영역, 나무 1종, 상자·통·화로 등 위 건물에 필요한 소수 부품.
- 캐릭터·건물·나무·상자는 실제 두께/부피를 갖도록 제작한다. 바닥의 기존 텍스처 활용은 가능하다.
- 생성 스크립트나 재사용 가능한 Godot scene/resource로 에셋을 분리한다. 24×24 원본 픽셀을 무조건 독립 cube 576개로 만드는 방식은 피하고 읽히는 큰 형태를 만든다.
- 각 대표 에셋에 원본 파일, 가져온 색/형태, 추정한 측면/뒷면, 모델 경로를 대응한 표를 남긴다. 없는 나무 원본을 있다고 주장하지 말고 동일 팔레트의 신규 파생 디자인으로 표시한다.
- 단순 조명과 그림자로 부피를 드러내되 바닥 무늬와 그림자가 캐릭터 식별을 방해하지 않게 한다.
- 고정된 독립 fixture에서 칸 클릭/키보드 이동, 장애물 차단, 검 장비 토글을 시연한다. fixture의 occupancy가 이동을 결정하고 메시 충돌이 게임 규칙을 대신하지 않는다.
- 원본 2D 스프라이트와 신규 3D 기본 탑뷰를 같은 배율로 비교할 수 있게 한다.

현재 원본 캐릭터는 정면형 전신 그림이다. 진짜 수직 탑뷰 3D에서는 얼굴/몸이 덜 보일 수 있다.
카메라를 몰래 기울이거나 평면 캐릭터로 되돌려 유사도를 얻지 말고, 기본 탑뷰의 종족 식별성을 우선한다.
비교 결과와 제한을 명시한다. 증거 캡처에 한해 별도 경사 시점으로 실제 입체임을 보여줄 수 있으나,
기본 실행·초기화·이동 후 카메라는 항상 수직 탑뷰다. 사용자용 자유 회전 기능은 후속 범위다.

## 예산과 종료 범위

- 이번 작업은 위 1개 구역, 3종 캐릭터, 2종 건물과 소수 부품의 첫 검증까지다.
- 외부 유료 에셋 구매/생성 API, 새 모델 학습, 전 종족·아이템 양산은 포함하지 않는다.
- 기존 Godot 4.6 Compatibility 설정에서 시작한다. 사용 가능한 Blender/Godot 절차 중 단순하고 재현 가능한 것을 선택한다.
- 본편 renderer 교체, sim 규칙/저장 데이터/경제·전투 밸런스 변경, 기존 실험 리팩터링은 포함하지 않는다.
- 완료 결과 commit까지 수행한다. main 병합·원격 배포·후속 실험은 자동 수행하지 않는다.
- 발견한 결함의 수정을 포함해 아래 검증과 문서화를 완료하고 반환한다. 시각 기준에 못 미쳐도 수치나 이미지를 숨기지 않고 미달로 보고한다.

## 실행 전 protocol과 검증

실행 담당은 구체 구현·파일·검증 명령을 `docs/plans/pixel24-diorama3d-protocol.md`에 기록하고 먼저 커밋한다.

필수 증거:

1. 기준 commit 및 원본 에셋 hash 일치. 기존 PNG와 registry 변경 없음.
2. Godot import/parse 성공과 독립 scene 실행 명령.
3. 기본/초기화/이동 후 직교 수직 카메라 유지.
4. 화면 투영으로 지상 X/Z 인접 칸 간격이 각각 24px임을 확인. 1× 기준, 확대 배율, viewport/HUD 범위를 명시.
5. 독립 fixture에서 클릭 칸 왕복 매핑과 이동, 벽·건물 점유 차단, 경계 입력, 장비 토글 확인.
6. 수관 아래 캐릭터/선택 표시가 사라지지 않도록 가림 처리 사례 1개. 시각 수관 전체를 충돌 칸으로 만들지 않는다.
7. 본편 저장/session을 조작하지 않음. 본편 FOV 통합은 미구현으로 명시하고 가짜 통과를 주장하지 않는다.
8. 실제 렌더의 432×432 기본 탑뷰, nearest 확대본, 원본/3D 비교, 경사 증거, 건물·수관 가림 사례 캡처.
9. 대표 모델의 mesh/triangle 수, 전체 draw call 및 frame time을 가능한 실행 환경에서 측정. GPU/소프트웨어 렌더 여부와 측정 한계를 남기며 실제 휴대폰 성능으로 일반화하지 않는다.
10. 관련 Pixel24 에셋 회귀 suite 및 변경한 진입 UI가 있으면 그 focused check. 이미 통과한 검사 반복이나 무관한 전체 실험 실행은 불필요하다.

시각 판정: 1×에서 인간/드워프/고블린을 머리·귀·수염·옷 색으로 구별 가능한가,
장비 on/off가 읽히는가, 창고/대장간 기능이 구별되는가, 걷는 길과 막힌 칸이 읽히는가,
현재 팔레트와의 연속성이 있는가를 각각 결과 문서에서 평가한다. 시각 평가는 측정 사실과 구별한다.

## 결과물 및 반환

- 실행 가능 scene와 에셋/생성 도구, 간단한 실행 안내.
- protocol: `docs/plans/pixel24-diorama3d-protocol.md`.
- 결과: `docs/results/pixel24-diorama3d-result.md`.
- 검증 수치 및 캡처: `docs/results/pixel24-diorama3d/`.
- 결과 commit을 만든 뒤 실행 세션에서 사용자에게 직접 보고한다. 별도 세션으로 자동 queue/message를 보내지 않는다.
- 반환 메시지는 `LW-D3D-01` 상태, 결과 문서 절대 경로, 결과 commit, 해석·다음 진행 판단 요청만 간결히 담는다.

계획 담당은 새 실행을 시작하지 않는다. 사용자가 새 세션에서 직접 실행을 지시하고 결과를 전달하면 검토한다.

전달 기록: 계획 최초 commit `f7d0d8c3ca417b61705e54b74489847aeb7ee8f1`. 지정 UUID에 `codex queue --model gpt-5.6-sol -c model_reasoning_effort="medium"` 전달을 시도했으나 thread/queue/add가 세션 기록 없음으로 실패했다. 실행 요청은 기존 세션에 접수되지 않았다.

사용자 변경 기록: 사용자가 새 세션에서 직접 지시하는 방식으로 전환했다. 이미 연결한 `pixel24_diorama_impl`은 중단했다. 중단 후 worktree는 clean이며 protocol/구현/테스트 결과의 추가 파일 또는 commit이 없음을 확인했다.
