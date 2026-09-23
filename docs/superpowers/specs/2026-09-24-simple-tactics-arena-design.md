# 전술 단순화(성격 기본 + 가중 전술 + 실수) · 전투 시험 모드 설계

작성일: 2026-09-24 · 상태: 설계 확정 · 구현 계획: `docs/superpowers/plans/2026-09-24-simple-tactics-arena.md`
근거: [태세 설계](2026-09-23-stances-design.md) · [오토배틀 설계](2026-09-23-autobattle-design.md) · Eslabong 조사(성격 = 기본 전술, 전술 = 가중치, 실수 확률, 전술은 "제안")

## 0. 결정 사항과 원칙

1. **접근성 다이어트.** 플레이어가 만지는 것은 멤버당 **태세 3버튼**과 전투 중 **적 탭(집중 공격)·후퇴** 뿐이다. 규칙 편집기·노브 슬라이더·진형 교환·정지 옵션·명령 5종·지킬 대상 선택은 **UI에서 제거**한다(엔진 API는 남긴다 — 시뮬·테스트·고급 옵션용).
2. **성격이 기본 전술이다.** 태세를 안 고르면 성격 적성 최고가 태세이고, 노브는 성격값 그대로다.
3. **강제 태세는 가중치로 부드럽게.** 적성 밖 태세를 골라도 스트레스·갈등 기억은 없다. 대신 **실수 확률**이 올라간다: 그 라운드에는 성격의 기본 태세로 행동한다("전술은 제안").
4. **실수는 성격이 보이는 방식이다.** 성격마다 기본 실수 확률이 있고(성실할수록 낮음), 실수의 형태는 성격을 따른다: 신중한 멤버는 **머뭇거림**(WAIT), 대담한 멤버는 **무모함**(예고 칸 무시하고 공격). 결정론(시드 해시)이라 시뮬과 호환된다.
5. **전투 시험 모드.** 마을에서 탐험 없이 바로 아레나 전투로 들어가 파츠·태세를 자유롭게 바꿔 가며 싸워 본다. 경제·가방·성장에 영향 없음(별도 세션).

## 1. 성격 → 전술 (엔진)

### 1.1 실수 확률

`expedition/stances.gd`:

```gdscript
static func mistake_chance(actor) -> int   # 퍼센트, 0~40
```

- 기본: `base = 4 + (1000 − C) / 60` → C 1000 → 4%, C 0 → 20%.
- 강제 가중: 태세가 편안 범위 밖이면 `+ min(20, gap / 40)` — `gap = aptitude[default] − aptitude[chosen]`(0~2000) → 최대 +20%.
- 불안(스트레스 ≥ 100): ×1.5, 붕괴(≥ 150): ×2. 상한 40%.
- 판정: `Hexaco.sample(seed, expedition*100000 + round*100 + actor.id, "mistake", 100) < chance` — 라운드·멤버마다 한 번. 결정론.

### 1.2 실수의 형태 (`Stances.mistake_kind(actor) -> String`)

- 강제 태세 중(편안 범위 밖)이면 `"REVERT"`: 그 라운드는 `default_stance`로 행동(로그 "OO · 자기 방식대로").
- 아니면 성격으로: `E ≥ X`이면 `"HESITATE"`(그 라운드 WAIT, 로그 "OO · 머뭇거림"), 아니면 `"RECKLESS"`(돌격형 프로그램으로 행동하되 예고 회피 없음·posture +100 취급, 로그 "OO · 무모함").
- `Tactics.choose` 1단계(명령) 뒤, 후퇴선 앞에 삽입: 실수면 위 행동을 돌려준다. 후퇴선 밑에서는 실수해도 후퇴가 먼저다(살아야 실수도 한다).

### 1.3 갈등 제거

- `open_battle_conflicts`의 스트레스 +8·`COMMAND_CONFLICT` 기억·"갈등" 메시지 삭제. `Knobs.conflicted`는 UI 배지용(⚠)으로만 남긴다. `actor.conflicted`는 UI 배지로 유지(스트레스 효과 없음), `ignoring` 필드는 삭제한다 — 불안해도 손잡이를 갈아치우지 않으니 읽는 곳이 없다.
- `Stances.effective`·`Knobs.effective`의 "불안하면 기본값" 규칙은 삭제하고 1.1의 ×1.5/×2로 대체한다(불안한 멤버는 자주 실수하지, 항상 딴 짓하진 않는다).

### 1.4 기본값·자동

- 노브는 항상 성격값(`Knobs.defaults(profile)`) — `set_knob`는 남기되 UI에서 부르지 않는다. 시뮬 빌드의 `knobs`는 그대로 적용된다.
- 호위 대상은 항상 자동(§0.6 순서). `set_protect`는 남기되 UI 없음.
- 정지 이벤트는 고정: BATTLE_START·DEATH·BATTLE_END ON, ALLY_LETHAL·HP_LOW OFF(멈춤이 잦아 답답함). `auto.stops`는 남기되 옵션 팝업 없음.
- 명령은 `FOLLOW`(기본)·`ATTACK_TARGET`(적 탭)·`RETREAT`(버튼)만 UI에 노출. 후퇴 버튼을 다시 누르면 FOLLOW.

