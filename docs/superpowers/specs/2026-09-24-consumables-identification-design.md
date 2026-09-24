# 물약·두루마리 소모품과 미감정 설계

작성일: 2026-09-24 · 상태: 구현됨 · 구현 계획: [소모품 구현 계획](../plans/2026-09-24-consumables-identification.md)
근거: [하강 Run 설계](2026-09-25-run-camp-npc-design.md) §2.3(물약·두루마리는 던전에서 줍는 소모품) · [층 생성기](2026-09-22-floor-generator-design.md) · `docs/inventory-ui.md`
참고 게임: Shattered Pixel Dungeon(SPD)의 물약·두루마리 구성과 미감정 규칙, DCSS의 외관 셔플.

## 0. 결정 사항

사용자와 합의한 결정. 나머지는 이 목록의 귀결이다.

1. **기존 소모품 5종은 새 카탈로그로 흡수한다.** `supplies` 배열·`SUPPLY_NAMES`·`grant_supply`·`use_supply`는 삭제한다. 치유 물약·정신 안정제는 카탈로그 항목이 되고, 활력 물약·화염 두루마리·물 두루마리는 사라진다(액체 화염·냉기 물약이 역할을 잇는다).
2. **감정 방법은 두 가지.** 사용하면 그 종류가 이번 Run 동안 감정된다. 감정 두루마리를 읽으면 가방의 미감정 종류 하나를 골라 감정한다. 야영 감정·개수 감정은 없다.
3. **드롭은 바닥 아이템.** 층 생성 시 방 바닥에 놓이고, 대원이 그 칸에 들어서면 자동으로 줍는다. 조사물의 기존 소모품 지급도 같은 풀에서 뽑는다. 몬스터 처치 드롭은 넣지 않는다(짐승 식량 드롭은 그대로).
4. **해로운 아이템을 넣는다.** 미감정 사용의 긴장감이 목적이다.
5. **규모는 물약 8 + 두루마리 8.** SPD 라인업에 가깝게 고르고, SPD의 Mind Vision 자리에 이 게임 고유의 스트레스 대응(정신 안정제)을 둔다.
6. **구현 접근은 JSON 카탈로그 + kind별 가방 + 바닥 아이템을 feature로.** 인스턴스 리스트나 배열 확장은 택하지 않는다.

## 1. 카탈로그 · `data/content/consumables.json`

각 항목: `id`, `class`(`potion`|`scroll`), `name`, `description`(감정 후 설명), `weight`(드롭 가중치), `area`(물약만, 투척 시 광역 효과 여부). 외관 풀은 같은 파일의 `appearances.potion`(색 10개)·`appearances.scroll`(무의미 제목 10개)에 둔다.

### 1.1 물약 8종

모두 **마신다**(대상: 조작 중인 대원 또는 동료). `area: true`인 3종은 **던진다**(사거리 4, 시선 필요, 대상 칸 중심 3×3)도 가능하다. `area: false`인 물약을 던지면 깨져서 낭비되고 감정되지 않는다(SPD와 같다). 마시거나 광역 투척은 감정된다.

| id | 이름 | 마시면 | 던지면 | weight |
|---|---|---|---|---|
| healing | 치유 물약 | HP +20, `bleed` 해제 | 낭비 | 15 |
| strength | 힘의 물약 | `str_bonus` +3 영구, 최대 HP +5(현재 HP도 +5) | 낭비 | 3 |
| haste | 가속 물약 | `haste` 300틱 | 낭비 | 5 |
| liquid_flame | 액체 화염 | 자기 발밑 3×3 목재 점화(fire +35) + 자신 `burn` 100틱 | 대상 3×3 목재 점화, 안의 모든 액터 `burn` 100틱 | 6 |
| frost | 냉기 물약 | 자신 `freeze` 100틱 | 대상 3×3 액터 `freeze` 100틱, 바닥 wet +70 | 5 |
| toxic_gas | 독가스 물약 | 자신 `poison` 300틱 | 대상 3×3 액터 `poison` 300틱 | 6 |
| experience | 경험의 물약 | 레벨 1 즉시 상승(`gain_level_xp`로 다음 레벨 경계까지 지급) | 낭비 | 3 |
| calm | 정신 안정제 | 스트레스 -25 | 낭비 | 8 |

- 마시기의 자기 대상 광역(액체 화염·냉기·독가스)은 마신 사람 위치를 중심으로 같은 3×3 규칙을 쓰되, 액체 화염만 마신 사람에게 `burn`을 추가로 남긴다.
- `str_bonus`는 액터 딕셔너리의 새 정수 필드(기본 0). `combat_stats.stats`가 `spec.str`을 읽는 세 곳(피해, 방어구 부담 완화)에서 `int(spec.str)+int(actor.get("str_bonus",0))`로 바꾼다.
- 체력 만땅·스트레스 0처럼 효과가 없을 때는 사용을 거부하고 소비하지 않는다(치유·정신 안정제·재충전). 나쁜 물약은 항상 마셔진다.

