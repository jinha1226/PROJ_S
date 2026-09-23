# 태세(역할형 AI) × 성격 설계

작성일: 2026-09-23 · 상태: 설계 확정 · 구현 계획: `docs/superpowers/plans/2026-09-23-stances.md`
근거: [오토배틀 설계](2026-09-23-autobattle-design.md) §3 · [밸런스 방법론](../../balance-method.ko.md) · 선행: [몬스터 파츠](2026-09-22-monster-parts-design.md)

## 0. 결정 사항과 원칙

1. **역할은 직업이 아니라 태세(stance)다.** 태세는 "능력을 어떻게 쓰나"(붙는다·거리 둔다·지킨다)를 정하고, 숙련·파츠는 제한하지 않는다. 안전 구역에서 자유 변경.
2. **태세는 3종 고정**: 돌격형 `CHARGER`, 거리형 `SKIRMISHER`, 호위형 `GUARDIAN`. 유연형(현행 최적 선택기)은 두지 않는다 — 안전빵이 다른 태세를 사장시킨다.
3. **성격은 적성(편안 범위)만 정한다.** 적성 밖 태세를 강제해도 되지만 노브와 같은 갈등 규칙이 붙는다. 잠그지 않는다.
4. **빌드가 태세를 제안한다**(배지). 강제가 아니다.
5. **거리형에 원거리 파츠가 없으면 치고 빠지기**로 일관되게 행동한다(돌격형으로 대체하지 않는다).
6. **호위 대상**: 지정 없으면 거리형 멤버 → 없으면 HP 비율 최저 아군. 솔로에서는 호위형 선택 불가.
7. **공통 표적**: `집중 공격` 명령이 있으면 그것, 없으면 돌격형이 붙은 적, 없으면 가장 가까운 적. 거리형은 이것을 쏘고, 호위형은 보호 대상에 접근하는 적을 우선하되 없으면 공통 표적.
8. 기존 노브 3개(태세·협동·후퇴선)는 **태세 안의 강도**로 남는다. 규칙 목록은 "언제 파츠를 쓰나"로 그대로.
9. 원칙: **의도한 역할을 일관되게 수행하는 것이 최적 행동보다 먼저다.** 후보 생성기는 태세별로 다르고, 공통 안전장치(후퇴선)만 위에 있다.

범위 밖: 유연형, 4번째 태세, 태세별 전용 파츠, 정착지 영입.

## 1. 데이터

액터 필드:

```gdscript
"stance": "CHARGER" | "SKIRMISHER" | "GUARDIAN"   # 기본값은 성격 적성 최고
"protect_id": -1                                   # 호위 대상 지정(파티 인덱스), -1이면 자동
```

`expedition/stances.gd`(신규, static):

```gdscript
const IDS := ["CHARGER","SKIRMISHER","GUARDIAN"]
const NAMES := {"CHARGER":"돌격형","SKIRMISHER":"거리형","GUARDIAN":"호위형"}
static func aptitude(profile) -> Dictionary   # {"CHARGER": X−E, "SKIRMISHER": E+C−1000, "GUARDIAN": A+H−1000}, 각 −1000~1000
static func default_stance(profile) -> String # aptitude 최고(동률이면 IDS 순)
static func comfortable(profile, stance) -> bool  # aptitude[stance] >= best − (200 + C/5)   (C 0→200, C 1000→400 폭)
static func suggested(actor) -> String        # 빌드 제안: 장착 파츠에 range ≥ 3인 DAMAGE/LUNGE가 있으면 SKIRMISHER, GUARD가 있으면 GUARDIAN, 아니면 CHARGER
static func effective(actor) -> String        # 불안(스트레스 ≥100)이면 default_stance, 아니면 actor.stance
```

- `Knobs.conflicted(actor)`에 태세 조건을 더한다: 노브가 범위 밖 **또는** `not Stances.comfortable(profile, actor.stance)`. 갈등 효과(전투 시작 스트레스 +8, `COMMAND_CONFLICT` 기억, 불안 시 기본값 복귀)는 기존 그대로 — 한 전투에 한 번만(노브·태세 합쳐서).
- `session.set_stance(index, stance)`: `set_knob`과 같은 조건(마을 또는 안전·비전투). 솔로(`party.size() == 1`)에서 GUARDIAN 거부. `session.set_protect(index, target_index)`: 같은 조건, 자기 자신·사망자 거부, −1 허용.
- 시뮬 빌드(`reference_builds.json`)에 `"stance"` 키(생략 시 `CHARGER`), `apply_build`가 적용.

