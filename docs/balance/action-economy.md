# 행동 경제 실험 결과

생성: `tests/action_economy.gd`(수동 도구) · 커밋 `b4c4a80` · 날짜 2026-09-22
근거: [밸런스 방법론](../balance-method.ko.md) §8-1 · 설계: [조우 시뮬레이터 설계](../superpowers/specs/2026-09-22-encounter-sim-design.md) §5.2·§6

- 시드 묶음: `S1` 200개 (1000~1199)
- 솔로 HP 스케일: `SOLO_HP_PERCENT 45` / `SOLO_HP_MIN 20` / `SOLO_HP_MAX 32` (파티 인원 1일 때만 적용, 실험 조건의 일부)
- 봇 정책: `tactical` (`expedition/sim/bot_policy.gd`: 접근 → 회복·방어 → 자동 공격)
- 아레나 공통 spec: size 20 · room [5, 5, 9, 9] · door [9, 4] · pillars [[8, 8], [10, 10]] · party_entry [9, 5] · light 90 · supplies [1, 0, 0, 0, 0, 1]
- 행렬: 규칙 3 × 인원 3 × 빌드 2 × 아레나 6 × 시드 200 = 21600전투
- 실행 시간: 916.4초

> 전투 자체는 결정론적(명중 판정 없음)이며, 시드는 적 배치만 바꾼다. 신뢰구간은 배치 분산에 대한 것이다.
> `distinct`는 시드 묶음에서 나온 서로 다른 `(결과, 라운드, 피해)` 조합의 수다 — 1이면 그 칸의 구간은 배치 분산이 없다는 뜻이다.

아레나 구성:

| 아레나 | 티어 | 구성 |
| --- | --- | --- |
| `early_hob` | early | dcss_hobgoblin/MELEE |
| `early_pair` | early | kobold/MELEE, dcss_rat/MELEE |
| `deep_mixed` | deep | dcss_hobgoblin/MELEE, goblin/RANGED, kobold/MELEE |
| `deep_caster` | deep | dcss_orc/MELEE, goblin/CASTER |
| `opt_archers` | optional | kobold/RANGED, goblin/RANGED, dcss_rat/MELEE |
| `opt_gnoll` | optional | dcss_gnoll/MELEE, dcss_rat/MELEE, dcss_rat/MELEE |

규칙:

| 규칙 | `solo_actions` | `solo_max_members` |
| --- | --- | --- |
| current | 1 | 0 |
| A | 2 | 0 |
| B | 1 | 2 |

## 표 1 — 규칙 × 인원 × 빌드 × 아레나

