# DCSS-BALANCE-01 결과

2026-09-13. 사용자 최종 범위인 규칙 분석 후 기존 코드 구현·초반 목록 실제 적용을 완료했다. 기준 게임 commit은 `b0d60ac`, 원본 분석 기준은 DCSS 0.34.1 commit `1eebc1a2892e1c89776a0d7a10691f8dac8d9796`이다.

## 적용 결과

DCSS 대응 무기 19종(기존 7 + 신규 12), 몬스터 8종(기존 2 + 신규 6)을 실제 콘텐츠에 연결했다. 원본 C++ 전투/AI 구현은 반입하지 않았다. 전체 참고 목록은 몬스터 정의 668개·무기 정의 59개이며, 실제 등록 목록과 분리된다. [종별 목록과 수치](dcss-content-catalog.md)를 참고한다.

무기 피해·공격 지연과 갑옷 AC, 기존 인간/엘프/드워프 종족 능력치, 기존 두 몬스터 HP·전투 수치를 조정했다. 기본 종족 능력치는 인간 5/5/5, 엘프 3/6/8, 드워프 6/3/5다. 신규 몬스터는 종별 전투 프로필·인지·기본 공격·장비·드롭을 사용한다. 1층 HD 1, 2층 HD 1–2 후보를 seed 기반으로 선택한다. 신규 무기는 층별 최소 깊이에 따라 바닥 전리품으로 최대 4개씩 배치한다. 전용 아트와 신체는 기존 대용 데이터를 사용한다.

무숙련 인간의 raw damage/공격·재장전 총 시간 샘플:

| 무기 | 피해 | 시간 |
|---|---:|---:|
| 소검 대응 | 25 | 100 |
| 레이피어 대응 | 35 | 120 |
| 손도끼 | 35 | 130 |
| 철퇴 | 40 | 140 |
| 창 | 30 | 110 |
| 단궁 대응 | 40 | 140 |
| 쇠뇌 대응 | 80 | 190 |

## 검증

- [JSON 콘텐츠](dcss-validation/content.log): 5 tests, 0 failed. 스키마·ID 참조·종족 수치 권위 확인.
- [무기 전투](dcss-validation/weapons.log): 9 tests, 0 failed. 실제 피해/시간·숙련·탄약/재장전·XP 확인.
- [통합 acceptance](dcss-validation/acceptance.log): PASS. 신규 6종 실제 엔티티 생성·종별 프로필/공격 spec·신규 12무기 지급/장착/해제/드롭, 80개 seed의 2층 출현 결정성·HD 제한, world audit와 snapshot 복원 일치, 실제 제품 새 게임/전투 행동·새 콘텐츠 전리품/출현·저장 journal 재생 일치, 구 밸런스 저장 거부 시 현재 세션 보존 확인.
- 작성 도구 재실행 후 콘텐츠·참조 JSON SHA-256 변경 없음. `git diff --check` 통과.
- [기존 solo-start 테스트](dcss-validation/legacy-solo-start.log): `solo departure accepted: town_required` 1개 실패. 현재 제품의 거점 비활성화 상태에서 거점 출발을 요구하는 기존 테스트다. 해당 거점 제거 동작을 이번 작업에서 변경하지 않았다. 위 통합 검증은 현재 직접 던전 시작 경로를 검증한다. 이 기존 테스트를 통과했다고 보고하지 않는다.

## 단위 변환과 한계

HP는 참고 평균 HP ×10, 일반 공격 피해 목표는 DCSS 피해 ×5, aut는 ×10이다. 기존 고정 피해 공식의 actor power 24를 무기 기본 피해에서 차감하며, 음수 기본 피해는 허용하지 않아 매우 약한 무기의 무숙련 인간 피해 하한은 24다. AC는 기존 flat armor에 ×2로 압축했다. 명중·EV·장비 능력치 요구량과 출혈은 현재 엔진에 맞춘 자체 근사다. 무작위 AC, 원작 명중분포·몬스터 장비 선택 분포·전투 확률분포·무기 브랜드·특수 무기 성질은 재현하지 않는다. 무장 몬스터의 공격력과 자연 공격은 기존 고정 power 모델을 사용하므로 무기 상실 후 피해까지 원작과 같다고 보장하지 않는다.

독·주문·비행·변신·고유 저항 등 현재 엔진에서 대응하지 않는 몬스터는 실제 등록에서 제외했다. 신규 전용 아트/해부학과 원작 던전 출현표·아이템 희귀도는 포함하지 않는다. 거점/반복 원정 제거 상태를 유지한다. 별도 옵션인 `game/rebuilt` 데모는 대상이 아니다.

밸런스가 달라지면 과거 전투 journal이 정확히 재생되지 않으므로 이전 marker 없는 세션은 명시적으로 새 게임을 요구한다. 저장 파일을 자동 삭제하거나 변환하지 않는다. 변경 후 새 게임 저장은 정확히 재생된다.

## 재실행

Godot 4.6.2에서 다음 스크립트를 `godot --headless --path . --script <경로>`로 실행한다:

- `tests/run_json_content_database_tests.gd`
- `tests/run_weapon_combat_tests.gd`
- `tests/dcss_balance_acceptance.gd`

전체 수치 참고 목록 재생성은 `python3 tools/build_dcss_balance_catalog.py --source <고정 commit 체크아웃> --item-properties <동일 버전 item-prop.cc>`(PyYAML 필요), 자체 초반 콘텐츠 작성은 `python3 tools/build_dcss_playable_content.py --root .`이다. 기존 7무기·종족·갑옷의 변경 전후 수치는 `data/content/dcss_balance_reference.json`에 기록한다. 원본 소스 체크아웃은 저장소 밖에서만 분석에 사용한다.
