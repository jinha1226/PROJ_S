# Utility 프로필 튜닝 기록

`data/content/tactics_profiles.json`의 가중치는 [설계 §4](../superpowers/specs/2026-09-24-utility-lookahead-design.md)의
출발값에서 시작한다. 계약 테스트·게이트를 통과시키려고 바꾼 값은 전부 여기에 이유와 함께 적는다.

## Task 1 — 효용 핵심 (태세 후보)

| 변경 | 값 | 이유 |
| --- | --- | --- |
| `ally_delta`를 **모든 태세의 모든 MOVE 태그**에 0으로 추가 (`approach`·`sidestep`·`escape`·`disengage`·`block`·`advance`·`rejoin`) | 0 | 설계 §4의 `personality` 표에는 `ally_delta`(cohesion × 0.10)가 있지만 어떤 프로필에도 들어 있지 않아 `cohesion` 노브가 아무 후보에도 닿지 않았다. 기본 가중치 0이면 노브가 0일 때 순위에 영향이 없고, 노브를 켜면 모든 이동 후보가 함께 반응한다. |
| `GUARDIAN`에 `MOVE:approach`·`MOVE:sidestep` 열 추가 (CHARGER 값 복사) | CHARGER와 동일 | `Stances.candidates`는 호위 대상이 없는 호위형에게 돌격형 프로그램을 돌린다. 열이 없으면 그 후보들이 조용히 0점이 되어 이름 순으로 뽑힌다. `tests/utility.gd`의 (태세, 태그) 커버리지 검사가 이제 이 구멍을 잡는다. |

### `ally_delta`가 예전 `cohesion_shift`와 같지 않다는 점

같은 노브를 쓰지만 모양이 다르다. 숨기지 말고 Task 4에서 이 값을 기준으로 다시 잰다.

- 예전: `signi(delta) × cohesion × 0.10` → cohesion 100에서 `{−10, 0, +10}`, 폭 20.
  **접촉을 끊는 이동에 음의 값**이 붙었다.
- 지금: 유효 가중치 `0 + cohesion × 0.10`에 입력 `(delta+1)/2 ∈ {0, 0.5, 1}` → cohesion 100에서
  `{0, +5, +10}`, 폭 10. 벌점은 없고 보상만 있으며, 0.5의 상수 항은 같은 태그의 모든 후보에
  똑같이 실리므로 순위에는 영향을 주지 않는다.
- 즉 **부호는 같고 폭은 절반이며 이탈 벌점이 없다.** 스케일 0.10은 설계 §5가 못 박은 값이라
  이번 태스크에서는 건드리지 않는다.

### Task 1에서 파츠는 아직 효용 밖이다

파츠·밀치기·엄호는 여전히 `rule_choice`의 선점으로 뽑힌다(설계 §1의 제거 대상이지만 Task 2의 일이다).
그래서 이번에 삭제한 `attack_shift`(피해 파츠 + posture × 0.15)와 엄호의 cohesion 가산(+ cohesion × 0.20)은
**대체물이 없는 상태**다 — Task 2가 `PART` 프로필을 파이프라인에 넣을 때까지 파츠 선택은 성격을 읽지 않는다.

바꾸지 않은 것: 나머지 가중치는 설계 §4 그대로다. `la_*` 입력은 이 태스크에서 중립값(1.0/0.0)이라
`la_self_hit`·`la_ally_hit`는 아직 태그마다 상수를 더할 뿐이고(순위에 영향 없음), `la_enemy_hit`는 `damage`와 같은 값이다.
Task 3의 예측기가 들어오면 다시 잰다.

## 계약 테스트 결과 (Task 1)

| 스위트 | 결과 |
| --- | --- |
| `utility` | 85 checks, 0 failures (신규) |
| `stances` | 98 checks, 0 failures (변경 전과 같은 검사 수) |
| `autobattle` | 109 checks, 0 failures |
| `protect` | 38 checks, 0 failures |
| `skill_rule_conditions` | 962 checks, 0 failures |
| `companion_tactics` | 0 failures |
| `encounter_sim` | 0 failures |
| `parts` | 338 checks, 0 failures |
| `solo_balance` | 0 failures; 3/8 완주 (기준 ≥ 3/8) |

### 재측정 (검토 1차 수정 뒤)

| 스위트 | 결과 |
| --- | --- |
| `utility` | 127 checks, 0 failures (커버리지·commitment·in_band 검사 추가) |
| `stances` | 98 checks, 0 failures |
| `autobattle` | 109 · `protect` 38 · `skill_rule_conditions` 962 · `companion_tactics` · `encounter_sim` · `parts` 338 | 모두 0 failures |
| `solo_balance` | 0 failures; **4/8 완주** (3/8 → 4/8) |

솔로 완주가 하나 늘어난 것은 호위형이 호위 대상 없이 돌격형으로 돌 때 후보가 0점으로 뭉개지지 않게
됐고(`MOVE:approach`·`MOVE:sidestep` 열), `in_band`가 생성기와 같은 거리 척도를 쓰게 된 결과다.
가중치 자체는 설계 §4에서 더 움직이지 않았다.

## Task 2 — 파츠가 같은 풀로 들어오다

### `rule_ready`는 등급형이다 (설계 §2 수정)

`rule_choice`를 지우면 그 안에 있던 두 가지 약속이 같이 사라진다: **규칙 목록의 순위**와
**대상 선호**(`LOWEST_HP`/`NEAREST`/`ALLY`). 둘 다 계약 테스트가 지키는 것이라
(`skill_rule_conditions.gd`의 "follows the wound, not the order") 불리언 하나로는 표현할 수 없다.
그래서 `rule_ready`를 0..1 **등급**으로 바꿨다.

