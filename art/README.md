# 아트 작업 자료

게임에 들어가는 파일은 [assets/](../assets/README.md), 실제 적용 화면은 [docs/art/](../docs/art/README.md)에 있다. 이 폴더는 원본·참고·이전 시안을 보관한다. `.gdignore`와 Web 내보내기 제외 규칙으로 게임 리소스에 포함하지 않는다.

## 현재 사용할 자료

| 구분 | 폴더 | 역할 |
|---|---|---|
| 제작 원본 | [sources/fantasy_pawns_v1](sources/fantasy_pawns_v1/README.md) | 종족·아이템·입체감 있는 타일 원본, 프롬프트, 해시·배치 정보 |
| 제작 원본 | [sources/fantasy_monsters_v1](sources/fantasy_monsters_v1/README.md) | 현재 몬스터 시트와 프롬프트 |
| 스타일 기준 | [references/fantasy-pawns](references/fantasy-pawns/README.md) | 단순한 판타지 폰 스타일. 평면 벽 후속 실험은 보관용이며 현재 벽 제작 기준이 아니다. |
| UI 배치 참고 | [references/ui/main-menu-pixel-icons-gameplay-v4.png](references/ui/main-menu-pixel-icons-gameplay-v4.png) | 상단 상태, 상시 스킬, 하단 명령 배치 참고. 현재 실제 UI는 docs/art 참고. |
| 이전 시안 | [archive/](archive/README.md) | 다른 화풍, 폐기한 픽셀·캐릭터 시트, 이전 화면 캡처 |

## 새 작업을 추가할 때

1. 새로 생성한 시안·비교 결과는 `archive/` 아래 별도 주제 폴더에 저장한다.
2. 채택한 참고 이미지는 `references/`, 제작에 쓰는 원본과 프롬프트·출처는 `sources/`에 둔다.
3. 잘라내기·투명화한 실제 게임 이미지만 `assets/`에 추가한다. 사용처와 기존 이미지 대체 여부를 해당 README에 적는다.
4. 실제 게임 크기로 확인한 결과는 `docs/art/`에 저장한다.

현재 재가공 도구:

```bash
python3 tools/art/build_fantasy_pawns.py
python3 tools/art/build_fantasy_monsters.py
```

이 명령은 현재 런타임 에셋을 다시 생성하므로, 원본 수정 후 검토할 때 실행한다. 단순히 시안을 보려면 각 README와 이미지 링크를 사용한다.

## 2026-09-16 정리 확인

- 기존 추적 파일 307개를 이동했다. 이 중 이미지 176개(약 84MiB)는 SHA-256 대조로 내용이 동일함을 확인했다.
- 제작 도구 2개의 새 원본 경로와 원본 manifest 해시, 기존에 연결되던 Markdown 링크를 검증했다.
- `fantasy_pawn_assets_acceptance.gd`와 Godot 에디터 리소스 가져오기가 통과했다.
- Web 내보내기와 별도 빈 폴더에서의 패키지 단독 실행이 통과했다. `art/` 자료는 내보내기에 포함되지 않았다.
