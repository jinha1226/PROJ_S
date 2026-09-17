# 8×8 전술 RPG 스테이지 캠페인 — 설계 스펙

작성일: 2026-09-18
기준 커밋: `79f1f17` (8×8 SRPG 개별 턴 브랜치, `origin/backup/before-full-rollback-20260915` HEAD)
브랜치: `feat/srpg-stage-campaign`, 워크트리 `/mnt/d/STARTU/proj-s-srpg-stages`

## 0. 결정 요약

| 항목 | 결정 |
|---|---|
| 장르 | 턴제 전술 RPG (오토배틀러·방치형 폐기) |
| 전투 | 8×8 전장, 개별 initiative 턴, 이동 1~3칸·공격 1~3회 (브랜치 그대로) |
| 던전 구조 | 층 = 3×3 방 9개. **걸어서 방 이동 → 맵 화면에서 노드 선택**으로 교체 |
| 메타 | Darkest Dungeon식: 스트레스·붕괴/각성, 야영, 거점 로스터. 기벽은 HEXACO 값 이동으로 대체 |
| 도주 | 브랜치 규칙(출구 집결) 유지 + 추격 유지 + 스트레스 비용 추가. 원정 포기 추가 |
| 방 설계 | 방 하나하나 수제 저작. 스테이지 스키마 확장 + 설계 원칙 + 도구 |
| 플랫폼 | 모바일 웹(360×800) 우선, 스팀 PC 후속. 서버 없음 |
| 기준 코드 | `79f1f17`. 롤백 이후 커밋(Model B, 아트, use-based 스킬 등)은 필요 시 파일 단위 cherry-pick, 이번 범위 밖 |

## 1. 기준과 브랜치

- `79f1f17`에서 `feat/srpg-stage-campaign` 생성. 현 `merge/legacy-use-based-skills`·`main`은 건드리지 않는다.
- 첫 작업: 브랜치 테스트 6종이 현재 환경에서 통과하는지 재확인해 기준선을 잡는다.
  `stage_counterplay_acceptance`, `srpg_party_turns_acceptance`, `stage_context_ui_acceptance`,
  `first_floor_solo_roster`, `handcrafted_tile_assets_acceptance`, `round_combat_scenarios`.
- 테스트는 `/root/lw-bench` ext4 복사본에서 godot 순차 실행 (9p 경로는 20배 느림).
- cherry-pick 후보(이번 범위 밖): use-based 스킬 `ddbdbb8`, 변이 흡수 `798003a`.

## 2. 노드 맵과 방 진입

### 2.1 StageMapModel (`sim/stage_map_model.gd`, 순수 함수)

`nine_room_floor_state`를 읽어 UI가 쓰는 형태로 변환한다.

```text
{
  floor_index: int,
  current: room_id,
  nodes: [{id, name, role, biome, visited, cleared, reachable, camp_available}],
  edges: [[a, b], ...]          # 발견된 통로만
}
```

- `reachable` = 현재 방과 발견된 통로로 인접하며 현재 방이 전투 중이 아님.
- `cleared` = 전투방의 활성 적 0.
- 이 형태는 3×3이든 후속 DAG 생성기든 동일해야 한다. UI는 방 좌표를 모른다.

### 2.2 맵 화면 (`playtest/stage_map_view.gd`)

- 3×3 노드와 발견된 연결을 표시. `reachable` 노드만 터치 가능.
- 터치 → 세션 `enter_room(room_id)` → 기존 `room_transition_rules`로 파티를 해당 방 입구에 배치
  → 전투방이면 기존 배치 단계, 비전투방이면 방 진입 후 즉시 탐색 가능.
- 통로 걷기 입력과 방 경계 슬라이드 연출은 제거한다. 방 안 이동은 8×8 전투 규칙만 존재.
- 방 클리어(적 전멸) 또는 비전투방에서 "나가기" → 맵으로 복귀. 방 상태(시체·아이템·지형)는 유지.
- 버튼: `야영`(4절 조건 충족 시), `거점으로 귀환`(원정 포기).

### 2.3 도주·추격·포기

- 도주: 브랜치 규칙 유지 — 활동 파티원이 출구 중심 체비쇼프 2칸 이내에 집결하면 이탈.
- 도주 비용: 도주 *시도*(출구 요청) 시 전원 스트레스 **+120**. 실패해도 비용은 남는다.
- 브랜치 규칙상 파티 전원이 행동 가능해야 도주할 수 있다(`room_party_cannot_move`). 행동 불능(DOWNED) 동료가 있으면 도주 불가 — 구하거나 잃을 때까지 남는다. 낙오 규칙은 없다.
- 추격 유지: 도주 후 진입한 방에서 경로 거리 2 이내 추격 가능한 적 최대 2마리가 다음 라운드에 뒤 출구로 등장.
- 보스방·계단방 보스 전투는 도주 불가.
- 원정 포기: 맵 화면에서 전투 중이 아닐 때. 전리품·XP 유지, 전원 스트레스 **+200**. 층 상태는 방문 기록·방 전투 상태를 초기화한다(1단계). 새 시드로 층을 완전 재생성하는 것은 거점 계획(Plan C)에서 다룬다.
- 계단방 → 2층. 2층 계단 = 원정 성공 귀환. 2층은 기존 생성 유지(저작은 후속).

