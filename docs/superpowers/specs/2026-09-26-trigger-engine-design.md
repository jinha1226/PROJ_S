# ② 키워드·발동 엔진

작성일: 2026-09-26 · 상태: **검토 반영·② 구현 완료**
근거: [공격 형태·부위 영혼석](2026-09-26-damage-forms-part-stones-design.md) §3·§6 ② · [영혼석 개편](2026-09-26-soulstone-rework-design.md)
다음 단계: [③ 빌드군과 부위 효과](2026-09-26-build-families-part-effects-design.md), [④ 부위 영혼석 구현](2026-09-26-part-stones-implementation-design.md)
기존 코드: `expedition/progression/stone_effects.gd`(340줄, 대표 효과 30개를 효과마다 `if has(...)`로 처리), `expedition/combat/passives.gd`, `combat_rules.gd`, `statuses.gd`, `reactions.gd`, `expedition/spells/spells.gd`, `summons.gd`, `expedition/run/session.gd`(`after_damage`)

## 구현 계약 보정 (2026-09-26)

- 사건의 `form`은 `s.blow_form`의 실제 베기·타격·찌르기이며, `element`, `hit_form`, `spell`은 별도 필드다. 피해 경로에서 실제 엄호 대상, 손실량, 치명타 여부와 처치 직전 상태 스냅샷을 전달한다.
- 조건을 먼저 평가하고, 실행할 규칙이 있을 때 한 번 표식을 예약한다. 같은 효과·사건의 여러 규칙은 함께 실행한다. 예약은 결과보다 먼저라 재진입이 차단된다.
- 오라는 `scope: allies`로 소유자 탐색을 명시한다. 같은 `group`은 중첩하지 않으며 실제 피해 대상 주변에서 읽는다. 소환 강화는 `scope: summoner`로 구분한다.
- 기존 효과의 롤 레인과 발동 빈도를 보존한다. 기존에 매 타격·매 상태마다 검사하던 규칙만 `limit: event`를 명시한다. 새 효과의 기본값은 행동당 한 번이다. 깊이 제한은 두 종류 모두 적용한다.
- `ALLY_LETHAL`은 치명상 직전, `ALLY_CRISIS`는 실제 HP가 25% 경계를 처음 넘은 직후다. 보호 재지정은 타격당 한 번이며 상호 보호 순환을 만들지 않는다.
- ②에서는 기존 30개 효과를 옮긴다. ④의 부위 ID·직접 딕셔너리 조회 전환은 별도 단계다. 지원하지 않는 데이터 키는 검사 실패로 드러내며 빈 동작으로 통과시키지 않는다.

## 0. 목표와 결정

③에서 부위 효과 114개를 만든다. 지금처럼 효과마다 코드를 한 줄씩 끼워 넣으면 `stone_effects.gd`가 1,000줄을 넘고, 새 발동 조건이 생길 때마다 전투 코드 여러 곳을 고쳐야 한다. 이 단계는 **효과를 데이터로 적고, 발동 지점을 한곳으로 모으는** 틀을 만든다.

1. **혼합 방식.** 흔한 모양(조건 → 결과)은 데이터 행으로 적는다. 데이터로 적기 어려운 효과(부활, 효과 공유 등)는 이름 붙은 코드 처리기(`code`)로 남긴다. 목표는 114개 중 90개 이상을 데이터로.
2. **발동 지점은 `StoneEffects.fire(s, trigger, context)` 한 함수로 모은다.** 전투 코드는 "이런 일이 일어났다"만 알린다. 누가 어떤 효과로 반응하는지는 엔진이 찾는다.
3. **수치 보정(공격력 %, 받는 피해 %, 치명타 확률 등)은 발동과 따로 모은다.** `StoneEffects.modifier(s, key, actor, context)`가 해당 키의 보정을 모두 더한다. 기존 `outgoing`/`incoming`/`crit_chance`/`delay`는 이것을 부르게 바뀐다.
4. **연쇄는 허용하되 깊이를 제한한다.** 효과가 건 상태가 다른 효과의 "상태를 걸 때"를 부를 수 있다. 한 행동 안에서 연쇄 깊이는 2까지, 같은 효과는 한 행동에 한 번까지(`Reactions.once`와 같은 창).
5. **효과가 주는 피해는 2차 피해다.** 효과의 추가 피해·폭발·전이 피해는 `EXTRA` 또는 `REACTION` 형태로 들어가서 대표 효과·치명타·부상을 다시 부르지 않는다(기존 규칙 그대로).
6. **기존 30개 효과는 동작을 바꾸지 않고 옮긴다.** 옮긴 뒤 `tests/stone_effects.gd`가 그대로 통과해야 한다.