### 1.2 두루마리 8종

모두 **읽는다**(읽는 사람 = 조작 중인 대원). 대상 선택은 없고 즉시 발동한다.

| id | 이름 | 효과 | weight |
|---|---|---|---|
| identify | 감정 두루마리 | 가방의 미감정 종류 하나를 골라 감정. 미감정 상태로 읽으면 자기 자신이 먼저 감정된 뒤 고른다. 고를 것이 없으면 "감정할 것이 없다"만 남기고 소비된다 | 20 |
| upgrade | 강화 두루마리 | 읽는 사람이 장착 중인 무기·방어구 중 하나를 골라 `enchant` +1. 둘 다 없으면 거부, 소비하지 않음 | 4 |
| magic_mapping | 마법 지도 | 층의 벽이 아닌 모든 타일을 `explored`에 넣는다(`visible`은 그대로) | 6 |
| teleportation | 순간이동 | 읽는 사람이 현재 위치에서 맨해튼 거리 12 이상인 임의의 빈 바닥 칸으로 이동. 후보가 없으면 가장 먼 빈 칸 | 6 |
| mirror_image | 거울상 | 읽는 사람 인접 빈 칸에 아군 소환 `mirror` 2체(`Summons.summon`, 300틱). `combat.json.summons.mirror` 행 추가: 이름 "거울상", hp 12, power 6, speed 100, duration 300 | 5 |
| lullaby | 자장가 | 시야 안(`floor_state.visible`)의 몬스터 전부 `sleep_until = time+300`, `alert = false` | 5 |
| rage | 분노 | 층의 살아 있는 몬스터 전부 `alert = true` + `haste` 200틱 | 4 |
| recharging | 재충전 | 읽는 사람 MP를 최대치로. 이미 최대면 거부 | 5 |

- **잠(`sleep_until`)**: `monster_ai.turn`이 `s.time < sleep_until`이면 아무것도 하지 않고 돌아간다(순찰도 하지 않음). `session.damage`가 피해를 입힌 몬스터의 `sleep_until`을 0으로 지운다. 잠든 몬스터는 `alert`가 거짓이므로 기존 `stab` 2배 규칙이 그대로 적용된다.
- **선택 흐름**: 감정·강화는 `s.pending_choice = {"kind":"identify"|"upgrade","options":[...]}` 하나를 공유한다. 두루마리는 읽는 순간 소비되고 `pending_choice`가 세워진다. `s.resolve_choice(option)`이 효과를 적용하고 비운다. 선택 대기 중에는 `use_item`·`act`가 거부된다(테스트로 보장). UI는 `pending_choice`가 있으면 선택 팝업을 띄운다.

### 1.3 가중치와 드롭 풀

드롭 한 번은 `Hexaco.sample(seed, key, "item_kind", 가중치 합)`로 카탈로그 전체에서 가중치 비례로 뽑는다. 깊이별 풀 차이는 두지 않는다(이번 범위 밖).

## 2. 외관과 감정 · 세션 상태

`Session`의 새 필드:

| 필드 | 타입 | 뜻 |
|---|---|---|
| `bag` | `Dictionary` kind → int | 보유 개수. 0이면 키 없음 |
| `known` | `Dictionary` kind → true | 이번 Run에서 감정된 종류 |
| `appearances` | `Dictionary` kind → String | 이번 Run의 외관 라벨("붉은 물약", "'ZELGO MER' 두루마리") |
| `pending_choice` | `Dictionary` | §1.2 선택 흐름. 비어 있으면 없음 |

- `depart()`에서 `bag`·`known`을 비우고 `appearances`를 시드로 셔플한다. 셔플은 `Hexaco.sample(seed, i, "appearance_potion"/"appearance_scroll", n)`을 쓰는 Fisher–Yates로, 같은 시드는 같은 배정을 낸다.
- 라벨 규칙 `Consumables.label(s, kind)`: 감정 전 외관 라벨, 감정 후 이름. 설명 규칙: 감정 전 "정체 불명", 감정 후 카탈로그 `description`.
- 감정 메시지: "붉은 물약은 치유 물약이었다". 줍기 메시지: "붉은 물약 획득".
- 시뮬·픽스처용 `grant_item(kind, count, known)`: `known=true`면 감정 상태로 지급한다. 바닥·조사물 지급은 항상 미감정이다(이미 감정된 종류면 당연히 이름으로 보인다).

## 3. 모듈 · `expedition/items/consumables.gd`

정적 모듈. `Gear`가 파츠·장비를 맡듯 소모품 동사를 전부 맡는다.

