# 몬스터 시그니처 이능 · 파츠 시스템 설계

작성일: 2026-09-22 · 상태: 설계 확정 · 구현 계획: `docs/superpowers/plans/2026-09-22-monster-parts.md`
근거: [밸런스 방법론](../../balance-method.ko.md) · 선행: [스킬 효과 유형 4종](2026-09-22-skill-archetypes-design.md), [조우 시뮬레이터](2026-09-22-encounter-sim-design.md)

## 0. 결정 사항과 원칙

브레인스토밍에서 확정된 결정:

1. 종족마다 **시그니처 이능 하나**가 있고, 그것이 곧 그 종족의 공격 패턴이자 드롭이다.
2. 시그니처는 **패시브 + 액티브** 한 쌍이며, 드롭 아이템 하나("파츠")가 둘 다 담는다.
3. 1층 종족은 지금의 8종을 유지한다. 종족 수를 늘리지 않고 8종을 서로 다르게 만든다.
4. 파츠는 **아이템**이다: 파티 공용 가방에 들어가고, 복수 소지 가능, 영구 습득 없음, 장착·해제는 **마을에서만**. 원정 실패·포기 시 스냅샷 규칙으로 소실된다.
   **밀치기·엄호도 파츠다.** 타고난 행동은 공격·이동·대기뿐이고, 밀치기와 엄호는 시작 가방에 1개씩 들어 있으며 마을 상점에서 더 살 수 있다. 슬롯은 파츠를 끼우기 전까지 비어 있다.
5. 적의 액티브는 **준비 라운드(`prep`)** 뒤에 발동한다. 코드는 0~2를 지원하고, 1층 8종 데이터는 전부 1이다. 기본 공격은 예고가 없다.
6. 접근법 A: **카탈로그 공유**. `abilities.gd`의 정의 하나가 적의 공격이자 플레이어의 파츠다. 적도 `Abilities`의 실행기를 그대로 쓴다. 역할(MELEE/RANGED/CASTER)은 기본 공격 패턴으로 남기고, 시그니처는 그 위에 얹는다.

원칙: 스킬별·종족별 분기 코드 0줄 — 밀치기·엄호의 실행도 `session.act`의 분기가 아니라 카탈로그의 effect가 된다. 새 종족은 `DEFINITIONS` 한 항목과 `floor_monsters.json` 한 행으로 추가된다. 패시브는 닫힌 종류 목록과 훅 세 개로만 구현한다.

범위 밖: 영구 사망·정착지 시설(별도 계획), 2층 이상 종족 설계(강쥐는 데이터만), 파츠 그래픽, 파츠 판매·분해.

## 1. 데이터 모델

### 1.1 파츠 정의 (`expedition/abilities.gd` `DEFINITIONS`)

기존 필드(`name item description target range radius damage heal cooldown effect axis rule_when short shape self_hit icon`)에 다음을 더한다. `drop` 필드는 삭제한다.

| 필드 | 값 | 의미 |
| --- | --- | --- |
| `species` | 종족 id 또는 `""` | 이 파츠의 주인 종족. `""`이면 게임 내 드롭 없음(시험 스킬·구 이능) |
| `passive` | `{"kind": K, "value": int}` 또는 `{}` | 상시 효과. `K`는 §1.2의 닫힌 목록 |
| `enemy` | `{"prep": 0~2, "target": "NEAREST"}` | 적이 쓸 때의 준비 라운드와 대상 선택. `target`은 현재 `NEAREST`만 |
| `allies_hit` | bool | 범위 피해가 시전자 진영도 맞히는가. 기존 BOMB·SHOCKWAVE는 `true`(동작 유지), 신규 범위 파츠는 `false` |
| `tile_wet` | int (기본 0) | DAMAGE 실행 시 피격 칸의 `wet`을 이 값까지 올림. 강쥐 물세례용 |

- `droppable()`은 "species가 비어 있지 않은 id" 목록으로 바뀐다(정의 순서). 보스 시련의 드롭 순환은 이 목록을 그대로 쓴다.
- 기존 SHOCKWAVE·BOMB·IRON_HIDE는 `species ""`, `passive {}`로 남긴다(시험 로드아웃으로만 획득). 시험 스킬 4종도 같다.
- `effect`는 기존 `DAMAGE / SHIELD / HEAL / LUNGE`에 **`PUSH`·`GUARD`** 두 종류를 더한다. 밀치기와 엄호가 `DEFINITIONS`의 항목이 되기 때문이다(§1.6). `target`은 `ENEMY / SELF`에 **`ALLY`**(인접 아군)를 더한다.
- `Abilities.STARTERS`·`Rules.SKILLS` 상수와 `BASIC_BADGES`의 PUSH/GUARD 항목은 삭제한다. `BASIC_BADGES`에는 `ATTACK/MOVE/WAIT`만 남는다.
- `Abilities.species_part(species_id) -> String`: 그 종족의 파츠 id, 없으면 `""`. 정의 순서상 첫 일치.

