# 아이템·전리품·무기 성장 단계 0~2 protocol

- 기준 commit: `e55672d` (`docs: plan item rewards and material-tier weapon progression`)
- 작업 범위: 단계 0~2의 대표 흐름
- 규칙 버전: `species-drops-v2`, `weapon-recraft-v1`, `item-reward-families-v1`
- 원칙: 기존 소유권·아이템 인스턴스·저장/복원 계약을 유지하고, 새 보상은 기존 이벤트와 레지스트리에 연결한다.

## 보상 계약

사망 보상 이벤트 `corpse.loot_materialized`는 기존 `generated_items`를 유지하고, 단계 1 보상에 다음 `reward_rows`를 추가한다.

| 필드 | 계약 |
|---|---|
| `reward_id` | 출처 테이블 안에서 정렬·중복 금지인 ID |
| `reward_family` | `CURRENCY` 또는 `MONSTER_ABILITY` |
| `definition_id` | 통화 보상에서는 빈 문자열 |
| `ability_id` | 이능 보상에서 실제 `ActiveSkillRegistry` ID, 통화에서는 빈 문자열 |
| `amount` | 양의 정수. 이능은 1 |
| `chance_per_1000` | 0~1000의 결정적 확률 |

대표 goblin 보상은 마석 드롭과 별개로 골드 12, 실제 구현된 `FIREBOLT` 이능 1개다. 동일 시드·사망 이벤트 ID·종족·보상 ID로 SHA-256 keyed roll을 계산하며 전역 RNG를 소비하지 않는다. 동일 이능은 화면/소유 효과상 한 번만 취급하고 자동 장착하지 않는다.

기존 `species-drops-v1` 사망 이벤트는 복원 검증에서 읽을 수 있게 유지한다. 과거 이벤트를 새 테이블로 다시 추첨하지 않는다.

## 대표 무기 재제작 계약

`WEAPON_SHORT_SWORD` → `WEAPON_SHORT_SWORD_IRON` 변환만 먼저 허용한다. 필요한 자원은 `MATERIAL_IRON_INGOT` 1개이며 테스트 비용은 골드 0이다. `+1` 강화 수치는 만들지 않는다.

재제작은 `WorldItemOperations.preview_recraft`/`commit_recraft`의 clone-validate-swap 경로를 사용한다.

- 성공: 같은 인스턴스 ID의 정의만 변경하고 재료 1개를 차감한다.
- 보존: 희귀도, 브랜드/affix, 소유자, 장착 슬롯, 쇠뇌 런타임 행.
- 실패·취소: live item state, revision, 이벤트를 변경하지 않는다.
- 완료 후 같은 원본 정의를 다시 재제작할 수 없다.

## 검증 순서

1. JSON·아이템·무기·종족 드롭·재제작 레지스트리의 엄격한 키/교차 참조 검증
2. 고정 시드 보상 행 재현성과 reward ID 중복 방지 검증
3. 대표 무기 재제작 성공 시 identity/affix/equipment 보존 검증
4. 재료 부족 거절 시 원자성 검증
5. 기존 corpse drop·JSON·전투/아이템 회귀 테스트 실행

## 의도적으로 다음 단계로 남긴 항목

이번 protocol은 단계 2의 대표 무기 한 개에 한정한다. T2/T3와 층별 생성 제한, 일곱 무기군 확장, 탐험 장소 보상, 이능의 레벨별 1~6칸 결속/제거 정책, 특별 발견, 완전한 UI는 후속 설계 승인 대상이다. 이번 구현은 현재 프로젝트의 기존 2-slot active loadout을 깨지 않으며, 보상 획득과 장착을 별도 명령으로 노출한다.
