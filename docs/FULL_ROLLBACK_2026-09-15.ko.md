# 큰 맵·기존 필드 턴 버전 전체 복원

- 사용자 승인: 8×8 이전의 큰 맵, 기존 동료 전술, 기존 턴 처리로 전체 롤백. 이후 UI·아트 변경도 함께 되돌림.
- 복원 전 HEAD: `79f1f17`. 보존 브랜치: `backup/before-full-rollback-20260915`.
- 복원 대상: `c59c969`. 이후 `9099bc5`에서 48×48 four-zone 맵이 도입되었으므로 예약 라운드 직전 `5853fba`보다 앞선 이 버전을 선택했다.
- 정확한 기존 층 크기: 1층 80×80, 2층 96×96. 두 층 모두 방별 8×8 이동 제한 없는 기존 생성기를 복원했다. 모든 층을 96×96으로 새로 변경하지 않았다.
- 추적 파일 전체를 대상 커밋에서 복원했다. 이 결과 문서를 추가하기 전 `git diff --cached c59c969 --exit-code`와 `git diff --exit-code` 모두 종료 코드 0으로 대상과 동일함을 확인했다.
- 이전 기록은 Git 이력과 보존 브랜치에 남아 있다. 기존 미추적 파일과 사용자 저장 데이터는 삭제하지 않았다. 새 버전 저장 파일의 구버전 호환성을 보장하지 않으며 실제 사용자 저장 로드는 검증하지 않았다.

## 검증

Godot 4.6.2, 현재 작업 폴더에서 실행.

- `godot --headless --path . --editor --import --quit`: 통과, 스크립트 오류 없음.
- `godot --headless --path . --quit-after 5`: 종료 코드 0. 헤드리스 시작 검사이며 수동 모바일 플레이 검사는 아니다.
- `tests/compact_campaign_floor_smoke.gd`: 0 failures. seed 1/44/256의 두 층 생성, 연결성, 적과 보급 위치 검증. seed 44에서 80×80 및 96×96 확인.
- `tests/companion_order_smoke.gd`: 0 failures. 동료 예약·취소·자동 행동 복귀·UI의 시간 무소모 검증.
- 원본 `tests/field_turn_acceptance.gd`: 실패. 최초 공격에 미장착 `STRIKE`를 사용해 `active_skill_not_equipped`가 발생하고 직접 공격 확인이 연쇄 실패한다. 복원 대상에 포함된 `docs/ABILITY_INVENTORY_AUDIT.ko.md`는 STRIKE 무료 지급 제거를 이미 기록하고 있다.
- 추가 필드 검사: `FIELD TURN: PASS []`, 종료 코드 0. 대기 시간 진행, 이동·일반 공격, 실패 행동의 원자적 롤백, 전술 명령, 전투 모드 전환 없음, 저장 저널 재생 일치, 마을 출발을 검증했다.

추가 필드 검사는 원본 테스트를 `/tmp/full_rollback_field_turn_acceptance.gd`로 복사하고 다음 표현식 한 곳만 교체하여 실행한다. 제품 코드 및 원본 테스트는 변경하지 않는다.

```gdscript
# 기존
session.strike_with_skill("STRIKE",target) if attacks==0 else session.strike_enemy(target)
# 임시 검증본
session.strike_enemy(target)
```

실행: `godot --headless --path . --script /tmp/full_rollback_field_turn_acceptance.gd`.

푸시·배포는 수행하지 않았다.
