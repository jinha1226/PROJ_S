# 스킬 가치 실험 결과

생성: `tests/skill_value.gd`(수동 도구) · 커밋 `fd25e19` · 날짜 2026-09-22
근거: [밸런스 방법론](../balance-method.ko.md) §5 · 설계: [스킬 원형 설계](../superpowers/specs/2026-09-22-skill-archetypes-design.md) §5

**몬스터 파츠 도입 후 첫 측정.** 적도 자기 시그니처 파츠를 예고하고 쓰는 환경에서 전 빌드를 다시 잰 결과다 — 이전 보고서의 수치와 직접 비교하지 않는다. 게이트 판정은 [파츠 밸런스 게이트](parts-gates.md)에 있다.

- 시드 묶음: `S2` 60개 (5000~5059)
- 규칙: `current` (`solo_actions 1` / `solo_max_members 0`) 하나만 쓴다 — 이번 실험의 축은 빌드다.
- 봇 정책: `rules` — 영웅이 동료와 같은 규칙 목록(`expedition/tactic_rules.gd`)을 읽고 `Tactics.choose`가 고른 행동을 그대로 누른다.
- **물자 0**: `supplies [0, 0, 0, 0, 0, 0]`. 회복품이 없으므로 스킬의 값이 물약에 가려지지 않는다.
- 솔로 HP 스케일: `SOLO_HP_PERCENT 45` / `SOLO_HP_MIN 20` / `SOLO_HP_MAX 32` (파티 인원 1일 때만 적용, 실험 조건의 일부)
- 아레나 공통 spec: size 20 · room [5, 5, 9, 9] · door [9, 4] · pillars [[8, 8], [10, 10]] · party_entry [9, 5] · light 90 · supplies [0, 0, 0, 0, 0, 0]
- 행렬: 빌드 16 × 인원 2 × 아레나 6 × 시드 60 = 11520전투
- 실행 시간: 347.3초

> 전투의 명중 판정은 없다. 같은 커밋·같은 시드·같은 빌드는 같은 전투를 낸다 — 표의 모든 칸은 재실행으로 그대로 재현된다. 시드는 적 배치와 부상 부위 선택에만 영향을 준다.
> `사용 평균`은 그 빌드의 첫 장착 스킬을 한 전투에서 누른 횟수의 평균이다(누르지 않은 전투는 0으로 센다).
> `distinct`는 시드 묶음에서 나온 서로 다른 `(결과, 라운드, 피해)` 조합의 수다.

이 파이프라인이 찾아낸 사전 수정: HEAVY_STRIKE(사거리 1)가 대각선 인접 적에게 불법이던 문제 — `Abilities.legal`이 사거리 1 스킬에 맨해튼 거리 대신 `melee_reach`를 쓰도록 고쳤다(Task 2). 기본 공격이 닿는 칸에 강타가 닿지 않는 상태에서는 사용 평균이 스킬의 값이 아니라 기하의 사고를 재던 셈이다.

빌드 구성:

| 빌드 | 장착 | 규칙 |
| --- | --- | --- |
| `melee_1` | PUSH, GUARD | PUSH→NEAREST(CHARGING), GUARD→ALLY(ALLY_LETHAL) |
| `b_strike` | HEAVY_STRIKE, GUARD | HEAVY_STRIKE→NEAREST(ALWAYS), GUARD→ALLY(ALLY_LETHAL) |
| `b_knife` | THROWING_KNIFE, GUARD | THROWING_KNIFE→NEAREST(ALWAYS), GUARD→ALLY(ALLY_LETHAL) |
| `b_dressing` | FIELD_DRESSING, GUARD | FIELD_DRESSING→SELF(HP), GUARD→ALLY(ALLY_LETHAL) |
| `b_lunge` | LUNGE, GUARD | LUNGE→NEAREST(ALWAYS), GUARD→ALLY(ALLY_LETHAL) |
| `b_bomb` | BOMB, GUARD | BOMB→NEAREST(ALWAYS), GUARD→ALLY(ALLY_LETHAL) |
| `b_shockwave` | SHOCKWAVE, GUARD | SHOCKWAVE→SELF(ALWAYS), GUARD→ALLY(ALLY_LETHAL) |
| `b_iron` | IRON_HIDE, GUARD | IRON_HIDE→SELF(DANGER), GUARD→ALLY(ALLY_LETHAL) |
| `p_rat` | RAT_GNAW, GUARD | RAT_GNAW→NEAREST(ALWAYS), GUARD→ALLY(ALLY_LETHAL) |
| `p_lizard` | LIZARD_TAIL, GUARD | LIZARD_TAIL→NEAREST(ALWAYS), GUARD→ALLY(ALLY_LETHAL) |
| `p_kobold` | KOBOLD_SLING, GUARD | KOBOLD_SLING→NEAREST(ALWAYS), GUARD→ALLY(ALLY_LETHAL) |
| `p_goblin` | GOBLIN_SHIV, GUARD | GOBLIN_SHIV→NEAREST(ALWAYS), GUARD→ALLY(ALLY_LETHAL) |
| `p_hob` | HOB_CLUB, GUARD | HOB_CLUB→NEAREST(ALWAYS), GUARD→ALLY(ALLY_LETHAL) |
| `p_orc` | ORC_CLEAVER, GUARD | ORC_CLEAVER→NEAREST(ALWAYS), GUARD→ALLY(ALLY_LETHAL) |
| `p_gnoll` | GNOLL_SPEAR, GUARD | GNOLL_SPEAR→NEAREST(ALWAYS), GUARD→ALLY(ALLY_LETHAL) |
| `p_river` | RIVER_RAT_SPLASH, GUARD | RIVER_RAT_SPLASH→NEAREST(ALWAYS), GUARD→ALLY(ALLY_LETHAL) |

아레나 구성:

| 아레나 | 티어 | 구성 |
| --- | --- | --- |
| `early_hob` | early | dcss_hobgoblin/MELEE |
| `early_pair` | early | kobold/MELEE, dcss_rat/MELEE |
| `deep_mixed` | deep | dcss_hobgoblin/MELEE, goblin/RANGED, kobold/MELEE |
| `deep_caster` | deep | dcss_orc/MELEE, goblin/CASTER |
| `opt_archers` | optional | kobold/RANGED, goblin/RANGED, dcss_rat/MELEE |
| `opt_gnoll` | optional | dcss_gnoll/MELEE, dcss_rat/MELEE, dcss_rat/MELEE |

## 표 1 — 빌드 × 인원 × 아레나

