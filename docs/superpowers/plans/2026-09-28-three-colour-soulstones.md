# 3색 영혼석: 색 = 발동 시점, 아이콘 = 효과 — 설계·구현 계획

작성일: 2026-09-28 · 상태: **방향 합의됨, 구현 전** · 아이콘 시안: `assets/soulstone-icons-v1/preview.png`
기준 규칙: [공격·대기 영혼석 실행 매핑](../../attack-wait-soulstones.ko.md)(`attack_wait_v1`, 일반 원정 기본), [휴식처](../specs/2026-09-28-rest-stops-design.md), [성장 방식 결정](../specs/2026-09-28-soulstone-progression-directions.md)
데이터: `data/content/attack_wait_effects.json`(효과 106개: `event` = HIT·ATTACK·WAIT, `role` = OFFENSE·DEFENSE·CHAIN, `family`, `op`, `role_stats`), `data/content/essences.json`(부위·변형), `expedition/progression/attack_wait.gd`

## 0. 결정 (2026-09-28 대화)

1. **역할군은 3개로 줄인다.** 데드셀의 빨강·보라·초록처럼 색 세 가지.
2. **색 = 발동 시점.** 빨강 = 내가 때릴 때, 보라 = 내가 대기할 때, 초록 = 내가 맞을 때. 영혼석 설명은 "무엇을"만 말한다.
3. **효과마다 아이콘.** 12개 아이콘(출혈·중독·화상·빙결·감전·저주·추가 공격·치명/조준·회복·보호·반사·소환) + 모서리 표시(없음 = 건다, ＋ = 키운다, ✸ = 터뜨린다).
4. **영혼석 = 발동 효과 1개 + 상시 보정 1줄(없을 수 있음).** 두 문장짜리("화염 피해 +30%, 15% 화상")는 이해가 쉬우니 허용한다. 캐릭터에 패시브 전용 칸은 두지 않는다.
5. **쌓는 효과는 쌓는 시점이 색.** 맞아서 쌓으면 초록, 대기로 쌓으면 보라. 쓰는 시점은 표시로 보여 준다.
6. **교체**: 같은 색끼리는 안전한 곳 어디서나 페널티 없이(빠진 영혼석은 가방으로). 다른 색으로는 휴식처에서만 덮어쓰기(옛 영혼석은 사라짐). 칸 6, 가방 3.

## 1. 3색과 발동 시점

| 색 | 이름 | 발동 시점 (문장에 쓰는 말) | 지금 데이터에서 |
| --- | --- | --- | --- |
| **빨강** | 공격 | 공격하면·적중하면·치명타면·처치하면 | `event` HIT·ATTACK |
| **보라** | 전술 | 대기하면 (조준·시전·치유·소환·다음 공격 준비) | `event` WAIT 중 피격 반응이 아닌 것 |
| **초록** | 생존 | 맞으면·피하면·막으면·쓰러질 피해를 받으면 | **새 `event` STRUCK.** 지금 "대기로 피격 반응을 준비"하는 DEFENSE 효과를 옮긴다 |

- 한 인물이 여러 색을 섞어도 된다. 섞으면 "때릴 때도, 맞을 때도" 뭔가 터지는 캐릭터가 된다.
- 연쇄(`CHAIN`)는 색이 아니다. 연쇄 효과도 자기 발동 시점의 색을 가지고, 모서리 표시(＋·✸)로 연쇄임을 보여 준다.

### 1.1 초록(STRUCK) 추가 규칙

- 유효한 직접 피격(기본 공격·적 기술의 실제 피해) 한 번에 한 번 발동한다. 지속 피해·반사 피해·자기 피해는 피격이 아니다.
- 회피·막기도 초록 발동이다(피해 0이어도 "맞을 뻔함"). 문장은 "피하면", "막으면".
- 행동당·대상당 한도는 기존 `limit`을 쓴다. 초록 반응이 만든 피해는 2차 피해라 다시 초록을 부르지 않는다.
- 지금 DEFENSE 효과 중 "대기로 다음 피격까지 방어 유지"(대기 보호막 등)는 보라로 남긴다(대기하는 행동이 핵심이므로). "대기로 준비한 피격 반응"(반사·반격 준비 등)은 준비 없이 바로 초록 STRUCK로 바꾼다. 효과별 판정은 §6 T1의 표로.

## 2. 영혼석 한 장

```
┌─────────┐  테두리 색 = 언제 (빨강·보라·초록)
│   🔥     │  가운데 아이콘 = 무엇을 (12개)
│      ＋  │  모서리 = 건다(없음) / 키운다(＋) / 터뜨린다(✸)
└─────────┘
 화염 피해 +30%   ← 상시 보정 한 줄 (있으면)
```