### 1.2 패시브 종류 (닫힌 목록, `expedition/passives.gd`)

| kind | 훅 | 효과 |
| --- | --- | --- |
| `PACK` | outgoing | 공격자와 인접한 같은 진영 생존자 1명당 +`value` |
| `RETALIATE` | after_hit | 피해가 들어온 뒤, 인접한 공격자에게 `value` 피해를 되돌려줌(form `RETALIATE`, 되돌린 피해에는 패시브를 적용하지 않음) |
| `DIRTY` | outgoing | 대상 HP가 최대의 50% 미만이면 +`value` |
| `AMBUSHER` | outgoing | 대상이 같은 진영 생존자와 인접해 있지 않으면 +`value` |
| `THICK_HIDE` | incoming | 받는 피해 −`value`, 최소 1 |
| `BLOODLUST` | outgoing | 자신의 HP가 최대의 50% 미만이면 +`value` |
| `REGEN` | round_start | 라운드 시작마다 HP +`value` (최대 HP까지) |
| `AMPHIBIOUS` | outgoing | 자신이 선 칸이 `water`이거나 `wet > 0`이면 +`value` |

훅은 네 개뿐이다. 피해량을 바꾸는 둘은 순수 함수이고, 부작용은 `after_hit`·`round_start`에만 있다.

```gdscript
# expedition/passives.gd (static)
static func of(actor: Dictionary) -> Array        # 적용 중인 passive 딕셔너리 목록
static func outgoing(s, attacker: Dictionary, target: Dictionary, amount: int) -> int
static func incoming(s, target: Dictionary, amount: int) -> int
static func after_hit(s, target: Dictionary, attacker: Dictionary, form: String) -> void   # RETALIATE
static func round_start(s, actor: Dictionary) -> void
```

- `of(actor)`: 파티원은 `equipped_abilities`의 각 id가 `DEFINITIONS`에 있고 `passive`가 비어 있지 않으면 포함. 적은 `actor.part_id`의 passive.
- 훅 호출 지점은 `session.damage()` 한 곳(`outgoing`은 엄호 재지정 전에 공격자·의도 대상으로, `incoming`은 방어 감산 뒤 최종 수령자에게, `after_hit`은 HP 차감 뒤)과 `session.end_round()`의 라운드 시작 처리(생존 파티원 + 생존 적) 한 곳. 다른 곳에서 패시브를 읽지 않는다. `source`가 액터가 아니면(불·함정 999) outgoing·after_hit을 건너뛴다.
- `RETALIATE`는 `after_hit` 안에서 `s.damage(attacker, value, target.id, "RETALIATE")`를 호출한다. `damage()`는 form이 `RETALIATE`이면 outgoing·incoming·after_hit 훅을 모두 건너뛰므로 서로 반격하는 무한 루프가 없다. 반격은 공격자가 살아 있고 `melee_reach`로 인접할 때만.
- 종류를 추가하려면 표에 한 줄, `passives.gd`의 `match`에 한 분기. 세 훅 밖의 효과(이동력 등)는 이 설계의 범위가 아니며, 필요해지면 훅을 추가하는 별도 설계로 다룬다.

### 1.6 기본 파츠: 밀치기·엄호

| id | 아이템 | target | range | cooldown | effect | rule_when | 설명 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `PUSH` | 밀치기 요령 | ENEMY | 1 | 0 | `PUSH` | `CHARGING` | 인접한 적을 한 칸 밀어냅니다. 밀 곳이 없으면 피해 8. 적의 예고 공격을 취소합니다. |
| `GUARD` | 엄호 요령 | ALLY | 1 | 0 | `GUARD` | `ALLY_LETHAL` | 인접 아군이 받을 피해를 대신 받고 절반만 입습니다. |

