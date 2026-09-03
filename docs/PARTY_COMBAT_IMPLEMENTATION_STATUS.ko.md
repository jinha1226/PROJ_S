# 파티 전투 구현 현황

기준일 2026-09-04, 기준 `fix/party-hexaco-v2` 커밋 `29a38e3`.

이 문서는 파티 전투 관련 구현 상태의 짧은 기준점이다. 세부 수치와 wire 계약은
`docs/superpowers/specs/2026-09-02-party-*.md`를 따르고, 과거 Phase 3/4 구현 프롬프트와
충돌하면 이 문서와 최신 스펙이 우선한다.

## 확정된 플레이 원칙

- 플레이어는 주인공을 조작하고 동료는 완전 자동으로 행동한다.
- 기본 흐름은 `개별 시야 → 파티 정보 공유 → 자동 경고 → 플레이어 행동을 암묵적 지시로
  사용`이다.
- 전투마다 성향·전술 프리셋이나 느슨한 명령을 다시 입력하지 않는다.
- 제품 예외 명령은 파티 전체용 `공격 대상 지정`, `후퇴`, `공격 중지`, `자리 지키기`,
  `따라오기` 다섯 개뿐이다.
- 개별 동료 override는 회귀·디버그용 내부 API에만 남고 제품 조작에는 노출하지 않는다.

## 성격 모델

파티에는 고정 성격 유형도, 과거 임시 4-facet
`aggression/altruism/boldness/composure`도 사용하지 않는다. 모든 동료는 `0..1000` 정수의
연속형 HEXACO 여섯 축 `H/E/X/A/C/O`를 저장한다.

- 성격은 탐지 성공이나 경고 누락 확률을 만들지 않는다.
- 성격은 같은 정보를 받은 뒤 `ENGAGE/PROTECT/RETREAT/HOLD` 효용을 편향한다.
- 사기 회복탄력성은 `C`와 `E`에서 결정론적으로 도출한다.
- 고정 유형명은 저장·판단하지 않는다. 표시용 요약 label만 파생할 수 있고 효과는 없다.

마이그레이션 경계와 축별 의미는
`docs/superpowers/specs/2026-09-02-party-hexaco-migration-design.md`가 권위다.

## 완료된 단계

### P1 — 동료 자율 전투

- HEXACO와 상황·관계·stress를 읽는 정수 Utility AI
- `ENGAGE/PROTECT/RETREAT/HOLD` 선택과 기존 HOLD/MOVE/MELEE 실행
- 반복 preview의 순수성, 설명 trace, 4인 파티 시드 매트릭스

### P2 — 적 무리 전술

- 적이 배치된 파티 전원을 인지
- 분대 focus와 대상 claim, 사망·이탈 시 결정론적 재표적
- 여러 적의 이동 목적지 예약과 충돌 시 대체 이동/HOLD
- 관찰 DTO와 8개 조우 매트릭스

### P3 — 사기·공포

- 피해·아군 다운/사망·적 사망의 직접 stress와 거리 4 이내 전염
- `NORMAL → PANIC` 850, `PANIC → NORMAL` 650 히스테리시스
- `party.morale_changed` 권위 사건, save/load/replay, 안전 회복
- 숨은 확률 판정이나 4개 성격 유형 없음

### 자율 제어·관찰 표면

- 동료가 주인공보다 먼저 적을 발견하고 `party.contact_reported`로 공유 가능
- 새 접촉 자동 정지와 발견자·방향 경고
- 주인공 공격 대상을 지속되는 암묵적 공통 focus로 사용
- 4 대 4 `[NPC 관찰]`의 상단 `NEXT` 행동 순서, 유닛별 가는 반투명 표적선,
  선택 유닛 판단 이유
- 다섯 예외 명령의 `party.command_issued` 사건·stale plan·세션 journal 재현

### P4-1 — 화면 밖 전투 forecast

- 주인공 참여·플레이어 관찰·상세 반경·미결정 선택·미지원 상태를 명시적으로 거부
- 두 세력의 stance, readiness, 대상별 정수 예상 피해와 이유 trace를 순수 계산
- HP·world time·RNG·ID·journal을 변경하지 않음

### P4-2a — 독립 권위 리듀서

- 대상별 HP 1/1000 잔여값을 보존하고 정수 HP를 올림하지 않음
- 피해→다운→사망, 라운드 종료와 조우 종료 사건
- canonical int64 문자열, 상태 hash, JSON save/load와 중단 재개 결정성
- caller 상태 무변경과 실패 시 전체 원자 거부
- 한 호출에서 모든 원격 조우를 합쳐 최대 8라운드만 처리하고 나머지는 이월

P4-2a는 아직 제품 frame/step에 연결되지 않았으므로 현재 실플레이 연산 비용은 0이다.

## 현재 검증

- 파티 AI: 20/20
- 적 무리 전술: 12/12
- 파티 사기: 9/9
- 화면 밖 전투 P4: 10/10
- 12개 4인 파티 전투·190턴: rejected step 0, invalid world 0
- 적 전술 8개 조우·89턴: rejected/invalid/restore failure 0
- 사기 8개 조우·116턴: 위법 PANIC/rejected/invalid/restore failure 0

## 다음 구현 순서

1. **P4-2b 제품 bridge:** 기존 combat profile·장비·HEXACO에서 입력을 투영하고 actor
   cadence에 도래한 활성 원격 조우만 전역 8라운드 예산으로 처리한다. 모든 NPC를 매 frame
   훑지 않고, 기존 환경/actor 두 canonical schedule을 늘리지 않는다.
2. **P4-3 상세 복귀:** 플레이어 접근·관찰·참여 시 축약 처리를 멈추고 동일-grid 상세
   전투로 복귀한다. P4 상태와 world entity HP/life가 이중 권위가 되면 안 된다.
3. **P4-4 매트릭스·튜닝:** 상세/축약 결과 편향, 정지, save/restore drift와 제품 체감
   성능을 측정한다.

아직 구현되지 않은 항목을 완료로 해석하면 안 된다. 특히 P4-2a 상태만으로 제품 전투를
건너뛰거나 원격 조우의 HP를 실제 `WorldState`에 적용하는 호출 경로는 없다.
