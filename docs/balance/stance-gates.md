# 태세 게이트 G7 결과

생성: `tests/stance_gate.gd`(수동 도구) · 커밋 `ebc5d5b-dirty` · 날짜 2026-09-23
근거: [밸런스 방법론](../balance-method.ko.md) §5 · 설계: [태세 설계](../superpowers/specs/2026-09-23-stances-design.md) §4

- 시드 묶음: `S4` 40개 (8000~8039)
- 인원: [3.0] · 봇 정책: `rules`(영웅도 동료와 같은 규칙 목록을 읽고 `Tactics.choose`가 고른 행동을 누른다)
- 규칙: `current` (`solo_actions 1` / `solo_max_members 0`)
- **물자 0**: `supplies [0, 0, 0, 0, 0, 0]` — 태세의 값이 회복품에 가려지지 않는다.
- 아레나 공통 spec: size 20 · room [5, 5, 9, 9] · door [9, 4] · pillars [[8, 8], [10, 10]] · party_entry [9, 5] · light 90 · supplies [0, 0, 0, 0, 0, 0]
- 행렬: 빌드 4 × 아레나 6 × 시드 40 = 960전투
- 실행 시간: 44.0초
- 솔로 HP 스케일: `SOLO_HP_PERCENT 45` / `SOLO_HP_MIN 20` / `SOLO_HP_MAX 32` (3인 실험이라 적용되지 않는다)

> 명중 판정이 없으므로 같은 커밋·같은 시드·같은 빌드는 같은 전투를 낸다 — 표의 모든 칸은 재실행으로 재현된다.
> `역할 유지`는 `battle_stats.members[id].role_rounds`(`Stances.in_role`이 참인 라운드 / 전체 라운드)를 그 태세를 든 자리 전부에 대해 시드 묶음 전체로 합산한 비율이다.

빌드 구성:

| 빌드 | 태세 | 장착 | 규칙 |
| --- | --- | --- | --- |
| `stance_mixed` | CHARGER, SKIRMISHER, GUARDIAN | PUSH,GUARD / KOBOLD_SLING,GUARD / PUSH,GUARD | PUSH→NEAREST(CHARGING), KOBOLD_SLING→NEAREST(ALWAYS), GUARD→ALLY(ALLY_LETHAL) |
| `stance_charger` | CHARGER | PUSH, GUARD | PUSH→NEAREST(CHARGING), GUARD→ALLY(ALLY_LETHAL) |
| `stance_skirmisher` | SKIRMISHER | KOBOLD_SLING, GUARD | KOBOLD_SLING→NEAREST(ALWAYS), GUARD→ALLY(ALLY_LETHAL) |
| `stance_guardian` | GUARDIAN | PUSH, GUARD | PUSH→NEAREST(CHARGING), GUARD→ALLY(ALLY_LETHAL) |

아레나 구성:

| 아레나 | 티어 | 구성 |
| --- | --- | --- |
| `early_hob` | early | dcss_hobgoblin/MELEE |
| `early_pair` | early | kobold/MELEE, dcss_rat/MELEE |
| `deep_mixed` | deep | dcss_hobgoblin/MELEE, goblin/RANGED, kobold/MELEE |
| `deep_caster` | deep | dcss_orc/MELEE, goblin/CASTER |
| `opt_archers` | optional | kobold/RANGED, goblin/RANGED, dcss_rat/MELEE |
| `opt_gnoll` | optional | dcss_gnoll/MELEE, dcss_rat/MELEE, dcss_rat/MELEE |

## 표 1 — 빌드 × 아레나

