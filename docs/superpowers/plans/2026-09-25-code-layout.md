# 코드 정리(도메인 폴더 재배치) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `expedition/`의 평면 50개 파일을 도메인 폴더로 옮기고, `session.gd`(1,442줄)·`main.gd`(1,203줄)를 책임별 모듈로 쪼갠다. **동작 변경 없음** — 파일 이동·함수 이전·preload 경로 갱신만. 47개 스위트가 안전망이다.

**Architecture:** Shattered Pixel Dungeon의 도메인 패키지(actors/items/levels/effects/scenes/ui)와 DCSS의 접두사 도메인(spl-*, mon-*, item-*) 관행을 따른다. 세션에서 이미 `static func(s, …)` 모듈로 나뉜 것은 파일만 옮기고, 세션 안에 남은 야영·하강·장비·주문·오토배틀 API를 같은 꼴의 모듈로 추출한다. 화면은 하나의 `main.gd` 대신 화면별 빌더로. 호환 오토배틀 경로는 `run/autobattle.gd` 한 파일로 격리한다(삭제하지 않는다 — 사용자 결정).

**Tech Stack:** Godot 4.6. 스크립트 이동은 `git mv`(`.gd`와 `.gd.uid`를 함께), preload 경로는 `res://` 절대 경로라 전부 갱신해야 한다. `project.godot`의 `run/main_scene`과 `main.tscn`의 `ext_resource path`도 경로다. 검증은 임포트 검사 + 전체 CI 47개.

**Spec:** `docs/systems-overview.ko.md`(현재 구조), 이 계획의 이동 표가 규범.

## Global Constraints

- **동작 변경 금지.** 함수 본문은 옮기되 고치지 않는다. 검사 수·결과가 전과 같아야 한다(47/47, 계약 수치 동일). 리팩터링 중 발견한 버그는 고치지 말고 보고서에 적는다.
- 한 Task가 끝날 때마다 임포트 검사 0 오류 + 전체 CI 47/47. 중간 상태로 커밋하지 않는다(Task 하나 = 커밋 하나, 이동과 경로 갱신이 한 커밋에).
- `.gd`를 옮길 때 짝인 `.gd.uid`를 같이 옮긴다(`git mv a.gd b/a.gd; git mv a.gd.uid b/a.gd.uid`). 새 파일은 임포트 검사가 `.uid`를 만든다 — 커밋에 포함.
- preload 경로 갱신은 `grep -rn 'res://expedition/<old>' --include=*.gd --include=*.tscn --include=*.godot .`로 **잔존 0**을 확인한다. 테스트·툴(`tools/`)·시뮬(`sim/`)의 경로도 포함.
- `manual_mode` 분기는 손대지 않는다(Task 4에서 오토배틀 경로를 파일로 옮길 때 분기 자체는 유지).
- 커밋은 `jinha1226 <jinha1226@gmail.com>`, 트레일러 `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## 목표 트리

```
expedition/
  run/          session.gd · camp.gd · descent.gd · autobattle.gd · run_result.gd(companion_rows) · arena_test.gd
  time/         scheduler.gd
  combat/       combat_stats.gd · combat_rules.gd · passives.gd
  spells/       spells.gd · summons.gd(spells에서 분리)
  actors/       monster_ai.gd · boss_ai.gd · floor_tactics_adapter.gd · npc_roster.gd · npc_ai.gd · npc_modes.gd · npc_recruit.gd
  ai/           tactical_action_selector.gd · stances.gd · utility.gd · lookahead.gd · parts_candidates.gd · tactic_rules.gd · knobs.gd
  items/        abilities.gd · gear.gd(session에서 분리) · curios.gd · inventory_slot.gd
  progression/  mastery.gd · mastery_effects.gd · growth.gd
  level/        floor_generator.gd · floor_templates.gd · continuous_floor.gd · encounter_builder.gd · exploration_navigation.gd
  ui/           main.gd · main.tscn · screens/{start_screen,floor_hud,camp_screen,result_card,popups,character_folio(=character_ui),arena_setup}.gd · board.gd · battle_hud.gd · map_view.gd · companion_intent_ui.gd · companion_intent_overlay.gd · battle_presentation.gd · battle_actor_visual.gd · body_presentation.gd · body_status_silhouette.gd
  art/          mobile_art.gd · environment_art.gd · floor1_art.gd · ink_torso_art.gd · masonry_tiles.gd · map_icons.gd · mastery_glyph.gd · growth_emblem.gd · radial_light.gd
  sim/          (그대로) encounter_runner.gd · encounter_arena.gd · bot_policy.gd · model_b_runner.gd
  legacy/       (그대로)
