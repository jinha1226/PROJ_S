# 환경 에셋 v1

기존 dark-masonry 벽·바닥을 스타일 참조로 built-in imagegen으로 생성했다. 원본 1254×1254 PNG 세 장을 보존하며, `catalog.json`의 픽셀 좌표를 `AtlasTexture`로 읽는다. 논리 기준은 32px이고 네이티브 32px 도트 시트는 아니다.

## 파일

- `assets/topdown/environment-v1/objects.png`: 기둥, 잔해, 상자, 통, 횃불 점등/소등, 화로 점등/소등, 석관, 제단, 철창, 바리케이드, 뼈, 광석, 석상, 촛불. 실제 투명 알파를 보존했다.
- `assets/topdown/environment-v1/terrain.png`: 물 4종, 잿불·불길·용암 4종, 이끼·진흙·독늪·오염, 서리·얼음·재·철망.
- `assets/topdown/environment-v1/themes.png`: 침수 지하묘지, 폐광, 불탄 성채, 얼어붙은 유적. 각 행은 바닥 A/B, 벽 정면, 벽 윗면 순서다.
- `assets/topdown/environment-v1/catalog.json`: 이름별 영역과 오브젝트 기준점.
- [생성 프롬프트 원문](environment-v1-prompts.json): 세 시트의 최종 프롬프트. 참조 파일은 `dark-masonry-walls-v2.png`, `dark-masonry-tiles-v1.png`다.

## 사용

`expedition/environment_art.gd`의 `object_texture`, `terrain_texture`, `material`, `paint_object`로 읽는다. 오브젝트의 불규칙한 배치 간격은 개별 영역으로 지정해 가장자리가 잘리지 않게 했다. 지형·재질은 시트 구분선을 제외한 내부 영역을 사용한다.

`masonry_tiles.gd.paint_walls`에 선택적인 재질 사전을 전달한다. 기존 가로·세로·모서리 형상 계산과 높이·두께는 그대로 공유한다. 재질을 생략하면 기존 벽을 그린다.

미리보기: `godot --path . tools/art/environment_preview.tscn`

동일한 방 형태를 네 가지 재질로 나란히 표시하고, 물·불 등의 지형과 오브젝트를 함께 배치한다. 아래에는 전체 에셋을 표시한다. 별도 화면 캡처는 만들지 않았다.

## 적용 범위

이번 산출물은 에셋 라이브러리와 미리보기다. 실제 층 생성·충돌·광원·피해·스폰은 변경하지 않아 진행 중인 밸런스 실험 조건에 영향을 주지 않는다. 횃불·불은 정적 이미지이고 애니메이션 프레임은 아니다. 물가 연결 타일과 지형 경계 혼합은 후속 작업이며, 생성 텍스처의 완전한 무봉제 반복을 보장하지 않는다.