## 현재 데이터 계약

- 기존 30개 행은 `limit: event`로 예전 발동 빈도를 유지한다. 새 효과는 기본 `limit: action`이며 같은 효과·사건의 적격 규칙들을 한 번에 실행한다.
- 새 `HIT` 규칙은 `phase`를 생략한다. 현재 타격의 원소 반응이 끝난 뒤 발동하며 주문·처치 타격도 사건을 보낸다. 기존 흡혈·연사는 `phase: after`, 기존 상태 발동은 `phase: proc`를 명시해서 순서를 보존한다.
- 새 `ATTACK` 규칙은 피해 % 합산 뒤 적용한다. 기존 거머리·분노 상태 준비는 `phase: prepare`, 기습 배율은 `phase: scaled`다. 이 구분은 기존 30개 이식용이며 새 콘텐츠는 별도 단계가 필요한 경우만 사용한다.
- `mod` 값은 숫자 또는 `{"value": 5, "per_stack": ["rage", 1]}` 형태다. `per_count`·`per_lost_hp`도 이 값의 인자로 쓴다. `ALWAYS`의 확률 조건은 금지해 UI가 수치를 조회할 때 롤을 소모하지 않는다.
- 회복량은 `heal: {"max_hp%": 15}` / `heal: {"dealt%": 15}` / `heal: 5`, 폭발은 `burst: 1, damage: 5`, 상태는 `apply_status: "bleed", ticks: 300`이다. `target: self_and_allies`는 자신과 인접 아군을 포함한다.
- 범위 효과는 대각선을 포함하는 정사각 반경이며, 지속 피해 보정은 상태를 건 인물에게서 읽는다. 효과는 생존한 소유자만 발동한다.
- 치명상 대신 맞기는 원래 대상에게 계산된 최종 피해를 타격당 한 번만 넘긴다. 실제 받는 대상·보호막·부상·처치 기록은 보호자를 따른다. 조건부 처치 효과는 피해 시점의 상태와 치명타 사실을 읽는다.
- 공격 중 새로 받은 `until: attack` 쌓임은 현재 공격에 바로 사라지지 않고 다음 공격에 사용한다. 행동·다음 공격·전투 종료·tick 종료 경계를 분리한다.

## 1. 키워드 사전(확정본)

효과 문구와 데이터는 이 단어만 쓴다. 새 단어는 이 표에 먼저 추가한다.

### 1.1 발동 조건 `when`

