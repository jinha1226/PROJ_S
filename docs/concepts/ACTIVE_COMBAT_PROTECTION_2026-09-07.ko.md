# 타깃 편향 및 보호 판단 수정 검증

기존 256시드 × 7조건 × 6정책 = 10,752회와 동일 조건을 재실행했다. 적/아군 스킬·HP·기력·종족 속도·배치·주인공 사망 패배 규칙은 유지했다. 변경은 tactical_action_selector 공통 AI: ID 독립 동률/접근 대상 선택, 피해 과잉분 제한, 처치로 제거할 위협 평가, 실제 위험 대비 치유/보호막/밀치기, 행동 시간당 효용이다. 개별 요소를 분리한 실험이 아니므로 차이를 ID 편향 제거 하나에만 귀속하지 않는다.

성격+스킬 조건, 주인공 가까운 적 우선 정책:

| 항목 | 이전 | 수정 |
|---|---:|---:|
| 승리 / 256 | 87 (34.0%) | 208 (81.3%) |
| 패배 | 169 | 48 |
| 동료 세 명 생존 상태에서 패배 | 163 | 35 |
| 패배 시 남은 동료 HP 평균 / 300 | 272.3 | 206.3 |

기존 효용 정책도 105/256 → 216/256으로 변했다. 이 정책은 주인공 판단까지 함께 바뀌므로 비교 해석에 주의한다. 전체 실행에서 잘못된 명령과 제한 도달은 0, 첫 표본 재실행 일치. 대칭 타깃 64시드에서 30/34 선택, ID 교환 및 배열 반전 시 같은 위치 선택. 위험한 동료 우선 지원, 주인공 ID 교환 후 동일 지원, 진영 교환 후 동일 지원, 중복 보호막 회피, 원거리/벽/행동 시각 위험 평가를 테스트했다. 기존 시간표·전투 UI 회귀 및 소스 없는 웹 패키지의 전투 UI 검사 통과.

중요: 이 실험은 총 HP 기반이며 본 게임 육체 시뮬레이터, 출혈, 부위 손상/기능 소실, 장비/이능 트리거, 전체 감정 기억과 연결되어 있지 않다. 이 승률은 최종 밸런스가 아니다. 후속 밸런스 조정보다 실제 전투·육체 처리 공유를 먼저 진행해야 한다. 새 어그로 스탯, 도발, 몸으로 가로막기 기능은 추가하지 않았다. 실제 게임의 고정 주인공 구조를 변경하지 않았다.

원시 결과: `/tmp/active-combat-after-protection-256.json`. 집계: `ACTIVE_COMBAT_PROTECTION_2026-09-07.json`.

```sh
godot --headless --path . --script tools/active_combat_balance_sweep.gd -- --seeds=256 --output=/tmp/active-combat-after-protection-256.json
node tools/summarize_active_combat_sweep.mjs /tmp/active-combat-after-protection-256.json docs/concepts/ACTIVE_COMBAT_PROTECTION_2026-09-07.json
godot --headless --path . --script tests/tactical_action_selector_smoke.gd
```
