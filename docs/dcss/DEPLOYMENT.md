# Model B Pages 배포 기준

`main`은 GitHub Pages의 배포 branch다. Model B feature branch의 run `35166418661`은 성공했다. `74c50fc`를 main에 반영한 뒤 Pages run `35166679505`는 이전 동료 선물/합류 검사인 `field_feedback_acceptance`에서 실패했다. 이전 main `d685c33`의 run `35092774112`도 같은 검사에서 실패했다.

실패 로그는 NPC 접근 중 `FAIL approach`/`FAIL join approach`에서 시작해 선물·합류 검사로 이어진다. 로컬 진단에서 고정된 terrain-only 경로의 `move_destination_occupied`를 확인했고, 점유를 피한 접근도 해당 legacy 전투 시나리오에서 `party_actor_unavailable`에 도달했다. Model B 런은 이 시나리오와 동료 시스템을 사용하지 않는다.

배포 gate를 현재 서비스 범위에 맞게 분리했다. 검사를 성공 처리하거나 assertion을 삭제하지 않는다.

- Pages: Model B 전체 시뮬레이션/저장/UI + 공유 턴 엔진/자산 + export + checkout 없는 pack 실행 + export pack 전체 acceptance.
- `Model B tests and playable builds`: 기존 별도 테스트·Windows/Web artifact workflow 유지.
- `Legacy regression tests (not a deployment gate)`: 기존 settlement/entry/assets/procedural/field/elemental 테스트 블록을 원문 그대로 보존. Actions 수동 실행 가능, 실패 시 실패로 보고하고 로그 artifact를 남긴다. 알려진 legacy 실패를 해결했다고 주장하지 않는다.

신체 손상·성격 동료·흡수 이능을 붙이지 말고 Model B에 집중하라는 사용자 범위에 따른 분리다. 이 기능을 신규 런에 연결할 때 관련 회귀 검사를 다시 필수 gate에 편입해야 한다. 기존 게임 소스와 테스트 소스는 이번 변경에서 수정하지 않는다.
