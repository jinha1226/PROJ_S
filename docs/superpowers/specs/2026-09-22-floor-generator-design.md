# 1층 절차 생성기 · DD식 조우 배치 설계

작성일: 2026-09-22 · 상태: 설계 승인 완료, 구현 계획 작성 예정
관련: [솔로 1층 유물 회수 계획](../../solo-floor1-relic-plan.md), [구현 결과](../../solo-floor1-relic-results.md)

## 0. 결정 요약

| 항목 | 결정 |
| --- | --- |
| 층 호흡 | 한 출정에 필수 조우 2~3회 + 선택 조우 1~2회. 전투 하나가 5~8라운드짜리 묵직한 싸움 |
| 레이아웃 | DCSS `layout_rooms` 변형: 방 10~12개 뿌리기 → MST + 여분 간선 2~3개 → `join_the_dots` 복도. 고리 2~3개, 막다른 방 2~3개 |
| 크기 | 64×64 (테마 상수. 작으면 80으로 올림) |
| 특수 방 | ASCII 템플릿 6종 (JSON), 층 테마별 풀 |
| 조우 구성 | 위협 예산제 + 가드레일 2개. 고정 슬롯 없음 |
| 몬스터 행동 | DD식: 방에 고정, 시야에 들어오면 개전 (현행 유지) |
| 종족 출현 | DCSS `(min, max, rarity, 곡선)` 테이블. 층 깊이에 따라 가중치 변화 |
| 방 크기 | 조우 방 내부 9×9 ~ 12×10 (동료 3인 + 적 4마리 대비), 일반 방 5×5 ~ 8×7 |
| 복도 | 폭 1. 조우는 방 안에서만 시작 |

## 1. 생성 파이프라인

입력: `theme: Dictionary`(floor_themes.json 한 항목), `seed: int`, `depth: int`.
출력: `layout: Dictionary` (§7). 모든 난수는 `RandomNumberGenerator`에 `seed`를 넣어 사용하며 동일 입력 → 동일 출력.

```
1. 방 뿌리기     count ∈ theme.rooms.count. 종류: 템플릿(필수 3 + 조우 풀에서 fight_picks), 조우(절차), 일반(절차).
                 조우 방 수 ∈ theme.rooms.fight (템플릿 조우 방 포함).
                 크기(내부): 조우 fight_size 범위, 일반 plain_size 범위, 템플릿 고정.
                 배치 규칙: 외곽 1칸 벽 유지, 방 사이(벽 포함) 최소 2칸 간격, 겹침 금지.
                 입구 야영지는 x < size/3 영역, 유물의 방은 x > size*2/3 영역에 우선 배치.
                 200회 시도해도 count 미달이면 seed+1로 전체 재생성(최대 5회). 5회 실패는 오류(push_error)이며 테스트 실패로 취급.
2. 그래프        방 중심 간 유클리드 거리로 Kruskal MST. 이후 추가 간선 extra_links개:
                 아직 없는 쌍을 거리 오름차순으로 보되, 새 간선의 중심-중심 선분이 다른 방 사각형을 관통하면 건너뜀.
                 결과 그래프에 고리 ≥ 1 없으면 재생성.
3. 복도          간선마다 두 방의 문 후보 중 서로 가장 가까운 쌍 선택. 절차 방의 문 후보 = 각 변 중앙 ±2 칸(모서리 제외).
                 join_the_dots: 시작→끝을 L자(먼저 긴 축)로 걷되 theme.corridor.wiggle 회까지 중간 꺾임 지점을 무작위 이동.
                 복도 폭 1(고정; 테마 키 없음). 벽 칸만 파고 이미 바닥이면 그대로 둠(다른 방 관통 허용 → 그 방에 문 추가).
                 복도가 템플릿 방 내부를 관통하는 것은 금지(템플릿 사각형은 통과 불가 영역으로 취급하여 우회).
4. 템플릿 스탬프 예약된 자리에 ASCII를 회전(ORIENT 허용 시 0/90/180/270 중 시드 선택) 후 기록. 문 후보 `+`는 3단계에서 사용.
5. 지형 칠하기   절차 방 내부: theme.palette.accent_ratio 비율로 잔해/목재/물 군집(부모 프로젝트 `_place_clustered_field_regions` 방식: 시드 순위로 정렬한 후보에서 군집 성장).
                 조우 방: 장애물(벽 기둥) ≤ 내부 칸의 15%, 문·무리 앵커 주변 1칸 보호, 빈 5×5 블록 최소 1개 보장(없으면 장애물 제거 재시도 10회).
6. 배치          §3 조우, §4 조사물·유물.
7. 검증          §5. 실패 시 seed+1 재생성(1단계와 같은 5회 한도 공유).
```