- `species ""`, `passive {}`, `enemy {"prep":0,"target":"NEAREST"}`(적은 쓰지 않음 — `part_id`가 될 일이 없다). `axis` PUSH는 `MELEE`, GUARD는 `""`. `damage` PUSH 8.
- `effect PUSH`의 `resolve`: 현재 `session.act`의 `"PUSH"` 분기 그대로 — 뒤 칸이 비었으면 밀고, 아니면 `power`(파티원은 `Growth.power(actor,"MELEE",8)`)만큼 IMPACT 피해; 대상의 intent 제거; 층이면 `MonsterAI.interrupt`, 보스 시련이면 기존 `charging/fuse/cooldown/recovery` 초기화; 메시지 유지. `legal`은 `target == "ENEMY"` 공통 규칙(인접·시야).
- `effect GUARD`의 `resolve`: 현재 `"GUARD"` 분기 그대로 — `actor.guarded = true`, `victim.protected_by = actor.id`, 메시지. `legal`은 `target == "ALLY"` 규칙: 피해자가 시전자와 같은 진영, 시전자 아님, 생존, `melee_reach`.
- `session.act`의 `match`에는 `WAIT / MOVE / ATTACK / FIRE / WATER / ELECTRIC`만 남는다. `PUSH`·`GUARD`는 다른 파츠와 같이 `Abilities.DEFINITIONS.has(kind)` 경로로 실행된다.
- `Tactics.choose`의 밀치기·엄호 후보 생성(밀기 이득 계산, 인접 아군 후보)은 점수 논리이므로 그 자리에 남기되, 각각 `"PUSH" in actor.equipped_abilities` / `"GUARD" in actor.equipped_abilities`일 때만 만든다. `main.gd`의 엄호 버튼 비활성 조건(인접 아군 없음)과 "엄호 · 인접 아군 선택" 안내는 `def.target == "ALLY"` 일반 조건으로 바꾼다.
- `Rules.defaults()`는 `[]`를 돌려준다. 규칙은 장착할 때 `default_rule`로 생긴다(§1.4). `make_rule`의 `subject` 기본값 논리는 그대로.

### 1.7 획득 경로

- 시작 가방 `STARTING_PARTS := {"PUSH":1,"GUARD":1}`: 새 세션의 `parts_bag`이 이것으로 시작한다. 시작 시 장착은 비어 있다.
- 마을 상점(`SHOP`)에 `{"id":"part:PUSH","name":"밀치기 요령","price":10}`, `{"id":"part:GUARD","name":"엄호 요령","price":10}` 두 행을 더한다. `stock`·`add_stock`은 `part:` 접두어를 `parts_bag`으로 연결한다. `buy`·`refund`·`purchases` 처리는 다른 상품과 같고, `MIN_KIT`·`top_up_kit`에는 넣지 않는다. `provision_stock`·`provision_sale_value`는 `part:` 행을 건너뛴다(파츠는 귀환 시 환전되지 않고 가방에 남는다).
- 층 모드가 아닌 구 방 모드·보스 시련에는 마을 상점이 없으므로, `_init`이 모든 파티원에게 밀치기·엄호를 장착시키고 기본 규칙을 넣은 채 시작한다(이전 동작 유지, 가방 계산 없음). 층 모드는 빈 슬롯 + 시작 가방.
- 종족 파츠는 드롭으로만 얻는다(§1.5).

### 1.3 액터 필드

- `learned_abilities` **삭제**. `essences` **삭제**.
- `equipped_abilities`: 유지하되 의미는 **파츠 슬롯 2칸**. 각 칸은 파츠 id(밀치기·엄호 포함) 또는 `""`(빈칸). 기본값 `["",""]`. 슬롯에 없는 파츠는 쓸 수 없다 — 밀치기·엄호도 마찬가지다. `rules` 기본값 `[]`.
- `session.act`·`reservation_choice`의 `kind in STARTERS …` 검사는 삭제한다(장착 검사는 `Abilities.legal` 한 곳). `Tactics.rule_choice`의 `rule.skill not in actor.equipped_abilities` 건너뛰기는 그대로.
- `session.parts_bag: Dictionary {part_id: count}` — 파티 공용 가방. 스냅샷(`take_snapshot`/`restore_snapshot`)에 `essences` 자리 대신 들어간다. `finish_expedition` 결과 요약의 `essences` 키는 `parts`로 이름을 바꾸고 같은 방식(스냅샷 대비 증가분)으로 계산한다.
- 적: `enemy.part_id` (종족 시그니처 id, 없으면 `""`), `enemy.cooldowns` (파티원과 같은 딕셔너리), 준비 상태 `charging / cast_id / cast_cell / cast_left`. 기존 `essence_id`는 `part_id`로 이름을 바꾼다(보스 시련 포함).

### 1.4 장착·해제 (마을 전용)

```gdscript
# session.gd
func equip_part(index: int, slot: int, id: String) -> bool
```

```gdscript
func unequip_part(index: int, slot: int) -> bool
```

