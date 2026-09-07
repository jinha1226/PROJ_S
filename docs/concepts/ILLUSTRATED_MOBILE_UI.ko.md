# 모바일 일러스트 에셋 적용

2026-09-07. 기존 픽셀 스킨 작업 위에 적용한 모바일 가시성 실험.

- 고정 정면, 이목구비 없는 단순한 머리/몸통, 짙은 외곽선, 제한된 음영.
- AI 생성 원본: assets/illustrated_front/raw/actors.png 및 terrain.png.
- 캐릭터는 3×3 원본의 418px 셀을 분리, 투명 여백 제거, 최대 216×224로 축소 후 256×256 투명 캔버스에 발 기준 정렬.
- 지형은 4×4 원본을 1024×1024로 정규화, 256px 영역 단위 사용. 1층 이끼/흙, 2층 재/석재 팔레트.
- 생성 요청: reference-matched dark fantasy, simple smooth outlined faceless front-facing actors, transparent evenly spaced 3×3 sprite sheet, consistent baseline, no weapons/text/UI/shadows. Human/dwarf/elf/orc/beastkin/goblin/kobold/slime/beetle.
- 지형 생성 요청: seamless low-contrast flat overhead 4×4 atlas, slate/moss/ash floors, water, walls, rubble, metal, inactive/active portal; no perspective or directional paths.
- 생성 ID: actors exec-8ed600cd-9763-4aed-9700-cdc69d321792; terrain exec-a8696012-1d40-4711-8204-a5999865fa6a; reference exec-48461282-925b-4f4d-8f69-c9cddd56e978 (동일 생성 세션 01a06bda-10f8-7b52-b038-37fa86676efc).
- slime/beetle 등록은 출현 규칙을 추가하지 않음. 장비 합성은 이전과 같이 비활성: 기존 픽셀 장비를 새 몸에 겹치지 않음. 실제 장비 능력치는 유지.

## 화면 구성

상단 48px, 한 줄 이벤트 24px, 파티 72px, 행동 버튼 48px. 중복 하단 내비게이션을 숨기고 가방 버튼/메뉴/인물 초상화로 상세 화면 접근.

파티 높이는 인원과 무관하게 고정하고 너비와 정보량만 변경한다.

- 1명: 넓은 초상화 카드, 이름, HP 수치/막대, 감정.
- 2명: 반폭 카드, 이름, HP 수치/막대.
- 3명: 초상화 옆 짧은 이름, 하단 HP 막대.
- 4명: 색상별 프레임의 머리/어깨 초상화와 하단 HP 막대/수치. 이름 등 상세 정보는 탭해서 확인.

이동 중 빠른 갱신 경로에서도 카드 HP/선택 상태를 갱신한다. 실제 휴대폰 가시성 및 터치 체감은 기기 검증이 필요하다.

## 컨셉 UI 후속 반영

기존 픽셀 프레임을 공유 코드 기반 둥근 회색 패널로 교체. 상단은 미니맵/F층/남은 시간/메뉴, 하단은 색상별 초상화와 탐험·상호작용·공격·대기/방어·가방 아이콘으로 구성. 글꼴은 기존 라이선스 포함 NanumSquareR을 사용한다. 아이콘은 코드로 그려 생성 이미지 속 가짜 버튼을 사용하지 않으며 기존 명령과 비활성 상태를 유지한다. 360px에서는 터치 표적을 확보하기 위해 컨셉의 초상화와 행동 버튼을 한 줄에 강제로 배치하지 않고 두 줄을 유지한다.

AUTO 마지막 이동에서 예약된 전체 UI 갱신이 새 터치의 down/up 사이에 실행되면 grid.cancel_pointer_gesture가 터치를 지우던 경로를 차단했다. 전체 갱신은 제스처 종료 후 수행하고, 모달 진입/핀치는 기존 명시적 취소를 유지한다. tests/auto_touch_handoff_smoke.gd에서 AUTO 이동 → 터치 down → 전체 갱신 → up → 수동 이동 반영을 검증한다.
