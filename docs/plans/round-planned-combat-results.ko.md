# 계획 라운드 전투 구현 결과

## 구현 상태

권위 상태·계획 편집·혼합 순서 실행·shadow preview·논리 중단/재개·세션 저장 재생을 제품 세션에 연결했다. 최초 상태 정의는 `e097f4e`, 실행기 및 세션 통합은 `22e490c`다. UI 변경은 별도 검증·커밋 단계에 남아 있으며 전체 인수 검증 완료를 선언하지 않는다.

라운드 시간은 참여자 수와 관계없이100, 기본 이동 예산3이다. initiative는 MOVE/ATTACK/CAST 채널에서 산출하고 HP 연동 부상은 이동 예산에 반영한다. 공격은 고정 월드 칸을 판정한다. preview는 같은 실행기로 shadow 세계를 실행하고 변경 없는 요청은 캐시한다.

## 사용자 확정 보상 규칙

전투 중 적끼리 오사하여 적이 죽어도 플레이어에게 처치 경험치를 지급한다. 플레이어가 유도했는지는 조건이 아니다. 밀치기로 유도한 처치도 포함한다. 실제 적 가해자와 사망 이벤트의 출처는 유지한다. 동일 사망 이벤트에 대한 경험치 중복 지급을 막는 기존 보상 장부를 재사용한다.

`tests/round_combat_advanced.gd`에서 먼저 이동으로 공격 칸을 비우고 다른 동료가 적을 밀어 넣은 뒤, 앞서 고정된 적의 공격으로 그 적이 죽는 순서를 검증했다. 플레이어 경험치 증가, 실제 적 가해자와 보상 출처, 보상 이벤트1회, 재처리 시 경험치 불변, 피해·사망·전리품 전체 이력 검증, snapshot 정확 복원을 통과했다. SHOVE는 현재 획득용 고기 아이템이 없는 기존 기술이라 테스트 fixture에 정상 형식의 획득 이력을 기록했다. 제품의 기술 장착 검사는 그대로 사용한다.

## 실제 실행한 검증

Godot4.6.2 headless, WSL Linux 환경에서 다음 검사를 실행했다.

| 검사 | 결과 | 확인 범위 |
|---|---|---|
| `round_combat_core.gd` | PASS | 기본 새 게임·실제 탐험 이동 후 계획 진입, preview 무변경, revision/중복 승인 거부,100시간 경계, 저장 journal 재생 |
| `round_combat_scenarios.gd` | PASS | 고정 AI 계획·아군 편집, 모든 참여자 기회1회, 전체 이력·복원 |
| `round_combat_advanced.gd` | PASS | 파티3/적3 혼합 순서, 밀치기와 적 오사 처치 경험치, 피해 예측 일치, 골절/치유 이동 예산, 막힌 경로, 실제 피해 후 계획 물약 사용 |
| `round_combat_interruptions.gd` | PASS | 이동 도중 숨은 적 발견, 미완료 경로와 실행 cursor/RNG 저장, 기존 순서 유지와 신규 적 추가, 재개100시간1회, 중복 재개 거부 |
| `hp_derived_injury_regression.gd` | PASS | 기존 HP 연동 부상 회귀 |
| `git diff --check` | PASS | 공백 오류 없음 |

재현: 저장소에서 `godot --headless --path . --script tests/round_combat_advanced.gd` 등 해당 파일로 실행한다. 실행 로그는 `/tmp/round-advanced-xp-final.log`, `/tmp/round-core-current.log`, `/tmp/round-interruptions-fixed.log`, `/tmp/round-hp-regression.log`에 기록했다.

## 남은 인수 검증

전체 이능/패시브, 상태·휴식·줍기·전술 표시·솔로 회귀, 실제 모바일360×800/390×844 터치, 파티3/적6의100라운드 성능 측정 및 추적/탐험 경계 추가 검사는 아직 전체 완료하지 않았다. headless PASS를 모바일 시각 검증으로 대체하지 않는다. 새 BALANCE_ID 저장은 기존 규칙 저장과 호환되지 않으며 기존 파일은 삭제하지 않는다. 푸시는 실행하지 않았다.
