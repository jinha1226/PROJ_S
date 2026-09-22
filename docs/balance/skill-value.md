# 스킬 가치 실험 결과

생성: `tests/skill_value.gd`(수동 도구) · 커밋 `995a105-dirty` · 날짜 2026-09-22
근거: [밸런스 방법론](../balance-method.ko.md) §5 · 설계: [스킬 원형 설계](../superpowers/specs/2026-09-22-skill-archetypes-design.md) §5

- 시드 묶음: `S2` 60개 (5000~5059)
- 규칙: `current` (`solo_actions 1` / `solo_max_members 0`) 하나만 쓴다 — 이번 실험의 축은 빌드다.
- 봇 정책: `rules` — 영웅이 동료와 같은 규칙 목록(`expedition/tactic_rules.gd`)을 읽고 `Tactics.choose`가 고른 행동을 그대로 누른다.
- **물자 0**: `supplies [0, 0, 0, 0, 0, 0]`. 회복품이 없으므로 스킬의 값이 물약에 가려지지 않는다.
- 솔로 HP 스케일: `SOLO_HP_PERCENT 45` / `SOLO_HP_MIN 20` / `SOLO_HP_MAX 32` (파티 인원 1일 때만 적용, 실험 조건의 일부)
- 아레나 공통 spec: size 20 · room [5, 5, 9, 9] · door [9, 4] · pillars [[8, 8], [10, 10]] · party_entry [9, 5] · light 90 · supplies [0, 0, 0, 0, 0, 0]
- 행렬: 빌드 8 × 인원 2 × 아레나 6 × 시드 60 = 5760전투
- 실행 시간: 185.9초

> 전투의 명중 판정은 없다. 같은 커밋·같은 시드·같은 빌드는 같은 전투를 낸다 — 표의 모든 칸은 재실행으로 그대로 재현된다. 시드는 적 배치와 부상 부위 선택에만 영향을 준다.
> `사용 평균`은 그 빌드의 첫 장착 스킬을 한 전투에서 누른 횟수의 평균이다(누르지 않은 전투는 0으로 센다).
> `distinct`는 시드 묶음에서 나온 서로 다른 `(결과, 라운드, 피해)` 조합의 수다.

이 파이프라인이 찾아낸 사전 수정: HEAVY_STRIKE(사거리 1)가 대각선 인접 적에게 불법이던 문제 — `Abilities.legal`이 사거리 1 스킬에 맨해튼 거리 대신 `melee_reach`를 쓰도록 고쳤다(Task 2). 기본 공격이 닿는 칸에 강타가 닿지 않는 상태에서는 사용 평균이 스킬의 값이 아니라 기하의 사고를 재던 셈이다.

빌드 구성:

| 빌드 | 장착 | 규칙 |
| --- | --- | --- |
| `melee_1` | PUSH, GUARD | PUSH→NEAREST(CHARGING), GUARD→SELF(HP) |
| `b_strike` | HEAVY_STRIKE, GUARD | HEAVY_STRIKE→NEAREST(ALWAYS), GUARD→SELF(HP) |
| `b_knife` | THROWING_KNIFE, GUARD | THROWING_KNIFE→NEAREST(ALWAYS), GUARD→SELF(HP) |
| `b_dressing` | FIELD_DRESSING, GUARD | FIELD_DRESSING→SELF(HP), GUARD→SELF(HP) |
| `b_lunge` | LUNGE, GUARD | LUNGE→NEAREST(ALWAYS), GUARD→SELF(HP) |
| `b_bomb` | BOMB, GUARD | BOMB→NEAREST(ALWAYS), GUARD→SELF(HP) |
| `b_shockwave` | SHOCKWAVE, GUARD | SHOCKWAVE→SELF(ALWAYS), GUARD→SELF(HP) |
| `b_iron` | IRON_HIDE, GUARD | IRON_HIDE→SELF(DANGER), GUARD→SELF(HP) |

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
| `melee_1` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 14.0 | 8.0 | PUSH | 0.00 | 0.00 | 1 |
| `melee_1` | 1 | `early_pair` | early | 0.58 [0.46, 0.70] | 31.6 | 11.4 | PUSH | 0.00 | 3.35 | 4 |
| `melee_1` | 1 | `deep_mixed` | deep | 0.00 [0.00, 0.06] | 49.8 | 9.0 | PUSH | 0.00 | 3.28 | 12 |
| `melee_1` | 1 | `deep_caster` | deep | 0.00 [0.00, 0.06] | 53.6 | 33.6 | PUSH | 0.00 | 19.47 | 9 |
| `melee_1` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 50.1 | 7.2 | PUSH | 0.00 | 2.57 | 7 |
| `melee_1` | 1 | `opt_gnoll` | optional | 0.00 [0.00, 0.06] | 51.8 | 11.7 | PUSH | 0.00 | 4.80 | 8 |
| `b_strike` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 7.0 | 7.0 | HEAVY_STRIKE | 1.00 | 0.00 | 1 |
| `b_strike` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 18.6 | 9.1 | HEAVY_STRIKE | 1.10 | 0.20 | 4 |
| `b_strike` | 1 | `deep_mixed` | deep | 0.00 [0.00, 0.06] | 52.0 | 10.6 | HEAVY_STRIKE | 1.75 | 3.88 | 9 |
| `b_strike` | 1 | `deep_caster` | deep | 0.00 [0.00, 0.06] | 53.6 | 33.6 | HEAVY_STRIKE | 1.00 | 19.47 | 9 |
| `b_strike` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 53.3 | 8.5 | HEAVY_STRIKE | 1.00 | 3.38 | 6 |
| `b_strike` | 1 | `opt_gnoll` | optional | 0.65 [0.52, 0.76] | 38.4 | 11.5 | HEAVY_STRIKE | 2.27 | 2.15 | 10 |
| `b_knife` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 0.0 | 7.0 | THROWING_KNIFE | 1.00 | 0.00 | 1 |
| `b_knife` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 12.6 | 8.8 | THROWING_KNIFE | 2.10 | 0.00 | 3 |
| `b_knife` | 1 | `deep_mixed` | deep | 0.02 [0.00, 0.09] | 47.5 | 8.9 | THROWING_KNIFE | 2.83 | 1.55 | 13 |
| `b_knife` | 1 | `deep_caster` | deep | 0.73 [0.61, 0.83] | 37.3 | 15.1 | THROWING_KNIFE | 4.27 | 0.92 | 6 |
| `b_knife` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 49.6 | 7.2 | THROWING_KNIFE | 1.97 | 1.40 | 12 |
| `b_knife` | 1 | `opt_gnoll` | optional | 0.27 [0.17, 0.39] | 39.7 | 10.7 | THROWING_KNIFE | 3.82 | 1.15 | 12 |
| `b_dressing` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 14.0 | 8.0 | FIELD_DRESSING | 0.00 | 0.00 | 1 |
| `b_dressing` | 1 | `early_pair` | early | 0.90 [0.80, 0.95] | 34.4 | 11.3 | FIELD_DRESSING | 0.72 | 1.43 | 7 |
| `b_dressing` | 1 | `deep_mixed` | deep | 0.00 [0.00, 0.06] | 71.5 | 10.7 | FIELD_DRESSING | 1.35 | 3.57 | 12 |
| `b_dressing` | 1 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 46.0 | 16.2 | FIELD_DRESSING | 1.47 | 0.53 | 5 |
| `b_dressing` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 64.3 | 7.6 | FIELD_DRESSING | 1.00 | 1.85 | 7 |
| `b_dressing` | 1 | `opt_gnoll` | optional | 0.12 [0.06, 0.22] | 69.6 | 13.3 | FIELD_DRESSING | 1.37 | 4.40 | 11 |
| `b_lunge` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 14.0 | 8.0 | LUNGE | 1.00 | 0.00 | 1 |
| `b_lunge` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 27.8 | 9.9 | LUNGE | 1.75 | 0.85 | 3 |
| `b_lunge` | 1 | `deep_mixed` | deep | 0.00 [0.00, 0.06] | 49.0 | 8.6 | LUNGE | 1.63 | 2.37 | 13 |
| `b_lunge` | 1 | `deep_caster` | deep | 0.18 [0.11, 0.30] | 51.0 | 18.2 | LUNGE | 2.15 | 7.17 | 6 |
| `b_lunge` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 48.7 | 6.7 | LUNGE | 1.00 | 1.70 | 9 |
| `b_lunge` | 1 | `opt_gnoll` | optional | 0.02 [0.00, 0.09] | 49.5 | 10.0 | LUNGE | 2.10 | 2.38 | 9 |
| `b_bomb` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 0.0 | 7.0 | BOMB | 1.00 | 0.00 | 1 |
| `b_bomb` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 8.9 | 8.2 | BOMB | 1.00 | 0.00 | 4 |
| `b_bomb` | 1 | `deep_mixed` | deep | 0.12 [0.06, 0.22] | 50.8 | 10.6 | BOMB | 1.43 | 4.10 | 12 |
| `b_bomb` | 1 | `deep_caster` | deep | 0.62 [0.49, 0.73] | 35.0 | 18.6 | BOMB | 2.17 | 5.65 | 6 |
| `b_bomb` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 51.0 | 7.4 | BOMB | 0.75 | 2.48 | 10 |
| `b_bomb` | 1 | `opt_gnoll` | optional | 0.35 [0.24, 0.48] | 38.9 | 11.7 | BOMB | 1.03 | 3.60 | 9 |
| `b_shockwave` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 14.0 | 8.0 | SHOCKWAVE | 1.00 | 0.00 | 1 |
| `b_shockwave` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 25.3 | 9.8 | SHOCKWAVE | 1.42 | 0.93 | 4 |
| `b_shockwave` | 1 | `deep_mixed` | deep | 0.00 [0.00, 0.06] | 48.0 | 8.7 | SHOCKWAVE | 1.55 | 2.37 | 12 |
| `b_shockwave` | 1 | `deep_caster` | deep | 0.27 [0.17, 0.39] | 47.7 | 28.6 | SHOCKWAVE | 1.27 | 14.93 | 8 |
| `b_shockwave` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 48.7 | 6.7 | SHOCKWAVE | 1.00 | 1.52 | 9 |
| `b_shockwave` | 1 | `opt_gnoll` | optional | 0.45 [0.33, 0.58] | 49.2 | 12.0 | SHOCKWAVE | 2.22 | 3.48 | 9 |
| `b_iron` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 15.0 | 9.0 | IRON_HIDE | 1.00 | 0.00 | 1 |
| `b_iron` | 1 | `early_pair` | early | 0.00 [0.00, 0.06] | 52.4 | 17.2 | IRON_HIDE | 3.50 | 7.00 | 4 |
| `b_iron` | 1 | `deep_mixed` | deep | 0.00 [0.00, 0.06] | 49.5 | 8.8 | IRON_HIDE | 1.38 | 2.05 | 10 |
| `b_iron` | 1 | `deep_caster` | deep | 0.00 [0.00, 0.06] | 52.6 | 30.1 | IRON_HIDE | 1.23 | 16.58 | 11 |
| `b_iron` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 48.8 | 7.7 | IRON_HIDE | 1.00 | 2.08 | 7 |
| `b_iron` | 1 | `opt_gnoll` | optional | 0.00 [0.00, 0.06] | 50.0 | 11.9 | IRON_HIDE | 2.10 | 3.55 | 8 |
| `melee_1` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 7.0 | 9.0 | PUSH | 0.00 | 0.00 | 1 |
| `melee_1` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 18.0 | 15.7 | PUSH | 0.00 | 4.22 | 22 |
| `melee_1` | 3 | `deep_mixed` | deep | 0.30 [0.20, 0.43] | 46.5 | 25.0 | PUSH | 0.00 | 10.95 | 46 |
| `melee_1` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 26.3 | 19.9 | PUSH | 0.00 | 3.68 | 13 |
| `melee_1` | 3 | `opt_archers` | optional | 0.10 [0.05, 0.20] | 50.4 | 19.1 | PUSH | 0.00 | 9.63 | 30 |
| `melee_1` | 3 | `opt_gnoll` | optional | 0.45 [0.33, 0.58] | 40.8 | 26.2 | PUSH | 0.00 | 12.72 | 49 |
| `b_strike` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 4.7 | 8.0 | HEAVY_STRIKE | 1.00 | 0.00 | 1 |
| `b_strike` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 5.1 | 8.6 | HEAVY_STRIKE | 0.93 | 0.00 | 11 |
| `b_strike` | 3 | `deep_mixed` | deep | 0.85 [0.74, 0.92] | 35.2 | 20.3 | HEAVY_STRIKE | 2.40 | 4.47 | 35 |
| `b_strike` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 25.2 | 20.2 | HEAVY_STRIKE | 1.43 | 1.50 | 10 |
| `b_strike` | 3 | `opt_archers` | optional | 0.40 [0.29, 0.53] | 46.5 | 20.5 | HEAVY_STRIKE | 0.55 | 11.67 | 25 |
| `b_strike` | 3 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 23.6 | 16.0 | HEAVY_STRIKE | 2.28 | 1.78 | 49 |
| `b_knife` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 4.7 | 8.0 | THROWING_KNIFE | 2.00 | 0.00 | 1 |
| `b_knife` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 6.9 | 10.3 | THROWING_KNIFE | 2.25 | 0.00 | 16 |
| `b_knife` | 3 | `deep_mixed` | deep | 0.98 [0.91, 1.00] | 32.0 | 16.9 | THROWING_KNIFE | 4.62 | 2.43 | 39 |
| `b_knife` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 18.2 | 18.3 | THROWING_KNIFE | 2.88 | 2.42 | 12 |
| `b_knife` | 3 | `opt_archers` | optional | 0.45 [0.33, 0.58] | 48.6 | 19.9 | THROWING_KNIFE | 3.20 | 8.70 | 27 |
| `b_knife` | 3 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 22.2 | 15.9 | THROWING_KNIFE | 5.05 | 0.30 | 54 |
| `b_dressing` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 7.0 | 9.0 | FIELD_DRESSING | 0.00 | 0.00 | 1 |
| `b_dressing` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 20.9 | 16.9 | FIELD_DRESSING | 1.62 | 5.00 | 15 |
| `b_dressing` | 3 | `deep_mixed` | deep | 0.68 [0.56, 0.79] | 59.9 | 26.5 | FIELD_DRESSING | 2.95 | 6.83 | 46 |
| `b_dressing` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 25.7 | 19.6 | FIELD_DRESSING | 0.92 | 0.08 | 13 |
| `b_dressing` | 3 | `opt_archers` | optional | 0.45 [0.33, 0.58] | 70.9 | 28.3 | FIELD_DRESSING | 4.10 | 11.88 | 33 |
| `b_dressing` | 3 | `opt_gnoll` | optional | 0.97 [0.89, 0.99] | 37.0 | 20.1 | FIELD_DRESSING | 1.53 | 3.65 | 52 |
| `b_lunge` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 4.7 | 8.0 | LUNGE | 1.00 | 0.00 | 2 |
| `b_lunge` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 5.9 | 8.6 | LUNGE | 0.93 | 0.00 | 11 |
| `b_lunge` | 3 | `deep_mixed` | deep | 0.92 [0.82, 0.96] | 32.5 | 17.5 | LUNGE | 2.45 | 4.10 | 39 |
| `b_lunge` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 19.5 | 15.7 | LUNGE | 1.17 | 0.33 | 15 |
| `b_lunge` | 3 | `opt_archers` | optional | 0.58 [0.46, 0.70] | 42.8 | 18.0 | LUNGE | 1.85 | 7.38 | 26 |
| `b_lunge` | 3 | `opt_gnoll` | optional | 0.98 [0.91, 1.00] | 26.7 | 15.3 | LUNGE | 2.55 | 2.32 | 52 |
| `b_bomb` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 7.0 | 9.0 | BOMB | 0.00 | 0.00 | 1 |
| `b_bomb` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 5.1 | 8.7 | BOMB | 0.65 | 0.00 | 9 |
| `b_bomb` | 3 | `deep_mixed` | deep | 0.72 [0.59, 0.81] | 36.6 | 22.1 | BOMB | 1.67 | 8.27 | 41 |
| `b_bomb` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 17.2 | 17.3 | BOMB | 1.28 | 1.00 | 11 |
| `b_bomb` | 3 | `opt_archers` | optional | 0.37 [0.26, 0.49] | 47.1 | 22.1 | BOMB | 1.67 | 11.83 | 29 |
| `b_bomb` | 3 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 22.2 | 18.3 | BOMB | 0.98 | 2.95 | 45 |
| `b_shockwave` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 7.0 | 9.0 | SHOCKWAVE | 0.00 | 0.00 | 1 |
| `b_shockwave` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 13.4 | 11.9 | SHOCKWAVE | 0.57 | 2.12 | 16 |
| `b_shockwave` | 3 | `deep_mixed` | deep | 0.55 [0.42, 0.67] | 44.2 | 23.2 | SHOCKWAVE | 1.12 | 8.58 | 44 |
| `b_shockwave` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 26.4 | 19.9 | SHOCKWAVE | 0.58 | 3.50 | 13 |
| `b_shockwave` | 3 | `opt_archers` | optional | 0.07 [0.03, 0.16] | 50.4 | 19.4 | SHOCKWAVE | 0.90 | 9.42 | 29 |
| `b_shockwave` | 3 | `opt_gnoll` | optional | 0.83 [0.72, 0.91] | 34.5 | 20.8 | SHOCKWAVE | 0.97 | 7.10 | 53 |
| `b_iron` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 7.7 | 11.0 | IRON_HIDE | 2.00 | 0.00 | 1 |
| `b_iron` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 16.9 | 19.3 | IRON_HIDE | 3.68 | 4.95 | 26 |
| `b_iron` | 3 | `deep_mixed` | deep | 0.12 [0.06, 0.22] | 50.8 | 29.6 | IRON_HIDE | 4.03 | 12.73 | 55 |
| `b_iron` | 3 | `deep_caster` | deep | 0.73 [0.61, 0.83] | 31.9 | 29.7 | IRON_HIDE | 2.18 | 8.20 | 36 |
| `b_iron` | 3 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 50.4 | 20.7 | IRON_HIDE | 2.10 | 9.47 | 38 |
| `b_iron` | 3 | `opt_gnoll` | optional | 0.58 [0.46, 0.70] | 38.9 | 28.8 | IRON_HIDE | 5.62 | 9.77 | 56 |