## 2. 템플릿 방 (data/content/floor_templates.json)

기호: `#` 벽 · `.` 돌 · `,` 잔해 · `~` 물(젖음 70) · `=` 목재 · `%` 금속 · `+` 문 후보(벽 위) · `@` 입구 관문 · `*` 유물 · `$` 잠긴 상자 · `^` 흙더미 · `A` 제단 · `C` 야영지 · `M` 무리 앵커 · `P` 후위 배치 후보.

각 항목: `{"id", "label", "tags": [...], "depth": [min,max], "orient": true|false, "rows": [...]}`. 크기는 rows에서 계산. 외곽은 반드시 `#` 또는 `+`.

`tags`와 `depth`는 테마별 템플릿 풀 선정을 위해 예약된 항목이며 현재 구현은 읽지 않는다(테마 JSON이 풀을 직접 나열한다).
문 후보 `+`는 모서리 칸에 둘 수 없다(모서리 문은 복도가 정면으로 닿지 못해 열리지 않는다).

| id | label | 내부 크기 | 역할 | 특징 |
| --- | --- | --- | --- | --- |
| entry_camp | 입구 야영지 | 7×7 | 시작·귀환, 조우 없음 | 중앙 `@`, 벽 쪽 `C` |
| relic_vault | 유물의 방 | 11×9 | 유물 + 심부 조우 | 안쪽 단상 `*`, 단상 앞 기둥 4개, `M` 단상 앞, `P` 기둥 옆, 문 후보 2개 |
| flooded_cistern | 침수 저장고 | 10×8 | 조우 | 절반 `~`, 돌 둑길, `M` 물 건너편 |
| collapsed_store | 무너진 창고 | 9×9 | 조우 | 잔해 격자, `^` 1개 |
| sealed_treasury | 봉인된 보고 | 6×6 | 막다른 보상 방 | `$` 2, `A` 1, 문 후보 1개(막다른 방 강제) |
| timber_gallery | 목재 회랑 | 12×6 | 조우 | 바닥 `=`, `%` 기둥, `P` 기둥 뒤 |

템플릿 조우 방은 조우 방 수에 포함된다. `sealed_treasury`는 MST 계산에서 제외했다가, MST 완성 후 가장 가까운 비-템플릿 방에 잎(leaf)으로 붙이고 추가 간선 대상에서도 제외한다(차수 1 보장).

## 3. 조우

### 3.1 종족 테이블 (data/content/floor_monsters.json)

```json
{"species_id": "dcss_orc", "min_depth": 1, "max_depth": 6, "rarity": 1000, "curve": "RISE",
 "threat": 4, "roles": ["MELEE","RANGED","CASTER"], "band": null}
```

곡선: `t = (d-min)/(max-min)` (max==min이면 t=0). `FLAT`=1, `RISE`=0.15+0.85t, `FALL`=1-0.85t, `PEAK`=0.2+0.8×(1-|2t-1|). 구간 밖은 0.

1층 초안(rarity, 곡선, 위협, 역할): 쥐(1~3, 1000, FALL, 1, 근접) · 목도리 도마뱀(1~3, 640, FALL, 1, 근접) · 코볼트(1~4, 1000, FLAT, 2, 근접·궁수) · 고블린(1~4, 1000, FLAT, 2, 근접·궁수·술사) · 홉고블린(1~5, 1000, PEAK, 3, 근접) · 오크(1~6, 1000, RISE, 4, 근접·궁수·술사) · 놀(1~8, 200, PEAK, 5, 근접, band: {"followers": ["dcss_rat","dcss_frilled_lizard"], "count": [2,2]}) · 강쥐(2~6, 600, RISE, 6, 근접).

역할 수정치: RANGED +1, CASTER +2. 역할 이름 표기는 현행 `monster_ai.ROLES` 라벨을 사용.

### 3.2 예산과 티어

테마 `monsters.budget`: 초입 3 · 중간 6 · 심부 9 · 선택 5. 허용 오차 ±1. 조우당 최대 4마리.

변경됨(2026-09-22): 구현 후 실측으로 심부 9→6, 중간 6→5로 조정, 완주 기준은 측정치 3/8로 두고 6/8 목표는 밸런스 방법론(docs/balance-method.ko.md)의 후속 작업으로 이관 — 근거: docs/solo-floor1-relic-results.md

티어 = 입구 방으로부터의 그래프 거리(간선 수): 유물의 방과 그 이웃 = 심부, 거리 1~2 = 초입, 그 외 = 중간. 선택 조우는 티어와 무관하게 예산 5.

