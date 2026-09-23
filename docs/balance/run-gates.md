# 하강 Run 밸런스 게이트

기준: 병합 트리 `c3f141c`(Plan A 하강 Run + Plan B 던전 NPC) 위의 리뷰 수정 라운드 · Godot 4.6.2 · 고정 시야 5칸 · 물자 5종 · 횃불/밝기/부상 없음.

| 게이트 | 표본 | 결과 | 판정 |
| --- | ---: | --- | --- |
| `solo_balance` | 1층 8시드 | 하강 3/8, 사망 5/8, 경로 정체 0 | 최소 3/8 충족 |
| `stance_gate` G7 | 40시드 × 6 아레나 × 4 빌드 | 혼합 태세 6/6 아레나 통과 | 통과 · [전체 표](stance-gates.md) |
| `utility` | 계약 검사 154개 | 실패 0 | 통과 |

NPC 시야 확장(Plan B)과 솔로 AP 변경이 겹친 뒤의 재측정이다. 세 게이트 모두 `3481360` 기준값과 같은 수를 냈으므로 `floor_themes.json`의 몬스터 예산은 손대지 않았다.

`ranged_probe`는 고정 아레나의 탐색 측정이며 현재 합격 기준은 없다. 아래는 각 구성의 승률이다(`tests/ranged_probe.gd`, 병합 트리에서 재측정 — 값 변동 없음).

| 아레나 | 1인 | 2인 | 3인 |
| --- | ---: | ---: | ---: |
| early_pair | 1.00 | 1.00 | 1.00 |
| deep_mixed | 0.00 | 1.00 | 1.00 |
| opt_archers | 0.00 | 1.00 | 1.00 |
| two_archers | 0.00 | 1.00 | 1.00 |

솔로 원거리 조합 3종의 패배는 남은 밸런스 문제다. 이 아레나는 층 생성 예산과 별도로 몬스터 구성을 고정하므로, 층 예산만 낮춰도 탐침 수치는 바뀌지 않는다. 첫 층 실제 하강 게이트도 하한(3/8)에 걸쳐 있으므로 다음 밸런스 변경 때 별도 시드 묶음으로 재검증해야 한다. `ranged_probe`의 `taken` 출력은 현재 피해 집계가 연결되지 않아 판정에 사용하지 않았다.

## 기록되지 않았던 밸런스 변경

Plan A가 계획·스펙에 적지 않고 넣은 두 가지다. 둘 다 **의도된 것으로 확정**하고 여기에 남긴다.

### 1. 솔로 AP 2 → 1

`Session.action_budget()`은 파티가 1인일 때 `solo_rule("solo_actions")`를 돌려주고, 기본 규칙(`DEFAULT_RULES` = `balance_experiments.json`의 `current`)이 `solo_actions: 1`이다. 2인 이상은 종전대로 2(붕괴 상태면 1)다.

의도: **맞다.** 혼자인 주인공에게 라운드당 2행동을 주면 접근-공격을 한 턴에 끝내 몬스터가 반격할 기회를 잃고, 태세·엄호가 의미를 갖는 2·3인 파티 쪽이 상대적으로 약해진다. 솔로가 `solo_actions: 2`(실험 `A`)인 구성은 `balance_experiments.json`에 실험으로 남아 있으므로 되돌리려면 규칙만 바꾸면 된다. 현재 3/8 게이트는 `solo_actions: 1`에서 잰 값이다.

### 2. `theme_for()`의 무리 크기 증가

```gdscript
if depth >= 3:
    for key in theme.monsters.budget: theme.monsters.budget[key] = roundi(theme.monsters.budget[key]*scale)
    theme.monsters.max_members = mini(4,2+int(depth/3))
```

스펙 §4.1은 예산 배율 `×(1 + 0.25·(depth − 2))`만 적고 있었고 `max_members`는 적혀 있지 않았다.

판정: **유지하고 스펙에 적는다.** 예산만 키우면 깊은 층이 "같은 수의 더 센 몬스터"가 되어 태세·엄호·밀치기의 의미가 줄어든다. 깊이가 늘려야 하는 것은 개체의 강함이 아니라 무리의 크기다. 스펙 §4.1에 한 줄을 추가했다(3·4·5층 3인 무리, 6층부터 4인 무리 상한, 식은 고정하고 튜닝은 예산 값으로).

