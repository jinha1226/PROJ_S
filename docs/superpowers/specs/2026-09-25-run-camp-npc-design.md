# 하강 Run · 야영 · 던전 NPC 설계

작성일: 2026-09-25 · 상태: Plan B 구현됨 (Plan A 대기: shim 2개) · 구현 계획: `.superpowers/sdd/2026-09-25-dungeon-npc/`
선행 작업(이전 코드베이스 `/mnt/d/SS`, 코드는 재사용하지 않고 설계만 계승): `docs/EXPEDITION_AID_RECRUITMENT.ko.md`(도움 → 동행 수락, 커밋 b6f38c1) · `docs/INDEPENDENT_EXPLORER_UTILITY.ko.md`(독립 탐험 NPC의 모드 효용, 유지·전환 문턱, 활동 문구)
근거: [층 생성기](2026-09-22-floor-generator-design.md) · [태세](2026-09-23-stances-design.md) · [전술 단순화·전투 시험](2026-09-24-simple-tactics-arena-design.md) · [효용 선택기](2026-09-24-utility-lookahead-design.md)

## 0. 결정 사항

사용자와 합의한 결정. 이 문서의 나머지는 이 목록의 귀결이다.

1. **마을·귀환 없음.** Run은 1층에서 혼자 시작해 주인공이 죽을 때까지 내려가는 한 번의 하강이다. 상점·보급·유물 회수·입구 귀환·정착지·자금은 없다.
2. **자원은 식량 하나.** 용도는 던전 안 **야영**뿐이며, 식량이 파티 인원 이상일 때만 야영할 수 있다. 행동 20회당 소비·굶주림 게이지는 없앤다.
3. **횃불·빛 없음.** 횃불 아이템, 빛 0~100 게이지, 어둠 피해·전리품·드롭 보정, 어둠 스트레스 전부 삭제. 시야는 고정.
4. **상태는 HP와 스트레스만.** 부상·약초·붕대·목재·도구(열쇠·삽) 없음. **물약·두루마리는 던전에서 줍는 소모품 아이템으로 유지**(구매 없음, §2.3).
5. **층은 지금의 절차 생성 층**(연속 층)을 이어서 내려간다. 3×3 방 지도·방 모드·보스 시련 *모드*는 삭제하되 **보스 세 종은 보스 층으로 남긴다**(§4.4). 3인 파티 기준으로 층을 넓힌다.
6. **NPC는 던전 안에서 스스로 활동한다.** 혼자 시작해 던전에서 영입한다. 활동은 NPC 자신의 감각(시야·소음)으로 깨어났을 때만(§5.3). 층당 3~5명, Run 전체 명부에서 배치. **2인 조** 포함.
7. **영입은 성격이 정한다.** 외향형은 먼저 다가와 제안하고, 내향형은 플레이어가 탭해 말을 건다(§5.5). 파티 최대 3인.
8. **전투 AI는 그대로.** 태세·효용·룩어헤드·실수는 손대지 않는다. NPC도 같은 선택기로 움직인다.
9. **전투 시험 모드는 유지.** 시작 화면에서 진입.

## 1. Run 구조

### 1.1 흐름

```
시작 화면 ──[새 Run]──▶ 1층(혼자, EXPLORE) ──▶ … ──[내려가는 길]──▶ 2층 ──▶ … ──▶ 주인공 사망 ──▶ 결과 화면 ──▶ 시작 화면
     └──[전투 시험]──▶ ArenaSetup(기존)
```

- `Session` 단계: `EXPLORE` · `BATTLE` · `CAMP` · `DEFEAT`. `TOWN`·`EVENT`는 삭제한다.
- Run 시작: `Session.new_run(seed)`. 주인공 1명(HP 55, 스트레스 0, 성격 `Hexaco.generated(seed, 1)`), 가방에 밀치기·엄호 요령(`STARTING_PARTS`), 슬롯 빈칸, 식량 2. 1층을 생성하고 입구에 선다.
- 층 번호 `s.depth`(1부터). `expedition_number`는 삭제하고 기억 기록·실수 시드에는 `depth`를 쓴다(`Hexaco.sample(seed, depth*100000 + round*100 + id, …)`).
- Run 종료: 주인공(`party[0]`) 사망 즉시 `DEFEAT`. 동료만 죽으면 계속. 최종 목표(보스·유물)는 이번 범위 밖(§9).

### 1.2 결과 화면

