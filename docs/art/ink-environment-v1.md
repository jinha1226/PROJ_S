# 먹선 환경 v1

가독성 보정: 현재 재질은 같은 폴더의 materials-soft-v3.png를 사용한다. 내장 imagegen으로 검은 틈과 그림자를 짙은 회색·갈색으로 완화했다. 기존 4×4 영역과 2px 이동 격자는 유지하며 캐릭터·소품 먹선은 그대로 둔다. 프롬프트는 materials-soft-v3-prompts.json.

인간 캐릭터 ink-torso-v1을 기준으로 기존 거점·1층 재질·소품을 내장 imagegen으로 수정했다. 단순한 외곽선뿐 아니라 큰 검은 그림자 면, 각진 명암, 끊어진 윤곽을 사용한다.

## 원본과 적용

- 거점: assets/ui/settlement-hub-ink-v3.png (853×1844). 지붕 아래·문 안쪽·건물 측면·수목의 그림자를 강화했다. 시설명과 터치 영역은 기존 배치를 유지한다.
- 재질: assets/topdown/floor1-ink-v2/materials.png (1254×1254). 4×4, 판석 4종과 벽 정면/상부 및 특수지형. 바닥은 따뜻한 회색, 벽은 차가운 회색으로 구분한다.
- 소품: assets/topdown/floor1-ink-v2/props.png (1254×1254 RGBA). 기존 16종의 실루엣을 유지하며 큰 먹선 명암을 추가했다.
- 영역: 같은 폴더의 catalog.json. 소품의 새 알파 경계를 기준으로 영역을 다시 지정했다. 이미지 후처리 없이 원본을 AtlasTexture로 읽는다.
- 프롬프트와 참조: [ink-environment-v1-prompts.json](ink-environment-v1-prompts.json).

floor1_art와 settlement_hub가 새 원본을 사용한다. 기존 벽 연결 구조, 2px 이동 격자, 시야와 기억, 캐릭터 확대, 충돌과 스폰 규칙은 유지한다. 이전 이미지들은 비교를 위해 보존한다.

tools/art/floor1_flat_preview.tscn에서 먹선 캐릭터·새 타일·소품을 함께 확인할 수 있다. 소품 전체를 제작했지만 신규 장애물이나 횃불 스폰을 추가한 것은 아니다.
