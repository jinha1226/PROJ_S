# 마지막 불씨 · Last Ember

모바일 세로 화면에서 한 손으로 조종하는 등불지기 던전 게임. 이동·대기 중에만 시간이 흐른다. 브라우저 ES 모듈과 Three.js CDN을 사용하며 빌드 과정은 없다.

`새로_시작/`의 1~5차 프롬프트를 기준으로 시뮬레이션과 3D 화면을 처음부터 다시 작성했다. 이전 실행 코드는 Git 이력에 남아 있다.

## 실행

정적 서버에서 `index.html`을 연다. 개발 도구는 Node 22 이상.

```sh
npm install
npm run serve
npm run lint
npm run test:rules
npx playwright install chromium
npm test
npm run measure
```

모바일: 화면 아래를 누르고 끌어 이동, 손을 떼면 멈춤. 두 손가락 회전·핀치, 시점 버튼. PC: WASD/방향키, Space 대기. 화면 위쪽 적 선택·바닥 자동 걷기. 물건을 고른 뒤 화면을 눌러 던진다.

튜토리얼에서 첫 주민을 구하고, 불가에서 건설과 원정을 진행한다. 훈련장을 짓고 구역을 되찾으면 동료가 늘어난다. 마지막 구역은 등불지기와 동료 네 명이 필요하다. 새벽 이후 이번 주의 레이드가 열린다.

## 검증과 배포

`main`에 푸시하면 GitHub Actions가 의존·문법 검사, Node 규칙 테스트, 전투 측정, PC·모바일 Chromium 테스트를 실행한다. 성공한 버전만 GitHub Pages에 배포한다. 스크린샷과 `measure.json`은 Actions의 `test-results` 아티팩트에 남는다.

프롬프트와 구현의 연결 조건, 아직 검증하지 못한 범위는 `docs/implementation.md`에 기록한다.
