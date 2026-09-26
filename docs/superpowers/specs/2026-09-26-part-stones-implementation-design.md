# ④ 부위 영혼석 구현

작성일: 2026-09-26 · 상태: **②·④-a 완료 — 기존 30종 90부위, ④-b 새 8종은 후속**
근거: [공격 형태·부위 영혼석](2026-09-26-damage-forms-part-stones-design.md)(① 방향, 부위 판정) · [② 발동 엔진](2026-09-26-trigger-engine-design.md) · [③ 빌드군과 부위 효과](2026-09-26-build-families-part-effects-design.md)(효과 114개, 새 종족 8개)
전제: ①(`Forms`, `enemy.part_kind`)과 ②(`stone_effects.json`, `EffectEngine`)가 먼저 끝나 있다.
기존 코드: `expedition/progression/essences.gd`, `data/content/essences.json`, `expedition/items/gear.gd`(`roll_part`), `expedition/items/abilities.gd`, `expedition/actors/npc_essences.gd`, `expedition/ui/screens/essence_tab.gd`, `popups.gd`, `data/content/floor_monsters.json`, `expedition/legacy/dcss_enemy_registry.gd`, `assets/monsters-v1/png/<종족>_<방향>.png`

## 0. 결정

1. **영혼석 id = `<종족 영혼석 id>/<부위>`.** 예: `RAT_GNAW/cut`, `RAT_GNAW/broken`, `RAT_GNAW/pierced`. 속성 변종은 뒤에 `@<속성>`: `SPIDER_WEB/pierced@poison`.
2. **맨 id(`RAT_GNAW`)는 그 종족의 대표 부위(★)를 뜻하는 별칭**으로 남긴다. 들어오는 모든 id는 `Essences.canonical(id)`로 정규형(`BASE/part[@elem]`)으로 바꿔 저장한다. 공개 조회 API에서만 별칭을 허용한다. `parts_bag`, `essences`, `drops`를 직접 읽는 호출부와 테스트는 정규 키로 함께 옮기며, 별칭을 저장 키로 중복 보관하지 않는다.
3. **세 부위는 역할(기본 스탯), 액티브(파츠), 주문 학파를 같은 종족에서 물려받는다.** 다른 것은 대표 효과뿐이다. 같은 종족의 두 부위를 끼우면 액티브·주문은 한 번만 들어간다(규칙·주문 목록 중복 제거).
4. **역할 조합·속성 세트는 부위마다 센다.** 같은 종족 부위 셋을 끼우면 그 역할 3개로 센다(빌드를 한 종족으로 모으는 길을 막지 않는다).
5. **몬스터는 대표 부위(★) 효과 하나만 가진다.** 몬스터 개성은 지금과 같게 유지된다.
6. **드롭**: 떨어지는지는 지금 규칙(그 종족 첫 처치 100%, 이후 25%), 어느 부위인지는 ①의 `enemy.part_kind`. 결과 id = `BASE/<part_kind>` + 변종 속성.
7. **보스 영혼석 셋은 부위가 없다.** `GOBLIN_CHIEF` 등은 지금 id 그대로(정규형도 맨 id).
8. **두 단계로 나눠 구현한다.** ④-a 기존 30종의 부위 90개(새 효과 60개), ④-b 새 종족 8개와 효과 24개. ④-a만으로도 게임이 완결된다.

## 1. 데이터

### 1.1 `data/content/essences.json`

종족 행에 `parts`와 `headline`을 더한다. `effect`(기존 대표 효과 id)는 지운다(대표 부위의 `effect`가 대신한다).

```json
"RAT_GNAW": {
  "role": "PACK", "element": "", "school": "", "species": "dcss_rat", "family": "rat",
  "headline": "cut",
  "parts": {
    "cut":     {"name": "쥐 꼬리", "effect": "RAT_GNAW"},
    "broken":  {"name": "쥐 앞니", "effect": "RAT_INCISOR"},
    "pierced": {"name": "쥐 심장", "effect": "RAT_HEART"}
  }
}
```