| id | 뜻 | 부르는 곳 | context |
| --- | --- | --- | --- |
| `ALWAYS` | 상시(수치 보정 전용) | `modifier` | — |
| `ATTACK` | 1차 공격을 하려 할 때(피해 계산 중) | `StoneEffects.outgoing` | attacker, target, form, spell, ranged |
| `HIT` | 1차 공격이 명중해 피해가 들어간 뒤 | `CombatRules.damage` 끝(`procs` 자리) | attacker, target, form, lost |
| `STRUCK` | 1차 공격에 맞은 뒤 | `StoneEffects.after_hit` | target(=나), attacker, form, lost |
| `DODGE` | 공격을 피했을 때 | `CombatRules.attack`의 회피 분기 | target(=나), attacker |
| `BLOCK` | 방패로 막았을 때 | `CombatRules.attack`의 막기 분기 | target(=나), attacker |
| `CRIT` | 치명타를 냈을 때 | `StoneEffects.outgoing`의 치명타 분기 | attacker, target |
| `KILL` | 내가 처치했을 때 | `Session.after_damage`의 처치 분기 | killer, victim, form, victim_statuses |
| `ALLY_KILL` | 같은 편 다른 인물이 처치했을 때 | 처치 분기 | me, killer, victim |
| `DEATH_NEAR` | 반경 3 안에서 누가(적·아군 불문) 쓰러졌을 때 | 처치 분기 | witness(=나), victim |
| `LETHAL` | 내가 쓰러질 피해를 받으려 할 때 | `StoneEffects.lethal` | target(=나), amount |
| `STATUS_GIVEN` | 내가 누군가에게 해로운 상태를 걸었을 때 | `Statuses.apply` 끝(실제로 걸렸을 때만) | source(=나), victim, status |
| `STATUS_TAKEN` | 나에게 해로운 상태가 걸리려 할 때 | `Statuses.apply` 앞(`shed` 자리) | victim(=나), source, status |
| `WOUND` | 내가 부상(출혈·골절·급소)을 입혔을 때 | `Forms.wound` 끝 | source(=나), victim, status |
| `REACTION` | 내 피해가 원소 반응을 일으켰을 때 | `Reactions` 반응 발생 지점 | source(=나), target, reaction |
| `CAST` | 내가 주문을 썼을 때(실패 제외) | `Spells.cast` | caster(=나), spell |
| `SUMMON` | 내가 소환수를 불렀을 때 | `Summons.summon` | caster(=나), pet |
| `SUMMON_END` | 내 소환수가 사라지거나 쓰러졌을 때 | `Summons.expire`, 소환수 처치 | caster(=나), pet, died |
| `PET_KILL` | 내 소환수가 처치했을 때 | 처치 분기(처치자가 소환수) | caster(=나), pet, victim |
| `ALLY_LETHAL` | 인접 동료가 쓰러질 피해를 받기 전 | `after_damage` 방어 계산 뒤, HP 차감 전 | ally, attacker, amount, redirector |
| `ALLY_CRISIS` | 인접 동료의 체력이 25% 이하로 처음 떨어질 때 | `after_damage` | me, ally |
| `ROUND_START` | 라운드 시작 | `Passives.round_start` | actor |
| `BATTLE_START` | 전투 시작 | `StoneEffects.battle_start` | actor |
| `MOVED` | 이동을 마쳤을 때 | `Session` 이동 처리 | actor, from, to |
| `DOT_TICK` | 반경 2 안의 적이 지속 피해를 입었을 때 | `Statuses.tick` | witness(=나), victim, status, amount |
| `HEALED` | 내가 누군가를 회복시켰을 때 | `StoneEffects.heal` | healer(=나), target, amount |

### 1.2 조건 `if` (모두 참이어야 발동, 배열)

| id | 인자 | 뜻 |
| --- | --- | --- |
| `form` | `SLASH`/`IMPACT`/`PIERCE` | 이 피해의 형태 |
| `ranged` | bool | 거리 2 이상 |
| `spell` | bool | 주문 피해인가 |
| `target_has` | 상태 id | 대상이 그 상태 |
| `target_harmful_at_least` | n | 대상의 해로운 상태 수 ≥ n |
| `target_full` | bool | 대상 체력 가득 |
| `target_distance_at_least` | n | 거리 ≥ n |
| `self_hp_below` | % | 내 체력 < % |
| `self_has` | 상태 id | 내가 그 상태 |
| `self_wet` | bool | 젖은 칸·물 |
| `status_is` | 상태 id 또는 배열 | (`STATUS_*`, `WOUND`) 걸린 상태 |
| `adjacent_allies_at_least` | n | 인접 동료 수 ≥ n |
| `adjacent_enemies_at_least` | n | 인접 적 수 ≥ n |
| `no_adjacent_enemy` | bool | 인접 적 없음 |
| `stack_at_least` | [이름, n] | 내 쌓임 ≥ n |
| `unarmed` | bool | 무기를 들지 않음(지팡이 포함 X, 맨손만) |
| `first_attack` | bool | 이번 전투에서 내 첫 공격 |
| `same_target_as_ally` | bool | 동료가 이번 라운드에 같은 대상을 쳤음 |
| `moved_this_round` | bool | 이번 라운드에 이동했음 |
| `killer_is_crit` | bool | (`KILL`) 치명타로 처치 |
| `victim_had` | 상태 id 또는 `"harmful"` | (`KILL`) 쓰러지기 직전 대상이 그 상태였음 |
| `owner_adjacent_to_target` | bool | (피해 받는 쪽 보정) 효과 주인이 맞는 인물과 인접. 해골 병사처럼 "인접 동료가 받는 피해"에 쓴다 |
| `status_already` | bool | (`STATUS_GIVEN`, `WOUND`) 대상이 이미 그 상태였음 |
| `chance` | % | 확률(결정론 롤, 레인 `fx_<효과 id>`) |

### 1.3 결과 `do` (배열, 순서대로)