도달 층 · 라운드 수 · 처치 수 · 함께한 동료 목록(이름, 합류 층, 최후: "n층에서 전사" / "생존") · 실수 횟수 합계. 버튼: 새 Run · 시작 화면.

## 2. 자원과 상태

### 2.1 식량

- `s.food: int`. 시작 2. 상한 없음.
- 소비는 야영(§3)에서만: 인원수만큼.
- 획득처는 층의 **조사물**과 몬스터 드롭. 기존 큐리오(잠긴 상자·흙더미)와 도구는 다음 4종으로 교체한다. 층당 배치 수는 테마 JSON `curios`에 둔다.

| 조사물 | 결과 | 층당 |
| --- | --- | --- |
| 버려진 보급 상자 | 식량 +2~3 | 1~2 |
| 버섯 군락 | 식량 +1~2, 30%로 채집자 HP −4("독성") | 1~2 |
| 죽은 모험가 | 식량 +1, 30%로 파츠 아이템 1(`roll_part`), 30%로 소모품 1 | 0~1 |
| 부서진 궤짝 | 파츠 아이템 1 또는(50%) 소모품 1 | 1 |

- 몬스터 드롭: 짐승 종족(쥐·도마뱀 계열, `species_catalog`의 `beast` 태그)은 처치 시 25%로 식량 +1. 기존 파츠 드롭(`DROP_PERCENT`)은 그대로.
- 조사는 지금처럼 인접 탭 → 선택 팝업(조사 / 지나간다). 자동 획득 없음.

### 2.2 상태

- `hp/max_hp`, `stress`(0~200, 불안 ≥ 100·붕괴 ≥ 150 — 기존 실수 배수 그대로).
- 스트레스 원천: 기존 전투 원천(피해·아군 쓰러짐)과 §5의 NPC 사건. 굶주림·어둠 원천은 삭제.
- 삭제: `hunger`, `exploration_tools`, `torches`, `light`, `bank`, `loot`(자금), `free_provisions`/`purchases`. 처치·조사 점수는 결과 화면용 `s.score`로 대체.

### 2.3 소모품

- `supplies` 배열은 남기되 **5종**: 치유 물약(HP +20), 정신 안정제(스트레스 −25), 활력 물약(스트레스 −10·HP +5 — 굶주림이 없어졌으니), 화염 두루마리, 물 두루마리. 붕대(6번째)는 삭제. 시작 보유 0.
- 획득: 부서진 궤짝은 50%로 파츠 대신 소모품 1(무작위); 죽은 모험가는 30%로 소모품 1; 보급 상자는 20%로 소모품 1. 몬스터 드롭 없음.
- 사용은 지금처럼 가방(`use_supply`)에서. 야영에서도 쓸 수 있다.

## 3. 야영

- 조건: `phase == "EXPLORE"`, 파티 시야에 적 없음, `food >= alive().size()`. HUD의 **야영** 버튼은 조건이 참일 때만 활성(비활성 시 툴팁 "식량 n 필요" / "적이 보임").
- 효과(즉시, 라운드 소비 없음): `food -= alive().size()`; 전원 `hp += ceil(max_hp*0.5)`(상한 max_hp); `stress -= 30`(하한 0); 파츠 쿨다운 초기화.
- 야영 화면(`CAMP` 단계): 멤버 카드 ×인원(HP·스트레스·태세 3버튼·파츠 슬롯 2) + 가방 목록. **파츠 장착·교체·해제는 여기서만**(`equip_part/unequip_part`의 TOWN 조건을 CAMP로). "야영 끝" → `EXPLORE`.
- 층당 횟수 제한 없음. 야영 중 습격 없음(§9).
- 야영 위치는 어디든(입구 야영지 템플릿은 그대로 두되 특별 효과 없음).

## 4. 층과 하강

### 4.1 내려가는 길

- 필수 템플릿 `relic_vault`를 **`descent`**(내려가는 길)로 교체: 방 안에 특징 `{"kind":"stairs"}` 1칸. `entry_camp`·`sealed_treasury`는 유지(`sealed_treasury`의 보상은 파츠 궤짝).
- 계단 인접 탭 → 팝업 "n+1층으로 내려간다 / 아직" → 내려가면 `s.descend()`: `depth += 1`, 새 층 생성(시드 `seed + depth*7919`), 파티는 새 입구에, 적·조사물·NPC 배치는 새로, HP·스트레스·식량·가방·기억은 유지. 되돌아올 수 없다(입구 특징은 장식).
- 테마: `depth 1` = `F1_RUINS`, `depth 2` = `F2_MINES`, `depth ≥ 3` = 두 테마 번갈아(홀수 RUINS, 짝수 MINES) + 몬스터 예산 ×(1 + 0.25·(depth − 2)) 반올림. `Objective`(유물) 코드는 삭제.