```

`sim/`(저장소 루트의 `sim/party_memory_state.gd`, `hexaco_profile.gd`, `combat_kernel.gd`, `turn_engine.gd`)와 `data/content/`, `tests/`는 옮기지 않는다.

## 이동 표 (Task 1~3에서 실행)

| 지금 | 이후 | Task |
| --- | --- | --- |
| `expedition/scheduler.gd` | `expedition/time/scheduler.gd` | 1 |
| `combat_stats.gd`, `combat_rules.gd`, `passives.gd` | `expedition/combat/` | 1 |
| `spells.gd` | `expedition/spells/spells.gd` | 1 |
| `monster_ai.gd`, `boss_ai.gd`, `floor_tactics_adapter.gd`, `npc_roster.gd`, `npc_ai.gd`, `npc_modes.gd`, `npc_recruit.gd` | `expedition/actors/` | 1 |
| `tactical_action_selector.gd`, `stances.gd`, `utility.gd`, `lookahead.gd`, `parts_candidates.gd`, `tactic_rules.gd`, `knobs.gd` | `expedition/ai/` | 1 |
| `abilities.gd`, `curios.gd`, `inventory_slot.gd` | `expedition/items/` | 1 |
| `mastery.gd`, `mastery_effects.gd`, `growth.gd` | `expedition/progression/` | 1 |
| `floor_generator.gd`, `floor_templates.gd`, `continuous_floor.gd`, `encounter_builder.gd`, `exploration_navigation.gd` | `expedition/level/` | 1 |
| `mobile_art.gd`, `environment_art.gd`, `floor1_art.gd`, `ink_torso_art.gd`, `masonry_tiles.gd`, `map_icons.gd`, `mastery_glyph.gd`, `growth_emblem.gd`, `radial_light.gd` | `expedition/art/` | 2 |
| `main.gd`, `main.tscn`, `board.gd`, `battle_hud.gd`, `map_view.gd`, `companion_intent_ui.gd`, `companion_intent_overlay.gd`, `battle_presentation.gd`, `battle_actor_visual.gd`, `body_presentation.gd`, `body_status_silhouette.gd`, `character_ui.gd`, `arena_setup.gd` | `expedition/ui/` (`character_ui.gd` → `ui/screens/character_folio.gd`, `arena_setup.gd` → `ui/screens/arena_setup.gd`) | 2 |
| `session.gd` | `expedition/run/session.gd` | 3 |
| `legacy/*`, `sim/*` | 그대로 | — |

`project.godot`: `run/main_scene="res://expedition/ui/main.tscn"`. `main.tscn`: `path="res://expedition/ui/main.gd"`.

---

### Task 1: 엔진 파일 이동 (time · combat · spells · actors · ai · items · progression · level)

**Files:** 이동 표의 Task 1 행 전부(`.uid` 포함). 갱신: 이 파일들을 preload하는 모든 `.gd`(`expedition/`, `sim/`, `tests/`, `tools/`).

- [ ] **Step 1:** 폴더 생성, `git mv` 로 이동(`.gd` + `.gd.uid`).
- [ ] **Step 2:** 경로 갱신. 스크립트: `for f in <이동 파일들>; do grep -rl "res://expedition/$f" --include=*.gd --include=*.tscn . | xargs sed -i "s#res://expedition/$f#res://expedition/<새폴더>/$f#g"; done` — 파일별로 정확한 새 폴더를 매핑해 실행하고 `grep -rn "res://expedition/\(scheduler\|combat_stats\|…\)\.gd"`로 잔존 0 확인. `load("res://…")` 문자열도 같이(`Session`의 `load("res://expedition/abilities.gd")` 류).
- [ ] **Step 3:** 임포트 검사 0 오류 → 전체 CI 47/47(수치 동일). `.uid` 새로 생긴 것 있으면 `git add`.
- [ ] **Step 4:** 커밋 `refactor(layout): engine scripts into time/combat/spells/actors/ai/items/progression/level`.

### Task 2: UI·아트 파일 이동

**Files:** 이동 표의 Task 2 행, `project.godot`, `main.tscn`. `character_ui.gd`는 `ui/screens/character_folio.gd`로 **이름도** 바꾼다(preload 상수 `CharacterUI`는 유지해도 됨).

- [ ] **Step 1~2:** Task 1과 같은 절차. `main.tscn`의 `ext_resource path`와 `project.godot`의 `main_scene` 갱신. 테스트가 `load("res://expedition/main.tscn")`을 쓰면 갱신(`grep -rn "main.tscn" tests`).
- [ ] **Step 3:** 임포트 + CI 47/47. 씬 테스트(`ui_smoke`, `mobile_hud`, `start_kit`, `arena_mode`, `model_b_*_ui`, `recruit scene`)가 특히 게이트.
- [ ] **Step 4:** 커밋 `refactor(layout): ui and art scripts into ui/ and art/; main scene path`.

### Task 3: `session.gd` 분리 → `run/`

`session.gd`를 `expedition/run/session.gd`로 옮기고, 아래 함수 묶음을 **본문 그대로** `static func(s, …)` 모듈로 뽑는다. 세션에는 얇은 위임(`func camp() -> bool: return Camp.camp(self)`)을 남겨 공개 API(테스트가 부르는 이름)는 바뀌지 않는다.

| 새 파일 | 옮길 함수(현재 줄) |
| --- | --- |
| `run/camp.gd` | `can_camp`(326) `camp`(333) `end_camp`(344) `prepare_spell`(603) `learn_spell`(618) `grant_book`(627) `book_tier`(636) `random_book`(647) |
| `run/descent.gd` | `depart`(284) `stairs_sealed`(350) `descend`(353) `gain_level_xp`(1115) |
| `items/gear.gd` | `gear_slot`(651) `equip_gear`(659) `unequip_gear`(677) `grant_gear`(1124) `equip_part`(1140) `unequip_part`(1153) `grant_part`(365) `grant_supply`(370) `use_supply`(1417) `roll_part`(1100) `grant_test_loadout`(1165) `spend_growth`(1129) `reset_rules`(1133) |
| `run/autobattle.gd` (호환 경로 격리) | `auto_attack`(461) `reservation_choice`(781) `reserve_action`(804) `cancel_reservation`(812) `command_choice`(816) `companion_choice`(840) `companion_intent_snapshot`(852) `_intent_id`(867) `auto_step`(879) `open_battle_conflicts`(921) `end_battle_orders`(957) `remember_round`(962) `auto_stop_reason`(970) `companion_previews`(1005) `end_round`(1365) `action_budget`(386) `solo_rule`(382) `plan_enemies`(1354) `enemy_attack_turn`(1357) `_enemy_attack_turn`(1361) |
| `run/orders.gd` | `set_knob`(1019) `set_stance`(1030) `set_protect`(1038) `set_tactic`(1045) `set_basic_target`(1061) `update_rule`(1066) `reorder_rule`(1075) `can_swap_formation`(443) `swap_formation`(447) |
| `run/arena_test.gd` | `load_arena_presets`(1178) `arena_test`(1190) `arena_contact`(1218) |
| `run/run_result.gd` | `companion_rows`(244) `reset_battle_stats`(183) `member_stats`(198) `note_explain`(932) `note_mistake`(947) |
| `session.gd`에 남김 | 상태·필드, `_init/new_run/make_actor`, 조회(`alive/friends/wanderer/side_of/hostiles_of/dominated/at/tile/inside/is_free/distance/melee_reach/walk_reach/can_step/combat_enemies/party_enemies/in_combat/leader/rally_point/on_floor/npc_clock/npc_cooldown/actor_by_id/protection_recipient/subject_name`), 행동(`act/act_as/action_cost/submit/can_submit/cast/status_blocks/record_action/movement_cells/attack_cells/attack_preview/attack_reach/finish_player_action/_presentation_action`), 피해(`damage/after_damage/enemy_attack_effect/check_battle_end/discharge/conductive/start_battle`), 기억·스트레스(`message/remember_important/remember_plain/stress`), 영입 위임(`aid/propose/recruit/offer/answer_offer` — 이미 `Recruit` 위임) |

- [ ] **Step 1:** 파일 이동 + 경로 갱신(`res://expedition/session.gd` → `res://expedition/run/session.gd`; 48곳).
- [ ] **Step 2:** 모듈 추출. 각 함수는 `func name(...)` → `static func name(s, ...)`로 옮기고 본문의 암묵 `self` 참조를 `s.`로 바꾼다(`party` → `s.party` 등). 세션에는 같은 시그니처의 위임 함수를 남긴다. 상수(`STARTING_PARTS`, `PREPARED_SLOTS`, `ARENA_PRESETS` 등)는 쓰는 모듈로 옮기되 세션에서 참조하던 곳은 `Module.CONST`로.
- [ ] **Step 3:** 임포트 + CI 47/47 + 계약 수치 동일. `session.gd`가 700줄 이하인지 확인(목표 ≤ 650).
- [ ] **Step 4:** 커밋 `refactor(session): camp, descent, gear, orders, arena test, result and the compat auto-battle path move out of session.gd`.

### Task 4: `main.gd` 화면 분리 → `ui/screens/`

`main.gd`는 조립·입력 라우팅·공용 위젯 헬퍼(`label/button/icon_button/gauge/resource_gauge/clear/popup_width/modal/run_action`)만 남기고, 화면 빌더를 `static func build(ui, …)` 모듈로 뽑는다(`arena_setup.gd`·`character_ui.gd`가 이미 이 꼴이다).

| 새 파일 | 옮길 함수 |
| --- | --- |
| `ui/screens/start_screen.gd` | `build_start_screen` `build_kit_picker` `kit_detail` `choose_kit` `new_run` `depart` |
| `ui/screens/floor_hud.gd` | `refresh`의 층 HUD 부분(헤더·로그·멤버 카드·`SpellBar`·`BottomActions`·`build_manual_controls`·`build_stop_banner`) `arm_attack` `show_manual_tactics` `preview_attack` `confirm_attack` `choose_spell` `choose_item` `choose_part` `show_part_actions` `select_actor` |
| `ui/screens/camp_screen.gd` | `build_camp_screen` `show_gear` `show_prepare` `show_learn` `show_stairs` |
| `ui/screens/result_card.gd` | `build_result_card` `companion_history` |
| `ui/screens/popups.gd` | `show_menu` `show_logs` `show_map` `show_curio` `show_enemy_info` `inspect_cell` `show_npc` `npc_personality` `propose_npc` `update_offer_popup` `show_supplies` `show_item_detail` `build_inventory` `inventory_rows` `gear_name` `equip_from_bag` `popup_list` `show_tactics` `open_rule` `build_skill_rules` `change_basic_target` `change_tactic_rule` `tactic_pick` `show_mastery_detail` `show_character` |
| `ui/screens/autobattle_hud.gd` (호환 경로) | `auto_interval` `auto_tick` `toggle_auto` `toggle_speed` `check_stop` `note_stop` `stop_message` `toggle_retreat` `report_battle` `show_battle_report` |
| `main.gd`에 남김 | `_ready` `_process` `_input` `_unhandled_key_input` `refresh`(분기만: IDLE→start, CAMP→camp, DEFEAT→result, floor→floor_hud) `on_cell` `focus_enemy` `navigation_tick` `toggle_explore` `stop_navigation` `popup_open` `run_action` `finish_presentation` `queue_action` `show_arena_setup/start_arena/leave_arena` 위젯 헬퍼 |

- [ ] **Step 1:** 화면별 파일 생성, 함수 본문 이동(`self.` → `ui.`), `main.gd`에 위임 유지(테스트가 `main.new_run()`, `main.on_cell()`, `main.find_child("KitPick")` 등을 부르므로 **노드 이름과 `main`의 공개 메서드 이름은 그대로**).
- [ ] **Step 2:** 임포트 + CI 47/47. `main.gd` ≤ 400줄.
- [ ] **Step 3:** 커밋 `refactor(ui): screens split out of main.gd; main keeps routing and widget helpers`.

### Task 5: 상태·소환 정리(코드 이동만) + 문서

- `spells/summons.gd`: `Spells.summon/summon_cells`와 `Scheduler.environment_tick`의 소환 만료 블록을 옮긴다(호출은 그대로).
- `combat/statuses.gd`: `Session.status_blocks`, `Scheduler.environment_tick`의 상태 만료·tick 피해 블록, `Spells.apply_status`를 한 파일로(본문 그대로). `combat_stats/rules`의 상태 읽기는 그대로 둔다(변경 아님).
- 문서: `docs/systems-overview.ko.md`의 파일 경로 갱신, `README`의 구조 절 갱신, `docs/superpowers/specs/*`는 손대지 않는다(역사 문서).
- [ ] 임포트 + CI 47/47 → 커밋 `refactor(combat): statuses and summons in their own files; docs paths`.

### Task 6: 검증·마무리

- [ ] `grep -rn "res://expedition/[a-z_]*\.gd" --include=*.gd --include=*.tscn . | grep -v "res://expedition/\(run\|time\|combat\|spells\|actors\|ai\|items\|progression\|level\|ui\|art\|sim\|legacy\)/"` → 0건.
- [ ] `find expedition -maxdepth 1 -name "*.gd"` → 0건.
- [ ] 임포트 + 전체 CI 47/47, 계약 수치 표(before/after 동일)를 보고서에.
- [ ] 이동 표 최종본을 `docs/systems-overview.ko.md` 부록으로.

## 자기 검토

- 커버리지: 목표 트리의 모든 폴더가 Task 1~4 어딘가에서 채워진다. `legacy/`·`sim/`·`data/`·`tests/`는 의도적으로 제외.
- 이름 일관성: 모듈 상수명은 기존 관행(`const Camp = preload(...)`)을 따르고 세션 공개 API 이름은 불변.
- 위험: (1) preload 경로 누락 → 임포트 검사가 잡는다(SCRIPT ERROR). (2) 세션 함수 추출 시 `self` 암묵 참조 누락 → 각 Task 뒤 47개 스위트. (3) `main.gd` 분리는 클로저(`func(): …`)가 `self`를 잡는 곳이 많아 `ui.` 치환을 꼼꼼히. (4) `.uid` 누락 시 Godot이 새로 만들어 diff가 커진다 — `git mv`로 같이 옮긴다.
