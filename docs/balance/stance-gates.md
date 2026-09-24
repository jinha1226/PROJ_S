# 태세 게이트 G7 결과

생성: `tests/stance_gate.gd`(수동 도구) · 커밋 `1c17779-dirty` · 날짜 2026-09-23
근거: [밸런스 방법론](../balance-method.ko.md) §5 · 설계: [태세 설계](../superpowers/specs/2026-09-23-stances-design.md) §4

- 시드 묶음: `S4` 40개 (8000~8039)
- 인원: [3.0] · 봇 정책: `rules`(영웅도 동료와 같은 규칙 목록을 읽고 `Tactics.choose`가 고른 행동을 누른다)
- 규칙: `current` (`solo_actions 1` / `solo_max_members 0`)
- **물자 0**: `supplies [0, 0, 0, 0, 0]` — 태세의 값이 회복품에 가려지지 않는다.
- 아레나 공통 spec: size 20 · room [5, 5, 9, 9] · door [9, 4] · pillars [[8, 8], [10, 10]] · party_entry [9, 5] · sight 5 · supplies [0, 0, 0, 0, 0]
- 행렬: 빌드 4 × 아레나 6 × 시드 40 = 960전투
- 실행 시간: 74.9초
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
| `stance_mixed` | `early_hob` | early | 1.00 [0.91, 1.00] | 0.1 | 9.0 | 돌 0.01 (1/120) 거 0.98 (118/120) 호 1.00 (120/120) |
| `stance_mixed` | `early_pair` | early | 1.00 [0.91, 1.00] | 10.9 | 13.2 | 돌 0.33 (54/163) 거 0.70 (114/163) 호 0.98 (116/118) |
| `stance_mixed` | `deep_mixed` | deep | 0.97 [0.87, 1.00] | 18.1 | 14.1 | 돌 0.39 (127/322) 거 0.70 (227/322) 호 0.96 (187/195) |
| `stance_mixed` | `deep_caster` | deep | 1.00 [0.91, 1.00] | 11.1 | 11.9 | 돌 0.33 (96/290) 거 0.40 (117/290) 호 0.86 (241/279) |
| `stance_mixed` | `opt_archers` | optional | 0.97 [0.87, 1.00] | 21.1 | 13.9 | 돌 0.38 (99/259) 거 0.67 (173/259) 호 0.87 (110/127) |
| `stance_mixed` | `opt_gnoll` | optional | 1.00 [0.91, 1.00] | 10.8 | 13.1 | 돌 0.53 (190/356) 거 0.73 (259/356) 호 0.90 (311/344) |
| `stance_charger` | `early_hob` | early | 1.00 [0.91, 1.00] | 0.7 | 9.1 | 돌 0.13 (46/352) |
| `stance_charger` | `early_pair` | early | 1.00 [0.91, 1.00] | 10.7 | 13.2 | 돌 0.26 (112/434) |
| `stance_charger` | `deep_mixed` | deep | 1.00 [0.91, 1.00] | 16.7 | 12.9 | 돌 0.35 (222/643) |
| `stance_charger` | `deep_caster` | deep | 1.00 [0.91, 1.00] | 15.5 | 14.7 | 돌 0.27 (187/685) |
| `stance_charger` | `opt_archers` | optional | 1.00 [0.91, 1.00] | 18.7 | 12.7 | 돌 0.36 (181/507) |
| `stance_charger` | `opt_gnoll` | optional | 1.00 [0.91, 1.00] | 9.6 | 10.7 | 돌 0.39 (299/763) |
| `stance_skirmisher` | `early_hob` | early | 1.00 [0.91, 1.00] | 0.6 | 9.7 | 거 0.78 (433/558) |
| `stance_skirmisher` | `early_pair` | early | 1.00 [0.91, 1.00] | 5.6 | 12.5 | 거 0.71 (570/806) |
| `stance_skirmisher` | `deep_mixed` | deep | 0.95 [0.83, 0.99] | 25.3 | 21.3 | 거 0.66 (1090/1648) |
| `stance_skirmisher` | `deep_caster` | deep | 0.95 [0.83, 0.99] | 19.5 | 18.2 | 거 0.56 (867/1544) |
| `stance_skirmisher` | `opt_archers` | optional | 0.68 [0.52, 0.80] | 27.7 | 19.6 | 거 0.58 (738/1271) |
| `stance_skirmisher` | `opt_gnoll` | optional | 0.80 [0.65, 0.90] | 15.3 | 26.4 | 거 0.72 (1703/2373) |
| `stance_guardian` | `early_hob` | early | 1.00 [0.91, 1.00] | 3.9 | 9.9 | 호 1.00 (290/290) |
| `stance_guardian` | `early_pair` | early | 1.00 [0.91, 1.00] | 9.9 | 14.0 | 호 0.97 (625/642) |
| `stance_guardian` | `deep_mixed` | deep | 0.90 [0.77, 0.96] | 22.7 | 22.9 | 호 0.86 (1043/1210) |
| `stance_guardian` | `deep_caster` | deep | 0.60 [0.45, 0.74] | 30.8 | 23.0 | 호 0.80 (783/973) |
| `stance_guardian` | `opt_archers` | optional | 0.78 [0.62, 0.88] | 28.6 | 21.1 | 호 0.93 (1140/1230) |
| `stance_guardian` | `opt_gnoll` | optional | 1.00 [0.91, 1.00] | 6.4 | 14.2 | 호 0.96 (1202/1252) |