### 4.2 파티 기준 층 크기

`floor_themes.json` 두 테마 공통으로:

| 항목 | 지금 | 변경 |
| --- | --- | --- |
| `size` | 64 | 80 |
| `rooms.count` | 10~12 | 13~16 |
| `plain_size` | 5×5 ~ 8×7 | 6×6 ~ 9×8 |
| `fight_size` | 9×9 ~ 12×10 | 10×10 ~ 13×11 |
| 복도 폭 | 1 | 2 (생성기 `corridor.width`, 검증에 "모든 복도 칸은 폭 2 이상" 추가) |
| NPC 방 | — | `npc_rooms` 3~5: 조우가 없는 일반 방 중 입구에서 먼 순으로 |

`tests/floor_generator.gd`의 시드 0~99 검증은 새 값으로 그대로 돈다.

### 4.3 자동 이동

층이 커진 만큼 탭 이동을 경로 이동으로 바꾼다: 시야 안(또는 기억한) 칸을 탭하면 A* 경로로 한 라운드에 한 걸음씩 자동 진행, 적이 시야에 들어오거나(`BATTLE_START`) 조사물·계단·NPC에 인접하면 멈춘다. 기존 "인접 칸 탭 = 한 걸음"은 그대로 포함된다.

### 4.4 보스 층

- `depth % 3 == 0`인 층은 `descent` 대신 필수 템플릿 **`boss_lair`**(14×12, 계단 `>`, 전력탑 `Y`, 물웅덩이 `~` 2칸, 문 2)를 쓴다. 보스는 기존 보스 시련의 세 패턴을 `(depth/3 − 1) % 3` 순서로: 수렁 포식자(물에서 회복, 반경 2 폭발 예고) → 폭탄 암살자(대상 중심 3×3 예고 후 모서리 순간이동) → 과부하 거인(HP 절반에서 보호막, 전력탑 인접 탭으로 해제). HP 64 + 8·(depth/3 − 1). 처치 시 파츠 드롭 100%.
- 보스 패턴 코드는 `expedition/boss_ai.gd`로 옮긴다: 방 모드의 `rooms[room]` 상태(`pattern/shield/pylon/overloaded`) 대신 보스 액터 자신의 필드에 들고, 예고는 층의 `s.intents`에 다른 몬스터와 같은 형식(`{id, cell, damage, kind:"BOSS"}`)으로 넣어 룩어헤드·태세가 그대로 읽는다. `MonsterAI.turn`은 `enemy.get("boss",false)`면 `BossAI.turn`으로 넘긴다.
- 계단은 보스가 살아 있는 동안 "봉인됨". 보스 층에는 NPC 배치 없음(§5.2).

## 5. NPC

### 5.1 명부

- Run 시작 시 NPC **10명** 생성(`s.roster: Array`), 각각 `{id: 1000+i, name, profile: Hexaco.generated(seed, 1000+i), stance: Stances.default_stance(profile), hp, max_hp 55, stress: 0~40, equipped_abilities: [파츠 0~1], rules, memory: Memory.new(), partner: id | -1, bond: "close"|"strained"|"", state: "UNMET"|"MET"|"PARTY"|"DEAD", floor_seen: int}`.
- 이름은 `data/content/npc_names.json`(20개)에서 시드로 중복 없이.
- 파츠: 40%로 카탈로그에서 무작위 1개 장착(`default_rule` 포함).
- **2인 조**: 10명 중 2쌍(4명). `partner` 상호 지정, `bond`는 60% `close` / 40% `strained`.
- 파티 멤버는 `party`에 옮겨 담고 명부 `state = "PARTY"`. `party[0]`은 언제나 주인공.

### 5.2 층 배치

- 층당 배치 수: 1층 3명, 2층부터 4~5명(시드). 명부에서 `state != "PARTY"/"DEAD"`인 NPC를 `UNMET` 우선으로 뽑는다. 2인 조는 둘 다 자유로울 때 같은 방에 함께 배치.
- 배치 방은 §4.2 `npc_rooms`. 상황은 셋 중 하나:

| 상황 | 위치 | 상태 |
| --- | --- | --- |
| 교전 중 | 조우 방 옆 NPC 방에 몬스터 무리 1개(예산 3) 추가 배치, NPC는 무리와 거리 2 이내 | HP 60~80%, 50% 굶주림 |
| 부상 | NPC 방, 혼자 | HP 30~50%, 스트레스 +30, 50% 굶주림 |
| 휴식 | NPC 방 | HP 그대로 |

- 다시 만나는 NPC(`MET`)는 이전 HP에서 10~30% 깎여 배치(그동안 싸웠다).
- NPC는 층의 액터 목록 `s.npcs`에 들어간다(`party`·`enemies`와 별개).

### 5.3 감각과 깨어남

- NPC 시야 = `MonsterAI.sight(s)`(4~6칸, 대칭 시야 규칙과 동일). 소음 반경 10칸(`s.distance`).
- **깨어남**: (a) NPC 시야에 파티원이 있거나, (b) 소음 반경 안에서 전투(`BATTLE` 단계의 피해 사건)가 났을 때. `npc.awake = true`.
- **잠듦**: 파티 시야 밖이고 소음 없이 5라운드 지나면 `awake = false`. 잠든 NPC는 행동하지 않고 시뮬 비용 0.
- 깨어 있는 NPC는 파티 시야 밖에 있어도 행동한다(다가오는 장면을 위해).

### 5.4 행동

깨어 있는 NPC는 매 라운드(파티 차례 뒤, 적 차례 앞) 한 번 행동한다.

- **전투 중(자기 시야에 적)**: `Tactics.choose(s, npc)`를 그대로 쓴다. 이를 위해 아군 판정을 한 곳으로 모은다: `s.friends(actor)` = 파티 생존자 + 깨어 있는 NPC(전원 서로 아군). 태세·효용·룩어헤드·규칙(`alive()`를 아군으로 쓰는 곳)과 몬스터 AI의 표적(`targets`)이 이 함수를 쓴다. 즉 깨어 있는 NPC는 전투에서 파티 편이고, 몬스터도 NPC를 노린다. 명령(집중 공격·후퇴)은 받지 않는다 — 다만 집중 공격 표적은 공유 휴리스틱이라 NPC도 따른다(명령이 아니다). 실수 규칙도 적용.
- **전투 아님 — 활동 모드**: 이전 코드베이스의 독립 탐험 NPC 효용을 우리 `Utility` 코어로 다시 만든다. 모드 4개를 `tactics_profiles.json`의 새 표 `npc_modes`에 두고 `Utility.score`로 고른다(정수 가중합, 결정론, 설명 상위 3). 유지 10라운드, 80점 이상 차이면 즉시 전환(이전 설계의 300시간·80점을 라운드로 옮김).

| 모드 | 행동 | 주요 고려 사항(입력 0~1 / 부호) |
| --- | --- | --- |
| `APPROACH` | 파티 쪽으로 한 걸음(`steps_toward`), 인접하면 제안(§5.5) | `X`(+), `A`(+), `wounded`(+), `party_room`(파티 인원/3, −: 자리 없으면 덜), `declined`(−, 거절 기억) |
| `HOLD` | 파티와 거리 3~5 유지(`in_band`식) | `X`(−), `C`(+), `declined`(+) |
| `REST` | 제자리 대기 | `wounded`(+: HP < 40%), `stress`(+) |
| `EXPLORE` | 층의 방 중심을 순회(입구에서 먼 방부터, 시드 순서) | `O`(+), `hp_ratio`(+), `party_seen`(−: 파티가 시야에 있으면 덜) |

  - 2인 조는 뒤처진 쪽이 파트너에게 한 걸음(모드보다 우선).
  - 활동 문구를 NPC 카드에 한 줄로: "다가오는 중" / "거리를 두고 지켜보는 중" / "부상으로 대기 중" / "주변을 탐색 중" / "교전 중". 설명(`explain`)은 `battle_stats`처럼 `npc.explains`에 최근 20개.
- NPC가 전투에서 죽으면 명부 `DEAD`, 결과 화면 이력에 남는다.

### 5.5 영입

세 갈래가 있다. **도움**은 확정, 나머지는 성격 확률.