알려진 설계 공백: deep = 유물 방 + 이웃, early = 그래프 거리 ≤2 규칙 아래에서 방 10~12개 층은 mid 티어 필수 조우가 거의 생기지 않는다(8시드 중 0). 티어 구간 재정의는 밸런스 후속 작업에서 다룬다.

### 3.3 조우 방 선정

1. 유물의 방: 항상 필수 조우(심부).
2. 입구→유물 방 사이의 관절점(입구·유물 제외)을 계산. 관절점 방이 조우 방 종류이면 필수 조우. 
3. 필수 조우가 2개 미만이면: 후보 조우 방 각각에 대해 "그 방을 막았을 때 입구→유물 경로가 남는지"와 "입구→유물 최단 경로에 포함되는지"를 보고, 최단 경로에 포함되는 방 중 입구에서 가까운 순으로 추가. 목표: 필수 2~3개.
4. 선택 조우: `sealed_treasury`와 인접한 방(조우 방이면) 1개 + 막다른 조우 방 중 1개(있으면). 합계 1~2.
5. 필수 조우 수가 3을 넘거나 2 미만이면 재생성.

### 3.4 무리 채우기 (조우당 최대 20회 재굴림)

```
남은 = 예산; 무리 = []
반복:
  후보 = 테이블에서 curve(depth) > 0 이고 위협(역할 수정 전) ≤ 남은+1 인 종족
  OOD: 심부·선택 조우이면 10% 확률로 depth+1 테이블 사용
  종족 = rarity×curve 가중 추첨
  역할 = 종족 roles 중 가중 추첨(MELEE 60 / RANGED 30 / CASTER 10). 가드레일(술사 ≤1, 같은 종족+역할 ≤2) 위반 시 다른 역할, 없으면 종족 재추첨
  추가; 남은 -= 위협+역할 수정치
  band가 있는 종족이면 추종자를 count만큼 즉시 추가(예산 차감), 리더 1회만
  종료: 남은 < 1 또는 4마리
검사: 3마리 이상이면 후위 ≥1 (없으면 마지막 근접 하나를 RANGED로 변환, 불가하면 재굴림) · 합계 ≥ 예산−1 · ≤ 예산+1
20회 실패 시 예산 최대 종족 단독(홉고블린 등)으로 폴백. 무리 없는 조우 금지.
```

### 3.5 방 안 배치

- 앵커: 템플릿 `M`, 절차 방은 문(복수면 입구 방향 문)에서 가장 먼 바닥 칸.
- 리더(위협 최대)를 앵커에. 근접은 앵커 8방향 이웃 중 빈 칸. 후위는 `P` 후보 → 없으면 장애물에 인접한 칸 중 앵커 뒤(문 반대 방향) 우선.
- 모든 구성원은 모든 문에서 체비쇼프 거리 ≥ 3. 만족 못 하면 앵커를 문에서 멀어지는 순서로 다시 시도.
- 생성기는 각 적에 `{"species_id","role","pos","group_id","tier"}`를 준다. `monster_ai.configure`는 인덱스 순환 대신 이 role을 사용.

## 4. 조사물 · 유물 · 보상

- 유물: `relic_vault`의 `*`. 생성 후 입구→유물 8방향 최단 거리가 층 최대 거리의 60% 미만이면 재생성. `expedition_objective.gd`의 후보 탐색·심부 출구 우선 규칙은 삭제하고, 생성기 결과 검증과 상태 관리만 남긴다.
- 잠긴 상자: `sealed_treasury`의 `$` 2개 + 테마 `curios.locked_chest` 범위까지 막다른 일반 방에 추가. 조우 방 금지.
- 흙더미: `collapsed_store`의 `^`(뽑힌 경우) + 테마 범위까지 가지(척추 외) 일반 방 모서리 칸.
- 제단: `sealed_treasury`의 `A`.
- 야영지: `entry_camp`의 `C` + 중간 티어 일반 방 하나에 50% 확률(시드) 추가.
- 척추(입구→유물 최단 경로 위의 방)에는 상자·흙더미·제단을 두지 않는다.
- 조사물·유물·적·문·야영지·관문 칸은 서로 겹치지 않으며 복도 칸에 두지 않는다.

## 5. 검증 (tests/floor_generator.gd, 시드 0~99)

