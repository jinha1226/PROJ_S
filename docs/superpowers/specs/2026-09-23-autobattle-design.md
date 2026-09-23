# 오토배틀 전환 · 성향 노브 · 전투 결과 설계

작성일: 2026-09-23 · 상태: 설계 확정(턴제 유지 결정 2026-09-23) · 구현 계획: `docs/superpowers/plans/2026-09-23-autobattle.md`
근거: [밸런스 방법론](../../balance-method.ko.md) · 선행: [몬스터 파츠](2026-09-22-monster-parts-design.md), [스킬 효과 유형](2026-09-22-skill-archetypes-design.md)

## 0. 결정 사항과 원칙

브레인스토밍에서 확정된 결정:

1. **자동 + 개입(B).** 전투는 규칙 엔진이 굴리고, 플레이어는 멈춰서 개입한다. 탐색(층 이동·횃불·큐리오·아이템 관리)은 수동 그대로.
2. **개입은 명령만(A).** 멈춘 동안 할 수 있는 것은 파티 명령·아이템·횃불·진형 교체. 멤버 개개인의 행동을 직접 고르는 조작은 층 모드에서 없앤다.
3. **이벤트 자동 정지(A).** 정지 이벤트에서 스스로 멈추고, 그 외에는 "정지" 버튼. 전투 시작 정지는 기본 ON.
4. **성향 노브 3개**를 규칙 목록 위에 두고, 기본값과 편안 범위를 **성격(HEXACO)**에서 끌어낸다. 범위 밖 강제는 갈등(`COMMAND_CONFLICT`)을 낳는다.
5. **전투 결과 화면**: 시뮬 계측을 그대로 플레이어에게 보여 "왜 졌는지 → 무엇을 바꿀지"를 잇는다.
6. 전투 형식은 **턴제 그리드 유지**로 결정(부록 A의 검토 결과).

원칙: 게임이 쓰는 자동 진행 함수와 시뮬레이터가 쓰는 함수는 **같은 함수**다(`session.auto_step`). 시뮬이 재는 것이 곧 플레이어가 보는 것이어야 밸런스 파이프라인이 유효하다. 주인공에게 특별한 AI는 없다 — 동료와 같은 `Tactics.choose`.

범위 밖: 실시간 전투, 멤버 개별 조작(C안), 정착지 시설, 2층 이상.

## 1. 자동 진행

### 1.1 `session.auto_step() -> bool`

한 라운드를 규칙으로 진행한다. 반환값은 "진행했는가".

```
1. phase != "BATTLE" 또는 생존자 없음 → false.
2. 생존 파티원 각각(파티 순서, selected 무관)에 대해 AP가 남아 있는 동안:
   choice = command_choice(actor)   # 파티 명령이 정한 행동이 있으면 그것
   if choice.is_empty(): choice = Tactics.choose(self, actor)
   act_as(actor, choice.kind, choice.cell)   # 기존 act()를 selected 교체 없이 액터 지정으로 호출
   actor.last_action = choice.reason
3. end_round()  (적 턴·패시브·쿨다운·다음 라운드)
4. true
```

- `act()`는 `party[selected]`를 쓰므로 `act_as(actor, kind, cell)`로 분리한다: `act()`는 `act_as(party[selected], …)`의 껍데기. `finish_player_action()`의 "동료가 뒤따라 행동" 블록은 층 모드에서 `auto_step`이 대신하므로 층 모드에서는 호출하지 않는다(구 방 모드·보스 시련은 그대로).
- `resolving_companions`·`reservation` 경로는 층 모드에서 쓰지 않는다. 층 모드의 `reserve_action`은 `false`를 돌려준다.
- 솔로: 파티원 1명, `solo_actions` 규칙 그대로(1행동).

### 1.2 정지 이벤트

```gdscript
const AUTO_STOPS := ["BATTLE_START","BATTLE_END","DEATH","ALLY_LETHAL","HP_LOW"]
var auto := {"running":false,"stops":{"BATTLE_START":true,"ALLY_LETHAL":true,"HP_LOW":true,"DEATH":true,"BATTLE_END":true},"hp_low":30,"speed":1}
func auto_stop_reason() -> String   # 이번 라운드 시작 시점에 해당하는 첫 이벤트 id, 없으면 ""
```