- 액터의 규칙을 목록 순서로 훑어 이 후보에 `Rules.matches`가 처음 참이 되는 규칙을 찾는다.
- 기본값 = `1.0 − 0.1 × min(index, 4)` — 1순위 1.0, 2순위 0.9, 5순위 이하 0.6.
- 그 규칙이 **고를 법한 대상**이면 ×1.0, 아니면 ×0.8. 선호는 같은 파츠의 형제 후보끼리만 비교한다
  (`LOWEST_HP`/`ALLY` → 최저 HP, 그 외 → 최단 거리, 동률은 칸 이름 오름차순).
- 맞는 규칙이 없으면 0.0.

형제 후보는 `Utility.context(s, actor, pool)`이 `ctx.pool`로 실어 나른다. 후보 하나를 재는 비용은
O(풀) — 라운드당 후보 20개면 무시할 수준이다.

**곡선도 같이 바뀐다.** 설계 §4의 `rule_ready` 곡선은 `step`이었는데, `step`은 `x ≥ 1`만 통과시켜
0.9·0.8 같은 등급을 전부 0으로 깎는다. `linear`로 바꿨다.

### 가중치: `PART` 열의 `rule_ready`

| 태세 | 설계 §4 | Task 2 | 왜 |
| --- | --- | --- | --- |
| CHARGER | 120 | **200** | 돌격형의 `ATTACK`은 `any_foe_adjacent` 100 + 피해/처치/`la_*`로 140~210이 나온다. 피해가 0인 파츠(밀치기·엄호)는 120으로는 기본 공격을 이길 수 없어 `parts.gd`·`protect.gd`의 "조건이 참이면 그 파츠" 계약이 깨진다. |
| SKIRMISHER | 140 | **320** | 거리형의 `MOVE:escape`는 `cell_danger` 200 + `la_self_hit` 60이고, posture가 신중할수록(−100) 320까지 오른다. `companion_tactics.gd`의 "a matched skill policy outranks the stance"가 이 값을 요구한다 — 예고 칸에서 도망치는 대신 밀쳐서 예고를 끊는 선택이다. |
| GUARDIAN | 150 | **200** | 돌격형과 같은 이유. 호위형 `PART` 열은 `la_ally_hit` 60이 중립값 1.0으로 상수처럼 붙어 있어 실질은 260이다. |

이 값들은 **Task 3 이전의 임시값**이다. `la_lethal_saved`·`la_ally_hit`가 실제 값을 내기 시작하면
엄호·밀치기가 스스로 점수를 벌게 되므로 `rule_ready`를 설계 §4의 120~150 쪽으로 다시 내리며 재측정한다.

### 잃어버린 것: 밀치기의 `benefit`/불 보너스

옛 `rule_candidates`는 밀치기에 `40 + benefit + bonus`를 매겼다(위협 감소량, 밀려난 칸의 불 차이,
밀 곳이 없을 때의 피해 8). Task 2는 이 수치를 **점수에서 뺐다** — 설계 §5대로 `la_ally_hit`·
`la_lethal_saved`가 대신할 자리이기 때문이다. 그 둘이 중립인 동안 밀치기는 `rule_ready` 하나로만
점수를 받는다. `benefit` 계산 자체는 남아 있다: "다른 아군의 사거리에서 적을 끌어내지 말 것"이라는
안전 검사의 절반이 그 값이다. 밀 곳이 없을 때의 피해 8은 후보의 `damage`로 들어가
`damage`·`kill`·`la_enemy_hit` 열이 읽는다.

### 계약 테스트는 한 줄도 지우지 않았다

`skill_rule_conditions`(962) · `parts`(338) · `protect`(38) · `stances`(98)는 **검사 수정 없이**
그대로 통과한다. `reason`에서 `"n순위 · "` 접두사가 사라졌지만 이를 읽는 검사는 없었다.

`tests/utility.gd`의 신규 `parts()`만 설계 브리프의 원문에서 한 줄을 고쳤다: 아군 치명 위기 장면에서
`f.foes[0].charging = true`를 뺐다. 예고 중인 적은 **밀치기의 기본 규칙(`CHARGING`)도** 참으로 만들고,
밀치기 규칙이 목록 1순위라 등급형 `rule_ready`에서는 밀치기(1.0)가 엄호(0.9)를 이긴다 — 규칙 순위가
지켜야 할 약속이므로 이쪽이 옳다. 예고 없이도 인접한 근접 적 + 예고 피해 9로 아군은 치명 위기이므로
장면의 뜻("아군이 죽을 상황이면 엄호")은 그대로다.

### 계약 테스트 결과 (Task 2)

| 스위트 | 결과 |
| --- | --- |
| `utility` | 134 checks, 0 failures (`parts()` 7 checks 추가) |
| `stances` | 98 checks, 0 failures |
| `autobattle` | 109 checks, 0 failures |
| `protect` | 38 checks, 0 failures |
| `skill_rule_conditions` | 962 checks, 0 failures |
| `parts` | 338 checks, 0 failures |
| `companion_tactics` | 0 failures |
| `encounter_sim` | 0 failures |
| `solo_balance` | 0 failures; **4/8 완주** (기준 ≥ 3/8, 기준선 4/8 유지) |

## Task 3 — 룩어헤드 예측기와 부호 있는 안전 항

### 안전 고려 사항은 절대값이 아니라 **제자리 대비 차이**다 (설계 §2 수정)

Task 2까지 `cell_danger`는 "도착 칸이 얼마나 안전한가"(1 − 위험/20)였고 `la_self_hit`·`la_ally_hit`는
룩어헤드가 꺼져 있어 상수 1.0이었다. 셋 다 **절대값**이라, 아무 일도 하지 않는 안전한 칸에도
가중치 전액을 지급했다. 그 결과 태세 후보(`MOVE:escape` 200, `MOVE:approach` 20~40 …)는
가만히 있기만 해도 수십~200점을 벌었지만 `PART` 열에는 그런 상수 항이 거의 없어, Task 2는
계약을 지키려고 `rule_ready`를 200~320까지 밀어 올려야 했다. 즉 **파츠가 태세를 이기려면
파츠가 아니라 규칙 가중치가 커져야 하는** 구조였다.