## 2. 행동 프로그램 (`expedition/tactical_action_selector.gd`)

`Tactics.choose(s, actor)`의 구조를 바꾼다:

```
1. 명령(command_choice)이 답을 주면 그것.                      [기존]
2. low := hp% <= retreat_hp  → 후퇴 후보(거리 벌리기 150, 회복 파츠 +150)만으로 선택.  [기존 후퇴선]
3. 규칙 목록(rule_choice)이 매칭되면 그것 — 단 ALLY 대상(엄호)만 즉시, 나머지는 태세 후보와 경쟁.  [기존과 유사]
4. 태세 후보 생성: Stances.candidates(s, actor, stance) → options
5. options에 노브 조정(태세·협동)을 더하고 최고 점수 선택. 없으면 WAIT.
```

공통 헬퍼: `party_target(s) -> Dictionary`(공통 표적, §0.7), `protectee(s, actor) -> Dictionary`(§0.6), `ranged_part(actor) -> String`(장착 파츠 중 range ≥ 3인 DAMAGE/LUNGE, 없으면 "").

### 2.1 돌격형 `CHARGER`

- 표적 = 공통 표적. 인접이면 **ATTACK**(점수 100 + 피해). 아니면 표적에 인접한 빈 칸으로 **최단 경로 MOVE**(점수 80). 경로가 없으면 가장 가까운 적으로 같은 처리.
- 예고 칸 회피는 **하지 않는다**(`posture`가 −60 이하일 때만 예고 칸에서 한 칸 비켜서는 후보 60을 추가). 불 칸은 항상 피한다.
- 밀치기 규칙(CHARGING)이 매칭되면 규칙이 이긴다(3단계).
- 노브: `posture`는 ATTACK 점수 ±15, `cohesion`은 무시, `retreat_hp` 공통.

### 2.2 거리형 `SKIRMISHER`

- `ranged_part(actor)`가 있으면: 사거리 `R`. 표적이 `R` 안·시야 안이고 규칙이 그 파츠를 허용하면 파츠 사용(규칙 목록 경로). 표적과의 거리 `d`:
  - `d < 2`: 표적에서 멀어지는 칸으로 MOVE(점수 120, 후퇴 계산 재사용).
  - `2 ≤ d ≤ R`: 자리 유지 → 파츠 쿨다운 중이면 WAIT(점수 50); 인접 적이 있으면 ATTACK(60).
  - `d > R`: 표적 쪽으로 MOVE(80), 단 도착 칸이 적과 인접하면 제외.
- 원거리 파츠가 없으면 **치고 빠지기**: 인접이면 ATTACK(100) 후 다음 라운드 `hit_and_run = true`; `hit_and_run`이면 표적에서 2칸 떨어지는 MOVE(120) 후 플래그 해제; 아니면 표적에 접근 MOVE(80). 라운드마다 "접근 → 타격 → 이탈" 3박자.
- 예고 칸은 항상 피한다(위험 회피 후보 200, 기존).
- 노브: `posture`는 유지 거리에 영향(공격적일수록 `R−1`까지 접근), `cohesion`은 무시, `retreat_hp` 공통.

### 2.3 호위형 `GUARDIAN`

