# 몬스터 사망 후 목재 표시와 장착창 배치

## 확인한 원인

아이템 드롭 테이블이 아니라 정착지 자원 표시 경로가 원인이었다.

1. `base_monster_supply_rules.gd::caches`는 `entity.died` 이벤트를 읽어 고블린에 TIMBER, 코볼트에 STONE, 나머지 종에는 ID 기준 자원을 할당한다.
2. `base_progression_service.gd::_base_cache_rows`는 정착지 활성화 여부를 확인하지 않고 이 자원을 바닥 자원 목록에 추가했다.
3. `party_grid_view.gd::_draw_ground_items`는 시체보다 나중에 자원을 그렸다. TIMBER는 0x72 atlas의 crate `(288,408,16,24)`, STONE은 floor_4 타일이었다.
4. 일반 아이템 드롭 목록만 확인하면 이 경로를 놓친다. 곤봉 이미지 누락은 별도 문제이며 이번 목재의 원인이 아니다.

절차적 던전 seed 1의 고블린을 실제 damage API로 처치해 재현했다. 옛 규칙은 death 17, 위치 `[47,11]`에 `LOOT_EXP1_DEATH17 / TIMBER`를 반환했다. 같은 위치의 실제 아이템은 `WEAPON_SHORT_SWORD`, `ESSENCE_PREDATOR_NERVE`, `MAGIC_STONE`이었다.

## 수정

- 정착지가 비활성화되어 있으면 서비스에서 건설용 바닥 자원을 반환하지 않는다. 몬스터 사망 자원과 고정 채집 지점 모두 적용한다.
- 기존 저장 이벤트와 일반 아이템, 시체 표현은 보존한다.
- 장착창 왼쪽에 선택 캐릭터의 페이퍼돌, 오른쪽에 폭 164px인 장착 영역을 둔다.
- 중앙 머리–몸통–신발, 양옆 손과 각 손 아래 반지를 배치한다. 오른손은 MAIN_HAND, 왼손은 OFF_HAND에 연결한다.
- 현재 실제 장비 계약은 5칸이다. 머리·신발은 비활성 표시 칸이며 아직 장착할 수 없다.

## 검증

- `tests/disabled_settlement_loot_acceptance.gd`: 실제 사망으로 옛 목재 경로를 재현하고, 수정된 서비스에서는 자원이 노출되지 않으며 일반 무기는 드롭됨을 확인.
- `tests/character_views_acceptance.gd`: 페이퍼돌 좌측 배치, 장착 영역 폭, 슬롯 위치, 빈칸 비활성, 필터, 실제 무기 장착, 저장/불러오기 검증.
- 검증은 창 없는 Godot headless로 수행. 육안 스크린샷 검수는 수행하지 않음.