- `equip_part` 조건: `phase == "TOWN"`, 살아 있는 파티원, `slot in [0,1]`, `Abilities.DEFINITIONS.has(id)`, `parts_bag[id] > 0`. 같은 파티원의 다른 칸에 이미 같은 id가 있으면 실패(같은 파츠 2개 장착 불가; 서로 다른 파티원은 각자 같은 파츠를 낄 수 있다).
- `equip_part` 실행: 그 칸에 파츠가 있었으면 먼저 `parts_bag[old] += 1`(교체). `parts_bag[id] -= 1`, 칸에 `id`. `actor.reservation = {}`.
- `unequip_part`: 같은 조건에서 칸을 `""`로 비우고 파츠를 가방으로 되돌린다. 빈칸이면 실패.
- 규칙: 빠진 파츠의 규칙(`rule.skill == old`)은 `actor.rules`에서 제거, 새 파츠는 `Abilities.default_rule(id)`를 뒤에 추가(이미 있으면 추가 안 함).
- 기존 `Abilities.equip`·`session.equip_ability`·`consume_essence`는 삭제. `reset_rules`는 `Rules.defaults()` + 장착된 파츠의 `default_rule`.
- `grant_test_loadout()`: `phase == "TOWN"`에서 `DEFINITIONS`의 모든 id(밀치기·엄호 포함)를 `parts_bag`에 1개씩 넣는다(이미 1개 이상이면 더하지 않음). 메시지: "시험 로드아웃 · 파츠 %d종 지급 — 파츠 탭에서 장착하세요."

### 1.5 드롭

`roll_essence` → `roll_part`. 적 사망 시 `enemy.part_id`가 정의에 있으면 기존 확률(층: 빛 단계별 50/65/80%, 그 외 `DROP_PERCENT`)로 `parts_bag[id] += 1`, 메시지 "`item` 획득". 성장 XP 지급은 그대로.

`continuous_floor.apply`: 드롭 순환 코드 삭제, `enemy.part_id = Abilities.species_part(member.species_id)`. `boss_trial.gd`: `boss.part_id = droppable()[pattern % size]`.

## 2. 적 AI 통합

### 2.1 준비 상태 통일

`MonsterAI`의 술사 시전(`charging/cast_cell`)을 일반화한다. 준비 상태는 `{charging: bool, cast_id: String, cast_cell: Vector2i, cast_left: int}`이며 `cast_id == ""`는 기존 역할 시전(피해 14, 사거리 4)이다.

`plan(s)`는 준비 중인 적마다 intent `{"id", "cell", "damage", "kind"}`를 만든다. `kind`는 `cast_id`(역할 시전이면 `""`), `damage`는 파츠면 `DEFINITIONS[cast_id].damage`, 역할 시전이면 14. `Rules.lethal_threat`는 `intent.damage`를 그대로 읽으므로 변경 없음. `board.gd`는 예고 칸 표시에 `kind`가 비어 있지 않으면 `Abilities.badge(kind)` 텍스트를 덧붙인다.

### 2.2 턴 순서 (`MonsterAI.turn`)

```
1. 사망·대상 없음 → 종료. 경계(alert) 판정은 그대로.
2. 경계 해제(거리 > 15) → charging 해제, plan.
3. cast_recovery > 0 → 감소 후 종료.
4. 파츠 쿨다운 감소: cooldowns[part_id] = max(0, -1)  (이 턴 시작 시 1회)
5. charging이면:
   a. cast_left -= 1; cast_left > 0이면 plan 후 종료 (prep 2의 둘째 라운드)
   b. 해제(charging=false), plan.
   c. cast_id == "" → 기존 역할 시전 해결(변경 없음).
   d. 아니면 Abilities.resolve(s, enemy, cast_id, cast_cell); cooldowns[cast_id] = cooldown + 1. 종료.
6. 시그니처 시도: part_id가 있고 cooldowns[part_id] == 0이고, 가장 가까운 파티원부터 Abilities.legal(s, enemy, part_id, target.pos)가 참인 첫 대상이 있으면:
   - prep == 0 → Abilities.execute(...) 후 종료.
   - prep > 0 → charging=true, cast_id=part_id, cast_cell=target.pos, cast_left=prep; plan; 메시지 "<이름> · <파츠 name> 준비". 종료.
7. 없으면 기존 역할 행동(근접 추격 / 원거리 / 술사 시전 / 이동).
```

- 술사 역할의 시전은 파츠 시도 다음 순서이므로, 둘 다 가능하면 파츠가 먼저다.
- `interrupt(s, enemy)`(밀치기 또는 피격): charging 해제, `cast_recovery = 1`, 파츠 준비였으면 `cooldowns[cast_id] = DEFINITIONS[cast_id].cooldown`(역할 시전이면 기존대로 `cast_cooldown = 3`), intents에서 제거, 메시지 "시전이 끊겼습니다" 유지.
- 적 쿨다운은 파티원과 달리 `end_round`가 아니라 위 4단계에서 줄인다(적 턴이 곧 라운드 1회).

### 2.3 `Abilities`의 양측 공용화

```gdscript
static func legal(s, actor, id, target) -> bool
static func execute(s, actor, id, target) -> bool   # legal 후 resolve
static func resolve(s, actor, id, target) -> void   # 합법성 검사 없이 해결(예고 해결용)
static func power(s, actor, def) -> int             # 파티원: Growth.power(actor, axis, damage); 적: damage + (층이면 enemy_bonus(light))
```