Task 3은 셋을 **부호 있는 차이**로 바꾸고 새 곡선 `signed`(−1..1로만 클램프, 0 바닥 없음)를 넣었다.

| id | 전 | 후 |
| --- | --- | --- |
| `cell_danger` | `1 − min(1, danger(dest)/20)`, 곡선 `linear` | `(danger(내 칸) − danger(dest)) / max(1, 내 HP)`, 곡선 `signed` (MOVE가 아니면 0) |
| `la_self_hit` | 상수 `1.0`, 곡선 `linear` | `(predict(제자리).self − predict(행동).self) / max(1, 내 HP)`, 곡선 `signed` |
| `la_ally_hit` | 상수 `1.0`, 곡선 `linear` | `(제자리.allies − 행동.allies) / max(1, 나를 뺀 생존 아군 HP 합)`, 곡선 `signed` |
| `la_enemy_hit` | `damage/40` | `min(1, predict(행동).enemies/40)` (범위·밀치기 낙하 피해 포함) |
| `la_lethal_saved` | 상수 `0.0` | `min(1, lethal_saved/3)` |

중립은 0이고, 더 위험한 칸으로 가는 것은 **실제 벌점**이다. 룩어헤드를 끄면
`la_self_hit = la_ally_hit = 0.0`(1.0이 아니다), `la_lethal_saved = 0`, `la_enemy_hit = damage/40`.
제자리 예측(`ctx.stand`)과 `danger(내 칸)`은 액터당 한 번, 행동 예측은 후보당 한 번 계산한다.

### 가중치: 전 → 후

| 열 | 항목 | Task 2 | Task 3 | 왜 |
| --- | --- | --- | --- | --- |
| `considerations.cell_danger` | 곡선 | `linear` | **`signed`** | 위 |
| `considerations.la_self_hit` | 곡선 | `linear` | **`signed`** | 위 |
| `considerations.la_ally_hit` | 곡선 | `linear` | **`signed`** | 위 |
| CHARGER/`PART` | `rule_ready` | 200 | **150** | 설계 §4는 120. 부호 있는 안전 항이 들어오자 태세 후보의 상수 보너스가 사라져 120까지 내릴 수 있었지만, 120은 `skill_rule_conditions`의 "PUSH follows the wound" / "PUSH fires on a wounded foe"를 깬다. 그 장면의 점수 차: 12 HP 적을 마무리하는 `ATTACK` **146점**(any_foe_adjacent 100 + damage 20 + kill 20 + la_enemy_hit 6) 대 `PUSH` **120점** → **−26**. 필요한 최솟값은 147이고 145는 실패, 150은 통과한다. **147이 아니라 150으로 잡은 이유**: 147은 한 장면의 점수에 딱 맞춘 값이라 여유가 0이고, 다른 파츠·성장 수치가 조금만 움직여도 다시 깨진다. 10 단위의 둥근 수에 3점의 여유를 남긴 150이 프로필 표에서도 읽기 쉽다. |
| SKIRMISHER/`PART` | `rule_ready` | 320 | **140** | 설계 §4 값으로 복귀. `MOVE:escape`의 `cell_danger` 200이 더 이상 상수 보너스가 아니라 320이 필요 없다. |
| GUARDIAN/`PART` | `rule_ready` | 200 | **150** | 설계 §4 값으로 복귀. 같은 이유. |
| CHARGER/`PART` | `la_self_hit` | 없음 | **40** | 파츠도 자기 안전을 읽어야 한다(밀치기로 예고를 끊는 선택이 그 자체로 점수를 받는다). |
| SKIRMISHER/`PART` | `la_self_hit` | 없음 | **60** | 거리형은 같은 항을 이동 후보에서 40~60으로 쓴다. |
| GUARDIAN/`PART` | `la_self_hit` | 없음 | **40** | 돌격형과 같음. |
| 모든 열 | `same_as_last` | 10 | **10 (그대로)** | `oscillation()`이 10에서 통과했다 — 15까지 올릴 필요가 없었다. |
| 모든 열 | `contact_penalty` | −1000 | **−1000 (그대로)** | 다만 발동 조건이 좁아졌다(아래). |

그 밖의 가중치는 한 칸도 움직이지 않았다.

### `contact_penalty`는 진짜 원거리 파츠에만 (판정 R3-a)

전: `range ≥ 3`. 후: `axis == "RANGED"` **그리고** `range ≥ 3`. 돌진(`LUNGE`)·기습(`GOBLIN_SHIV`)은
사거리 3이지만 `axis`가 `MELEE`다 — 붙기 위해 3칸을 뻗는 파츠라 접촉 중에 집어넣을 이유가 없다.
벌점 값은 세 `PART` 열 모두 −1000 그대로.

### `rule_ready` 등급의 기본값 (판정 R3-b)

`1.0 − 0.1·min(index,4)` → **`1.0 − 0.02·min(index,4)`**. 규칙 순위는 스케일이 아니라 동점 처리라는
판정이다. 대상 선호 계수 ×0.8은 그대로. 순위를 셀 때 **장착하지 않은 파츠의 규칙은 건너뛴다**(옛
`rule_choice`와 같다). 죽은 검사였던 `rule.get("enabled",true)`는 지웠다 — `Rules.matches`가 이미 본다.

`Utility.preference`의 빈 칸 처리도 고쳤다: `s.at(cell)`이 비어 있으면 HP 0이 아니라 **가장 덜 선호**(9999)다.

### 예측기 설계 메모 (`expedition/lookahead.gd`)

