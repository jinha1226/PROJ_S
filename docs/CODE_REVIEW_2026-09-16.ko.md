# 2026-09-16 코드 전체 리뷰와 최적화

`origin/main` `6901e45` 기준. 정적 분석(파일·함수 크기, 참조, 중복)과 실제 제품 세션 프로파일링을
함께 했다. 수치는 Godot 4.6.2 headless, DUO 시나리오, seed 44/20260828, 단일 개발 환경의
wall time이며 모바일 실측이 아니다.

## 규모

| 영역 | 파일 | 줄 |
|---|---:|---:|
| `sim/` | 187 | 36,606 |
| `playtest/` | 127 | 42,218 |
| `tests/` | 327 | 50,896 |
| `game/`, `tools/`, `examples/` | 24 | 2,509 |

가장 큰 파일: `party_playtest_session.gd` 10,491줄, `party_encounter_sandbox.gd` 7,899줄,
`world_state.gd` 7,294줄, `party_grid_view.gd` 4,315줄. 4,280개 함수 중 100줄 초과 50개,
200줄 초과 17개. 200줄 초과는 대부분 스냅샷/히스토리 검증 함수(`_restored_state_error` 838줄,
`_lifecycle_history_error` 484줄)와 세션 `load_session_json` 525줄이다.

## 가장 큰 발견: 개발 환경 I/O

`/mnt/d`(9p drvfs) 위에서 세션 스크립트 로드에 32~39초, 샌드박스 씬 로드에 12~13초가 걸린다.
같은 프로젝트를 WSL ext4(`/root/lw-bench`)로 복사하면 각각 1.6초, 0.85초다. 스크립트 하나만
읽는 빈 실행은 0.18초라 Godot 자체 문제가 아니라 파일 시스템 문제다.

| 항목 | /mnt/d (9p) | ext4 |
|---|---:|---:|
| `party_playtest_session.gd` 로드 | 32,134~38,966 ms | 1,612 ms |
| `party_encounter_sandbox.tscn` 로드 | 12,296~13,196 ms | 846 ms |
| `Session.new(DUO)` | 477 ms | 496 ms |

테스트 한 스위트를 돌릴 때마다 40초 이상을 파일 읽기에 쓰고 있으므로, 저장소를 WSL 파일
시스템으로 옮기거나 Windows 쪽 Godot로 실행하는 것이 어떤 코드 최적화보다 큰 개선이다.

## 런타임 프로파일 (이번에 수정한 것)

`tests/product_step_performance_probe.gd`를 추가했다. 세션 생성, 첫 갱신, 샌드박스 입력 경로
(`_on_explore`)로 12걸음을 재고 `sim/perf_probe.gd` 보고서를 출력한다.

| 항목 | 변경 전 | 변경 후 |
|---|---:|---:|
| `Session.new(DUO)` | 486~510 ms | 312~326 ms |
| 첫 `_refresh` | 33~40 ms | 28 ms |
| 걸음당 명령 처리 | 25.2 ms | 19.4~19.8 ms |
| 걸음당 프레임 2개 | 24.9~25.8 ms | 23.2~23.3 ms |

1. **아이템·무기·카탈로그 레지스트리가 조회마다 행 전체를 재검증했다.** `ItemRegistry.has()`가
   `definition_error()`를 매번 실행했고, 그 안에서 `DefinitionScript.new()`와
   `WeaponRegistry.has()`(역시 재검증)까지 호출했다. 세션 생성 한 번에 `definition()`이
   3,200회 이상 불렸다(아이템 인스턴스·인벤토리 검증 루프). 콘텐츠는 프로세스 수명 동안
   불변이므로 id별 유효성을 memo했다. `definition_error(row)` 자체는 그대로라 잘못된 행을
   넣는 테스트는 영향이 없다.
2. **`party_status()`가 갱신 한 번에 7~9회 호출됐다.** 순수 함수이고 결과를 `duplicate(true)`로
   돌려주므로, `_presentation_visible_cells`와 같은 방식으로 세계·파티 입력(인스턴스 id,
   world_time, step_index, events 수, revision, safe_phase, 접촉·진형·앵커·방향, 식량, 아이템
   revision, 리더 위치, 로스터 presence, 활성 멤버, 원정 주기)을 키로 memo했다.
3. 삭제된 테스트의 고아 `.uid` 두 개를 제거했다.

## 남은 병목 (측정만 하고 수정하지 않음)

- **정적 투영 캐시 재빌드 `party_grid_view._ensure_static_projection_cache`: 걸음당 약 12 ms.**
  195칸 기준 `_static_cell_content` 5.5 ms(캐시 적중률 약 45%. 시야 상태가 바뀐 28칸이 4방향
  이웃까지 무효화해 100칸 이상을 다시 만든다), `_rebuild_torch_cache` 2 ms,
  ground candidates 1.5 ms, `_observed_tile_spec` 1.2 ms. 재빌드를 뺀 순수 `_draw`는 약
  3.2 ms. 다른 세션이 이 파일을 활발히 수정 중이라 손대지 않았다. 후보: 이웃 무효화 대신
  (정제된 행 + 4이웃 정제 행) 해시를 캐시 키로 사용, 횃불·바닥 후보 목록을 칸 루프 안에서
  한 번에 수집.
