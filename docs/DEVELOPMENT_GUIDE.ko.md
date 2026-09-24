# 개발 가이드

이 문서는 사람과 에이전트(Claude·Codex) 모두를 위한 규칙이다. 새 기능을 넣거나 고칠 때 이 틀을 지킨다. 현재 시스템의 사실은 `docs/systems-overview.ko.md`, 주문은 `docs/spells.ko.md`, 설계 근거는 `docs/superpowers/specs/`, 밸런스 기록은 `docs/balance/`에 있다.

## 1. 코드는 도메인 폴더에 산다

```
expedition/
  run/          Run 상태와 단계: session.gd(상태·조회·행동·피해만) + camp/descent/orders/arena_test/run_result/autobattle(호환)
  time/         scheduler.gd — tick 스케줄러
  combat/       combat_stats.gd(실효값) · combat_rules.gd(명중·피해) · statuses.gd(상태) · passives.gd
  spells/       spells.gd(원시 8개, 시전) · summons.gd
  actors/       monster_ai · boss_ai · npc_roster · npc_ai · npc_modes · npc_recruit · floor_tactics_adapter(레거시)
  ai/           동료 판단: tactical_action_selector · stances · utility · lookahead · parts_candidates · tactic_rules · knobs
  items/        abilities(파츠) · gear · curios · inventory_slot
  progression/  mastery · mastery_effects · growth(호환)
  level/        floor_generator · floor_templates · continuous_floor · encounter_builder · exploration_navigation
  ui/           main.gd(라우팅·위젯 헬퍼만) · screens/*.gd(화면별 빌더) · board · battle_hud · map_view · 연출
  art/          코드 텍스처·타일·아이콘
  sim/          시뮬 러너·아레나·봇
  legacy/       옛 코드(참조만)
sim/            공용 커널: combat_kernel(스케줄·시야) · turn_engine(굴림·경로) · party_memory_state · hexaco_profile
data/content/   모든 표(JSON): combat · mastery · tactics_profiles · floor_* · exploration_curios · balance_experiments
tests/          스위트 1파일 1주제, CI 목록은 .github/workflows/deploy-pages.yml
docs/           설계(specs) · 계획(plans) · 리뷰(reviews) · 밸런스 · 개요
```

새 파일을 만들 때 "이건 무엇인가"로 폴더를 고른다(기능 이름으로 폴더를 만들지 않는다). 평면 `expedition/*.gd`는 두지 않는다. 스크립트를 옮길 때는 `.gd.uid`를 같이 `git mv`하고 `res://` 경로를 전부 갱신한 뒤 임포트 검사로 확인한다.

## 2. 모듈은 `static func(s, …)`, 세션은 위임

- 게임 로직은 세션 인스턴스를 첫 인자로 받는 정적 함수 모듈로 쓴다(`Camp.camp(s)`, `Spells.cast(s, caster, id, target)`). 상태는 `Session`이 들고, 동사는 모듈에 있다.
- 테스트·UI가 부르는 공개 API는 `Session`(또는 `main`)의 한 줄 위임으로 유지한다. 시그니처를 바꾸면 호출처 전부와 테스트를 같은 커밋에서 고친다.
- 모듈은 `Session`을 preload하지 않는다(순환 금지). 필요한 것은 `s.`로 받는다.
- 화면은 `ui/screens/<screen>.gd`의 `static func build(ui, …)`. 노드 이름은 계약이다(테스트가 `find_child`로 찾는다) — 바꾸면 테스트도 같이.

## 3. 데이터가 규범, 코드는 원시