## 3. 스트레스·붕괴·각성

기존 `party_morale_model`(0~1000, 안정<300<긴장<600<불안<850 공황, 전염 4칸, HEXACO 저항)을 그대로 쓴다. 추가는 두 가지.

### 3.1 판정 이벤트

- 스트레스가 **처음** `PANIC_ENTER`(850)에 닿는 순간 1회 판정. 원정당 인물별 1회.
- 각성 확률 = 기본 25% + (50 − E)/4 + (C − 50)/8 + (H − 50)/8, 5~60%로 클램프. HEXACO 0~100 척도.
- 각성: 스트레스 300으로 리셋, 이번 전투 동안 명중 +10%·저항 +10%, 매 라운드 인접(체비쇼프 1) 아군 스트레스 −50.
- 실패(붕괴): 기존 `PANIC` 모드 진입(이미 구현된 이기적 행동 AI). 해제는 기존 650 규칙.
- 판정은 world RNG를 사용해 저장·재현이 일치해야 한다.

### 3.2 HEXACO 이동 (기벽 대체)

- 붕괴 1회: E +2, A −1. 각성 1회: E −2, C +1.
- 원정당 축별 이동 상한 ±10. 값은 0~100 클램프.
- 원정 결과 화면에 "성격이 변했다" 항목으로 표시.

### 3.3 스트레스 소스

- 기존: 피해, 동료 부상·사망 목격, 적 사기, 굶주림.
- 추가: 도주(2.3), 포기(2.3).
- 어둠 스트레스(`darkness_stress_rules`)는 방 구조에서 **끈다**(횃불 시스템 미사용).
- 거점 복귀 시 자동 회복 없음. 200 초과분은 숙소 휴식으로만 감소(5절).

## 4. 야영

- 조건: 휴식방(`SAFE`) 또는 클리어한 전투방. 층당 최대 **2회**(카운터는 `nine_room_floor_state.care`에 저장).
- 비용: 브랜치 식량 계약 그대로 — 휴식 1회당 파티 고정 식량. 부족하면 불가.
- 효과: 기존 개인별 자연회복 × 휴식 배율(HP), 부상 회복 진행, **스트레스 −250**.
- 상호작용 1회: 파티 내 HEXACO 관계값으로 사건 1개 선택.
  - 위로: 둘 다 스트레스 −100, 관계 +. (bond 높은 쌍 우선)
  - 다툼: 둘 다 +60, 관계 −. (trust 낮은 쌍 우선)
  - 이야기: 전원 −40. (해당 쌍 없을 때 기본)
  - `party_emotion_model`의 bond/trust와 `TOWN_REST_REDUCTION` 재사용.
- 야영 중 습격은 없다(후속).

## 5. 거점 로스터

- 기존 `base_settlement_rules`(16×16, 6건물) 재사용. 건물 의미:
  - 숙소 LODGE: 휴식 배정 정원 4, 원정 1회 경과당 스트레스 −300.
  - 진료소 CLINIC: 부상·부위 손상 치료.
  - 대장간 ARMORY: 장비 교체.
  - 시장 MARKET: 식량·소모품 구매.
  - 원정문 GATE: 편성 4명·출발.
  - 창고 STORAGE: 공유 가방(`party_bag_rules`).
- 로스터 최대 **8명**. 거점 대기 = `DORMANT`. 원정 편성 = `DEPLOYED`/`GROUPED`. 사망 = `DEFEATED`, 영구 상실, 묘비 목록에 기록.
- 신규 영웅: 원정 귀환마다 후보 2명 도착(시드 결정적: 종족·HEXACO·시작 스킬 1·시작 장비). 한도 초과 시 해고 필요.
- 성장·이능·숙련·장비는 영웅별 개별 귀속(브랜치의 `party_growth_rules`·`PartyMemberState` 그대로).
- 프로토타입에서 **끄는 것**: 거점 자원(목재·석재·약초)·건설. 건물 6개 완공 상태로 시작.

## 6. UI

- 흐름: 거점(원정문 편성) → 맵 → 방(배치 → 전투) → 맵 → … → 귀환 결과 → 거점.
- 재사용: 8×8 전장 UI 전부(`stage_context_bar`, `stage_deployment_view`, `tactical_board_*`, `stage_portrait`), 거점 뷰(`base_settlement_view`).
- 신규: `stage_map_view`, `camp_panel`(야영 결과·상호작용 로그), `expedition_result_panel`(전리품·XP·성격 변화·사망자), 거점 `roster_panel`(편성·해고·숙소 배정).
- 스트레스 밴드는 기존 초상화 표시. 각성/붕괴는 전투 로그 + 초상화 아이콘.
- 모바일 360×800 우선, 44px 터치 규칙 유지.

