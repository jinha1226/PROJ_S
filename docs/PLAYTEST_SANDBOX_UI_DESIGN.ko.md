# Living World Playtest Sandbox UI 설계

## 0. 문서의 역할

이 문서는 `/mnt/d/STARTU/living-world-sim`의 직접 플레이 테스트 화면 구현 계약이다.

목표는 예쁜 최종 게임 UI가 아니다. 새 시스템을 추가할 때마다 다음을 빠르게 눈으로 검증하는 세로형 developer sandbox다.

- 이동 입력이 어떤 시간 비용으로 처리됐는지
- 행동 구간에 어떤 환경 틱이 끼어들었는지
- 선택한 타일이 왜 통과 가능하거나 불가능한지
- 객관적 exposure와 현재 종족의 주관적 위험 점수가 어떻게 다른지
- 사건·snapshot·command journal로 같은 문제를 재현할 수 있는지

UI는 시뮬레이션 규칙을 복제하지 않는다. `PlaytestSession`이 제공하는 detached DTO만 읽고 명령을 제출한다.

## 1. 화면 설계 원칙

1. **맵 우선**: 세로 800px에서도 맵이 화면의 절반 이상을 차지한다.
2. **행동 결과 설명**: 매 입력 뒤 `무슨 행동 / 시간 비용 / 끼어든 틱 / 사건`이 한 화면에 남는다.
3. **객관과 주관 분리**: fire·water·conductivity 같은 원시 exposure와 species risk component를 같은 카드 안에서 다른 열로 보여준다.
4. **전도와 감전 구분**: 전도도가 높아도 persistent 전기 위험이 없으면 `전기 위험 없음`으로 명시한다.
5. **색만 믿지 않음**: 모든 terrain과 상태는 색 + glyph/짧은 문자로 구분한다.
6. **world state와 UI state 분리**: 선택 칸·카메라·열린 패널은 snapshot에 넣지 않는다.
7. **한 입력 한 step**: Timer, `_process`, Tween이 authoritative world를 진행하지 않는다.
8. **빠른 재현**: seed, command 수, save/load, replay journal 접근이 두 번 이하의 조작으로 가능하다.

## 2. 기준 화면과 반응형 범위

기준 viewport는 현재 프로젝트와 같은 `450×800` portrait다.

- 최소 지원 폭: 360
- 기준 폭: 450
- 최대 검증 폭: 540
- touch target 최소 한 변: 44px
- safe-area inset을 root padding에 반영
- 화면이 넓어져도 9×9 cell 수를 늘리지 않고 cell과 여백을 늘림
- 높이가 부족하면 최근 사건 패널을 먼저 접고 맵과 행동 버튼을 보존

월드는 `32×48`, 화면은 플레이어 중심 `9×9` camera window다. 월드 가장자리에서는 camera를 clamp해 가능한 한 9×9를 채운다. 최종 게임의 월드 크기·카메라 정책을 확정하는 UI가 아니다.

## 3. 기본 화면 wireframe

```text
┌──────────────────────────────────────────┐  0
│ HP 100/100  HUMAN     D1 05:02  T230 S2 │
│ Seed 0007                 DEBUG OMNI  ≡  │  58
├──────────────────────────────────────────┤
│                                          │
│     9×9 PLAYER-CENTERED MAP VIEW         │
│                                          │
│       # # # # # # # # #                  │
│       # . . ~ ~ ~ . = #                  │
│       # . @ . , . F = #                  │
│       # . . . . . . = #                  │
│       # # # # # # # # #                  │
│                                          │  472
├──────────────────────────────────────────┤
│ (12,18) SHALLOW WATER                    │
│ 이동 가능 · 130 · SLOW                  │
│ 불 0 / 다음피해 0   물 80 → 위험 60     │
│ 전도 60 / 전기위험 없음   독 0  총 60   │  590
├──────────────────────────────────────────┤
│ 예상: 이동@230 → 환경@300 → 준비@360    │  630
├──────────────────────────────────────────┤
│ [ 이동 ] [ 대기 ] [ 불 ] [ 물 ] [ 방전 ]│  688
├──────────────────────────────────────────┤
│ 최근: +130 이동 (12,18), 환경틱 1회      │
│ #42 T300 combat.fire_damage 20           │
│                       로그 펼치기  ▲     │  800
└──────────────────────────────────────────┘
```

