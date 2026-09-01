# 엔티티 인벤토리·장비·시체 루팅 구현 지시서

## 0. 문서의 지위

이 문서는 현재 주인공 전용인 인벤토리·장비 상태를 모든 전투 캐릭터로 일반화하고,
몬스터 사망 후 소지품·착용 장비·종족 드롭을 루팅할 수 있게 만드는 작업의 구현 계약이다.

구현 순서는 다음과 같이 고정한다.

```text
A. 엔티티 단위 인벤토리·장비 기반 — 동작 변화 0
→ C. 사망·시체 루팅·종족별 드롭
→ B. 적 장비의 전투 반영
→ D. 동료 인벤토리 UI
```

A와 C를 먼저 닫는다. B는 전투 시스템을 손보는 단계로 분리하고, D는 canonical 상태와
명령 facade가 안정된 뒤 진행한다.

여기서 A의 “동작 변화 0”은 플레이 중 아이템·전투·AI 결과가 같아야 한다는 뜻이다.
snapshot v7 전환과 v6 저장 거부는 HARD_CUT 정책에 따른 명시적인 wire 계약 변경이다.

## 1. 최종 사용자 경험

최종적으로 주인공, 동료, 적, 중립 NPC는 같은 인벤토리와 장착 슬롯을 가진다. 몬스터가
죽으면 그 몬스터가 실제로 들고 있거나 착용했던 아이템은 시체에 그대로 남고, 종족별
드롭 테이블로 생성된 전리품도 함께 루팅할 수 있다.

```text
고블린 시체
├─ 장착했던 녹슨 단검       # 생전부터 존재한 동일 item instance
├─ 장착했던 누더기 갑옷     # 생전부터 존재한 동일 item instance
├─ 가방에 있던 회복약       # 생전 소지품
└─ 고블린 귀                # 사망 시 종족 드롭 테이블로 생성
```

장착품을 드롭 테이블로 다시 생성하지 않는다. 생전 아이템과 사망 생성 아이템을 분리하여
중복 보상을 막는다.

## 2. 절대 결정 사항

- 인벤토리의 canonical 소유자는 `PartyEncounterState`가 아니라 `SimWorldState`다.
- `ground_items`도 인벤토리와 함께 월드 아이템 집합체로 이동한다.
- 모든 전투 엔티티의 가방 용량은 12칸으로 통일한다.
- 장착 슬롯에 꽂힌 아이템은 인벤토리의 ownership table에 계속 존재한다. 현재와 같이
  장착 아이템은 12칸 가방 사용량에는 포함하지 않는다.
- `equipped_weapon_id`를 별도 권위로 저장하지 않는다. 현재 주무기는 인벤토리의
  `MAIN_HAND` 아이템에서 도출한다.
- 화살·볼트 수량과 장전 여부는 장착 무기 ID와 분리된 runtime 상태로 둔다.
- 죽은 엔티티의 인벤토리를 즉시 삭제하거나 전부 새 아이템으로 변환하지 않는다.
- 종족 드롭은 `entity.died` 한 건당 정확히 한 번만 생성한다.
- 모든 preview는 순수하고, 모든 commit은 원자적이며, 실패 시 snapshot·RNG·ID·event
  ledger·revision이 완전히 동일해야 한다.
- float 확률을 사용하지 않는다. 드롭 확률은 `0..1000` 정수 단위로 계산한다.
- 런타임 드롭 판정은 전역 RNG draw 순서를 소비하지 않는다.

## 3. 비목표

### A의 비목표

- 몬스터 장비가 공격력·방어력·회피·명중을 바꾸는 것
- 몬스터가 AI 판단으로 아이템을 줍거나 장착·교체·사용하는 것
- 시체 상호작용과 종족 드롭
- 동료 인벤토리 화면
- 가방 크기·무게·부피의 종족별 차이

### C의 비목표

- 적 장비의 전투 수치 반영
- 적의 능동적 장비 교체 AI
- 상점, 제작, 내구도, 아이템 파괴
- 동료 간 자동 아이템 분배
- 시체 부패와 시간 경과에 따른 전리품 손상

## 4. canonical 소유 구조