- 기본 스탯(`role_stats`)은 색마다 하나: 빨강 = 공격력, 보라 = 공격력·행동 속도 소폭, 초록 = 최대 HP·방어. 카드에는 쓰지 않고 상세에만.
- 상시 보정 줄은 효과 데이터의 `passive`(선택) 필드. 지금 `mods`를 쓰는 효과 중 발동과 별개로 항상 켜진 수치만.

## 3. 아이콘 체계

시안: `assets/soulstone-icons-v1/` — 생성기 `tools/art/build_soulstone_icons.py`, 래스터화 `tools/art/rasterize_svgs.gd`, 미리보기 `tools/art/soulstone_icon_preview.py`.

| 파일 | 내용 |
| --- | --- |
| `effects/<key>.svg` | 12개: `bleed` 출혈, `poison` 중독, `burn` 화상, `freeze` 빙결·둔화, `shock` 감전, `curse` 약화·저주, `extra_strike` 추가 공격, `crit` 치명·조준, `heal` 회복, `guard` 보호·방어, `thorns` 반사·반격, `summon` 소환 |
| `badges/boost.svg`, `badges/burst.svg` | ＋ 키운다, ✸ 터뜨린다 |
| `frames/{red,purple,green}.svg` | 테두리 |
| `samples/*.svg` | 색별 견본 3개 + 빨강 출혈의 표시 3단계 |
| `png/…` | 같은 구조의 128px PNG(게임·미리보기용) |

**효과 → 아이콘 규칙** (`family`와 `op`에서 자동, 예외만 데이터에 `icon` 명시)

| 조건 | 아이콘 |
| --- | --- |
| `family` bleed / poison / fire / ice / air(전기) | bleed / poison / burn / freeze / shock |
| `op` curse·weak 계열 또는 `family` will·hex | curse |
| `op` extra·second·연타 | extra_strike |
| `op` aim·attack_prep·attack_bonus, 치명 | crit |
| `op` heal_self·heal_ally·regen·drain·cleanse | heal |
| `op` bless·ally_guard·guard·방어 보정 | guard |
| `op` 반사·반격(thorns·counter) | thorns |
| `op` summon·pet_* | summon |

**모서리 표시 규칙**: `role` CHAIN이고 `op`가 burst·spread·status_area·lightning(퍼짐·폭발)이면 ✸, CHAIN이고 그 밖(대상 상태 조건의 추가 피해·강화)이면 ＋, OFFENSE·DEFENSE는 없음.

**같은 아이콘을 모든 곳에서**: 영혼석 칸·가방·드롭 선택·도감·흡수 카드, 적 머리 위 상태 표시(출혈 걸린 적 = 핏방울), 공격·대기 버튼 위 준비 표시(빨강 효과는 공격 버튼, 보라는 대기 버튼, 초록은 인물 카드).

## 4. 교체 규칙

| 상황 | 규칙 |
| --- | --- |
| 흡수 | 빈 칸에, 안전한 곳 어디서나. 칸이 다 차면 흡수 불가 |
| **같은 색 교체** | 안전한 곳 어디서나, 페널티 없음. 칸의 영혼석과 가방의 **같은 색** 영혼석을 맞바꾼다(빠진 것은 가방으로, 가방 수는 변하지 않음) |
| **다른 색으로 교체** | **휴식처에서만.** 가방의 영혼석을 찬 칸에 덮어쓰면 옛 영혼석은 사라진다 |
| 칸 비우기 | 불가 |
| 가방 | 파티 공용 최대 3. 가득 차면 드롭 창의 "가방에 넣기"가 "하나 버리고 넣기" |

- [휴식처 설계](../specs/2026-09-28-rest-stops-design.md) §1의 "교체는 휴식처에서만 덮어쓰기"를 위 표로 바꾼다(같은 색 맞바꾸기 추가).
- 같은 색 맞바꾸기는 인물 사이 이동을 허용한다(A가 빼서 가방에 넣은 것을 B가 흡수). 가방이 공용이기 때문이다.

## 5. 역할군 3개로

- 표시: 영혼석·도감·NPC·예시 빌드에서 역할군 5개(탱커·근접 딜러·원거리 딜러·캐스터·서포터)와 세부 유형 17개를 **3색 이름(공격·전술·생존)**으로 바꾼다. 세부 유형은 내부 호환용으로만 남긴다.
- NPC 시작 빌드(지금 방어·근접·원거리·마법·지원 중 무작위): 3색 중 하나. 초록 = 방어, 빨강 = 근접·원거리, 보라 = 마법·지원.
- 역할 조합 개수 보너스는 `attack_wait_v1`에서 이미 쓰지 않는다. 그대로 둔다(색 개수 보너스는 이번에 넣지 않는다).
- 도감 거르기: 3색 칩 + 아이콘 칩.