`legal`의 진영 분기:
- 장착 검사: 파티원은 `id in actor.equipped_abilities`, 적은 `actor.part_id == id`.
- AP 검사는 파티원만.
- `target == "ENEMY"`인 스킬의 피해자는 `victim.enemy != actor.enemy`.
- 나머지(사거리·시야·쿨다운·페이즈·HEAL 만혈·LUNGE 경로)는 공통.

`resolve`의 진영 분기:
- DAMAGE: 피격 후보는 `party + enemies` 중 생존자, 시전자 제외, `allies_hit == false`면 시전자 진영 제외. `self_hit`은 기존대로. `tile_wet > 0`이면 피격 칸마다 `tile.wet = max(wet, tile_wet)`(벽 제외).
- 예고 해결에서 대상 칸에 아무도 없으면 범위만 처리한다(radius 0이면 아무 일도 없음, 메시지 "<이름>의 <파츠>가 빗나갔습니다").
- LUNGE: 대상 칸에 피해자가 없으면 이동만 하고 피해 없음. `lunge_cell`은 `LUNGE` 상수 대신 호출한 `id`의 정의를 읽도록 시그니처를 `lunge_cell(s, actor, id, target)`로 바꾼다.
- 로그·effects·쿨다운 설정은 공통. 파티원의 `ap` 차감은 `session.act`가 계속 담당한다.

### 2.4 시야·AP

적은 `ap`를 쓰지 않는다(턴당 시그니처 1회 또는 역할 행동 1회). 파티원은 파츠 액티브를 즉발로 쓴다(prep 없음).

## 3. 1층 8종 시그니처

역할 기본 공격(근접 7 / 궁수 6 / 술사 4·시전 14)은 그대로. 아래는 그 위에 얹는 시그니처. 수치는 초기값이며 §5의 게이트로 조정한다. 모든 종족 `enemy.prep = 1`, `enemy.target = "NEAREST"`.

1층 기준의 힘 상한: 액티브 피해는 역할 기본 공격(근접 7)보다 조금 높은 정도이고, 가장 무거운 한 방(홉고블린 내려치기)도 기존 술사 시전(14)을 넘지 않는다. 패시브는 +1~+3 범위. 플레이어가 끼면 `Growth.power`가 붙지만 기본 공격(18)보다 낮은 값이며, 파츠의 가치는 사거리·범위·이동·패시브에서 나온다.

| 종족 | 파츠 id · 아이템 | 패시브 | 액티브 (target / range / radius / damage / cd / effect / axis) |
| --- | --- | --- | --- |
| 쥐 `dcss_rat` | `RAT_GNAW` · 쥐 이빨 | `PACK` 1 | 물어뜯기: ENEMY / 1 / 0 / 9 / 2 / DAMAGE / MELEE |
| 목도리 도마뱀 `dcss_frilled_lizard` | `LIZARD_TAIL` · 도마뱀 꼬리 | `RETALIATE` 2 | 꼬리치기: ENEMY / 1 / 1 / 6 / 3 / DAMAGE / MELEE · `allies_hit false` · shape SQUARE |
| 코볼트 `kobold` | `KOBOLD_SLING` · 코볼트 투석끈 | `DIRTY` 3 | 투석: ENEMY / 4 / 0 / 7 / 2 / DAMAGE / RANGED |
| 고블린 `goblin` | `GOBLIN_SHIV` · 고블린 단검 | `AMBUSHER` 3 | 기습: ENEMY / 3 / 0 / 10 / 3 / LUNGE / MELEE |
| 홉고블린 `dcss_hobgoblin` | `HOB_CLUB` · 홉고블린 곤봉 | `THICK_HIDE` 1 | 내려치기: ENEMY / 1 / 0 / 14 / 3 / DAMAGE / MELEE |
| 오크 `dcss_orc` | `ORC_CLEAVER` · 오크 도끼 | `BLOODLUST` 3 | 휘두르기: ENEMY / 1 / 1 / 11 / 3 / DAMAGE / MELEE · `allies_hit false` · shape SQUARE |
| 놀 `dcss_gnoll` | `GNOLL_SPEAR` · 놀 창 | `REGEN` 2 | 창 찌르기: ENEMY / 2 / 0 / 12 / 3 / DAMAGE / MELEE |
| 강쥐 `dcss_river_rat` | `RIVER_RAT_SPLASH` · 강쥐 가죽 | `AMPHIBIOUS` 3 | 물세례: ENEMY / 3 / 1 / 5 / 3 / DAMAGE / RANGED · `allies_hit false` · shape SQUARE · `tile_wet 70` |