`SimWorldState`에 `WorldItemState` 하나를 둔다.

```text
SimWorldState
├─ entities[entity_id]
├─ combatant_states[entity_id]
├─ agent_states[entity_id]
├─ item_state: WorldItemState
│  ├─ revision
│  ├─ next_item_instance_id
│  ├─ inventory_rows[entity_id]: InventoryState
│  ├─ ammo_pool_rows[entity_id]: AmmoPoolState
│  ├─ weapon_runtime_rows[item_instance_id]: WeaponRuntimeState
│  └─ ground_items: GroundItemState
├─ encounter_lab
└─ party_encounter
```

`WorldItemState`가 인벤토리와 바닥 아이템을 함께 소유하므로 pickup/drop/loot가 서로 다른
상태 소유자와 revision을 가로지르지 않는다. `PartyEncounterState`는 파티 구성과 현재
던전 조우 상태만 계속 소유한다.

### 4.1 `WorldItemState` wire v1

```text
schema_version: 1
revision: int64 canonical string
next_item_instance_id: int64 canonical string
inventory_rows: entity_id 오름차순 Array
ammo_pool_rows: entity_id 오름차순 Array
weapon_runtime_rows: item_instance_id 오름차순 Array
ground_items: GroundItemState v1
processed_drop_death_event_ids: int64 오름차순 Array
```

예시:

```json
{
  "schema_version": 1,
  "revision": "14",
  "next_item_instance_id": "32",
  "inventory_rows": [
    {"entity_id": "1", "inventory": {"schema_version": 1}}
  ],
  "ammo_pool_rows": [
    {
      "entity_id": "1",
      "ammo_pool": {
        "schema_version": 1,
        "ammo_pools": [
          {"ammo_kind": "ARROW", "amount": 12},
          {"ammo_kind": "BOLT", "amount": 6}
        ]
      }
    }
  ],
  "weapon_runtime_rows": [],
  "ground_items": {"schema_version": 1, "rows": []},
  "processed_drop_death_event_ids": []
}
```

실제 `InventoryState` 직렬화는 기존 필드 전체를 유지한다. 위 JSON의 축약된 inventory는
구조 위치를 설명하기 위한 예시일 뿐 exact fixture가 아니다.

### 4.2 인벤토리 이름 일반화

`ProtagonistInventoryState`를 범용 `InventoryState`로 바꾼다. 내부 의미와 직렬화 구조는
A에서 가능한 한 유지한다.

- `backpack`은 소유 아이템 전체의 canonical table이다.
- `equipped`는 `backpack`에 존재하는 instance ID만 참조한다.
- `used_backpack_slots()`는 장착되지 않은 row만 센다.
- `equipment_bonuses()`와 `combat_modifier_dto()`는 그대로 범용 API가 된다.
- `with_legacy_weapon()` 같은 주인공 bootstrap helper는 범용 상태에서 제거하고 session
  bootstrap 쪽으로 옮긴다.

Godot resource rename으로 `.uid`와 preload 경로가 불안정해질 경우 첫 커밋에서는 기존
파일을 compatibility wrapper로 남길 수 있다. 최종 A 완료 시 새 코드가
`ProtagonistInventoryState`라는 이름을 직접 참조해서는 안 된다.

### 4.3 무기 권위와 runtime 상태

현재 `WeaponLoadoutState.equipped_weapon_id`와 인벤토리 `MAIN_HAND`가 같은 사실을 중복
저장하고 `inventory_loadout_bridge_mismatch`로 묶고 있다. 이 중복을 제거한다.

```text
현재 장착 무기
  = inventory_rows[entity_id].equipped_item("MAIN_HAND")
  → ItemDefinition.weapon_id
```

runtime 상태는 다음처럼 나눈다.

- 화살·볼트 보유량: `ammo_pool_rows[entity_id]`
- 석궁 장전 등 무기에 붙어 이동해야 하는 상태:
  `weapon_runtime_rows[item_instance_id]`

장전된 석궁을 바닥에 버리거나 시체에서 루팅해도 같은 무기 instance의 장전 상태가
보존되어야 한다. `reload_required=true`인 무기 instance는 장전 여부와 무관하게 runtime
row를 정확히 하나 가지며, 그 외 무기는 runtime row를 가지지 않는다. 해당 무기가
제거될 때만 runtime row를 함께 제거한다.