| 빌드 | 인원 | 아레나 | 티어 | 승률 [95% CI] | 평균 피해(개인별) | 평균 라운드 | 장착 스킬 | 사용 평균 | 방어 사용 평균 | distinct |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `melee_1` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 14.0 | 10.0 | PUSH | 0.00 | 0.00 | 1 |
| `melee_1` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 15.3 | 11.5 | PUSH | 0.00 | 0.00 | 5 |
| `melee_1` | 1 | `deep_mixed` | deep | 0.00 [0.00, 0.06] | 51.8 | 10.0 | PUSH | 0.00 | 0.00 | 14 |
| `melee_1` | 1 | `deep_caster` | deep | 0.65 [0.52, 0.76] | 49.9 | 12.9 | PUSH | 0.27 | 0.00 | 6 |
| `melee_1` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 47.4 | 6.3 | PUSH | 0.00 | 0.00 | 8 |
| `melee_1` | 1 | `opt_gnoll` | optional | 0.97 [0.89, 0.99] | 28.9 | 16.4 | PUSH | 0.03 | 0.00 | 20 |
| `b_strike` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 7.0 | 9.0 | HEAVY_STRIKE | 1.00 | 0.00 | 1 |
| `b_strike` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 16.2 | 11.3 | HEAVY_STRIKE | 2.00 | 0.00 | 4 |
| `b_strike` | 1 | `deep_mixed` | deep | 0.30 [0.20, 0.43] | 40.6 | 10.4 | HEAVY_STRIKE | 1.47 | 0.00 | 16 |
| `b_strike` | 1 | `deep_caster` | deep | 0.38 [0.27, 0.51] | 45.4 | 11.1 | HEAVY_STRIKE | 1.03 | 0.00 | 6 |
| `b_strike` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 48.0 | 6.7 | HEAVY_STRIKE | 0.87 | 0.00 | 7 |
| `b_strike` | 1 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 16.6 | 13.8 | HEAVY_STRIKE | 2.23 | 0.00 | 10 |
| `b_knife` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 0.0 | 7.0 | THROWING_KNIFE | 1.00 | 0.00 | 1 |
| `b_knife` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 5.2 | 10.4 | THROWING_KNIFE | 3.18 | 0.00 | 4 |
| `b_knife` | 1 | `deep_mixed` | deep | 0.07 [0.03, 0.16] | 51.4 | 10.4 | THROWING_KNIFE | 2.92 | 0.00 | 11 |
| `b_knife` | 1 | `deep_caster` | deep | 0.83 [0.72, 0.91] | 46.0 | 13.6 | THROWING_KNIFE | 3.40 | 0.00 | 5 |
| `b_knife` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 49.0 | 6.1 | THROWING_KNIFE | 1.20 | 0.00 | 7 |
| `b_knife` | 1 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 15.6 | 15.8 | THROWING_KNIFE | 4.93 | 0.00 | 17 |
| `b_dressing` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 14.0 | 10.0 | FIELD_DRESSING | 0.00 | 0.00 | 1 |
| `b_dressing` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 16.4 | 12.0 | FIELD_DRESSING | 0.28 | 0.00 | 5 |
| `b_dressing` | 1 | `deep_mixed` | deep | 0.00 [0.00, 0.06] | 65.8 | 11.6 | FIELD_DRESSING | 1.10 | 0.00 | 13 |
| `b_dressing` | 1 | `deep_caster` | deep | 0.73 [0.61, 0.83] | 68.5 | 15.1 | FIELD_DRESSING | 1.57 | 0.00 | 6 |
| `b_dressing` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 58.8 | 6.9 | FIELD_DRESSING | 0.95 | 0.00 | 10 |
| `b_dressing` | 1 | `opt_gnoll` | optional | 0.97 [0.89, 0.99] | 35.3 | 18.0 | FIELD_DRESSING | 0.72 | 0.00 | 19 |
| `b_lunge` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 7.0 | 9.0 | LUNGE | 1.00 | 0.00 | 1 |
| `b_lunge` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 18.9 | 12.0 | LUNGE | 2.00 | 0.00 | 6 |
| `b_lunge` | 1 | `deep_mixed` | deep | 0.10 [0.05, 0.20] | 48.6 | 10.3 | LUNGE | 1.80 | 0.00 | 15 |
| `b_lunge` | 1 | `deep_caster` | deep | 0.43 [0.32, 0.56] | 47.8 | 11.5 | LUNGE | 1.40 | 0.00 | 5 |
| `b_lunge` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 48.2 | 6.4 | LUNGE | 0.95 | 0.00 | 9 |
| `b_lunge` | 1 | `opt_gnoll` | optional | 0.93 [0.84, 0.97] | 27.5 | 16.2 | LUNGE | 2.97 | 0.00 | 16 |
| `b_bomb` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 0.0 | 7.0 | BOMB | 1.00 | 0.00 | 1 |
| `b_bomb` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 5.2 | 9.7 | BOMB | 1.10 | 0.00 | 4 |
| `b_bomb` | 1 | `deep_mixed` | deep | 0.40 [0.29, 0.53] | 50.2 | 11.4 | BOMB | 1.72 | 0.00 | 14 |
| `b_bomb` | 1 | `deep_caster` | deep | 0.97 [0.89, 0.99] | 28.9 | 11.2 | BOMB | 1.35 | 0.00 | 5 |
| `b_bomb` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 47.9 | 6.0 | BOMB | 0.72 | 0.00 | 7 |
| `b_bomb` | 1 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 12.6 | 12.3 | BOMB | 1.80 | 0.00 | 16 |
| `b_shockwave` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 14.0 | 10.0 | SHOCKWAVE | 1.00 | 0.00 | 1 |
| `b_shockwave` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 11.5 | 11.3 | SHOCKWAVE | 2.00 | 0.00 | 4 |
| `b_shockwave` | 1 | `deep_mixed` | deep | 0.25 [0.16, 0.37] | 51.1 | 10.4 | SHOCKWAVE | 1.37 | 0.00 | 16 |
| `b_shockwave` | 1 | `deep_caster` | deep | 0.65 [0.52, 0.76] | 44.1 | 11.4 | SHOCKWAVE | 1.30 | 0.00 | 6 |
| `b_shockwave` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 47.4 | 6.3 | SHOCKWAVE | 0.90 | 0.00 | 8 |
| `b_shockwave` | 1 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 19.7 | 13.7 | SHOCKWAVE | 2.35 | 0.00 | 14 |
| `b_iron` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 15.0 | 11.0 | IRON_HIDE | 1.00 | 0.00 | 1 |
| `b_iron` | 1 | `early_pair` | early | 0.92 [0.82, 0.96] | 34.5 | 19.0 | IRON_HIDE | 3.25 | 0.00 | 5 |
| `b_iron` | 1 | `deep_mixed` | deep | 0.00 [0.00, 0.06] | 49.7 | 10.9 | IRON_HIDE | 1.47 | 0.00 | 15 |
| `b_iron` | 1 | `deep_caster` | deep | 0.53 [0.41, 0.65] | 48.8 | 15.1 | IRON_HIDE | 2.00 | 0.00 | 6 |
| `b_iron` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 47.5 | 6.9 | IRON_HIDE | 0.78 | 0.00 | 10 |
| `b_iron` | 1 | `opt_gnoll` | optional | 0.43 [0.32, 0.56] | 46.0 | 22.4 | IRON_HIDE | 4.17 | 0.00 | 19 |
| `p_rat` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 14.0 | 10.0 | RAT_GNAW | 1.00 | 0.00 | 1 |
| `p_rat` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 15.3 | 11.5 | RAT_GNAW | 2.00 | 0.00 | 5 |
| `p_rat` | 1 | `deep_mixed` | deep | 0.00 [0.00, 0.06] | 51.6 | 9.9 | RAT_GNAW | 1.43 | 0.00 | 13 |
| `p_rat` | 1 | `deep_caster` | deep | 0.17 [0.09, 0.28] | 47.7 | 10.8 | RAT_GNAW | 1.38 | 0.00 | 5 |
| `p_rat` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 47.4 | 6.3 | RAT_GNAW | 0.78 | 0.00 | 8 |
| `p_rat` | 1 | `opt_gnoll` | optional | 0.95 [0.86, 0.98] | 35.4 | 17.6 | RAT_GNAW | 3.50 | 0.00 | 20 |
| `p_lizard` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 14.0 | 10.0 | LIZARD_TAIL | 1.00 | 0.00 | 1 |
| `p_lizard` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 11.3 | 10.8 | LIZARD_TAIL | 1.43 | 0.00 | 5 |
| `p_lizard` | 1 | `deep_mixed` | deep | 0.00 [0.00, 0.06] | 50.3 | 9.4 | LIZARD_TAIL | 1.10 | 0.00 | 13 |
| `p_lizard` | 1 | `deep_caster` | deep | 0.17 [0.09, 0.28] | 47.7 | 10.8 | LIZARD_TAIL | 1.22 | 0.00 | 5 |
| `p_lizard` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 47.4 | 6.3 | LIZARD_TAIL | 0.78 | 0.00 | 8 |
| `p_lizard` | 1 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 26.2 | 16.2 | LIZARD_TAIL | 2.73 | 0.00 | 15 |
| `p_kobold` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 0.0 | 9.0 | KOBOLD_SLING | 2.00 | 0.00 | 1 |
| `p_kobold` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 5.0 | 10.5 | KOBOLD_SLING | 2.20 | 0.00 | 4 |
| `p_kobold` | 1 | `deep_mixed` | deep | 0.00 [0.00, 0.06] | 51.2 | 10.1 | KOBOLD_SLING | 2.20 | 0.00 | 14 |
| `p_kobold` | 1 | `deep_caster` | deep | 0.83 [0.72, 0.91] | 46.8 | 14.2 | KOBOLD_SLING | 3.18 | 0.00 | 6 |
| `p_kobold` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 49.0 | 6.1 | KOBOLD_SLING | 1.10 | 0.00 | 7 |
| `p_kobold` | 1 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 26.2 | 17.4 | KOBOLD_SLING | 4.17 | 0.00 | 19 |
| `p_goblin` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 7.0 | 9.0 | GOBLIN_SHIV | 1.00 | 0.00 | 1 |
| `p_goblin` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 18.3 | 11.7 | GOBLIN_SHIV | 1.82 | 0.00 | 6 |
| `p_goblin` | 1 | `deep_mixed` | deep | 0.10 [0.05, 0.20] | 48.5 | 9.8 | GOBLIN_SHIV | 1.62 | 0.00 | 15 |
| `p_goblin` | 1 | `deep_caster` | deep | 0.47 [0.35, 0.59] | 47.4 | 11.4 | GOBLIN_SHIV | 1.40 | 0.00 | 6 |
| `p_goblin` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 48.2 | 6.4 | GOBLIN_SHIV | 0.95 | 0.00 | 9 |
| `p_goblin` | 1 | `opt_gnoll` | optional | 0.93 [0.84, 0.97] | 26.5 | 15.9 | GOBLIN_SHIV | 2.93 | 0.00 | 16 |
| `p_hob` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 12.0 | 10.0 | HOB_CLUB | 1.00 | 0.00 | 1 |
| `p_hob` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 13.0 | 11.5 | HOB_CLUB | 2.00 | 0.00 | 5 |
| `p_hob` | 1 | `deep_mixed` | deep | 0.00 [0.00, 0.06] | 49.4 | 10.5 | HOB_CLUB | 1.40 | 0.00 | 13 |
| `p_hob` | 1 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 45.2 | 13.4 | HOB_CLUB | 1.65 | 0.00 | 5 |
| `p_hob` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 42.4 | 6.4 | HOB_CLUB | 0.78 | 0.00 | 7 |
| `p_hob` | 1 | `opt_gnoll` | optional | 0.97 [0.89, 0.99] | 27.3 | 16.8 | HOB_CLUB | 2.92 | 0.00 | 20 |
| `p_orc` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 14.0 | 10.0 | ORC_CLEAVER | 1.00 | 0.00 | 1 |
| `p_orc` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 9.8 | 10.7 | ORC_CLEAVER | 1.43 | 0.00 | 5 |
| `p_orc` | 1 | `deep_mixed` | deep | 0.30 [0.20, 0.43] | 50.6 | 10.3 | ORC_CLEAVER | 1.17 | 0.00 | 14 |
| `p_orc` | 1 | `deep_caster` | deep | 0.83 [0.72, 0.91] | 47.7 | 11.4 | ORC_CLEAVER | 1.03 | 0.00 | 6 |
| `p_orc` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 47.4 | 6.3 | ORC_CLEAVER | 0.78 | 0.00 | 8 |
| `p_orc` | 1 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 17.6 | 13.5 | ORC_CLEAVER | 2.33 | 0.00 | 14 |
| `p_gnoll` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 14.0 | 10.0 | GNOLL_SPEAR | 1.00 | 0.00 | 1 |
| `p_gnoll` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 12.1 | 11.4 | GNOLL_SPEAR | 2.00 | 0.00 | 4 |
| `p_gnoll` | 1 | `deep_mixed` | deep | 0.28 [0.19, 0.41] | 66.3 | 12.6 | GNOLL_SPEAR | 1.97 | 0.00 | 16 |
| `p_gnoll` | 1 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 52.0 | 14.0 | GNOLL_SPEAR | 1.87 | 0.00 | 6 |
| `p_gnoll` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 52.6 | 6.7 | GNOLL_SPEAR | 0.95 | 0.00 | 7 |
| `p_gnoll` | 1 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 26.5 | 16.6 | GNOLL_SPEAR | 2.92 | 0.00 | 20 |
| `p_river` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 7.0 | 10.0 | RIVER_RAT_SPLASH | 1.00 | 0.00 | 1 |
| `p_river` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 4.5 | 9.9 | RIVER_RAT_SPLASH | 1.33 | 0.00 | 5 |
| `p_river` | 1 | `deep_mixed` | deep | 0.00 [0.00, 0.06] | 51.0 | 9.3 | RIVER_RAT_SPLASH | 1.33 | 0.00 | 10 |
| `p_river` | 1 | `deep_caster` | deep | 0.43 [0.32, 0.56] | 49.0 | 13.1 | RIVER_RAT_SPLASH | 1.75 | 0.00 | 5 |
| `p_river` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 47.4 | 6.1 | RIVER_RAT_SPLASH | 0.95 | 0.00 | 9 |
| `p_river` | 1 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 18.8 | 15.9 | RIVER_RAT_SPLASH | 2.77 | 0.00 | 15 |
| `melee_1` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 1.8 | 8.6 | PUSH | 0.00 | 0.00 | 9 |
| `melee_1` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 3.0 | 8.8 | PUSH | 0.00 | 0.00 | 15 |
| `melee_1` | 3 | `deep_mixed` | deep | 0.98 [0.91, 1.00] | 17.6 | 11.0 | PUSH | 0.02 | 0.07 | 47 |
| `melee_1` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 11.2 | 11.9 | PUSH | 0.68 | 0.00 | 30 |
| `melee_1` | 3 | `opt_archers` | optional | 0.93 [0.84, 0.97] | 24.2 | 12.8 | PUSH | 0.00 | 0.03 | 39 |
| `melee_1` | 3 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 12.6 | 13.4 | PUSH | 0.00 | 0.00 | 55 |
| `b_strike` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 4.3 | 7.9 | HEAVY_STRIKE | 1.00 | 0.00 | 3 |
| `b_strike` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 3.4 | 7.7 | HEAVY_STRIKE | 0.93 | 0.00 | 11 |
| `b_strike` | 3 | `deep_mixed` | deep | 1.00 [0.94, 1.00] | 16.9 | 9.5 | HEAVY_STRIKE | 1.15 | 0.03 | 42 |
| `b_strike` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 10.6 | 9.6 | HEAVY_STRIKE | 1.00 | 0.00 | 19 |
| `b_strike` | 3 | `opt_archers` | optional | 1.00 [0.94, 1.00] | 20.1 | 11.3 | HEAVY_STRIKE | 1.15 | 0.12 | 30 |
| `b_strike` | 3 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 11.7 | 10.7 | HEAVY_STRIKE | 1.57 | 0.10 | 45 |
| `b_knife` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 2.6 | 10.1 | THROWING_KNIFE | 2.80 | 0.00 | 7 |
| `b_knife` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 1.1 | 8.6 | THROWING_KNIFE | 2.25 | 0.00 | 8 |
| `b_knife` | 3 | `deep_mixed` | deep | 1.00 [0.94, 1.00] | 20.2 | 12.6 | THROWING_KNIFE | 3.95 | 0.03 | 50 |
| `b_knife` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 11.6 | 11.6 | THROWING_KNIFE | 3.27 | 0.00 | 19 |
| `b_knife` | 3 | `opt_archers` | optional | 1.00 [0.94, 1.00] | 23.3 | 12.1 | THROWING_KNIFE | 3.63 | 0.12 | 34 |
| `b_knife` | 3 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 11.2 | 15.2 | THROWING_KNIFE | 4.90 | 0.00 | 49 |
| `b_dressing` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 2.1 | 8.6 | FIELD_DRESSING | 0.00 | 0.00 | 8 |
| `b_dressing` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 2.4 | 8.3 | FIELD_DRESSING | 0.00 | 0.00 | 12 |
| `b_dressing` | 3 | `deep_mixed` | deep | 1.00 [0.94, 1.00] | 18.3 | 11.2 | FIELD_DRESSING | 0.37 | 0.00 | 49 |
| `b_dressing` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 16.8 | 10.8 | FIELD_DRESSING | 0.33 | 0.00 | 34 |
| `b_dressing` | 3 | `opt_archers` | optional | 0.97 [0.89, 0.99] | 24.8 | 13.1 | FIELD_DRESSING | 0.62 | 0.00 | 34 |
| `b_dressing` | 3 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 12.8 | 12.5 | FIELD_DRESSING | 0.08 | 0.00 | 51 |
| `b_lunge` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 0.7 | 7.9 | LUNGE | 1.00 | 0.00 | 4 |
| `b_lunge` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 3.1 | 7.5 | LUNGE | 1.00 | 0.00 | 11 |
| `b_lunge` | 3 | `deep_mixed` | deep | 1.00 [0.94, 1.00] | 17.4 | 9.9 | LUNGE | 1.45 | 0.18 | 43 |
| `b_lunge` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 14.1 | 9.1 | LUNGE | 1.18 | 0.05 | 22 |
| `b_lunge` | 3 | `opt_archers` | optional | 1.00 [0.94, 1.00] | 17.6 | 9.8 | LUNGE | 1.75 | 0.00 | 33 |
| `b_lunge` | 3 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 11.1 | 10.7 | LUNGE | 1.98 | 0.00 | 46 |
| `b_bomb` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 3.2 | 8.9 | BOMB | 1.00 | 0.00 | 6 |
| `b_bomb` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 1.9 | 7.9 | BOMB | 0.77 | 0.00 | 14 |
| `b_bomb` | 3 | `deep_mixed` | deep | 1.00 [0.94, 1.00] | 12.0 | 9.8 | BOMB | 1.25 | 0.00 | 45 |
| `b_bomb` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 12.4 | 10.3 | BOMB | 0.92 | 0.00 | 26 |
| `b_bomb` | 3 | `opt_archers` | optional | 0.93 [0.84, 0.97] | 20.8 | 10.4 | BOMB | 1.33 | 0.10 | 36 |
| `b_bomb` | 3 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 7.9 | 11.1 | BOMB | 1.00 | 0.00 | 38 |
| `b_shockwave` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 2.1 | 8.6 | SHOCKWAVE | 0.00 | 0.00 | 8 |
| `b_shockwave` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 2.4 | 8.3 | SHOCKWAVE | 0.18 | 0.00 | 12 |
| `b_shockwave` | 3 | `deep_mixed` | deep | 1.00 [0.94, 1.00] | 17.2 | 10.8 | SHOCKWAVE | 0.18 | 0.03 | 47 |
| `b_shockwave` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 17.0 | 10.5 | SHOCKWAVE | 0.07 | 0.00 | 31 |
| `b_shockwave` | 3 | `opt_archers` | optional | 0.90 [0.80, 0.95] | 23.6 | 12.6 | SHOCKWAVE | 0.22 | 0.07 | 37 |
| `b_shockwave` | 3 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 12.2 | 12.7 | SHOCKWAVE | 0.07 | 0.13 | 49 |
| `b_iron` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 2.6 | 9.6 | IRON_HIDE | 1.00 | 0.00 | 20 |
| `b_iron` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 5.8 | 10.3 | IRON_HIDE | 1.35 | 0.00 | 37 |
| `b_iron` | 3 | `deep_mixed` | deep | 0.97 [0.89, 0.99] | 19.2 | 12.8 | IRON_HIDE | 1.60 | 0.12 | 52 |
| `b_iron` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 17.3 | 12.5 | IRON_HIDE | 1.88 | 0.00 | 47 |
| `b_iron` | 3 | `opt_archers` | optional | 0.92 [0.82, 0.96] | 25.5 | 15.5 | IRON_HIDE | 1.90 | 0.00 | 38 |
| `b_iron` | 3 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 18.1 | 15.9 | IRON_HIDE | 2.53 | 0.00 | 58 |
| `p_rat` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 3.2 | 8.9 | RAT_GNAW | 1.00 | 0.00 | 10 |
| `p_rat` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 4.3 | 8.7 | RAT_GNAW | 0.82 | 0.00 | 21 |
| `p_rat` | 3 | `deep_mixed` | deep | 0.97 [0.89, 0.99] | 22.2 | 11.8 | RAT_GNAW | 1.68 | 0.02 | 50 |
| `p_rat` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 19.1 | 10.8 | RAT_GNAW | 1.82 | 0.00 | 35 |
| `p_rat` | 3 | `opt_archers` | optional | 0.87 [0.76, 0.93] | 25.4 | 13.3 | RAT_GNAW | 1.75 | 0.03 | 37 |
| `p_rat` | 3 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 14.7 | 13.3 | RAT_GNAW | 2.08 | 0.02 | 51 |
| `p_lizard` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 2.0 | 8.6 | LIZARD_TAIL | 0.00 | 0.00 | 8 |
| `p_lizard` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 2.9 | 8.6 | LIZARD_TAIL | 0.28 | 0.00 | 14 |
| `p_lizard` | 3 | `deep_mixed` | deep | 0.98 [0.91, 1.00] | 18.6 | 11.0 | LIZARD_TAIL | 0.45 | 0.05 | 47 |
| `p_lizard` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 16.9 | 10.2 | LIZARD_TAIL | 0.42 | 0.00 | 26 |
| `p_lizard` | 3 | `opt_archers` | optional | 0.93 [0.84, 0.97] | 23.9 | 12.8 | LIZARD_TAIL | 0.43 | 0.03 | 37 |
| `p_lizard` | 3 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 12.9 | 12.3 | LIZARD_TAIL | 0.55 | 0.00 | 53 |
| `p_kobold` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 3.8 | 10.1 | KOBOLD_SLING | 2.00 | 0.00 | 11 |
| `p_kobold` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 2.8 | 9.9 | KOBOLD_SLING | 2.17 | 0.00 | 21 |
| `p_kobold` | 3 | `deep_mixed` | deep | 1.00 [0.94, 1.00] | 20.9 | 12.7 | KOBOLD_SLING | 2.92 | 0.03 | 53 |
| `p_kobold` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 13.8 | 11.6 | KOBOLD_SLING | 2.40 | 0.00 | 27 |
| `p_kobold` | 3 | `opt_archers` | optional | 0.97 [0.89, 0.99] | 27.5 | 14.0 | KOBOLD_SLING | 3.32 | 0.30 | 39 |
| `p_kobold` | 3 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 12.8 | 14.2 | KOBOLD_SLING | 3.53 | 0.00 | 51 |
| `p_goblin` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 0.7 | 7.5 | GOBLIN_SHIV | 1.00 | 0.00 | 3 |
| `p_goblin` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 4.0 | 7.5 | GOBLIN_SHIV | 0.98 | 0.00 | 13 |
| `p_goblin` | 3 | `deep_mixed` | deep | 1.00 [0.94, 1.00] | 16.8 | 9.6 | GOBLIN_SHIV | 1.42 | 0.17 | 42 |
| `p_goblin` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 13.4 | 8.8 | GOBLIN_SHIV | 1.18 | 0.00 | 18 |
| `p_goblin` | 3 | `opt_archers` | optional | 1.00 [0.94, 1.00] | 18.1 | 9.7 | GOBLIN_SHIV | 1.70 | 0.03 | 33 |
| `p_goblin` | 3 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 13.2 | 11.0 | GOBLIN_SHIV | 2.02 | 0.08 | 51 |
| `p_hob` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 2.1 | 8.6 | HOB_CLUB | 1.00 | 0.00 | 8 |
| `p_hob` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 1.9 | 8.3 | HOB_CLUB | 0.82 | 0.00 | 12 |
| `p_hob` | 3 | `deep_mixed` | deep | 0.98 [0.91, 1.00] | 15.2 | 10.9 | HOB_CLUB | 1.27 | 0.03 | 47 |
| `p_hob` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 15.6 | 10.5 | HOB_CLUB | 1.22 | 0.00 | 34 |
| `p_hob` | 3 | `opt_archers` | optional | 1.00 [0.94, 1.00] | 19.3 | 12.8 | HOB_CLUB | 1.50 | 0.17 | 35 |
| `p_hob` | 3 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 11.2 | 12.7 | HOB_CLUB | 1.70 | 0.00 | 51 |
| `p_orc` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 2.1 | 8.6 | ORC_CLEAVER | 0.00 | 0.00 | 8 |
| `p_orc` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 2.9 | 8.2 | ORC_CLEAVER | 0.28 | 0.00 | 15 |
| `p_orc` | 3 | `deep_mixed` | deep | 1.00 [0.94, 1.00] | 17.0 | 10.6 | ORC_CLEAVER | 0.43 | 0.10 | 47 |
| `p_orc` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 17.1 | 10.3 | ORC_CLEAVER | 0.42 | 0.00 | 32 |
| `p_orc` | 3 | `opt_archers` | optional | 0.90 [0.80, 0.95] | 24.1 | 12.5 | ORC_CLEAVER | 0.43 | 0.07 | 36 |
| `p_orc` | 3 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 11.4 | 11.8 | ORC_CLEAVER | 0.50 | 0.00 | 46 |
| `p_gnoll` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 3.1 | 8.9 | GNOLL_SPEAR | 1.00 | 0.00 | 10 |
| `p_gnoll` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 2.0 | 8.2 | GNOLL_SPEAR | 0.97 | 0.00 | 13 |
| `p_gnoll` | 3 | `deep_mixed` | deep | 1.00 [0.94, 1.00] | 18.2 | 10.9 | GNOLL_SPEAR | 1.42 | 0.00 | 49 |
| `p_gnoll` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 14.2 | 10.1 | GNOLL_SPEAR | 1.37 | 0.00 | 22 |
| `p_gnoll` | 3 | `opt_archers` | optional | 1.00 [0.94, 1.00] | 21.0 | 12.7 | GNOLL_SPEAR | 1.73 | 0.02 | 33 |
| `p_gnoll` | 3 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 11.3 | 12.2 | GNOLL_SPEAR | 2.13 | 0.00 | 51 |
| `p_river` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 2.6 | 9.4 | RIVER_RAT_SPLASH | 0.50 | 0.00 | 11 |
| `p_river` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 3.5 | 8.6 | RIVER_RAT_SPLASH | 0.62 | 0.00 | 20 |
| `p_river` | 3 | `deep_mixed` | deep | 1.00 [0.94, 1.00] | 19.1 | 11.4 | RIVER_RAT_SPLASH | 1.15 | 0.23 | 51 |
| `p_river` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 16.7 | 10.4 | RIVER_RAT_SPLASH | 0.30 | 0.00 | 28 |
| `p_river` | 3 | `opt_archers` | optional | 1.00 [0.94, 1.00] | 24.2 | 13.5 | RIVER_RAT_SPLASH | 1.52 | 0.23 | 37 |
| `p_river` | 3 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 9.0 | 11.3 | RIVER_RAT_SPLASH | 0.90 | 0.00 | 49 |