- `rule_when`은 전부 `ALWAYS`. `short`는 액티브 이름 두 글자(물기·꼬리·투석·기습·곤봉·도끼·창·물). `icon`은 기존 폴백 5.
- `description`은 "패시브 · 액티브" 한 줄: 예) 쥐 이빨 — "무리: 인접 아군당 피해 +1 · 물어뜯기: 인접 대상 피해 9 · 재사용 2턴".
- 범위 1 파츠(꼬리치기·휘두르기)는 대상 칸 중심 3×3. 적이 쓰면 `allies_hit false`라 같은 무리를 다치게 하지 않고, 플레이어가 쓰면 파티원을 다치게 하지 않는다.
- 놀 창(range 2)의 사거리 판정은 기존 `legal`의 Manhattan 거리(range > 1)를 그대로 따른다.

`data/content/floor_monsters.json`은 바꾸지 않는다. 종족→파츠는 `DEFINITIONS[id].species`가 담당하며, 검증 테스트가 "각 종족에 파츠가 정확히 하나"를 확인한다.

## 4. 규칙 카탈로그 · UI

### 4.1 `Rules.SKILLS`를 카탈로그에서 파생

`tactic_rules.gd`의 `SKILLS` 상수를 없애고 `static func skill(id) -> Dictionary`와 `static func catalog() -> Dictionary`를 둔다. 모든 항목(밀치기·엄호·파츠·구 이능·시험 스킬)을 `Abilities.DEFINITIONS`에서 만든다:

| `def.target` | `targets` | `conditions` |
| --- | --- | --- |
| `SELF` | `["SELF"]` | `["ALWAYS","HP","STATUS","DANGER"]` |
| `ENEMY` | `["NEAREST","LOWEST_HP"]` | `["ALWAYS","HP","STATUS","CHARGING","DANGER"]` |
| `ALLY` | `["ALLY"]` | `["ALLY_LETHAL"]` |

`name`·`description`은 `def`의 것. `Abilities.default_rule(id)`의 대상은 `SELF → "SELF"`, `ALLY → "ALLY"`, `ENEMY → "NEAREST"`.

`tactic_rules.gd`는 `abilities.gd`를 `preload`하지 않는다(`abilities.gd`가 이미 `tactic_rules.gd`를 preload하므로 순환). `catalog()`는 `static var` 캐시에 `load("res://expedition/abilities.gd")`로 한 번 채운다. `valid`·`matches`·`summary`·UI·테스트의 `Rules.SKILLS[...]` 18곳은 `Rules.skill(id)` / `Rules.catalog()`로 바꾼다. `tests/skill_rule_conditions.gd`의 전수 검사는 `catalog()` 순회로 바뀌어 파츠 8종을 자동으로 포함한다.

### 4.2 파츠 탭 (`character_ui.gd`, `main.gd`)

- 탭 이름 "이능" → "파츠". 머리글 "파츠 슬롯 N / 2"(N = 장착 수).
- 슬롯 카드 2장: 파츠면 이름 + 패시브·액티브 설명 한 줄씩 + "해제"·"교체" 버튼, 빈칸이면 "빈 슬롯" + "장착" 버튼. 버튼은 `phase == "TOWN"`에서만 활성. 장착·교체 목록: `parts_bag`에서 수량 > 0인 파츠(수량 표시), 없으면 "가방에 파츠 없음". 선택 시 `session.equip_part(index, slot, id)`, 해제는 `session.unequip_part(index, slot)`.
- 규칙 목록(사용 방침)은 그대로: 장착된 것의 규칙만 보인다(`rule_choice`가 이미 미장착 규칙을 건너뛰고, `equip_part`가 규칙을 넣고 뺀다).
- 가방(`show_supplies`) 카테고리 "이능" → "파츠": 행은 `parts_bag`, 설명은 "패시브 · 액티브", 상세 버튼은 "<이름> 1번 / 2번 장착"(TOWN에서만). "먹이기"·`confirm_essence` 삭제.
- 결과 화면: `r.parts` 목록 표시(`item ×n`).
- 전투 버튼(`main.gd` 파티 열): 액터당 2개 그대로, 층·보스 시련에서는 파츠 슬롯 2칸(빈 슬롯은 비활성 버튼에 캡션 "빈 슬롯"), 구 방 모드는 기존 `SKILLS[i]` 표. 파츠 버튼 캡션은 `Rules.skill(id).name`과 쿨다운. `tests/ui_smoke.gd`의 슬롯 수 검사(6)는 그대로.
- 상점 목록에 밀치기 요령·엄호 요령 두 행(가격 10).
- 적 예고: 기존 예고 칸 표시에 파츠 short 텍스트.

### 4.3 시뮬레이터·기준 빌드

