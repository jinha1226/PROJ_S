# 구역·보스·영혼석 에셋 v1

만든 도구: `tools/art/build_zone_assets.py` (`python3 tools/art/build_zone_assets.py`로 다시 만든다). 모든 그림은 종이인형 문법이다. 굵은 잉크 외곽선, 단색 면, 오른쪽 아래 그림자 초승달을 쓴다. 검토용 시트는 `docs/art/zones-v1/`에 있다.

코드에는 아직 연결하지 않았다. 아래 "연결" 열이 붙일 곳이다. 계획 문서는 `docs/superpowers/plans/2026-09-25-*.md`다.

## 영혼석 `assets/zones-v1/soulstones/` (128 px)

한 장을 세 겹으로 겹쳐 그린다: 돌 → 계열 문양 → (2·3단계면) 단계 빛 → (보스면) 금테.

| 파일 | 내용 |
| --- | --- |
| `stone_<속성>.png` | 깎은 돌. 속성 `none`, `fire`, `ice`, `air`, `poison`, `will`, `bleed` 일곱 색 |
| `emblem_<계열>.png` | 흰 문양, 투명 바탕. 계열 `rat`, `goblin`, `reptile`, `kobold`, `orc`, `elemental`, `insect`, `gnoll`, `undead`, `bat` |
| `tier_2.png`, `tier_3.png` | 단계 빛. 아래쪽 점 개수가 단계 |
| `boss_rim.png` | 보스 영혼석 금테와 작은 왕관 |

- 연결: `mobile_art.gd`의 `part_icon(id)`을 대신한다. 돌 색은 `Essences.element(id)`(없으면 `none`), 문양은 `Essences.family(id)`, 단계는 `Essences.tier(actor,id)`, 금테는 보스 영혼석 id(`GOBLIN_CHIEF`, `FURNACE_HEART`, `SOUL_EATER`, 최종 보스 보상)다. 계열이 없는 행이 남아 있으면 문양 없이 돌만 그린다.
- 시트: `soulstones.png`(속성 × 계열 전체와 단계·보스 예시), `soulstone-parts.png`(겹 하나씩).

## 상태 배지 `assets/zones-v1/status/` (128 px)

`wet`, `stun`, `taunt`, `bleed`, `burn`, `poison`, `freeze`, `confuse`, `slow`, `sealed`(영혼 봉인), `cracked`(골렘 갈라짐), `marked`(족장 지휘 표식), `steam`.

- 연결: 캐릭터 카드와 몬스터 길게 누르기 정보의 상태 줄, 반응 이름을 띄울 때 옆 아이콘. 상태 id는 반응 계획(3/4)과 같다.

## 보스 `assets/zones-v1/bosses/` (192 px, 남쪽)

| 파일 | 보스 |
| --- | --- |
| `goblin_chief.png` | 3층 고블린 족장: 붉은 망토, 털 깃, 쇠 왕관, 해골 지팡이 |
| `furnace_golem.png` | 6층 용광로 골렘: 가슴의 불 아가리, 용암 이음새, 굴뚝 |
| `soul_eater.png` | 9층 영혼 포식자: 빈 두건, 톱니 입, 도는 영혼석 셋 |
| `fallen_aura.png` | 12층 타락한 모험가: 그 NPC의 종이인형 **뒤에** 까는 보라 불꽃과 붉은 테 그림자 |

- 연결: 보스 계획(4/4)은 보스를 종족 그림(`sprite_species`)으로 그린다. `mobile_art.gd`에 `BOSS_SPRITES := {"goblin_chief":..., "furnace_golem":..., "soul_eater":...}`를 두고 `paint_boss`가 보스 종류로 고르게 하면 된다. 최종 보스는 NPC 그림을 그대로 쓰고, 먼저 `fallen_aura.png`를 같은 크기로 그린 뒤 그 위에 NPC를 그린다. 그림 크기는 기존 보스처럼 3타일.

## 보스 방 소품 `assets/zones-v1/props/` (192 px)

`throne`(왕좌 방), `lever_up`, `lever_down`(제련소 수로 레버, 당긴 쪽에 물줄기), `furnace`(제련소), `binding_altar`(구속의 제단), `chain_post`(구속된 몬스터 자리), `gravestone`, `open_coffin`(묘역의 심장).

- 연결: `floor1_art.gd`의 `OBJECTS`에 같은 이름으로 넣는다. 발 위치는 기존 물건과 같은 `OBJECT_FOOT`(64단위 격자의 y=58)다. 레버는 당겨지면 `lever_down`으로 바꾼다.

## 새 구역 바닥과 벽 `assets/zones-v1/tiles/` (1254 px, flat-v1 배치)