- **도움 → 동행**(이전 설계 계승, 물약 대신 식량): 인접한 NPC가 부상(HP < 50%)이거나 굶주림 상태(`npc.hungry`, 배치 상황 "부상"·"교전 중"의 절반에 부여)면 대화 팝업에 **[식량 1 나누기]**가 뜬다. 나누면 `food −1`, NPC HP +10 또는 굶주림 해제, NPC 기억 `AID_RECEIVED`(기존 KIND, 중요도 500). 도움받은 NPC는 그 뒤 **[동행 제안]**에 확률 없이 수락한다(자리가 있을 때). 도움은 정원이 차 있어도 줄 수 있고 수락 권한은 층을 넘어도 유지된다.
- **제안 팝업**(NPC 발, `APPROACH` 모드로 인접했을 때): 한 줄 대사 + [동행] [거절]. 파티가 3명이면 [거절]만 있고 대사는 "자리가 없군". 거절하면 NPC 기억에 `DECLINED_BY_PLAYER`(중요도 400), 20라운드 동안 다시 제안하지 않음.
- **말 걸기**(플레이어 발): 인접한 NPC 탭 → 팝업(대사 + [동행 제안] [식량 1 나누기(조건부)] [닫기]). 도움 기억이 없으면 수락 확률로 답한다:
  - `chance = 60 + (X + A − 1000)/25 + (15 if hp < 50%) − (25 if DECLINED_BY_PLAYER 기억 있음)`, 0~95로 자름.
  - 판정 `Hexaco.sample(seed, depth*100000 + round*100 + npc.id, "recruit", 100) < chance`. 결정론.
  - 거절당하면 NPC 기억 `DECLINED_PLAYER`(중요도 300), 주인공 기억에도 같은 기록(instigator = npc). 20라운드 뒤 재시도 가능(그때는 chance −10 추가).
- **합류**: `party.append(npc)`, 명부 `PARTY`, 진형 끝에. 기억 `RECRUITED`(양쪽, 중요도 500). NPC의 파츠·규칙·태세는 그대로 들어온다(태세는 성격 탭에서 바꿀 수 있음). 합류한 NPC는 `s.npcs`에서 빠져 두 AI가 동시에 돌지 않는다.
- **2인 조 규칙**: 한 명이 합류하려 할 때 파트너가 같은 층에 살아 있으면
  - `close`: 둘이 같이 온다. 자리가 2개 없으면 합류 거절("얘를 두고는 못 가").
  - `strained`: 파트너는 남는다. 남는 쪽 기억 `LEFT_BY_PARTNER`(중요도 600), 떠나는 쪽 스트레스 +10. 남은 파트너는 `MET`으로 명부에 남아 뒤 층에서 다시 나올 수 있다.
- `Memory.KINDS`에 `RECRUITED`, `DECLINED_BY_PLAYER`, `DECLINED_PLAYER`, `LEFT_BY_PARTNER` 추가(`AID_RECEIVED`는 기존).
- 동료 내보내기·이탈은 범위 밖(§9). 파티가 3명이면 새 영입은 누가 죽기 전까지 불가.

## 6. UI

- **시작 화면**: 제목 · [새 Run] · [전투 시험]. 마을 화면(`show_town_*`, 훈련·요양·상점·보급)은 삭제. 전투 시험은 지금처럼 별도 세션(`town_session` → `menu_session`으로 이름만).
- **HUD**: 기존 멤버 카드·▶/⏸·속도·후퇴·가방 + **식량 n** 표시 + **야영** 버튼. 횃불 버튼 삭제. 상단 위치 표시는 "n층".
- **NPC 표시**: 보드에 이름표가 붙은 아군색 토큰. 인접 탭 → 대화 팝업(§5.5). 비인접 탭 → 카메라만.
- **야영 화면**: §3.
- **결과 화면**: §1.2. 전투 결과 카드(`BattleReport`)는 그대로.
- 전투 중 NPC는 멤버 카드에 나오지 않는다(파티가 아님). 로그에는 "이름 · 행동"으로 찍힌다.

## 7. 삭제 목록