## 표 2 — 기준선 `melee_1` 대비 Δ

같은 인원·같은 아레나의 기준선 칸과 비교한다. Δ승률은 퍼센트포인트, Δ피해는 개인별 평균 피해의 절대 변화량이다(피해는 낮을수록 좋다).

| 빌드 | 인원 | 아레나 | Δ승률(pp) | Δ피해 |
| --- | --- | --- | --- | --- |
| `b_strike` | 1 | `early_hob` | +0.0 | -7.0 |
| `b_strike` | 1 | `early_pair` | +0.0 | +0.9 |
| `b_strike` | 1 | `deep_mixed` | +30.0 | -11.2 |
| `b_strike` | 1 | `deep_caster` | -26.7 | -4.5 |
| `b_strike` | 1 | `opt_archers` | +0.0 | +0.7 |
| `b_strike` | 1 | `opt_gnoll` | +3.3 | -12.2 |
| `b_strike` | 3 | `early_hob` | +0.0 | +2.5 |
| `b_strike` | 3 | `early_pair` | +0.0 | +0.4 |
| `b_strike` | 3 | `deep_mixed` | +1.7 | -0.7 |
| `b_strike` | 3 | `deep_caster` | +0.0 | -0.6 |
| `b_strike` | 3 | `opt_archers` | +6.7 | -4.2 |
| `b_strike` | 3 | `opt_gnoll` | +0.0 | -1.0 |
| `b_knife` | 1 | `early_hob` | +0.0 | -14.0 |
| `b_knife` | 1 | `early_pair` | +0.0 | -10.1 |
| `b_knife` | 1 | `deep_mixed` | +6.7 | -0.4 |
| `b_knife` | 1 | `deep_caster` | +18.3 | -3.9 |
| `b_knife` | 1 | `opt_archers` | +0.0 | +1.7 |
| `b_knife` | 1 | `opt_gnoll` | +3.3 | -13.2 |
| `b_knife` | 3 | `early_hob` | +0.0 | +0.9 |
| `b_knife` | 3 | `early_pair` | +0.0 | -2.0 |
| `b_knife` | 3 | `deep_mixed` | +1.7 | +2.6 |
| `b_knife` | 3 | `deep_caster` | +0.0 | +0.5 |
| `b_knife` | 3 | `opt_archers` | +6.7 | -1.0 |
| `b_knife` | 3 | `opt_gnoll` | +0.0 | -1.4 |
| `b_dressing` | 1 | `early_hob` | +0.0 | +0.0 |
| `b_dressing` | 1 | `early_pair` | +0.0 | +1.1 |
| `b_dressing` | 1 | `deep_mixed` | +0.0 | +14.0 |
| `b_dressing` | 1 | `deep_caster` | +8.3 | +18.6 |
| `b_dressing` | 1 | `opt_archers` | +0.0 | +11.4 |
| `b_dressing` | 1 | `opt_gnoll` | +0.0 | +6.5 |
| `b_dressing` | 3 | `early_hob` | +0.0 | +0.3 |
| `b_dressing` | 3 | `early_pair` | +0.0 | -0.7 |
| `b_dressing` | 3 | `deep_mixed` | +1.7 | +0.8 |
| `b_dressing` | 3 | `deep_caster` | +0.0 | +5.7 |
| `b_dressing` | 3 | `opt_archers` | +3.3 | +0.6 |
| `b_dressing` | 3 | `opt_gnoll` | +0.0 | +0.1 |
| `b_lunge` | 1 | `early_hob` | +0.0 | -7.0 |
| `b_lunge` | 1 | `early_pair` | +0.0 | +3.6 |
| `b_lunge` | 1 | `deep_mixed` | +10.0 | -3.2 |
| `b_lunge` | 1 | `deep_caster` | -21.7 | -2.1 |
| `b_lunge` | 1 | `opt_archers` | +0.0 | +0.9 |
| `b_lunge` | 1 | `opt_gnoll` | -3.3 | -1.3 |
| `b_lunge` | 3 | `early_hob` | +0.0 | -1.1 |
| `b_lunge` | 3 | `early_pair` | +0.0 | +0.1 |
| `b_lunge` | 3 | `deep_mixed` | +1.7 | -0.2 |
| `b_lunge` | 3 | `deep_caster` | +0.0 | +3.0 |
| `b_lunge` | 3 | `opt_archers` | +6.7 | -6.7 |
| `b_lunge` | 3 | `opt_gnoll` | +0.0 | -1.6 |
| `b_bomb` | 1 | `early_hob` | +0.0 | -14.0 |
| `b_bomb` | 1 | `early_pair` | +0.0 | -10.1 |
| `b_bomb` | 1 | `deep_mixed` | +40.0 | -1.6 |
| `b_bomb` | 1 | `deep_caster` | +31.7 | -21.0 |
| `b_bomb` | 1 | `opt_archers` | +0.0 | +0.5 |
| `b_bomb` | 1 | `opt_gnoll` | +3.3 | -16.2 |
| `b_bomb` | 3 | `early_hob` | +0.0 | +1.4 |
| `b_bomb` | 3 | `early_pair` | +0.0 | -1.1 |
| `b_bomb` | 3 | `deep_mixed` | +1.7 | -5.6 |
| `b_bomb` | 3 | `deep_caster` | +0.0 | +1.3 |
| `b_bomb` | 3 | `opt_archers` | +0.0 | -3.5 |
| `b_bomb` | 3 | `opt_gnoll` | +0.0 | -4.8 |
| `b_shockwave` | 1 | `early_hob` | +0.0 | +0.0 |
| `b_shockwave` | 1 | `early_pair` | +0.0 | -3.8 |
| `b_shockwave` | 1 | `deep_mixed` | +25.0 | -0.6 |
| `b_shockwave` | 1 | `deep_caster` | +0.0 | -5.8 |
| `b_shockwave` | 1 | `opt_archers` | +0.0 | +0.0 |
| `b_shockwave` | 1 | `opt_gnoll` | +3.3 | -9.1 |
| `b_shockwave` | 3 | `early_hob` | +0.0 | +0.4 |
| `b_shockwave` | 3 | `early_pair` | +0.0 | -0.7 |
| `b_shockwave` | 3 | `deep_mixed` | +1.7 | -0.4 |
| `b_shockwave` | 3 | `deep_caster` | +0.0 | +5.9 |
| `b_shockwave` | 3 | `opt_archers` | -3.3 | -0.6 |
| `b_shockwave` | 3 | `opt_gnoll` | +0.0 | -0.4 |
| `b_iron` | 1 | `early_hob` | +0.0 | +1.0 |
| `b_iron` | 1 | `early_pair` | -8.3 | +19.2 |
| `b_iron` | 1 | `deep_mixed` | +0.0 | -2.1 |
| `b_iron` | 1 | `deep_caster` | -11.7 | -1.1 |
| `b_iron` | 1 | `opt_archers` | +0.0 | +0.1 |
| `b_iron` | 1 | `opt_gnoll` | -53.3 | +17.1 |
| `b_iron` | 3 | `early_hob` | +0.0 | +0.8 |
| `b_iron` | 3 | `early_pair` | +0.0 | +2.7 |
| `b_iron` | 3 | `deep_mixed` | -1.7 | +1.7 |
| `b_iron` | 3 | `deep_caster` | +0.0 | +6.1 |
| `b_iron` | 3 | `opt_archers` | -1.7 | +1.3 |
| `b_iron` | 3 | `opt_gnoll` | +0.0 | +5.5 |
| `p_rat` | 1 | `early_hob` | +0.0 | +0.0 |
| `p_rat` | 1 | `early_pair` | +0.0 | +0.0 |
| `p_rat` | 1 | `deep_mixed` | +0.0 | -0.2 |
| `p_rat` | 1 | `deep_caster` | -48.3 | -2.2 |
| `p_rat` | 1 | `opt_archers` | +0.0 | +0.0 |
| `p_rat` | 1 | `opt_gnoll` | -1.7 | +6.5 |
| `p_rat` | 3 | `early_hob` | +0.0 | +1.4 |
| `p_rat` | 3 | `early_pair` | +0.0 | +1.3 |
| `p_rat` | 3 | `deep_mixed` | -1.7 | +4.7 |
| `p_rat` | 3 | `deep_caster` | +0.0 | +7.9 |
| `p_rat` | 3 | `opt_archers` | -6.7 | +1.2 |
| `p_rat` | 3 | `opt_gnoll` | +0.0 | +2.1 |
| `p_lizard` | 1 | `early_hob` | +0.0 | +0.0 |
| `p_lizard` | 1 | `early_pair` | +0.0 | -4.0 |
| `p_lizard` | 1 | `deep_mixed` | +0.0 | -1.5 |
| `p_lizard` | 1 | `deep_caster` | -48.3 | -2.2 |
| `p_lizard` | 1 | `opt_archers` | +0.0 | +0.0 |
| `p_lizard` | 1 | `opt_gnoll` | +3.3 | -2.7 |
| `p_lizard` | 3 | `early_hob` | +0.0 | +0.2 |
| `p_lizard` | 3 | `early_pair` | +0.0 | -0.2 |
| `p_lizard` | 3 | `deep_mixed` | +0.0 | +1.0 |
| `p_lizard` | 3 | `deep_caster` | +0.0 | +5.7 |
| `p_lizard` | 3 | `opt_archers` | +0.0 | -0.3 |
| `p_lizard` | 3 | `opt_gnoll` | +0.0 | +0.3 |
| `p_kobold` | 1 | `early_hob` | +0.0 | -14.0 |
| `p_kobold` | 1 | `early_pair` | +0.0 | -10.3 |
| `p_kobold` | 1 | `deep_mixed` | +0.0 | -0.6 |
| `p_kobold` | 1 | `deep_caster` | +18.3 | -3.1 |
| `p_kobold` | 1 | `opt_archers` | +0.0 | +1.7 |
| `p_kobold` | 1 | `opt_gnoll` | +3.3 | -2.7 |
| `p_kobold` | 3 | `early_hob` | +0.0 | +2.0 |
| `p_kobold` | 3 | `early_pair` | +0.0 | -0.3 |
| `p_kobold` | 3 | `deep_mixed` | +1.7 | +3.3 |
| `p_kobold` | 3 | `deep_caster` | +0.0 | +2.6 |
| `p_kobold` | 3 | `opt_archers` | +3.3 | +3.3 |
| `p_kobold` | 3 | `opt_gnoll` | +0.0 | +0.2 |
| `p_goblin` | 1 | `early_hob` | +0.0 | -7.0 |
| `p_goblin` | 1 | `early_pair` | +0.0 | +3.0 |
| `p_goblin` | 1 | `deep_mixed` | +10.0 | -3.3 |
| `p_goblin` | 1 | `deep_caster` | -18.3 | -2.5 |
| `p_goblin` | 1 | `opt_archers` | +0.0 | +0.9 |
| `p_goblin` | 1 | `opt_gnoll` | -3.3 | -2.4 |
| `p_goblin` | 3 | `early_hob` | +0.0 | -1.1 |
| `p_goblin` | 3 | `early_pair` | +0.0 | +1.0 |
| `p_goblin` | 3 | `deep_mixed` | +1.7 | -0.8 |
| `p_goblin` | 3 | `deep_caster` | +0.0 | +2.3 |
| `p_goblin` | 3 | `opt_archers` | +6.7 | -6.1 |
| `p_goblin` | 3 | `opt_gnoll` | +0.0 | +0.6 |
| `p_hob` | 1 | `early_hob` | +0.0 | -2.0 |
| `p_hob` | 1 | `early_pair` | +0.0 | -2.3 |
| `p_hob` | 1 | `deep_mixed` | +0.0 | -2.4 |
| `p_hob` | 1 | `deep_caster` | +35.0 | -4.7 |
| `p_hob` | 1 | `opt_archers` | +0.0 | -5.0 |
| `p_hob` | 1 | `opt_gnoll` | +0.0 | -1.5 |
| `p_hob` | 3 | `early_hob` | +0.0 | +0.3 |
| `p_hob` | 3 | `early_pair` | +0.0 | -1.1 |
| `p_hob` | 3 | `deep_mixed` | +0.0 | -2.4 |
| `p_hob` | 3 | `deep_caster` | +0.0 | +4.4 |
| `p_hob` | 3 | `opt_archers` | +6.7 | -4.9 |
| `p_hob` | 3 | `opt_gnoll` | +0.0 | -1.5 |
| `p_orc` | 1 | `early_hob` | +0.0 | +0.0 |
| `p_orc` | 1 | `early_pair` | +0.0 | -5.5 |
| `p_orc` | 1 | `deep_mixed` | +30.0 | -1.2 |
| `p_orc` | 1 | `deep_caster` | +18.3 | -2.2 |
| `p_orc` | 1 | `opt_archers` | +0.0 | +0.0 |
| `p_orc` | 1 | `opt_gnoll` | +3.3 | -11.2 |
| `p_orc` | 3 | `early_hob` | +0.0 | +0.3 |
| `p_orc` | 3 | `early_pair` | +0.0 | -0.2 |
| `p_orc` | 3 | `deep_mixed` | +1.7 | -0.5 |
| `p_orc` | 3 | `deep_caster` | +0.0 | +6.0 |
| `p_orc` | 3 | `opt_archers` | -3.3 | -0.1 |
| `p_orc` | 3 | `opt_gnoll` | +0.0 | -1.2 |
| `p_gnoll` | 1 | `early_hob` | +0.0 | +0.0 |
| `p_gnoll` | 1 | `early_pair` | +0.0 | -3.2 |
| `p_gnoll` | 1 | `deep_mixed` | +28.3 | +14.5 |
| `p_gnoll` | 1 | `deep_caster` | +35.0 | +2.1 |
| `p_gnoll` | 1 | `opt_archers` | +0.0 | +5.2 |
| `p_gnoll` | 1 | `opt_gnoll` | +3.3 | -2.4 |
| `p_gnoll` | 3 | `early_hob` | +0.0 | +1.3 |
| `p_gnoll` | 3 | `early_pair` | +0.0 | -1.0 |
| `p_gnoll` | 3 | `deep_mixed` | +1.7 | +0.6 |
| `p_gnoll` | 3 | `deep_caster` | +0.0 | +3.1 |
| `p_gnoll` | 3 | `opt_archers` | +6.7 | -3.3 |
| `p_gnoll` | 3 | `opt_gnoll` | +0.0 | -1.3 |
| `p_river` | 1 | `early_hob` | +0.0 | -7.0 |
| `p_river` | 1 | `early_pair` | +0.0 | -10.8 |
| `p_river` | 1 | `deep_mixed` | +0.0 | -0.8 |
| `p_river` | 1 | `deep_caster` | -21.7 | -0.9 |
| `p_river` | 1 | `opt_archers` | +0.0 | +0.0 |
| `p_river` | 1 | `opt_gnoll` | +3.3 | -10.1 |
| `p_river` | 3 | `early_hob` | +0.0 | +0.8 |
| `p_river` | 3 | `early_pair` | +0.0 | +0.4 |
| `p_river` | 3 | `deep_mixed` | +1.7 | +1.6 |
| `p_river` | 3 | `deep_caster` | +0.0 | +5.5 |
| `p_river` | 3 | `opt_archers` | +6.7 | -0.0 |
| `p_river` | 3 | `opt_gnoll` | +0.0 | -3.6 |