| id | 인자 | 뜻 |
| --- | --- | --- |
| `damage_percent` | % | (`ATTACK`에서만) 이 공격의 피해 ±% |
| `extra_damage` | 양, 원소 | 대상에게 2차 피해(`EXTRA`) |
| `apply_status` | 상태, tick, 대상(`target`/`attacker`/`self`) | 상태 걸기(`Statuses.apply`) |
| `extend_status` | 상태, % | 대상에게 걸린 상태 지속 연장 |
| `spread_status` | 상태 또는 `"harmful"`, 반경 | 죽은/맞은 대상의 상태를 주변 적에게 옮김 |
| `burst` | 반경, 피해(고정 또는 `victim_max_hp%`), 원소 | 지점 폭발(`REACTION` 형태) |
| `push` | 칸, 막히면 피해 | 대상을 밀어냄 |
| `heal` | `max_hp%` 또는 `dealt%` 또는 고정, 대상(`self`/`adjacent_allies`/`party`/`ally`) | 회복(`StoneEffects.heal`) |
| `gain_mp` | 양 | MP 회복 |
| `stack` | 이름, +n, 최대, 풀림 규칙 | 쌓임 증가(§2) |
| `clear_stack` | 이름 | 쌓임 초기화 |
| `buff` | 상태(`haste`/`ward`/`rage`/사용자 정의), tick, 대상 | 이로운 상태 걸기 |
| `cooldowns` | −n | 내 파츠 재사용 대기 감소 |
| `redirect` | — | (`ALLY_LETHAL`) 현재 치명상을 대신 받음. 보호 후보는 원래 대상과 다르고 살아 있어야 하며 한 타격에 한 번만 재지정 |
| `revive` | HP% | (`LETHAL`) 쓰러지지 않고 HP%로 |
| `raise_dead` | 소환 종류, tick | (`KILL`) 쓰러진 적 자리에 소환수 |
| `summon` | 종류, tick | 소환 |
| `notice` | 문구, 톤 | 발동 알림(`PROC`). 확률 효과와 상태 변화에는 반드시 |

### 1.4 수치 보정 키 `modifier`

`when: "ALWAYS"`와 `if`로 조건부 상시 보정을 적는다(`do` 대신 `mod`).

| 키 | 단위 | 읽는 곳 |
| --- | --- | --- |
| `attack_percent` | % | `outgoing` |
| `taken_percent` | % | `incoming` |
| `crit_chance` / `crit_damage` | %p | `crit_chance` / `crit_percent` |
| `wound_chance` | %p (형태별 `wound_chance.SLASH` 등) | `Forms.wound_chance` |
| `status_ticks` | % (상태별 가능) | `status_ticks` |
| `speed` | % | `speed` |
| `range` | 칸 | `range_bonus` |
| `max_hp_percent` | % | `hp_percent` |
| `block` / `armour` / `dodge` | 점 | `stat_bonus` |
| `res.<원소>` | 점 | `stat_bonus` |
| `summon_count` / `summon_power` / `summon_hp` / `summon_ticks` | 수 / % | `summon_extra`, `Summons.summon` |
| `reaction_percent` | % | `Reactions` 피해 |
| `bleed_tick` / `poison_tick` | +피해 | `Statuses.tick` |
| `heal_taken_percent` | % | `heal` |
| `will_save` | %p | 저주 주문 의지 판정 |

## 2. 쌓임(스택)

- 인물마다 `actor.stacks = {이름: {"n": int, "until": tick}}`.
- 행 정의: `{"stack": "rage", "add": 1, "max": 5, "until": "battle" | "action" | <tick 수> | "attack"}`.
  - `battle`: 전투 끝까지. `attack`: 내가 다음에 공격하면 사라짐. `<tick 수>`: 마지막으로 쌓인 뒤 그만큼 지나면 사라짐.
- 쌓임은 `modifier`의 곱 인자로 쓸 수 있다: `{"mod": "attack_percent", "per_stack": ["rage", 5]}`.
- `StoneEffects.battle_start`가 모두 비운다. 쌓임이 바뀔 때 알림(`+1 분노` 등)은 데이터의 `notice`로.
- 기존 `latch`(거머리)와 `raging`(놀)은 쌓임으로 옮긴다.

## 3. 데이터 형식

새 파일 `data/content/stone_effects.json`:

