# 몬스터 파츠 밸런스 게이트 (G1~G5)

**몬스터 파츠 도입 후 첫 측정.** 날짜 2026-09-22 · 코드 커밋 `fd25e19` (`feat(parts): part builds, enemy-use metrics, balance gates`). G1~G4와 [skill-value.md](skill-value.md)는 `fd25e19`의 깨끗한 작업 트리에서, [action-economy.md](action-economy.md)와 G5는 그 보고서를 커밋한 `f46781a`에서 돌렸다 — 두 커밋 사이에 게임 수치는 바뀌지 않았다.
기준은 [몬스터 파츠 설계](../superpowers/specs/2026-09-22-monster-parts-design.md) §5.2에서 실측 전에 고정한 것이고, 방법은 [밸런스 방법론](../balance-method.ko.md) §3·§5를 따른다.

적이 자기 시그니처 파츠를 예고하고 해결하는 환경에서 처음 돌린 측정이므로, 이 문서의 수치는 파츠 도입 이전 보고서의 수치와 직접 비교하지 않는다.

## 결과 표

| 게이트 | 도구 | 기준 | 실측 | 판정 | 시드 |
| --- | --- | --- | --- | --- | --- |
| G1 솔로 1층 | `tests/solo_balance.gd` (CI) | 8시드 중 승리 ≥ 3 | **5/8** (성공 0·3·4·5·7, 패배 1·2·6) | 통과 | 0~7 |
| G2 조우 아레나 (3인) | `tests/skill_value.gd` 표 1 + `tests/encounter_sim.gd` (CI) | 3인 `rules` 정책 6아레나 승률 ≥ 0.90 | 최저 **0.93** (`opt_archers`), 나머지 0.98~1.00 | 통과 | S2 5000~5059 |
| G2 조우 아레나 (솔로 초입) | 같음 | 솔로 `early_*` 승률 ≥ 0.50 | `early_hob` **1.00**, `early_pair` **1.00** | 통과 | S2 5000~5059 |
| G3 스킬 가치 | `tests/skill_value.gd` → [skill-value.md](skill-value.md) | 파츠 8종 중 지배 후보 0, "봇이 못 씀" 0 | 지배 **0**, 봇이 못 씀 **0**, 약함 **0** (전 16빌드 기준) | 통과 | S2 5000~5059 |
| G4 적 시그니처 사용 | `run_many.enemy_skill_uses_mean` → [skill-value.md](skill-value.md) 표 3 | 8종 각각 전투당 평균 ≥ 0.5회 | 최저 **0.51** (`RAT_GNAW`/`opt_archers`), 최고 2.22 | 통과 | S2 5000~5059 |
| G5 엄호 가치 | `tests/party_guard_probe.gd` | 3인 아레나 사망 수: 엄호 있음 < 없음 | **71 < 73** (300시드 합계) | 통과(주의) | 5000~5299 |

수치 조정은 **없었다.** 다섯 게이트가 모두 첫 측정에서 기준을 넘었으므로 설계 §5.2의 조정 우선순위(액티브 damage → cooldown → 패시브 value)를 쓸 일이 없었다. §3의 8종 수치는 구현된 값 그대로다.

## 실행 순서와 명령

```
godot --headless --path . --script res://tests/solo_balance.gd                     # G1
godot --headless --path . --script res://tests/encounter_sim.gd                    # G2 (CI 검사)
godot --headless --path . --script res://tests/skill_value.gd                      # G2·G3·G4 (보고서 재생성)
godot --headless --path . --script res://tests/action_economy.gd                   # G2 보조 (보고서 재생성)
godot --headless --path . --script res://tests/party_guard_probe.gd                # G5 (기본 300시드)
```

공통 조건: `rules` 정책, 물자 0(`skill_value`), 아레나 spec `size 20 · room [5,5,9,9] · door [9,4] · pillars [[8,8],[10,10]] · party_entry [9,5] · light 90`. 명중 판정이 없으므로 같은 커밋·같은 시드는 같은 전투를 낸다 — 표의 모든 칸은 재실행으로 그대로 재현된다.

## G2 — 3인 `rules` 정책 승률

기준 빌드 `melee_1`, 인원 3, 시드 60개.

| 아레나 | 티어 | 승률 [95% CI] | 기준 0.90 |
| --- | --- | --- | --- |
| `early_hob` | early | 1.00 [0.94, 1.00] | 통과 |
| `early_pair` | early | 1.00 [0.94, 1.00] | 통과 |
| `deep_mixed` | deep | 0.98 [0.91, 1.00] | 통과 |
| `deep_caster` | deep | 1.00 [0.94, 1.00] | 통과 |
| `opt_archers` | optional | 0.93 [0.84, 0.97] | 통과 |
| `opt_gnoll` | optional | 1.00 [0.94, 1.00] | 통과 |

솔로 초입: `early_hob` 1.00, `early_pair` 1.00 (기준 0.50). 솔로 심부·선택 아레나(`deep_mixed` 0.00, `opt_archers` 0.00)는 이 게이트의 대상이 아니다 — 행동 경제 결정이 아직 보류이고([action-economy.md](action-economy.md)), §5.2가 솔로에 건 조건은 `early_*`뿐이다.

CI 쪽 검사는 `tests/encounter_sim.gd`에 하나 추가했다: `early_hob` 구성·3인·`rules` 정책·20시드 `run_many`에서 `enemy_skill_uses_mean["HOB_CLUB"] > 0`. 적이 파츠를 실제로 쓰지 않으면 G4 계열 수치가 전부 무의미해지므로, 그 전제만 CI가 지킨다.