| 이벤트 | 조건 (라운드 시작 시 평가) | 기본 |
| --- | --- | --- |
| `BATTLE_START` | `combat_enemies()`가 직전 라운드에는 비었고 지금은 비어 있지 않음 | ON |
| `ALLY_LETHAL` | 생존 파티원 중 `Rules.lethal_threat(s, a) >= a.hp`인 사람이 있음 | ON |
| `HP_LOW` | 생존 파티원 중 `hp*100/max_hp <= auto.hp_low`인 사람이 새로 생김(직전 라운드에는 아니었음) | ON, 30% |
| `DEATH` | 직전 라운드에 파티원이 쓰러짐 | ON |
| `BATTLE_END` | `combat_enemies()`가 직전 라운드에는 비어 있지 않았고 지금은 비었음 | ON |

- `AUTO_STOPS`의 나열 순서가 곧 **우선순위**다: 한 라운드에 여러 이벤트가 동시에 성립해도 `BATTLE_START` → `BATTLE_END` → `DEATH` → `ALLY_LETHAL` → `HP_LOW` 순으로 첫 하나만 보고된다. 앞의 셋은 "굳은" 이벤트라 꺼져 있어도 상태를 소비한다(다음 라운드에 다시 터지지 않는다).
- 평가에 필요한 "직전 라운드" 상태는 `auto`에 `prev_threats: int`, `prev_low: Array[int]`, `prev_alive: int`로 보관하고 **`auto_step` 시작 시점**에 `remember_round()`로 갱신한다(끝이 아니다). 정지 이벤트는 "이번 라운드 **동안** 무엇이 바뀌었는가"를 묻기 때문에, 그 라운드 안에서 일어난 사망이나 전멸이 델타로 남으려면 스냅샷이 행동 전에 찍혀야 한다. `auto_stop_reason`이 이벤트를 보고할 때도 같은 함수로 한 번 더 갱신해 같은 이벤트가 곧바로 재발화하지 않게 한다.
- 같은 이벤트가 연속 라운드에 반복되면(예: 계속 치명 위기) 다시 멈추지 않는다: `auto.last_stop = {"reason", "round"}`를 두고 같은 reason이면 3라운드 안에는 재정지하지 않는다. `BATTLE_START`·`BATTLE_END`·`DEATH`는 예외 없이 멈춘다.
- 시뮬레이터는 정지 이벤트를 무시한다(`auto_stop_reason`을 호출하지 않는다).

### 1.3 UI 루프 (`main.gd`)

- 층 모드 전투 화면에 **재개 ▶ / 정지 ⏸** 토글과 **속도 1×/2×**. `auto.running`이면 타이머(1× = 0.7초, 2× = 0.35초)마다 `run_action(session.auto_step)`; 실행 전에 `auto_stop_reason()`이 비어 있지 않으면 `running=false`, 알림 배너에 이벤트 이름("전투 시작 · 적 3", "아린 치명 위기", "브란 체력 30% 이하", "세라 쓰러짐", "전투 종료")을 띄운다.
- 팝업(가방·상점·캐릭터·결과)이 열려 있으면 타이머는 돌지만 `auto_step`을 부르지 않는다.
- 전투 밖(`safe()`)에서는 자동 진행 없음 — 탐색은 수동. 적을 발견하면 `BATTLE_START`로 멈춘 상태에서 시작하므로, 플레이어가 ▶를 눌러야 첫 라운드가 돈다.
- 정지 이벤트 설정은 옵션 팝업(체크 5개 + HP 임계값 20/30/40/50)에서 바꾸고 세션에 저장한다.

## 2. 명령

`party_command`는 **주인공을 포함한 전원**에게 적용된다(지금은 동료만). `command_choice(actor)`는 기존 `companion_choice`에서 명령 처리 부분만 떼어낸 함수다.

