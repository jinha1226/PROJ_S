# 독립 탐험 NPC — 행동 점수·유지·이유 표시

기준: main에 푸시한 `9307306`. [소스 검토](NPC_SIMULATION_SOURCE_REVIEW.ko.md)의 첫 적용 단계다. 새로운 NPC 엔진/외부 플러그인은 추가하지 않는다.

## 연결한 범위

- `sim/independent_explorer_decision.gd`: 기존 동료의 `DecisionRulesetRegistry.ActionDef/ConsiderationDef/evaluate`, 정수 weighted sum과 linear curve를 재사용한다. 네 행동만 평가하며 고정 순서 `RETURN → FIGHT → REST → EXPLORE`로 동점을 결정한다.
- `sim/systems/independent_explorer_system.gd`: 실제 actor tick에서 새 정책을 호출한다. 이동·공격·피해·물자·휴식 처리는 기존 authority를 유지한다. 렌더 frame마다 NPC 판단을 실행하지 않는다.
- 성격 C/E/O, 현재 HP·피로·스트레스·공포·분노, **현재 NPC가 LOS로 확인한 적에 대한** 기존 SELF_HARM 기억 중요도를 입력한다. 부재한 HEXACO facet은 기존 동료 appraisal과 같이 500으로 처리한다. 기존 4-facet 성격을 임의로 다른 HEXACO 값으로 변환하지 않는다.
- 목표 변경 후 기본 300 world-time 유지, 기존 행동 대비 80점 이상 개선 시 전환. 기존 탐험 목표/짧은 경로 캐시도 계속 사용한다. 이는 목적지 생성/경로 탐색을 새로 만든 것이 아니라, 고수준 행동의 작은 점수 변동으로 인한 전환을 억제하는 장치다.
- 식량 고갈, 기존 기준 이하의 심한 부상, 귀환 서비스 결정, 근처 적과 싸울 수 없는 장비·신체 상태는 점수/유지 시간보다 우선한다. 쉬거나 탐색 중 적이 4칸 안으로 접근하면 유지 시간이 남아 있어도 재판단한다. 더 이상 보이지 않는 적은 전투 후보가 아니다.
- 행동 불가 recovery lock 동안 독립 NPC가 이동/공격뿐 아니라 직접 휴식 회복을 수행하지 않도록 `world.can_act`를 확인한다. 무기 사용 가능 여부는 기존 `Items.attack_error`에 맡긴다. 새 부상 판정이나 기어가기 금지 규칙을 만들지 않았다.

기본 효과 예: HP 65%, 적 거리 3, 보급 있음이라는 같은 상황에서 C/E=100인 탐험자는 교전, C/E=900인 탐험자는 귀환을 선택한다. O는 탐색 선호 점수에 반영되지만 모든 성격 축이 모든 행동에 의미 있는 영향을 주도록 억지로 연결하지 않았다. H/A/X의 구조·분배·합류 행동 확장은 이후 범위다.

## 표시와 저장

- 기존 NPC 상태 상세창 본문에 `현재 행동 · 식량이 떨어져 귀환 중` 같은 한 줄을 표시한다. HUD/맵/로그/초상화/버튼 배치는 변경하지 않는다.
- 현재 플레이어/파티의 시야에서 관측 가능한 독립 탐험자에게만 새 `npc_activity` 문자열을 제공한다. 보이지 않으면 빈 문자열이며, 점수표·적 ID·사적인 목표는 DTO에 넣지 않는다. 사망/쓰러짐은 오래된 행동 이유보다 현재 생명 상태가 우선한다.
- `population.patrol`의 기존 행에 `decision_mode`, `decision_reason`, `decision_until`, `decision_ruleset`을 저장한다. 재현에 필요한 작은 상태만 저장하며 consideration 전체를 매 tick 사건에 쌓지 않는다. 표시에는 기존 `activity` 필드도 사용한다.
- 정책 변경이므로 이전 규칙으로 생성한 원정 journal의 재현 호환성을 보장하지 않는다. 사용자 지시에 따라 이전 진행 자료 마이그레이션은 범위가 아니며, 새 원정으로 테스트한다. 이번 규칙으로 생성한 새 저장은 정확히 재현되는지 검증한다.

## 제외한 범위

원거리 NPC의 물리 행동 주기(기존 expanded 원정에서 거리 16 초과 시 최소 300 시간), 자동 구조/전리품 분배/배신, 새로운 장기 관계 모델, GOAP 연쇄 계획, 원거리·마법 NPC 공격 지원은 바꾸지 않았다. 같은 적을 계속 추적하는 별도 전투 타깃 고정이나 막힌 경로 cooldown도 새로 추가하지 않았다. 기존 자체 LOS/경로/시간 처리를 이어 쓰며, 살아 있는 모든 NPC의 위치 추론 모델을 재구축한 것은 아니다.

## 검증

- 기존 `living_expedition_acceptance.gd`: 성격별 선택, 물자·휴식·독립 이동·부상·서비스·기존 원정 저장 재현 검사 통과.
- `independent_explorer_utility_acceptance.gd`: 같은 상황의 성격/공포/기억 차이, 결정성, 유지 시간/전환 문턱/위험 중단, 무기 사용 불가, 실제 actor tick의 정책 상태 저장 및 정확한 journal 재현, recovery lock, 기존 상세창 한 줄 표시, 시야 밖 비노출을 확인한다.
- 로컬 headless 정책 평가 1000회 + 결과 동등성 비교 약 99ms 표본. 호출당 약 0.1ms이며 NPC 전체 시뮬레이션/모바일 성능 측정은 아니다.

- `independent_explorer_utility_acceptance.gd`: `INDEPENDENT UTILITY: PASS`, 스크립트 오류 없이 종료 코드 0.
- `legacy_shell_engine_acceptance.gd`: `LEGACY SHELL ENGINE: PASS`, 종료 코드 0.
- `godot --headless --quiet --path . --export-release Web build/web/index.html`: Web 내보내기 성공, 종료 코드 0.
- 별도 `/tmp` 경로에서 내보낸 `index.pck`를 `--main-pack ... --quit-after 5`로 실행: 스크립트 오류 없이 종료 코드 0. 이는 패키지 기동 검사이며 모바일 브라우저의 조작·성능 검증을 대신하지 않는다.
- 이전 작업 `9307306`의 main 푸시는 성공했다. GitHub Actions 배포 완료 여부는 이번 검증에 포함하지 않았다.