- 세션을 복제하지 않는다. 행동의 즉시 효과를 `pos_override`/`hp_override`/`protected`/`intents`
  네 개의 스크래치 사전에 담고, 그 위에서 `Rules.lethal_threat`을 다시 계산한다(`threat_after`).
- `threat_after`는 `lethal_threat`의 조건을 그대로 복사했다: 예고 칸 피해(+floor면 어둠 보너스),
  경계 중이거나 시야 9 안에 있는 적만, `cast_recovery > 0`인 적은 제외, 근접 접촉이면 역할 피해
  (비근접 역할은 4), 사선 안이면 원거리 역할 피해, 그리고 엄호 대상은 절반(최소 1).
- 순수·결정론적이다. 세션은 읽기만 한다.
- 비용: 후보당 O(파티 × 적). 제자리 예측은 액터당 한 번만.

### 테스트 수정 (검사 단위, 옛 → 새)

| 파일·검사 | 옛 | 새 | 왜 |
| --- | --- | --- | --- |
| `utility.gd` / "approach step…" | `inp.cell_danger == 1.0` | `inp.cell_danger == 0.0` | 안전한 칸 → 안전한 칸은 차이가 없다. |
| `utility.gd` / "telegraphed cell" | `inp.cell_danger == 0.5` | `== -10.0/hero.hp` (+ 반대 방향 한 칸을 `+10.0/hero.hp`로 새로 검사) | 10 피해 예고 칸으로 들어가는 것은 음의 차이, 빠져나오는 것은 같은 크기의 양의 차이. |
| `utility.gd` / "disabled: neutral" | `la_self_hit == 1.0` | `== 0.0` | 꺼진 룩어헤드는 중립 0이지 공짜 보너스가 아니다. |
| `utility.gd` / 노브 곱 fixture | 적 HP 30 | 적 HP **5**(일격 처치) + `la_self_hit > 0` 사전 확인 | 차이형이 되면서 살아남는 적을 때리는 `la_self_hit`가 0이 되어 posture 스케일 항이 하나만 남았다. 처치 장면이라야 `damage`와 `la_self_hit` 둘 다 움직인다. 기대값은 여전히 프로필에서 계산한다(`knob_shift`). 이 장면 뒤 적 HP는 30으로 되돌린다. |
| `utility.gd` / curves | — | `signed`가 부호를 유지하고 −1..1로 클램프하는지 (신규) | 새 곡선. |
| `utility.gd` / `lookahead()`·`oscillation()` | — | 브리프 원문 그대로 신규 | Task 3. |
| `companion_tactics.gd` / "first matching skill wins" | `choose(...).kind == "PUSH"` | `grade(PUSH) > grade(GUARD)` + `choose(...).kind == "GUARD"` | 설계 §7.1이 예고한 의도 변경 (a): 파츠는 선점하지 않고 경쟁한다. 이 장면에서 엄호는 7 피해를 3으로 줄여 5 HP 리더를 **실제로 살리고**(`la_lethal_saved` +67), 밀치기는 보스를 여전히 리더에게 닿는 칸으로 밀 뿐이다. 순위 차는 등급 −2%(≈4점)뿐이라 살린 목숨이 이긴다. 규칙 순위 자체는 `rule_ready` 등급 비교로 계속 검사한다. |
| `companion_tactics.gd` / "skill reordering still applies" | `choose(...).kind == "GUARD"` | `grade(GUARD) > grade(PUSH)` | 같은 이유. `reorder_rule`이 등급 순서를 뒤집는다는 약속은 그대로 지킨다. |

`stances.gd`(98) · `protect.gd`(38) · `parts.gd`(338) · `skill_rule_conditions.gd`(962) ·
`autobattle.gd`(109)는 **한 줄도 고치지 않았다**.

### 진동 없음 (commitment)

브리프의 `oscillation()`: 정지한 적에게서 5칸 떨어진 투석 거리형이 4라운드를 돌아
A-B-A-B가 되지 않는지. `same_as_last` **10**(설계 §4 값)에서 바로 통과했으므로 15로 올리지 않았다.

### 계약 테스트 결과 (Task 3)

| 스위트 | 결과 |
| --- | --- |
| `utility` | 147 checks, 0 failures (`lookahead()`·`oscillation()`·`signed` 곡선 추가) |
| `stances` | 98 checks, 0 failures |
| `autobattle` | 109 checks, 0 failures |
| `protect` | 38 checks, 0 failures |
| `skill_rule_conditions` | 962 checks, 0 failures |
| `parts` | 338 checks, 0 failures |
| `companion_tactics` | 0 failures |
| `encounter_sim` | 0 failures |
| `solo_balance` | 0 failures; **4/8 완주** (기준 ≥ 3/8, 기준선 4/8 유지) |
| `ranged_probe` 2인 | `deep_mixed` 0.93 · `opt_archers` 1.00 · `two_archers` 1.00 (이전 0.73 / 0.90 / 1.00) |
| 임포트 | 오류 0 |

### 검토 1차 수정 (Fix round 1)

가중치는 한 칸도 움직이지 않았다. 바뀐 것은 예측기의 정확도·비용과 성격 노브의 바닥이다.