## 표 2 — 기준선 `melee_1` 대비 Δ

같은 인원·같은 아레나의 기준선 칸과 비교한다. Δ승률은 퍼센트포인트, Δ피해는 개인별 평균 피해의 절대 변화량이다(피해는 낮을수록 좋다).

| 빌드 | 인원 | 아레나 | Δ승률(pp) | Δ피해 |
| --- | --- | --- | --- | --- |
| `b_strike` | 1 | `early_hob` | +0.0 | -7.0 |
| `b_strike` | 1 | `early_pair` | +41.7 | -13.0 |
| `b_strike` | 1 | `deep_mixed` | +0.0 | +2.2 |
| `b_strike` | 1 | `deep_caster` | +0.0 | +0.0 |
| `b_strike` | 1 | `opt_archers` | +0.0 | +3.1 |
| `b_strike` | 1 | `opt_gnoll` | +65.0 | -13.4 |
| `b_strike` | 3 | `early_hob` | +0.0 | -2.3 |
| `b_strike` | 3 | `early_pair` | +0.0 | -12.9 |
| `b_strike` | 3 | `deep_mixed` | +55.0 | -11.3 |
| `b_strike` | 3 | `deep_caster` | +0.0 | -1.1 |
| `b_strike` | 3 | `opt_archers` | +30.0 | -3.9 |
| `b_strike` | 3 | `opt_gnoll` | +55.0 | -17.2 |
| `b_knife` | 1 | `early_hob` | +0.0 | -14.0 |
| `b_knife` | 1 | `early_pair` | +41.7 | -19.0 |
| `b_knife` | 1 | `deep_mixed` | +1.7 | -2.3 |
| `b_knife` | 1 | `deep_caster` | +73.3 | -16.3 |
| `b_knife` | 1 | `opt_archers` | +0.0 | -0.5 |
| `b_knife` | 1 | `opt_gnoll` | +26.7 | -12.1 |
| `b_knife` | 3 | `early_hob` | +0.0 | -2.3 |
| `b_knife` | 3 | `early_pair` | +0.0 | -11.1 |
| `b_knife` | 3 | `deep_mixed` | +68.3 | -14.5 |
| `b_knife` | 3 | `deep_caster` | +0.0 | -8.1 |
| `b_knife` | 3 | `opt_archers` | +35.0 | -1.8 |
| `b_knife` | 3 | `opt_gnoll` | +55.0 | -18.6 |
| `b_dressing` | 1 | `early_hob` | +0.0 | +0.0 |
| `b_dressing` | 1 | `early_pair` | +31.7 | +2.8 |
| `b_dressing` | 1 | `deep_mixed` | +0.0 | +21.7 |
| `b_dressing` | 1 | `deep_caster` | +100.0 | -7.6 |
| `b_dressing` | 1 | `opt_archers` | +0.0 | +14.2 |
| `b_dressing` | 1 | `opt_gnoll` | +11.7 | +17.8 |
| `b_dressing` | 3 | `early_hob` | +0.0 | +0.0 |
| `b_dressing` | 3 | `early_pair` | +0.0 | +3.0 |
| `b_dressing` | 3 | `deep_mixed` | +38.3 | +13.4 |
| `b_dressing` | 3 | `deep_caster` | +0.0 | -0.6 |
| `b_dressing` | 3 | `opt_archers` | +35.0 | +20.6 |
| `b_dressing` | 3 | `opt_gnoll` | +51.7 | -3.8 |
| `b_lunge` | 1 | `early_hob` | +0.0 | +0.0 |
| `b_lunge` | 1 | `early_pair` | +41.7 | -3.8 |
| `b_lunge` | 1 | `deep_mixed` | +0.0 | -0.8 |
| `b_lunge` | 1 | `deep_caster` | +18.3 | -2.6 |
| `b_lunge` | 1 | `opt_archers` | +0.0 | -1.5 |
| `b_lunge` | 1 | `opt_gnoll` | +1.7 | -2.3 |
| `b_lunge` | 3 | `early_hob` | +0.0 | -2.3 |
| `b_lunge` | 3 | `early_pair` | +0.0 | -12.1 |
| `b_lunge` | 3 | `deep_mixed` | +61.7 | -14.0 |
| `b_lunge` | 3 | `deep_caster` | +0.0 | -6.8 |
| `b_lunge` | 3 | `opt_archers` | +48.3 | -7.6 |
| `b_lunge` | 3 | `opt_gnoll` | +53.3 | -14.1 |
| `b_bomb` | 1 | `early_hob` | +0.0 | -14.0 |
| `b_bomb` | 1 | `early_pair` | +41.7 | -22.7 |
| `b_bomb` | 1 | `deep_mixed` | +11.7 | +1.0 |
| `b_bomb` | 1 | `deep_caster` | +61.7 | -18.6 |
| `b_bomb` | 1 | `opt_archers` | +0.0 | +0.9 |
| `b_bomb` | 1 | `opt_gnoll` | +35.0 | -12.9 |
| `b_bomb` | 3 | `early_hob` | +0.0 | +0.0 |
| `b_bomb` | 3 | `early_pair` | +0.0 | -12.9 |
| `b_bomb` | 3 | `deep_mixed` | +41.7 | -9.9 |
| `b_bomb` | 3 | `deep_caster` | +0.0 | -9.1 |
| `b_bomb` | 3 | `opt_archers` | +26.7 | -3.3 |
| `b_bomb` | 3 | `opt_gnoll` | +55.0 | -18.6 |
| `b_shockwave` | 1 | `early_hob` | +0.0 | +0.0 |
| `b_shockwave` | 1 | `early_pair` | +41.7 | -6.3 |
| `b_shockwave` | 1 | `deep_mixed` | +0.0 | -1.8 |
| `b_shockwave` | 1 | `deep_caster` | +26.7 | -5.9 |
| `b_shockwave` | 1 | `opt_archers` | +0.0 | -1.4 |
| `b_shockwave` | 1 | `opt_gnoll` | +45.0 | -2.6 |
| `b_shockwave` | 3 | `early_hob` | +0.0 | +0.0 |
| `b_shockwave` | 3 | `early_pair` | +0.0 | -4.6 |
| `b_shockwave` | 3 | `deep_mixed` | +25.0 | -2.2 |
| `b_shockwave` | 3 | `deep_caster` | +0.0 | +0.1 |
| `b_shockwave` | 3 | `opt_archers` | -3.3 | +0.0 |
| `b_shockwave` | 3 | `opt_gnoll` | +38.3 | -6.3 |
| `b_iron` | 1 | `early_hob` | +0.0 | +1.0 |
| `b_iron` | 1 | `early_pair` | -58.3 | +20.8 |
| `b_iron` | 1 | `deep_mixed` | +0.0 | -0.3 |
| `b_iron` | 1 | `deep_caster` | +0.0 | -1.0 |
| `b_iron` | 1 | `opt_archers` | +0.0 | -1.4 |
| `b_iron` | 1 | `opt_gnoll` | +0.0 | -1.8 |
| `b_iron` | 3 | `early_hob` | +0.0 | +0.7 |
| `b_iron` | 3 | `early_pair` | +0.0 | -1.1 |
| `b_iron` | 3 | `deep_mixed` | -18.3 | +4.3 |
| `b_iron` | 3 | `deep_caster` | -26.7 | +5.6 |
| `b_iron` | 3 | `opt_archers` | -10.0 | -0.0 |
| `b_iron` | 3 | `opt_gnoll` | +13.3 | -1.9 |