빌드별 요약(전 칸 기준, 우세/열세는 Δ승률의 부호):

| 빌드 | 장착 스킬 | 사용 평균 | Δ승률 평균(pp) | 우세 칸 | 열세 칸 | 1인 Δ승률 ≥ +20pp 아레나 |
| --- | --- | --- | --- | --- | --- | --- |
| `b_strike` | HEAVY_STRIKE | 1.28 | +1.3 | 4/12 | 1/12 | 1/6 |
| `b_knife` | THROWING_KNIFE | 3.12 | +3.1 | 5/12 | 0/12 | 0/6 |
| `b_dressing` | FIELD_DRESSING | 0.50 | +1.1 | 3/12 | 0/12 | 0/6 |
| `b_lunge` | LUNGE | 1.54 | -0.6 | 3/12 | 2/12 | 0/6 |
| `b_bomb` | BOMB | 1.16 | +6.4 | 4/12 | 0/12 | 2/6 |
| `b_shockwave` | SHOCKWAVE | 0.80 | +2.2 | 3/12 | 1/12 | 1/6 |
| `b_iron` | IRON_HIDE | 1.91 | -6.4 | 0/12 | 5/12 | 0/6 |
| `p_rat` | RAT_GNAW | 1.60 | -4.9 | 0/12 | 4/12 | 0/6 |
| `p_lizard` | LIZARD_TAIL | 0.87 | -3.8 | 1/12 | 1/12 | 0/6 |
| `p_kobold` | KOBOLD_SLING | 2.60 | +2.2 | 4/12 | 0/12 | 0/6 |
| `p_goblin` | GOBLIN_SHIV | 1.50 | -0.3 | 3/12 | 2/12 | 0/6 |
| `p_hob` | HOB_CLUB | 1.44 | +3.5 | 2/12 | 0/12 | 1/6 |
| `p_orc` | ORC_CLEAVER | 0.82 | +4.2 | 4/12 | 1/12 | 1/6 |
| `p_gnoll` | GNOLL_SPEAR | 1.61 | +6.2 | 5/12 | 0/12 | 2/6 |
| `p_river` | RIVER_RAT_SPLASH | 1.18 | -0.8 | 3/12 | 1/12 | 0/6 |