- 부위 이름·효과는 ③ §3 표 그대로.
- 보스 행에는 `parts`가 없다.
- 효과 정의(문구, 키워드, 규칙)는 ②의 `data/content/stone_effects.json`에 효과 id로 있다.

### 1.2 새 종족(④-b)

| 파일 | 추가 |
| --- | --- |
| `data/content/floor_monsters.json` | 8행: `zone`, `min_depth`/`max_depth`(구역 범위), `rarity`(구역 평균 600~700), `curve`, `threat`, `roles`, `role`, `family`, `variants`(구역 속성), `form`/`skin`/`bone`(③ §2), `beast` |
| `data/content/essences.json` | 8행(③ §2의 영혼석 id: `HOUND`, `SHROOM`, `SALAMANDER`, `GHOST`, `ACOLYTE`, `MIMIC`, `WEAVER`, `ZOMBIE`) |
| `data/content/stone_effects.json` | 효과 24개 |
| `expedition/items/abilities.gd` | 액티브 8개(③ §2 초안) — 몬스터 예고 규칙(`enemy.prep`)은 기존 종족 파츠와 같게 |
| `expedition/legacy/dcss_enemy_registry.gd` | 8종 프로필(체력·속도 등, 같은 구역 같은 역할 종족을 본뜸) |
| `expedition/progression/bestiary.gd` | 표에 8종(`role`, `zone`) — `ROLE_*` 수치는 그대로 |
| `assets/monsters-v1/png/<id>_{north,south,east,west}.png` | 종족마다 4방향, 모두 32장. 새 그림은 사용자 검토 후 적용한다. 승인 전에는 기존 그림을 쓰는 임시 대체 표로 실행을 유지한다(`mobile_art.gd`의 몬스터 텍스처 조회에 대체 표) |
| `data/content/species_catalog.json` 등 종족 목록을 읽는 곳 | 목록 검사 테스트가 가리키는 곳을 따라 추가 |

## 2. 코드

### 2.1 `expedition/progression/essences.gd`

| 함수 | 바뀌는 것 |
| --- | --- |
| `canonical(id) -> String` (새) | 맨 id → `BASE/<headline>`, 변종 보존. 보스·주문 전용 행은 맨 id 그대로. 잘못된 부위 → `""` |
| `base_of(id)` | `/`와 `@` 앞부분(종족 영혼석 id) |
| `part_of(id) -> String` (새) | `cut`/`broken`/`pierced` 또는 `""` |
| `variant_element(id)` | `@` 뒤(지금과 같음) |
| `has(id)` | 정규형으로 바꾼 뒤 부위가 그 행의 `parts`에 있는지 |
| `row(id)` | 결과에 `part`, `part_name`, `effect`(그 부위의 효과 id) |
| `title(id)` | 부위 이름(`쥐 꼬리`), 변종이면 앞에 속성(`독 쥐 꼬리`) |
| `absorb`/`put`/`absorbed`/`equipped` | 들어오는 id를 `canonical`로. 같은 정규 id는 한 번만 흡수(지금 규칙 그대로) |
| `sync_spells` | 같은 학파 부위가 여럿이어도 주문은 한 번 |

### 2.2 `expedition/progression/stone_effects.gd`

- `effect_of(id)`: `row(id).effect`(부위의 효과).
- `effects(actor)`: 멤버는 끼운 부위의 효과들(중복 제거, 슬롯 순서). 몬스터는 `species_effect(species_id)` = 그 종족 `headline` 부위의 효과.

### 2.3 `expedition/items/abilities.gd`

- 영혼석 ID와 액티브 ID를 분리한다. 같은 종족 부위 둘은 하나의 액티브·재사용 대기를 공유하고, UI 선택·AI 규칙도 액티브 ID를 쓴다. 마지막 해당 부위가 빠질 때만 규칙을 지운다.
- 변종 부위가 섞이면 첫 봉인되지 않은 슬롯의 속성을 액티브에 쓴다(`BASE@element`). 재사용 대기 키는 종족 `BASE`로 공유한다. 같은 종족 부위의 주문 선택도 함께 바뀐다.


