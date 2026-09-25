# 기술 아이콘 v1

만든 도구: `tools/art/build_skill_icons.py`. 파일: `assets/items-v1/skills/<id>.png`(128 px). 검토 시트: `docs/art/skills-v1/skills-sheet.png`.

주문 아이콘(`assets/items-v1/spells`)과 같은 카드 틀이라 싸움 버튼에 나란히 놓인다. 테두리 색은 영혼석의 역할을 따른다.

| 테두리 | 역할 | 아이콘 |
| --- | --- | --- |
| 호박색 | 무리 | 물어뜯기, 물세례, 해일, 방패벽 |
| 빨강 | 광폭 | 꼬리치기, 휘두르기, 내려찍기, 창 찌르기, 할퀴기 |
| 청록 | 기습 | 기습, 거미줄, 달라붙기, 흡혈 물기 |
| 강철 | 수호 | 도발, 방패 자세, 몸 말기, 허물 벗기, 가시 갑옷 |
| 올리브 | 사수 | 투석, 조준 사격, 도끼 투척, 독침, 뼈화살 연사 |
| 뼈색 | 기본 행동 | 밀치기(`PUSH`), 엄호(`GUARD`) |
| 금색 | 보스 영혼석 | 지휘(`GOBLIN_CHIEF`), 과열 장갑(`FURNACE_HEART`), 영혼 먹기(`SOUL_EATER`) |

파일 이름은 `abilities.gd`와 `essences.json`의 id다. 주문 종족의 몬스터 전용 공격(`FIRE_CALLER`, `WRAITH` 등)은 플레이어가 쓰지 않으므로 없다. 플레이어는 그 영혼석으로 주문을 쓰고, 주문 아이콘을 쓴다.

연결: `mobile_art.gd`의 `part_icon(id)`이 옛 아이콘 시트를 번호로 고르는 대신 `load("res://assets/items-v1/skills/%s.png" % id)`를 쓰게 한다. 변종 id(`<기본>@<속성>`)는 `@` 앞의 기본 id로 찾는다. 파일이 없으면 지금처럼 옛 시트로 돌아간다.