## 표 3 — 적 시그니처 파츠 사용 (아레나 × 파츠)

한 전투에서 그 종족이 자기 시그니처 파츠를 실제로 해결한 횟수의 평균이다(`run_many.enemy_skill_uses_mean`). 각 칸은 그 아레나의 모든 빌드·인원 조합(32칸)을 평균한 값이고, `최소`는 그 조합들 중 가장 낮은 칸이다. 게이트 G4의 기준은 전투당 평균 ≥ 0.5회다.

| 아레나 | 종족 | 파츠 | 전투당 평균 | 최소 칸 | 판정 |
| --- | --- | --- | --- | --- | --- |
| `early_hob` | dcss_hobgoblin | `HOB_CLUB` | 0.91 | 0.00 | 통과 |
| `early_pair` | kobold | `KOBOLD_SLING` | 1.26 | 0.90 | 통과 |
| `early_pair` | dcss_rat | `RAT_GNAW` | 0.82 | 0.17 | 통과 |
| `deep_mixed` | dcss_hobgoblin | `HOB_CLUB` | 0.98 | 0.47 | 통과 |
| `deep_mixed` | goblin | `GOBLIN_SHIV` | 0.89 | 0.52 | 통과 |
| `deep_mixed` | kobold | `KOBOLD_SLING` | 1.48 | 0.82 | 통과 |
| `deep_caster` | dcss_orc | `ORC_CLEAVER` | 0.93 | 0.17 | 통과 |
| `deep_caster` | goblin | `GOBLIN_SHIV` | 1.21 | 0.83 | 통과 |
| `opt_archers` | kobold | `KOBOLD_SLING` | 0.83 | 0.00 | 통과 |
| `opt_archers` | goblin | `GOBLIN_SHIV` | 0.70 | 0.18 | 통과 |
| `opt_archers` | dcss_rat | `RAT_GNAW` | 0.51 | 0.10 | 통과 |
| `opt_gnoll` | dcss_gnoll | `GNOLL_SPEAR` | 1.65 | 1.00 | 통과 |
| `opt_gnoll` | dcss_rat | `RAT_GNAW` | 2.22 | 0.35 | 통과 |

