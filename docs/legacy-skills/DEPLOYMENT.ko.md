# Legacy 기본 배포 복원

앞선 main 병합은 사용 기반 숙련 코드를 legacy에 추가했지만, entry router와 Pages workflow는 Model B를 기본으로 유지했다. 사용자가 지적한 GitHub Actions와 실제 배포 대상의 불일치를 수정한다.

- 기본 실행은 `playtest/party_encounter_sandbox.tscn`.
- main push의 `Test and deploy Legacy Web`은 legacy 기본 부팅, 사용 기반 숙련 sequence, 기존 저장 복원을 검증하고 Pages에 배포한다.
- export한 PCK만 있는 별도 폴더에서도 기본 장면이 legacy인지 검증한다. 소스 트리의 fallback을 허용하지 않는다.
- `Model B tests and playable builds`는 수동 실행으로 유지한다. 해당 export에만 `model_b` feature를 넣어 선택된 게임과 artifact 이름을 일치시킨다.
- Model B 코드는 보존하며 `--model-b` 또는 Web `?demo=crawl`로 선택할 수 있다. 기존 legacy/prototype/rebuilt 선택도 유지한다.

회귀 검사 `tests/legacy_default_boot_smoke.gd`는 실제 ProjectSettings의 시작 장면을 로드하고 router를 거쳐 도착한 장면, legacy session, 시작 직업 선택 UI를 확인한다. legacy 클래스를 직접 생성하는 테스트로 기본 배포 대상 검사를 대신하지 않는다.