| 규칙 | 인원 | 빌드 | 아레나 | 티어 | 승률 [95% CI] | distinct | 평균 피해(개인별) | p95 피해 | 평균 라운드 | 첫 사망 라운드 중앙값 | 회복 사용 평균 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| current | 1 | starter | `early_hob` | early | 1.00 [0.98, 1.00] | 1 | 14.0 | 14.0 | 8.0 | — | 0.00 |
| current | 1 | starter | `early_pair` | early | 0.50 [0.43, 0.57] | 5 | 49.5 | 84.0 | 12.2 | 16 | 1.00 |
| current | 1 | starter | `deep_mixed` | deep | 0.10 [0.07, 0.16] | 14 | 73.7 | 83.0 | 10.1 | 9 | 2.00 |
| current | 1 | starter | `deep_caster` | deep | 0.60 [0.54, 0.67] | 10 | 60.7 | 83.0 | 13.8 | 16 | 1.19 |
| current | 1 | starter | `opt_archers` | optional | 0.00 [0.00, 0.02] | 12 | 66.1 | 74.0 | 6.7 | 7 | 1.61 |
| current | 1 | starter | `opt_gnoll` | optional | 0.00 [0.00, 0.02] | 15 | 69.8 | 73.0 | 11.5 | 12 | 2.00 |
| current | 1 | melee_1 | `early_hob` | early | 1.00 [0.98, 1.00] | 1 | 14.0 | 14.0 | 8.0 | — | 0.00 |
| current | 1 | melee_1 | `early_pair` | early | 0.50 [0.43, 0.57] | 5 | 49.5 | 84.0 | 12.2 | 16 | 1.00 |
| current | 1 | melee_1 | `deep_mixed` | deep | 0.10 [0.07, 0.16] | 14 | 73.7 | 83.0 | 10.1 | 9 | 2.00 |
| current | 1 | melee_1 | `deep_caster` | deep | 0.60 [0.54, 0.67] | 10 | 60.7 | 83.0 | 13.8 | 16 | 1.19 |
| current | 1 | melee_1 | `opt_archers` | optional | 0.00 [0.00, 0.02] | 12 | 66.1 | 74.0 | 6.7 | 7 | 1.61 |
| current | 1 | melee_1 | `opt_gnoll` | optional | 0.00 [0.00, 0.02] | 15 | 69.8 | 73.0 | 11.5 | 12 | 2.00 |
| current | 2 | starter | `early_hob` | early | 1.00 [0.98, 1.00] | 4 | 12.3 | 28.0 | 8.5 | — | 0.00 |
| current | 2 | starter | `early_pair` | early | 0.97 [0.94, 0.99] | 40 | 16.9 | 36.0 | 9.5 | 15 | 0.05 |
| current | 2 | starter | `deep_mixed` | deep | 0.84 [0.78, 0.88] | 128 | 47.4 | 80.0 | 13.8 | 12 | 1.48 |
| current | 2 | starter | `deep_caster` | deep | 0.89 [0.83, 0.92] | 28 | 28.5 | 81.0 | 13.1 | 23 | 0.41 |
| current | 2 | starter | `opt_archers` | optional | 0.69 [0.62, 0.75] | 38 | 56.2 | 84.0 | 13.3 | 11 | 1.93 |
| current | 2 | starter | `opt_gnoll` | optional | 0.51 [0.44, 0.57] | 141 | 53.4 | 83.0 | 18.5 | 18 | 1.45 |
| current | 2 | melee_1 | `early_hob` | early | 1.00 [0.98, 1.00] | 4 | 12.3 | 28.0 | 8.5 | — | 0.00 |
| current | 2 | melee_1 | `early_pair` | early | 0.97 [0.94, 0.99] | 40 | 16.9 | 36.0 | 9.5 | 15 | 0.05 |
| current | 2 | melee_1 | `deep_mixed` | deep | 0.84 [0.78, 0.88] | 128 | 47.3 | 80.0 | 13.8 | 12 | 1.48 |
| current | 2 | melee_1 | `deep_caster` | deep | 0.89 [0.83, 0.92] | 28 | 28.5 | 81.0 | 13.1 | 23 | 0.41 |
| current | 2 | melee_1 | `opt_archers` | optional | 0.69 [0.62, 0.75] | 38 | 56.0 | 84.0 | 13.3 | 11 | 1.93 |
| current | 2 | melee_1 | `opt_gnoll` | optional | 0.53 [0.46, 0.60] | 145 | 51.4 | 83.0 | 17.9 | 18 | 1.37 |
| current | 3 | starter | `early_hob` | early | 1.00 [0.98, 1.00] | 4 | 22.2 | 49.0 | 18.5 | 15 | 0.00 |
| current | 3 | starter | `early_pair` | early | 1.00 [0.98, 1.00] | 51 | 13.4 | 51.0 | 11.6 | 15 | 0.00 |
| current | 3 | starter | `deep_mixed` | deep | 0.97 [0.94, 0.99] | 99 | 35.3 | 72.0 | 14.6 | 7 | 0.93 |
| current | 3 | starter | `deep_caster` | deep | 1.00 [0.98, 1.00] | 27 | 17.4 | 39.0 | 14.7 | 23 | 0.00 |
| current | 3 | starter | `opt_archers` | optional | 0.86 [0.81, 0.90] | 58 | 46.8 | 84.0 | 16.4 | 7 | 1.61 |
| current | 3 | starter | `opt_gnoll` | optional | 0.81 [0.76, 0.86] | 170 | 36.7 | 77.0 | 18.6 | 12 | 0.71 |
| current | 3 | melee_1 | `early_hob` | early | 1.00 [0.98, 1.00] | 4 | 22.2 | 49.0 | 18.5 | 15 | 0.00 |
| current | 3 | melee_1 | `early_pair` | early | 1.00 [0.98, 1.00] | 51 | 13.4 | 51.0 | 11.6 | 15 | 0.00 |
| current | 3 | melee_1 | `deep_mixed` | deep | 0.97 [0.94, 0.99] | 99 | 35.2 | 72.0 | 14.6 | 7 | 0.93 |
| current | 3 | melee_1 | `deep_caster` | deep | 1.00 [0.98, 1.00] | 27 | 16.9 | 39.0 | 14.7 | 23 | 0.00 |
| current | 3 | melee_1 | `opt_archers` | optional | 0.86 [0.81, 0.90] | 58 | 46.6 | 84.0 | 16.4 | 7 | 1.61 |
| current | 3 | melee_1 | `opt_gnoll` | optional | 0.88 [0.82, 0.91] | 159 | 33.8 | 66.0 | 17.3 | 12 | 0.51 |
| A | 1 | starter | `early_hob` | early | 1.00 [0.98, 1.00] | 1 | 0.0 | 0.0 | 5.0 | — | 0.00 |
| A | 1 | starter | `early_pair` | early | 1.00 [0.98, 1.00] | 4 | 6.7 | 9.0 | 6.1 | — | 0.00 |
| A | 1 | starter | `deep_mixed` | deep | 1.00 [0.98, 1.00] | 17 | 39.3 | 52.0 | 8.3 | — | 0.23 |
| A | 1 | starter | `deep_caster` | deep | 1.00 [0.98, 1.00] | 5 | 8.9 | 15.0 | 6.3 | — | 0.00 |
| A | 1 | starter | `opt_archers` | optional | 1.00 [0.98, 1.00] | 18 | 60.8 | 73.0 | 9.1 | — | 1.18 |
| A | 1 | starter | `opt_gnoll` | optional | 1.00 [0.98, 1.00] | 15 | 19.4 | 31.0 | 8.0 | — | 0.00 |
| A | 1 | melee_1 | `early_hob` | early | 1.00 [0.98, 1.00] | 1 | 0.0 | 0.0 | 5.0 | — | 0.00 |
| A | 1 | melee_1 | `early_pair` | early | 1.00 [0.98, 1.00] | 4 | 6.7 | 9.0 | 6.1 | — | 0.00 |
| A | 1 | melee_1 | `deep_mixed` | deep | 1.00 [0.98, 1.00] | 17 | 39.3 | 52.0 | 8.3 | — | 0.23 |
| A | 1 | melee_1 | `deep_caster` | deep | 1.00 [0.98, 1.00] | 5 | 8.9 | 15.0 | 6.3 | — | 0.00 |
| A | 1 | melee_1 | `opt_archers` | optional | 1.00 [0.98, 1.00] | 18 | 60.8 | 73.0 | 9.1 | — | 1.18 |
| A | 1 | melee_1 | `opt_gnoll` | optional | 1.00 [0.98, 1.00] | 15 | 19.4 | 31.0 | 8.0 | — | 0.00 |
| A | 2 | starter | `early_hob` | early | 1.00 [0.98, 1.00] | 4 | 12.3 | 28.0 | 8.5 | — | 0.00 |
| A | 2 | starter | `early_pair` | early | 0.97 [0.94, 0.99] | 40 | 16.9 | 36.0 | 9.5 | 15 | 0.05 |
| A | 2 | starter | `deep_mixed` | deep | 0.84 [0.78, 0.88] | 128 | 47.4 | 80.0 | 13.8 | 12 | 1.48 |
| A | 2 | starter | `deep_caster` | deep | 0.89 [0.83, 0.92] | 28 | 28.5 | 81.0 | 13.1 | 23 | 0.41 |
| A | 2 | starter | `opt_archers` | optional | 0.69 [0.62, 0.75] | 38 | 56.2 | 84.0 | 13.3 | 11 | 1.93 |
| A | 2 | starter | `opt_gnoll` | optional | 0.51 [0.44, 0.57] | 141 | 53.4 | 83.0 | 18.5 | 18 | 1.45 |
| A | 2 | melee_1 | `early_hob` | early | 1.00 [0.98, 1.00] | 4 | 12.3 | 28.0 | 8.5 | — | 0.00 |
| A | 2 | melee_1 | `early_pair` | early | 0.97 [0.94, 0.99] | 40 | 16.9 | 36.0 | 9.5 | 15 | 0.05 |
| A | 2 | melee_1 | `deep_mixed` | deep | 0.84 [0.78, 0.88] | 128 | 47.3 | 80.0 | 13.8 | 12 | 1.48 |
| A | 2 | melee_1 | `deep_caster` | deep | 0.89 [0.83, 0.92] | 28 | 28.5 | 81.0 | 13.1 | 23 | 0.41 |
| A | 2 | melee_1 | `opt_archers` | optional | 0.69 [0.62, 0.75] | 38 | 56.0 | 84.0 | 13.3 | 11 | 1.93 |
| A | 2 | melee_1 | `opt_gnoll` | optional | 0.53 [0.46, 0.60] | 145 | 51.4 | 83.0 | 17.9 | 18 | 1.37 |
| A | 3 | starter | `early_hob` | early | 1.00 [0.98, 1.00] | 4 | 22.2 | 49.0 | 18.5 | 15 | 0.00 |
| A | 3 | starter | `early_pair` | early | 1.00 [0.98, 1.00] | 51 | 13.4 | 51.0 | 11.6 | 15 | 0.00 |
| A | 3 | starter | `deep_mixed` | deep | 0.97 [0.94, 0.99] | 99 | 35.3 | 72.0 | 14.6 | 7 | 0.93 |
| A | 3 | starter | `deep_caster` | deep | 1.00 [0.98, 1.00] | 27 | 17.4 | 39.0 | 14.7 | 23 | 0.00 |
| A | 3 | starter | `opt_archers` | optional | 0.86 [0.81, 0.90] | 58 | 46.8 | 84.0 | 16.4 | 7 | 1.61 |
| A | 3 | starter | `opt_gnoll` | optional | 0.81 [0.76, 0.86] | 170 | 36.7 | 77.0 | 18.6 | 12 | 0.71 |
| A | 3 | melee_1 | `early_hob` | early | 1.00 [0.98, 1.00] | 4 | 22.2 | 49.0 | 18.5 | 15 | 0.00 |
| A | 3 | melee_1 | `early_pair` | early | 1.00 [0.98, 1.00] | 51 | 13.4 | 51.0 | 11.6 | 15 | 0.00 |
| A | 3 | melee_1 | `deep_mixed` | deep | 0.97 [0.94, 0.99] | 99 | 35.2 | 72.0 | 14.6 | 7 | 0.93 |
| A | 3 | melee_1 | `deep_caster` | deep | 1.00 [0.98, 1.00] | 27 | 16.9 | 39.0 | 14.7 | 23 | 0.00 |
| A | 3 | melee_1 | `opt_archers` | optional | 0.86 [0.81, 0.90] | 58 | 46.6 | 84.0 | 16.4 | 7 | 1.61 |
| A | 3 | melee_1 | `opt_gnoll` | optional | 0.88 [0.82, 0.91] | 159 | 33.8 | 66.0 | 17.3 | 12 | 0.51 |
| B | 1 | starter | `early_hob` | early | 1.00 [0.98, 1.00] | 1 | 14.0 | 14.0 | 8.0 | — | 0.00 |
| B | 1 | starter | `early_pair` | early | 0.50 [0.43, 0.57] | 5 | 49.5 | 84.0 | 12.2 | 16 | 1.00 |
| B | 1 | starter | `deep_mixed` | deep | 0.84 [0.78, 0.88] | 4 | 67.2 | 81.0 | 12.4 | 13 | 1.40 |
| B | 1 | starter | `deep_caster` | deep | 0.60 [0.54, 0.67] | 10 | 60.7 | 83.0 | 13.8 | 16 | 1.19 |
| B | 1 | starter | `opt_archers` | optional | 0.00 [0.00, 0.02] | 5 | 82.8 | 84.0 | 10.4 | 11 | 2.00 |
| B | 1 | starter | `opt_gnoll` | optional | 0.50 [0.43, 0.57] | 5 | 49.5 | 84.0 | 12.2 | 16 | 1.00 |
| B | 1 | melee_1 | `early_hob` | early | 1.00 [0.98, 1.00] | 1 | 14.0 | 14.0 | 8.0 | — | 0.00 |
| B | 1 | melee_1 | `early_pair` | early | 0.50 [0.43, 0.57] | 5 | 49.5 | 84.0 | 12.2 | 16 | 1.00 |
| B | 1 | melee_1 | `deep_mixed` | deep | 0.84 [0.78, 0.88] | 4 | 67.2 | 81.0 | 12.4 | 13 | 1.40 |
| B | 1 | melee_1 | `deep_caster` | deep | 0.60 [0.54, 0.67] | 10 | 60.7 | 83.0 | 13.8 | 16 | 1.19 |
| B | 1 | melee_1 | `opt_archers` | optional | 0.00 [0.00, 0.02] | 5 | 82.8 | 84.0 | 10.4 | 11 | 2.00 |
| B | 1 | melee_1 | `opt_gnoll` | optional | 0.50 [0.43, 0.57] | 5 | 49.5 | 84.0 | 12.2 | 16 | 1.00 |
| B | 2 | starter | `early_hob` | early | 1.00 [0.98, 1.00] | 4 | 12.3 | 28.0 | 8.5 | — | 0.00 |
| B | 2 | starter | `early_pair` | early | 0.97 [0.94, 0.99] | 40 | 16.9 | 36.0 | 9.5 | 15 | 0.05 |
| B | 2 | starter | `deep_mixed` | deep | 0.84 [0.78, 0.88] | 128 | 47.4 | 80.0 | 13.8 | 12 | 1.48 |
| B | 2 | starter | `deep_caster` | deep | 0.89 [0.83, 0.92] | 28 | 28.5 | 81.0 | 13.1 | 23 | 0.41 |
| B | 2 | starter | `opt_archers` | optional | 0.69 [0.62, 0.75] | 38 | 56.2 | 84.0 | 13.3 | 11 | 1.93 |
| B | 2 | starter | `opt_gnoll` | optional | 0.51 [0.44, 0.57] | 141 | 53.4 | 83.0 | 18.5 | 18 | 1.45 |
| B | 2 | melee_1 | `early_hob` | early | 1.00 [0.98, 1.00] | 4 | 12.3 | 28.0 | 8.5 | — | 0.00 |
| B | 2 | melee_1 | `early_pair` | early | 0.97 [0.94, 0.99] | 40 | 16.9 | 36.0 | 9.5 | 15 | 0.05 |
| B | 2 | melee_1 | `deep_mixed` | deep | 0.84 [0.78, 0.88] | 128 | 47.3 | 80.0 | 13.8 | 12 | 1.48 |
| B | 2 | melee_1 | `deep_caster` | deep | 0.89 [0.83, 0.92] | 28 | 28.5 | 81.0 | 13.1 | 23 | 0.41 |
| B | 2 | melee_1 | `opt_archers` | optional | 0.69 [0.62, 0.75] | 38 | 56.0 | 84.0 | 13.3 | 11 | 1.93 |
| B | 2 | melee_1 | `opt_gnoll` | optional | 0.53 [0.46, 0.60] | 145 | 51.4 | 83.0 | 17.9 | 18 | 1.37 |
| B | 3 | starter | `early_hob` | early | 1.00 [0.98, 1.00] | 4 | 22.2 | 49.0 | 18.5 | 15 | 0.00 |
| B | 3 | starter | `early_pair` | early | 1.00 [0.98, 1.00] | 51 | 13.4 | 51.0 | 11.6 | 15 | 0.00 |
| B | 3 | starter | `deep_mixed` | deep | 0.97 [0.94, 0.99] | 99 | 35.3 | 72.0 | 14.6 | 7 | 0.93 |
| B | 3 | starter | `deep_caster` | deep | 1.00 [0.98, 1.00] | 27 | 17.4 | 39.0 | 14.7 | 23 | 0.00 |
| B | 3 | starter | `opt_archers` | optional | 0.86 [0.81, 0.90] | 58 | 46.8 | 84.0 | 16.4 | 7 | 1.61 |
| B | 3 | starter | `opt_gnoll` | optional | 0.81 [0.76, 0.86] | 170 | 36.7 | 77.0 | 18.6 | 12 | 0.71 |
| B | 3 | melee_1 | `early_hob` | early | 1.00 [0.98, 1.00] | 4 | 22.2 | 49.0 | 18.5 | 15 | 0.00 |
| B | 3 | melee_1 | `early_pair` | early | 1.00 [0.98, 1.00] | 51 | 13.4 | 51.0 | 11.6 | 15 | 0.00 |
| B | 3 | melee_1 | `deep_mixed` | deep | 0.97 [0.94, 0.99] | 99 | 35.2 | 72.0 | 14.6 | 7 | 0.93 |
| B | 3 | melee_1 | `deep_caster` | deep | 1.00 [0.98, 1.00] | 27 | 16.9 | 39.0 | 14.7 | 23 | 0.00 |
| B | 3 | melee_1 | `opt_archers` | optional | 0.86 [0.81, 0.90] | 58 | 46.6 | 84.0 | 16.4 | 7 | 1.61 |
| B | 3 | melee_1 | `opt_gnoll` | optional | 0.88 [0.82, 0.91] | 159 | 33.8 | 66.0 | 17.3 | 12 | 0.51 |