대략적 높이 배분:

| 영역 | 기준 높이 |
|---|---:|
| 상단 HUD | 58 |
| 맵 viewport | 414 |
| 선택·위험 카드 | 118 |
| 예상 timeline strip | 40 |
| action dock | 58 |
| 접힌 recent log | 112 |

정확한 픽셀보다 우선순위와 정보 계층을 지킨다. 작은 화면에서는 recent log를 56px 한 줄로 줄인다.

## 4. 상단 HUD

항상 보여줄 정보:

```text
HP current/max
species display name
calendar projection
world_time (T)
step_index (S)
seed
omniscient debug badge
menu button
```

표시 예:

```text
HP 76/100  HUMAN       D1 05:02  T230 S2
Seed 0007                 DEBUG OMNI  ≡
```

규칙:

- HP는 숫자와 bar를 함께 사용한다.
- HP 30% 이하는 amber, 15% 이하는 red이지만 숫자를 숨기지 않는다.
- `T`와 `S`를 명시해 세계시간과 결정 수를 혼동하지 않게 한다.
- calendar는 표시용 projection이고 authoritative time은 `T`다.
- `DEBUG OMNI`는 현재 화면이 시야/인지 제한 없는 개발용 정보라는 표시다.
- player가 죽으면 HUD 배경을 dark red로 바꾸고 `GAME OVER · 마지막 입력은 정착됨`을 표시한다.

## 5. 9×9 map viewport

### 5.1 렌더링 방식

전체 월드 타일을 Node로 만들지 않는다. 하나의 custom `Control`이 `_draw()`에서 보이는 9×9만 그린다.

- 기준 cell 44px
- grid 실제 크기 396×396
- 남는 영역은 중앙 정렬 padding
- 매 HUD refresh에 session의 `view_visible_cells(radius=4)` DTO를 새로 읽음
- tile/entity authoritative 객체 참조를 보관하지 않음
- `_gui_input(event)`에서 local cell을 world position으로 변환

### 5.2 terrain 표현

색과 glyph를 함께 쓴다.

| terrain | glyph | 기본색 | 의미 |
|---|---|---|---|
| `floor` | `.` | 중간 회색 | 일반 바닥 |
| `stone_floor` | `:` | 푸른 회색 | 돌바닥 |
| `wood_floor` | `=` | 갈색 | 가연성 바닥 |
| `metal` | `+` | 청회색 | 전도성 바닥 |
| `rubble` | `,` | 황갈색 | 느린 이동 |
| `shallow_water` | `~` | 청록 | 정적 물 노출 80 |
| `wall` | `#` | 어두운 남색 | 통과 불가 |
| world 밖 | 공백 | 검정 | 선택 불가 |

### 5.3 상태 overlay 순서

아래에서 위 순서로 그린다.

```text
terrain base
→ wetness blue corner mark / 값
→ fire orange-red fill pulse 없는 정적 overlay / 값
→ corpse x
→ living entity glyph
→ player @
→ traversal hint border
→ selection border
```

- fire는 애니메이션 없이도 세기를 알 수 있게 작은 `F`와 0..100 숫자를 표시한다.
- wetness는 `W` 또는 blue corner bar와 값을 표시한다.
- player `@`는 가장 높은 contrast로 표시한다.
- 선택 칸은 yellow 3px border.
- 현재 actor의 네 cardinal 후보는 thin border:
  - green: 이동 가능
  - red: terrain/occupancy blocked
  - amber: 이동 가능하지만 total risk가 현재 칸보다 큼. 경고일 뿐 금지 아님.