- 수치·목록은 `data/content/*.json`에 둔다. 코드는 그 표를 읽는 **원시 연산**만 구현한다(주문 50개 = 원시 8개 + 50행; 태세 가중치 = `tactics_profiles.json`; 무기·방어구·종족·kit·책·소환수 = `combat.json`).
- 새 콘텐츠를 넣는 순서: 표에 행 추가 → 필요하면 원시 하나 추가 → 데이터 형태 검사(`tests/spellbooks.gd`의 shape 검사처럼) → 효과 검사 1개.
- 이름·설명은 데이터의 `name`/`note`에 두고 문서(`docs/spells.ko.md` 등)는 데이터에서 정리한다. 코드에 한글 문자열을 흩뿌리지 않는다(로그 메시지는 예외).

## 4. 결정론

- 모든 굴림은 `Hexaco.sample(seed, lane, name, modulus)` 또는 그것을 감싼 `CombatRules.roll`. `randi()`·시드 없는 `RandomNumberGenerator`는 금지. lane에는 시간(`s.time`)·행동 번호(`turn_serial`)·액터 id·깊이처럼 "그 순간을 유일하게 만드는 값"을 넣는다.
- 같은 시드·같은 입력은 같은 로그를 내야 한다. 새 시스템에는 "두 세션을 같은 입력으로 돌려 로그 비교" 검사를 하나 둔다.

## 5. 시간의 단위

- 기준 100 tick = 주인공 행동 1회. 무기·지형·상태가 비용을 바꾼다(`Session.action_cost`). 동료·NPC·몬스터는 `ready_at`으로 스케줄러가 돌린다.
- 지속 시간은 tick으로 적는다(3턴 = 300). "라운드"라는 말은 문서에서 "구간(주인공 행동 사이)"으로 쓴다. 옛 라운드 경로(`run/autobattle.gd`, `manual_mode == false`)는 호환용으로 남아 있을 뿐 새 기능은 그 경로에 넣지 않는다.

## 6. 전투 AI를 건드릴 때

- `ai/` 폴더(태세·효용·룩어헤드·파츠 후보·규칙·노브)와 `tactics_profiles.json`은 **계약 테스트가 지킨다**: `tests/stances.gd`·`utility.gd`·`companion_tactics.gd`·`protect.gd`·`skill_rule_conditions.gd`. 검사 수를 줄이는 변경은 하지 않는다.
- 가중치를 바꾸면 `docs/balance/utility-tuning.md`에 before/after와 이유를 적고 게이트(`stance_gate`, `solo_balance`, `ranged_probe`)를 다시 잰다.
- 판단은 "현재 세션 스냅샷 + 예고(`resolve_at`)"만 읽는다. 라운드 번호·시간을 직접 읽는 곳은 lane뿐이어야 한다.
- 동료·NPC·소환수는 같은 선택기를 탄다. 편 판정은 `s.friends()`/`s.side_of()`/`s.hostiles_of()`를 쓰고, `enemy` 플래그를 직접 비교하지 않는다.

## 7. 테스트와 CI

- 스위트는 `tests/<주제>.gd` 하나, 머리 주석 한 줄, `check(ok, reason)`·`quit(1 if failures)` 패턴, 마지막에 `"<이름>: %d checks, %d failures"`를 찍는다(수를 찍어야 이주 표를 만들 수 있다).
- 새 스위트는 `.github/workflows/deploy-pages.yml`의 `for suite in …` 목록에 넣는다. CI는 `SCRIPT ERROR:`/`^ERROR:` 한 줄이면 실패다(RID 누수 ERROR 포함 — 씬 테스트는 만든 노드를 `queue_free()`하고 `await process_frame`).
- 계약 스위트의 검사 수는 줄이지 않는다. 지운 기능의 검사를 없앨 때는 같은 파일에 새 흐름 검사를 같은 수 이상 넣고 before/after 표를 `docs/balance/`의 해당 문서에 적는다.
- 게이트는 합격선이 아니라 기준선일 수 있다(전투 수학이 바뀐 직후). 어느 쪽인지 문서에 명시한다.
- 헤드리스만: `godot --headless --path . --script res://tests/<name>.gd`, 임포트 검사 `godot --headless --path . --editor --import --quit`. **창을 띄우지 않는다.**