## G4 — 아레나 × 파츠 (전투당 평균 사용 횟수)

각 칸은 그 아레나의 빌드 16 × 인원 2 = 32칸의 평균이고, `최소 칸`은 그중 가장 낮은 칸이다. 기준은 평균 ≥ 0.5회.

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

목도리 도마뱀과 강쥐는 실험 아레나 6개에 자리가 없다. 8종을 빠짐없이 덮기 위해 같은 시드 묶음·같은 빌드 16 × 인원 2 격자로 1종족 아레나를 따로 돌렸다(`tests/skill_value.gd`의 `absent_rows`, 보고서 표 3 아래에 함께 나온다).

| 종족 | 파츠 | 전투당 평균 | 최소 칸 | 판정 |
| --- | --- | --- | --- | --- |
| dcss_frilled_lizard | `LIZARD_TAIL` | 0.65 | 0.00 | 통과 |
| dcss_river_rat | `RIVER_RAT_SPLASH` | 0.92 | 0.00 | 통과 |

**최소 칸 0.00의 정체 — 예고를 끊는 빌드다.** 0인 칸은 사거리나 조건이 막힌 것이 아니라, 그 칸의 플레이어 빌드가 예고를 끊어서 생긴다. `melee_1`·`starter`의 규칙 목록은 `[PUSH, NEAREST, CHARGING]`이라 적이 준비에 들어간 라운드마다 밀치기가 들어간다. 1종족 아레나를 `melee_1` 하나로만 재면 `LIZARD_TAIL`·`RIVER_RAT_SPLASH`가 둘 다 0.00이 되고 `interrupts_mean`이 1.00으로 올라간다(10시드 확인). 즉 0.00은 파츠의 실패가 아니라 밀치기의 성공이며, 파츠 수치를 올릴 근거가 되지 않는다. 6아레나 행렬 전체의 `interrupts_mean` 평균은 0.02회/전투다 — 적이 여럿이면 한 명을 끊어도 나머지가 해결한다.

## G5 — 엄호 규칙의 값

3인·`rules` 정책·아레나 `deep_mixed`·`deep_caster`·`opt_gnoll`·빌드 `melee_1`·`b_iron`, 시드 5000~5299(300개). 같은 빌드에서 엄호 규칙만 뺀 것이 `no_guard` 열이다.

| 빌드 | 엄호 있음 사망 | 엄호 없음 사망 | 차이 |
| --- | --- | --- | --- |
| `melee_1` | 27 (25/0/2) | 28 (26/0/2) | −1 |
| `b_iron` | 44 (32/0/12) | 45 (34/0/11) | −1 |
| 합계 | **71** | **73** | **−2** |

괄호는 `deep_mixed`/`deep_caster`/`opt_gnoll` 순이다. 기준(있음 < 없음)은 합계와 빌드별 합계 모두에서 만족한다.

**주의 — 효과가 작고 아레나별로는 뒤집힌다.** 1800전투에서 사망 2건 차이(2.7%)이고, `b_iron`/`opt_gnoll` 한 칸은 오히려 12 > 11로 반대 방향이다. 원인은 엄호가 거의 발동하지 않는 것이다: 유일한 조건 `ALLY_LETHAL`이 가장 자주 맞는 칸에서도 전투당 0.05회고, 나머지 네 칸은 0.00~0.01회다. 설계 §5.2는 "예고가 근접 적에도 생겼으므로 차이가 벌어져야 정상"이라고 적었는데, 벌어지지 않았다 — 예고가 늘어난 만큼 밀치기(`CHARGING`)가 먼저 그 예고를 끊어 버리기 때문으로 보인다.

도구의 기본 시드 수는 이번 측정에서 60 → 300으로 올렸다. 60시드에서는 양쪽이 6 대 6으로 같아 **차이를 판정할 사망 표본 자체가 없었다**(3아레나 180전투에 사망 6건). 이것은 밸런스 수치 변경이 아니라 측정 표본 변경이며, `--seeds N`으로 예전 크기도 그대로 재현할 수 있다.

이 항목은 파츠 수치로 고칠 문제가 아니므로 §5.2의 조정 우선순위를 적용하지 않았다. 엄호의 값을 키우려면 `ALLY_LETHAL` 말고 다른 조건(적 2마리 이상 인접 등)을 주거나 밀치기와의 경합을 손봐야 하는데, 둘 다 이 스펙의 범위 밖이다. 다음 스펙의 후보로 남긴다.

## 남는 것

1. 엄호 조건 확장 — 위의 G5 주의 사항. 지금은 규칙이 거의 발동하지 않아 게이트가 표본으로만 통과한다.
2. 솔로 심부·선택 아레나(`deep_mixed` 0.00, `opt_archers` 0.00)는 행동 경제 결정이 보류라 그대로다. §5.2가 이번에 건 기준은 아니지만 다음 단계의 입력이다.
3. 사용 평균 0인 칸이 있는 빌드는 `melee_1`·`b_dressing`·`b_shockwave`·`p_lizard`·`p_orc` 다섯이다. 파츠 빌드 둘은 3인 `early_hob` 한 칸씩뿐이고(나머지는 기준선 `melee_1`과 구 시험 빌드), 다섯 모두 빌드 단위 사용 평균은 사장 기준(0.2)을 넘는다. 진단은 모두 "합법인데 규칙이 그 라운드를 고르지 않음"이다(`p_lizard`·`p_orc` 8/23) — 사거리·쿨다운이 아니라 규칙 조건 쪽이며 파츠 수치 조정 대상이 아니다. [skill-value.md](skill-value.md)의 진단 표 참고.
