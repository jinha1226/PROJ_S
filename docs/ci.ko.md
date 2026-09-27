# GitHub Actions 검사와 배포

`main` 푸시는 리소스 가져오기 → 선택 검사 → Web 내보내기·패키지 실행 확인 → Pages 배포 순서로 진행한다.

기본 검사는 `run_start`, `ui_smoke`, `mobile_hud`, `layout_guard` 4개다. 여기에 이전 푸시 이후 변경된 `.gd`·`.json` 파일과 연결된 검사를 추가한다. 파일명과 검사명이 같으면 자동으로 선택하고, 이름이 다른 기능은 `tools/ci/select_suites.py`의 `LINKS`에서 연결한다. 예를 들어 영혼석 카드 변경은 `stone_drop_ui`, 상태 VFX 변경은 `effect_vfx`를 추가한다. 의존 관계 전체를 분석하는 방식은 아니므로 큰 전투 규칙 변경은 전체 검사도 실행한다.

전체 104개 회귀·밸런스 검사는 삭제하지 않았다. GitHub **Actions → Test and deploy expedition → Run workflow**에서 `full_checks`를 선택하면 실행된다. 선택하지 않으면 기본 검사로 배포한다. 검사 목록은 `tools/ci/full-suites.txt`에 있다.

문서만 바뀐 푸시는 배포하지 않는다. Godot 실행 파일과 Web용 내보내기 템플릿은 캐시한다. 리소스 오류와 실제 Web 패키지의 실행 오류 확인은 모든 배포에 유지한다.

새 검사를 추가하면 전체 목록에 등록하고, 파일명이 다르면 `LINKS`에도 연결한다. 로컬에서 선택 결과를 확인하려면:

```bash
python3 tools/ci/select_suites.py expedition/ui/screens/stone_drop_card.gd
python3 tools/ci/select_suites.py --full
```