## 2. UI 다이어트

| 화면 | 제거 | 남김/변경 |
| --- | --- | --- |
| 성격 탭 | 노브 슬라이더·편안 범위 띠·`ProtectPick`·적성 막대 | HEXACO 게이지, **태세 3버튼**(⚠은 적성 밖 표시, 툴팁 "실수 확률 n%"), "빌드 추천" 배지, 실수 확률 한 줄("실수 확률 12% · 성실 낮음") |
| 파츠 탭 | 규칙 카드의 "사용 방침 ›"·자동 ON/OFF | 슬롯 카드·장착/교체/해제만 |
| 전투 HUD | 명령 바 5개, 진형 버튼, ⚙ 옵션 | 멤버 카드 · ▶/⏸ · 1×/2× · **후퇴** 토글 · 가방 · 횃불. 적 탭 = 집중 공격(기존) |
| 결과 카드 | 갈등 표시 | 실수 횟수("실수 2") 추가 — `battle_stats.members[id].mistakes` |

엔진 API·테스트는 유지: `set_knob/set_protect/swap_formation/update_rule` 등은 세션에 남고 `tests/autobattle.gd`·`tests/stances.gd`의 해당 검사는 세션 층에서 그대로 통과해야 한다. UI 검사 중 제거된 위젯을 찾는 것만 삭제한다.

## 3. 전투 시험 모드

### 3.1 진입·세션

- 마을 화면 버튼 **"전투 시험"**(`TownArena`, 시험 로드아웃 옆). 누르면 **시험 설정 화면**(`ArenaSetup`)으로.
- 시험은 **별도 세션**: `Session.arena_test(seed, party_size, arena_id, members: Array) -> Session` (static). 층 모드·3인(또는 설정 인원), `grant_test_loadout` 후 `members[i] = {"stance", "parts": [id, id]}`를 적용(`equip_part` 우회: 슬롯에 직접 넣고 `default_rule` 추가), 아레나는 `encounter_arena.layout(spec, theme, seed)` + `continuous_floor.apply` — 시뮬 러너와 같은 경로. `phase = "BATTLE"`, `reset_battle_stats()`.
- 아레나 목록: `data/content/balance_experiments.json`의 `action_economy.arenas` 6개 + `"custom"`(적 구성을 종족·역할로 최대 3명 직접 고름).
- 본 세션(마을·가방·자금)은 건드리지 않는다. 시험이 끝나면 "설정으로"(`ArenaSetup` 재진입, 같은 설정 유지) 또는 "마을로"(본 세션 복귀).

### 3.2 설정 화면 (`ArenaSetup`, `expedition/arena_setup.gd` 신규)

- 상단: 아레나 선택(OptionButton: 6종 + 직접), 시드(숫자, 기본 랜덤, "고정" 체크), 인원(1~3).
- 멤버 카드 ×인원: 이름·성격 요약, **태세 3버튼**, **파츠 슬롯 2개**(각각 OptionButton: 빈칸 + 카탈로그 전체 파츠 이름 — 밀치기·엄호·시험 스킬 포함), 실수 확률.
- 직접 아레나: 적 슬롯 3개(OptionButton: 없음 + 종족 8 × 역할 MELEE/RANGED/CASTER).
- 버튼 "시작" → 세션 생성 → 전투 HUD(기존 `refresh`가 그대로 그림; 전투 시작 정지에서 시작). "마을로".
- 설정은 `main.gd`의 `arena_config: Dictionary`에 남아 다음 진입 때 복원.

### 3.3 흐름

전투 시작 정지 → ▶ → 자동 진행 → 결과 카드(기존, "설정으로"·"다시"(같은 설정·새 시드) 버튼 추가) → 설정 화면. 사망·전멸도 결과 카드로 끝나고 본 세션에 영향 없음.

## 4. 검증

- `tests/stances.gd`에 `mistakes()`: 실수 확률 공식(고정 프로필), 강제 가중, 불안 배수·상한, 결정론(같은 시드 같은 결과), 형태(REVERT/HESITATE/RECKLESS)와 실제 행동, 후퇴선 우선, 갈등 스트레스 없음.
- `tests/arena_mode.gd`(신규, CI): `Session.arena_test`가 본 세션과 독립(가방·자금 불변), 멤버 설정 적용(태세·파츠·규칙), 6종 아레나 + 직접 구성 생성, 전투 진행·결과 카드·"다시"가 새 시드, 씬: `TownArena` 버튼 → `ArenaSetup` 위젯 존재 → 시작 → HUD → 결과.
- 기존 UI 검사에서 제거 위젯 참조 삭제; 세션 층 검사 유지.
- 게이트 재측정은 하지 않는다(실수 확률은 결정론이지만 승률을 바꾼다 — 다음 밸런스 라운드에서 `solo_balance` 등 재확인; CI의 `solo_balance` 기준 3/8은 유지하고 미달이면 `mistake_chance`의 `base` 상수만 조정 가능).