| 항목 | 전 | 후 | 왜 |
| --- | --- | --- | --- |
| `Lookahead.predict` 죽은 적의 예고 | `PUSH`만 대상의 intent를 지웠다 | match 블록 뒤에서 `hp_override`로 HP ≤ 0이 된 **모든** 적의 intent를 지운다 | 예고 중인 시전자를 **죽여도** 예고가 남아 있어, 밀치면 `lethal_saved` 1인데 죽이면 0이었다. `la_lethal_saved`는 200~300짜리 항이라 파츠 선택이 통째로 뒤집혔다. |
| 성격 노브와 `signed` 가중치 | `weight += knob × scale`, 바닥 없음 | 곡선이 `signed`인 고려 사항은 `weight = max(0, weight)` | posture ≥ 67이면 가중치 20짜리 `cell_danger`·`la_self_hit`가 음수가 되어, 대담한 대원이 예고 칸으로 **걸어 들어가면 보상**을 받았다. 대담함은 무관심이지 자해가 아니다. `tests/utility.gd`의 `knob_shift`도 같은 클램프로 기대값을 낸다(원시 scale이 아니라 클램프된 차이). |
| `before_lethal` 계산 | 후보마다 파티원 수만큼 `Rules.lethal_threat` | `Lookahead.baseline(s)`를 `Utility.context`에서 한 번 → `ctx.before_lethal`로 재사용 | 후보와 무관한 값이었다. |
| 예측 호출 | 모든 후보 | 프로필 열이 `la_*` 넷 중 하나도 쓰지 않으면 건너뛴다(값은 룩어헤드 꺼짐과 동일) | `WAIT`·`MOVE:sidestep`처럼 룩어헤드를 읽지 않는 열은 예측 비용을 내지 않는다. |
| `s.intents.duplicate(true)` | 깊은 복사 | `duplicate()` | intent를 고치지 않고 목록만 거른다. |

새 검사: `lookahead()`에 "killing the caster drops its telegraph too"(HP 9 대원, 예고 10, 5 HP 시전자를
18로 처치 → `self == 0`, `lethal_saved == 1`), 그리고 `signed_weights_never_reward()`(posture 100
돌격형이 예고 칸으로 가는 후보에서 `cell_danger`·`la_self_hit` 기여가 ≤ 0이고, 예고 칸 점수가 빈 칸
점수를 넘지 못한다).

| 스위트 | 결과 (Fix round 1) |
| --- | --- |
| `utility` | **151** checks, 0 failures |
| `stances` 98 · `autobattle` 109 · `protect` 38 · `skill_rule_conditions` 962 · `parts` 338 · `companion_tactics` · `encounter_sim` | 모두 0 failures |
| `solo_balance` | 0 failures; 4/8 완주 |
| `ranged_probe` 2인 | `deep_mixed` **0.97** · `opt_archers` 1.00 · `two_archers` 1.00 |
| 임포트 | 오류 0 |


## Task 4 — 설명 계측 · 게이트 · 튜닝 기록

### 계측 (설계 §6)

`auto_step`이 누른 모든 행동을 `battle_stats.members[id].explains`에 적는다:
`{"round","kind","cell","explain"}`, 최대 `Session.EXPLAIN_KEEP = 20`이며 넘치면 **앞에서** 버린다.
`explain`은 `choice.get("explain",[])`로 읽는다 — 불길 회피·머뭇거림·후퇴선처럼 효용 풀이 아닌
단계가 답한 라운드는 설명이 없고, 그 사실 자체가 기록으로 남는다. `reason` 문자열은 건드리지 않았다
(설계 §0.4): 이것은 통계이지 UI가 아니며, `expedition/main.gd`·`battle_hud.gd`는 한 줄도 바뀌지 않았다.

`expedition/sim/encounter_runner.gd`가 전투 끝에 이 창을 태세별로 집계해
`run_one().explain_top[stance][consideration_id]`로 싣고, `run_many`가 시드 묶음 전체로 합산한다.
`tests/stance_gate.gd`·`tests/skill_value.gd`는 `-- --explain`으로 그 표를 찍고 보고서에 덧붙인다.

`(무득점)`은 **기여가 양수인 항이 하나도 없는 선택**이다(최상위 항의 `contrib`가 0 이하).
후보가 이겨서가 아니라 남은 것 중 덜 나빠서 뽑힌 라운드이고, 정직하게 그 자체를 한 칸으로 센다.

### 게이트 (전/후)

기준선은 두 가지다: **태세 작업 시점의 기록**(`docs/balance/stance-gates.md`의 이전 판)과
**이 브랜치에서 가중치를 건드리기 전의 재측정**(Task 3 종료 상태, 커밋 `7f1bc21`).

| 아레나 | 혼합: 태세 작업 시점 | 혼합: Task 3 종료 | 혼합: **Task 4 최종** |
| --- | --- | --- | --- |
| `early_hob` | 1.00 | 1.00 | 1.00 |
| `early_pair` | 1.00 | 1.00 | 1.00 |
| `deep_mixed` | 0.72 | 0.88 | **0.88** |
| `deep_caster` | 0.55 | 0.78 | **0.78** (기준 0.85 **미달**) |
| `opt_archers` | 0.93 | 0.88 | **0.93** |
| `opt_gnoll` | 0.95 | 0.97 | **0.95** |

| 단일 태세 빌드 | 태세 작업 시점 | **Task 4 최종** (아레나 6개, 기준 ≥ 0.60이 4개 이상) |
| --- | --- | --- |
| `stance_charger` | 통과 | **6/6** — 1.00 · 1.00 · 0.93 · 0.75 · 0.97 · 1.00 |
| `stance_skirmisher` | 통과 | **6/6** — 1.00 · 1.00 · 0.65 · 0.75 · 0.65 · 0.68 |
| `stance_guardian` | **3/6 미달** | **6/6** — 1.00 · 1.00 · 0.88 · 0.68 · 0.65 · 0.95 |

| 그 밖의 게이트 | 기준 | 전 | 후 |
| --- | --- | --- | --- |
| `solo_balance` 완주 | ≥ 3/8 | 4/8 (Task 3) | **5/8** |
| `ranged_probe` 2인 `deep_mixed` | ≥ 0.73 | 0.97 | **1.00** |
| `ranged_probe` 2인 `opt_archers` | ≥ 0.90 | 1.00 | **1.00** |
| `ranged_probe` 2인 `two_archers` | ≥ 1.00 | 1.00 | **1.00** |