| 명령 | 뜻 | `command_choice` |
| --- | --- | --- |
| `FOLLOW` (기본) | 규칙대로 싸움 | `{}` (규칙에 맡김) |
| `HOLD_POSITION` | 자리 지킴 | 인접 적이 있으면 `{}`(규칙이 공격), 없으면 WAIT |
| `STOP_ATTACK` | 공격 중지·집결 | 진형 기준점(§6)으로 이동, 도착했으면 WAIT |
| `RETREAT` | 후퇴 | 적과 거리를 벌리는 이동(현행), 없으면 WAIT |
| `ATTACK_TARGET` | 집중 공격 | `command_target` 적에게 규칙 후보 중 그 적을 향하는 것만 허용(현행) |

- 명령은 멈춘 동안에만 바꿀 수 있다(진행 중에는 버튼 비활성). 바꾸면 자동으로 ▶ 재개하지 않는다.
- 아이템(물약·붕대·두루마리)·횃불은 멈춘 동안에만 쓸 수 있고, 사용은 라운드를 소모하지 않는다(현행 `use_supply` 규칙 유지: 전투 중 사용자는 AP 1 소모 → 자동 진행에서는 사용자가 그 라운드에 행동 하나를 잃는다. 이것이 "아이템은 공짜가 아니다"의 비용).
- 후퇴·포기·귀환은 현행 `abandon`/`return_home` 그대로(안전할 때만).

## 3. 성향 노브와 성격

### 3.1 노브

액터 필드 `knobs := {"posture":0,"cohesion":0,"retreat_hp":25}`.

| 노브 | 범위 | 뜻 |
| --- | --- | --- |
| `posture` 태세 | −100(신중) ~ +100(공격적) | 위험을 감수하고 공격하는 정도 |
| `cohesion` 협동 | −100(독자) ~ +100(밀집) | 아군 옆을 지키는 정도 |
| `retreat_hp` 후퇴선 | 0 ~ 60 (%) | 이 HP 이하면 거리 벌리기·회복 우선 |

### 3.2 `Tactics.choose`에 미치는 영향

점수는 정수이며 현행 값(회피 200+, 공격 = 피해량(+12 처치), 밀치기 40+, 엄호 35, 파츠 40)에 더한다. 상수는 `Tactics.KNOB`에 모아 둔다.

| 후보 | 조정 |
| --- | --- |
| ATTACK / 피해 파츠 | `+ posture * 15 / 100` (공격적 +15, 신중 −15) |
| 위험 회피 MOVE (`danger(cell) < here`) | 신중: `+ (−posture) * 30 / 100`; 공격적: 예고 칸(intent)이 아닌 위험(불)만 있으면 후보에서 제외 |
| 엄호 GUARD | `+ cohesion * 20 / 100` |
| 이동 후보 전부 | 도착 칸에서 인접 아군 수가 줄면 `− cohesion * 10 / 100`, 늘면 `+ cohesion * 10 / 100`; `cohesion < 0`이면 부호 반대(독자 행동은 흩어짐을 선호) |
| 후퇴 | `hp*100/max_hp <= retreat_hp`이면: 적과 거리를 벌리는 MOVE 후보(현행 RETREAT 계산) 점수 150, 회복 파츠(HEAL)·회복 아이템 규칙 우선; 공격 후보 −20 |

후퇴선 아래의 후보 풀은 **거리를 벌리는 MOVE와 회복(HEAL) 파츠 둘뿐**이다 — 공격·밀치기·엄호·태세 후보는 전부 탈락하고, 풀이 비면 WAIT. 그 안의 점수는 MOVE `150 + cohesion * 10 / 100`(≤ 160), 회복 파츠 `40 + 150 = 190`이므로 **회복 파츠를 들고 있으면 회복이 이기고, 없으면 거리를 벌리는 MOVE가 유일한 답**이다. 회복 파츠가 없는 빌드(현행 기준 빌드 대부분)에서 후퇴선 아래의 행동이 언제나 한 칸 물러서기인 이유가 이것이다.

규칙 목록(`rules`)이 매칭되면 그것이 먼저다(현행). 노브는 규칙이 고르지 않은 후보들 사이의 순위만 바꾼다. 단 후퇴선은 규칙보다 앞선다(살아야 규칙도 있다) — `retreat_hp` 조건에 들어가면 `rule_choice`를 건너뛰고 위 후퇴 점수로 고른다.

