# 공용 장비 오버레이 정렬

캐릭터 완성 이미지를 종족별로 만들지 않고, 변경하지 않은 기존 종족 베이스에
가죽갑옷 1장과 철투구 1장을 런타임에 겹친다. 다리는 사용하지 않는다.

![Godot에서 렌더링한 6종족 비교](species-fit.png)

열: 인간 / 엘프 / 드워프 / 오크 / 수인 / 고블린.
행: 원본 / 갑옷 / 투구 / 둘 다. 각 조합 아래는 40px 표시다.

## 구현

- `playtest/fantasy_equipment_overlays.gd`: 원본 128px 캔버스 좌표에 종족별
  몸통·머리 사각형을 정의한다. 동일한 장비 텍스처를 위치·크기만 달리해 사용한다.
- 갑옷이 덮는 기본 회색 옷은 그리지 않고, 원본 머리·목 영역을 UV 폴리곤으로
  다시 그린다. 드워프 수염은 별도 전경 영역으로 보존한다. 베이스 PNG는 수정하지 않는다.
- 순서: 갑옷 → 원본 머리/수염 → 투구 → 기존 방패/확대 무기.
- 갑옷을 해제하면 원본 전신 표시로 돌아간다. 대응하지 않는 종족·장비는 기존 표시를 유지한다.
- `ARMOR_LEATHER`는 기존 장착 DTO를 통해 지도·초상화·페이퍼돌에 반영된다.
- `head_definition_id: HELMET_IRON`은 렌더러와 비교용 입력에만 연결했다.
  실제 인벤토리 HEAD 슬롯은 기존과 같이 비활성 상태다. 투구 장착/능력치/저장은
  이번 작업에서 추가하지 않았다.

## 재현·검증

생성 원본과 프롬프트: `art/sources/fantasy_equipment_overlays_v1/`.
`python3 tools/art/build_equipment_overlays.py`로 투명 이미지의 여백만 잘라 런타임
PNG 두 장을 재생성한다. 종족별 합성 PNG는 만들지 않는다.

```
godot --headless --editor --path . --import --quit
godot --display-driver x11 --path . --script tools/art/review_equipment_overlays.gd
godot --headless --path . --script tests/fantasy_item_expansion_acceptance.gd
```

비교 스크립트는 실제 공용 `draw_actor` 경로로 `/tmp/equipment-overlays-review.png`를
출력한다. 6종족 × 4조합을 128px/40px로 시각 확인했다. 이 정렬표는 현재 정면 고정
베이스 전용이며, 새 종족·방향·다른 장비 실루엣을 추가하면 별도 피팅이 필요하다.