- **관측 DTO `observe_party_ui` 4~7 ms/회.** `obs.context` 안의 바닥 아이템 행 생성이
  아이템마다 `ActorStatRules.for_entity`, 레지스트리 조회, `duplicate(true)` 여러 번을 한다.
  보이는 아이템이 적어 지금은 0.5 ms 수준.
- **저장 JSON 6.5 MB.** `snapshot.tiles`가 17,664칸 × 약 380바이트로 전체의 99%다. 기본값
  칸도 모든 환경 필드를 쓴다. 제품 샌드박스는 아직 저장하지 않으므로 당장 문제는 아니지만,
  모바일 자동 저장을 붙이기 전에 기본값 생략이나 압축이 필요하다.
- `duplicate(true)` 호출이 `party_playtest_session.gd`에 218곳, `party_grid_view.gd`에 94곳.
  대부분 DTO 경계의 방어적 복사라 정당하지만, 같은 갱신 안에서 같은 DTO를 여러 번 복사하는
  경로(`party_status` 9회, `party_cards` 3회)는 위와 같은 memo로 줄일 수 있다.

## 정리 대상 (판단 필요)

- **참조 없는 스크립트.** 제품·테스트 어디서도 참조되지 않음: `playtest/eight_way_actor_assets.gd`,
  `playtest/frontier_campaign_panel.gd`, `playtest/modular_topdown_assets.gd`,
  `tools/art/measure_keyed_grid.gd`, `tools/capture_low_poly_3d_lab.gd`,
  `tools/capture_modular_topdown.gd`, `tools/art/preview_monster_corpses.gd`,
  `tools/art/preview_part_discovery.gd`. 문서에서만 언급: `sim/npc_memory.gd`,
  `sim/systems/npc_coordinator.gd`(351줄), `examples/*.gd`. `assets/README.md`가 과거 실험
  화면 코드를 의도적으로 유지한다고 적어 두었으므로 삭제하지 않았다.
- **중복 함수.** `_eligible_members(world)`가 `party_memory_model.gd`와 `party_morale_model.gd`에
  완전히 동일하고, `party_relationship_model.gd`(정렬만 다름)와 `party_emotion_model.gd`(마을
  거주자 포함)에 변형이 있다. `_position_from`이 `duel_decision_grid.gd`와
  `playtest_grid_view.gd`에 동일하다.
- **`.uid`/`.import` 미커밋.** import 후 약 150개 `.gd.uid`와 76개 `.import`가 새로 생긴다
  (`assets/generated/topdown_tactical64_v1`, `topdown_walls_doors64_v1`, `docs/art`, `docs/ui`).
  Godot 4.4+는 `.uid`를 커밋하도록 권장한다. 세션마다 다른 uid가 생성되므로 한 체크아웃에서
  한 번에 커밋하는 것이 좋다.
- `sim/world_state.gd:3245`의 유일한 TODO(v4 item event rows).
- `tests/torch_travel_performance_probe.gd`는 횃불이 "폐기된 장비"가 된 뒤 fixture equip에서
  실패한다(측정 불가).

## 검증

ext4 복사본 두 개(변경 전 `origin/main`, 변경 후)에서 같은 스위트를 순차 실행해 FAIL 줄을
비교했다. 결과는 아래 표.

| 스위트 | 변경 전 FAIL 줄 | 변경 후 FAIL 줄 | 차이 |
|---|---:|---:|---|
| run_product_tests | 85 | 85 | 동일 |
| run_item_core_tests | 12 | 12 | 동일 |
| run_world_item_operations_tests | 0 | 0 | 동일 |
| run_weapon_combat_tests | 0 | 0 | 동일 |
| run_phase4_tests | 29 | 29 | 동일 |
| run_party_ai_tests | 1 | 1 | 동일 |
| awareness_contact_regression | 12 | 12 | 동일 |
| single_screen_combat_acceptance | 2 | 2 | 동일 |
| run_party_observation_performance_tests | 1 | 1 | 동일 |
| run_expedition_cycle_tests | 7 | 7 | 동일 |
| run_guild_tutorial_tests | 0 | 0 | 동일 |
| run_party_auto_explore_tests | 0 | 0 | 동일 |
| run_json_content_database_tests | 0 | 0 | 동일 |
| run_party_auto_flow_tests | 0 | 0 | 동일 |
| run_progression_tests | 1 | 1 | 동일 |

FAIL 줄 집합을 스위트별로 diff해 모두 동일함을 확인했다. 빨간 스위트는 전부 `origin/main`
`6901e45`에서 이미 실패하던 것이다. 특히 `awareness_contact_regression`(적이 연 접촉이 NONE,
`settle_contact`가 `deployment_phase_required`)과 `single_screen_combat_acceptance`(원거리 적 탭이
`melee_not_legal`), `test_party_combat_matrix`(승률 0/12)는 이번 변경과 무관하게 main에서
깨져 있으므로 별도 확인이 필요하다.
