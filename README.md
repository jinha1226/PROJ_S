# 횃불과 원소 (PROJ_S)

모바일 세로 화면에서 한 손으로 하는 턴제 던전 크롤러. 빌드 도구 없이 브라우저 ES 모듈 + Three.js(CDN)로 돈다.
세상에 남은 마지막 모닥불은 사람으로 탄다 — 원소·지형·소모품·영혼석 빌드로 어둠의 주인을 쓰러뜨리고, 되찾은 등불 조각으로 흩어진 사람들을 불러 모은다.

- **플레이**: GitHub Pages — `https://jinha1226.github.io/PROJ_S/` (이전 단계: `versions/v1.html` ~ `v3.html`)
- **로컬**: 저장소 루트에서 `python3 -m http.server 8000` → `http://localhost:8000` (모듈이라 `file://` 더블클릭으로는 안 열린다. 인터넷 필요 — Three.js를 CDN에서 받는다). `?seed=123`을 붙이면 같은 층이 나온다.
- 진행은 브라우저 localStorage에 저장된다. 타이틀의 "처음부터"로 지운다.

## 구성

| 경로 | 내용 |
| --- | --- |
| `index.html` | 화면 틀·CSS·importmap. `js/main.js`를 불러온다 |
| `js/` | 게임 코드. `data/`(표) · `core/`(규칙, 화면을 모름) · `render/`(3D, `render/diorama.js` = DioramaKit) · `ui/` · `town/` · `flow.js`(모드 전환) · `main.js`(연결) |
| `versions/v1~v3.html` | 1차·2차·3차 한 파일 보존본 (v3 = 모듈로 나누기 전 원본) |
| `docs/코드정리_가이드.md` | **코드 구조와 규칙 — 기능을 추가할 때 먼저 읽는다** (§9 기능별로 고칠 파일) |
| `docs/prompts/`, `docs/설계_아이템_장비.md` | 단계별 제작 프롬프트, 다음 단계(장비) 설계 |
| `tests/smoke.mjs`, `tests/gear.mjs`, `tests/story.mjs`, `tests/stones.mjs` | 헤드리스 크롬 스모크 테스트, 장비 확인 목록(설계 §15), 스토리·정착지 확인 목록(설계 §9), 영혼석 액티브 스킬 확인 목록(설계 §6) |
| `docs/설계_영혼석_스킬.md` | 영혼석 = 액티브 스킬(쿨타임 + 색 감소), 24개 목록 (§8 적용 기록) |
| `docs/설계_스토리_정착지.md` | 마지막 불 줄거리 · 모닥불 밝기 · 방문자 · 등불지기 잇기 · 결말 (§11 적용 기록) |
| `tools/shots.mjs` | 화면 확인용 헤드리스 스크린샷(`test-results/`) |
| `tools/fix-imports.mjs` | 모듈의 빠진·안 쓰는·없는 import를 찾고 고치며 의존 규칙 위반을 알린다 (`npm run lint` / `npm run fix-imports`) |
| `tools/equivalence.mjs` | 리팩터링 전후 동작 비교 (`node tools/equivalence.mjs versions/v3.html index.html`) |

던전과 정착지는 같은 3D 체계(`render/diorama.js`)를 `preset: 'dungeon' | 'settlement'`로 바꿔 쓴다.

## 테스트 · 배포

`main`에 push하면 GitHub Actions가

1. import 검사(`npm run lint`), 헤드리스 크롬 `tests/smoke.mjs`(이전 버전 로드·정착지·출발·무작위 200턴·영혼석 24종·보스 귀환·콘솔 오류 0)·`tests/gear.mjs`(장비 확인 목록)·`tests/story.mjs`(스토리·정착지)·`tests/stones.mjs`(영혼석 스킬)를 돌리고, 스크린샷을 아티팩트로 올린 뒤
2. 통과하면 GitHub Pages로 배포한다.

로컬에서:

```bash
npm install
npx playwright install chromium
npm run lint        # import · 의존 규칙
npm test            # 스모크
node tests/gear.mjs # 장비
node tests/story.mjs # 스토리·정착지
node tests/stones.mjs # 영혼석 스킬
```

## 이전 Godot 본편

2026-09-29 이전의 Godot 프로젝트는 `backup/main-godot-20260929` 브랜치에 있다.