**남은 공백: 혼합 파티의 `deep_caster` 0.78 < 0.85.** 태세 작업 시점의 세 공백 중 둘
(혼합 `deep_mixed` 0.72, 호위형 단일 3/6)은 효용 선택기가 닫았고, 이 하나가 남았다.

### 가중치 조정 (2회, 프로필 가중치만)

**1차 — 대담함은 무관심이지 자해가 아니다 (유지).**

| 열 | 항목 | 전 | 후 |
| --- | --- | --- | --- |
| CHARGER/`ATTACK` | `la_self_hit` | 20 | **60** |
| CHARGER/`MOVE:approach` | `cell_danger` | 20 | **120** |
| CHARGER/`MOVE:approach` | `la_self_hit` | 20 | **80** |
| GUARDIAN/`MOVE:approach` | `cell_danger` | 20 | **120** |
| GUARDIAN/`MOVE:approach` | `la_self_hit` | 20 | **80** |

이유: `cell_danger`·`la_self_hit`는 Task 3에서 **부호 있는 차이**가 됐고 입력은 HP로 정규화된다.
10 피해 예고 칸에 55 HP 대원이 들어가는 입력은 −0.18이라 가중치 20에서는 기여가 **−3.6**이다.
같은 후보의 `closes_distance`는 80 × 0.5 = **+40**이므로, 돌격형은 예고 칸을 사실상 공짜로 밟고 있었다.
120/80이면 같은 장면이 −22/−15가 되어 한 칸 옆으로 돌아가는 후보와 겨룰 수 있다. 호위형은 호위 대상이
없을 때 돌격형 프로그램을 돌리므로 같은 열을 같은 값으로 맞췄다.

결과: 혼합 `opt_archers` 0.88 → **0.93**, `opt_gnoll` 0.97 → 0.95, 돌격형 단일 `deep_caster` 0.78 → 0.75,
혼합 `deep_caster`는 **0.78 그대로**. 계약 스위트는 전부 검사 수 변화 없이 통과(아래 표).
게이트를 뒤집지는 못했지만 근거가 옳고 한 아레나가 올라 **유지**한다.

**2차 — `PART`의 `rule_ready` 200 (되돌림).**

| 열 | 항목 | 전 | 시도 | 판정 |
| --- | --- | --- | --- | --- |
| CHARGER/`PART` | `rule_ready` | 150 | 200 | **되돌림** |
| GUARDIAN/`PART` | `rule_ready` | 150 | 200 | **되돌림** |

가설: `deep_caster`(오크 + 고블린 시전자)에서 예고 중인 시전자를 밀치기(`PUSH`→`CHARGING`)로 끊는 일이
더 자주 일어나면 승률이 오른다. 결과는 **혼합 `deep_caster` 0.775로 변화 없음**(등급 차 자체가 규칙 순위
2%뿐이라 `rule_ready`의 절대값은 형제 후보 순위를 거의 바꾸지 않는다), 대신 혼합 `opt_archers`가
0.93 → 0.88로 떨어졌다. 순이익이 음수라 되돌렸다. 격리 측정: 같은 30시드 `deep_caster` 혼합에서
`rule_ready` 150 → 승률 0.775 / 평균 19.55라운드, 200 → 0.775 / 19.50라운드.

**여기서 멈춘다.** 브리프의 조정 한도 2회를 썼고, 검사를 고쳐 통과시키지 않는다.

### `deep_caster`가 남은 이유 (다음 작업의 입력)

- 이 아레나는 **모든 빌드에서** 낮다: 돌격형 0.75 · 거리형 0.75 · 호위형 0.68 · 혼합 0.78.
  한 태세의 약점이 아니라 아레나(오크 근접 + 고블린 시전자)의 난이도다.
- `la_lethal_saved`는 **이진값**이다. `GUARD`는 피해를 절반으로 줄일 뿐이라 치명 위기를 벗기지 못하면
  0점이고, 시전자의 큰 예고 앞에서는 "덜 맞았다"가 점수를 받지 못한다. 아군 쪽 **피해 감소량**을
  읽는 고려 사항(`la_ally_hit`의 엄호 버전)이 있으면 이 칸이 오를 여지가 크다.
  이번 태스크는 고려 사항을 새로 만들지 않으므로 기록만 남긴다.
- 부호 있는 안전 항의 가중치는 0에서 잘린다. 그래서 posture는 `cell_danger`·`la_self_hit`를 **끄는**
  방향으로만 움직이고, 대담함은 `damage`·`any_foe_adjacent`의 크기로만 표현된다. 시전자를 향해
  달려드는 성향을 가중치로 만들 수단이 지금은 좁다.

### `--explain` 표 — 태세가 서로 다른 이유로 움직이는가

출처: `godot --headless --path . --script res://tests/stance_gate.gd -- --explain`
(30시드 × 6아레나 × 4빌드, 전문은 [stance-gates.md](stance-gates.md)의 같은 표).
각 칸은 그 태세가 효용 풀에서 고른 행동의 **최상위 고려 사항**을 빈도순으로 셋까지, `n`은 행동 수다.

혼합 파티(한 전투 안에서 세 태세가 동시에):