## 5. A — 엔티티 단위 인벤토리 기반

### 5.1 엔티티 생성과 제거

`SimWorldState.add_entity()` 성공은 다음 상태를 전부 생성하거나 전부 실패해야 한다.

```text
entities[id]
combatant_states[id]
item_state.inventory_rows[id]
item_state.ammo_pool_rows[id]
```

기본 인벤토리는 빈 12칸이고 ammo pool은 0이다. `add_lab_actor()`도 `add_entity()`를
통과하므로 duel lab 액터가 자동으로 같은 인벤토리 계약을 얻는다. A에서는 lab UI나
장비 fixture를 추가하지 않는다.

엔티티 hard-delete는 다음 중 하나가 먼저 완료된 경우에만 허용한다.

1. 인벤토리와 runtime row가 비어 있다.
2. 명시적인 despawn transaction이 모든 아이템을 바닥 또는 다른 소유자에게 옮겼다.

DEAD 전환은 hard-delete가 아니다. 시체 루팅을 위해 엔티티와 인벤토리를 유지한다.

### 5.2 bootstrap

- 주인공의 현재 시작 가방·장착품·탄약·바닥 아이템을 같은 instance ID와 수량으로
  `world.item_state`에 생성한다.
- 동료·적·중립 NPC는 A에서는 빈 인벤토리로 생성한다.
- A 전후 동일 seed의 첫 전투 snapshot 의미, 주인공 공격 결과, UI 표시 아이템과 수량이
  같아야 한다.
- 자율 원정 실험기의 로컬 `inventory`/`ground`는 즉시 억지로 월드에 합치지 않는다.
  먼저 공용 API로 교체한 뒤 해당 실험기의 simulator world가 `WorldItemState`를 소유하게
  하는 별도 작은 커밋으로 제거한다. 최종 A 완료 시 별도 authority가 남아서는 안 된다.

### 5.3 조회 API

게임플레이와 UI가 Dictionary를 직접 잡지 않도록 `SimWorldState` 또는 전용 facade에 다음
읽기 API를 둔다.

```gdscript
func inventory_of(entity_id: int) -> InventoryState
func equipped_item(entity_id: int, slot: String) -> ItemInstance
func equipment_modifiers(entity_id: int) -> Dictionary
func ground_item(instance_id: String) -> ItemInstance
func item_owner(instance_id: String) -> Dictionary
```

반환 DTO와 상태 객체는 외부 변조가 canonical 상태에 침투하지 않도록 clone 또는 detached
DTO로 반환한다. 전투 kernel 내부의 읽기 전용 fast path가 필요하면 private reference API로
분리한다.

### 5.4 단일 transaction API

기존 `ItemInventoryOperations`의 pure clone-and-return 의미를 보존하되 entity ID와 전체
`WorldItemState`를 받는 상위 operation 계층을 추가한다.

```gdscript
preview_pickup(entity_id, instance_id, position)
commit_pickup(entity_id, instance_id, position)
preview_drop(entity_id, instance_id, position)
commit_drop(entity_id, instance_id, position)
preview_equip(entity_id, instance_id, slot)
commit_equip(entity_id, instance_id, slot)
preview_unequip(entity_id, slot)
commit_unequip(entity_id, slot)
preview_transfer(from_entity_id, to_entity_id, instance_id)
commit_transfer(from_entity_id, to_entity_id, instance_id)
preview_use(entity_id, instance_id)
commit_use(entity_id, instance_id)
```

각 commit 순서는 고정한다.

```text
입력 검증
→ WorldItemState clone
→ clone만 변경
→ 전역 item invariant 검증
→ revision 정확히 +1
→ event 작성
→ world에 atomic 교체
```

실패 시 원본 상태를 되돌리는 것이 아니라 애초에 원본을 변경하지 않는다. 시간 진행이나
combat 효과를 포함하는 session 명령은 기존처럼 전체 rollback memento 경계 안에서 이
item commit을 호출한다.

### 5.5 기존 facade 호환