| 파일 | 배치 |
| --- | --- |
| `temple-floor-slabs.png`, `crypt-floor-slabs.png` | 2×2 바닥 판 넷(`floor_a`~`floor_d`), 기존 `ruins-floor-slabs.png`와 같다 |
| `temple-wall-blocks.png`, `crypt-wall-blocks.png` | 왼쪽 위 `front`, 오른쪽 위 `top`, 아래 줄은 변형(덩굴 앞면, 금 간 윗면 / 줄무늬 앞면, 금 간 윗면) |

- 연결: `floor1_art.gd` `tile()`의 테마 분기에 `F3_TEMPLE` → temple, `F4_CRYPT` → crypt 시트를 더한다. 구역 계획(1/4) Task 6의 "빌린 그림에 색 입히기"를 이 시트로 바꾼다. 나무·물·금속 같은 재료 칸은 기존 폐허 재료를 그대로 쓴다.

## 위험 칸과 반응 칸 `assets/zones-v1/hazards/` (256 px, 한 칸)

| 파일 | 쓰임 |
| --- | --- |
| `lava.png`, `deep_water.png`, `bog.png` | 지형 자체. 칸 전체를 덮는다 |
| `gas.png`, `fog.png`, `collapse.png`, `collapse_armed.png` | 바닥 위에 겹치는 투명 그림. `collapse_armed`는 예고 중인 천장 |
| `steam.png`, `ice.png`, `poison_pool.png` | 반응 칸. 바닥 위에 겹친다 |

- 연결: `board.gd`의 칸 그리기에서 지형(`lava`, `deep_water`, `bog`)은 재료 대신, 나머지는 바닥을 그린 뒤 위에 그린다. 필드 이름은 구역 계획(`gas`, `fog`, `collapse`)과 반응 계획(`steam_until`, `ice`, `poison_pool`)을 따른다.

## 구역 재료 칸 `assets/zones-v1/tiles/<테마>-materials.png` (1254 px)

`temple-materials.png`, `crypt-materials.png`. 폐허 재료 시트(`assets/topdown/flat-v1/ruins-materials.png`)와 16칸의 위치가 같아서 `assets/topdown/floor1-ink-v2/catalog.json`의 `materials` 좌표로 그대로 자른다.

| 칸 | 신전 | 묘역 |
| --- | --- | --- |
| `floor_a`~`floor_d` | 청록 판석, 이끼 | 보라 판석, 룬 고리 |
| `front`, `top` | 청록 벽 | 보라 벽 |
| `wood` | 이끼 낀 판자 | 관 판자 |
| `metal` | 녹청 슨 청동 창살 | 녹슨 쇠 창살 |
| `water`, `water_ripple` | 바닥 타일이 비치는 맑은 물 | 검은 물 |
| `mud`, `dirt` | 뻘, 모래 | 무덤 흙 |
| `moss` | 짙은 이끼 | 창백한 균류 |
| `rubble` | 무너진 기둥 조각 | 뼈 무더기 |
| `embers` | 푸른 룬 빛 | 보라 혼불 |
| `damp` | 젖은 판석 | 얼룩진 판석 |

- 연결: `floor1_art.gd` `tile()`의 재료 분기에서 `F3_TEMPLE`, `F4_CRYPT`일 때 이 시트를 쓴다.
- 시트: `docs/art/zones-v1/materials.png`.

## 배너 틀과 승리 그림 `assets/ui/frames-v1/` (도구 `tools/art/build_ui_extras.py`)

| 파일 | 쓰임 |
| --- | --- |
| `banner_level.png` | 레벨 업 배너(금색, 별 모서리) |
| `banner_essence.png` | 영혼석 획득 배너(보라, 보석 모서리) |
| `banner_boss.png` | 보스 등장 배너(빨강, 해골 모서리) |
| `banner_victory.png` | 승리 결과 카드(금색과 초록) |
| `ribbon_gold.png`, `ribbon_purple.png`, `ribbon_red.png` | 배너 제목 리본 |
| `victory.png` | 승리 결과 카드 그림(360×240): 영혼석 왕관, 검과 지팡이, 월계수, 묘역 계단 위로 비치는 빛 |

- 배너 틀은 나인 패치다. PNG는 384 px이고 모서리 여백은 112 px(원본 192 단위의 56)다. `banners.gd`의 `frame()`에서 `StyleBoxFlat` 대신 `StyleBoxTexture`를 쓰고 `texture_margin_*`을 112로, 화면에서는 `scale`로 줄이거나 `texture_margin`을 56으로 두고 텍스처를 절반 크기로 불러온다. 내용 여백(`content_margin_*`)은 40 정도가 알맞다.
- 리본은 가운데 3분의 1만 늘린다(`texture_margin_left/right` = 폭의 3분의 1). 배너 제목 뒤에 깐다.
- `victory.png`는 `result_card.gd`의 승리 분기(`session.phase == "VICTORY"`) 맨 위에 둔다.
- 시트: `docs/art/zones-v1/ui-frames.png`.
