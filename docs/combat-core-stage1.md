# 전투 코어 교체 — 1단계

기존 캠페인과 분리한 Godot 원형. 기존 실행 장면/세이브/전투 경로는 아직 교체하지 않는다.
외부 소스의 복사나 번역 없이 직접 작성했다.

## 범위와 실행

`godot --path . prototype/combat_scene.tscn`

9×9 격자, 주인공 1명, 적 2명. 상하좌우 인접 칸 클릭/터치 또는
WASD/방향키 이동, 적 칸 진입으로 공격, Space/버튼으로 대기, 재시작 버튼.
이 단계는 고정 피해와 동일 행동 비용 100을 사용한다. 대각선 이동,
시야, 성격, 육체, 저장, 자동탐험, 실제 게임 연결은 후속 단계다.

단일 코어가 입력 검증 → 행동 실행 → 행동 시간 갱신 → 적 행동 → 다음 주인공 입력을 처리한다.
사망은 피해 처리에서 즉시 확정하며 시체는 이동/행동 대상에서 제외한다.
화면은 결과 이벤트를 표시하며 판정을 소유하지 않는다.

## 실제 확인한 참고 소스

- [Shattered Pixel Dungeon Actor.java](https://github.com/00-Evan/shattered-pixel-dungeon/blob/master/core/src/main/java/com/shatteredpixel/shatteredpixeldungeon/actors/Actor.java):
  `spendConstant`, `process`, `remove`. 각 actor의 시간으로 실행 순서를 선택하고
  동시간에는 우선순위를 사용한다. 우리 코어는 정수 시간과 고정 ID 순서를 사용한다.
  원본의 스레드/스프라이트 동기화는 도입하지 않는다.
- [Char.java](https://github.com/00-Evan/shattered-pixel-dungeon/blob/master/core/src/main/java/com/shatteredpixel/shatteredpixeldungeon/actors/Char.java):
  후속 피해/사망 구현 비교 대상. 이 단계에서 전체 로직을 분석하거나 이식하지 않았다.
- 후속 조사 위치: 같은 actors 폴더의 `hero/Hero.java`, `mobs/Mob.java`.

참고 링크는 master여서 변경될 수 있다. 실제 코드를 이식할 단계라면 revision과
GPL-3.0-or-later 조건부터 별도로 고정한다. 현재 원형은 해당 게임의 포트가 아니다.

## 검증

`godot --headless --path . --log-file /tmp/combat-core-stage1.log --script tests/combat_core_stage1.gd`

통과: 잘못된 입력/벽 이동의 상태 보존, 행동 시간, 즉시 사망과 반격 차단,
사망 타일 점유 해제, 반복 입력 결정성, 패배 이후 입력 차단.
실제 기기의 터치 반응과 렌더링 체감은 아직 검증하지 않았다.

## 다음 단계

이 원형에서 이동/공격 감각 확인 후 행동별 시간과 단일 시야 조회를 연결한다.
그 뒤 기존 게임과 연결할 어댑터를 만들고, 마지막에 성격/육체를 붙인다.
프로토타입을 또 하나의 운영 전투 경로로 남기지 않고, 교체 시 기존 경로 제거 범위를 명시한다.