주인공 UI의 public API 이름은 A에서 유지해 회귀 범위를 줄인다.

```gdscript
protagonist_inventory()
pickup_ground_item(instance_id)
equip_inventory_item(instance_id, slot)
unequip_inventory_slot(slot)
drop_inventory_item(instance_id)
discard_inventory_item(instance_id)
use_inventory_item(instance_id)
```

내부에서 `party_encounter.protagonist_id`를 구한 뒤 범용 transaction에 전달한다. UI가
`party_encounter.protagonist_inventory`나 `ground_items`를 직접 읽는 경로는 제거한다.

### 5.6 wire와 HARD_CUT

- `SimWorldState.SNAPSHOT_VERSION`을 7로 올린다.
- v7 top-level exact key에 `item_state`를 추가한다.
- `PartyEncounterState`의 다음 필드를 제거하고 nested schema를 올린다.
  - `protagonist_inventory`
  - `ground_items`
  - `protagonist_loadout`
- 기존 월드 snapshot v6은 객체 생성 전에 `unsupported_snapshot_version`으로 거부한다.
- v6 내부의 party v1~v11 migration fixture를 v7 복원 계약으로 가장하지 않는다. 필요한
  범위는 상태 단위 migration test와 명시적으로 분리한다.
- rollback memento에도 `item_state`를 포함한다. accepted operation과 rejected operation의
  atomicity test가 save snapshot뿐 아니라 memento 경로도 검증해야 한다.

## 6. C — 사망, 시체 루팅, 종족 드롭

### 6.1 시체 인벤토리

`CombatantState.life_state == "DEAD"`인 엔티티의 기존 `inventory_rows[entity_id]`를 시체
인벤토리로 취급한다. 별도 복제본을 만들지 않는다.

- 생전 장착품은 같은 instance ID와 affix, rarity, quantity를 유지한다.
- 죽는 순간 장착 슬롯을 강제로 비우지 않는다.
- 시체에서는 장착 효과를 계산하지 않는다.
- 시체 아이템을 루팅할 때 source 장착 슬롯을 transaction 안에서 먼저 해제하고
  destination 가방으로 옮긴다.
- destination 가방이 가득 차면 source 슬롯과 양쪽 인벤토리가 모두 무변경이어야 한다.

### 6.2 생전 소지품·시작 장비 생성

C에서 실제 플레이 중 장착 장비를 루팅할 수 있으려면 몬스터가 사망 전에 해당 item
instance를 소유해야 한다. 이를 종족 드롭과 섞지 않고 별도의 시작 loadout 콘텐츠로 둔다.

```text
data/content/actor_loadouts.json
sim/actor_loadout_registry.gd
```

spawn/scenario row가 `loadout_id`를 선택하고, registry가 엔티티 생성 직후 고정 item 목록과
장착 슬롯을 그 엔티티 인벤토리에 넣는다. 예시는 다음과 같다.

```json
{
  "loadout_id": "GOBLIN_MELEE_V1",
  "items": [
    {
      "entry_id": "MAIN_WEAPON",
      "definition_id": "WEAPON_SHORT_SWORD",
      "quantity": 1,
      "equip_slot": "MAIN_HAND"
    },
    {
      "entry_id": "BODY_ARMOR",
      "definition_id": "ARMOR_LEATHER",
      "quantity": 1,
      "equip_slot": "BODY"
    }
  ]
}
```

- instance는 이 시점에 월드 allocator로 실제 생성한다.
- loadout row와 item row는 ID 순으로 정렬·유일해야 한다.
- `equip_slot`이 비어 있으면 가방 소지품이고, 값이 있으면 정의상 허용되는 슬롯이어야 한다.
- 같은 슬롯에 두 item을 배치하거나 12칸을 넘는 loadout을 거부한다.
- C에서는 이 장비가 소유·장착·루팅되지만 적 전투 수치에는 영향을 주지 않는다.
- B는 이미 존재하는 이 장비를 전투 판정에서 읽기 시작하는 단계다.

초기 C 수직 슬라이스에는 최소 한 종류의 고블린 loadout을 넣어, 실제 게임 경로에서
장착 무기와 방어구를 시체로부터 루팅할 수 있어야 한다. 장비 선택 확률·희귀도·AI 교체는
후속 콘텐츠 작업으로 남긴다.