- hazard score가 MOVE legality를 바꾸지 않는다.

### 5.4 camera

- player가 이동할 때 즉시 새 authoritative position을 중심으로 갱신한다.
- 부드러운 보간은 하지 않는다. 시뮬레이션 위치와 시각 위치가 어긋나지 않게 한다.
- player가 죽어도 마지막 위치를 중심으로 유지한다.
- LOAD 후에는 저장된 player tag/ID를 session이 다시 찾아 camera를 맞춘다.

## 6. 선택·위험 카드

선택한 world position에 대해 `DestinationAssessment`와 Exposure DTO를 표시한다.

첫 줄:

```text
(x,y) TERRAIN_NAME
이동 가능 · 130 · SLOW
```

불가능하면:

```text
(x,y) WALL
이동 불가 · 벽
```

두 번째와 세 번째 줄은 객관값과 주관 점수를 분리한다.

```text
객관  불 45  다음틱피해 20    물 80  젖음 12
평가  불 36  물 60            총 위험 96

객관  전도 72  전기위험 0/NONE    독 0
평가  전기 0                   독 0
```

중요:

- `conductivity=72`를 감전 확률로 표현하지 않는다.
- persistent electric risk가 0이면 반드시 `전기위험 없음` 또는 `0/NONE`이라고 쓴다.
- static water exposure와 dynamic wetness를 둘 다 표시하고 combined water exposure도 tooltip/상세에 표시한다.
- source event ID는 기본 카드에는 숨기고 상세 log에서 확인한다.
- total risk는 굵게 표시하되 component를 숨기지 않는다.
- 선택 칸이 현재 player 칸이면 이동 버튼 대신 `현재 위치` 상태를 표시한다.
- 비인접 칸도 inspection은 가능하지만 MOVE button은 disabled다.

## 7. 예상 timeline strip

선택 칸이 유효한 인접 MOVE 목적지면 `session.preview_move(position)` 결과를 표시한다.

```text
예상: 이동@230 → 환경@300 → 준비@360
```

규칙:

- marker kind와 절대시간을 표시한다.
- 한 줄을 넘으면 horizontal scroll 또는 `환경×N` 축약을 사용한다.
- 확률적 화재 확산·예상 피해를 preview하지 않는다.
- preview가 거부되면 `예상 불가: 점유됨`처럼 reason을 표시한다.
- 행동 실행 뒤에는 strip이 실제 timeline으로 잠시 바뀐다.

```text
실제: 이동@230 → 환경@300[#42,#43] → 준비@360
```

- 다음 선택/입력 때 다시 예상 timeline으로 돌아간다.

## 8. action dock

기본 5개 버튼:

```text
[ 이동 ] [ 대기 ] [ 불 ] [ 물 ] [ 방전 ]
```

동작:

- `이동`: 선택 칸으로 `SimCommand.move_to`; valid cardinal destination일 때만 enabled
- `대기`: 표준 WAIT 100, 선택과 무관
- `불`: 선택 칸 IGNITE 70
- `물`: 선택 칸 POUR_WATER 60
- `방전`: 선택 칸 DISCHARGE 40

버튼은 최소 44px 높이, 눌림 상태와 disabled 상태를 색뿐 아니라 opacity/label로 구분한다.

원소 power 조절 UI는 이번 버전에 넣지 않는다. 고정 power는 버튼의 tooltip과 log에 표시한다.

잘못된 행동을 UI에서 모두 막지는 않는다. core가 거부한 결과도 status/log로 보여줘야 회귀를 직접 확인할 수 있다. 단 MOVE처럼 명백한 비인접 selection은 button을 disabled해 기본 사용성을 유지한다.

## 9. 입력 계약

### 마우스·터치

