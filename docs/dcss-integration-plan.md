# DCSS 밸런스 적용 설계

최종 사용자 선택: 원본 규칙을 분석해 기존 코드로 구현하고 초반 던전에 필요한 목록만 실제 적용한다. 원본 C++·YAML·아트 파일을 제품에 복사하지 않는다. 전투 공식·AI·부상·숙련 엔진은 현재 구현을 사용한다.

기준은 [DCSS 0.34.1](https://github.com/crawl/crawl/tree/0.34.1), commit `1eebc1a2892e1c89776a0d7a10691f8dac8d9796`이다. 무기 기본 피해·명중 보너스·지연, 몬스터 HP·HD·AC·EV·일반 공격 수치, 기존 종족 기본값을 분석해 현재 단위로 변환한다. 원작 전투 확률분포를 정확히 재현하는 작업은 아니다.

실제 제품 진입점은 `playtest/entry_router.tscn` → `party_encounter_sandbox.tscn`이다. 콘텐츠 JSON, 종별 전투/인지 프로필 조회, 캠페인 층별 출현 후보, 바닥 장비 전리품에 연결한다. 옵션용 `game/rebuilt` 데모는 이번 적용 대상에 포함하지 않는다.

최종 목록과 적용값은 [콘텐츠 목록](dcss-content-catalog.md), 실행 범위는 [protocol](dcss-balance-protocol.md), 검증과 한계는 [결과](dcss-balance-result.md)에 기록한다.