### 6.3 종족 드롭 테이블

수정 가능한 JSON 콘텐츠로 둔다.

```text
data/content/species_drop_tables.json
sim/species_drop_registry.gd
```

문서 exact top-level shape:

```json
{
  "content_schema_version": 1,
  "content_version": "2026-09-01",
  "content_type": "SPECIES_DROP_TABLES",
  "ruleset_id": "species-drops-v1",
  "tables": [
    {
      "species_id": "goblin",
      "rolls": [
        {
          "roll_id": "GOBLIN_EAR",
          "definition_id": "GOBLIN_EAR",
          "chance_per_1000": 700,
          "min_quantity": 1,
          "max_quantity": 2
        }
      ]
    }
  ]
}
```

검증 조건:

- `species_id`와 `roll_id`는 각각 문서 전체에서 정렬·유일하다.
- `definition_id`는 `ItemRegistry`에 존재한다.
- 확률은 `0..1000`, 수량은 `1..stack_limit` 범위다.
- 한 종족당 roll row는 최대 16개다.
- 테이블이 없는 종족은 종족 전용 추가 드롭 0개이며 오류가 아니다.
- 장비와 생전 소지품을 종족 드롭 테이블에 넣지 않는다.

초기 `GOBLIN_EAR`처럼 아직 없는 종족 재료는 먼저 `data/content/items.json`에 정상
`MATERIAL` 정의로 추가한 뒤 drop table에서 참조한다. placeholder인
`MATERIAL_UNSPECIFIED`를 실제 종족 드롭으로 사용하지 않는다.

### 6.4 결정론적 드롭 판정

드롭 내용은 다음 key로 각 roll을 독립 판정한다.

```text
world_seed
+ death_event_id
+ dead_entity.species_id
+ species-drop ruleset_id
+ roll_id
```

기존 keyed hash utility를 사용하며 전역 RNG state를 소비하지 않는다. 수량 판정도 같은
key에 별도 channel을 붙인다. 반복 순서가 결과를 바꾸지 않도록 table을 `roll_id` 순으로
평가한다.

생성 instance ID는 충돌 없는 월드 allocator를 사용한다.

```text
ITEM_%020d
```

allocator 증가와 아이템 삽입, processed death ID 기록은 한 transaction이다. 중간 실패 시
전부 되돌린다.

### 6.5 사망 event 연결과 중복 방지

모든 사망 원인—직접 공격, DOWNED 이후 출혈, 상태 피해, 환경 피해, finisher—은 최종
`entity.died` event를 공통 입력으로 사용한다. 공격 함수에서 HP를 보고 별도로 드롭을
생성하지 않는다.

```text
entity.died
→ 아직 처리하지 않은 death event인지 확인
→ 종족 drop roll 계산
→ 시체 inventory에 item 추가
→ corpse.loot_materialized event emit
→ processed_drop_death_event_ids에 source death event ID 기록
```

`corpse.loot_materialized`의 `cause_id`는 source `entity.died.id`, `actor_id`와 `target_id`는
죽은 entity ID로 고정한다. data에는 ruleset ID와 생성된 instance ID/definition ID/quantity
목록을 정렬해 기록한다. 드롭이 0개여도 processed ID와 0개 결과 event를 남겨 replay가
“미처리”와 “빈 결과”를 구분하게 한다.

시체 인벤토리의 12칸이 이미 가득 차 드롭 row를 추가할 수 없다면 해당 드롭을 같은
transaction에서 시체 위치의 `ground_items`로 보낸다. 아이템을 삭제하거나 기존 소지품을
밀어내지 않는다. 여러 바닥 아이템이 같은 좌표에 있는 것은 허용하며 instance ID로
구분한다.

### 6.6 시체 루팅 명령

core/facade는 다음 명령을 제공한다.

```gdscript
preview_loot_corpse(looter_id, corpse_id, instance_id)
commit_loot_corpse(looter_id, corpse_id, instance_id)
```

허용 조건:

