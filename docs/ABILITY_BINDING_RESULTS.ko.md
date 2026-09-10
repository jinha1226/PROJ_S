# 이능 결속 구현 결과

- 완료일: 2026-09-10
- 기준 프로토콜: `docs/ABILITY_BINDING_PROTOCOL.ko.md`

## 구현 결과

- 캐릭터별 `bound_ability_ids`를 party schema v25에 추가했다.
- 레벨별 6칸 결속 DTO와 잠금 슬롯의 해금 레벨 표시를 추가했다.
- `ESSENCE_FIRE_BOLT`를 보관 후 `FIREBOLT`로 결속하는 원자적 서비스를 추가했다.
- 결속 시 아이템 소비, 결속 이벤트, command journal을 기록하고 실패 시 rollback한다.
- 동일 능력과 alias ID의 중복 결속을 차단한다.
- v24 저장은 빈 결속 상태로 안전하게 마이그레이션한다.
- 기존 상세 UI를 실제 결속 상태·보관 이능 아이템 표시와 결속 callback에 연결했다.
- 제거는 정책 미정 상태를 명시적으로 반환하며 UI에서도 잠겨 있다.

## 검증

`tests/run_ability_binding_tests.gd` 실행 결과:

- 3 tests, 0 failed
- 슬롯 한도 1/2/5/6/6
- alias·중복·아이템 소비·이벤트·저장 wire·party restore·정책 미정 제거 검증

기존 phase 4 회귀는 새 schema 컴파일 수정 후 정상적으로 실행되기 시작했으며, 전체 suite는 장시간 UI/통합 테스트가 포함되어 별도 확인이 필요하다. 이 변경은 기존 사용자의 guild/tutorial 및 환경 관련 dirty worktree를 포함하지 않고, 관련 능력 UI 테스트의 기대값만 새 계약에 맞췄다.

## 남은 결정

흡수=결속은 이번 구현의 안전한 권장 가정으로 확정했다. 제거 후 소멸·회수·재아이템화와 비용, 패시브 효과 수치, 결속 액티브의 전투 버튼 노출은 계획서의 미정 항목으로 남겨 두었고 임의로 삭제·자동 노출하지 않았다.
