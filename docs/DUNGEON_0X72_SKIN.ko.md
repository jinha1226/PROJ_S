# 0x72 그래픽 교체

2026-09-12. Kenney 기반 화면을 0x72 DungeonTileset II 기반으로 교체했다.
게임 시뮬레이션과 HUD → 게임 화면 → 로그 → 초상화 → 하단 버튼 구조는 유지했다.

## 적용 범위

- [0x72 원본 v1.7](https://0x72.itch.io/dungeontileset-ii)의 캐릭터, 몬스터, 무기, 물약, 지형을 사용한다.
- [Niji Extended v1.1](https://nijikokun.itch.io/dungeontileset-ii-extended)의 같은 스타일 횃불, 불꽃, 가방, 문을 함께 사용한다.
- 두 배포 페이지의 CC0 선언, 다운로드 버전과 해시는 `assets/0x72/dungeon-ii/SOURCE.md`에 기록했다. 외부 실행 코드는 가져오지 않았다.
- 던전, 초상화, 인벤토리, 바닥 아이템, 마을 시설 아이콘을 연결했다. 기존 Kenney 파일은 보존하지만 활성 스킨은 사용하지 않는다.
- 원본 영역 좌표를 정적 데이터로 보관하고 AtlasTexture를 캐시한다. 캐릭터와 긴 무기의 가로세로 비율을 유지한다.
- 걷기 프레임이 있는 캐릭터는 기존 이동 중 다시 그리기에서 프레임을 선택한다. 정지 애니메이션 때문에 상시 다시 그리기를 추가하지 않았다.
- 라이선스와 출처 문서가 내보내기에 포함되도록 필터를 추가했다.

## 남아 있는 외형 한계

- 수인, 코볼트, 슬라임, 딱정벌레 일부는 원본의 유사 캐릭터로 대체한다.
- 석궁은 다른 활 그림, 식량은 녹색 병, 일부 재료는 해골 등 대체 아이콘이다.
- 방패 전용 그림이 없어 중립적인 갈색 도형으로 표시한다. 방어구 아이콘은 있으나 착용 시 몸체에 맞춰 바뀌는 갑옷 레이어는 없다.
- 좌우 반전과 원본 걷기 프레임을 사용하며, 진짜 8방향 캐릭터 세트는 아니다.
- 물은 지형 색조로 구분하고, 마을 시설은 완성된 건물 그림 대신 같은 팩의 상징 아이콘을 사용한다.

## 검증

- `godot --display-driver x11 --rendering-method gl_compatibility --path . --script tests/dungeon_0x72_acceptance.gd`: `0X72 ASSETS: PASS`.
  영역 경계, 캐시 재사용, 종족 매핑, 미탐색 타일 숨김, 관측의 상태 불변성, 실제 장비 교체, 방패 대체 표시와 월드 유효성을 검사했다.
- `godot --headless --path . --script tests/mobile_combat_loot_torch_acceptance.gd`: `MOBILE COMBAT LOOT TORCH: PASS`.
- 390×844 화면을 실제 렌더링하고 비율과 장비 표시를 확인했다: [던전](previews/0x72-dungeon-mobile.png), [인벤토리](previews/0x72-inventory-mobile.png).
- 데스크톱 소프트웨어 렌더러에서 확인한 결과다. 모바일 실기기 FPS나 웹 배포 완료를 의미하지 않는다.
