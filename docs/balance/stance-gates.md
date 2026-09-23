# 태세 게이트 G7 결과

생성: `tests/stance_gate.gd`(수동 도구) · 커밋 `7f1bc21-dirty` · 날짜 2026-09-23
근거: [밸런스 방법론](../balance-method.ko.md) §5 · 설계: [태세 설계](../superpowers/specs/2026-09-23-stances-design.md) §4

- 시드 묶음: `S4` 40개 (8000~8039)
- 인원: [3.0] · 봇 정책: `rules`(영웅도 동료와 같은 규칙 목록을 읽고 `Tactics.choose`가 고른 행동을 누른다)
- 규칙: `current` (`solo_actions 1` / `solo_max_members 0`)
- **물자 0**: `supplies [0, 0, 0, 0, 0, 0]` — 태세의 값이 회복품에 가려지지 않는다.
- 아레나 공통 spec: size 20 · room [5, 5, 9, 9] · door [9, 4] · pillars [[8, 8], [10, 10]] · party_entry [9, 5] · light 90 · supplies [0, 0, 0, 0, 0, 0]
- 행렬: 빌드 4 × 아레나 6 × 시드 40 = 960전투
- 실행 시간: 52.1초
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
| `stance_mixed` | `early_hob` | early | 1.00 [0.91, 1.00] | 5.6 | 11.8 | 돌 0.08 (13/169) 거 0.93 (158/169) 호 1.00 (148/148) |
| `stance_mixed` | `early_pair` | early | 1.00 [0.91, 1.00] | 5.9 | 11.5 | 돌 0.46 (137/297) 거 0.69 (205/297) 호 0.92 (264/286) |
| `stance_mixed` | `deep_mixed` | deep | 0.88 [0.74, 0.95] | 24.6 | 17.2 | 돌 0.42 (218/513) 거 0.70 (359/510) 호 0.93 (437/470) |
| `stance_mixed` | `deep_caster` | deep | 0.78 [0.62, 0.88] | 24.9 | 19.6 | 돌 0.39 (170/433) 거 0.66 (285/429) 호 0.89 (270/304) |
| `stance_mixed` | `opt_archers` | optional | 0.93 [0.80, 0.97] | 26.7 | 20.3 | 돌 0.35 (192/546) 거 0.66 (400/604) 호 0.95 (539/568) |
| `stance_mixed` | `opt_gnoll` | optional | 0.95 [0.83, 0.99] | 17.9 | 22.4 | 돌 0.55 (419/762) 거 0.80 (580/723) 호 0.92 (644/702) |
| `stance_charger` | `early_hob` | early | 1.00 [0.91, 1.00] | 6.0 | 12.9 | 돌 0.24 (142/588) |
| `stance_charger` | `early_pair` | early | 1.00 [0.91, 1.00] | 5.6 | 9.4 | 돌 0.34 (219/643) |
| `stance_charger` | `deep_mixed` | deep | 0.93 [0.80, 0.97] | 19.0 | 12.2 | 돌 0.41 (432/1041) |
| `stance_charger` | `deep_caster` | deep | 0.75 [0.60, 0.86] | 25.9 | 17.2 | 돌 0.38 (362/954) |
| `stance_charger` | `opt_archers` | optional | 0.97 [0.87, 1.00] | 17.6 | 12.0 | 돌 0.34 (369/1070) |
| `stance_charger` | `opt_gnoll` | optional | 1.00 [0.91, 1.00] | 14.3 | 13.7 | 돌 0.53 (703/1320) |
| `stance_skirmisher` | `early_hob` | early | 1.00 [0.91, 1.00] | 2.0 | 12.5 | 거 0.77 (662/858) |
| `stance_skirmisher` | `early_pair` | early | 1.00 [0.91, 1.00] | 5.0 | 13.6 | 거 0.74 (760/1030) |
| `stance_skirmisher` | `deep_mixed` | deep | 0.65 [0.50, 0.78] | 33.9 | 26.0 | 거 0.62 (1444/2324) |
| `stance_skirmisher` | `deep_caster` | deep | 0.75 [0.60, 0.86] | 32.0 | 22.5 | 거 0.64 (1128/1774) |
| `stance_skirmisher` | `opt_archers` | optional | 0.65 [0.50, 0.78] | 35.4 | 24.7 | 거 0.49 (1035/2093) |
| `stance_skirmisher` | `opt_gnoll` | optional | 0.68 [0.52, 0.80] | 24.6 | 38.7 | 거 0.69 (2562/3736) |
| `stance_guardian` | `early_hob` | early | 1.00 [0.91, 1.00] | 1.1 | 10.8 | 호 1.00 (636/636) |
| `stance_guardian` | `early_pair` | early | 1.00 [0.91, 1.00] | 4.5 | 11.2 | 호 0.99 (941/951) |
| `stance_guardian` | `deep_mixed` | deep | 0.88 [0.74, 0.95] | 24.4 | 20.3 | 호 0.93 (1777/1901) |
| `stance_guardian` | `deep_caster` | deep | 0.68 [0.52, 0.80] | 28.0 | 25.7 | 호 0.91 (1823/2001) |
| `stance_guardian` | `opt_archers` | optional | 0.65 [0.50, 0.78] | 31.8 | 26.4 | 호 0.88 (2013/2291) |
| `stance_guardian` | `opt_gnoll` | optional | 0.95 [0.83, 0.99] | 15.7 | 25.2 | 호 0.92 (2477/2683) |

