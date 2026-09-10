# 환경 시뮬레이션 검토 후 마무리

기준: `3f67d39` / Godot 4.6.2 / Linux headless

## 수정 범위

- 물 잔량 1~9에서 wetness=0인데 source ID가 남아 턴이 롤백되던 오류 수정.
- 직접 열 입력과 수동 환경 tick의 발화 온도 판정을 공유. 전도된 열로도 발화하며, 자연 발화는 기존 fire_spread와 같이 다음 환경 tick부터 피해 가능.
- 불 확산이 바닥뿐 아니라 OIL 표면과 가연성 기체의 가연성도 사용.
- NONE/WATER 표면에 물을 부으면 실제 WATER 양을 추가. 이후 결빙·증발 경로에 참여.
- 점화 및 소화가 표면 물을 소비할 때 같은 양을 수증기로 이동. 수증기 저장 용량을 넘으면 물을 버리지 않고 남김. 포화 수증기로 점화 증발량이 0인 경우도 안전하게 거절 이벤트 생성.
- 소화 과정에서 wetness source를 초기화하기 전에 원인 ID를 보관해 소화 이벤트의 인과 관계 유지.
- 저장용 동적 타일 목록은 그대로 유지하되, 정지된 물·소진된 연료는 수동 flux 계산에서 제외. 변화하는 이웃의 열·기체가 있으면 다시 계산에 포함. 주위 온도 ±2의 잔여 열은 평형 온도로 정리.

## 근사 모델의 명시적 한계

- 물·기름·얼음은 여전히 단일 표면층이다. 이미 OIL/ICE가 있는 타일에 붓는 물은 기존 접촉 젖음 효과로 취급하며 다른 표면을 삭제하지 않는다. 혼합 유체나 이중 표면층을 추가한 변경이 아니다.
- 정상 온도의 물웅덩이는 접촉 젖음처럼 매 tick 사라지지 않는다. 물 표면 없는 기존 접촉 젖음은 계속 자연 건조한다.
- 수증기가 꽉 차 있으면 소화 효과는 적용하되 증발하지 못한 물은 보존한다. 잠열·정밀 유체 역학은 구현하지 않는다.
- 뜨겁거나 차가운 타일, 잔여 기체가 있는 타일의 계산까지 모두 잠재우는 캐시 최적화는 아니다. 저장용 dynamic 목록과 실제 flux 후보는 서로 다른 개념이다.
- snapshot v12 구조와 v11 거절 정책은 유지. 새 외부 소스·데이터·에셋을 도입하지 않았다. 상업 출시 전체 라이선스 감사를 뜻하지 않는다.

## 검증

환경 회귀에 잔량 81~89의 반복 턴/중간 저장 재실행, 열전도 발화, 돌 위 기름 확산, 부은 물의 결빙·증발, 수증기 포화 시 질량 보존, 정지 상태 100턴/롤백, 이웃 열 재활성화와 평형 수렴을 추가했다.

실행 명령:

```sh
godot --headless --path . --log-file /tmp/lw-env-final-full.log --script tests/run_tests.gd
godot --headless --path . --log-file /tmp/lw-env-final-environment.log --script tests/run_environment_simulation_tests.gd
godot --headless --path . --log-file /tmp/lw-env-regression-reproducible.log --script tests/run_environment_regression_tests.gd
godot --headless --path . --log-file /tmp/lw-env-field-turn-final.log --script tests/field_turn_acceptance.gd
godot --headless --path . --log-file /tmp/lw-env-resting-after.log --script tests/environment_performance_probe.gd -- --resting-only
```

- 환경 전용: **23 tests, 0 failed**.
- 환경 + 기존 원소/위험도 + core 저장·인과·재실행 + world/body: **62 tests, 0 failed**.
- 위 62개를 실행하는 전용 runner를 Pages CI에도 추가해 이후 배포 전 자동 검증한다.
- 실제 필드 턴 acceptance: **PASS**.
- 기존 idle/local fire/wide fire+gas/dense actors/chain explosion 성능 시나리오 5종도 모두 명령 승인, 최종 world_error 없음. 넓은 화재는 자연 발화가 추가되어 반응·이벤트가 증가하므로 정지 지도 최적화 수치를 그대로 적용할 수 없다.
- 별도 rollback 검사: 기능 5개 통과. 기존 성능 fixture는 지도 크기 9,216 기대에 17,664가 반환되는 불일치로 실패하며 환경 상태 복원 실패는 아니다.
- 전체 회귀: 기준 `3f67d39` **722 tests, 36 failed** → 수정 후 **728 tests, 36 failed**. 실패 테스트 ID를 정렬하여 비교한 결과 완전히 동일하며, 신규 6개 테스트는 전부 통과했다. 따라서 이번 변경의 추가 실패는 없지만 저장소 전체 검사가 통과한 것은 아니다.
- 기존 실패는 시체 드롭의 치명타 fixture/성장 보상, 예전 파티 저장 schema, 이전 UI·지도 규격, 적 인지, 정착지·진행·상태 lifecycle 계약, rollback 지도 크기 fixture 등에 남아 있다. 양쪽 실행 모두 종료 시 동일한 리소스 누수 경고도 남는다. 이번 환경 수정과 무관한 범위를 자동 수정하지 않았다.

전체 회귀 비교 명령 (테스트 ID 기준, 출력 없음 = 동일):

```sh
diff -u <(rg '^FAIL' /tmp/lw-env-baseline-full.log | sed 's/ -- .*//' | sort -u) <(rg '^FAIL' /tmp/lw-env-final-full.log | sed 's/ -- .*//' | sort -u)
```

## 정지 지도 성능 비교

같은 seed=206, 100×100 wood_floor에 소진된 연료 10,000칸 및 격자형 물 표면 5,000칸을 구성하고 WAIT 100회를 실행. 비교 대상은 기준 커밋의 별도 임시 checkout이며 양쪽에 동일한 측정 스크립트를 사용했다.

| 항목 | 수정 전 | 수정 후 |
|---|---:|---:|
| 평균 환경 tick | 369,908µs | 61,324µs |
| 평균 전체 turn | 524,983µs | 224,169µs |
| 저장용 dynamic 타일 | 10,000 | 10,000 |
| 최종 이벤트 수 | 5,100 | 5,100 |
| 명령 승인 / 최종 상태 검증 | 전부 승인 / 정상 | 전부 승인 / 정상 |

서로 다른 시작 시각의 단일 실행이며 다른 회귀 검사가 동시에 실행 중이었다. 약 6배의 환경 처리 차이는 해당 정지 지도에서의 관측일 뿐, 일반 전투 성능이나 모바일 성능 보장이 아니다. 전체 turn에는 저장·검증 등 환경 이외 비용이 남는다.
