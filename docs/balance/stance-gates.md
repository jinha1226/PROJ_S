# 태세 게이트 G7 결과

생성: `tests/stance_gate.gd`(수동 도구) · 커밋 `a396702` · 날짜 2026-09-23
근거: [밸런스 방법론](../balance-method.ko.md) §5 · 설계: [태세 설계](../superpowers/specs/2026-09-23-stances-design.md) §4

- 시드 묶음: `S4` 40개 (8000~8039)
- 인원: [3.0] · 봇 정책: `rules`(영웅도 동료와 같은 규칙 목록을 읽고 `Tactics.choose`가 고른 행동을 누른다)
- 규칙: `current` (`solo_actions 1` / `solo_max_members 0`)
- **물자 0**: `supplies [0, 0, 0, 0, 0, 0]` — 태세의 값이 회복품에 가려지지 않는다.
- 아레나 공통 spec: size 20 · room [5, 5, 9, 9] · door [9, 4] · pillars [[8, 8], [10, 10]] · party_entry [9, 5] · light 90 · supplies [0, 0, 0, 0, 0, 0]
- 행렬: 빌드 4 × 아레나 6 × 시드 40 = 960전투
- 실행 시간: 43.8초
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

**G7 종합: 미달**

솔로 기준(`tests/solo_balance.gd` ≥ 3/8)은 이 도구가 아니라 CI 스위트가 잰다 — 아래 "솔로 기준" 절에 결과를 손으로 적는다.

---

> 여기서부터는 **손으로 적은 절**이다. 위의 본문은 `tests/stance_gate.gd`가 파일 전체를 덮어쓰며 생성하므로, 도구를 다시 돌린 뒤에는 이 아래를 다시 붙여야 한다.

## 솔로 기준 (`tests/solo_balance.gd`)

- 기준: 완주 **≥ 3/8** (태세 설계 §4). 오토배틀 원장이 남긴 임시 기준 `wins >= 1`을 복구했다.
- 측정(커밋 `a396702`, 시드 0~7, CI 스위트와 같은 명령 `godot --headless --path . --script res://tests/solo_balance.gd`): **3/8 완주 · 실패 0건 → 통과.**
  - SUCCESS: 시드 0(행동 150·체력 49), 1(249·49), 7(163·47). DEFEAT: 시드 2~6.
  - 동일 캐릭터 4연속 원정: SUCCESS / DEFEAT / SUCCESS / SUCCESS.
- **봇이 영웅의 태세를 CHARGER로 정한다.** `play()` 시작에서 `s.set_stance(0,"CHARGER")`를 호출한다. 엔진은 바꾸지 않았다 — `make_actor`는 여전히 성격이 정한 기본 태세를 준다. 혼자인 영웅은 호위할 대상도 없고(엔진이 1인 GUARDIAN을 거부한다) 사거리 3 이상 파츠도 없으므로, 실제 솔로 플레이어라면 누구나 돌격형을 고른다. 이 한 줄이 **2/8 → 3/8**의 차이를 만든다(같은 커밋에서 그 줄만 주석 처리하면 2/8, 기준 미달).

## 조정 기록 (설계 §4 순서: 태세 점수 상수 → 노브 매핑, 파츠 수치 불변)

첫 측정에서 G7이 미달이라 두 번 조정을 시도했고, **둘 다 게이트를 뒤집지 못해 되돌렸다**. 파츠 수치는 손대지 않았다. 아래 승률은 모두 같은 시드 묶음 `S4`(8000~8039, 40시드)에서 잰 값이다.

### 조정 1 — 태세 점수 상수: 호위형 "가로막기(치명)" 130 → 95 (`expedition/stances.gd`)

이유: `130`은 같은 블록의 "저지" ATTACK(100)을 이기므로, 위협을 때려 없앨 수 있는 호위형이 치명 위기에서 오히려 옆으로 비켜서며 한 라운드를 버린다고 읽었다(호위형 단일 파티의 평균 라운드 35~45, 인원당 피해 40~48).