| 빌드 | 아레나 | 티어 | 승률 [95% CI] | 평균 피해(개인별) | 평균 라운드 | 역할 유지 |
| --- | --- | --- | --- | --- | --- | --- |
| `stance_mixed` | `early_hob` | early | 1.00 [0.91, 1.00] | 21.0 | 19.1 | 돌 0.51 (124/242) 거 0.83 (202/242) 호 1.00 (40/40) |
| `stance_mixed` | `early_pair` | early | 1.00 [0.91, 1.00] | 4.5 | 9.7 | 돌 0.51 (132/260) 거 0.76 (197/260) 호 1.00 (260/260) |
| `stance_mixed` | `deep_mixed` | deep | 0.85 [0.71, 0.93] | 27.3 | 21.1 | 돌 0.44 (258/582) 거 0.83 (500/605) 호 0.89 (535/603) |
| `stance_mixed` | `deep_caster` | deep | 0.55 [0.40, 0.69] | 28.3 | 18.1 | 돌 0.47 (189/399) 거 0.78 (278/358) 호 1.00 (214/214) |
| `stance_mixed` | `opt_archers` | optional | 0.93 [0.80, 0.97] | 21.1 | 15.5 | 돌 0.42 (195/462) 거 0.77 (366/473) 호 0.92 (430/466) |
| `stance_mixed` | `opt_gnoll` | optional | 0.97 [0.87, 1.00] | 14.3 | 19.1 | 돌 0.56 (342/614) 거 0.84 (526/626) 호 0.95 (575/605) |
| `stance_charger` | `early_hob` | early | 1.00 [0.91, 1.00] | 18.7 | 16.0 | 돌 0.57 (160/280) |
| `stance_charger` | `early_pair` | early | 1.00 [0.91, 1.00] | 8.1 | 10.2 | 돌 0.40 (293/726) |
| `stance_charger` | `deep_mixed` | deep | 0.88 [0.74, 0.95] | 21.3 | 12.4 | 돌 0.44 (438/1002) |
| `stance_charger` | `deep_caster` | deep | 0.55 [0.40, 0.69] | 28.0 | 17.2 | 돌 0.47 (452/959) |
| `stance_charger` | `opt_archers` | optional | 1.00 [0.91, 1.00] | 18.1 | 11.6 | 돌 0.39 (404/1048) |
| `stance_charger` | `opt_gnoll` | optional | 1.00 [0.91, 1.00] | 12.9 | 13.8 | 돌 0.53 (711/1341) |
| `stance_skirmisher` | `early_hob` | early | 1.00 [0.91, 1.00] | 0.0 | 9.0 | 거 0.92 (440/480) |
| `stance_skirmisher` | `early_pair` | early | 1.00 [0.91, 1.00] | 4.7 | 12.0 | 거 0.77 (512/669) |
| `stance_skirmisher` | `deep_mixed` | deep | 0.95 [0.83, 0.99] | 23.8 | 17.8 | 거 0.68 (1107/1633) |
| `stance_skirmisher` | `deep_caster` | deep | 0.78 [0.62, 0.88] | 27.5 | 20.0 | 거 0.63 (730/1158) |
| `stance_skirmisher` | `opt_archers` | optional | 0.82 [0.68, 0.91] | 28.1 | 18.6 | 거 0.61 (951/1557) |
| `stance_skirmisher` | `opt_gnoll` | optional | 1.00 [0.91, 1.00] | 12.1 | 18.6 | 거 0.81 (1460/1811) |
| `stance_guardian` | `early_hob` | early | 1.00 [0.91, 1.00] | 40.2 | 31.4 | 호 0.44 (184/416) |
| `stance_guardian` | `early_pair` | early | 1.00 [0.91, 1.00] | 10.3 | 16.0 | 호 0.94 (1243/1324) |
| `stance_guardian` | `deep_mixed` | deep | 0.23 [0.12, 0.38] | 45.7 | 44.6 | 호 0.73 (2519/3439) |
| `stance_guardian` | `deep_caster` | deep | 0.42 [0.29, 0.58] | 43.7 | 36.5 | 호 0.72 (1890/2637) |
| `stance_guardian` | `opt_archers` | optional | 0.07 [0.03, 0.20] | 47.5 | 35.6 | 호 0.78 (2084/2655) |
| `stance_guardian` | `opt_gnoll` | optional | 0.78 [0.62, 0.88] | 26.4 | 39.0 | 호 0.80 (3132/3923) |