- tile 한 번 누르기: 선택·inspection만 수행
- 선택된 인접 tile을 다시 누르기: MOVE commit
- 또는 선택 후 `이동` 버튼: MOVE commit
- 비인접 tile 두 번 누르기는 이동하지 않음
- UI 버튼을 누른 pointer event가 map까지 전파되지 않음

두 번 누르기 이동은 더블클릭 시간 판정이 아니라 “같은 선택 칸을 다시 누름”이다. 모바일에서도 예측 가능하다.

### 키보드

```text
Arrow / WASD  즉시 cardinal MOVE
Space / .     WAIT
1             선택 칸 IGNITE
2             선택 칸 WATER
3             선택 칸 DISCHARGE
L             log drawer 열기/닫기
Esc           menu 또는 drawer 닫기
```

키 repeat는 OS event를 그대로 여러 step으로 폭주시키지 않게 action press 한 번당 한 command만 제출한다.

## 10. 결과 feedback

모든 command 뒤 화면 아래 recent log 첫 줄에 결과 요약을 남긴다.

성공 예:

```text
이동 (11,18)→(12,18) · +130 · T230→360 · 환경틱 1회
```

거부 예:

```text
거부 · 목적지가 점유됨 · 시간/step 변화 없음
```

사망 예:

```text
이동은 정착됨 · T300 화재 피해 20 · PLAYER 사망
```

reason 표시 매핑은 UI presentation table에서만 한다. core reason string을 바꾸지 않는다.

최소 매핑:

| reason | 사용자 표시 |
|---|---|
| `move_requires_actor` | 이동할 actor가 없음 |
| `actor_not_found` | actor를 찾을 수 없음 |
| `actor_dead` | 사망한 actor는 행동할 수 없음 |
| `move_out_of_bounds` | 월드 경계 밖 |
| `move_not_cardinal_adjacent` | 인접한 네 방향만 이동 가능 |
| `move_terrain_blocked` | 통과할 수 없는 지형 |
| `move_destination_occupied` | 목적지가 점유됨 |
| `schedule_budget_exceeded` | 한 행동의 세계 처리량 한도 초과 |
| `time_overflow` | 세계시간 한도 도달 |

알 수 없는 reason은 숨기지 않고 raw string을 표시한다.

## 11. recent log와 확장 drawer

접힌 상태는 최근 결과 요약과 사건 1~2개만 표시한다.

`로그 펼치기`를 누르면 화면 아래에서 overlay drawer가 올라오며 맵 일부를 덮을 수 있다. authoritative simulation은 멈추거나 진행할 것이 없으므로 별도 pause 상태를 만들지 않는다.

drawer 탭:

### EVENTS

```text
#41 T230 action.move actor=1 pos=(12,18) value=130
#42 T300 combat.fire_damage target=1 value=20 cause=#9
#43 T300 entity.died target=1 cause=#42
```

- event ID, world time, type, actor/target, magnitude, cause를 표시
- 선택 event의 data Dictionary를 pretty JSON으로 펼칠 수 있음

### TIMELINE

- 마지막 실제 step의 marker를 순서대로 표시
- 각 marker의 event IDs 표시
- preview와 actual이 같은지 session이 제공하면 parity badge 표시

### REPLAY

- seed
- species
- command count
- accepted command journal JSON
- `클립보드 복사` 버튼
- 현재 snapshot JSON의 별도 복사는 menu에 둬도 됨

drawer가 열려 있을 때 키보드 MOVE는 막아 accidental step을 방지한다.

## 12. menu sheet

상단 `≡` 버튼은 full-width modal sheet를 연다.

구성:

```text
PLAYTEST SETTINGS

Species
[ HUMAN ] [ AMPHIBIAN ] [ DWARF ]

Seed  [ 0007 ]
[ 같은 seed 리셋 ] [ 새 seed ]

[ SAVE SLOT ] [ LOAD SLOT ]
[ SNAPSHOT JSON 복사 ]

Legend / Controls
DEBUG OMNISCIENT 설명

[ 닫기 ]
```