빌드별 요약(전 칸 기준, 우세/열세는 Δ승률의 부호):

| 빌드 | 장착 스킬 | 사용 평균 | Δ승률 평균(pp) | 우세 칸 | 열세 칸 | 1인 Δ승률 ≥ +20pp 아레나 |
| --- | --- | --- | --- | --- | --- | --- |
| `b_strike` | HEAVY_STRIKE | 1.39 | +20.6 | 5/12 | 0/12 | 2/6 |
| `b_knife` | THROWING_KNIFE | 3.00 | +25.1 | 7/12 | 0/12 | 3/6 |
| `b_dressing` | FIELD_DRESSING | 1.42 | +22.4 | 6/12 | 0/12 | 2/6 |
| `b_lunge` | LUNGE | 1.63 | +18.8 | 6/12 | 0/12 | 1/6 |
| `b_bomb` | BOMB | 1.14 | +22.8 | 7/12 | 0/12 | 3/6 |
| `b_shockwave` | SHOCKWAVE | 1.05 | +14.4 | 5/12 | 1/12 | 3/6 |
| `b_iron` | IRON_HIDE | 2.49 | -8.3 | 1/12 | 4/12 | 0/6 |

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

사용 평균이 0인 칸이 있는 빌드: `melee_1`, `b_dressing`, `b_bomb`, `b_shockwave`. 각 빌드를 사용 평균 0인 바로 그 칸의 config로·시드 3개씩 다시 돌리며, 매 라운드 `Abilities.legal(영웅, 스킬, 보이는 적 각각 또는 자신)`을 검사해 합법이었던 라운드 수를 셌다.