- looter와 corpse가 모두 존재하고 서로 다른 entity다.
- looter는 `ACTIVE`, corpse는 `DEAD`다.
- 두 위치의 Chebyshev distance가 1 이하다.
- instance는 corpse inventory에 존재한다.
- looter 가방에 전체 수량을 받을 수 있다.
- 해당 action을 실행할 권한과 시간 비용은 session/coordinator가 검증한다.

루팅 성공 시 source의 장착 슬롯을 자동으로 비우고 동일 instance를 destination으로
옮긴다. 자동 장착은 하지 않는다. C에서는 한 번에 한 item row만 옮기며 `loot all`은 UI
편의 기능으로 미리 추가하지 않는다.

### 6.7 시체 정리

다음 조건이 모두 충족되기 전에는 corpse entity를 제거하지 않는다.

- 시체 인벤토리가 비었다.
- 해당 사망 event의 종족 드롭 처리가 완료됐다.
- 같은 위치에 시체가 소유한 runtime row가 없다.
- 시체를 참조하는 필수 opening/quest/event 상태가 없다.

C에서는 자동 시체 소멸 시간을 만들지 않는다. 정리가 필요하면 명시적인 cleanup 정책을
별도 작업으로 설계한다.

## 7. B — 적 장비의 전투 반영

B 전에도 적은 인벤토리에 장비를 소유·장착할 수 있고, 죽으면 그 장비를 루팅할 수 있다.
다만 A와 C에서는 적 장비 수치를 전투 계산에 넣지 않는다.

B에서 다음을 수행한다.

- 모든 공격자의 무기를 `world.equipped_item(actor_id, "MAIN_HAND")`로 조회한다.
- 모든 방어자의 방어구·방패 modifier를 `world.equipment_modifiers(target_id)`로 동결한다.
- 공격 preview 시 장비 source와 total을 frozen combat assessment에 포함한다.
- commit 중 mutable inventory를 다시 읽지 않는다.
- 적 장비가 강하면 상쇄 보정 없이 실제로 강해진다.
- 플레이어만 장비 효과를 받는 기존 protagonist special case를 제거한다.

B에서는 C의 시작 loadout을 그대로 사용한다. 적의 능동적인 장비 선택·교체 AI는 별도
후속 작업으로 두며, 종족 드롭 테이블에 무기를 넣어 장비 시스템을 우회하지 않는다.

## 8. D — 동료 인벤토리 UI

D는 canonical 상태를 새로 만들지 않는다. A/C의 조회·transaction facade만 사용한다.

- 파티 상태창에서 캐릭터를 선택해 해당 `entity_id` 인벤토리를 표시한다.
- 동료와 인접한 경우 주인공 ↔ 동료 transfer를 제공한다.
- 장착/해제 버튼은 선택한 아이템 바로 옆에 표시한다.
- 시체 선택 시 동일 패널 형태로 corpse inventory를 표시하되 장착 버튼 대신 루팅 버튼을
  표시한다.
- UI가 `WorldItemState` 내부 Dictionary를 직접 수정하지 않는다.

## 9. 전역 불변식

`WorldItemState.validation_error(world)`는 최소한 다음을 검증한다.

1. `inventory_rows` key 집합이 `combatant_states` key 집합과 정확히 같다.
2. `ammo_pool_rows` key 집합도 `combatant_states` key 집합과 정확히 같다.
3. 모든 row는 key 오름차순으로 직렬화되고 중복 key가 없다.
4. 모든 item instance ID는 모든 인벤토리와 바닥을 합쳐 월드 전체에서 유일하다.
5. 장착 instance는 같은 inventory ownership table에 존재한다.
6. 같은 instance가 두 장착 슬롯에 동시에 연결되지 않는다.
7. 슬롯 종류, 양손 무기와 보조 손 충돌, 12칸 용량 규칙이 유효하다.
8. `weapon_runtime_rows`는 존재하는 WEAPON instance만 참조한다.
9. `reload_required=true`인 모든 무기는 runtime row를 정확히 하나 가지며, 그 외 무기는
   runtime row를 가지지 않는다. 장전 상태도 무기 정의의 ammo/reload 규칙과 일치한다.