species 변경은 새 arena reset이다. command journal이 비어 있지 않으면 `현재 실행을 버리고 재시작` 확인을 한 번 받는다. SAVE/LOAD 성공·실패는 sheet와 recent log 양쪽에 표시한다.

`새 seed`는 시스템 시계를 authoritative sim에 넣는다는 뜻이 아니다. UI가 새로운 정수 seed 하나를 선택해 session reset 인자로 넘기며, 선택된 seed를 즉시 표시·기록한다.

## 13. 상태별 화면

### 정상

- MOVE와 원소 버튼 활성 조건을 DTO에서 계산
- selection 기본값은 player 위치
- camera는 player 중심

### command 거부

- world 표시를 추측해 바꾸지 않고 session에서 전부 다시 읽음
- 선택 유지
- reason banner와 no-op 표시

### GAME OVER

- map과 inspection/log/save/load는 유지
- MOVE/WAIT/원소 버튼 disabled
- LOAD/RESET만 강조
- actor.ready marker를 생존 의미로 오해하지 않게 마지막 timeline 유지

### 저장 슬롯 없음/손상

- world를 바꾸지 않음
- `LOAD 실패 · 유효한 v3 snapshot 없음` 표시
- raw parser/script error를 사용자에게 노출하지 않되 log에는 reason 보존

### viewport resize

- current selection/camera 유지
- layout만 재계산
- sim snapshot과 journal 불변

## 14. PlaytestSession UI 계약

UI agent는 core 파일이나 `PlaytestSession`을 수정하지 않는다. 아래와 동등한 public API를 사용하고, 실제 이름 차이는 작은 adapter 메서드로 UI 쪽에서 흡수한다.

```text
reset(seed: int, species_id: String) -> bool
player_id() -> int
player_state() -> detached Dictionary
world_status() -> detached Dictionary

view_visible_cells(radius: int = 4) -> Array[Dictionary]
inspect_destination(position: Vector2i) -> DestinationAssessment | Dictionary
preview_move(position: Vector2i) -> SimActionPreview

commit_move(position: Vector2i) -> SimStepResult
commit_wait() -> SimStepResult
commit_ignite(position: Vector2i) -> SimStepResult
commit_water(position: Vector2i) -> SimStepResult
commit_discharge(position: Vector2i) -> SimStepResult

save_slot() -> Dictionary            # {ok, reason}
load_slot() -> Dictionary
snapshot_json() -> String
command_journal_json() -> String

recent_events(limit: int) -> Array[Dictionary]
last_result_summary() -> Dictionary
```

필요한 DTO 필드가 session에 없으면 UI agent는 core를 우회해 `session.sim.world.tile_at()`을 읽지 않는다. 누락 API를 main agent에게 보고하고 core 담당자가 session에 추가하게 한다.

LOAD 뒤 오래된 player 객체 참조를 유지하지 않는다. session이 `player` tag나 저장된 ID를 다시 찾아 detached player state를 반환해야 한다.

## 15. 파일 소유권

UI 구현 담당이 수정할 수 있는 범위:

```text
playtest/playtest_sandbox.tscn
playtest/playtest_sandbox.gd
playtest/playtest_grid_view.gd
playtest/playtest_theme.gd            # 필요할 때만
project.godot                         # main_scene과 UI input actions
tests/test_playtest_ui.gd
README.md의 Playtest 실행·조작 부분   # core 담당 완료 뒤 충돌 없이
```

수정 금지:

```text
sim/**
playtest/playtest_session.gd
기존 core tests의 의미
snapshot/command/event 규칙
```

UI 때문에 core reason이나 DTO를 임의 변경하지 않는다.

## 16. 구현 세부 지침

