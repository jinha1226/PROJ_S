# 독립 던전 실행부 재구축

## 범위

기본 진입점을 `game/rebuilt/game.tscn`으로 교체했다. 기존 캠페인의 매 턴 실행 경로를 우회하는 독립 게임 상태이며, 기존 코드와 저장 파일은 삭제하지 않았다.

- 기본 주소: 새 던전 실행부
- `?legacy=1` 또는 네이티브 `--legacy-game`: 기존 게임
- `?prototype=combat`: 이전 전투 실험 화면
- 새 저장: `user://rebuilt_dungeon_v1.json`, 임시 파일과 `.bak` 사용

구현 범위는 64×64 던전, 이동/전투/즉시 사망, 적 추적과 성격 기반 후퇴, 6칸 시야와 지형 기억, 횃불/고정 광원, 자동탐험, 회복약/금화, 층 이동, 상태창, 저장/복구다. 한쪽 벽 모서리의 대각선 이동은 허용하고 양쪽이 벽인 틈은 막는다.

**기존 게임과 기능 동등한 완성품은 아니다.** 마을, 동료 관계, 기존 장비/능력 전체, 상세 부위 손상은 아직 이식하지 않았다. 혈액 표시는 현재 HP 비율에서 파생되며 뼈 강도는 기본값이다. 이러한 기능은 기존 게임에 보존되어 있다.

## 구조

- `world.gd`: 단일 정본 상태와 행동 처리. 입력이 없으면 시뮬레이션을 돌리지 않는다.
- `min_heap.gd`: 절대 행동 시각 기반 스케줄러와 경로 우선순위 큐.
- `navigation.gd`: 플레이어 경로는 배열 기반 A*, 적 추적은 목표별 공유 거리장. 거리장은 최대 8개, 14칸 범위이며 동적 점유는 다음 이동 시 검사한다.
- `board.gd`: 화면 주변 타일만 그리기, 타일 자료 캐시, 120ms 이동 보간. 애니메이션이 끝나면 프레임 처리를 중단한다.
- `game.gd`: 입력/UI/자동이동 타이머/지연 저장. 기존 이벤트 저널과 저장 경로를 공유하지 않는다.

시야는 플레이어 위치가 바뀔 때 갱신한다. 고정 광원은 층 생성/복구 때 미리 계산한다. 그리기 중 광원 LOS 계산이나 전체 게임 상태 복제는 없다. 시야 밖 적은 그리지 않고 기억한 지형과 광원만 어둡게 표시한다.

기존 지도 생성기, 타일/캐릭터 자산, HEXACO 자료, 공통 이동/시야 기하 규칙은 재사용했다.

## 참고 방식

Shattered Pixel Dungeon의 [Hero.java](https://github.com/00-Evan/shattered-pixel-dungeon/blob/master/core/src/main/java/com/shatteredpixel/shatteredpixeldungeon/actors/hero/Hero.java), [Actor.java](https://github.com/00-Evan/shattered-pixel-dungeon/blob/master/core/src/main/java/com/shatteredpixel/shatteredpixeldungeon/actors/Actor.java), [PathFinder.java](https://github.com/00-Evan/shattered-pixel-dungeon/blob/master/SPD-classes/src/main/java/com/watabou/utils/PathFinder.java)를 통해 입력 대기/행동 시간/목표 거리장 구조를 참고했다. 해당 소스를 복사하거나 번역 이식한 것이 아니라 프로젝트에 맞춰 독립 구현했다. DCSS 전투 전체를 이식했다는 의미도 아니다.

## 검증

명령: `godot --headless --path . --script tests/rebuilt_runtime_acceptance.gd`

통과 항목: 실제 맵 초기화, 대각선 모서리 규칙, 실패 행동 원자성, 물 이동 비용, 시야 캐시, 반경, 즉시 사망과 점유 해제, JSON 정확한 왕복과 결정적 재개, 잘못된 저장 거부, 물 경로, 100명 적 처리, 자동탐험.

로컬 Godot 4.6.2 headless 측정:

| 작업 | 중앙값 | p95 |
|---|---:|---:|
| 물 10칸 목적지 경로, 50회 | 1.063ms | 1.211ms |
| 100명 적 배치에서 대기, 30회 | 0.652ms | 0.790ms |

공유 거리장 적용 전 새 실행부의 적별 A* 버전은 같은 종류의 밀집 테스트에서 중앙값 약 339ms였다. 이는 개발 중 새 실행부 간 비교이지 기존 게임 전체와의 대조 벤치마크가 아니다. 표 수치는 렌더링/저장/모바일 브라우저를 포함하지 않으며, 정지한 플레이어와 캐시 재사용에 유리한 조건이다. 실기기 이동 중 프레임 지연의 보증으로 해석하지 않는다.

Web 릴리스 내보내기 성공. Chromium의 390×844 터치 에뮬레이션에서 화면과 터치 이동 확인. 새로고침 후 위치, 시간 200, 횃불 연료 19800이 유지되고 저장 복구 메시지가 표시됨을 확인했다. 실제 휴대폰에서의 장시간 자동탐험/발열/프레임 시간은 추가 검증 대상이다.