준비가 끊긴 횟수(밀치기·피격)는 `interrupts_mean`으로 같은 행렬에서 잰다 — 전 칸 평균 0.02회/전투.

행렬의 6아레나에 자리가 없는 종족은 같은 시드 묶음으로 1종족 아레나를 따로 돌려 잰다 — G4가 파츠 8종을 빠짐없이 덮게 하기 위해서다(표 3과 같은 빌드 16 × 인원 2 격자, `rules` 정책, 물자 0).

| 종족 | 파츠 | 전투당 평균 | 최소 칸 | 판정 |
| --- | --- | --- | --- | --- |
| dcss_frilled_lizard | `LIZARD_TAIL` | 0.65 | 0.00 | 통과 |
| dcss_river_rat | `RIVER_RAT_SPLASH` | 0.92 | 0.00 | 통과 |

## 후보 판정 (설계 §5-4, 사전 고정)

- **지배 후보**: 1인에서 아레나 6개 중 4개 이상에서 Δ승률 ≥ +20pp.
- **사장 후보(봇이 못 씀)**: 장착 스킬 사용 평균 < 0.2회/전투.
- **사장 후보(약함)**: 모든 칸에서 Δ승률 ≤ 0 이고 Δ피해 ≥ 0.

| 판정 | 빌드 |
| --- | --- |
| 지배 후보 | — |
| 사장 후보(봇이 못 씀) | — |
| 사장 후보(약함) | — |