- 액티브 조회는 `Essences.base_of(id)`로. 규칙(`rules`) 추가는 같은 `base_of`가 이미 있으면 건너뛴다(`Essences.put`).
- `droppable()`은 그대로(종족 단위). 드롭 결과 id는 `gear.gd`가 만든다.

### 2.4 `expedition/items/gear.gd` — `roll_part`

- ①에서 기록만 하던 부분을 바꾼다: `id = "%s/%s" % [base, enemy.part_kind]` + 변종이면 `@속성`. 가방에 그 id를 넣는다.
- 메시지: `"%s 획득" % Essences.title(id)`. 부위가 형태와 맞게 나왔으면(`part_kind`가 마무리 형태의 부위) 별도 표시를 추가하지 않는다. 획득 로그는 `"쥐 꼬리 획득"`처럼 아이템 이름만 쓴다.

### 2.5 `expedition/actors/npc_essences.gd`

- `preference`: 역할 점수(지금) + **키워드 점수**. NPC 성격별 선호 키워드 표(예: 낮은 A → 출혈·광폭·분쇄, 높은 C → 수호·지원, 높은 O → 원소·저주·소환·사령). 효과 키워드는 `stone_effects.json`의 `keywords`.
- `continuing`: 역할·속성에 더해 **같은 빌드군 키워드**를 나누는 부위끼리 보너스(`SET_BONUS`와 같은 크기).
- `on_hunt`: NPC 사냥 드롭도 부위 판정(NPC 무기 형태로 마무리 형태).

### 2.6 화면

| 곳 | 표시 |
| --- | --- |
| 영혼석 탭 카드(`essence_tab.gd`) | 제목 = 부위 이름, 그 아래 효과 문구, 키워드 칩(빌드군 색), 역할·속성 태그(지금처럼). 같은 종족 다른 부위를 이미 가졌으면 "같은 종족 2/3" |
| 가방 목록 | 종족별로 묶고 부위 셋을 한 줄에(없는 부위는 빈 칸 + "베기로 마무리" 힌트) |
| 적 정보 창(`popups.gd`) | ①의 몸 한 줄 아래 "부위: 꼬리(베기) · 앞니(타격) · 심장(찌르기)", 이미 가진 부위는 표시 |
| 영혼석 세트 목록 | 역할 조합 개수(부위 단위), 빌드군 키워드별 개수(참고용, 효과 없음) |
| 아이콘 | 종족 영혼석 아이콘 + 부위 모서리 표식 3종(잘림/부서짐/꿰뚫림). 새 그림은 표식 3장만 |

## 3. 옮기기

- 기존 테스트 61곳 이상이 맨 id(`RAT_GNAW` 등)를 쓴다. 맨 id = 대표 부위 별칭이므로 API 조회 검사는 유지한다. 맨 id로 딕셔너리를 직접 읽는 검사는 정규 키로 수정해야 한다. 대표 부위가 기존 효과를 가지도록 ③ 표의 ★를 정했다(기존 종족은 전부 기존 효과 부위가 ★).
- `Essences.content.rows[id].effect`를 직접 읽는 곳은 `row(id).effect`로 바꾼다.
- `battle_stats.drops`, `parts_bag`, `essence_seen`의 키: `parts_bag`와 `drops`는 정규 id, `essence_seen`은 지금처럼 종족 단위(`kind_key`).
- 현재 런 파일 저장 기능은 없다. 딕셔너리 상태는 `Essences.normalize_run`으로 이식하며, 향후 파일 복원 직후에도 이 함수를 호출한다. 흡수는 한 번으로, 가방 수량은 합계로, 봉인·재사용 대기는 최댓값으로 합친다.

## 4. 몬스터