- `reference_builds.json`: `learned` 키 삭제. `equipped`는 파츠 슬롯 2칸이며 기존 빌드는 그대로(`starter`·`melee_1`은 `["PUSH","GUARD"]`, `b_strike`는 `["HEAVY_STRIKE","GUARD"]` 등). `apply_build`는 `equipped`와 `rules`만 적용한다. 파츠 빌드 8개 추가: `p_rat p_lizard p_kobold p_goblin p_hob p_orc p_gnoll p_river`, 각각 `equipped [<파츠>, "GUARD"]`, `ranks {"MELEE":1}`, `rules [[<파츠>,"NEAREST","ALWAYS"],["GUARD","ALLY","ALLY_LETHAL"]]`.
- `balance_experiments.json`의 `skill_value.builds`에 파츠 8개 추가. `docs/balance/skill-value.md`를 재생성한다(적도 시그니처를 쓰는 새 환경에서 전 빌드 재측정 — 이전 보고서와 직접 비교하지 않고 머리말에 "몬스터 파츠 도입 후" 명시).
- `encounter_runner.run_one`에 `enemy_skill_uses: {part_id: count}`와 `interrupts: int`(밀치기·피격으로 끊긴 준비 횟수)를 추가하고 `run_many`에 평균(`enemy_skill_uses_mean`, `interrupts_mean`)을 넣는다. 계측은 세션 카운터로 한다: `stats_enemy_skill: Dictionary`는 적이 `resolve`/`execute`할 때, `stats_interrupts: int`는 `MonsterAI.interrupt`가 파츠 준비를 끊을 때 올린다(`stats_redirects`와 같은 방식). 로그 문자열은 세지 않는다.

## 5. 검증과 밸런스 게이트

### 5.1 CI 테스트

새 스위트 `tests/parts.gd` (`.github/workflows/deploy-pages.yml` 목록에 추가):

1. 정의 검증: `floor_monsters.json`의 각 종족에 `species_part`가 정확히 하나; 모든 파츠의 `passive.kind`가 `Passives.KINDS`에 있음; `enemy.prep`이 0~2; `effect`가 4종 중 하나; `Rules.valid(Abilities.default_rule(id))`가 전 정의에서 참.
2. 패시브 8종 각각 한 케이스(수치까지): PACK 인접 아군 2명 → +2, RETALIATE 인접 공격자 2 피해·비인접 0·반격에 반격 없음, DIRTY 대상 49%에서 +3·50%에서 +0, AMBUSHER 고립 대상 +3·인접 아군 있으면 +0, THICK_HIDE 2 피해 → 1(최소 1), BLOODLUST 자신 49% +3, REGEN 라운드 시작 +2·최대 초과 없음, AMPHIBIOUS 젖은 칸 +3·마른 칸 +0.
3. 적 예고: 홉고블린이 인접 파티원을 보면 `charging`·`intents[0].kind == "HOB_CLUB"`·`damage 14`; 다음 라운드 해결 시 파티원 HP −(14+어둠 보너스, `Growth.incoming` 적용)·`cooldowns` 설정; 준비 중 밀치기 → intent 제거·`cast_recovery 1`·쿨다운 = 정의 cooldown; prep 0 데이터로 바꾸면 즉발; prep 2면 두 라운드 뒤 해결.
4. 예고 해결에서 대상이 칸을 비우면 피해 0(radius 0), 범위 파츠는 남은 칸을 맞힘. `allies_hit false`인 오크 휘두르기가 인접한 다른 적을 안 맞힘.
5. 플레이어: 파츠 장착 후 `act(id, cell)` 즉발·쿨다운·AP 차감; `Growth.power` 적용.
6. 장착 규칙: 새 세션의 슬롯이 `["",""]`이고 가방이 `{"PUSH":1,"GUARD":1}`; 슬롯이 비면 `act("PUSH")`·`act("GUARD")`가 실패하고 `Tactics.choose`가 밀치기·엄호 후보를 내지 않음; 장착하면 기존 `protect`·`companion_tactics`의 동작 그대로; TOWN 밖에서 `equip_part`·`unequip_part` 실패; 가방 0개면 실패; 같은 파티원에 같은 파츠 2개 실패; 다른 파티원은 각자 가능; 교체·해제 시 이전 파츠가 가방으로 복귀; 규칙이 추가·제거됨; 상점에서 `part:PUSH` 구매·환불이 `parts_bag`과 `bank`를 맞게 바꿈.
7. 스냅샷: 원정 중 획득한 파츠가 DEFEAT/ABANDON에 소실·SUCCESS/PARTIAL에 유지(기존 `expedition_settlement`·`solo_floor` 검사를 `parts_bag`으로 바꿔 유지).
8. 드롭: 쥐를 죽이면 `RAT_GNAW`가 확률로 가방에 들어감(빛 단계별 확률 검사는 `torch_tradeoff`에서 유지).
9. `Rules.catalog()`가 `DEFINITIONS`의 모든 id를 포함하고, `Rules.skill("GUARD").targets == ["ALLY"]`, `Rules.valid`가 카탈로그 전 항목의 `default_rule`을 받아들임.