## 6. 구현 작업 (Codex)

각 작업은 자기 테스트와 커밋을 가진다. 커밋은 그 작업 파일만 `git add <경로>`.

### T1. 데이터: 색·아이콘·표시 필드와 이전
- `attack_wait_effects.json` 효과마다 `colour`(red·purple·green), `icon`(12 키), `badge`(""·boost·burst), `passive`(선택, 한 줄 문구와 수치).
- `tools/migrate_soulstone_colours.py`: §1·§3 규칙으로 채우고, **DEFENSE 중 피격 반응을 준비하는 WAIT 효과 목록**과 규칙에 걸리지 않은 효과를 출력 → 사람 검토용 표를 `docs/superpowers/plans/2026-09-28-three-colour-review.md`에 남긴다.
- `role_stats`를 색 키로(`red`·`purple`·`green`), 옛 역할 키는 읽을 때 옮긴다.
- 테스트 `tests/soulstone_colours.gd`: 모든 효과에 색·아이콘(12 중 하나)·표시, 색과 `event`의 일치(red ↔ HIT·ATTACK, purple ↔ WAIT, green ↔ STRUCK), 아이콘 파일 존재.

### T2. 초록 발동(STRUCK)
- `attack_wait.gd` `EVENTS`에 STRUCK. 피해 처리(`Session.after_damage`의 실제 피격 대상), 회피·막기 분기(`CombatRules.attack`)에서 `push(s,"STRUCK",victim,{...})`.
- §1.1 규칙(유효 직접 피격만, 한 번, 2차 피해 제외).
- T1에서 옮긴 효과들을 STRUCK로 바꾸고 준비 상태(`aw_state`의 피격 준비)를 쓰던 코드를 정리.
- 테스트: 직접 피격·회피·막기에 발동, 지속·반사·자기 피해에 불발, 한 번만, 초록 반응 피해가 초록을 다시 부르지 않음, NPC도 같음.

### T3. 아이콘 적용
- `expedition/art/soulstone_icons.gd`(새): `stone_icon(stone_id) -> Texture2D` — 테두리·아이콘·표시 PNG를 합성(캐시). `effect_icon(key)`, `status_icon(status)`.
- 교체: `mobile_art.gd`의 `part_icon`을 쓰는 영혼석 칸·가방·드롭 선택·흡수 카드·도감을 `stone_icon`으로. 적 상태 표시에 `status_icon`. 공격·대기 버튼 위 준비 표시, 인물 카드 초록 표시.
- 카드 문구: 발동 문장 1줄 + 상시 보정 1줄. 색 이름 칩.
- 테스트: 모든 영혼석이 아이콘을 얻음, 화면 노드 존재(`essence_ui`, `codex_ui`, 드롭 창), 상태 아이콘 매핑.

### T4. 교체 규칙과 가방 3
- `essences.gd`: `swap_same_colour(s, actor, slot, bag_id) -> String`(안전한 곳, 같은 색만, 가방 수 불변), `overwrite(s, actor, slot, bag_id) -> String`(`phase == "REST"`만, 다른 색 허용, 옛 것 소멸). `stone_bag_limit`(일반 3, 개발 경로 0).
- `stone_drop.gd`: 가방 가득 참 → "하나 버리고 넣기".
- 테스트: 같은 색 맞바꾸기(어디서나, 인물 사이 이동), 다른 색은 휴식처에서만, 덮어쓰기 소멸, 가방 상한, 개발 경로 무제한.

### T5. 휴식처
- [휴식처 설계](../specs/2026-09-28-rest-stops-design.md) 그대로(3·6·9층 보스 뒤, 완전 회복, 빈사 해제, 도감). 영혼석 부분은 이 문서 §4.

### T6. 역할군 3개 표시와 문서
- §5 표시·NPC 시작 빌드·도감 거르기·예시 빌드(`example_builds.json`의 `group`을 색으로).
- `docs/attack-wait-soulstones.ko.md`, `docs/soulstones.ko.md`를 새 규칙으로.
- 테스트: `role_groups`·`example_builds`·`npc_*` 스위트를 3색으로 옮김(검사 수 유지).

## 7. 검토할 것

1. 아이콘 시안(`preview.png`): 모양·색·크기, 특히 반사(가시 고리)와 저주(눈).
2. T1이 출력할 "피격 반응 준비 → 초록 STRUCK" 전환 목록.
3. 보라의 이름("전술") — 대기에 치유·소환·시전이 모두 들어가서 "전술"이 맞는지.
4. 색별 기본 스탯 수치.