- 몬스터의 대표 효과 = 그 종족 ★ 부위 효과(기존 종족은 지금과 동일).
- 몬스터는 역할 조합·속성 세트를 쓰지 않는다(지금과 같음).
- 변종 몬스터(`@속성`)는 속성 태그와 저항만 더한다(지금과 같음).

## 5. 테스트

| 스위트 | 검사 |
| --- | --- |
| `tests/part_stones.gd` (새) | `canonical`(맨 id, 부위 id, 변종, 보스, 잘못된 부위), `title`, `row.effect`, 흡수·장착 정규화, 같은 종족 두 부위의 액티브·주문 중복 제거, 역할 조합이 부위 단위로 셈 |
| `tests/part_drops.gd` (①) | 드롭 결과 id가 `BASE/part_kind`, 변종 보존, 메시지 |
| `tests/part_effects.gd` (새) | ③의 효과 114개 각각: 발동 조건 한 번 참·한 번 거짓, 결과, 알림. 빌드군마다 §4 완성 빌드 하나를 끼운 전투 한 판이 오류 없이 끝남 |
| `tests/new_species.gd` (새, ④-b) | 8종이 구역 표에 나옴, 몸 단계·형태, 액티브 예고와 발동, 그림 조회(대체 표 포함) |
| `tests/npc_essences.gd` | 키워드 선호·빌드군 보너스 |
| `tests/essence_ui.gd`, `inspect_ui.gd` | 부위 카드, 가방 묶음, 적 정보 창 부위 줄 |
| 기존 | `stone_effects`, `essences`, `tag_sets`, `bestiary`, `encounter_builder`, `floor_generator` 등 그대로 통과. 종족 수 30 → 38을 세는 검사는 38로 |

## 6. 순서

| 단계 | 내용 |
| --- | --- |
| ④-a1 | 데이터 형식과 `Essences` 정규화(효과는 ★만, 나머지 부위는 빈 효과) → 기존 테스트 통과 |
| ④-a2 | 드롭이 부위 id를 줌, 영혼석 화면·적 정보 창 |
| ④-a3 | 기존 30종의 새 효과 60개(②의 데이터로) — 빌드군 묶음 단위로 나눠서(출혈·분쇄·급소 → 광폭·수호·사수 → 원소·저주·독 → 소환·사령·지원) |
| ④-a4 | NPC 선호, 역할 조합 재조정(③ §5) |
| ④-b | 새 종족 8개(데이터·액티브·그림·효과 24개) |

## 7. 검토할 결정

1. 맨 id를 대표 부위 별칭으로 두는 방식(대안: 모든 곳을 정규 id로 한 번에 바꾸기).
2. 같은 종족 부위 셋이 역할 조합에 3개로 세는 것(대안: 종족당 1개로만).
3. 새 종족 그림: 새로 그릴지, ④-b 첫 버전은 색만 바꾼 임시 그림으로 갈지.
4. 부위 드롭이 형태와 맞았을 때 메시지에 형태를 붙이는 연출.

## ④-a 후속 구현 확인

- 첫 처치 100%·이후 25% 판정을 유지하고, 마지막 공격 형태로 선택한 부위의 정규 ID를 실제 지급한다. 독립 NPC도 자기 사냥의 동일한 부위 선택을 읽는다.
- 기존 대표 효과 30개에 새 효과 60개를 더했다. 몬스터는 계속 대표 부위 효과 하나만 쓴다.
- 종족별 세 부위를 가방·흡수 UI에서 묶고 이름·보유 상태·효과·빌드군·형태 힌트를 표시한다. 몬스터 정보에도 부위 셋의 보유 여부가 나온다.
- 같은 종족을 모은 수는 정보 표시이며 별도 추가 보너스가 아니다. 역할 조합은 ③ §5 수치로 조정했다.
- NPC 선택은 기존 역할·성격 선호에 실제 효과의 빌드군 연속성을 더한다.
- 새 종족 8개·효과 24개·새 그림은 이 단계에 포함하지 않는다. 새 그림은 사용자 검토 후 적용한다.