| 함수 | 역할 |
|---|---|
| `content` | JSON 로드(정적) |
| `definition(kind)` / `kinds()` / `potions()` / `scrolls()` | 카탈로그 조회 |
| `shuffle_appearances(seed) -> Dictionary` | §2 셔플 |
| `label(s, kind)` / `description(s, kind)` | 표시 문자열 |
| `random_kind(seed, key) -> String` | 가중치 드롭 |
| `grant(s, kind, count=1, known=false)` | 가방에 넣고 메시지 |
| `pickup(s, actor)` | 액터 위치의 `item` feature를 줍고 feature 삭제 |
| `identify(s, kind)` | `known`에 기록, 메시지 |
| `use(s, kind, target=Vector2i(-1,-1), recipient=-1) -> bool` | 물약: `target`이 유효하면 던지기, 아니면 `recipient`(기본 조작 중 대원)가 마시기. 두루마리: 읽기. 성공 시 감정·소비·행동 시간 소모 |
| `resolve_choice(s, option) -> bool` | §1.2 선택 완료 |
| 효과 함수들 | kind별 `static func` 하나씩(`drink_healing`, `throw_liquid_flame`, `read_lullaby` …). `use`가 이름으로 `Callable`을 찾는다 |

행동 시간: 기존 `use_supply`와 같다 — 층 위에서는 수동 모드면 `ap = 1; Scheduler.advance(s, 100)`, 아니면 `finish_player_action()`. 야영 중에도 사용할 수 있다(스케줄러는 돌지 않음). `EXPLORE`·`BATTLE`·`CAMP` 외에는 거부.

`Session` 래퍼: `grant_item`, `use_item`, `identify_item`, `resolve_choice`, `item_label(kind)`. `gear.gd`에서 `grant_supply`·`use_supply`를 지운다.

## 4. 바닥 드롭

- `data/content/floor_themes.json`의 두 테마에 `"items": [4, 6]` 추가.
- `floor_generator.place_features`: 조사물 배치 뒤, `plain` 방(spine 포함) 중에서 문 인접이 아닌 빈 바닥 칸에 `{"kind":"item","item_id":<kind>,"label":<name>}`를 `rng.randi_range(items[0], items[1])`개 놓는다. kind는 생성기의 `rng`로 가중치 비례 선택(생성기는 `Hexaco`가 아니라 자기 `rng`를 쓴다). 같은 시드는 같은 배치.
- feature는 이동을 막지 않는다(`is_free`는 지형·액터만 본다).
- **줍기**: `session.act_as`의 `MOVE` 분기에서 `actor.pos = target` 직후, 액터가 파티원이면 `Consumables.pickup(s, actor)`. NPC·몬스터는 줍지 않는다. 자동탐험 경로도 같은 `MOVE`를 타므로 자동으로 줍는다.
- **표시**: `board.gd`의 feature 그리기가 `kind == "item"`이면 `Icons.paint(self, "potion"|"scroll", …)`을 쓴다. `map_icons.gd`에 두 아이콘 추가(물약: 병 실루엣, 두루마리: 말린 종이). 8비트 아트 경로(`FirstFloor.feature_id`)가 빈 문자열을 돌려주면 기존처럼 아이콘으로 떨어진다.
- `observe`의 `discoveries` 마커는 그대로("" 마커).
- **조사물**: `curios.gd`의 `grant_supply(random slot)` 두 곳을 `grant_item(random_kind(seed, key))`로 바꾼다. 확률(`supply_chance`, `item`)은 손대지 않는다.

## 5. UI

- **가방 팝업**(`popups.gd inventory_rows`): 소모품 행을 `bag`에서 만든다. `label = Consumables.label`, `description = Consumables.description`, 미감정이면 `label`에 " · 미감정"을 붙인다. 아이콘은 물약이면 `Art.ui_icon(6)`, 두루마리면 `Art.ui_icon(9)`. 행 필드: `kind`, `class`, `known`.
- **상세창**(`show_item_detail`): 물약은 대원별 "N 마신다" 버튼, `area` 물약이거나 미감정 물약이면 "던진다 · 바닥 선택" 버튼 추가(층 위에서만). 두루마리는 "읽는다" 버튼 하나. 상세창을 닫은 뒤 `ui.run_action`으로 `use_item`을 부른다.
- **던지기 흐름**: `main.gd`의 `pending_item: int`를 `pending_item: String`(kind, 빈 문자열이면 없음)으로 바꾼다. `floor_hud.choose_item(ui, kind)`가 공지 "N · 대상 칸 선택"을 띄우고, 탭 시 `use_item(kind, point)`.
- **선택 팝업**: `refresh` 시 `session.pending_choice`가 비어 있지 않으면 `Popups.show_choice(ui)`가 옵션 버튼 목록을 띄운다. 감정은 옵션이 미감정 kind(라벨은 외관), 강화는 `"weapon"`/`"armour"`(라벨은 장비 이름). 닫기 버튼 없음(선택은 필수).
- **오토배틀 HUD 소모품 바 제거**: `floor_hud.build`의 5칸 `shared` 행과 `ui.item_buttons`를 지운다. 가방 버튼은 이미 하단 행에 있다. `tests/mobile_hud.gd`의 "supplies live in the bag" 검사는 이미 이 상태를 요구한다.
- 야영 화면의 가방 버튼은 그대로.

