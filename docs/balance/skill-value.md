# 스킬 가치 실험 결과

생성: `tests/skill_value.gd`(수동 도구) · 커밋 `d208d63` · 날짜 2026-09-22
근거: [밸런스 방법론](../balance-method.ko.md) §5 · 설계: [스킬 원형 설계](../superpowers/specs/2026-09-22-skill-archetypes-design.md) §5

- 시드 묶음: `S2` 60개 (5000~5059)
- 규칙: `current` (`solo_actions 1` / `solo_max_members 0`) 하나만 쓴다 — 이번 실험의 축은 빌드다.
- 봇 정책: `rules` — 영웅이 동료와 같은 규칙 목록(`expedition/tactic_rules.gd`)을 읽고 `Tactics.choose`가 고른 행동을 그대로 누른다.
- **물자 0**: `supplies [0, 0, 0, 0, 0, 0]`. 회복품이 없으므로 스킬의 값이 물약에 가려지지 않는다.
- 솔로 HP 스케일: `SOLO_HP_PERCENT 45` / `SOLO_HP_MIN 20` / `SOLO_HP_MAX 32` (파티 인원 1일 때만 적용, 실험 조건의 일부)
- 아레나 공통 spec: size 20 · room [5, 5, 9, 9] · door [9, 4] · pillars [[8, 8], [10, 10]] · party_entry [9, 5] · light 90 · supplies [0, 0, 0, 0, 0, 0]
- 행렬: 빌드 8 × 인원 2 × 아레나 6 × 시드 60 = 5760전투
- 실행 시간: 242.6초

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
| `melee_1` | 1 | `early_pair` | early | 0.58 [0.46, 0.70] | 31.6 | 10.9 | PUSH | 0.00 | 3.02 | 5 |
| `melee_1` | 1 | `deep_mixed` | deep | 0.00 [0.00, 0.06] | 48.2 | 7.6 | PUSH | 0.00 | 2.77 | 12 |
| `melee_1` | 1 | `deep_caster` | deep | 0.00 [0.00, 0.06] | 53.5 | 28.3 | PUSH | 0.00 | 16.50 | 10 |
| `melee_1` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 49.5 | 6.3 | PUSH | 0.00 | 2.47 | 10 |
| `melee_1` | 1 | `opt_gnoll` | optional | 0.00 [0.00, 0.06] | 51.4 | 10.7 | PUSH | 0.00 | 4.30 | 11 |
| `b_strike` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 7.0 | 7.0 | HEAVY_STRIKE | 1.00 | 0.00 | 1 |
| `b_strike` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 18.0 | 8.9 | HEAVY_STRIKE | 1.10 | 0.20 | 5 |
| `b_strike` | 1 | `deep_mixed` | deep | 0.00 [0.00, 0.06] | 51.0 | 9.5 | HEAVY_STRIKE | 1.80 | 3.43 | 12 |
| `b_strike` | 1 | `deep_caster` | deep | 0.00 [0.00, 0.06] | 53.7 | 30.7 | HEAVY_STRIKE | 1.27 | 18.10 | 10 |
| `b_strike` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 51.9 | 7.2 | HEAVY_STRIKE | 1.00 | 2.80 | 7 |
| `b_strike` | 1 | `opt_gnoll` | optional | 0.70 [0.57, 0.80] | 39.2 | 11.4 | HEAVY_STRIKE | 2.27 | 2.38 | 11 |
| `b_knife` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 0.0 | 7.0 | THROWING_KNIFE | 1.00 | 0.00 | 1 |
| `b_knife` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 11.4 | 8.7 | THROWING_KNIFE | 2.10 | 0.00 | 4 |
| `b_knife` | 1 | `deep_mixed` | deep | 0.00 [0.00, 0.06] | 48.4 | 9.0 | THROWING_KNIFE | 2.70 | 2.28 | 12 |
| `b_knife` | 1 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 31.6 | 14.2 | THROWING_KNIFE | 4.00 | 0.65 | 6 |
| `b_knife` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 50.6 | 6.7 | THROWING_KNIFE | 1.80 | 1.83 | 12 |
| `b_knife` | 1 | `opt_gnoll` | optional | 0.40 [0.29, 0.53] | 36.4 | 10.2 | THROWING_KNIFE | 3.70 | 0.85 | 12 |
| `b_dressing` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 14.0 | 8.0 | FIELD_DRESSING | 0.00 | 0.00 | 1 |
| `b_dressing` | 1 | `early_pair` | early | 0.82 [0.70, 0.89] | 40.3 | 12.4 | FIELD_DRESSING | 0.97 | 2.68 | 9 |
| `b_dressing` | 1 | `deep_mixed` | deep | 0.00 [0.00, 0.06] | 69.1 | 8.9 | FIELD_DRESSING | 1.22 | 2.82 | 12 |
| `b_dressing` | 1 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 51.7 | 16.9 | FIELD_DRESSING | 1.92 | 0.80 | 4 |
| `b_dressing` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 64.4 | 6.8 | FIELD_DRESSING | 1.00 | 1.82 | 9 |
| `b_dressing` | 1 | `opt_gnoll` | optional | 0.03 [0.01, 0.11] | 68.6 | 11.9 | FIELD_DRESSING | 1.17 | 3.92 | 12 |
| `b_lunge` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 14.0 | 8.0 | LUNGE | 1.00 | 0.00 | 1 |
| `b_lunge` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 26.2 | 9.4 | LUNGE | 1.67 | 0.52 | 3 |
| `b_lunge` | 1 | `deep_mixed` | deep | 0.00 [0.00, 0.06] | 47.5 | 7.5 | LUNGE | 1.48 | 2.28 | 11 |
| `b_lunge` | 1 | `deep_caster` | deep | 0.17 [0.09, 0.28] | 51.2 | 23.0 | LUNGE | 1.95 | 11.42 | 7 |
| `b_lunge` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 47.7 | 5.8 | LUNGE | 1.00 | 1.45 | 10 |
| `b_lunge` | 1 | `opt_gnoll` | optional | 0.02 [0.00, 0.09] | 48.8 | 9.6 | LUNGE | 2.08 | 2.23 | 11 |
| `b_bomb` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 0.0 | 7.0 | BOMB | 1.00 | 0.00 | 1 |
| `b_bomb` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 10.0 | 8.2 | BOMB | 1.00 | 0.00 | 4 |
| `b_bomb` | 1 | `deep_mixed` | deep | 0.17 [0.09, 0.28] | 48.5 | 9.2 | BOMB | 1.43 | 3.28 | 14 |
| `b_bomb` | 1 | `deep_caster` | deep | 0.78 [0.66, 0.87] | 29.3 | 15.7 | BOMB | 1.92 | 3.33 | 7 |
| `b_bomb` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 50.7 | 6.8 | BOMB | 0.73 | 2.72 | 9 |
| `b_bomb` | 1 | `opt_gnoll` | optional | 0.40 [0.29, 0.53] | 36.4 | 11.1 | BOMB | 1.00 | 3.25 | 11 |
| `b_shockwave` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 14.0 | 8.0 | SHOCKWAVE | 1.00 | 0.00 | 1 |
| `b_shockwave` | 1 | `early_pair` | early | 1.00 [0.94, 1.00] | 25.8 | 9.7 | SHOCKWAVE | 1.42 | 0.93 | 5 |
| `b_shockwave` | 1 | `deep_mixed` | deep | 0.00 [0.00, 0.06] | 47.0 | 7.7 | SHOCKWAVE | 1.45 | 2.28 | 15 |
| `b_shockwave` | 1 | `deep_caster` | deep | 0.00 [0.00, 0.06] | 53.7 | 30.7 | SHOCKWAVE | 1.27 | 18.10 | 10 |
| `b_shockwave` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 46.8 | 5.7 | SHOCKWAVE | 1.00 | 1.25 | 14 |
| `b_shockwave` | 1 | `opt_gnoll` | optional | 0.35 [0.24, 0.48] | 49.9 | 11.3 | SHOCKWAVE | 2.08 | 3.47 | 12 |
| `b_iron` | 1 | `early_hob` | early | 1.00 [0.94, 1.00] | 15.0 | 9.0 | IRON_HIDE | 1.00 | 0.00 | 1 |
| `b_iron` | 1 | `early_pair` | early | 0.00 [0.00, 0.06] | 52.3 | 17.1 | IRON_HIDE | 3.50 | 7.00 | 5 |
| `b_iron` | 1 | `deep_mixed` | deep | 0.00 [0.00, 0.06] | 49.1 | 7.9 | IRON_HIDE | 1.33 | 1.98 | 12 |
| `b_iron` | 1 | `deep_caster` | deep | 0.00 [0.00, 0.06] | 52.4 | 23.6 | IRON_HIDE | 2.10 | 11.47 | 11 |
| `b_iron` | 1 | `opt_archers` | optional | 0.00 [0.00, 0.06] | 48.8 | 7.0 | IRON_HIDE | 1.00 | 2.20 | 9 |
| `b_iron` | 1 | `opt_gnoll` | optional | 0.00 [0.00, 0.06] | 49.9 | 11.3 | IRON_HIDE | 2.00 | 3.45 | 11 |
| `melee_1` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 22.1 | 18.5 | PUSH | 0.00 | 0.00 | 4 |
| `melee_1` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 15.2 | 12.3 | PUSH | 0.00 | 0.00 | 30 |
| `melee_1` | 3 | `deep_mixed` | deep | 0.65 [0.52, 0.76] | 36.0 | 17.8 | PUSH | 0.00 | 9.00 | 48 |
| `melee_1` | 3 | `deep_caster` | deep | 0.98 [0.91, 1.00] | 19.9 | 17.4 | PUSH | 0.00 | 1.53 | 21 |
| `melee_1` | 3 | `opt_archers` | optional | 0.17 [0.09, 0.28] | 48.6 | 21.1 | PUSH | 0.00 | 13.32 | 34 |
| `melee_1` | 3 | `opt_gnoll` | optional | 0.55 [0.42, 0.67] | 38.1 | 24.1 | PUSH | 0.00 | 10.33 | 48 |
| `b_strike` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 17.5 | 16.5 | HEAVY_STRIKE | 0.00 | 0.00 | 2 |
| `b_strike` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 11.1 | 12.0 | HEAVY_STRIKE | 0.35 | 0.00 | 12 |
| `b_strike` | 3 | `deep_mixed` | deep | 0.97 [0.89, 0.99] | 24.2 | 11.8 | HEAVY_STRIKE | 1.02 | 2.23 | 41 |
| `b_strike` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 16.3 | 11.8 | HEAVY_STRIKE | 1.40 | 0.00 | 14 |
| `b_strike` | 3 | `opt_archers` | optional | 0.47 [0.35, 0.59] | 41.3 | 17.2 | HEAVY_STRIKE | 0.37 | 9.62 | 25 |
| `b_strike` | 3 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 16.5 | 12.5 | HEAVY_STRIKE | 1.85 | 0.38 | 45 |
| `b_knife` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 2.3 | 8.0 | THROWING_KNIFE | 2.00 | 0.00 | 2 |
| `b_knife` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 5.0 | 8.8 | THROWING_KNIFE | 1.97 | 0.00 | 8 |
| `b_knife` | 3 | `deep_mixed` | deep | 1.00 [0.94, 1.00] | 29.8 | 14.6 | THROWING_KNIFE | 4.58 | 1.87 | 41 |
| `b_knife` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 12.9 | 12.4 | THROWING_KNIFE | 3.60 | 0.03 | 15 |
| `b_knife` | 3 | `opt_archers` | optional | 0.72 [0.59, 0.81] | 41.0 | 16.5 | THROWING_KNIFE | 3.27 | 6.88 | 29 |
| `b_knife` | 3 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 24.1 | 15.6 | THROWING_KNIFE | 5.38 | 0.12 | 56 |
| `b_dressing` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 22.1 | 18.5 | FIELD_DRESSING | 0.00 | 0.00 | 4 |
| `b_dressing` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 15.4 | 12.1 | FIELD_DRESSING | 0.00 | 0.00 | 29 |
| `b_dressing` | 3 | `deep_mixed` | deep | 0.98 [0.91, 1.00] | 36.3 | 15.4 | FIELD_DRESSING | 1.50 | 2.70 | 47 |
| `b_dressing` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 19.1 | 15.1 | FIELD_DRESSING | 0.03 | 0.00 | 19 |
| `b_dressing` | 3 | `opt_archers` | optional | 0.75 [0.63, 0.84] | 49.8 | 17.1 | FIELD_DRESSING | 2.15 | 4.80 | 32 |
| `b_dressing` | 3 | `opt_gnoll` | optional | 0.93 [0.84, 0.97] | 33.3 | 17.8 | FIELD_DRESSING | 1.08 | 1.52 | 50 |
| `b_lunge` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 9.3 | 10.0 | LUNGE | 1.00 | 0.00 | 2 |
| `b_lunge` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 8.7 | 9.5 | LUNGE | 0.92 | 0.00 | 17 |
| `b_lunge` | 3 | `deep_mixed` | deep | 0.95 [0.86, 0.98] | 28.9 | 12.9 | LUNGE | 1.92 | 3.37 | 48 |
| `b_lunge` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 15.8 | 11.4 | LUNGE | 1.22 | 0.00 | 17 |
| `b_lunge` | 3 | `opt_archers` | optional | 0.68 [0.56, 0.79] | 37.5 | 14.1 | LUNGE | 1.43 | 5.88 | 27 |
| `b_lunge` | 3 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 20.2 | 13.2 | LUNGE | 2.12 | 0.35 | 53 |
| `b_bomb` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 2.3 | 8.0 | BOMB | 1.00 | 0.00 | 2 |
| `b_bomb` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 5.1 | 8.1 | BOMB | 0.68 | 0.00 | 11 |
| `b_bomb` | 3 | `deep_mixed` | deep | 0.92 [0.82, 0.96] | 24.9 | 14.2 | BOMB | 1.58 | 3.10 | 44 |
| `b_bomb` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 14.7 | 12.4 | BOMB | 1.12 | 0.02 | 23 |
| `b_bomb` | 3 | `opt_archers` | optional | 0.82 [0.70, 0.89] | 35.9 | 15.0 | BOMB | 2.28 | 5.02 | 27 |
| `b_bomb` | 3 | `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 16.9 | 14.4 | BOMB | 0.93 | 0.40 | 40 |
| `b_shockwave` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 22.1 | 18.5 | SHOCKWAVE | 0.00 | 0.00 | 4 |
| `b_shockwave` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 14.8 | 12.3 | SHOCKWAVE | 0.02 | 0.00 | 29 |
| `b_shockwave` | 3 | `deep_mixed` | deep | 0.87 [0.76, 0.93] | 34.9 | 15.9 | SHOCKWAVE | 0.57 | 6.32 | 44 |
| `b_shockwave` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 17.8 | 14.2 | SHOCKWAVE | 0.37 | 0.63 | 20 |
| `b_shockwave` | 3 | `opt_archers` | optional | 0.30 [0.20, 0.43] | 47.6 | 18.6 | SHOCKWAVE | 0.50 | 10.50 | 35 |
| `b_shockwave` | 3 | `opt_gnoll` | optional | 0.90 [0.80, 0.95] | 34.7 | 21.7 | SHOCKWAVE | 1.28 | 6.12 | 51 |
| `b_iron` | 3 | `early_hob` | early | 1.00 [0.94, 1.00] | 21.9 | 20.5 | IRON_HIDE | 1.00 | 0.00 | 8 |
| `b_iron` | 3 | `early_pair` | early | 1.00 [0.94, 1.00] | 15.6 | 13.6 | IRON_HIDE | 1.23 | 0.02 | 46 |
| `b_iron` | 3 | `deep_mixed` | deep | 0.48 [0.36, 0.61] | 40.8 | 22.8 | IRON_HIDE | 2.97 | 11.08 | 54 |
| `b_iron` | 3 | `deep_caster` | deep | 1.00 [0.94, 1.00] | 17.5 | 15.2 | IRON_HIDE | 1.73 | 0.83 | 31 |
| `b_iron` | 3 | `opt_archers` | optional | 0.10 [0.05, 0.20] | 49.5 | 22.1 | IRON_HIDE | 1.60 | 12.75 | 37 |
| `b_iron` | 3 | `opt_gnoll` | optional | 0.88 [0.78, 0.94] | 31.6 | 21.7 | IRON_HIDE | 3.73 | 5.47 | 60 |

## 표 2 — 기준선 `melee_1` 대비 Δ

같은 인원·같은 아레나의 기준선 칸과 비교한다. Δ승률은 퍼센트포인트, Δ피해는 개인별 평균 피해의 절대 변화량이다(피해는 낮을수록 좋다).

| 빌드 | 인원 | 아레나 | Δ승률(pp) | Δ피해 |
| --- | --- | --- | --- | --- |
| `b_strike` | 1 | `early_hob` | +0.0 | -7.0 |
| `b_strike` | 1 | `early_pair` | +41.7 | -13.6 |
| `b_strike` | 1 | `deep_mixed` | +0.0 | +2.9 |
| `b_strike` | 1 | `deep_caster` | +0.0 | +0.3 |
| `b_strike` | 1 | `opt_archers` | +0.0 | +2.4 |
| `b_strike` | 1 | `opt_gnoll` | +70.0 | -12.2 |
| `b_strike` | 3 | `early_hob` | +0.0 | -4.7 |
| `b_strike` | 3 | `early_pair` | +0.0 | -4.1 |
| `b_strike` | 3 | `deep_mixed` | +31.7 | -11.8 |
| `b_strike` | 3 | `deep_caster` | +1.7 | -3.6 |
| `b_strike` | 3 | `opt_archers` | +30.0 | -7.4 |
| `b_strike` | 3 | `opt_gnoll` | +45.0 | -21.6 |
| `b_knife` | 1 | `early_hob` | +0.0 | -14.0 |
| `b_knife` | 1 | `early_pair` | +41.7 | -20.1 |
| `b_knife` | 1 | `deep_mixed` | +0.0 | +0.2 |
| `b_knife` | 1 | `deep_caster` | +100.0 | -21.9 |
| `b_knife` | 1 | `opt_archers` | +0.0 | +1.2 |
| `b_knife` | 1 | `opt_gnoll` | +40.0 | -15.0 |
| `b_knife` | 3 | `early_hob` | +0.0 | -19.8 |
| `b_knife` | 3 | `early_pair` | +0.0 | -10.2 |
| `b_knife` | 3 | `deep_mixed` | +35.0 | -6.2 |
| `b_knife` | 3 | `deep_caster` | +1.7 | -7.0 |
| `b_knife` | 3 | `opt_archers` | +55.0 | -7.7 |
| `b_knife` | 3 | `opt_gnoll` | +45.0 | -14.0 |
| `b_dressing` | 1 | `early_hob` | +0.0 | +0.0 |
| `b_dressing` | 1 | `early_pair` | +23.3 | +8.7 |
| `b_dressing` | 1 | `deep_mixed` | +0.0 | +20.9 |
| `b_dressing` | 1 | `deep_caster` | +100.0 | -1.7 |
| `b_dressing` | 1 | `opt_archers` | +0.0 | +15.0 |
| `b_dressing` | 1 | `opt_gnoll` | +3.3 | +17.2 |
| `b_dressing` | 3 | `early_hob` | +0.0 | +0.0 |
| `b_dressing` | 3 | `early_pair` | +0.0 | +0.2 |
| `b_dressing` | 3 | `deep_mixed` | +33.3 | +0.3 |
| `b_dressing` | 3 | `deep_caster` | +1.7 | -0.9 |
| `b_dressing` | 3 | `opt_archers` | +58.3 | +1.2 |
| `b_dressing` | 3 | `opt_gnoll` | +38.3 | -4.7 |
| `b_lunge` | 1 | `early_hob` | +0.0 | +0.0 |
| `b_lunge` | 1 | `early_pair` | +41.7 | -5.4 |
| `b_lunge` | 1 | `deep_mixed` | +0.0 | -0.7 |
| `b_lunge` | 1 | `deep_caster` | +16.7 | -2.2 |
| `b_lunge` | 1 | `opt_archers` | +0.0 | -1.8 |
| `b_lunge` | 1 | `opt_gnoll` | +1.7 | -2.6 |
| `b_lunge` | 3 | `early_hob` | +0.0 | -12.8 |
| `b_lunge` | 3 | `early_pair` | +0.0 | -6.6 |
| `b_lunge` | 3 | `deep_mixed` | +30.0 | -7.1 |
| `b_lunge` | 3 | `deep_caster` | +1.7 | -4.1 |
| `b_lunge` | 3 | `opt_archers` | +51.7 | -11.1 |
| `b_lunge` | 3 | `opt_gnoll` | +45.0 | -17.9 |
| `b_bomb` | 1 | `early_hob` | +0.0 | -14.0 |
| `b_bomb` | 1 | `early_pair` | +41.7 | -21.5 |
| `b_bomb` | 1 | `deep_mixed` | +16.7 | +0.3 |
| `b_bomb` | 1 | `deep_caster` | +78.3 | -24.2 |
| `b_bomb` | 1 | `opt_archers` | +0.0 | +1.2 |
| `b_bomb` | 1 | `opt_gnoll` | +40.0 | -15.0 |
| `b_bomb` | 3 | `early_hob` | +0.0 | -19.8 |
| `b_bomb` | 3 | `early_pair` | +0.0 | -10.2 |
| `b_bomb` | 3 | `deep_mixed` | +26.7 | -11.2 |
| `b_bomb` | 3 | `deep_caster` | +1.7 | -5.2 |
| `b_bomb` | 3 | `opt_archers` | +65.0 | -12.7 |
| `b_bomb` | 3 | `opt_gnoll` | +45.0 | -21.2 |
| `b_shockwave` | 1 | `early_hob` | +0.0 | +0.0 |
| `b_shockwave` | 1 | `early_pair` | +41.7 | -5.8 |
| `b_shockwave` | 1 | `deep_mixed` | +0.0 | -1.2 |
| `b_shockwave` | 1 | `deep_caster` | +0.0 | +0.3 |
| `b_shockwave` | 1 | `opt_archers` | +0.0 | -2.7 |
| `b_shockwave` | 1 | `opt_gnoll` | +35.0 | -1.5 |
| `b_shockwave` | 3 | `early_hob` | +0.0 | +0.0 |
| `b_shockwave` | 3 | `early_pair` | +0.0 | -0.4 |
| `b_shockwave` | 3 | `deep_mixed` | +21.7 | -1.1 |
| `b_shockwave` | 3 | `deep_caster` | +1.7 | -2.2 |
| `b_shockwave` | 3 | `opt_archers` | +13.3 | -1.1 |
| `b_shockwave` | 3 | `opt_gnoll` | +35.0 | -3.4 |
| `b_iron` | 1 | `early_hob` | +0.0 | +1.0 |
| `b_iron` | 1 | `early_pair` | -58.3 | +20.8 |
| `b_iron` | 1 | `deep_mixed` | +0.0 | +1.0 |
| `b_iron` | 1 | `deep_caster` | +0.0 | -1.1 |
| `b_iron` | 1 | `opt_archers` | +0.0 | -0.7 |
| `b_iron` | 1 | `opt_gnoll` | +0.0 | -1.5 |
| `b_iron` | 3 | `early_hob` | +0.0 | -0.3 |
| `b_iron` | 3 | `early_pair` | +0.0 | +0.3 |
| `b_iron` | 3 | `deep_mixed` | -16.7 | +4.8 |
| `b_iron` | 3 | `deep_caster` | +1.7 | -2.4 |
| `b_iron` | 3 | `opt_archers` | -6.7 | +0.8 |
| `b_iron` | 3 | `opt_gnoll` | +33.3 | -6.5 |

빌드별 요약(전 칸 기준, 우세/열세는 Δ승률의 부호):

| 빌드 | 장착 스킬 | 사용 평균 | Δ승률 평균(pp) | 우세 칸 | 열세 칸 | 1인 Δ승률 ≥ +20pp 아레나 |
| --- | --- | --- | --- | --- | --- | --- |
| `b_strike` | HEAVY_STRIKE | 1.12 | +18.3 | 6/12 | 0/12 | 2/6 |
| `b_knife` | THROWING_KNIFE | 3.01 | +26.5 | 7/12 | 0/12 | 3/6 |
| `b_dressing` | FIELD_DRESSING | 0.92 | +21.5 | 7/12 | 0/12 | 2/6 |
| `b_lunge` | LUNGE | 1.48 | +15.7 | 7/12 | 0/12 | 1/6 |
| `b_bomb` | BOMB | 1.22 | +26.2 | 8/12 | 0/12 | 3/6 |
| `b_shockwave` | SHOCKWAVE | 0.91 | +12.4 | 6/12 | 0/12 | 2/6 |
| `b_iron` | IRON_HIDE | 1.93 | -3.9 | 2/12 | 3/12 | 0/6 |

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

사용 평균이 0인 칸이 있는 빌드: `melee_1`, `b_dressing`, `b_strike`, `b_shockwave`. 각 빌드를 사용 평균 0인 바로 그 칸의 config로·시드 3개씩 다시 돌리며, 매 라운드 `Abilities.legal(영웅, 스킬, 보이는 적 각각 또는 자신)`을 검사해 합법이었던 라운드 수를 셌다.

| 빌드 | 스킬 | 사용 평균 0인 칸 | 진단 |
| --- | --- | --- | --- |
| `melee_1` | PUSH | 전 칸 | `PUSH`는 능력이 아니라 기본 전술(`Abilities.DEFINITIONS` 밖)이라 `legal` 진단 대상이 아니다 — 규칙 조건 `CHARGING`이 맞은 라운드가 없었다는 뜻이다. |
| `b_dressing` | FIELD_DRESSING | 1인/`early_hob`, 3인/`early_hob`, 3인/`early_pair` | 합법 라운드 10/109 — 규칙이 고르지 않음 |
| `b_strike` | HEAVY_STRIKE | 3인/`early_hob` | 합법인 라운드 없음(0/46) — 사거리/조건 확인 |
| `b_shockwave` | SHOCKWAVE | 3인/`early_hob` | 합법 라운드 52/52 — 규칙이 고르지 않음 |

`합법 라운드 N/M`이 0이 아니면 스킬은 쓸 수 있었는데 규칙이 그 라운드를 고르지 않았다는 뜻이고(규칙 조건 쪽 문제), 0이면 `legal`이 한 번도 참이 되지 않았다는 뜻이다(사거리·대상·쿨다운 쪽 문제).

## 추적 계획

1. 사장 후보의 원인을 규칙 조건과 사거리로 분리해 재실험(진단 줄이 가리키는 쪽만 바꾼다)
2. 지배 후보는 비용 축(쿨다운·자원)을 하나만 바꿔 다시 측정
3. 물자 축(0 vs 2)을 더해 스킬과 소모품의 대체 관계 측정
4. 3인에서 동료도 같은 빌드를 드는 조건 추가(현재는 파티 전원이 같은 빌드다)