## 표 2 — 결정 규칙 판정 (설계 §6, 사전 고정)

판정은 `tactical` 정책·`melee_1` 빌드·심부 아레나 2개(`deep_mixed`, `deep_caster`)에서만 본다.

| 규칙 | (a) 솔로 심부 승률 ≥ 70% | (b) 2인 개인별 평균 피해 < 솔로 | (c) 3인 심부 승률 ≥ 90% | 통과 |
| --- | --- | --- | --- | --- |
| current | 실패 | 통과 | 통과 | 실패 |
| A | 통과 | 실패 | 통과 | 실패 |
| B | 실패 | 통과 | 통과 | 실패 |

## 판정

**보류.** 세 조건을 모두 만족하는 규칙이 없다. 설계 §6에 따라 사망 원인을 아래에 기록하고 실험안을 다시 정의한다.

심부 아레나에서 솔로(`melee_1`)가 무너지는 지점:

| 규칙 | 아레나 | 승률 | 첫 사망 라운드 중앙값 | p95 피해 | 첫 행동 이전 피해 평균 | 평균 라운드 |
| --- | --- | --- | --- | --- | --- | --- |
| current | `deep_mixed` | 0.10 | 9 | 83.0 | 0.0 | 10.1 |
| current | `deep_caster` | 0.60 | 16 | 83.0 | 0.0 | 13.8 |
| A | `deep_mixed` | 1.00 | — | 52.0 | 0.0 | 8.3 |
| A | `deep_caster` | 1.00 | — | 15.0 | 0.0 | 6.3 |
| B | `deep_mixed` | 0.84 | 13 | 81.0 | 0.0 | 12.4 |
| B | `deep_caster` | 0.60 | 16 | 83.0 | 0.0 | 13.8 |

이 도구는 **후보를 계산해 출력할 뿐 채택을 확정하지 않는다.** 채택 확정은 사람이 이 보고서를 읽고 별도 커밋으로 한다(설계 §6·§8).
