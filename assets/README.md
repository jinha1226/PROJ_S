# 게임 에셋 안내

## 현재 채택한 스타일

| 폴더 | 사용처 |
|---|---|
| [fantasy_pawns_v1](fantasy_pawns_v1/README.md) | 종족·몬스터·장비·소모품·특수부위·타일·연결 벽 |
| [ui/fantasy_pawns_v1](ui/fantasy_pawns_v1/README.md) | 현재 명령·상태 아이콘 |
| fonts | 게임 한글·영문 글꼴 및 라이선스 |

매핑 기준은 `playtest/fantasy_pawn_assets.gd`, `playtest/topdown_tile_assets.gd`, `playtest/gameplay_pixel_icons.gd`다. 원본 시트는 [art/sources](../art/README.md), 현재 적용 캡처는 [docs/art](../docs/art/README.md)에 있다.

## 함께 유지하는 기존 에셋

현재 팩에 없는 이미지의 대체 경로와 기존 렌더러·테스트가 있으므로, 아래 폴더는 이름만 보고 삭제하지 않는다.

- `0x72/`: 아직 사용 중인 몬스터·장비·환경 이미지의 대체 팩. CC0 출처 문서를 함께 유지한다.
- `generated/item-icons-v1/`: 기존 아이템 아이콘 대체 경로.
- `generated/topdown_tactical64_v1/`, `generated/topdown_walls_doors64_v1/`: `legacy_generated_tile_assets.gd`가 참조하는 지형.
- `ui/gameplay_v4/`, `ui/dark_fantasy_v1/`: 기존 UI 리소스와 검증 자료.
- `pixel24_v3/`, `pixel24_v4/`, `topdown_fixed_front/`, `handcrafted64/`, `illustrated_front/`, `kenney/`: 기존 캐릭터·아이템·렌더러 팩. 별도 화면과 검증 참조를 확인한 후에 교체한다.
- `generated/dark_fantasy_topdown_v2/`, `generated/modular_topdown_v1/`, `generated/topdown_cutout_v1/`, `3d/`, `living_expedition_v2/`, `sprites/`: 과거 실험 화면·제작 체계에 속하는 자료. 이번에는 해당 화면의 코드를 폐기하지 않고 유지했다. Web 빌드 제외 범위는 `export_presets.cfg`가 기준이다.

## 이전 시안 찾기

사용하지 않는 생성 시트·컨셉·이전 화면은 [art/archive](../art/archive/README.md)로 이동했다. 이미지 내용과 라이선스·프롬프트를 보존했으며, 이번 정리는 Git 이력 삭제나 용량 축소 작업이 아니다.
