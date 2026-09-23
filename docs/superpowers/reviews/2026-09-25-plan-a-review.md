# Plan A(하강 Run) 리뷰 — feat/descent-run-plan-a f33d810

검토 대상: `3481360..f33d810` (106 files, +3320/−5066). 검토자: Claude(리뷰 에이전트 + 컨트롤러 확인). 브랜치 CI: 34/34 통과, 임포트 0 오류. 계약 스위트 수치 유지(stances 113 · utility 154 · autobattle 108 · parts 338 · skill_rule_conditions 962). 새 스위트 run_start/camping/floor_descent/boss_floor/curios 통과. 솔로 밸런스 3/8(기준선 ≥ 3/8에 정확히 걸침, 지표명이 wins → descents로 바뀜).

## 판정: 수정 후 병합 가능

Task 1~7이 전부 구현됐고, 지운 것들(`floor_mode`·빛·횃불·자금·유물·방 모드·보스 시련·`expedition_number`·`restore_snapshot`)의 잔재가 없다. 계획과 스펙이 다른 곳은 스펙을 따랐다(EXPLORE 단계, 주인공 사망 = DEFEAT, 부상 시스템 제거). 막는 것은 설계가 아니라 제약 위반과 UI 회귀다.

## 반드시 고칠 것 (병합 전)

1. **계약 스위트 검사 수 감소.** 전역 제약("삭제 스위트 7개 외에는 검사 수를 줄이지 않는다; 지운 check만큼 새 흐름 검사를 추가")이 6개 파일에서 깨졌다: `solo_floor` 81→22, `mobile_hud` 53→26, `integration` 46→21, `companion_tactics` 98→82, `curios` 21→11, `solo_balance` 11→6, `enemy_turns` 11→10. 지운 것 상당수가 삭제 기능과 무관하다(뷰포트 맞춤, 44px 터치 타깃, 미니맵 가시성, 시야 정지, 대각선 코너, 토스트, 세로 화면 레이아웃). 복구하거나, 정당한 사유와 함께 before/after 표를 `docs/balance/run-gates.md`에 넣을 것.
2. **짐승 식량 드롭 테스트 없음**(스펙 §2.1, 계획의 40시드 검사). `curios` 스위트의 "거리 초과 / 주변에 적 있음 / 도구 표 삭제" 검사도 사라졌다.
3. **`encounter_builder.gd` 변경 분리.** 무리 채우기 폴백을 재귀 탐색으로 바꾸고 깊이 6 이상은 카탈로그를 재사용하게 한 것은 Plan B 소유 파일이고, 모든 깊이의 조우 구성을 바꿔 Task 7이 잰 게이트 수치를 움직인다. 별도 커밋으로 떼거나 Plan B 쪽으로 넘길 것. (고침 자체는 타당하다.)
4. **기록되지 않은 밸런스 변경 두 가지**를 `run-gates.md`에 명시할 것: 솔로 AP가 2 → 1로(`action_budget`이 `party.size() == 1`이면 `solo_actions`), `theme_for()`가 `monsters.max_members`를 `min(4, 2 + depth/3)`로 키움(스펙 §4.1은 예산 배율만).

## 고쳐야 하지만 병합은 막지 않음

5. `main.gd refresh()`가 매번 보드·미니맵을 `queue_free()` 후 재생성한다. 타격 이펙트 연속성 블록(`elapsed/impact_elapsed/reset_effects`)이 사라져 플래시·흔들림이 끊기고, 80×80 미니맵이 매 갱신 전부 다시 그려진다(모바일 성능).
6. 멤버 카드가 텍스트 버튼 하나로 격하됐다. 초상화, 태세·상태·마지막 행동 캡션, 선택 멤버 금테, 사망 멤버 회색, ⚠ 배지가 없어졌다. 스펙 §6은 기존 카드 유지.
7. 도달 불가 UI 코드 잔존: `show_party_tactics`(버튼 없음 → 집중/정지/추적 명령 접근 불가), `show_orders`(“원정 · 귀환” 버튼), `choose_skill`, `open_management`, `board.draw_movement_previews()`가 `pass`, `const PARTY_SIZE := 1` 미사용.
8. 스펙에 없는 다섯 번째 단계 `"IDLE"`과 `simulation_arena` 플래그 — 스펙 §1.1에 한 줄 추가하거나 이름을 정리.

## 사소한 것

9. 기계적 치환 잔재: `board.gd`의 `return true and …`, `if actor.enemy and true:`(2곳), `main.gd run_action`의 `is_processing() and true and …`, `floor_generator.validate()`의 `(3 if boss else 3)`.
10. `session.act_as`의 인라인 `preload("res://expedition/boss_ai.gd")` → 파일 상수로.
11. `floor_templates.json`·`floor_themes.json`·`stance-gates.json`을 통째로 재포맷해 실제 변경이 묻힌다.
12. `tests/map_fixture.gd` 삭제는 승인 목록 밖(참조 없어 무해).
13. 새 스위트가 `"%d failures"`만 찍고 `%d checks`를 안 찍어 이주 표를 만들 수 없다.

