# Plan A 결과 — 스테이지 스키마·1층 저작·노드 맵·도주/포기 비용

기준: `79f1f17` → 브랜치 `feat/srpg-stage-campaign` (2026-09-18). 스펙 `docs/superpowers/specs/2026-09-18-srpg-stage-campaign-design.md`, 계획 `docs/superpowers/plans/2026-09-18-plan-a-stage-map-and-authored-rooms.md`.

## 구현된 것

| 커밋 | 내용 |
|---|---|
| `7ab0fd0` | 스테이지 스키마 v2 (`data/content/stages/f1.json`) + 검증 카탈로그 `sim/stage_catalog.gd`, `first_floor_stages.gd`는 호환 shim |
| `00e2f9e` `1b0c537` | 1층 9방 재설계 + 설계 문서 `docs/stages/f1.ko.md` (사용자 승인) |
| `fadb136` `06a4e65` | 생성기가 저작 wave 0 사용, 방별 증원(`interval/cap/spawn_edges`, authored wave 칸), `SURVIVE` 목표·`cleared()`·`retreat_allowed()` |
| `62ad526` | `sim/stage_map_model.gd` — 층 상태 → 노드/간선 |
| `4ed21b3` `16eff10` | `room_transition_system.travel()` 0시간 맵 이동, 세션 `request_room_travel`, 저널 `travel` 재현 |
| `fbf7866` `6800ec6` | 도주 시도 스트레스 +120, `retreat_allowed=false` 방 도주 금지, 원정 포기(+200, 저널 `base ABANDON`, 다음 출발 시 층 진행 초기화) |
| `26614c1` | 맵 오버레이 `playtest/stage_map_view.gd`, 컨텍스트 바 `지도` 버튼, 통로 걷기 입력은 전투 중 도주에만 |
| `f3d806c` | `tools/stage_lab.gd`, `tools/stage_probe.gd` |

수치: `data/content/stage_stress.json` (`retreat_attempt:120`, `abandon:200`), 방별 증원·목표는 `f1.json`.

## 테스트 (2026-09-18, `/root/lw-bench-srpg`, 순차)

| 테스트 | 기준선(`79f1f17`) | 현재 |
|---|---|---|
| stage_counterplay_acceptance | PASS | PASS |
| srpg_party_turns_acceptance | PASS | PASS |
| first_floor_solo_roster | PASS | PASS (저작 wave 0 수 기준으로 갱신) |
| handcrafted_tile_assets_acceptance | PASS | PASS |
| round_combat_scenarios | PASS | PASS |
| first_floor_stages_acceptance | PASS | PASS |
| handcrafted_rooms_acceptance | — | PASS |
| stage_schema_acceptance (신규) | — | PASS |
| stage_objective_acceptance (신규) | — | PASS |
| stage_map_acceptance (신규) | — | PASS |
| retreat_stress_acceptance (신규) | — | PASS |
| abandon_acceptance (신규) | — | PASS |
| stage_context_ui_acceptance | 미실행 (xvfb 없음) | 미실행 |
| stage_map_ui_acceptance (신규) | — | **작성만, 미실행** (X11 필요) |

Web release export: exit 0, 오류 0 (`build/web/index.html` 생성).

## 진단 (stage_probe, 방 7 경비실, 단순 돌격 정책, 시드 1~5)

```
seed,room,outcome,rounds,hp_lost,waves
1,7,cleared,6,104,0
2,7,defeat,5,120,0
3,7,defeat,5,120,0
4,7,defeat,5,120,0
5,7,defeat,4,120,0
```
돌격 정책은 후퇴·우선순위가 없으므로 방 난이도의 판정이 아니라 신호다. 실제 플레이로 확인한다.

## 알려진 한계·후속 (이번 범위 밖)

- 원정 포기 시 층 완전 재생성은 Plan C — 지금은 다음 출발 때 방문·발견·전투 상태만 초기화(적·전리품 유지).
- 2층은 생성 유지, 저작 없음. `REACH`/`PROTECT` 목표·함정 hazard는 스키마만.
- UI 테스트 2종은 X11 환경에서 실행해야 한다. 맵 오버레이는 외부 상태 변화(자동 진행으로 전투 진입)에 자동으로 닫히지 않는다.
- 설계 검토 메모: 감시소·저장터·경비실 세 방의 의도 해법이 "기둥 틈에 둘이 나란히"로 같다. 저장터(6) 재설계 후보.
- 소소한 파킹 항목: SURVIVE 클리어 라운드에 억제된 증원은 한 라운드 뒤로 밀림(간격 전체가 아님); 비전투 출구 요청의 이벤트 실패 시 `request_serial` 누수; `room_retreat_forbidden` 중복 검사; `abandon→room_combat_active` 미검증; `room.entered` 검증기가 `travel` 키를 요구(구 저장은 어차피 생성기 VERSION 8로 무효).
- 사전 존재 버그(미수정): `round_combat_system.confirm`이 사후조건 실패 시 `finish_step()`을 두 번 호출; `run_party_morale_tests`·`run_base_acceptance_tests`는 기준 커밋에서도 실패.
- 저작 힌트 문장이 길어 HUD에서 잘릴 수 있음 — 실기기 확인.

## 다음

Plan B(스트레스 판정·각성·HEXACO 이동, 야영), Plan C(거점 로스터·원정 결과·전체 UI 흐름). 그 전에 실제 플레이로 1층 9방과 맵 흐름을 만져 보고 고칠 것을 정한다.