### 3.3 성격 → 기본값·편안 범위

HEXACO 값 `v(F)`는 0~1000. 중심 500.

| 노브 | 기본값 | 편안 범위 반폭 |
| --- | --- | --- |
| `posture` | `(v(X) − v(E)) / 10` → −100~100 클램프 | `20 + v(C)/20` (성실할수록 넓음: 20~70) |
| `cohesion` | `(v(A) − 500) / 5` → −100~100 클램프 | `20 + v(C)/20` |
| `retreat_hp` | `10 + v(E)/25` (0~50) | `10 + v(C)/50` (10~30) |

- 새 액터는 기본값으로 시작한다. 플레이어는 마을·안전 구역에서 노브를 바꿀 수 있다(캐릭터 창 "성향" 탭 — 현재 "성격" 탭을 확장).
- **갈등**: 노브가 편안 범위 밖이면 그 멤버는 `conflicted = true`. 전투가 시작될 때(`BATTLE_START` 시점) 갈등 중인 멤버는 스트레스 +8과 `COMMAND_CONFLICT` 기억(강도 600, 기존 `remember_important` 경로)을 얻는다. 상태가 **불안(스트레스 ≥ 100)** 이면 그 전투 동안 노브는 성격 기본값으로 대체된다(명령 무시 — 로그 "아린 · 자기 방식대로 움직입니다"). **붕괴**면 추가로 `posture`가 −100 또는 +100 극단(E 높으면 −100, 낮으면 +100)으로 간다.
- 성격 탭에 노브 슬라이더와 편안 범위 띠를 같이 그려 "이 사람은 여기가 편하다"가 보이게 한다.

### 3.4 시뮬 빌드

`reference_builds.json`에 `"knobs": {"posture":0,"cohesion":0,"retreat_hp":25}`(생략 시 이 값). `apply_build`가 적용한다. 성격 갈등은 시뮬에서도 그대로 작동한다(시뮬 액터의 HEXACO는 시드로 생성되므로 결정론).

## 4. 규칙

- 주인공 규칙 편집은 동료와 같은 UI(파츠 탭의 사용 방침·순위)로 마을·안전 구역에서 한다. 층 모드 `safe_management()`가 참일 때 허용.
- 기본 규칙은 파츠 장착 시 `default_rule`로 생기는 것 그대로. 노브가 생겨서 없어지는 규칙 조건은 없다.
- 새 조건 없음. 예고 칸 회피는 `Tactics`의 위험 회피 이동이, 고립 회피는 협동 노브가 맡는다. 플레이 후 "규칙으로 못 하는 상황"이 반복되면 그때 조건을 추가한다.

## 5. 전투 결과 화면

### 5.1 계측 (`session.battle_stats`)

전투 단위(`BATTLE_START` ~ `BATTLE_END`)로 초기화되는 딕셔너리. `damage()`·`resolve`·`interrupt`·`roll_part`·`end_round`가 채운다.

```
{"rounds": int, "enemies": int, "kills": int,
 "members": {id: {"dealt": int, "taken": int, "guards": int, "redirected": int, "parts": {part_id: count}, "healed": int, "downed": bool, "conflict": bool}},
 "interrupts": int, "enemy_parts": {part_id: count}, "drops": {part_id: count}, "stops": [reason, …]}
```

기존 `stats_redirects`·`stats_enemy_skill`·`stats_interrupts`는 이 구조로 흡수한다(시뮬 러너는 `battle_stats` 합계를 읽는다).

### 5.2 화면

`BATTLE_END` 정지 시 결과 카드를 띄운다(닫으면 탐색 계속). 내용:

- 머리: "전투 종료 · N라운드 · 적 M 처치 · 아군 사망 K"
- 멤버 표: 이름 · 입힌 피해 · 받은 피해 · 엄호(횟수/대신 받은 피해) · 쓴 파츠 · 갈등 여부
- 적: 쓴 파츠(예고가 몇 번 맞았나)·끊긴 횟수
- 획득: 파츠 드롭
- 버튼: "파츠·규칙 보기"(캐릭터 창), "닫기"
- 사망자가 있으면 그 멤버 행을 강조하고 "마지막 3라운드 로그"를 덧붙인다.