## 표 2 — 태세별 역할 유지 비율

| 빌드 | 아레나 | 돌격형 | 거리형 | 호위형 |
| --- | --- |  --- | --- | --- |
| `stance_mixed` | `early_hob` | 0.51 (124/242) | 0.83 (202/242) | 1.00 (40/40) |
| `stance_mixed` | `early_pair` | 0.51 (132/260) | 0.76 (197/260) | 1.00 (260/260) |
| `stance_mixed` | `deep_mixed` | 0.44 (258/582) | 0.83 (500/605) | 0.89 (535/603) |
| `stance_mixed` | `deep_caster` | 0.47 (189/399) | 0.78 (278/358) | 1.00 (214/214) |
| `stance_mixed` | `opt_archers` | 0.42 (195/462) | 0.77 (366/473) | 0.92 (430/466) |
| `stance_mixed` | `opt_gnoll` | 0.56 (342/614) | 0.84 (526/626) | 0.95 (575/605) |
| `stance_charger` | `early_hob` | 0.57 (160/280) | — | — |
| `stance_charger` | `early_pair` | 0.40 (293/726) | — | — |
| `stance_charger` | `deep_mixed` | 0.44 (438/1002) | — | — |
| `stance_charger` | `deep_caster` | 0.47 (452/959) | — | — |
| `stance_charger` | `opt_archers` | 0.39 (404/1048) | — | — |
| `stance_charger` | `opt_gnoll` | 0.53 (711/1341) | — | — |
| `stance_skirmisher` | `early_hob` | — | 0.92 (440/480) | — |
| `stance_skirmisher` | `early_pair` | — | 0.77 (512/669) | — |
| `stance_skirmisher` | `deep_mixed` | — | 0.68 (1107/1633) | — |
| `stance_skirmisher` | `deep_caster` | — | 0.63 (730/1158) | — |
| `stance_skirmisher` | `opt_archers` | — | 0.61 (951/1557) | — |
| `stance_skirmisher` | `opt_gnoll` | — | 0.81 (1460/1811) | — |
| `stance_guardian` | `early_hob` | — | — | 0.44 (184/416) |
| `stance_guardian` | `early_pair` | — | — | 0.94 (1243/1324) |
| `stance_guardian` | `deep_mixed` | — | — | 0.73 (2519/3439) |
| `stance_guardian` | `deep_caster` | — | — | 0.72 (1890/2637) |
| `stance_guardian` | `opt_archers` | — | — | 0.78 (2084/2655) |
| `stance_guardian` | `opt_gnoll` | — | — | 0.80 (3132/3923) |

## 게이트 G7 판정 (스펙 §4, 사전 고정)

- **혼합 파티**(`stance_mixed`, 돌·거·호): 아레나 6개 **전부**에서 승률 ≥ 0.85.
- **단일 태세 파티**: 각 빌드가 아레나 6개 중 4개 이상에서 승률 ≥ 0.60 (어느 태세도 사장 아님).

| 빌드 | 기준 | 충족 아레나 | 판정 |
| --- | --- | --- | --- |
| `stance_mixed` | 전 아레나 ≥ 0.85 | 5/6 (미달: `deep_caster`) | **미달** |
| `stance_charger` | 4/6 아레나 ≥ 0.60 | 5/6 (`early_hob`, `early_pair`, `deep_mixed`, `opt_archers`, `opt_gnoll`) | 통과 |
| `stance_skirmisher` | 4/6 아레나 ≥ 0.60 | 6/6 (`early_hob`, `early_pair`, `deep_mixed`, `deep_caster`, `opt_archers`, `opt_gnoll`) | 통과 |
| `stance_guardian` | 4/6 아레나 ≥ 0.60 | 3/6 (`early_hob`, `early_pair`, `opt_gnoll`) | **미달** |

**G7 종합: **미달****

솔로 기준(`tests/solo_balance.gd` ≥ 3/8)은 이 도구가 아니라 CI 스위트가 잰다 — 아래 "솔로 기준" 절에 결과를 손으로 적는다.

