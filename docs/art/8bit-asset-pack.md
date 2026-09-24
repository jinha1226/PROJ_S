# 고전 8비트 에셋 팩

현재 전통 로그라이크 모드의 그래픽은 `assets/8bit/`에 모았다. 모든 시트는 imagegen 기본 도구로 제작했고, 기존 UI 아틀라스와 실제 게임 화면을 팔레트·비율 참고 이미지로 사용했다. 원본 PNG를 프로젝트 안에 보존하며 Godot에서 `AtlasTexture`로 잘라 사용한다. 맵·아이콘에는 nearest 필터를 적용한다.

| 파일 | 구성과 게임 데이터 연결 |
| --- | --- |
| `actors.png` | 4×2. 인간, 드워프, 엘프, 오크, 늑대 수인, 마법사, 상인, 방랑자. 현재 파티·NPC 및 초상화에 사용. |
| `monsters.png` | 4×2. 쥐, 목도리 도마뱀, 코볼트, 고블린, 홉고블린, 오크, 놀, 강쥐. `floor_monsters.json`의 8개 `species_id`와 동일한 순서. |
| `fire-lizard-boss.png` | 보스 단일 스프라이트. |
| `mastery-icons.png` | 5×2. 검·창·둔기·도끼·활 / 화염·냉기·기류·변이·소환. 숙련 10종 및 시작 장비 선택에 사용. |
| `spell-icons.png` | 4×3. 기본 주문 12종. `mobile_art.gd`의 `SPELL_IDS` 순서. |
| `spells-{fire,ice,air,hex,summon}.png` | 각 5×2. 계열마다 레벨 1~10 주문·특성 아이콘 10개씩, 총 50개. 숙련 상세의 레벨 카드와 준비한 주문에 사용. |
| `equipment-icons.png` | 4×3. 검·단검·창·둔기 / 도끼·활·지팡이·갑옷 / 방패·반지·마법서·두루마리. 장비 가방에 사용. |
| `ruins-tiles.png`, `mines-tiles.png` | 각 4×4. 기존 `floor1-ink-v2/catalog.json`과 같은 재질 순서·좌표. 1층 유적과 2층 폐광의 바닥·전면 벽·상단 벽·물·흙 등을 구성한다. |
| `props.png` | 4×4. 기둥, 잔해, 상자, 통, 횃불, 화로, 야영불, 석관, 제단, 유물, 철창, 뼈, 바리케이드 등 기존 카탈로그의 16종. |
| `start-background.png`, `camp-background.png` | 시작 화면의 입구와 야영 화면의 화톳불. 텍스트·캐릭터는 포함하지 않아 실제 UI와 파티 데이터를 별도로 그린다. |

시트 생성 프롬프트의 공통 기준: **classic 8-bit console pixel art, hard square pixel clusters, dark 1–2 pixel logical outline, 3–4 flat tones per material, coherent charcoal/navy/brass palette, no gradient or anti-aliasing**. 캐릭터·몬스터·아이콘·오브젝트는 진짜 투명 배경에 셀별로 격리했고, 타일은 기존 4×4 재질 배치를 유지하는 스타일 변환으로 제작했다. 유적과 폐광은 벽 형상이 같아 기존 연결 로직을 공유한다.

새 몬스터나 주문을 데이터에 넣을 때에는 `expedition/art/mobile_art.gd`의 해당 ID 목록 또는 계열 시트도 함께 늘려야 한다. 알 수 없는 몬스터 ID는 코볼트, 알 수 없는 주문 ID는 기본 화염탄 아이콘으로 표시한다.