기존 스위트 수정: 밀치기·엄호를 쓰는 모든 스위트(`protect`·`companion_tactics`·`boss_trial`·`mobile_actions`·`enemy_turns`·`skill_rule_conditions`·`encounter_sim`·`solo_balance`·`solo_floor` 등)는 픽스처에서 `equipped_abilities = ["PUSH","GUARD"]`와 해당 `default_rule`을 넣어 이전 동작을 유지한다(공용 헬퍼 `tests/map_fixture.gd`·`tests/floor_fixture.gd`에 `equip_basics(s)` 추가). `abilities_growth`(먹이기 → 장착), `character_ui`, `continuous_floor`(드롭 순환 → `part_id == species_part`), `expedition_settlement`, `mobile_hud`, `skill_archetypes`, `solo_floor`, `terrain_layouts`, `test_loadout`, `torch_tradeoff`, `skill_rule_conditions`(카탈로그 순회), `boss_trial`(있다면 `part_id`). 다른 스위트 회귀 없음.

### 5.2 밸런스 게이트 (방법론 §3·§5)

구현 완료 후 순서대로 실행하고 결과를 `docs/balance/`에 남긴다. 게이트를 통과하지 못하면 §3의 수치를 조정하고 다시 돌린다. 조정 우선순위는 액티브 damage → cooldown → 패시브 value 순이며, prep은 1층에서 바꾸지 않는다.

| 게이트 | 도구 | 기준 |
| --- | --- | --- |
| G1 솔로 1층 | `tests/solo_balance.gd`(CI) | 8시드 중 승리 ≥ 3 (현 기준 유지) |
| G2 조우 아레나 | `tests/encounter_sim.gd`(CI) + `tests/action_economy.gd` 재생성 | 3인 `rules` 정책에서 6아레나 승률 ≥ 0.9; 솔로 `early_*` 아레나 승률 ≥ 0.5 |
| G3 스킬 가치 | `tests/skill_value.gd` → `docs/balance/skill-value.md` | 파츠 8종 중 지배 후보 0, "봇이 못 씀" 0; 약함 후보는 기록만 |
| G4 적 시그니처 사용 | `run_many.enemy_skill_uses_mean` | 8종 각각 자기 파츠를 전투당 평균 ≥ 0.5회 사용(사용 0이면 `legal` 어디서 막혔는지 G3와 같은 방식으로 기록) |
| G5 엄호 가치 | `tests/party_guard_probe.gd` | 3인 아레나 사망 수가 엄호 규칙 있음 < 없음 (예고가 근접 적에도 생겼으므로 차이가 벌어져야 정상) |

보고서 머리말에는 커밋·날짜·시드·"몬스터 파츠 도입 후 첫 측정" 문장을 넣는다.

## 6. 파일 요약

| 파일 | 변경 |
| --- | --- |
| `expedition/abilities.gd` | 정의 필드 추가·파츠 8종·`species_part`·`power`·`resolve`·진영 분기·`equip` 삭제 |
| `expedition/passives.gd` | 신규: `KINDS`·`of`·`outgoing`·`incoming`·`round_start` |
| `expedition/monster_ai.gd` | 준비 상태 일반화·시그니처 시도·쿨다운·`interrupt` |
| `expedition/session.gd` | `parts_bag`·`STARTING_PARTS`·상점 `part:`·`equip_part`/`unequip_part`·`roll_part`·`damage` 훅·`end_round` 훅·스냅샷·결과·`grant_test_loadout`·`act`에서 PUSH/GUARD 분기 제거·삭제(`essences`·`learned_abilities`·`consume_essence`·`equip_ability`) |
| `expedition/tactic_rules.gd` | `SKILLS` 삭제·`skill`·`catalog`·`defaults() == []` |
| `expedition/tactical_action_selector.gd` | 밀치기·엄호 후보를 장착 시에만 생성 |
| `expedition/continuous_floor.gd`, `expedition/boss_trial.gd` | `part_id` |
| `expedition/board.gd` | 예고 칸 파츠 텍스트 |
| `expedition/main.gd`, `expedition/character_ui.gd` | 파츠 탭·가방·결과 |
| `expedition/sim/encounter_runner.gd`, `data/content/reference_builds.json`, `data/content/balance_experiments.json` | 빌드·계측 |
| `tests/parts.gd` 신규, 기존 스위트 수정(픽스처 `equip_basics` 포함), `.github/workflows/deploy-pages.yml` | 검증 |
| `docs/balance/skill-value.md`·`.json`, `docs/balance/action-economy.md`·`.json` | 재생성 |