| 빌드 | 스킬 | 사용 평균 0인 칸 | 진단 |
| --- | --- | --- | --- |
| `melee_1` | PUSH | 전 칸 | `PUSH`는 능력이 아니라 기본 전술(`Abilities.DEFINITIONS` 밖)이라 `legal` 진단 대상이 아니다 — 규칙 조건 `CHARGING`이 맞은 라운드가 없었다는 뜻이다. |
| `b_dressing` | FIELD_DRESSING | 1인/`early_hob`, 3인/`early_hob` | 합법 라운드 15/45 — 규칙이 고르지 않음 |
| `b_bomb` | BOMB | 3인/`early_hob` | 합법 라운드 12/24 — 규칙이 고르지 않음 |
| `b_shockwave` | SHOCKWAVE | 3인/`early_hob` | 합법 라운드 24/24 — 규칙이 고르지 않음 |

`합법 라운드 N/M`이 0이 아니면 스킬은 쓸 수 있었는데 규칙이 그 라운드를 고르지 않았다는 뜻이고(규칙 조건 쪽 문제), 0이면 `legal`이 한 번도 참이 되지 않았다는 뜻이다(사거리·대상·쿨다운 쪽 문제).

## 추적 계획

1. 사장 후보의 원인을 규칙 조건과 사거리로 분리해 재실험(진단 줄이 가리키는 쪽만 바꾼다)
2. 지배 후보는 비용 축(쿨다운·자원)을 하나만 바꿔 다시 측정
3. 물자 축(0 vs 2)을 더해 스킬과 소모품의 대체 관계 측정
4. 3인에서 동료도 같은 빌드를 드는 조건 추가(현재는 파티 전원이 같은 빌드다)

