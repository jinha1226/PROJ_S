# 부위·장비·빌드 AI 후속 게이트

2026-09-26 · 기준 `358be17`과 이번 구현을 같은 시드로 비교. 기존 미커밋 난이도 변경은 양쪽에서 제외했다.

실행: `tests/stance_gate.gd -- --quick`의 계산 경로. 보고서 경로만 임시 파일로 바꿔 기존 측정 결과를 덮어쓰지 않았다. 3인 파티, 빌드 4종 × 아레나 6종 × 시드 8개 = 버전당 192전투. 축약 시드이므로 최종 밸런스 승인에 쓰지 않는다.

| 빌드 | 아레나 | 이전 승률 | 구현 후 승률 |
| --- | --- | ---: | ---: |
| stance_mixed | early_hob | 100.0% | 100.0% |
| stance_mixed | early_pair | 100.0% | 100.0% |
| stance_mixed | deep_mixed | 75.0% | 75.0% |
| stance_mixed | deep_caster | 100.0% | 100.0% |
| stance_mixed | opt_archers | 100.0% | 100.0% |
| stance_mixed | opt_gnoll | 100.0% | 100.0% |
| stance_charger | early_hob | 100.0% | 100.0% |
| stance_charger | early_pair | 100.0% | 100.0% |
| stance_charger | deep_mixed | 100.0% | 100.0% |
| stance_charger | deep_caster | 100.0% | 100.0% |
| stance_charger | opt_archers | 100.0% | 100.0% |
| stance_charger | opt_gnoll | 100.0% | 100.0% |
| stance_skirmisher | early_hob | 100.0% | 100.0% |
| stance_skirmisher | early_pair | 100.0% | 100.0% |
| stance_skirmisher | deep_mixed | 75.0% | 75.0% |
| stance_skirmisher | deep_caster | 100.0% | 87.5% |
| stance_skirmisher | opt_archers | 87.5% | 87.5% |
| stance_skirmisher | opt_gnoll | 100.0% | 100.0% |
| stance_guardian | early_hob | 100.0% | 100.0% |
| stance_guardian | early_pair | 87.5% | 87.5% |
| stance_guardian | deep_mixed | 62.5% | 62.5% |
| stance_guardian | deep_caster | 50.0% | 50.0% |
| stance_guardian | opt_archers | 50.0% | 50.0% |
| stance_guardian | opt_gnoll | 100.0% | 100.0% |

- 혼합 파티: 전후 모두 5/6 아레나 통과. `deep_mixed`는 목표 승률 85%에 못 미친다.
- 단일 태세: 전후 모두 각 빌드의 4개 이상 아레나 통과 조건을 만족한다.
- 솔로 원정 봇: 전후 모두 1/8 완주. 경로 막힘은 없지만 이 봇의 생존율을 개선할 추가 밸런스 작업이 필요하다.
- 이 행렬은 기존 대표 부위 로드아웃의 회귀 비교다. 새 60개 효과와 장비의 모든 조합이 균형 잡혔다는 증거가 아니다.
- 새 기능은 `part_effects`, `gear_slots`, `randarts`, `unrands`, `gear_affixes`, `build_sense`, `build_ai`의 상태·대가·결정론·선택 시나리오로 검증한다.