주의: 게이트 수치는 전부 1층(`depth = 1`)과 고정 아레나에서 잰 것이라 이 두 변경 중 `max_members` 쪽은 **게이트가 재지 않는다**. 깊은 층 난이도는 `solo_balance`의 2층 이후 구간이 측정 대상이 될 때 다시 봐야 한다.

## `encounter_builder.gd` — 범위 밖 변경 보류

Plan A의 폴백 탐색 변경은 별도 커밋으로 보류. `expedition/encounter_builder.gd`는 `origin/main`과 바이트 동일하며(`git diff origin/main -- expedition/encounter_builder.gd`가 빈 출력), 무리 채우기 폴백을 재귀 탐색으로 바꾼 hunk와 깊이 6 클램프 hunk 모두 병합에서 제외됐다. 깊이 클램프만 load-bearing이었으므로 호출부(`floor_generator.gd`의 `Encounters.fill(rng,mini(depth,6),…)`)에서 대신 맞췄다 — 빌더 자체는 손대지 않았고 Plan B의 조우 구성 게이트 수치는 그대로다.

## 테스트 이주

전역 제약("삭제 스위트 7개 외에는 검사 수를 줄이지 않는다")을 깬 7개 파일의 복구 결과다. 수치는 소스의 `check(` 등장 줄 수(`check` 정의 줄 1개 포함).

| 스위트 | 기준 `3481360` | 수정 후 | 지운 검사를 무엇으로 바꿨나 |
| --- | ---: | ---: | --- |
| `solo_floor` | 81 | 81 | 유물 발견·집기·귀환 → 계단 발견·하강 규칙, 마을 회복 → 야영 규칙, 원정 왕복 → 층간 지속(파츠·물자·기억·처치 수), 마을 결과 화면 → 세로 화면 HUD 적합·44px 타깃·2인 카드 |
| `mobile_hud` | 53 | 61 | 횃불·자금 위젯과 게이지 → 식량 라벨·야영 버튼·푸터 구성, 상점/숙소 44px → 푸터·물자 슬롯·멤버 카드 44px. 유지·복구: 뷰포트 적합, 미니맵 가시성, 시야 정지(6→5칸), 토스트 수명, 대각선 차단, 동료 명령(HOLD/대열) |
| `integration` | 46 | 46 | 3×3 방 지도·마을 왕복·유물 → 층 생성 결정성, 층 위 행동 계약(거절은 무료·밀치기·물/불), 라운드 종료 적 차례, 기억 기록 4종, 전멸 종료 |
| `companion_tactics` | 98 | 100 | 횃불/자금 HUD 버튼·`choose_skill` 예약 → 초상화 길게 누르기, 규칙 편집기(기본 대상·전술 규칙·숙련 탭), 이동 예고 마커 검증 |
| `curios` | 21 | 29 | 도구(열쇠·삽)·자금 보상 → 4종 조사물의 식량/파츠/소모품 결과, "도구 표 삭제", 거리 초과·주변에 적 있음·행동 불가, 짐승 식량 드롭 40시드 탐침 |
| `solo_balance` | 11 | 13 | 마을 보급·귀환 왕복·재출정 → 1층 8시드 하강 + 같은 주인공의 2층 연속 하강(campaign) |
| `enemy_turns` | 11 | 16 | 방 모드 수문장 → 층 몬스터 역할별 차례. 복구: 벽이 추격을 막음, 깨지 않은 적은 제자리, 죽은 시전자의 예고 무효 |

Plan A가 새로 만든 스위트도 `"%d checks, %d failures"`를 찍는다: `run_start` 16 · `camping` 8 · `floor_descent` 86 · `boss_floor` 90 · `playthrough` 12.

재실행 명령:

```bash
godot --headless --path . --script res://tests/solo_balance.gd
godot --headless --path . --script res://tests/stance_gate.gd
godot --headless --path . --script res://tests/ranged_probe.gd
godot --headless --path . --script res://tests/utility.gd
```