10. ground position은 bounds 안이며 canonical 정렬이다.
11. processed death ID는 실제 `entity.died` event이고 중복·역순이 없다.
12. `next_item_instance_id`는 이미 할당된 runtime ID보다 크다.
13. accepted transaction은 revision을 정확히 1 올린다.
14. rejected preview/commit은 revision을 포함한 전체 상태를 바꾸지 않는다.

`PartyEncounterState`와 `WorldState`가 같은 item invariant를 각각 복제하지 않는다.
`WorldState.world_state_error()`는 `item_state.validation_error(self)`의 결과를 한 번 연결한다.

## 10. 파일별 작업 경계

| 파일 | 책임 |
|---|---|
| `sim/inventory_state.gd` | 범용 12칸 인벤토리·장착 authority |
| `sim/world_item_state.gd` | 모든 inventory, ammo, weapon runtime, ground, revision 소유 |
| `sim/ammo_pool_state.gd` | entity별 화살·볼트 수량 |
| `sim/weapon_runtime_state.gd` | weapon instance별 장전 상태 |
| `sim/item_inventory_operations.gd` | 단일 inventory 내부 pure operation 유지·일반화 |
| `sim/world_item_operations.gd` | entity/ground/corpse 간 pure transaction |
| `sim/actor_loadout_registry.gd` | 생전 시작 소지품·장비 콘텐츠 검증·지급 |
| `sim/species_drop_registry.gd` | JSON drop table 검증·결정론적 roll |
| `sim/systems/corpse_loot_system.gd` | death event 소비, drop 생성, loot commit |
| `sim/world_state.gd` | item_state 소유·wire·memento·entity lifecycle·전역 검증 |
| `sim/party_encounter_state.gd` | 주인공 item/loadout/ground 권위 제거 |
| `sim/systems/melee_combat_system.gd` | B에서 entity별 장비 modifier 소비 |
| `playtest/party_playtest_session.gd` | 기존 주인공 facade 유지, corpse loot facade 추가 |
| `sim/npc_expedition/npc_expedition_simulator.gd` | 로컬 inventory/ground authority 제거 |
| `data/content/actor_loadouts.json` | 적·NPC의 생전 시작 소지품·장착품 |
| `data/content/species_drop_tables.json` | 종족별 추가 드롭 콘텐츠 |
| `data/content/items.json` | 종족 드롭으로 참조할 실제 MATERIAL 정의 추가 |

## 11. 구현 커밋 순서

한 번에 전체를 바꾸지 말고 다음 순서로 각 커밋을 green 상태로 유지한다.

### A1 — 범용 상태와 검증기

- `InventoryState`, ammo/runtime state, `WorldItemState` 추가
- wire round-trip과 malformed fixture test
- 아직 gameplay 호출부를 전환하지 않음

### A2 — 월드 생명주기와 snapshot v7

- `WorldState`에 item_state 연결
- add_entity/restore/memento/global validation 연결
- 주인공 초기 inventory/ground/loadout 이전
- PartyEncounterState 중복 필드 제거

### A3 — 범용 operation과 기존 facade 전환

- 주인공 pickup/equip/unequip/drop/use를 entity ID operation으로 교체
- 전투의 주인공 무기 조회를 inventory authority로 교체
- 기존 UI·save/replay·journal 회귀 테스트 복구

### A4 — 자율 NPC authority 통합

- `NpcExpeditionSimulator.inventory/ground` 제거
- simulator world의 item_state와 같은 operation 사용
- 동일 seed trace와 save/restore 결정성 검증

### C1 — 드롭 registry와 death materialization

- 시작 loadout JSON/registry와 최소 고블린 장비 fixture 추가
- 종족 드롭 JSON/registry와 keyed roll 추가
- 모든 death 경로에서 한 번만 materialize
- capacity overflow의 ground fallback 추가

### C2 — 시체 루팅 facade

- preview/commit loot 추가
- equipped source 자동 해제와 원자적 transfer
- corpse lifecycle/cleanup gate 추가

### B와 D

- A/C acceptance가 green인 별도 커밋 이후 진행

## 12. 필수 테스트

### A core

