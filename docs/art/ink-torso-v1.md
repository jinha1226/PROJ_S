# 먹선 토르소 · 인간 레이어 v1

가독성 수정 v2: 현재 원본은 parts-readable-v2.png. 얼굴의 검은 눈·볼 그림자를 줄이고 피부 면적을 넓혔으며 몸통 명암을 단순화했다. 전체 표시 배율은 유지하고 머리 배치만 92×139에서 110×167로 약 20% 확대했다. 머리 중심 x=128, 하단 y=163을 유지한다. 인게임 배치·docs/art/catalog.json·HTML 미리보기를 함께 갱신했다. 내장 imagegen 편집 프롬프트는 ink-torso-readable-v2-prompts.json.

선택한 짧고 넓은 토르소와 각진 먹선 스타일을 인간 주인공 아린에 적용한다.
원본 시안은 [torso-rimworld-darkest-v1.png](torso-rimworld-darkest-v1.png).

- 현재 파츠 원본: `assets/characters/ink-torso-v1/parts-readable-v2.png` (1254×1254 RGBA). 이전 parts.png는 비교용으로 보존한다.
- 배치: `assets/characters/ink-torso-v1/catalog.json`. 사용자가 미리보기에서 저장한 `docs/art/catalog.json`의 배치를 반영했다. 좌표 기준은 256×256.
- 렌더링: 기본복/갑옷 몸통 중 하나 → 머리 → 검과 손 → 방패 순서. 이미지를 합쳐 저장하지 않고 실행 시 AtlasTexture로 겹친다.
- 인게임 기본 조합은 갑옷·검·방패. 외형만 바뀌며 장비 능력치나 인벤토리 교체와 연결된 상태는 아니다.
- 아린의 보드 표시와 이동 예약 잔상에 적용한다. 다른 동료·몬스터·상태창 초상화는 기존 그림을 사용한다.
- 보드와 이동 잔상은 하단을 고정하고 위로 확대한다. 레이어 인간은 기존 표시 영역의 2.0배, 여백이 적은 기존 동료는 1.67배로 표시한다. 타일 점유와 판정은 유지한다.
- 웹 내보내기에 배치 JSON을 포함한다.

## 배치 수정

[레이어 미리보기](ink-torso-layer-preview.html)를 브라우저에서 열면 기본복/갑옷, 머리, 검, 방패를 선택하고 위치와 크기를 조절할 수 있다. 초기 배치는 인게임 JSON과 동일하다.
수정 후 저장한 `catalog.json`은 `assets/characters/ink-torso-v1/catalog.json`에 반영하고 게임을 다시 실행한다. HTML에는 로컬 파일로도 열 수 있도록 초기 배치가 내장되어 있으므로 함께 갱신한다.

Godot에서는 `tools/art/floor1_flat_preview.tscn`을 실행하면 실제 타일과 주인공을 함께 볼 수 있다.
첫 시제품은 한 방향이며, 목·어깨 가림과 작은 크기의 가독성은 플레이하면서 다듬는다.

[생성 프롬프트](ink-torso-v1-prompts.json). built-in image_gen으로 제작했으며 원본 알파와 색상을 보존했다.
