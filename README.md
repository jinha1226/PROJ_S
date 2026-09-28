# 횃불과 원소 (PROJ_S)

모바일 세로 화면에서 한 손으로 하는 턴제 던전 크롤러. HTML 파일 하나(Three.js CDN)로 돈다.
위험을 읽고, 원소·지형·소모품·영혼석 빌드로 무너뜨리고, 원정에서 돌아와 작은 마을을 키운다.

- **플레이**: GitHub Pages — `https://jinha1226.github.io/PROJ_S/` (이전 단계: `versions/v1.html`, `versions/v2.html`)
- **로컬**: `index.html`을 브라우저로 열면 된다(인터넷 필요 — Three.js를 CDN에서 받는다).
- 진행은 브라우저 localStorage에 저장된다. 타이틀의 "처음부터"로 지운다.

## 구성

| 파일 | 내용 |
| --- | --- |
| `index.html` | 현재 판(3차까지): 전투·원소·지형·소모품 → 영혼석 빌드·공격 형태 → 구역 원정·보스·정착지(HEXACO NPC) |
| `versions/v1.html`, `v2.html` | 1차·2차 결과 보존본 |
| `docs/prompts/` | 단계별 제작 프롬프트(1차·2차·3차·사이·추가 장비) |
| `docs/설계_아이템_장비.md` | 다음 단계(장비) 설계 |
| `tests/smoke.mjs` | 헤드리스 크롬 스모크 테스트 |

`index.html` 안의 `<script id="diorama-kit">` 블록이 카메라·조명·셰이더·격자·이펙트이고, 게임 규칙과 분리되어 던전(`preset: 'dungeon'`)과 정착지(`'settlement'`)가 같이 쓴다.

## 테스트 · 배포

`main`에 push하면 GitHub Actions가

1. 헤드리스 크롬으로 `tests/smoke.mjs`를 돌리고(로드·정착지·출발·무작위 200턴·영혼석 24종·보스 귀환·이전 버전 로드), 스크린샷을 아티팩트로 올린 뒤
2. 통과하면 GitHub Pages로 배포한다.

로컬에서:

```bash
npm install
npx playwright install chromium
npm test
```

## 이전 Godot 본편

2026-09-29 이전의 Godot 프로젝트는 `backup/main-godot-20260929` 브랜치에 있다.