```json
{
  "version": 1,
  "effects": {
    "HOUND_EAR": {
      "name": "피 냄새",
      "text": "출혈 중인 대상에게 주는 피해 +20%",
      "keywords": ["출혈"],
      "rules": [
        {"when": "ALWAYS", "if": [{"target_has": "bleed"}], "mod": {"attack_percent": 20}}
      ]
    },
    "HOUND_NOSE": {
      "name": "사냥 본능",
      "text": "출혈 중인 대상을 처치하면 반경 1의 적에게 출혈",
      "keywords": ["출혈", "처치"],
      "rules": [
        {"when": "KILL", "if": [{"victim_had": "bleed"}], "do": [
          {"spread_status": "bleed", "radius": 1, "ticks": 300},
          {"notice": "전이!", "tone": "debuff"}
        ]}
      ]
    },
    "GRAVEKEEPER": {
      "name": "무덤 지기",
      "text": "전투마다 한 번, 쓰러질 피해를 받으면 HP 30%로 일어남",
      "keywords": ["죽음 유예"],
      "rules": [{"when": "LETHAL", "code": "revive_once", "args": {"percent": 30}}]
    }
  }
}
```

- 효과 하나 = `rules` 여러 줄. 한 줄 = `when` + `if` + (`mod` 또는 `do` 또는 `code`).
- 수치 값에는 곱 인자를 붙일 수 있다: `{"attack_percent": 10, "per_count": "adjacent_allies"}`(인접 동료 수만큼), `{"attack_percent": 5, "per_stack": ["rage", 1]}`(쌓임 수만큼), `{"speed": 3, "per_lost_hp": 10}`(잃은 체력 10%마다).
- `text`는 화면 문구 그대로. `keywords`는 영혼석 화면의 칩과 NPC 선호 점수(④)에 쓴다.
- `code`는 `StoneEffects.CODE` 표에 등록된 처리기 이름. 처리기 시그니처는 `func(s, owner, rule, context) -> void`.
- 조건 `victim_had`: `KILL`에서 쓰러지기 직전 대상의 상태(처치 분기에서 스냅샷).

## 4. 엔진 구조

| 파일 | 책임 |
| --- | --- |
| `expedition/progression/stone_effects.gd` | 공개 API 유지(`outgoing`, `incoming`, `crit_chance`, `delay`, `lethal`, `on_kill`, `round_start`, `shed`, …). 내부는 아래 모듈을 부른다. 공개 이름을 바꾸지 않아 호출부가 그대로다 |
| `expedition/progression/effect_engine.gd` (새) | 효과 행 읽기, `fire(s, when, ctx)`, `modifier(s, key, actor, ctx)`, 조건 평가, 결과 실행, 연쇄 깊이·한 번 규칙 |
| `expedition/progression/effect_conditions.gd` (새) | `if` 항목 평가(항목 하나 = 함수 하나) |
| `expedition/progression/effect_actions.gd` (새) | `do` 항목 실행 |
| `expedition/progression/effect_code.gd` (새) | 데이터로 적기 어려운 처리기(`revive_once`, `share_to_summons`, `death_delay` 등) |
| `expedition/progression/stacks.gd` (새) | 쌓임 읽기·쓰기·풀림 |
| `data/content/stone_effects.json` (새) | 효과 정의 |

### 4.1 `fire`

```
fire(s, when, ctx):
  if s.effect_depth >= 2: return
  s.effect_depth += 1
  for owner in owners_of(when, ctx):          # 그 사건의 주인(공격자, 피격자, 처치자, 반경 안 목격자…)
    for effect_id in StoneEffects.effects(owner):   # 슬롯 순서, 각 효과 한 번
      eligible = matching rules whose conditions are all true
      if eligible is empty: continue
      if not Reactions.once(s, owner, "fx:"+effect_id+":"+when): continue
      for rule in eligible: run(rule, owner, ctx)
  s.effect_depth -= 1
```

- `owners_of`: 사건 종류마다 정해진 역할의 인물. `DEATH_NEAR`, `DOT_TICK`처럼 "주변"이 주인인 사건은 반경 안의 살아 있는 인물 전부.
- 몬스터도 주인이 될 수 있다(자기 종족 대표 부위 효과, ④ §4).
- `s.effect_depth`는 세션 변수(기본 0). 행동이 시작될 때(`Reactions.begin_action`) 0으로 되돌린다.

### 4.2 `modifier`

```
modifier(s, key, actor, ctx) -> int:
  total = 0
  for owner in modifier_owners(actor, ctx): # 자신 + scope:allies 오라 + scope:summoner
    for effect_id in StoneEffects.effects(owner):
      for rule in rules(effect_id) where rule.when == "ALWAYS" and rule.mod has key:
        if scope and conditions match: add value(rule.mod[key], owner)
  collapse the same group (e.g. SKELETON_WALL) to its strongest contribution
  return total
```