**후보는 확정이 아니다.** 이 판정은 검사한 조건(이 6아레나·2인원·물자 0·`rules` 정책) 안에서의 후보 탐지이며, 모든 상황에서의 우위나 열위를 증명하지 않는다. 수치 조정은 이 도구가 하지 않는다 — 사람이 보고서를 읽고 별도 커밋으로 결정한다(방법론 §5).

## 발견 사항 — 사용되지 않은 스킬

사용 평균이 0인 칸이 있는 빌드: `melee_1`, `b_dressing`, `b_shockwave`, `p_lizard`, `p_orc`. 각 빌드를 사용 평균 0인 바로 그 칸의 config로·시드 3개씩 다시 돌리며, 매 라운드 `Abilities.legal(영웅, 스킬, 보이는 적 각각 또는 자신)`을 검사해 합법이었던 라운드 수를 셌다.

| 빌드 | 스킬 | 사용 평균 0인 칸 | 진단 |
| --- | --- | --- | --- |
| `melee_1` | PUSH | 1인/`early_hob`, 1인/`early_pair`, 1인/`deep_mixed`, 1인/`opt_archers`, 3인/`early_hob`, 3인/`early_pair`, 3인/`opt_archers`, 3인/`opt_gnoll` | 합법 라운드 91/219 — 규칙이 고르지 않음 |
| `b_dressing` | FIELD_DRESSING | 1인/`early_hob`, 3인/`early_hob`, 3인/`early_pair` | 합법 라운드 7/72 — 규칙이 고르지 않음 |
| `b_shockwave` | SHOCKWAVE | 3인/`early_hob` | 합법 라운드 23/23 — 규칙이 고르지 않음 |
| `p_lizard` | LIZARD_TAIL | 3인/`early_hob` | 합법 라운드 8/23 — 규칙이 고르지 않음 |
| `p_orc` | ORC_CLEAVER | 3인/`early_hob` | 합법 라운드 8/23 — 규칙이 고르지 않음 |

`합법 라운드 N/M`이 0이 아니면 스킬은 쓸 수 있었는데 규칙이 그 라운드를 고르지 않았다는 뜻이고(규칙 조건 쪽 문제), 0이면 `legal`이 한 번도 참이 되지 않았다는 뜻이다(사거리·대상·쿨다운 쪽 문제).

## 추적 계획

1. 사장 후보의 원인을 규칙 조건과 사거리로 분리해 재실험(진단 줄이 가리키는 쪽만 바꾼다)
2. 지배 후보는 비용 축(쿨다운·자원)을 하나만 바꿔 다시 측정
3. 물자 축(0 vs 2)을 더해 스킬과 소모품의 대체 관계 측정
4. 3인에서 동료도 같은 빌드를 드는 조건 추가(현재는 파티 전원이 같은 빌드다)