## 표 2 — 태세별 역할 유지 비율

| 빌드 | 아레나 | 돌격형 | 거리형 | 호위형 |
| --- | --- |  --- | --- | --- |
| `stance_mixed` | `early_hob` | 0.08 (13/169) | 0.93 (158/169) | 1.00 (148/148) |
| `stance_mixed` | `early_pair` | 0.46 (137/297) | 0.69 (205/297) | 0.92 (264/286) |
| `stance_mixed` | `deep_mixed` | 0.42 (218/513) | 0.70 (359/510) | 0.93 (437/470) |
| `stance_mixed` | `deep_caster` | 0.39 (170/433) | 0.66 (285/429) | 0.89 (270/304) |
| `stance_mixed` | `opt_archers` | 0.35 (192/546) | 0.66 (400/604) | 0.95 (539/568) |
| `stance_mixed` | `opt_gnoll` | 0.55 (419/762) | 0.80 (580/723) | 0.92 (644/702) |
| `stance_charger` | `early_hob` | 0.24 (142/588) | — | — |
| `stance_charger` | `early_pair` | 0.34 (219/643) | — | — |
| `stance_charger` | `deep_mixed` | 0.41 (432/1041) | — | — |
| `stance_charger` | `deep_caster` | 0.38 (362/954) | — | — |
| `stance_charger` | `opt_archers` | 0.34 (369/1070) | — | — |
| `stance_charger` | `opt_gnoll` | 0.53 (703/1320) | — | — |
| `stance_skirmisher` | `early_hob` | — | 0.77 (662/858) | — |
| `stance_skirmisher` | `early_pair` | — | 0.74 (760/1030) | — |
| `stance_skirmisher` | `deep_mixed` | — | 0.62 (1444/2324) | — |
| `stance_skirmisher` | `deep_caster` | — | 0.64 (1128/1774) | — |
| `stance_skirmisher` | `opt_archers` | — | 0.49 (1035/2093) | — |
| `stance_skirmisher` | `opt_gnoll` | — | 0.69 (2562/3736) | — |
| `stance_guardian` | `early_hob` | — | — | 1.00 (636/636) |
| `stance_guardian` | `early_pair` | — | — | 0.99 (941/951) |
| `stance_guardian` | `deep_mixed` | — | — | 0.93 (1777/1901) |
| `stance_guardian` | `deep_caster` | — | — | 0.91 (1823/2001) |
| `stance_guardian` | `opt_archers` | — | — | 0.88 (2013/2291) |
| `stance_guardian` | `opt_gnoll` | — | — | 0.92 (2477/2683) |

## 게이트 G7 판정 (스펙 §4, 사전 고정)

- **혼합 파티**(`stance_mixed`, 돌·거·호): 아레나 6개 **전부**에서 승률 ≥ 0.85.
- **단일 태세 파티**: 각 빌드가 아레나 6개 중 4개 이상에서 승률 ≥ 0.60 (어느 태세도 사장 아님).

| 빌드 | 기준 | 충족 아레나 | 판정 |
| --- | --- | --- | --- |
| `stance_mixed` | 전 아레나 ≥ 0.85 | 5/6 (미달: `deep_caster`) | **미달** |
| `stance_charger` | 4/6 아레나 ≥ 0.60 | 6/6 (`early_hob`, `early_pair`, `deep_mixed`, `deep_caster`, `opt_archers`, `opt_gnoll`) | 통과 |
| `stance_skirmisher` | 4/6 아레나 ≥ 0.60 | 6/6 (`early_hob`, `early_pair`, `deep_mixed`, `deep_caster`, `opt_archers`, `opt_gnoll`) | 통과 |
| `stance_guardian` | 4/6 아레나 ≥ 0.60 | 6/6 (`early_hob`, `early_pair`, `deep_mixed`, `deep_caster`, `opt_archers`, `opt_gnoll`) | 통과 |

**G7 종합: 미달**

## 설명 빈도 (`--explain`)

각 칸은 그 태세가 효용 풀에서 고른 행동의 최상위 고려 사항을 빈도순으로 셋까지 적는다.
모수 `n`은 `battle_stats.members[].explains`(멤버당 마지막 20라운드)를 시드 묶음 전체로 합산한 행동 수다.
불길 회피·머뭇거림·후퇴선처럼 효용 풀이 아닌 단계가 답한 행동은 `explain`이 비어 있어 세지 않는다.