원정 결과 화면(`result`)에는 전투 수·총 라운드·총 사망만 합산한다.

## 6. 진형

`formation`은 **행군 순서**다: `["아린","브란","세라"]` 인덱스 배열. 탐색 이동 시 선두가 앞, 나머지가 뒤따르는 현행 `follow`의 순서를 이 배열이 정한다.

- `BATTLE_START` 정지 중에 "진형" 버튼으로 순서를 바꿀 수 있다: 두 멤버가 **자리를 맞바꾼다**(칸 교환, 라운드 소모 없음). 한 전투에 한 번만.
- `STOP_ATTACK`의 집결 기준점은 선두의 위치.
- 그 이상(사전 배치판)은 하지 않는다 — DD식 "보이면 시작"을 유지.

## 7. 전투 HUD (층 모드)

없애는 것: 멤버별 스킬 버튼 2개, 대상 칸 선택 모드, 동료 행동 예약 팝업, 턴 종료 버튼(자동이 대신).
남기는 것/새로 두는 것:

- 멤버 카드 3장: 이름·HP·스트레스·상태·갈등 표시·`last_action`. 길게 누르면 캐릭터 창.
- 명령 바 5개(멈춘 동안만 활성) + 집중 공격은 적 탭.
- ▶/⏸, 1×/2×, 아이템, 횃불, 진형, 포기/귀환(안전할 때).
- 알림 배너(정지 이유), 로그 3줄(현행).
- 보드: 예고 칸·파츠 배지·행동 미리보기(선택 멤버의 다음 `Tactics.choose` 결과를 반투명 화살표로) — 미리보기는 있으면 좋고, 없어도 됨(선택 사항).

구 방 모드·보스 시련의 수동 조작은 그대로 둔다(테스트 스캐폴딩). `ui_smoke`의 슬롯 검사는 방 모드 기준.

## 8. 시뮬 통합

- `bot_policy.step(s, "rules")`는 `s.auto_step()`을 호출하고 `"AUTO"`를 돌려준다. 접근 단계(적이 안 보일 때 방 중앙으로)는 남긴다 — 아레나 전용. `simple`/`tactical` 정책은 그대로.
- `encounter_runner.run_one`: 라운드 루프를 `auto_step` 기준으로 고치고 `battle_stats`에서 지표를 읽는다. 지표 이름은 유지(`damage_taken`, `skill_uses`, `guards`, `enemy_skill_uses`, `interrupts`).
- 게이트 재실행: G1~G5 그대로 + **G6 노브 지배**: 3인 6아레나에서 `posture ∈ {−60,0,+60} × cohesion ∈ {−60,0,+60}` 9조합 중 어떤 조합도 다른 조합 전부에 대해 Δ승률 ≥ +20pp를 6아레나 중 4개 이상에서 내지 않는다. `docs/balance/autobattle-gates.md`에 기록.
- 원정 봇(`solo_balance` 등)은 탐색을 그대로 하고 전투만 `auto_step`을 쓴다.

## 9. 검증

CI 스위트 `tests/autobattle.gd`:

1. `auto_step`이 생존 파티원 전원을 규칙으로 행동시키고 `end_round`를 부른다; 주인공이 `Tactics.choose`를 탄다; 솔로에서 1행동.
2. 정지 이벤트 5종 각각 조건 충족 시 `auto_stop_reason`이 그 id를 돌려주고, 연속 라운드 재정지 억제 규칙이 작동한다.
3. 명령 5종이 주인공에게도 적용된다; 진행 중 명령 변경 거부.
4. 노브: 태세 +100이 예고 칸이 아닌 불 칸 회피를 생략; 협동 +100이 고립 이동을 피함; 후퇴선 이하에서 거리 벌리기; 성격 기본값·편안 범위 공식(고정 HEXACO 값으로 수치 검사); 범위 밖 설정 → 전투 시작 시 스트레스 +8·`COMMAND_CONFLICT` 기억; 불안 상태에서 기본값 대체.
5. `battle_stats`가 전투마다 초기화되고 각 필드가 채워진다; 결과 카드가 뜨고 닫힌다(씬 테스트).
6. 진형 교환이 `BATTLE_START` 정지 중 1회만 된다.
7. 시뮬: `bot_policy rules`가 `auto_step`을 호출하고 `run_one` 지표가 이전과 같은 키를 낸다; 결정론 유지.

