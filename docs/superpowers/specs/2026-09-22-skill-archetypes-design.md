# 스킬 효과 유형 4종 · 규칙 봇 · 스킬 상대 가치 실험 설계

작성일: 2026-09-22 · 상태: 설계 확정 · 구현 계획: `docs/superpowers/plans/2026-09-22-skill-archetypes.md`
근거: [밸런스 방법론](../../balance-method.ko.md) §5 · 선행: [조우 시뮬레이터](2026-09-22-encounter-sim-design.md)

## 0. 목표와 원칙

1. 봇이 **스킬을 몰라도** 모든 스킬을 쓰게 한다: 주인공 봇이 동료와 같은 규칙 엔진(`Tactics.choose`)을 쓴다. 스킬별 봇 코드는 0줄.
2. 빠진 효과 유형 4개(단일 강타·원거리·회복·이동+타격)를 **시험용 최소 스킬**로 추가해, 규칙 엔진·실행기가 모든 유형을 다루는지 확인한다. 수치는 임시이며 이름에 '시험'을 붙인다.
3. 스킬 하나씩 장착한 기준 빌드로 아레나를 돌려 **상대 가치 표**(`docs/balance/skill-value.md`)를 만든다. 지배·사장은 **후보**로만 표시한다(방법론 §5).

범위 밖: 시험 스킬의 드롭·습득 경로(게임 내 획득 불가, 테스트 전용), 통로형 아레나, 탐색 봇, 실제 스킬 수치 확정.

## 1. 스킬 정의 확장 (`expedition/abilities.gd`)

`DEFINITIONS` 각 항목에 세 필드를 추가한다.

| 필드 | 값 | 의미 |
| --- | --- | --- |
| `effect` | `DAMAGE` / `SHIELD` / `HEAL` / `LUNGE` | 실행기 분기 |
| `axis` | `MELEE` / `RANGED` / `MAGIC` / `""` | `Growth.power` 축 (기존 BOMB=RANGED, SHOCKWAVE=MAGIC 하드코딩을 데이터로) |
| `rule_when` | `ALWAYS` / `HP` / `DANGER` | 기본 규칙의 조건 (기존 IRON_HIDE=DANGER 하드코딩을 데이터로) |

기존 3개: SHOCKWAVE `DAMAGE/MAGIC/ALWAYS`, BOMB `DAMAGE/RANGED/ALWAYS`, IRON_HIDE `SHIELD/""/DANGER`. 동작 변화 없음.

시험 스킬 4개(`item`은 "시험용 …" 표기, `description` 한 줄):

| id | name | target | range | radius | damage/heal | cooldown | effect | axis | rule_when |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `HEAVY_STRIKE` | 시험 강타 | ENEMY | 1 | 0 | damage 28 | 3 | DAMAGE | MELEE | ALWAYS |
| `THROWING_KNIFE` | 시험 투척 | ENEMY | 4 | 0 | damage 10 | 1 | DAMAGE | RANGED | ALWAYS |
| `FIELD_DRESSING` | 시험 응급처치 | SELF | 0 | 0 | heal 15 | 4 | HEAL | "" | HP |
| `LUNGE` | 시험 돌진 | ENEMY | 3 | 0 | damage 12 | 3 | LUNGE | MELEE | ALWAYS |

실행 규칙:
- `DAMAGE`: 기존 경로(`cells` → `damage`). radius 0이면 대상 칸 하나. `power = Growth.power(actor, axis, damage)`.
- `SHIELD`: 기존 `iron_guard`.
- `HEAL`: `actor.hp = min(max_hp, hp + heal)`, `Body.heal(actor)`. `legal`은 SELF이고 `hp < max_hp`일 때만.
- `LUNGE`: `lunge_cell(s, actor, target)` = 대상에 `melee_reach`하는 빈 칸 중 `can_step` 경로 길이(칸 수) ≤ `range`인 가장 가까운 칸(동률이면 `str(cell)` 순). 없으면 불법. 실행: 그 칸으로 이동 후 `damage(target, Growth.power(actor,"MELEE",damage), actor.id, "SLASH")`. 이동 이펙트는 남기지 않는다.
- 모든 스킬은 `cooldowns[id] = cooldown+1`, 로그 `actor.name · def.name`. `effects`에는 DAMAGE/LUNGE만 `ENEMY_ATTACK`류 표식을 남긴다(기존과 동일).

