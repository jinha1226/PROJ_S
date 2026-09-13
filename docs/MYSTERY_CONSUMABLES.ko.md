# 미감정 포션·스크롤 / 아이콘 연결

> 최초 4종 구현 기록. 현재 18종 확장 규칙은 [CONSUMABLES_V2.ko.md](CONSUMABLES_V2.ko.md)를 따른다.

## 적용 범위

사용자가 말한 랜덤 아이템은 처음에는 효과를 모르는 미감정 소모품이다.
이번에는 효과 4종부터 실제 드롭·사용·감정·아이템창에 연결한다.

| 종류 | 감정 후 이름 | 효과 |
|---|---|---|
| 포션 | 활력 물약 | HP 최대 40 회복 |
| 포션 | 마력 물약 | MP 최대 6 회복 |
| 스크롤 | 치유의 두루마리 | HP 최대 50 회복 |
| 스크롤 | 마력 회복의 두루마리 | MP 최대 10 회복 |

회복은 최대 HP/MP를 넘지 않는다. 기존 시작 회복 물약은 이미 알려진
별도 보급품으로 남긴다. 기존 미구현 SCROLL_UNSPECIFIED는 새 드롭에 사용하지 않는다.
독·순간이동·장비 강화·감정 주문 등은 이번 범위에 포함하지 않는다.

## 발견과 감정

- 포션은 붉은색/푸른색, 스크롤은 별/달 문양으로 구분한다.
- 새 게임의 기존 성격/특성 시드로 각 종류의 외형–효과 대응을 섞는다.
  같은 판에서는 동일 외형이 동일 효과이고, 층 이동·저장 복원으로 바뀌지 않는다.
  무작위이므로 다음 판에도 우연히 같은 대응이 나올 수 있다.
- 미감정 상태에서는 이름·설명·회복 수치를 감춘다. 바닥과 가방은 같은 외형을 쓴다.
- 사용하면 1개와 기존 아이템 행동 시간을 소모하고 해당 종류를 감정한다.
  이미 가진 나머지와 이후 주운 같은 종류도 실제 이름·효과가 표시된다.
- 미감정이면 HP/MP가 가득 차 있어도 감정 목적으로 사용 가능하다.
  감정된 회복품은 해당 자원이 가득 차 있으면 소모하지 않는다.
- NPC에게 치료품을 주는 경로는 미감정 효과를 미리 알아내거나 자동 소비하지 않는다.

## 드롭과 저장

드롭 테이블이 있는 종족의 사망 시, 기존 드롭과 독립적으로 18% 확률로
새 소모품 4종 중 1개를 바닥에 추가한다. 동일 시드·사망 이벤트에서는
동일 결과가 나온다. 기존 드롭의 난수 키는 유지한다.

드롭 규칙은 species-drops-v4. 이전 v1/v2/v3 드롭 이벤트의 검증 경로는
유지하지만, 이번 문서는 모든 과거 버전의 전체 명령 재생 호환성을 보증하지 않는다.
감정 정보는 item.identified 이벤트, MP 회복은 item.energy_restored 이벤트로
저장하고 검증한다. 화면 표시 캐시는 저장 데이터가 아니며 복원 시 재구성한다.

## 검증 명령

```sh
godot --headless --path . --script tests/mystery_consumables_acceptance.gd
godot --display-driver x11 --audio-driver Dummy --path . --script tests/mystery_items_ui_acceptance.gd
godot --headless --path . --script tests/monster_ability_drops_acceptance.gd
godot --headless --path . --script tests/potion_latency_death_layout_regression.gd
godot --headless --path . --script tests/run_corpse_drop_materialization_tests.gd
```

신규 검증은 외형 대응, 랜덤 드롭, 미감정 수치 은폐, 최초 사용,
나머지 수량 감정, 최대치 소모 방지, 실제 HP/MP 회복, 월드 검증과 스냅샷 복원,
390px 모바일 아이템창을 다룬다. 신규 회복 테스트는 아이템 지급만 픽스처로
넣고 피해·MP 지출은 실제 이동/전투/스킬 명령으로 만든다.
새 소모품의 자연 드롭→획득→사용 전체 명령 재생은 별도 장기 플레이 검증 대상이다.

아이콘과 생성 프롬프트 사양: `assets/generated/item-icons-v1/README.md`.
모바일 검증 스크린샷 출력: `/tmp/mystery-items-mobile.png`.

## 실행 결과

2026-09-13, Godot 4.6.2: 신규 소모품 검증 PASS, X11/llvmpipe 모바일 UI
검증 PASS, 기존 이능 드롭 16종 검증 PASS, 기존 물약/사망 레이아웃 회귀 PASS.
사망→바닥 생성→줍기→스냅샷 검증도 미감정 소모품을 포함해 10개 모두 PASS.
UI 스크린샷을 열어 두루마리/식량 아이콘과 미감정 팝업 표시를 확인했다.