| 빌드 | 아레나 | 돌격형 | 거리형 | 호위형 |
| --- | --- | --- | --- | --- |
| `stance_mixed` | `early_hob` | `(무득점)` 87% · `any_foe_adjacent` 8% · `closes_distance` 5% (n=167) | `rule_ready` 48% · `in_band` 38% · `closes_distance` 6% (n=160) | `any_foe_adjacent` 73% · `rule_ready` 26% · `protectee_near` 1% (n=145) |
| `stance_mixed` | `early_pair` | `any_foe_adjacent` 36% · `closes_distance` 34% · `rule_ready` 15% (n=291) | `in_band` 40% · `closes_distance` 19% · `(무득점)` 17% (n=266) | `protectee_near` 49% · `(무득점)` 16% · `any_foe_adjacent` 12% (n=273) |
| `stance_mixed` | `deep_mixed` | `any_foe_adjacent` 41% · `closes_distance` 33% · `rule_ready` 19% (n=375) | `rule_ready` 29% · `in_band` 27% · `(무득점)` 17% (n=464) | `protectee_near` 31% · `any_foe_adjacent` 21% · `(무득점)` 13% (n=383) |
| `stance_mixed` | `deep_caster` | `any_foe_adjacent` 35% · `closes_distance` 34% · `(무득점)` 17% (n=353) | `rule_ready` 30% · `in_band` 23% · `closes_distance` 16% (n=363) | `protectee_near` 29% · `any_foe_adjacent` 24% · `(무득점)` 17% (n=254) |
| `stance_mixed` | `opt_archers` | `closes_distance` 47% · `any_foe_adjacent` 28% · `rule_ready` 12% (n=389) | `rule_ready` 26% · `in_band` 24% · `closes_distance` 22% (n=564) | `protectee_near` 55% · `closes_distance` 13% · `(무득점)` 11% (n=500) |
| `stance_mixed` | `opt_gnoll` | `any_foe_adjacent` 47% · `rule_ready` 26% · `closes_distance` 22% (n=525) | `in_band` 38% · `rule_ready` 25% · `(무득점)` 15% (n=645) | `protectee_near` 31% · `any_foe_adjacent` 18% · `(무득점)` 18% (n=593) |

단일 태세 파티:

| 빌드 | 아레나 | 돌격형 | 거리형 | 호위형 |
| --- | --- | --- | --- | --- |
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

읽기:

- **돌격형** = `closes_distance`(32~58%) + `any_foe_adjacent`(21~36%). 거리를 좁히고 붙어서 때린다.
  설계가 예상한 `damage`·`target_adjacent`가 상위에 없는 이유는, 둘 다 붙은 뒤에야 켜지는 항이고
  붙는 과정이 라운드 수를 지배하기 때문이다. `(무득점)` 11~30%는 이미 붙어 있어 더 좁힐 곳도,
  안전해질 곳도 없는 라운드다(`early_hob` 혼합의 87%는 적이 하나뿐이라 돌격형이 할 일이 없는 칸이다).
- **거리형** = `in_band`(19~40%) + `rule_ready`(21~48%) + `opens_distance`(19~33%). 띠 안에 서고,
  띠 안이면 투석 규칙이 답한다. 설계가 적은 `in_band`/`cell_danger` 중 `cell_danger`가 상위에 없는 것은
  Task 3에서 그것이 **차이**가 되어 안전한 칸에서는 0이기 때문이다 — 예고가 깔린 라운드에만 뜬다.
- **호위형** = `protectee_near`(25~55%) + `la_ally_hit`(20~27%) + `any_foe_adjacent`. 곁을 지키고,
  아군이 덜 맞는 쪽으로 선다. `deep_mixed`·`opt_archers`처럼 원거리 적이 있는 아레나에서
  `la_ally_hit`가 2위로 올라오는 것이 룩어헤드가 실제로 일하고 있다는 증거다.

세 태세의 상위 항이 서로 겹치지 않는다 — **태세는 정량적으로 구분된다.**

### CI 스위트 하나가 빨갛던 것을 고쳤다 (`skill_archetypes`)

Task 4의 전체 스위트 실행에서 `skill_archetypes`가 **1 failure**로 나왔다:
`rule engine picks THROWING_KNIFE when its rule is first`. 이 브랜치의 가중치 조정 때문이 아니다 —
가중치를 되돌려도, Task 3 종료 커밋 `7f1bc21`에서도 같이 실패하고 효용 작업 직전 커밋 `31a6133`에서는
통과한다. 즉 **Task 1~3이 남긴 회귀**이고, 원인은 Task 3이 넣은 `contact_penalty`다:
장면이 적을 **인접 칸**에 두고 사거리 4의 `THROWING_KNIFE`를 기대하는데, 접촉 중인 사거리 3+ 원거리
파츠는 −1000으로 집어넣지 않는 것이 이제 설계다(효용 설계 §2, Task 3 판정 R3-a).

고친 것은 **장면**이다: 폭탄과 같은 이유로(자기가 휘말린다) 칼도 자기 거리에서 잰다 —
`f.foe.pos`를 인접(1)에서 3으로. 검사는 한 줄도 지우지 않았고 검사 수도 그대로다. 이 검사가 묻는 것은
"규칙 목록이 결정하는가"이지 "접촉 중에도 칼을 던지는가"가 아니다.

### 계약·게이트 스위트 결과 (Task 4)

| 스위트 | 결과 |
| --- | --- |
| `utility` | **154** checks, 0 failures (`explanations()` 3 checks 추가) |
| `stances` | 113 checks, 0 failures |
| `autobattle` | 105 checks, 0 failures |
| `protect` | 38 · `parts` 338 · `skill_rule_conditions` 962 | 모두 0 failures |
| `companion_tactics` · `encounter_sim` | 0 failures |
| `skill_archetypes` | 0 failures (장면 수정 뒤; 그 전 1 failure, 위 절) |
| CI 스위트 36개 전부(`deploy-pages.yml`, 끝에 ` utility` 추가) | `SCRIPT ERROR:`/`ERROR:` 0 |
| 임포트(`--editor --import --quit`) | 오류 0 |
| `solo_balance` | 0 failures; **5/8** 완주 |
| `stance_gate` | 혼합 5/6 (미달: `deep_caster`) · 단일 3빌드 전부 6/6 |
| `ranged_probe` 2인 | `deep_mixed` 1.00 · `opt_archers` 1.00 · `two_archers` 1.00 |

## NPC 활동 모드 (던전 NPC Task 4)