| 빌드 | 아레나 | 돌격형 | 거리형 | 호위형 |
| --- | --- | --- | --- | --- |
| `stance_mixed` | `early_hob` | `(무득점)` 87% · `any_foe_adjacent` 8% · `closes_distance` 5% (n=167) | `rule_ready` 48% · `in_band` 38% · `closes_distance` 6% (n=160) | `any_foe_adjacent` 73% · `rule_ready` 26% · `protectee_near` 1% (n=145) |
| `stance_mixed` | `early_pair` | `any_foe_adjacent` 36% · `closes_distance` 34% · `rule_ready` 15% (n=291) | `in_band` 40% · `closes_distance` 19% · `(무득점)` 17% (n=266) | `protectee_near` 49% · `(무득점)` 16% · `any_foe_adjacent` 12% (n=273) |
| `stance_mixed` | `deep_mixed` | `any_foe_adjacent` 41% · `closes_distance` 33% · `rule_ready` 19% (n=375) | `rule_ready` 29% · `in_band` 27% · `(무득점)` 17% (n=464) | `protectee_near` 31% · `any_foe_adjacent` 21% · `(무득점)` 13% (n=383) |
| `stance_mixed` | `deep_caster` | `any_foe_adjacent` 35% · `closes_distance` 34% · `(무득점)` 17% (n=353) | `rule_ready` 30% · `in_band` 23% · `closes_distance` 16% (n=363) | `protectee_near` 29% · `any_foe_adjacent` 24% · `(무득점)` 17% (n=254) |
| `stance_mixed` | `opt_archers` | `closes_distance` 47% · `any_foe_adjacent` 28% · `rule_ready` 12% (n=389) | `rule_ready` 26% · `in_band` 24% · `closes_distance` 22% (n=564) | `protectee_near` 55% · `closes_distance` 13% · `(무득점)` 11% (n=500) |
| `stance_mixed` | `opt_gnoll` | `any_foe_adjacent` 47% · `rule_ready` 26% · `closes_distance` 22% (n=525) | `in_band` 38% · `rule_ready` 25% · `(무득점)` 15% (n=645) | `protectee_near` 31% · `any_foe_adjacent` 18% · `(무득점)` 18% (n=593) |
| `stance_charger` | `early_hob` | `closes_distance` 32% · `(무득점)` 30% · `any_foe_adjacent` 28% (n=578) | — | — |
| `stance_charger` | `early_pair` | `closes_distance` 52% · `any_foe_adjacent` 24% · `(무득점)` 14% (n=622) | — | — |
| `stance_charger` | `deep_mixed` | `closes_distance` 44% · `any_foe_adjacent` 31% · `(무득점)` 12% (n=960) | — | — |
| `stance_charger` | `deep_caster` | `closes_distance` 41% · `any_foe_adjacent` 29% · `(무득점)` 16% (n=856) | — | — |
| `stance_charger` | `opt_archers` | `closes_distance` 58% · `any_foe_adjacent` 21% · `(무득점)` 11% (n=1034) | — | — |
| `stance_charger` | `opt_gnoll` | `closes_distance` 37% · `any_foe_adjacent` 36% · `(무득점)` 13% (n=1290) | — | — |
| `stance_skirmisher` | `early_hob` | — | `opens_distance` 33% · `rule_ready` 28% · `in_band` 20% (n=790) | — |
| `stance_skirmisher` | `early_pair` | — | `rule_ready` 25% · `in_band` 24% · `opens_distance` 23% (n=966) | — |
| `stance_skirmisher` | `deep_mixed` | — | `rule_ready` 24% · `in_band` 22% · `closes_distance` 19% (n=1664) | — |
| `stance_skirmisher` | `deep_caster` | — | `rule_ready` 24% · `in_band` 22% · `opens_distance` 19% (n=1402) | — |
| `stance_skirmisher` | `opt_archers` | — | `closes_distance` 25% · `rule_ready` 24% · `in_band` 19% (n=1413) | — |
| `stance_skirmisher` | `opt_gnoll` | — | `opens_distance` 30% · `rule_ready` 21% · `in_band` 21% (n=1934) | — |
| `stance_guardian` | `early_hob` | — | — | `protectee_near` 29% · `any_foe_adjacent` 26% · `(무득점)` 18% (n=615) |
| `stance_guardian` | `early_pair` | — | — | `protectee_near` 27% · `(무득점)` 20% · `any_foe_adjacent` 19% (n=836) |
| `stance_guardian` | `deep_mixed` | — | — | `la_ally_hit` 27% · `protectee_near` 25% · `any_foe_adjacent` 17% (n=1600) |
| `stance_guardian` | `deep_caster` | — | — | `protectee_near` 28% · `la_ally_hit` 24% · `any_foe_adjacent` 16% (n=1186) |
| `stance_guardian` | `opt_archers` | — | — | `protectee_near` 38% · `la_ally_hit` 21% · `closes_distance` 13% (n=1502) |
| `stance_guardian` | `opt_gnoll` | — | — | `any_foe_adjacent` 22% · `la_ally_hit` 21% · `(무득점)` 20% (n=1952) |

솔로 기준(`tests/solo_balance.gd` ≥ 3/8)은 이 도구가 아니라 CI 스위트가 잰다 — 아래 "솔로 기준" 절에 결과를 손으로 적는다.