기존 스위트: `companion_tactics`·`protect`·`mobile_actions`·`ui_smoke`(층 모드 부분)·`solo_*`·`encounter_sim`·`skill_value`·`party_guard_probe`를 새 루프에 맞춰 고친다.

## 10. 파일 요약

| 파일 | 변경 |
| --- | --- |
| `expedition/session.gd` | `auto`·`auto_step`·`act_as`·`auto_stop_reason`·`command_choice`·`battle_stats`·노브 갈등·진형 교환 |
| `expedition/tactical_action_selector.gd` | `KNOB` 상수·노브 점수·후퇴선 |
| `expedition/knobs.gd` (신규) | 성격 → 기본값·편안 범위, 갈등 판정 |
| `expedition/main.gd`, `character_ui.gd`, `board.gd` | 전투 HUD 교체·성향 탭·결과 카드·옵션 |
| `expedition/sim/bot_policy.gd`, `encounter_runner.gd`, `data/content/reference_builds.json` | `auto_step` 통합·`knobs` |
| `tests/autobattle.gd` 신규, 기존 스위트 수정, CI 목록 | 검증 |
| `docs/balance/autobattle-gates.md` | G1~G6 |

---

## 부록 A. 턴제 그리드 vs 실시간 — 검토

이 스펙은 턴제 그리드를 전제한다. 실시간(Eslabong식)으로 바꾸면 무엇이 달라지는지 정리한다. 결정은 별도.

| 축 | 턴제 그리드 (현행) | 실시간 |
| --- | --- | --- |
| 엔진 | 그대로. `auto_step` = 라운드 1회 | 이동·공격·쿨다운을 시간축으로 다시 씀. `session`의 라운드·AP·intents·예고(prep)·`end_round` 전부 교체 |
| 파츠 예고 | "1라운드 뒤"가 명확. 밀치기로 끊기·피하기·엄호가 라운드 단위로 성립 | "1.2초 뒤"로 바뀜. 끊기·피하기는 AI 반응 속도 문제가 되고, 플레이어 개입은 사실상 불가능(멈춤이 곧 일시정지) |
| 밸런스 시뮬 | 결정론. 시드 = 배치만. 게이트 파이프라인 그대로 | 프레임 순서·부동소수 누적으로 결정론이 깨지기 쉬움. 시뮬을 고정 틱으로 다시 만들어야 함 |
| 모바일 | 탭 몇 번, 언제든 멈춤. 세로 화면에 맞음 | 눈으로 따라가야 함. 정지 이벤트로 멈추면 결국 "턴제 같은 실시간" |
| 규칙·노브 | 후보 나열 → 점수. 지금 코드 | 같은 개념이지만 "언제 평가하나"(매 틱? 행동 끝날 때?)가 추가 설계 |
| DD 느낌 | 라운드제·예고·긴장 — DD와 같은 결 | 아레나 관전 느낌. 던전 탐색과의 이음새가 어색해짐 |
| 작업량 | 이 스펙 = 2~3주 규모(태스크 6~8개) | 전투 엔진 재작성 + 아트(애니메이션 필수) + 시뮬 재작성. 파츠·규칙은 살지만 그 외 대부분 새로 |

권고: **턴제 그리드 유지.** 실시간의 장점(박진감·관전 재미)은 턴제에서 **속도 2×·행동 미리보기·타격 연출**로 상당 부분 얻을 수 있고, 실시간의 비용(엔진·시뮬·아트 재작성, 개입 불가)은 이 프로젝트의 강점(결정론 밸런스 파이프라인, 모바일 세로 화면, DD식 예고 카운터플레이)을 직접 깎는다. Eslabong의 좋은 점(성향 노브·결과 화면·주장 조작)은 형식과 무관하게 이 스펙이 가져왔다.