## 표 2 — 태세별 역할 유지 비율

| 빌드 | 아레나 | 돌격형 | 거리형 | 호위형 |
| --- | --- |  --- | --- | --- |
| `stance_mixed` | `early_hob` | 0.01 (1/120) | 0.98 (118/120) | 1.00 (120/120) |
| `stance_mixed` | `early_pair` | 0.33 (54/163) | 0.70 (114/163) | 0.98 (116/118) |
| `stance_mixed` | `deep_mixed` | 0.39 (127/322) | 0.70 (227/322) | 0.96 (187/195) |
| `stance_mixed` | `deep_caster` | 0.33 (96/290) | 0.40 (117/290) | 0.86 (241/279) |
| `stance_mixed` | `opt_archers` | 0.38 (99/259) | 0.67 (173/259) | 0.87 (110/127) |
| `stance_mixed` | `opt_gnoll` | 0.53 (190/356) | 0.73 (259/356) | 0.90 (311/344) |
| `stance_charger` | `early_hob` | 0.13 (46/352) | — | — |
| `stance_charger` | `early_pair` | 0.26 (112/434) | — | — |
| `stance_charger` | `deep_mixed` | 0.35 (222/643) | — | — |
| `stance_charger` | `deep_caster` | 0.27 (187/685) | — | — |
| `stance_charger` | `opt_archers` | 0.36 (181/507) | — | — |
| `stance_charger` | `opt_gnoll` | 0.39 (299/763) | — | — |
| `stance_skirmisher` | `early_hob` | — | 0.78 (433/558) | — |
| `stance_skirmisher` | `early_pair` | — | 0.71 (570/806) | — |
| `stance_skirmisher` | `deep_mixed` | — | 0.66 (1090/1648) | — |
| `stance_skirmisher` | `deep_caster` | — | 0.56 (867/1544) | — |
| `stance_skirmisher` | `opt_archers` | — | 0.58 (738/1271) | — |
| `stance_skirmisher` | `opt_gnoll` | — | 0.72 (1703/2373) | — |
| `stance_guardian` | `early_hob` | — | — | 1.00 (290/290) |
| `stance_guardian` | `early_pair` | — | — | 0.97 (625/642) |
| `stance_guardian` | `deep_mixed` | — | — | 0.86 (1043/1210) |
| `stance_guardian` | `deep_caster` | — | — | 0.80 (783/973) |
| `stance_guardian` | `opt_archers` | — | — | 0.93 (1140/1230) |
| `stance_guardian` | `opt_gnoll` | — | — | 0.96 (1202/1252) |

## 게이트 G7 판정 (스펙 §4, 사전 고정)

- **혼합 파티**(`stance_mixed`, 돌·거·호): 아레나 6개 **전부**에서 승률 ≥ 0.85.
- **단일 태세 파티**: 각 빌드가 아레나 6개 중 4개 이상에서 승률 ≥ 0.60 (어느 태세도 사장 아님).

| 빌드 | 기준 | 충족 아레나 | 판정 |
| --- | --- | --- | --- |
| `stance_mixed` | 전 아레나 ≥ 0.85 | 6/6 | 통과 |
| `stance_charger` | 4/6 아레나 ≥ 0.60 | 6/6 (`early_hob`, `early_pair`, `deep_mixed`, `deep_caster`, `opt_archers`, `opt_gnoll`) | 통과 |
| `stance_skirmisher` | 4/6 아레나 ≥ 0.60 | 6/6 (`early_hob`, `early_pair`, `deep_mixed`, `deep_caster`, `opt_archers`, `opt_gnoll`) | 통과 |
| `stance_guardian` | 4/6 아레나 ≥ 0.60 | 6/6 (`early_hob`, `early_pair`, `deep_mixed`, `deep_caster`, `opt_archers`, `opt_gnoll`) | 통과 |

**G7 종합: 통과**

솔로 기준(`tests/solo_balance.gd` ≥ 3/8)은 이 도구가 아니라 CI 스위트가 잰다 — 아래 "솔로 기준" 절에 결과를 손으로 적는다.

