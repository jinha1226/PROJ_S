# DCSS·Shattered Pixel Dungeon 비교 기반 업데이트 항목

작성일: 2026-09-24
검토 기준: `origin/main`의 `2fe844e` (`Add 8-bit art pack and fix exploration HUD controls`)

이 문서는 현재 **잿빛 원정**을 코드·문서·헤드리스 테스트로 확인하고, [Dungeon Crawl Stone Soup(DCSS) 공식 매뉴얼](https://github.com/crawl/crawl/blob/master/crawl-ref/docs/crawl_manual.rst)과 [Shattered Pixel Dungeon(SPD) 공식 저장소](https://github.com/00-Evan/shattered-pixel-dungeon) 및 [개발자 변경 기록](https://shatteredpixel.com/blog/shattered-pixel-dungeon-v250.html)을 비교해 작성했다. 직접 플레이 테스트나 플레이어 설문 결과는 아니다. 두 게임의 콘텐츠 수를 그대로 목표로 삼기보다, 이 프로젝트의 파티·야영·파츠 시스템이 한 판 안에서 의미 있는 선택이 되게 만드는 데 초점을 둔다.

## 현재 갖춘 기반

- 80×80 절차 생성 층, 시야·자동탐험, 3층 간격 보스, 파티 영입, 야영과 식량 소비가 연결된 하강 Run이 있다. [README](../../README.md)
- 주문 50개와 기존 기본 주문, 무기·마법 숙련 10축, 물약 8종과 두루마리 8종의 Run별 외관 섞기·감정이 구현되어 있다. [주문 구현](../../expedition/spells/spells.gd) · [README](../../README.md)
- 새 8비트 시트가 캐릭터·몬스터·주문·숙련·타일·UI에 연결되어 있다. [에셋 목록](../art/8bit-asset-pack.md)

## 우선순위별 업데이트

| 우선순위 | 현재 차이 | 업데이트할 사항 | 완료 기준 |
| --- | --- | --- | --- |
| P0 | 현재는 사망 시 결과만 보여 주는 무한 하강이며, 앱 종료 후 저장·불러오기가 없다. DCSS에는 오브 회수라는 명확한 승리 목표가 있다. | 첫 완주 가능한 구간의 층수·최종 목표·승리 결과를 정하고 구현한다. 모바일에서 중단 후 같은 Run을 이어 할 수 있도록 저장·복원을 추가한다. | 시작부터 승리 또는 패배까지 실제 플레이로 도달할 수 있고, 앱 재실행 후 진행 상태가 복원된다. |
| P0 | 첫 층 난이도 기록이 현재 실행 결과와 다르고, 테스트는 하강률 하한을 검사하지 않는다. | 솔로와 파티의 층별 성공률·사망 원인·식량·행동 수를 여러 시드로 측정한다. 목표 난이도를 먼저 정한 뒤 회귀 게이트를 추가하고 기존 기록을 갱신한다. | 정한 시드 묶음과 목표치로 1층·첫 보스·최종 구간의 회귀 여부가 자동 판정된다. |
| P1 | 유적과 폐광 두 테마가 홀수·짝수 층에 반복 적용되고 보스 세 패턴도 순환한다. SPD는 다섯 지역에 각기 다른 방 구성을 더해 지역 차이를 만든다. | 지역별 지형 위험, 적 조합, 보상, 방 구조 중 적어도 두 요소를 다르게 설계한다. 먼저 완주 구간에 맞춘 세 번째 지역과 해당 지역만의 전투 판단을 추가한다. | 팔레트를 가려도 지역마다 탐험 경로와 전투·자원 선택이 달라진다. |
| P1 | 숙련 10축 중 고유 이정표는 검·화염에만 있고 융합 조합은 두 개다. 주문 50개는 8가지 기본 형태를 공유한다. | 숙련별 핵심 전술을 정의하고 이정표·파츠·주문 간 상호작용을 확장한다. 창의 거리 유지, 활의 사선 확보, 냉기의 지형 제어처럼 플레이 방식이 달라지는 선택부터 만든다. | 서로 다른 시작 빌드 최소 3종이 장비·위치·자원 사용에서 구별되는 판단을 요구한다. |
| P2 | 세 보스가 모두 같은 보스 스프라이트를 사용한다. | 각 보스의 실루엣과 공격 예고를 패턴에 맞게 구분하고 실제 모바일 화면 크기에서 판독성을 확인한다. | 이름을 가려도 보스를 구분할 수 있고, 위험 범위와 해결 행동을 전투 중 읽을 수 있다. |

## 근거와 검증 메모

- [Run 설명](../../README.md): 현재 마을·유물 회수·귀환·승리 흐름이 없고, 앱 종료 후 저장·불러오기도 없다. 기존 파티·야영 시스템은 완주 구간에 그대로 활용할 수 있다.
- [층 선택 코드](../../expedition/level/continuous_floor.gd)는 깊이의 홀짝으로 `F1_RUINS`와 `F2_MINES`를 고른다. [보스 코드](../../expedition/actors/boss_ai.gd)는 깊이에 따라 세 패턴을 순환한다. [층 템플릿](../../data/content/floor_templates.json)은 현재 7종이다.
- [숙련 데이터](../../data/content/mastery.json)에는 검·화염 이정표와 `sword_fire`·`fire_sword` 융합이 들어 있다. [주문 구현](../../expedition/spells/spells.gd)은 50개 주문을 8개 원시 형태로 처리한다. 기본 형태를 재사용하는 것 자체가 문제는 아니며, 실제 플레이에서 역할이 구분되는지가 판단 기준이다.
- [보스 그리기 코드](../../expedition/ui/battle_actor_visual.gd)는 `boss` 여부만 보고 단일 `fire-lizard-boss.png`를 사용한다.
- 2026-09-24에 `tests/run_start.gd`, `tests/playthrough.gd`, `tests/mobile_hud.gd`, `tests/solo_balance.gd`를 최신 코드에서 실행했다. 모두 검사 실패 0건이었다. 다만 `solo_balance`의 자동 행동은 8개 시드 중 **2개만 1층 하강**, 6개 사망했고, 연속 Run 시드는 2층에서 사망했다. [기존 기록](../balance/run-gates.md)은 3/8 하강으로 적혀 있다. [현재 테스트](../../tests/solo_balance.gd)는 모든 Run이 하강이나 사망으로 끝나는지만 확인하고 최소 하강률은 검사하지 않는다. 자동 행동의 성적은 플레이어 승률로 해석하면 안 된다.

## 실행 순서

1. 목표 층수·승리 조건과 중단 저장 범위를 정해 한 판의 시작과 끝을 연결한다.
2. 첫 층과 첫 보스의 자동 측정·사람 플레이 기록을 모아 목표 난이도를 정하고 테스트 게이트를 보강한다.
3. 완주 구간에 맞춘 지역별 규칙과 숙련별 고유 선택을 추가한다.
4. 보스별 그래픽·예고를 모바일 해상도에서 검증하고 수정한다.

참고: [DCSS 공식 매뉴얼](https://github.com/crawl/crawl/blob/master/crawl-ref/docs/crawl_manual.rst)은 승리 목표와 튜토리얼·도움말을 설명한다. [SPD 개발자 글](https://shatteredpixel.com/blog/shattered-pixel-dungeon-v250.html)은 다섯 지역과 도감·기록 UI를, [지역별 방 구성 설명](https://shatteredpixel.com/blog/coming-soon-to-shattered-trinkets.html)은 지역마다 방 유형을 늘린 사례를 보여 준다.