깨어 있는 NPC가 **아무도 자기를 공격하지 않을 때** 무엇을 하는가를 고르는 네 모드짜리 효용 표다.
파츠·태세와 같은 선형 가중합을 쓰되 표는 `data/content/tactics_profiles.json`의 `npc_modes`에 있고,
선택기는 `expedition/npc_modes.gd`(`table/inputs/score_of/choose`)다. 교전 중이면 표를 묻지 않는다 —
`FIGHT`는 상황이 정하는 것이지 취향이 아니다.

| 고려 항목 | 의미 | APPROACH | HOLD | REST | EXPLORE |
| --- | --- | ---: | ---: | ---: | ---: |
| `base` | 기본값 | 40 | 60 | 0 | 30 |
| `X` | 외향 /1000 | +120 | −60 | | |
| `A` | 온화 /1000 | +60 | | | |
| `C` | 신중 /1000 | | +80 | | |
| `O` | 개방 /1000 | | | | +120 |
| `wounded` | HP < 40% | +80 | | +200 | |
| `hp_ratio` | HP/최대 | | | | +60 |
| `party_room` | 파티 인원/3 | −90 | | | |
| `declined` | 거절 기억 | −150 | +120 | | |
| `stress` | 스트레스/200 | | | +80 | |
| `party_seen` | 파티가 시야에 | | | | −120 |

**유지와 전환.** 고른 모드는 `COMMIT_ROUNDS = 10` 라운드 동안 유지된다(`npc.mode_until`).
그 안에 바꾸려면 새 모드가 현재 모드를 `SWITCH_MARGIN = 80`점 넘겨 앞서야 한다 — 문턱이 없으면
성격이 비슷한 두 모드 사이에서 매 라운드 흔들린다. 유지 기간이 끝나면 점수만으로 다시 고른다.
2인 조는 짝이 고른 모드를 따라간다(`partner_of`), 활동 문구는 `NpcAI.LABELS`
(`교전 중`·`다가오는 중`·`거리를 두고 지켜보는 중`·`부상으로 대기 중`·`주변을 탐색 중`)이고
보드의 이름표 아래에 그대로 나온다.

**검사 시드.** `tests/npc_behaviour.gd`는 `Session.new(61,…)` + `Fixture.arena(s,12)` 한 장을 쓰고
(`npc_sense`는 51, `npc_roster`는 41~43·100+n, `recruit`은 71~82와 200+n), 각 모드는 해당
고려 항목을 끝값으로 밀어 그 모드가 뽑히는지, 문턱이 흔들림을 막는지를 본다.

| 스위트 | 결과 |
| --- | --- |
| `npc_roster` · `npc_sense` · `npc_behaviour` · `recruit` | 0 failures (CI 목록에 추가) |

## 눈으로 보는 체크리스트 (사용자 확인 항목)

수치가 아니라 눈으로 확인하는 항목이다. **전투 시험 모드**로 본다:
마을 → `전투 시험` → 아레나 고르기(`early_hob`·`deep_mixed`·`deep_caster`·… 또는 `직접 구성`) → 멤버마다 태세 버튼(돌격형·거리형·호위형)과 파츠 고르기 → 시작.
아레나 3개 × 태세 3개를 돌리며 아래 다섯 질문에 답한다. 한 칸이라도 "아니오"면 그 조합의
아레나·태세·파츠를 적어 둔다 — 다음 튜닝의 입력이다.

| # | 질문 | 무엇을 보는가 |
| --- | --- | --- |
| 1 | 돌격형이 표적에 **붙는가** | 첫 두세 라운드에 접촉하고, 붙은 뒤에는 떨어지지 않는가 |
| 2 | 거리형이 **거리를 두는가** | 접촉을 끊고 투석 사거리 띠(2칸~사거리) 안에 머무는가 |
| 3 | 호위형이 **곁을 지키는가** | 보호 대상 옆, 그리고 위협과 보호 대상 **사이**에 서는가 |
| 4 | 예고 칸을 **태세대로** 다루는가 | 돌격형은 감수하되 공짜로 밟지는 않고, 거리형은 피하고, 호위형은 대상 대신 받는가 |
| 5 | 파츠가 **제때** 나가는가 | 밀치기는 예고 중인 적에게, 엄호는 아군이 죽을 라운드에 — 접촉 중에 원거리 파츠를 꺼내지 않는가 |

아레나 3개 × 태세 3개(같은 태세로 전원을 맞춰 한 번, 혼합으로 한 번 보면 더 빠르다):

| 아레나 | 돌격형 | 거리형 | 호위형 |
| --- | --- | --- | --- |
| `early_hob` (근접 1) | [ ] 1 [ ] 2 [ ] 3 [ ] 4 [ ] 5 | [ ] 1 [ ] 2 [ ] 3 [ ] 4 [ ] 5 | [ ] 1 [ ] 2 [ ] 3 [ ] 4 [ ] 5 |
| `deep_mixed` (근접 2 + 원거리 1) | [ ] 1 [ ] 2 [ ] 3 [ ] 4 [ ] 5 | [ ] 1 [ ] 2 [ ] 3 [ ] 4 [ ] 5 | [ ] 1 [ ] 2 [ ] 3 [ ] 4 [ ] 5 |
| `deep_caster` (근접 1 + 시전자 1) | [ ] 1 [ ] 2 [ ] 3 [ ] 4 [ ] 5 | [ ] 1 [ ] 2 [ ] 3 [ ] 4 [ ] 5 | [ ] 1 [ ] 2 [ ] 3 [ ] 4 [ ] 5 |

수치 증거는 위 `--explain` 표에 있다. 이 체크리스트는 그 표가 **화면에서도 같은 이야기를 하는지**를
묻는 것이므로, 표와 눈이 어긋나면 어긋난 쪽을 그대로 적는다.