1. 모든 `add_entity()`가 빈 12칸 inventory와 ammo row를 만든다.
2. entity 생성 중 item row 생성 실패는 부분 상태를 남기지 않는다.
3. 모든 inventory와 ground를 합친 instance ID 중복을 거부한다.
4. inventory/ground/weapon runtime의 wire round-trip이 exact하다.
5. malformed·unsorted·extra-key·missing-row wire를 거부한다.
6. snapshot v7 save→restore가 exact하고 v6은 header에서 거부된다.
7. rollback memento가 item_state와 revision을 exact 복원한다.
8. 기존 주인공 시작 아이템·수량·장착 슬롯·탄약이 동일하다.
9. 기존 pickup/equip/unequip/drop/use journal replay 결과가 동일하다.
10. 장전된 석궁을 이동해도 같은 instance의 장전 상태가 유지된다.
11. duel lab 액터도 빈 inventory를 갖지만 lab 행동 trace는 동일하다.
12. 자율 NPC 실험기에 별도 inventory authority가 남지 않는다.

### C death/drop

1. 고블린 fixture가 생전부터 실제 무기·방어구 instance를 소유하고 지정 슬롯에 장착한다.
2. 공격 직후 사망과 DOWNED→DEAD 지연 사망 모두 같은 death hook을 탄다.
3. 출혈·환경 피해 사망도 종족 드롭을 생성한다.
4. 같은 death event를 두 번 처리해도 아이템과 event가 추가되지 않는다.
5. 같은 seed/snapshot/event ID는 항상 같은 드롭과 수량을 만든다.
6. drop 판정 전후 전역 RNG state가 동일하다.
7. drop table이 없는 종족은 0개 materialized event를 한 번 남긴다.
8. 죽은 적의 소지품·장착품 instance ID와 affix가 그대로 보존된다.
9. 시체 가방이 가득 찼으면 추가 드롭이 같은 위치 ground로 빠지고 사라지지 않는다.
10. 여러 몬스터가 같은 칸 근처에서 죽어도 instance ID 충돌이 없다.

### C loot

1. 인접한 ACTIVE looter만 DEAD corpse를 루팅할 수 있다.
2. 장착 중이던 source item을 루팅하면 source slot이 자동으로 비워진다.
3. destination에는 동일 instance가 들어가며 자동 장착되지 않는다.
4. 가방이 가득 찬 실패는 source/destination/revision/event를 바꾸지 않는다.
5. 같은 item을 두 번 루팅할 수 없다.
6. 살아 있는 대상, 멀리 있는 시체, 없는 item, 변조된 entity ID를 거부한다.
7. 마지막 전리품 전에는 corpse cleanup이 거부된다.
8. loot 포함 journal replay와 save/load final snapshot이 exact하다.

### B 회귀

1. 동일 장비를 든 주인공·동료·적의 frozen modifier가 동일하다.
2. 무장한 적은 무장하지 않은 동일 profile 적보다 상쇄 없이 강하다.
3. preview 뒤 장비를 바꾼 stale commit을 거부한다.
4. 적 장비가 없는 기존 fixture의 전투 결과는 B 이전 baseline과 같다.

## 13. 완료 기준

### A 완료

- 모든 combatant가 동일한 inventory 계약을 가진다.
- canonical inventory/ground authority가 `WorldItemState` 하나뿐이다.
- 주인공의 기존 아이템 UI·행동·전투 결과가 바뀌지 않는다.
- `equipped_weapon_id` 중복 권위와 bridge invariant가 제거된다.
- snapshot/replay/rollback과 전체 기존 테스트가 green이다.

### C 완료

- 어떤 경로로 죽어도 종족 드롭이 정확히 한 번 생성된다.
- 몬스터의 생전 소지품과 착용 장비를 동일 instance로 루팅할 수 있다.
- 가방 부족이나 반복 처리로 아이템이 사라지거나 복제되지 않는다.
- 같은 seed와 journal이 같은 corpse inventory와 final snapshot을 만든다.

### 최종 B/D 완료

- 적 장비가 실제 전투 수치에 반영된다.
- 주인공·동료·시체 UI가 동일한 범용 facade를 사용한다.
- 캐릭터 종류에 따라 별도 인벤토리 구현이나 직접 상태 수정 경로가 남지 않는다.