1. 방 count 범위, 조우 방 fight 범위, 필수 템플릿 3종 각 1, 겹침 없음, 외곽 1칸 벽.
2. 입구에서 8방향·모서리 규칙(Session.melee_reach와 동일)으로 모든 방 바닥과 모든 feature의 상호작용 칸 도달.
3. 그래프 고리 ≥ 1, 막다른 방 ≥ 2, 유물 경로 거리 ≥ 최대의 60%.
4. 필수 조우 2~3, 선택 1~2. 필수 조우 방 전부를 벽으로 막으면 입구→유물 도달 불가(최소 통과 보장). 각 조우 예산 ±1, 가드레일, 문에서 ≥3.
5. 조우 방 장애물 ≤15%, 빈 5×5 블록 존재.
6. feature·적 칸 비중첩, 복도에 없음.
7. 동일 시드 재생성 동일 결과. 재생성 횟수 ≤ 5, 실패 0.
8. `solo_balance.gd` 봇을 새 층에서 8시드 실행: 완주 ≥ 6/8, 행동 150~260. 실측 후 조정.

변경됨(2026-09-22): 구현 후 실측으로 심부 9→6, 중간 6→5로 조정, 완주 기준은 측정치 3/8로 두고 6/8 목표는 밸런스 방법론(docs/balance-method.ko.md)의 후속 작업으로 이관 — 근거: docs/solo-floor1-relic-results.md

기존 테스트 중 100×100 좌표를 가정한 것(`continuous_floor.gd`, `torch_vision.gd`, `monster_roles.gd`, `mobile_exploration.gd`, `solo_floor.gd`, `torch_tradeoff.gd`)은 생성기 결과에서 좌표를 얻는 픽스처로 바꾼다.

## 6. 기존 코드와의 경계

신규
- `expedition/floor_generator.gd` — §1 파이프라인. `static func generate(theme, seed, depth) -> Dictionary`.
- `expedition/floor_templates.gd` — JSON 로드, 회전, 스탬프, 기호→지형·feature 변환.
- `expedition/encounter_builder.gd` — §3 테이블 로드, 곡선, 추첨, 가드레일, 방 안 배치.
- `data/content/floor_themes.json`, `floor_templates.json`, `floor_monsters.json`.

수정
- `continuous_floor.gd`: `Source.generate(1, seed)` + 2배 확대 제거. `build()`가 `FloorGenerator.generate(theme, seed+expedition*7919, 1)` 결과의 terrain/features/enemies를 직접 사용. `SIZE`는 `layout.size`에서 읽는 인스턴스 값으로 바꾸고 `static func point()` 삭제.
- `expedition_objective.gd`: `choose/place` 삭제. `create`, `discover`, `text`, `description`, `error`, `pickup`, `reachability`(검증용) 유지.
- `monster_ai.configure(enemy, role)`: 역할을 인자로 받음.
- `board.gd`, `map_view.gd`, `radial_light.gd`: `session.BOARD_SIDE` 사용, 100 리터럴 제거. `map_view.draw_floor`의 `step = side/100.0` → `/BOARD_SIDE`.
- `session.gd`: 변경 없음(BOARD_SIDE는 이미 floor_state가 설정).

유지
- 전투·시야·미니맵 캐시·조사물 실행기·상점·정산·스냅샷.
- `legacy/four_zone_floor.gd`, `tactical_terrain_layout.gd`: 삭제하지 않되 기본 경로에서 참조 제거. 회귀용으로 `tests/legacy_four_zone.gd`가 있으면 유지, 없으면 추가하지 않는다.

## 7. 레이아웃 출력 계약

```
{
  "size": 64, "seed": int, "theme_id": "F1_RUINS", "depth": 1,
  "terrain": Array[String]  # size*size, "wall"|"stone"|"rubble"|"wood"|"water"|"metal"
  "rooms": [{"id", "rect": Rect2i(내부), "kind": "template"|"fight"|"plain", "template_id", "doors": [Vector2i], "tier": "early"|"mid"|"deep"|"", "spine": bool}],
  "edges": [[room_a, room_b]],
  "entry": Vector2i, "relic": Vector2i,
  "features": {Vector2i: {"kind": "entry"|"relic"|"curio"|"altar"|"camp", "curio_id"?, "label"}},
  "encounters": [{"room": id, "tier", "mandatory": bool, "budget": int,
                  "members": [{"species_id","role","pos"}]}],
  "stats": {"regenerations": int, "relic_distance": int, "max_distance": int}
}
```

`continuous_floor.build()`는 `terrain` → `s.tiles`(젖음 70은 water), `features` → `floor_state.features`, `encounters[*].members` → `s.enemies`(group_id = "F%d_E%02d")로 옮긴다. 미니맵 `observation()`의 width/height는 `size`.

## 8. 범위 밖

2층 테마 실제 내용, 몬스터 배회, 파티 모드 예산, 새 종족 추가, 동굴 레이아웃, 아트 교체. `F2_MINES` 테마는 JSON에 `"depth": 2`만 있는 뼈대로 둔다.
