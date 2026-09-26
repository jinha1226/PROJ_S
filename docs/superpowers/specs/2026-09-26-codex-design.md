# 도감

작성일: 2026-09-26 · 상태: **구현 완료**
다음: [읽히게 만들기](2026-09-26-legibility-design.md)
전제: ①(`Forms` 형태·몸 단계), ②(`stone_effects.json`의 `text`·`keywords`·`families`), ④-a1(정규 영혼석 id `BASE/part[@elem]`, 부위 이름). 장비 탭은 [장비 설계](2026-09-26-gear-affixes-design.md)의 고정 아티팩트가 들어온 뒤 켠다.
기존 코드: `expedition/progression/essences.gd`(`canonical`, `title`, `row`), `expedition/progression/bestiary.gd`(종족 표), `expedition/items/gear.gd`(`roll_part`), `expedition/run/session.gd`(`essence_seen`은 원정 단위), `expedition/ui/screens/start_screen.gd`, `camp_screen.gd`, `character_folio.gd`, `popups.gd`, `expedition/art/mobile_art.gd`, `assets/monsters-v1/png/<종족>_south.png`

## 0. 결정

1. **도감은 원정을 넘어 쌓이는 기록이다.** 파일 하나(`user://codex.json`)에 저장한다. 원정 중단·재개 저장과는 별개다(그것은 나중 단계).
2. **탭 셋**: 몬스터, 영혼석, 장비(고정 아티팩트가 생긴 뒤).
3. **처음엔 모른다.** 만나기 전의 몬스터는 실루엣, 얻기 전의 부위는 잠김 + 힌트.
4. **기록은 실제 원정에서만.** 전투 시험(아레나), 시험 장비(`grant_test_loadout`), 시뮬레이터·난이도 게이트·테스트는 도감에 쓰지 않는다.
5. **보상은 없다(이번 단계).** 도감 완성률은 표시만 한다. 수집 보상은 밸런스를 흔들어서 나중에 따로 정한다.

## 1. 기록하는 것

| 사건 | 기록 | 부르는 곳 |
| --- | --- | --- |
| 몬스터를 처음 봄 | `monsters[종족].seen = true`, 변종이면 `variants`에 속성 추가 | 층 시야 갱신(`floor_state.observe`) 뒤, 새로 보인 적 |
| 몬스터 처치 | `monsters[종족].kills += 1` | `Session.after_damage` 처치 분기(파티 쪽 처치만) |
| 부위 영혼석 획득 | `stones[BASE/part].found += 1`, 변종이면 `variants`에 속성 | `Gear.roll_part`가 가방에 넣을 때 |
| 부위 영혼석 흡수 | `stones[BASE/part].absorbed = true` | `Essences.absorb` 성공 |
| 고정 아티팩트 획득 | `unrands[id].found += 1` | 장비 드롭(장비 설계 이후) |
| 원정 끝 | `runs += 1`, `deepest = max(deepest, depth)` | 결과 카드(`result_card.gd`)를 띄울 때 |

- 영혼석 키는 **변종 속성을 뺀 `BASE/part`**. 보스 영혼석은 `BASE` 그대로.
- 보스 몬스터도 몬스터 탭에 들어간다(종족 id는 보스 id).

## 2. 파일과 모듈

### 2.1 `user://codex.json`

```json
{
  "version": 1,
  "runs": 3,
  "deepest": 7,
  "monsters": {"dcss_rat": {"seen": true, "kills": 41, "variants": ["poison"]}},
  "stones": {"RAT_GNAW/cut": {"found": 2, "absorbed": true, "variants": []}},
  "unrands": {}
}
```

- 모르는 키는 읽을 때 버리지 않고 그대로 둔다(나중 버전 호환).
- 파일이 없거나 깨졌으면 빈 도감으로 시작하고, 깨진 파일은 `codex.bad.json`으로 옮겨 둔다(덮어쓰지 않는다).
- 웹 빌드(`deploy-pages`)에서도 `user://`는 브라우저 저장소로 동작한다.

### 2.2 `expedition/progression/codex.gd` (새)

| 함수 | 뜻 |
| --- | --- |
| `static var path := "user://codex.json"` | 테스트가 임시 경로로 바꾼다 |
| `read() -> Dictionary`, `write(data) -> bool` | 읽기·쓰기 |
| `note_seen(s, enemy)`, `note_kill(s, enemy)`, `note_stone(s, id)`, `note_absorb(s, id)`, `note_unrand(s, id)`, `note_run_end(s)` | 기록. `s.records_codex`가 거짓이면 아무것도 안 함 |
| `flush(s)` | 바뀐 것이 있으면 파일에 쓴다 |
| `monster_entry(data, species) -> Dictionary`, `stone_entry(data, id) -> Dictionary` | 화면이 읽는 모양(알려짐 여부, 문구, 힌트) |
| `completion(data) -> Dictionary` | 탭별 완성률 |