## Plan B 소유 파일 변경 판정

| 파일 | 변경 | 판정 |
| --- | --- | --- |
| `stances.gd` | `mistaken()`의 `floor_mode` 가드 삭제, 시드 lane `expedition_number` → `depth` | 필요·수용(Plan B 인계 목록 항목). 아레나 세션에서도 실수가 굴러가게 됨 — 게이트 수치가 흡수. |
| `lookahead.gd`, `tactic_rules.gd` | `bonus := 0` 두 줄 | 허용 범위 그대로. |
| `parts_candidates.gd` | 보스 물웅덩이 조건을 액터 필드로 | 최소·불가피. |
| `abilities.gd` | 어둠 보정 삭제, 밀치기 인터럽트 분기 순서 | 필요, 동작 보존. |
| `monster_ai.gd` | 고정 시야, 보스 위임 | 계획에 명시. |
| `encounter_builder.gd` | 폴백 재귀 탐색 + 깊이 6 클램프 | **범위 밖** — 위 1~4의 3번. |

## 메인(Plan B, acef54d)과의 병합 계획

충돌 10개 파일. 원칙: 구조는 Plan A가 이기고, Plan B의 NPC 훅을 그 위에 다시 얹는다.

| 파일 | 해결 |
| --- | --- |
| `session.gd` | Plan A 본문 채택. 다시 얹을 것: 필드 `npcs/roster/noise/pending_offer`, `friends()/wanderer()/party_enemies()`, `end_round` 끝(`floor_state.observe` 직후)의 NPC 훅(sense 전부 → `noise.clear()` → 깨어 있는 NPC turn), `damage()`의 NPC 사망 분기(낯선 이 +5/+10, 동료는 ALLY_LOST+downed), 영입 위임(`aid/propose/offer/answer_offer/recruit/companion_rows`), `remember_plain`과 SOCIAL_KINDS 예외, `actor_by_id`/`movement_cells`의 NPC id 해석, `SUPPLY`·`stress()`의 npc 예외. Plan B 코드의 `phase == "BATTLE"` 검사는 EXPLORE가 안전 단계가 됐으므로 `phase in ["EXPLORE","BATTLE"]`로. |
| `continuous_floor.gd` | Plan A 채택. `apply()`에서 `BossAI.spawn` 뒤·`observe` 앞에 `NpcRoster.place` 호출은 `depart()/descend()`에 두고, `threats()`(관찰자 hoist)·`party_threats()`·`mint_enemy()`를 다시 얹는다. `safe()`는 `party_threats` 기준 유지. |
| `npc_roster.gd`(메인) | shim 두 개 삭제: `depth()` → `s.depth`, `npc_rooms()` → `layout.npc_rooms`(보스 층 `[]` 그대로). `descend()`에 `NpcRoster.place(self)`. `remember_plain/remember_important` 키와 `Stances.mistaken` lane은 Plan A가 이미 `depth`로 바꿈. |
| `main.gd` | Plan A 채택. `on_cell`의 시야 블록 맨 앞에 NPC 탭 분기(인접 → `show_npc`, `wanderer` 가드), `refresh()`에 `update_offer_popup()`, 결과 카드에 `companion_history()`(`Session.companion_rows`) 재삽입. `navigation_tick`/`exploration_navigation`의 정지 조건에 NPC 인접 추가. |
| `board.gd` | Plan A 정리 채택. NPC 토큰·이름표·활동 문구·반투명 그리기와 `wanderer()` 기반 색 분기, 선택 테두리의 인덱스 비교, `movement_previews`의 id 조회를 재적용. |
| `character_ui.gd` | Plan A의 CAMP 게이팅 채택. 기억 라벨 4종과 SOCIAL_KINDS 표시 예외 재적용. Plan B는 `Body/Silhouette`를 쓰지 않으므로 preload 삭제는 그대로. |
| `exploration_navigation.gd` | Plan A의 `phase != "EXPLORE"` 게이트 + Plan B의 `party_enemies()` 사용을 합침. |
| `parts_candidates.gd` | 양쪽 모두 한 줄: Plan A의 보스 조건 + Plan B의 `friends()` 치환. |
| `expedition_objective.gd` | Plan A대로 삭제(Plan B의 수정은 `party_enemies()` 치환뿐). |
| `deploy-pages.yml` | 합집합: Plan A 목록(7개 제거, `run_start camping floor_descent boss_floor` 추가) + Plan B의 `npc_roster npc_sense npc_behaviour recruit`. |
| 스펙 문서 | 양쪽 상태 줄을 합쳐 "Plan A·B 구현됨"으로. |

병합 후 반드시: 임포트 검사, 전체 CI(41+4−7 = 38개), `solo_balance`·`stance_gate`·`ranged_probe` 재측정(NPC 시야 확장과 솔로 AP 변경이 겹친 뒤의 수치).
