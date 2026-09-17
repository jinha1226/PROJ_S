# 조사 및 문서 검증

2026-09-17, 정적 소스 분석 보고서.

## 원본 확인

- 공식 주소: https://github.com/crawl/crawl
- `git clone --depth 1`로 원본을 내려받아 C++·Lua·YAML·DES를 직접 읽었다.
- 최초 확인과 최종 재확인 모두 remote `refs/heads/master`가 `2bd8e06e6e5614a6f4917c1c24e04a8922319476`였다.
- commit 시각: 2026-09-16 21:19:28 UTC. changelog는 0.35 개발 계열이다.
- 보고서가 링크하는 기준은 이동하는 master URL이 아니라 해당 commit이다.

## 수행한 검증

- `scripts/audit_sources.py`: 기준 commit, 98개 소스 앵커의 존재와 행 위치, 파일 SHA-256 기록.
- 선택 가능한 기본 종족 정의 27개, 제거 skill과 enum alias를 제외한 skill 29개, no-god/Pakellas 제외 신 26개를 정적 데이터로 대조.
- 몬스터 YAML 683개는 테스트/파생형/비출현 entity를 포함하는 파일 수라고 명시.
- 비제거 book spell enum 참조 132개는 전처리·런타임 availability를 모두 반영한 주문 총수가 아니라고 명시.
- `scripts/build_report.py`: 요구 순서의 25개 장, 인용 ID와 정의, 문서 내 로컬 파일 링크, 집계 값 검사.
- Python 스크립트 문법 검사, Pandoc HTML 생성, Git whitespace 검사.
- 문서의 실제 규칙과 제안 규칙을 구분하고, 시간·일정·사용성 목표가 실측 결과가 아님을 확인.

정량 집계에서 단순 명칭 수와 기능 수를 혼동하지 않도록 했다. 원작에 남아 있는 레거시 enum을 활성 기능으로 세지 않았으며, 선언만 확인한 대표 능력은 실행 코드와 교차 검토했다. 조사 과정에서 skill 수는 enum의 실제 활성 항목을 재집계해 29개로 확정했다.

## 수행하지 않은 것

- DCSS 빌드·플레이·seed별 던전 생성 실행·밸런스/승률 시뮬레이션.
- 모바일 prototype 구현·실기기 UI/사용성 테스트·시장성 조사.
- 98개 외부 링크 각각의 HTTP 응답 검사. 대신 고정 commit checkout의 실제 경로와 앵커 존재를 검사했다.
- HTML 브라우저 screenshot 검토. HTML은 CSS 내장본이며 Mermaid 도식은 코드 블록으로 보존한다. Markdown은 Mermaid 지원 뷰어에서 도식으로 읽을 수 있다.

이 문서의 검증 통과는 코드 근거와 산출물 무결성에 대한 것이며, 제안된 게임의 재미·난이도·매출·일정을 검증했다는 의미가 아니다. §23의 1,000 seed 검사와 사용자 관찰은 후속 개발에서 수행할 제안이다.