## 7. 방(스테이지) 저작 파이프라인

### 7.1 스키마 (`data/content/stages/f1.json`)

브랜치의 `first_floor_stages.json`을 확장한다. 유지: `id, name, role, biome, hint, rows(8×8), loot`. 추가:

| 필드 | 내용 | 프로토타입 |
|---|---|---|
| `entries` | 입구별 배치 후보 칸 `{portal_dir: [[x,y],...]}` | 구현 |
| `enemies` | `[{cell, kind, role, wave}]`, `enemy_cells` 대체. `role ∈ 돌격/궁수/방패/지원`, `wave` 0=초기 | 구현 |
| `reinforcements` | `{interval_rounds, cap, spawn_edges}` 방별 지정 (현재 전역 7라운드 → 방별) | 구현 |
| `objective` | `ELIMINATE \| SURVIVE{rounds} \| REACH{cell} \| PROTECT{cell}` | ELIMINATE·SURVIVE만 구현, 나머지 스키마 예약 |
| `hazards` | `[{cell, type}]` | 얕은 물만, 나머지 예약 |
| `design` | `{concept, intended_solution, counterplay, failure_mode, difficulty}` — 실행에 안 쓰임, 리뷰 기준 | 구현(검증만) |

### 7.2 방 설계 원칙 (방마다 검토하는 체크리스트)

1. 한 문장 콘셉트가 있다.
2. 의도한 해법 1개 + 다른 유효한 해법 1개 이상.
3. 입구에서 첫 턴에 보이는 정보만으로 위협을 읽을 수 있다(적 역할이 실루엣·위치로 드러남).
4. 입구 농성이 이득이 아니다 — 증원 또는 `SURVIVE`로 막는다.
5. 도주 출구가 계산에 들어간다 — 물러날 때의 손해가 방마다 다르다.
6. 이동 1~3칸·공격 1~3회 규칙에서 2~3라운드 안에 결정적 선택이 나온다.
7. 층 안에서 난이도 곡선이 있고 안전방·전리품방이 리듬을 끊는다.

### 7.3 층 설계 문서 (`docs/stages/f1.ko.md`)

3×3 표로 방 배치, 각 방의 콘셉트·해법·역할, 예상 경로별 난이도 곡선, 야영 권장 지점. **코드 변경 전에 이 문서를 먼저 쓰고 승인받는다.**

### 7.4 도구

- `tools/stage_lab.tscn`: 방 id를 지정해 거점·맵 없이 배치 단계부터 시작. 방 반복 테스트용.
- `tools/stage_probe.gd`(헤드리스): 방 id + 시드 N개로 단순 정책(돌격/거리 유지) 파티를 돌려 평균 라운드·피해·승률 출력. 농성 이득·난이도를 숫자로.
- `docs/art/handcrafted-stages/preview.html`을 확장 JSON에 맞게 갱신.

### 7.5 프로토타입 범위

1층 9방을 새 스키마로 **다시 설계**한다(현재 9방은 적 배치가 전부 `[5,2],[5,5],[2,5]`로 동일). 2층은 생성 유지.

## 8. 테스트·검증

- 기준선: 1절의 6종 통과.
- 신규 acceptance:
  - `stage_map_acceptance`: 모델 변환, 도달 가능성, 진입, 클리어 복귀, 저장 재현.
  - `retreat_stress_acceptance`: 도주 스트레스, 낙오 가산, 추격 등장, 보스방 불가.
  - `stress_resolve_acceptance`: 850 판정 1회, 각성 효과, HEXACO 이동 상한, 시드 결정론.
  - `camp_acceptance`: 층당 2회, 식량 부족, 상호작용 3종 선택 규칙.
  - `roster_acceptance`: 8명 한도, DORMANT 편성, 사망 영구, 후보 도착, 저장.
  - `abandon_acceptance`: 포기 시 전리품 유지, 층 폐기, 스트레스.
  - `stage_schema_acceptance`: 확장 JSON 검증, `design` 필드 필수, 9방 로드.
- 균형 진단(비필수): `first_floor_solo_balance_probe`를 4인 파티로 확장, 시드 20개 원정의 생존율·붕괴 횟수 CSV.

## 9. 완료 기준

거점에서 4명 편성 → 1층 9방 노드 맵 완주 또는 도주·포기 → 거점 귀환 → 숙소 휴식 → 재출발까지 한 사이클이 모바일 웹 빌드에서 돌아간다. 수치는 전부 설정 파일에 두고 플레이 후 조정한다.

## 10. 범위 밖 (후속)

- StS식 DAG 노드 맵 생성기 (StageMapModel 형태는 유지)
- 2층 이상 수제 저작, `REACH`/`PROTECT` 목표, 함정 hazard
- 야영 습격, 거점 건설·자원, 스팀 클라우드·리더보드
- 롤백 이후 커밋의 cherry-pick
