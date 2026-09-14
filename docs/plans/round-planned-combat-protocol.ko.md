# ROUND-COMBAT-01 실행 protocol

기준 HEAD `69e2483`(구현 기준 `5853fba`). 기존 사용자 변경 없음, 기존 미추적 import/uid/cache는 보존한다. 사용자 지정 계획의 A–F 범위를 현재 세션에서 실행한다. 푸시는 포함하지 않는다.

## 기존 속도 조사와 채택값

| 데이터 | 기존 사용 | 라운드 사용 |
|---|---|---|
| member.action_speeds MOVE/ATTACK/CAST(기본 각100) | 채널별 duration=ceil(base*100/rate) | 세 채널의 기준 동작 시간(MOVE100, 장비 공격+reload, CAST100)의 조화평균으로 initiative. DEX 추가 보정 없음 |
| DCSS 장비 attack_time/reload_time | 물리 행동 비용/재장전 | initiative의 ATTACK 채널과 실제 공격 busy/cooldown에 반영. 장비 변경으로 현재 순서 변경 없음 |
| HASTE +50 / SLOW -35 | 행동 rate | 각 채널 rate, 다음 라운드 순서·현재 남은 이동력에 반영 |
| 부상 move_milli 1000–3000 | 기존 탐험 이동 duration 증가 | 전투 이동력에만 base*1000/move_milli. initiative·라운드 시간 중복 감소 없음 |
| 이동 이능 move_delay / anchored | 이동 지연/불가 | 이동 예산 denominator(100+delay) / 기존 이동 assess 재사용 |
| 지형 move_time_cost | 탐험 이동 시간 | 전투 이동 예산 ceil(cost/100), 대각선 기존 flank 규칙 재사용 |
| 기존 이능 action_time / energy | 쿨다운·MP | 실행 시 기존 assess/commit 재사용, 슬롯별 세계 시간 증가 없음 |

기본 이동3, MOVE rate 기반 1–6칸, 부상 후 최소1칸. 순서는 initiative 내림차순·stable ID 오름차순. 참여자 라운드당 최대1회, 시간100을 완료 경계에서1회. 지속효과·환경·허기·NPC 시간 처리도 이 경계에 연결하고 참여자는 기존 자동 큐에서 제외한다.

실행기와 preview는 같은 순차 resolver를 사용한다. 결정적 기존 keyed-hash 전투 결과는 round/actor/slot 문맥으로 고정하며 preview 갱신으로 재추첨하지 않는다. 미탐색 정보로 인해 달라질 수 있는 결과는 조건부로 공개하고 숨은 적 정보를 DTO에서 제거한다. 공개 공격은 기본 월드 타일 고정; 추적/회복 개체 기술만 ENTITY로 구별한다.

계획·중단 상태는 party schema26 안에 넣어 snapshot·rollback에 포함한다. round 명령을 세션 journal로 재생한다. 별도 BALANCE_ID로 기존 저장은 보존하며 이전 전투 규칙 세션은 새 게임 안내로 거부한다.

각 단계의 테스트·결과를 결과 문서에 누적하고 커밋한다. 필수 통합·회귀·모바일 검사와 성능100라운드 결과는 실제 실행 여부와 수치를 구별해 기록한다.

## 보상 규칙 사용자 수정

사용자는 적끼리 공격해 죽은 경우에도 플레이어 경험치를 지급하도록 명시했다. 플레이어의 유도 여부와 관계없이 전투 중 적끼리 오사하여 죽으면 처치 경험치를 지급한다. 밀치기 등으로 적 공격을 유도한 처치도 정상 보상이다. 기존 적 사망 보상·중복 지급 방지·드롭 출처를 재사용하며 적 오사 사망을 경험치에서 제외하지 않는다. 인수인계 계획의 “모든 적 오사 경험치를 무조건 주는 새 정책을 만들지 않는다”보다 이번 사용자 지시가 우선한다.