결과: **사실상 무변화.** 24칸 중 값이 달라진 칸은 `stance_guardian`/`deep_caster` 하나뿐이고 그마저 인원당 피해 43.7 → 43.6, 승률은 0.42로 동일. `lethal_threat >= hp`가 실제로 성립하는 라운드가 드물어 이 상수가 순위를 가르는 일이 거의 없었다. 되돌렸다.

### 조정 2 — 노브 매핑: 돌격형의 예고 회피 문턱 `posture ≤ −60` → `posture ≤ 0` (`expedition/stances.gd`)

이유: 중립 자세(`Knobs.DEFAULT`, `posture 0`)의 돌격형이 시전 예고 칸에 그대로 서 있다. `deep_caster`(오크 근접 + 고블린 시전)가 혼합·돌격 양쪽에서 0.55로 걸린 유일한 아레나이므로 여기가 원인이라고 읽었다.

결과: 승률(조정 전 → 조정 후)

| 빌드 | early_hob | early_pair | deep_mixed | deep_caster | opt_archers | opt_gnoll |
| --- | --- | --- | --- | --- | --- | --- |
| `stance_mixed` | 1.00 → 1.00 | 1.00 → 1.00 | 0.85 → 0.90 | **0.55 → 0.53** | 0.93 → 0.90 | 0.97 → 0.97 |
| `stance_charger` | 1.00 → 1.00 | 1.00 → 1.00 | 0.88 → 0.90 | **0.55 → 0.88** | 1.00 → 1.00 | 1.00 → 1.00 |
| `stance_skirmisher` | 1.00 → 1.00 | 1.00 → 1.00 | 0.95 → 0.95 | 0.78 → 0.78 | 0.82 → 0.82 | 1.00 → 1.00 |
| `stance_guardian` | 1.00 → 1.00 | 1.00 → 1.00 | 0.23 → 0.23 | 0.42 → 0.40 | 0.07 → 0.07 | 0.78 → 0.78 |

돌격형 단일 파티의 `deep_caster`는 0.55에서 0.88로 크게 올랐지만(가설은 맞았다), **혼합 파티는 0.55 → 0.53으로 그대로다** — 혼합 파티의 `deep_caster` 병목은 돌격형 자리가 아니라는 뜻이다. 호위형도 변화 없음. 두 미달 게이트 중 어느 것도 뒤집히지 않아 되돌렸다. 설계 §2.1이 명시한 `−60`을 유지한다.

## 남은 진단 (다음 실험의 정의)

- **호위형 단일 파티(3/6)**: 세 명이 서로를 호위 대상으로 잡으면 아무도 공통 표적으로 전진하지 않는다. 설계 §2.3 (d)는 "위협이 없으면 `P` 곁에서 대기(40)"이고, 전진 후보 자체가 목록에 없다. 적이 먼저 다가오는 `early_hob`·`early_pair`·`opt_gnoll`에서는 전투가 성립해 1.00·1.00·0.78이지만, 원거리 적이 다가올 이유가 없는 `opt_archers`에서는 0.07(평균 35.6라운드, 인원당 피해 47.5)까지 떨어진다. **이것은 점수 상수가 아니라 후보 목록의 문제이므로 조정 순서로는 닿지 않는다** — 설계 쪽에서 "보호 대상이 없을 때(§2.3 마지막 줄)뿐 아니라 위협이 없을 때도 공통 표적으로 전진하는 후보"를 정의하는 것이 다음 단계다.
- **혼합 파티 `deep_caster`(0.53~0.55)**: 돌격형의 예고 회피로는 오르지 않는다. 같은 아레나에서 거리형 단일이 0.78로 가장 높으므로, 다음 실험은 혼합 파티 안의 어느 자리가 먼저 쓰러지는지(자리별 사망·피해)를 가르는 쪽이다.