- 세션은 `s.codex`(읽어 둔 사전)와 `s.records_codex`(기본 `false`)를 가진다. **메인 화면에서 "새 탐험"으로 시작한 원정만 `true`.**
- 쓰기는 모아서: 층 이동, 야영 진입, 원정 끝, 앱이 백그라운드로 갈 때(`NOTIFICATION_APPLICATION_PAUSED`, `NOTIFICATION_WM_CLOSE_REQUEST`, `main.gd`) `flush`.

## 3. 화면

### 3.1 들어가는 곳

- 시작 화면: "새 탐험" 아래 **"도감"** 버튼.
- 야영 화면: 메뉴에 "도감".
- 원정 중: 전술 메뉴(인물 상세 옆)에 "도감"(읽기 전용, 시간 흐르지 않음).
- 적 정보 창: 이름 옆 작은 "도감" 버튼 → 그 몬스터 항목으로 바로.

### 3.2 몬스터 탭

- 구역별 묶음(구역 1~4 + 보스). 한 줄에 칸 4개 정도의 격자.
- **모름**: 검은 실루엣(같은 그림을 검게), "???", 등장 구역만.
- **봄**: 그림, 이름. 누르면 상세.
- **상세**
  - 이름, 등장 구역, 역할
  - "공격 베기 · 피부 질김 · 뼈 단단함"(`Forms.body_line`)
  - 대표 효과(몬스터가 쓰는 효과) 문구
  - 액티브(파츠) 설명
  - **부위 셋**: 부위 이름 · 잘 나오는 마무리 형태 · 모음 여부("쥐 꼬리 — 베기로 마무리 — 모음")
  - 본 변종 속성, 처치 수

### 3.3 영혼석 탭

- 종족 × 부위 격자(종족 한 줄에 부위 셋). 구역 순.
- **잠김**: 부위 이름만 흐리게 + "베기로 마무리" 힌트. 종족을 아직 못 봤으면 "???".
- **모음**: 부위 이름, 효과 문구, 키워드 칩, 빌드군 칩. 흡수한 적이 있으면 표식.
- **거르기**: 위쪽에 빌드군 칩 12개(출혈·분쇄·급소…) — 누르면 그 빌드군 부위만(잠긴 것도 힌트와 함께 보임). 이것이 "이 빌드를 하려면 무엇을 모아야 하나"의 답이 된다.

### 3.4 장비 탭

- 고정 아티팩트 목록(찾은 것만 문구, 못 찾은 것은 칸 종류와 "???"). 장비 설계가 구현되기 전에는 탭을 숨긴다.

### 3.5 완성률

- 탭 제목 옆 "몬스터 23/41 · 영혼석 37/117 · 장비 2/12"(보스 포함 수).
- 시작 화면 도감 버튼에 전체 %.

## 4. 파일

| 파일 | 바뀌는 것 |
| --- | --- |
| `expedition/progression/codex.gd` (새) | 기록·저장·항목 |
| `expedition/ui/screens/codex_screen.gd` (새) | 세 탭, 상세, 거르기 |
| `expedition/run/session.gd` | `codex`, `records_codex`, 처치·시야 기록 호출 |
| `expedition/level/…`(시야 갱신) | 새로 보인 적 `note_seen` |
| `expedition/items/gear.gd`, `expedition/progression/essences.gd` | 획득·흡수 기록 |
| `expedition/ui/main.gd` | 앱 일시정지·종료 때 `flush`, 도감 화면 열기 |
| `start_screen.gd`, `camp_screen.gd`, 전술 메뉴, `popups.gd`(적 정보 창) | 진입점 |
| `expedition/art/mobile_art.gd` | 몬스터 그림 실루엣(모듈레이트 검정) |

## 5. 테스트

| 스위트 | 검사 |
| --- | --- |
| `tests/codex.gd` (새) | 임시 경로에서 저장·읽기 왕복, 깨진 파일은 옮기고 빈 도감, 모르는 키 보존, 각 기록 사건, 변종이 키에 들어가지 않음, `records_codex` 거짓이면 기록 없음(아레나·시험 장비·시뮬레이터), 완성률 |
| `tests/codex_ui.gd` (새) | 세 탭 만들기, 모름/봄/상세, 잠김 힌트, 빌드군 거르기, 진입점 버튼 이름 |
| 기존 | 테스트·시뮬레이터가 `user://codex.json`을 만들지 않음(스위트 시작·끝에 파일 유무 확인) |

## 6. 범위 밖

수집 보상, 원정 중단·재개 저장, 도감에서 원하는 부위 찍기(동료 AI 설계 §5와 연결은 나중), 몬스터 설명 글(배경 이야기).

## 7. 검토할 결정

1. 수집 보상을 두지 않는 것.
2. 진입점 네 곳(시작, 야영, 전술 메뉴, 적 정보 창).
3. 영혼석 탭에서 못 본 종족의 부위를 "???"로 숨길지, 부위 이름까지는 보여줄지.

구현 계약은 [수정한 구현 계획](../plans/2026-09-26-codex.md)의 첫 절을 따른다. 데이터 표기는 현재 아티팩트 배열과 보스 NPC 구조를 기준으로 갱신했다.