코드: `dungeon_map.gd`, 방 모드(`floor_mode == false` 분기 전부 — `floor_mode` 변수 자체 제거), `boss_trial.gd`(패턴은 `boss_ai.gd`로 이식 후 삭제), 지형 레이아웃 4종, `expedition_objective.gd`, `settlement_hub.gd`/마을 함수(`return_home`, `finish_expedition`, `rest_town`, `refit`, 상점·보급·`MIN_KIT`·`provision_*`·`buy/refund/price/stock`·`bank`), 횃불·빛(`torches`, `light`, `light_tier/loot_percent/drop_percent/enemy_bonus/sight_side/sight_radius/darkness_strength`, `ambush`의 어둠 조건), `hunger`·행동 20회 식량, `exploration_tools`·큐리오 도구, 붕대, `expedition_number`. `Session.new(seed, _, _, _, party_size)`와 `depart()`는 시그니처를 유지한다(30여 스위트의 픽스처가 쓴다): `depart()`가 곧 "Run 시작 = 1층 생성"이다.
데이터: `balance_experiments.json` 아레나의 `light` 필드(시뮬 러너는 고정 시야로), `exploration_curios.json` → 새 4종.
테스트(삭제): `boss_trial`(→ `boss_floor`로 대체), `terrain_layouts`, `torch_vision`, `torch_tradeoff`, `solo_provisioning`, `expedition_settlement`, `solo_recovery`(마을 요양 검사). `curios`·`mobile_exploration`·`playthrough`·`integration`은 새 흐름으로 재작성. CI 목록 갱신.

## 8. 검증

새 스위트(CI 등록):

- `run_start`: 시작 화면 → 새 Run → 1층 혼자·식량 2·슬롯 빈칸·가방에 요령 2; TOWN 단계 부재; 전투 시험 진입 유지.
- `camping`: 조건(적 시야·식량 부족·전투 중) 각각 거부; 효과 수치; 야영에서만 장착; 야영 뒤 EXPLORE.
- `floor_descent`: 계단 상호작용 → depth+1, 테마 교대, 예산 배율, 파티·식량·가방·기억 유지, 새 층 검증 통과(시드 0~19).
- `floor_generator`(갱신): 새 크기·복도 폭 2·`npc_rooms` 3~5, 시드 0~99; `boss_lair`가 depth 3의 필수 템플릿.
- `boss_floor`: 3층 생성에 보스 1·계단 봉인, 세 패턴의 예고가 `s.intents`에 실림(룩어헤드가 읽음), 거인 보호막·전력탑, 처치 후 계단 개방·파츠 드롭.
- `items`(기존 스위트 갱신): 소모품 5종 사용, 붕대 없음, 야영 중 사용 가능, 조사물에서 획득.
- `npc_sense`: 시야로 깨어남, 소음으로 깨어남, 5라운드 뒤 잠듦, 잠든 NPC는 행동 없음, 깨어 있는 NPC가 시야 밖에서 다가옴.
- `npc_behaviour`: 전투 중 태세대로 행동(`friends` 포함 — 엄호·공유 목표), 몬스터가 NPC를 노림; 활동 모드 효용(외향 → APPROACH, 내향 → HOLD, 부상 → REST, 개방 높고 파티 안 보이면 EXPLORE; 유지 10라운드·80점 전환; 결정론; 활동 문구), 2인 조 인접 우선, NPC 사망 → 명부 DEAD.
- `recruit`: 식량 나눔(food −1, AID_RECEIVED, 정원 차도 가능, 확률 없는 수락, 층 넘어 유지); 외향 선제안·내향 탭; 수락 확률 공식과 결정론; 거절 기억과 20라운드 쿨다운; 최대 3인; 2인 조 close(둘 다/자리 부족 거절)·strained(남는 쪽 기억·스트레스); 기억 KINDS 4종.
- `npc_roster`: 10명·2쌍·이름 중복 없음; 층 배치 수(1층 3, 이후 4~5); MET 재등장 시 HP 감소; PARTY/DEAD 제외.
- `auto_move`: 경로 이동과 정지 조건 4종.

게이트: 어둠 보정이 사라지므로 `solo_balance`(≥ 3/8), `stance_gate`, `ranged_probe`, `utility` 재측정 후 `docs/balance/`에 기록. 시뮬 러너의 `light` 제거로 수치가 움직이면 프로필 가중치가 아니라 몬스터 예산으로 맞춘다(AI는 손대지 않는다).

## 9. 범위 밖 (다음 스펙)

동료 이탈·내보내기, NPC 간·동료 간 관계 이벤트(야영 대화), 귀환 투표(귀환이 없으므로 "야영하자/계속 가자" 갈등으로 변형 예정), 야영 중 습격, 최종 목표(보스·유물)와 Run 성공, NPC끼리 싸우는 적대 NPC, 자동 탐험, 층 테마 추가.