- 보호 대상 `P` = `protectee(s, actor)`. 위협 = `P`에 접근 중인 적(`P`와의 거리 ≤ 2 또는 `P`를 향한 예고).
- 우선순위: (a) `P`가 치명 위기(`lethal_threat ≥ hp`)면 엄호 규칙(3단계, ALLY_LETHAL) — 엄호 파츠가 없으면 `P`와 위협 사이 칸으로 MOVE(130). (b) 위협이 인접이면 ATTACK(100). (c) 위협이 있으면 위협과 `P` 사이 칸(`P`에서 위협 방향 1칸)으로 MOVE(90). (d) 위협이 없으면 `P` 인접 칸 유지: 인접이면 공통 표적이 인접일 때만 ATTACK(60), 아니면 WAIT(40); 인접이 아니면 `P` 인접 칸으로 MOVE(80).
- `P`가 없으면(솔로/전멸) CHARGER로 동작.
- 노브: `cohesion`은 `P`와 유지하려는 거리(밀집 +100 → 1칸, 독자 −100 → 2칸), `posture`는 (b)의 공격 점수 ±15, `retreat_hp` 공통.

### 2.4 공통

- 후보에 없는 행동은 하지 않는다: 태세별 목록이 곧 성격이다.
- 밀치기/엄호/파츠 사용은 규칙 목록(3단계)이 결정한다. 태세는 규칙이 아무것도 고르지 않았을 때의 기본 움직임이다.
- `Stances.candidates`는 순수 함수(세션 읽기만). 시뮬 봇·게임 모두 `auto_step` → `Tactics.choose` 경로 그대로.

## 3. UI

- 캐릭터 창 "성격" 탭: 태세 선택 3버튼(현재 태세 강조, 적성 밖이면 "⚠ 성격과 맞지 않음"), 각 버튼 옆 적성 수치 막대, 빌드 제안 배지("빌드 추천: 거리형"). 호위형 선택 시 "지킬 대상" 옵션(자동/멤버 이름). 솔로에서는 호위형 비활성.
- 멤버 카드(전투 HUD)에 태세 아이콘 한 글자(돌/거/호)와 갈등 표시.
- 전투 결과 카드: 멤버 행에 태세와 "역할 수행" 지표(돌격: 표적 인접 라운드 비율, 거리: 사거리 유지 라운드 비율·원거리 파츠 없음 경고, 호위: 보호 대상 인접 라운드 비율·가로막기 횟수) — `battle_stats.members[id].role_rounds`로 집계.

## 4. 시뮬·게이트

- `reference_builds.json`: `stance_charger`(melee_1 + CHARGER), `stance_skirmisher`(KOBOLD_SLING + GUARD, SKIRMISHER), `stance_guardian`(melee_1 + GUARDIAN). 3인 아레나에서는 파티 셋에 다른 태세를 주는 `apply_build` 확장: `"stances": ["CHARGER","SKIRMISHER","GUARDIAN"]`(멤버 순).
- 게이트 G7 태세 생존: 3인 6아레나에서 혼합 파티(돌·거·호) 승률 ≥ 0.85; 단일 태세 파티 3종 각각 6아레나 중 ≥ 4에서 승률 ≥ 0.6(어느 태세도 사장 아님). 솔로 돌격형 `solo_balance` ≥ 3/8(오토배틀 Task 6의 G1을 이것으로 대체하고 `tests/solo_balance.gd`의 임시 기준을 3으로 복구).
- 조정 순서: 태세 점수 상수 → 노브 매핑 → (파츠 수치 불변).

## 5. 검증

`tests/stances.gd`(CI):
1. 적성·기본 태세·편안 범위 공식(고정 HEXACO 값).
2. `set_stance`/`set_protect` 조건(안전·솔로 GUARDIAN 거부·자기 지정 거부).
3. 돌격형: 표적에 붙어 공격, 예고 칸 위에서도 공격(posture 0), posture −80이면 비켜섬.
4. 거리형(원거리 파츠): d<2 이탈, 2~R 유지·파츠 사용, d>R 접근. 거리형(파츠 없음): 접근→타격→이탈 3라운드 순환.
5. 호위형: 보호 대상 자동 선택 순서, 위협 가로막기 칸, 치명 위기 시 엄호, 위협 없으면 옆 유지.
6. 갈등: 적성 밖 태세 → 전투 시작 스트레스·기억, 불안 시 기본 태세로 행동.
7. 공통 표적 우선순위(명령 > 돌격형 표적 > 최근접).
8. `battle_stats.role_rounds` 집계, 결과 카드 문구.
기존 `autobattle`·`skill_rule_conditions`·`protect`·시뮬 스위트 회귀 없음.
