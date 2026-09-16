# 추가 아이템 원본

내장 `image_gen`으로 생성한 석궁, 철퇴, 창, 곤봉, 파랑/초록 물약 6종이다. 정확한 프롬프트 템플릿과 개별 subject는 [manifest.json](manifest.json)에 있다. 실제 알파 배경을 검증한 뒤 내용 변경 없이 잘라내기·축소·중앙 정렬했다.

- 런타임: `assets/fantasy_pawns_v1/items/`
- 재생성: `python3 tools/art/build_fantasy_items_v2.py`
- 64px 미리보기: [icons.png](../../../docs/art/fantasy-items-v2/icons.png)

새 석궁·철퇴·창은 강철 변형에도 연결한다. 곤봉은 저층 몬스터가 장비/드롭하는 `WEAPON_DCSS_CLUB`에 연결한다. 단도·장검 계열은 기존 검, 전투 도끼는 기존 도끼, 오크 활은 기존 활을 사용한다.

미감정 물약은 기존 빨강과 새 파랑/초록을 사용하며, 기존 번호 표시로 종류를 구별한다. 색깔은 효과나 감정 여부를 공개하지 않는다. 채찍·플레일·삼지창의 전용 실루엣은 이번 추가 범위에 포함되지 않았다.
