# 아이템·전리품·무기 성장 단계 0~2 결과

- 기준 commit: `e55672d`
- 결과 상태: 구현 및 집중 검증 완료
- 결과 commit: 이 문서가 포함된 구현 커밋(최종 hash는 `git log -1`로 확인)

## 구현 결과

- 보상 계열 규칙과 용도 표를 추가했다. 철 주괴는 무기 소재, 마석은 환금품, 식량·포션은 보급품으로 분류된다.
- 종족 드롭 테이블을 `species-drops-v3`로 확장했다. goblin 사망 시 결정적으로 골드 12를 기록한다.
- `ESSENCE_FIRE_BOLT`는 실제 `FIREBOLT`를 참조하는 이능 획득물 후보로 등록했지만, 현재 해당 이능을 사용하는 몬스터 출처가 없어 드롭에는 배정하지 않았다.
- 생성된 이능 획득물은 `generated_reward_items`로 바닥에 놓을 수 있으며 일반 줍기·보관 경로와 흡수 잠금 미리보기를 사용한다.
- 기존 시체 전리품의 실제 소지품 이동과 새 생성 아이템은 그대로 유지했다. 동일 사망 이벤트 재처리는 idempotent하다.
- `WEAPON_SHORT_SWORD_IRON`과 `MATERIAL_IRON_INGOT`을 추가하고, 대표 단검의 원자적 재제작 경로를 연결했다.
- 재제작 미리보기/확정, town journal replay, 복원 시 레지스트리 검증을 연결했다.
- 이능 장착 이벤트·loadout 추가는 제거했다. 아이템 작업은 이능 획득물의 보관과 흡수 불가 상태만 표시한다.

## 재현 명령과 결과

작업 폴더에서 다음을 실행했다.

```text
jq empty data/content/items.json
jq empty data/content/weapons.json
jq empty data/content/species_drop_tables.json
godot --headless --path . --script res://tests/run_json_content_database_tests.gd
godot --headless --path . --script res://tests/run_item_reward_progression_tests.gd
```

결과:

- JSON content database: 5/5 통과
- item reward progression: 4/4 통과
- 집중 테스트는 고정 시드 보상 재현, reward ID 중복 방지, 재제작 identity/affix/equipment 보존, 재료 부족 원자성, revision/event 불변을 확인했다.

## 수치와 알려진 한계

- 테스트용 goblin 골드 보상은 12, 철 주괴 상점 가격은 18, 대표 재제작 재료는 1개, 골드 비용은 0이다. 밸런스 확정값이 아니다.
- 이능 보상은 이벤트의 출처·이능 ID·획득물 인스턴스에 귀속된다. 흡수 서비스가 없으므로 아이템을 소비하지 않으며, 레벨별 결속·제거는 별도 개발서 범위다.
- 층별 T1/T2/T3 깊이 제한과 1·2층 재생성/3층 이후 영속성은 현재 콘텐츠가 단일 대표 재제작 흐름인 관계로 후속 범위다.
- 전체 corpse regression에서는 기존 사용자 횃불 변경으로 화염 피해 기대치가 10에서 5로 달라져 사망 관련 기존 3개 케이스가 실패했다. 이번 보상 변경과 무관한 기준선 차이이며, 횃불 규칙은 이 작업에서 되돌리지 않았다.
- UI 아트·재제작 비교 화면은 추가하지 않았다. 기존 presentation DTO와 town journal API 수준에서 연결했다.
