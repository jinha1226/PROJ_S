# Room Tactics Prototype v1

Darkest Dungeon의 원정 압박과 Into the Breach의 짧은 텔레그래프 전투를 검증하는 독립 프로토타입입니다.

- 7×7 방, 영웅 3명, 적 3명
- 한 방은 최대 5턴
- 플레이어 턴 시작 시 모든 적의 다음 행동을 공개
- HP와 Stress를 별도 압박 축으로 사용
- 영웅별 이동/공격/방어 1회 후 턴 종료
- 적 의도는 플레이어 행동 뒤 다시 계산되어 화면에 즉시 반영
- 방어는 해당 적 턴의 HP 피해를 2 감소

실행:

```bash
godot --path . -- --room-tactics
```

웹에서는 `?prototype=room-tactics`를 사용합니다.

이 프로토타입은 기존 Model B/파티 조우 코어를 교체하지 않습니다. 재미 검증 후 원정 상태(방 6~10개, 방 단위 자동 저장, HP/Stress/부상 지속)와 연결하는 것을 다음 단계로 둡니다.