- root는 full-rect `Control`.
- container/anchor 기반으로 만들고 절대 좌표는 custom grid draw 안에서만 사용.
- theme은 high-contrast dark background, 밝은 text, 최소 4.5:1 대비를 목표.
- default font에서 glyph가 없을 수 있는 emoji를 핵심 표시에 사용하지 않음.
- 한국어 문자열이 깨지지 않는지 editor parse와 실제 창에서 확인.
- grid는 mouse filter와 event propagation을 명시적으로 설정.
- modal menu/drawer가 열리면 map/action input 차단.
- UI refresh는 command/selection/resize/load/reset 뒤 명시 호출. 매 frame 전체 갱신 금지.
- exception/assert로 UI 전체가 꺼지지 않게 null DTO와 load 실패를 표시 가능한 상태로 처리.
- test 전용 public method는 최소화하되 headless smoke가 selection→MOVE→HUD refresh를 호출할 수 있게 함.

## 17. 필수 UI 테스트

1. main scene이 `Control` root로 headless instantiate됨
2. 기준 450×800에서 주요 panel rect가 겹치거나 화면 밖으로 나가지 않음
3. 360×640과 540×960 resize smoke
4. visible cell은 정확히 최대 9×9이며 world coordinate 변환 정확
5. map click은 selection만, 같은 인접 칸 두 번째 click은 MOVE 하나만 제출
6. button click이 map click으로 전파되지 않음
7. keyboard 한 press가 MOVE 한 step만 생성
8. wall/occupied selection의 MOVE button disabled와 reason 표시
9. shallow water에서 HUMAN 60, AMPHIBIAN 0, DWARF 100 표시
10. conductivity 100/electric risk 0에서 `전기위험 없음` 표시
11. MOVE 뒤 HP/time/step/player position/timeline/log가 authoritative result와 일치
12. cadence 중 사망 시 GAME OVER state와 action disabled
13. SAVE→MOVE→LOAD 뒤 위치/time/exposure/HUD 복원
14. RESET same seed가 같은 visible cells와 snapshot을 만듦
15. log drawer/menu가 열린 동안 MOVE 입력 차단
16. 반환 DTO를 UI에서 formatting해도 session snapshot 불변
17. scene/editor parse stdout에 새 SCRIPT ERROR 없음

## 18. 수동 플레이 체크리스트

### 5분 루프 A — 이동 시간

- floor, shallow water, rubble을 차례로 이동
- `T`가 각각 100, 130, 140 증가하는지 확인
- 예상 timeline과 실제 timeline 비교
- wall과 점유 칸 거부에서 시간 불변 확인

### 5분 루프 B — affinity

- shallow water 선택
- HUMAN 60, AMPHIBIAN 0, DWARF 100 확인
- species를 바꿔도 terrain의 water exposure 80 자체는 변하지 않는지 확인
- metal/wet tile에서 conductivity와 electric risk 0 구분 확인

### 5분 루프 C — 환경 cadence

- 물 행동으로 `T=80`에 맞춤
- 불타는 목적지로 floor MOVE
- `T=100` 환경 marker와 새 위치 피해 확인
- 불타는 칸에서 빠져나오는 반대 시나리오 확인

### 5분 루프 D — 재현

- SAVE
- 3개 이상의 혼합 명령 실행
- LOAD
- 위치·시간·HP·불·젖음·risk 복원 확인
- replay drawer에서 seed와 journal 확인

## 19. 완료 기준

아래를 모두 만족해야 UI 완료다.

```text
UI headless tests 통과
+ 전체 core 회귀 통과
+ editor parse 성공
+ 실제 창 450×800 수동 실행 가능
+ 4개 5분 체크리스트 수행 가능
+ UI가 sim/** 또는 PlaytestSession 규칙을 우회하지 않음
```

최종 보고에는 화면 구조, 실행법, 조작법, UI 테스트 수, 실제 수동 확인 가능 시나리오, 남은 UX 제한을 포함한다.
