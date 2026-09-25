# 고전 8비트 에셋 팩

현재 전통 로그라이크 모드가 실제로 사용하는 그래픽은 `assets/8bit/classic/`에 있다. 이 폴더의 PNG는 16~32px 논리 크기의 스프라이트와 29색 공통 팔레트로 고정한 게임용 파일이다. `assets/8bit/`의 큰 이미지와 `assets/8bit/source/actors.png`는 제작 원본이며, `godot --headless --path . --script res://tools/art/build_classic_8bit.gd`로 게임용 PNG를 다시 만든다. 시작 화면과 야영 배경은 160×90px이다. 화면에서는 nearest 필터만 사용한다.

| 파일 | 구성과 게임 데이터 연결 |
| --- | --- |
| `actors.png` | 4×2, 각 24×24px. 인간, 드워프, 엘프, 오크, 늑대 수인, 마법사, 상인, 방랑자. 현재 파티·NPC 및 초상화에 사용. |
| `monsters.png` | 4×2. 쥐, 목도리 도마뱀, 코볼트, 고블린, 홉고블린, 오크, 놀, 강쥐. `floor_monsters.json`의 8개 `species_id`와 동일한 순서. |
| `fire-lizard-boss.png` | 보스 단일 스프라이트. |
| `mastery-icons.png` | 5×2. 검·창·둔기·도끼·활 / 화염·냉기·기류·변이·소환. 숙련 10종 및 시작 장비 선택에 사용. |
| `spell-icons.png` | 4×3. 기본 주문 12종. `mobile_art.gd`의 `SPELL_IDS` 순서. |
| `spells-{fire,ice,air,hex,summon}.png` | 각 5×2. 계열마다 레벨 1~10 주문·특성 아이콘 10개씩, 총 50개. 숙련 상세의 레벨 카드와 준비한 주문에 사용. |
| `equipment-icons.png` | 4×3. 검·단검·창·둔기 / 도끼·활·지팡이·갑옷 / 방패·반지·마법서·두루마리. 장비 가방에 사용. |
| `ruins-tiles.png`, `mines-tiles.png` | 각 4×4, 타일당 16×16px. 기존 `floor1-ink-v2/catalog.json`과 같은 재질 순서. 1층 유적과 2층 폐광의 바닥·전면 벽·상단 벽·물·흙 등을 구성한다. |
| `props.png` | 4×4. 기둥, 잔해, 상자, 통, 횃불, 화로, 야영불, 석관, 제단, 유물, 철창, 뼈, 바리케이드 등 기존 카탈로그의 16종. |
| `start-background.png`, `camp-background.png` | 시작 화면의 입구와 야영 화면의 화톳불. 텍스트·캐릭터는 포함하지 않아 실제 UI와 파티 데이터를 별도로 그린다. |

원본 시트는 imagegen으로 제작했지만, 큰 PNG를 줄여서 그리는 것만으로는 고전 8비트 표현이 되지 않아 실제 사용 파일은 고정 픽셀 격자로 변환했다. 캐릭터와 몬스터는 각 24×24px, 아이콘은 16×16px, 타일은 16×16px이며, 반투명 가장자리를 제거하고 색을 공통 팔레트로 제한한다. 유적과 폐광은 벽 형상이 같아 기존 연결 로직을 공유한다.

새 몬스터나 주문을 데이터에 넣을 때에는 `expedition/art/mobile_art.gd`의 해당 ID 목록 또는 계열 시트도 함께 늘려야 한다. 알 수 없는 몬스터 ID는 코볼트, 알 수 없는 주문 ID는 기본 화염탄 아이콘으로 표시한다.