## 6. 시뮬레이터·봇

- `expedition/sim/encounter_runner.gd`: `config.supplies`(길이 5 배열)는 실험 JSON과 문서 출력이 그대로 쓰므로 형식을 유지한다. 매핑은 **인덱스 0 → healing, 1 → calm, 2·3·4 → 무시**(활력·화염·물은 카탈로그에 없다). 지급은 `grant_item(kind, n, true)`(감정 상태).
- `expedition/sim/bot_policy.gd`: `s.supplies[0] > 0 and s.use_supply(0)` → `s.bag.get("healing",0) > 0 and s.use_item("healing")`.
- 아레나 화면(`arena_setup`)이 `supplies` 배열을 넘기면 같은 매핑을 탄다.

## 7. 테스트

새 `tests/consumables.gd`:

1. 카탈로그: 물약 8·두루마리 8, id 중복 없음, 외관 풀 각 10개, 가중치 양수, 효과 함수가 전부 존재.
2. 외관 셔플: 같은 시드는 같은 배정, 다른 시드는 어딘가 다름, 종류마다 서로 다른 외관.
3. 바닥 배치: 20개 시드에서 1층 `item` feature 수가 4~6, 문 인접 아님, 벽 아님.
4. 줍기: 아이템 칸으로 `MOVE`하면 `bag`에 1, feature 삭제, 메시지에 외관 라벨. 미감정 라벨이 가방 행에 " · 미감정"으로 표시.
5. 마시면 감정: 미감정 치유 물약을 마시면 HP 회복·`known`·"…이었다" 메시지. 체력 만땅이면 거부·미소비.
6. 감정 두루마리: 미감정 상태로 읽으면 자기 감정 후 `pending_choice`; `resolve_choice`로 다른 종류 감정; 대기 중 `act`·`use_item` 거부; 고를 것이 없으면 소비만.
7. 강화: 무기 `enchant` +1, 장비 없으면 거부.
8. 나쁜 물약: 독가스 마시면 `poison` 상태, 분노 두루마리는 모든 몬스터 `alert`.
9. 투척: 액체 화염을 목재 칸에 던지면 3×3 점화·안의 적 `burn`; 치유 물약을 던지면 소비되지만 감정되지 않음; 사거리 5 이상·벽은 거부.
10. 자장가: 시야 안 적이 `sleep_until` 동안 턴을 넘기고, 피해를 입으면 깬다.
11. 순간이동: 거리 12 이상 빈 칸, 마법 지도: `explored`가 바닥 타일 전부 포함.
12. 거울상: `npcs`에 아군 2체, 300틱 뒤 소멸.

기존 테스트 갱신: `mobile_actions`(supplies → bag/use_item), `run_start`("five empty supplies" → 빈 가방·외관 배정 존재), `solo_floor`(하강 시 가방 유지), `curios`(supplies 합 → bag 합), `arena_mode`, `abilities_growth`(가방 UI), `autobattle`, `encounter_sim`·`expedition_skills`·`action_economy`·`skill_value`·`stance_gate`·`party_guard_probe`·`ranged_probe`(config.supplies는 그대로 두되 runner 매핑에 맞춰 통과), `mobile_hud`(바 제거로 이미 통과), `continuous_floor`·`model_b_spells`·`parts`(`show_supplies` 호출 유지).

CI 목록(`.github/workflows/deploy-pages.yml`)에 `consumables` 추가.

## 8. 문서

- `README.md`: 소모품 문장을 "물약 8종·두루마리 8종이 미감정 상태로 바닥과 조사물에서 나오고, 사용하거나 감정 두루마리로 정체를 안다"로.
- `docs/systems-overview.ko.md` 53행: 소모품 항목 갱신, `items/consumables.gd` 파일 표에 추가.
- `docs/inventory-ui.md`: 소모품 행·상세창·던지기·선택 팝업 절 추가.

## 9. 범위 밖

깊이별 드롭 풀, 몬스터 처치 드롭, 가스 구름 지속, 투명·부양·정신 시야 물약, 저주·변환 두루마리, 야영 자동 감정, 앱 종료 후 저장.