- 역할 조합과 속성 세트(`TagSets`)의 보정은 이 단계에서 옮기지 않는다. `outgoing` 등에서 지금처럼 따로 더한다.
- 같은 키는 더한다(곱하지 않는다). 상한은 기존 규칙 그대로(속도 40, 막기 `BLOCK_CAP`, 치명 100).

### 4.3 기존 30개 옮기기

| 기존 처리 | 옮긴 모양 |
| --- | --- |
| 공격력 %(쥐, 오크, 코볼트, 놀, 강쥐, 화염·냉기) | `ALWAYS` + `mod.attack_percent` + 조건(`adjacent_allies`는 `per_count`, `ranged`, `self_hp_below`, `self_wet`, 원소) |
| 받는 피해 %(오크, 딱정벌레, 해골 병사) | `mod.taken_percent`, 해골 병사는 "인접 동료가 받을 때" → 조건 `owner_adjacent_to_target` |
| 상태 확률(거미, 골렘, 화염술사, 두꺼비, 서리, 원혼) | `HIT` + `chance` + `apply_status` + `notice` |
| 반격(도마뱀), 반사(망령 기사), 추가 사격(오크 투척병) | `STRUCK`/`HIT` + `chance` + `extra_damage`(반격은 `COUNTER` 형태 유지, 사격은 `code: second_shot`) |
| 처치 회복(구울), 처치 혼란(원혼) | `KILL` + `heal` / `apply_status`(반경) |
| 부활(묘지기) | `LETHAL` + `code: revive_once` |
| 기습(고블린), 달라붙기(거머리), 분노(놀) | `ATTACK` 조건 / 쌓임 |
| 사거리, 막기, 최대 HP, 속도, 소환 +1 | `mod` |
| 탈피(뱀) | `STATUS_TAKEN` + `chance` + `code: cancel_status` |
| 치유의 물결(물의 정령) | `ROUND_START` + `heal` |

## 5. 연쇄와 안전장치

- **깊이 2.** 1단계: 전투 사건 → 효과. 2단계: 효과가 만든 사건(상태를 걸었다, 처치했다) → 효과. 3단계는 없다.
- **한 행동 한 번.** 같은 인물의 같은 효과·같은 `when`은 `Reactions.once` 창 안에서 한 번.
- **2차 피해는 `HIT`/`ATTACK`/`CRIT`/부상을 부르지 않는다.** 다만 2차 피해로 처치하면 `KILL`은 부른다(깊이 규칙 안에서). "출혈 전이로 죽은 적이 또 전이"는 깊이 2에서 멈춘다.
- **결정론.** 모든 확률은 `CombatRules.roll(s, owner, other, "fx_"+effect_id, 100)`. 테스트는 `StoneEffects.force`로 고정한다(기존 방식).
- **알림.** 확률로 터진 효과, 상태를 건 효과, 쌓임 변화는 `notice`가 있어야 한다(데이터 검사 테스트가 확인).

## 6. 테스트

| 스위트 | 검사 |
| --- | --- |
| `tests/effect_engine.gd` (새) | 조건 항목 전부(항목마다 참·거짓 한 번), 결과 항목 전부, `modifier` 합산, 쌓임 네 가지 풀림 규칙, 깊이 2 제한, 한 행동 한 번, 2차 피해가 `HIT`을 부르지 않음, 결정론(같은 시드 같은 결과) |
| `tests/effect_data.gd` (새) | `stone_effects.json`의 모든 행이 사전의 단어만 쓰는지, `code`가 등록된 이름인지, 확률·상태 효과에 `notice`가 있는지, `text`가 비어 있지 않은지 |
| `tests/stone_effects.gd` | **바꾸지 않고** 통과(기존 30개 동작 보존) |
| `tests/crit.gd`, `tag_sets.gd`, `reactions.gd`, `wounds.gd` | 그대로 통과 |

## 7. 범위 밖

부위 효과 114개의 내용(③), 부위 영혼석 데이터와 화면(④), 역할 조합·속성 세트의 데이터화, AI가 효과를 고려해 행동을 고르는 것.

## 8. 후속 콘텐츠에서 검토할 결정

1. 연쇄 깊이 2가 충분한가(Achra는 사실상 무제한이지만 한 행동 한 번 규칙이 있다).
2. `DEATH_NEAR`·`DOT_TICK`의 반경(3, 2).
3. 효과 114개 중 `code` 처리기로 남길 수 있는 최대 개수(초안 목표: 24개 이하).
