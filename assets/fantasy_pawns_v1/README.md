# 판타지 폰 게임용 에셋 v1

승인한 [생성 원본](../concepts/fantasy_pawns_v1/README.md)을 게임용으로 가공한 세트다. 입체감 없는 맵 목업은 적용하지 않았다. 사용자가 코드 배경 제거·자르기를 명시적으로 승인한 후 제작했다.

## 구성과 적용

- `species/`: 인간·엘프·드워프·오크·수인·고블린, 128px RGBA. 한 칸 크기의 캔버스 안에 배치하고 발 기준점은 높이의 94%로 통일했다. 드워프·고블린은 조금 작다. 범용 인간형은 인간을 공유한다.
- `items/`: 장비·소모품·원소 부위 16종, 128px RGBA. 반지·활 안쪽도 투명하다. [분리 결과](cutout-review.png).
- `tiles/`: 원본 16종과 세로 통로용 문 2종, 64px RGBA.
- `walls/`: 원본 벽의 돌 윗면과 어두운 앞면을 재조합한 16종. 알려진 상하좌우 바닥 경계에만 윤곽선을 붙이고, 남쪽이 바닥일 때만 어두운 앞면을 노출한다. 그림 전체를 회전해 음영 방향을 바꾸지 않는다.
- `monsters/`: 후속 제작한 몬스터 12종, 128px RGBA. [목록·크기 비교·검증 기록](../../docs/art/fantasy-monsters-v1/README.md). 던전 오크(`dcss_orc`)는 기존 오크 베이스를 공유한다.

메인 원정 화면, 파티 초상화, 인물 상세 초상화, 가방과 장착 슬롯, 바닥 아이템에 적용했다. 무기·방패는 몸통 옆 작은 부착물로 표시한다. 종족 베이스에는 갑옷 전용 레이어나 걷기 프레임이 없으므로 기본복을 사용하고, 이동 보간은 기존 시스템을 유지한다.

실제 아이템 ID 매핑은 [fantasy_pawn_assets.gd](../../playtest/fantasy_pawn_assets.gd)의 `ITEM_IDS`가 기준이다. 불·냉기·물·전기 부위는 기존 `ESSENCE_*`, `PART_*` ID를 그대로 연결했다. 식별 전 물약 색상, 새 그림이 없는 무기·방어구·몬스터·지형은 기존 에셋을 사용한다. 투구는 파일만 준비되었으며 새 아이템 정의를 추가하지 않았다. 반지는 기존 범용 액세서리 이미지로 연결했다. 실험용 별도 전투/재구축/입체 투영 화면의 렌더러를 전면 교체하는 작업은 포함하지 않는다.

## 재생성

저장소 루트에서 실행한다. Python 3, Pillow, NumPy, SciPy가 필요하다. 원본은 덮어쓰지 않는다.

```bash
python3 tools/art/build_fantasy_pawns.py
godot --headless --path . --editor --quit
```

외곽선으로 둘러싸인 영역을 보존하고 바깥 체크무늬를 제거한다. 반지·활의 내부 구멍은 명시한 좌표에서 영역을 찾아 제거한다. 균등 격자를 가정하면 잘리는 활 끝을 보존하도록 행 경계를 직접 지정했다. `extraction.json`에 원본 해시와 잘라낸 영역을 기록한다.

이 배경 제거 방식은 이 원본의 닫힌 짙은 외곽선에 맞춘 것으로, 다른 시트에 무조건 재사용할 수 없다. 생성 원본의 미세한 그라데이션은 보존했다.

## 확인

```bash
godot --headless --path . --script tests/fantasy_pawn_assets_acceptance.gd
godot --headless --path . --script tests/topdown_generated64_acceptance.gd
godot --headless --path . --script tests/species_picker_start_regression.gd
godot --display-driver x11 --path . --script tools/art/preview_fantasy_pawns.gd
```

첫 테스트를 화면 모드로 실행하면 `/tmp/fantasy-pawns-game.png`, `/tmp/fantasy-pawns-inventory.png`를 저장한다. 마지막 도구는 실제 타일·종족 매핑으로 `/tmp/fantasy-pawns-connections.png`를 저장한다. 게임 규칙·시야·이동 판정·드롭 테이블은 변경하지 않는다.
