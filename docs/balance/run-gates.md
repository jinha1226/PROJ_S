# 하강 Run 밸런스 게이트

기준: `3481360`에서 Plan A를 적용한 작업 트리 · Godot 4.6.2 · 고정 시야 5칸 · 물자 5종 · 횃불/밝기/부상 없음.

| 게이트 | 표본 | 결과 | 판정 |
| --- | ---: | --- | --- |
| `solo_balance` | 1층 8시드 | 하강 3/8, 사망 5/8, 경로 정체 0 | 최소 3/8 충족 |
| `stance_gate` G7 | 40시드 × 6 아레나 × 4 빌드 | 혼합 태세 6/6 아레나 통과, 단일 태세 기준도 충족 | 통과 · [전체 표](stance-gates.md) |
| `utility` | 계약 검사 154개 | 실패 0 | 통과 |

`ranged_probe`는 고정 아레나의 탐색 측정이며 현재 합격 기준은 없다. 아래는 각 구성의 승률이다(`tests/ranged_probe.gd`).

| 아레나 | 1인 | 2인 | 3인 |
| --- | ---: | ---: | ---: |
| early_pair | 1.00 | 1.00 | 1.00 |
| deep_mixed | 0.00 | 1.00 | 1.00 |
| opt_archers | 0.00 | 1.00 | 1.00 |
| two_archers | 0.00 | 1.00 | 1.00 |

솔로 원거리 조합 3종의 패배는 남은 밸런스 문제다. 이 아레나는 층 생성 예산과 별도로 몬스터 구성을 고정하므로, 층 예산만 낮춰도 탐침 수치는 바뀌지 않는다. 첫 층 실제 하강 게이트도 하한에 걸쳐 있으므로 다음 밸런스 변경 때 별도 시드 묶음으로 재검증해야 한다. `ranged_probe`의 `taken` 출력은 현재 피해 집계가 연결되지 않아 판정에 사용하지 않았다.

재실행 명령:

```bash
godot --headless --path . --script res://tests/solo_balance.gd
godot --headless --path . --script res://tests/stance_gate.gd
godot --headless --path . --script res://tests/ranged_probe.gd
godot --headless --path . --script res://tests/utility.gd
```
