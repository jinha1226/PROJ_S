# Pages 배포 런타임 리소스 누락 수정

2026-09-16. 사용자 보고: 메인 푸시 후 GitHub Actions 실패.

## 원인

실패 실행: https://github.com/jinha1226/PROJ_S/actions/runs/35032089751 (`f2d6b0b`).

`Export Web build`까지 성공하고 `Validate exported pack runtime`에서 실패했다. 첫 오류는 `topdown_tile_assets.gd`가 preload하는 `stone_floor.png` 누락이며, 같은 지형·벽·문 이미지 누락이 연쇄 스크립트 오류를 일으켰다.

`export_presets.cfg`가 `assets/generated/*` 전체를 제외하고 있었다. 소스 체크아웃에서는 파일이 존재해 UI 테스트를 통과하지만, 소스 없이 PCK만 실행하면 실패한다. 수정 전 설정으로 로컬 PCK를 만들고 빈 작업 폴더에서 실행해 동일 오류를 재현했다.

## 변경

광범위한 generated 제외를 사용하지 않고 미사용 이미지 묶음과 source/review 디렉터리를 명시적으로 제외한다. `topdown_tactical64_v1/runtime`과 `topdown_walls_doors64_v1/runtime`을 포함한다. 동적 로딩에 사용하는 `item-icons-v1`도 포함한다. 직접 참조되는 지형 PNG 32개가 모두 Git 추적 대상임을 확인했다.

CI의 배포 파일 실행 검사를 유지하고, `Resource file not found` 오류도 실패로 판정하도록 보강했다. 지형 이미지 수정 후 검사에서 동적 로딩 아이템 아이콘 `padded.png` 누락도 발견해 함께 수정했다.

## 검증

수정 후 Web PCK를 다시 생성하고 소스 체크아웃 밖의 빈 폴더에서 `godot --headless --main-pack <pack> --quit-after 5`로 검사했다. 종료 코드 0, SCRIPT ERROR 및 ERROR 0건으로 통과했다. Godot의 root 실행 경고만 출력됐다. 실제 Pages 배포 결과는 수정 커밋의 GitHub Actions 실행에서 확인한다.
