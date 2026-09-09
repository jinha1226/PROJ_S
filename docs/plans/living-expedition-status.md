# 생활 원정 시스템 구현 상태

2026-09-09 현재의 코드와 남아 있는 `/tmp` 로그를 읽기 전용으로 대조한 결과다.

## 결론

생활 원정 MVP의 핵심 시스템 코드는 구현되어 있고 전용 acceptance는 통과했다. 다만
“모든 시스템과 UI가 완전히 끝났다”고 말할 상태는 아니다. 시스템 변경은 이번 통합
커밋 대상이며, 장시간·원거리 자율 생활이나 모든 생애 단계
뒤의 저장 재생까지 보장하는 완성형 월드 시뮬레이션은 아니다.

## 구현되어 확인된 범위

- 신규 캠페인에서 인간·엘프·드워프·오크·수인 5종을 선택하며 종족 고정 특성과 개인
  재능을 함께 표시한다. 마을 주민도 5종과 서로 다른 성격으로 생성된다.
- 버전 이벤트가 있는 새 캠페인만 생활 원정 지도와 행동을 사용한다. 레거시 생성자는
  자동 opt-in하지 않는다.
- 던전 방문자는 자동 동료가 아닌 동일한 물리 엔티티다. 좌표·점유·인물 정보가 같은
  ID를 사용하며 탐색, 휴식, 귀환, 피격, DOWNED, DEAD 상태를 기록한다.
- 이동은 공통 이동/경로 규칙, 근접전은 공통 무기·방어·피해 이벤트를 사용한다. 적의
  busy clock을 공유하고, 중립 NPC가 실제 인접한 경우에만 중립 교전 스케줄러가 적 행동을
  처리한다. 중립 처치의 플레이어 XP 제외와 영입된 옛 방문자의 XP 허용도 구분한다.
- AID는 플레이어 식량을 대상 NPC 인벤토리로 실제 이전한다.
- 1층과 2층에 버전 고정 발견 구간, 캠프/유물/보급 지점, 방문자 위치가 있으며 입구,
  출구, 포털, 보급 및 방문자 위치의 flood connectivity를 검사한다. 지도에는 landmark
  데이터와 native 표시 경로가 연결되어 있다.
- inspect/render는 시간을 진행시키지 않으며 기존 NPC 인물창, 마을 이동, 전투 명령
  회귀 테스트가 통과했다.

## 실제 검증 증거

- `/tmp/living-expedition-acceptance.log` (09:34): 0 failed.
- `/tmp/living-npc-inspection.log` (09:36): PASS.
- `/tmp/living-party-movement.log` (09:41): 7개 이동 회귀 PASS.
- `/tmp/living-town-navigation.log` (09:44): 320×640, 360×800, 430×932 PASS.
- `/tmp/living-battle-command-flow.log` (09:45): PASS.
- `/tmp/living-species-migration.log` (09:53): 7/7 PASS. 5종 저장/재생과 대형 캠페인
  simulator 재사용을 포함한다.
- `/tmp/living-editor-parse-escalated.log` (09:58): editor 초기화와 파일 스캔 완료.
- `/tmp/living_world_progression.log` (09-05): progression 5/5 PASS. 현재 생활 원정 변경
  뒤에 다시 실행한 로그는 아니다.

## 남은 검증·제품 한계

- 독립 NPC cadence는 플레이어로부터 16칸 이내에서만 처리된다. 현재 층의 가까운 NPC가
  살아 움직이는 MVP이며, 맵 전체를 계속 시뮬레이션하는 생활 세계는 아니다.
- 방문자는 성격·체력·식량·피로에 따라 EXPLORE/FIGHT/REST/RETURN을 선택하지만 행동
  종류와 목표 순환은 작다. 원거리 무기는 이 중립 전투 경로에서 지원되지 않아 거리를
  벌리는 fallback을 사용한다.
- 전용 acceptance의 깨끗한 저장/재생은 실제 actor cadence 뒤 snapshot 동일성을 검사한다.
  AID·DOWNED·DEAD 시나리오는 공통 이벤트와 현재 상태를 검사하지만, 이 모든 단계를
  지난 별도의 저장/재로드 시나리오까지 한 테스트로 검증하지는 않는다.
- 두 층은 서로 다른 재질·명칭의 발견 구간을 제공하지만 기본 공간 구성은 공통 템플릿에
  가깝다. 광범위한 생태·직업·경제 활동까지 구현된 것은 아니다.
- `/tmp/lws-progression-item-ui-10907.log` (09-07)은 progression UI 단독 fixture에서
  360×640 및 450×800 지도/portrait strip 배치 2건 실패를 기록한다. 이 로그는 이번 생활
  원정 변경보다 이전 것이므로 현재 코드 버그인지 오래된 fixture인지 최신 실행 없이는
  판정할 수 없다.
- 과거 작업 요약의 “progression 2/5 통과, 3건 실패(빈 combat preview/guard rows 및 mobile
  status label)”는 대응 로그 파일을 찾지 못했다. 따라서 실패 수와 원인을 현재 증거로
  확인할 수 없으며, 해결됐다고도 현재 실패라고도 주장하지 않는다.

## 배포 상태

감사 시점의 HEAD `52a6488`에는 최근 미술 커밋까지만 포함되어 있었다. 생활 원정 관련
`sim/`, `playtest/`, `tests/`, `docs/` 변경은 승인된 장비의 런타임 연결과 함께 이번 통합
커밋에 포함한다. GitHub Actions 배포 성공과 실제 모바일 플레이 검증은 별도 확인 사항이다.