## 8. 작업 흐름

1. **스펙** `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`: 결정 사항 번호 목록 → 규칙·수치 → 검증 항목 → 범위 밖. 사용자 승인 뒤에만 계획으로.
2. **계획** `docs/superpowers/plans/…`: Task 단위(테스트 먼저 → 구현 → 실행 → 커밋), 전역 제약, 파일 구조 표, 자기 검토.
3. **구현**: Task마다 구현자 1명 + 리뷰 1명(스펙 준수 → 정확성 → 품질), 수정 라운드는 같은 구현자, 마지막에 브랜치 전체 리뷰. 판정은 원장(`.superpowers/sdd/<plan>/progress.md`)에 `Ruling: 무엇 — 왜 — 틀리면 비용`으로 남긴다.
4. **커밋**: `jinha1226 <jinha1226@gmail.com>`, 트레일러 `Co-Authored-By: …`. 메시지는 `feat|fix|refactor|test|docs(범위): 한 줄`. Task = 커밋 하나. 순수 이동/분리(리팩터링)는 동작 변경과 섞지 않는다.
5. **푸시 전**: 임포트 0 오류 + 전체 CI 통과 + `git fetch` 후 fast-forward 확인. 메인이 움직였으면 리베이스하고 겹친 스위트를 다시 돌린다.
6. **병렬 작업(Claude·Codex)**: 시작 전에 `git pull`. 같은 파일을 동시에 고치지 않도록 소유 파일을 나눈다(계획의 "파일 구조" 표가 그 경계). 스펙·계획을 구현 중에 고치려면 사용자 판정을 먼저 받는다 — 구현에 맞춰 규범 문서를 바꾸지 않는다.

## 9. 새 것을 넣는 방법 (요약)

| 넣을 것 | 어디에 | 검사 |
| --- | --- | --- |
| 주문 | `combat.json.spells` 행(+`book`), 필요 시 `spells/spells.gd` 원시 | `tests/spellbooks.gd` shape + 효과 1개 |
| 상태 | `combat/statuses.gd`(부여·만료·tick), 읽는 곳은 `combat_stats/rules`·`act_as` | `spellbooks` 또는 `model_b_combat` |
| 파츠 | `items/abilities.gd DEFINITIONS` + 패시브 `combat/passives.gd` | `tests/parts.gd` |
| 몬스터 | `floor_monsters.json` 행(`speed/ac/ev/res`), 역할은 `actors/monster_ai.gd` | `monster_roles`, `encounter_builder` |
| 층 템플릿·테마 | `floor_templates.json`, `floor_themes.json` | `floor_generator`(시드 0~99) |
| 화면 | `ui/screens/<screen>.gd` + `ui/main.gd` 위임 + 노드 이름 | `ui_smoke`, `mobile_hud`(터치 44px·390px 폭) |
| 동료 행동 | 후보는 `ai/stances.gd`, 가중치는 `tactics_profiles.json` | `stances`·`utility` 계약 유지 |
| NPC 행동 | `actors/npc_modes.gd` 표 + `npc_ai.gd` | `npc_behaviour` |
| 성격·기억 | `sim/hexaco_profile.gd`, `sim/party_memory_state.gd KINDS` | `recruit`, `stances` |
| 밸런스 수치 | 표만; 근거는 `docs/balance/<주제>.md` | 게이트 재측정 |

## 10. 하지 않는 것

- Godot 창을 띄우는 검증. 그림 생성(아트는 AI 생성 자산을 사람이 넣는다).
- `/mnt/d/SS/new`(코덱스 작업 트리)와 부모 저장소 `/mnt/d/SS`의 직접 수정 — 워크트리에서 작업하고 메인으로 푸시한다.
- 리팩터링 중 버그 수정(적어 두고 따로 고친다), 테스트를 지워서 통과시키기, 스펙 개정 없이 규칙 바꾸기.
