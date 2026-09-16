# 판타지 몬스터 에셋 적용

2026-09-16. 내장 image_gen으로 원본을 생성하고, 승인된 코드 방식으로 배경 제거·분리·크기 조정을 수행했다.

## 미리보기

- [전체 12종과 24·32·48px 비교](sprites.png)
- [게임 렌더러로 던전 바닥에 배치한 화면](runtime.png)
- [생성 원본과 프롬프트](../../../art/sources/fantasy_monsters_v1/README.md)
- [개별 게임용 PNG](../../../assets/fantasy_pawns_v1/monsters)

## 적용 목록

| 몬스터 | 실제 ID |
|---|---|
| 화염도마뱀 | `fire_lizard` |
| 서리거미 | `frost_spider` |
| 물슬라임 | `water_slime` |
| 전기뱀장어 | `electric_eel` |
| 쥐 | `dcss_rat` |
| 강가쥐 | `dcss_river_rat` |
| 목도리도마뱀 | `dcss_frilled_lizard` |
| 놀 | `dcss_gnoll` |
| 홉고블린 | `dcss_hobgoblin` |
| 코볼트 | `kobold` |
| 슬라임 | `slime` |
| 딱정벌레 | `beetle` |

고블린은 기존 종족 베이스를 유지하고, `dcss_orc`는 오크 베이스로 연결했다. 현재 저층 스폰에 등록된 6개 `dcss_*` 종과 원소 몬스터 4종이 모두 전용/해당 종족 그림을 사용한다. 이전의 일반 인간 그림 대체를 해소했다. 기존 몬스터 ID와 전투·드롭·스폰 규칙은 그대로다.

투명 RGBA 128px 원본을 한 칸 캔버스로 표시한다. 쥐·강가쥐·딱정벌레·코볼트에는 서로 다른 축소 비율을 적용했다. 단일 포즈이며 걷기 애니메이션은 없다. 원소 특수부위는 몸에 포함된 색·형태로 표현한다. `runtime.png`는 실제 에셋 매핑과 그리기 함수를 사용한 검토용 고정 배치이며, 실전 조우 스크린샷은 아니다.

## 재생성과 검사

```bash
python3 tools/art/build_fantasy_monsters.py
godot --headless --path . --editor --quit
godot --headless --path . --script tests/fantasy_pawn_assets_acceptance.gd
godot --display-driver x11 --path . --script tools/art/preview_fantasy_monsters.gd
```

추출 스크립트는 Pillow·NumPy·SciPy와 기존 `build_fantasy_pawns.py`의 배경 제거 함수를 사용한다. 원본 해시와 영역·크기·발 기준점은 `monsters/extraction.json`에 기록한다. 마지막 도구의 출력은 `/tmp/fantasy-monsters-runtime.png`다.

검사 항목: 12종 알파·전경·규격, 종별 실제 텍스처 연결, 원본 종족 ID 보존, 한 칸 크기 유지, 저층 몬스터 등록 목록의 누락, 기존 미제작 종의 대체 경로. 기존 에셋 통합 테스트에 포함하여 GitHub Actions에서도 실행한다.

검증 결과: PNG 12개 검사 PASS, Godot 임포트·스크립트 검사 오류 없음, `FANTASY PAWNS: PASS`, 화면 렌더링 도구 종료 코드 0. 24·32·48px 비교와 실제 런타임 배치 화면을 시각적으로 확인했다.