`Abilities.default_rule(id) -> Dictionary` = `Rules.make_rule(id, "SELF" if target == SELF else "NEAREST", rule_when)`. `session.gd`의 `reset_rules`·`consume_essence` 두 곳이 이것을 쓴다(하드코딩 제거).

## 2. 규칙 카탈로그 (`expedition/tactic_rules.gd`)

`SKILLS`에 추가: `HEAVY_STRIKE`·`THROWING_KNIFE`·`LUNGE` = `targets ["NEAREST","LOWEST_HP"]`, `conditions ["ALWAYS","HP","STATUS","CHARGING","DANGER"]`; `FIELD_DRESSING` = `targets ["SELF"]`, `conditions ["ALWAYS","HP","STATUS","DANGER"]`. `make_rule`의 기본 `subject`는 SELF 대상 스킬이면 `"SELF"`, 아니면 `"TARGET"`(응급처치 HP 조건이 자신 체력을 보게).

`Tactics.choose`는 변경하지 않는다. 단, 이능 후보 생성의 "피해 스킬은 셀 안에 적이 있어야" 검사는 `def.effect == "DAMAGE"`로 바꾼다(LUNGE는 대상이 적이므로 별도 검사 불필요, HEAL/SHIELD는 SELF).

UI: `board.gd`의 예약 배지 텍스트 사전에 네 이름 추가, `main.gd` 가방 아이콘은 기존 폴백(`Art.item(5)`) 사용. 시험 스킬은 적 드롭 목록(`essence_id`)에 넣지 않는다.

## 3. 봇 정책 `rules` (`expedition/sim/bot_policy.gd`)

`step(s, "rules")`: 적이 보이지 않으면 기존 접근 단계; 보이면 `var choice = s.Tactics.choose(s, hero)` → `s.act(choice.kind, choice.cell)` → 반환값은 `choice.kind`(`ATTACK`/`MOVE`/`WAIT`/`GUARD`/`PUSH`/이능 id). 회복 물약·붕대는 이 정책에서 쓰지 않는다(스킬 가치를 물약이 가리지 않게). `simple`/`tactical`은 그대로.

실행기(`encounter_runner.gd`): `run_one` 결과에 `skill_uses: {kind: count}`(이능 id와 `PUSH`/`GUARD`만 집계), `run_many`에 `skill_uses_mean: {kind: 평균}`.

## 4. 기준 빌드 (`data/content/reference_builds.json`)

기존 `starter`·`melee_1` 유지 + 7개 추가. 모두 `ranks {"MELEE":1}`, 두 번째 장착 칸은 `GUARD`, `rules`는 `[[skill,target,when], …]`(첫 규칙이 장착 스킬, 둘째가 `GUARD SELF HP`):

| id | equipped | learned | rules |
| --- | --- | --- | --- |
| `b_strike` | HEAVY_STRIKE, GUARD | HEAVY_STRIKE | [HEAVY_STRIKE NEAREST ALWAYS], [GUARD SELF HP] |
| `b_knife` | THROWING_KNIFE, GUARD | THROWING_KNIFE | [THROWING_KNIFE NEAREST ALWAYS], [GUARD SELF HP] |
| `b_dressing` | FIELD_DRESSING, GUARD | FIELD_DRESSING | [FIELD_DRESSING SELF HP], [GUARD SELF HP] |
| `b_lunge` | LUNGE, GUARD | LUNGE | [LUNGE NEAREST ALWAYS], [GUARD SELF HP] |
| `b_bomb` | BOMB, GUARD | BOMB | [BOMB NEAREST ALWAYS], [GUARD SELF HP] |
| `b_shockwave` | SHOCKWAVE, GUARD | SHOCKWAVE | [SHOCKWAVE SELF ALWAYS], [GUARD SELF HP] |
| `b_iron` | IRON_HIDE, GUARD | IRON_HIDE | [IRON_HIDE SELF DANGER], [GUARD SELF HP] |

`melee_1`에 `rules [[PUSH NEAREST CHARGING],[GUARD SELF HP]]`를 명시한다(현행 기본과 동일). `apply_build`는 `rules`가 있으면 `actor.rules`를 그것으로 교체한다.

## 5. 실험 `skill_value` (`data/content/balance_experiments.json`, 도구 `tests/skill_value.gd`)

```json
"skill_value": {"seed_set": {"id": "S2", "start": 5000, "count": 60},
  "party_sizes": [1, 3], "builds": ["melee_1","b_strike","b_knife","b_dressing","b_lunge","b_bomb","b_shockwave","b_iron"],
  "policies": ["rules"], "rules": {"current": {"solo_actions": 1, "solo_max_members": 0}},
  "supplies": [0, 0, 0, 0, 0, 0], "baseline_build": "melee_1", "arenas": "<action_economy와 동일 6개>"}
```
물자는 0(스킬 가치를 물약이 가리지 않게). 8빌드 × 6아레나 × 2인원 × 60시드 = 5,760전투.

보고서 `docs/balance/skill-value.md` + `.json`:
1. 머리말(커밋·날짜·시드·규칙·물자 0·정책 `rules`·결정론 문장).
2. 표 1 — 빌드 × 인원 × 아레나: 승률[CI], 평균 개인별 피해, 평균 라운드, **스킬 사용 평균**(장착 스킬), 방어 사용 평균.
3. 표 2 — 기준선(`melee_1`) 대비 Δ: 같은 인원·아레나에서 Δ승률(pp), Δ피해. 빌드별 요약: Δ승률 평균, 6아레나 중 우세/열세 수.
4. 후보 판정(§5 방법론): **지배 후보** = 1인에서 6아레나 중 ≥4에서 Δ승률 ≥ +20pp; **사장 후보** = 장착 스킬 사용 평균 < 0.2/전투(→ "봇이 못 씀"으로 표기, 원인 추적 필요) 또는 모든 아레나에서 Δ승률 ≤ 0 이고 Δ피해 ≥ 0(→ "약함 후보"). 판정은 후보이며 확정이 아니라는 문장을 포함.
5. 발견 사항: 사용 0회 스킬은 `legal`/규칙 조건/사거리 중 어디서 막혔는지 도구가 한 줄로 추정해 기록(같은 아레나에서 `Abilities.legal`이 참이 된 라운드 수를 세어 "합법이었으나 규칙이 고르지 않음" vs "합법인 적 없음" 구분).

## 6. 검증

- `tests/skill_archetypes.gd`(CI): 4스킬 각각 `legal`·`execute` 동작(강타 피해·쿨다운, 투척 사거리 4·벽 뒤 불가, 응급처치 만혈 시 불법·15 회복·쿨다운 4, 돌진 이동+피해·경로 없으면 불법·사거리 초과 불법), `default_rule`이 `rule_when`을 따름, `reset_rules`/`consume_essence`가 같은 규칙을 만듦, 기존 3스킬 동작 동일(폭탄·충격파 피해 수치, 철갑), `Rules.valid`가 새 규칙을 받아들임, `Tactics.choose`가 각 빌드에서 장착 스킬을 후보로 냄.
- `tests/encounter_sim.gd` 확장: `rules` 정책이 `early_hob`에서 `b_strike`로 HEAVY_STRIKE를 ≥1회 사용, `b_dressing`이 HP 50% 이하에서만 응급처치, `skill_uses` 집계, 결정론.
- 기존 스위트 회귀 없음(알려진 사전 실패 2개 제외). `tests/skill_value.gd`는 수동(CI 제외), 실행 시간 기록.
