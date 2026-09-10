# 환경 시뮬레이션 보완 protocol

실험 ID: `SOL-MEDIUM-ENV-002`

기준 commit: `f0f84c3`

부모 결과: `SOL-MEDIUM-ENV-001`, 구현 `920a351`, 결과 `b5696e9`

## 질문과 종료 조건

1차 구현에서 빠진 폭발 밀쳐냄·지형 파괴, 장비 소재와 부위 coverage에 따른 환경 피해, 연기의 실제 시야 차단을 기존 권위 상태와 결정론을 깨지 않고 추가할 수 있는지 검증한다. 각 효과는 저장 후 복원과 같은 명령 재실행에서 동일한 상태·event를 만들어야 한다.

종료 조건은 다음과 같다.

- 폭발은 시작 시점 점유 상태를 기준으로 개체당 최대 한 번만 밀고, 막힌 칸·경계·점유 칸으로는 밀지 않는다.
- 폭발 전파는 파괴 전 지형으로 엄폐 감쇠를 계산한 뒤, 기계저항을 넘은 닫힌 문과 약한 지형을 rubble로 바꾼다.
- 밀쳐냄과 파괴는 원인 explosion wave를 가리키는 사건을 남기며, 저장·복원 후 위치와 지형의 의미 검증이 통과한다.
- 기존 장비 definition ID에 별도 환경 방어 registry를 연결한다. 같은 결정론적 피격 부위에서 coverage가 맞을 때만 소재별 fire/electric 감소를 한 번 적용하고, body injury는 감소 후 에너지만 받는다.
- 젖음은 전기 절연 효과를 약화한다. 금속이라는 이유만으로 전기 피해를 자동 증폭하지 않는다.
- 높은 연기는 terrain LOS와 별도로 중간 타일을 차단한다. 출발·도착 타일의 연기는 해당 타일 자체 관측을 숨기지 않으며, UI와 적 인지의 공용 LOS 함수가 같은 규칙을 쓴다.
- 전용 검사, 원소·body·이동·저장 회귀, 성능 probe가 통과하고 결과를 기존 결과 문서에 추가한다.

## 구현 규칙

폭발은 wave 탐색 중 피해·밀쳐냄·파괴 후보를 수집하고 탐색이 끝난 뒤 정렬해 반영한다. 이 순서로 개체가 다음 wave 칸으로 밀려 중복 피해를 받거나 먼저 부서진 벽이 같은 폭발의 전파 거리를 바꾸는 일을 막는다. 밀쳐냄은 전투 행동 시간이 아닌 강제 위치 변화이며 별도 `environment.knockback` 사건과 위치 history 해석을 사용한다.

지형 파괴는 기존 tile의 열·표면·대기 상태를 보존하고 terrain, 소재, 기본 가연성·전도성, substrate fuel만 rubble 기준으로 바꾼다. topology를 바꾸므로 관측 cache는 world step과 terrain fingerprint를 함께 사용한다.

장비 wire를 바꾸지 않고 자체 작성한 `environment_armor_registry`가 현재 `ARMOR_LEATHER`, `ARMOR_PADDED`, `SHIELD_WOOD`의 소재, coverage와 원소 감소율을 제공한다. hit part는 기존 `BodyCombatRules.select_part()`를 한 번만 호출한다. HP와 body layer는 동일한 감소 후 피해를 사용하고 기존 물리 `armor_flat`은 다시 적용하지 않는다.

연기 차단 임계값은 중앙 환경 설정에 둔다. `EnemyPerceptionRegistry.has_line_of_sight()`가 중간 타일의 smoke를 읽으므로 적 인지, 스킬 reach와 필드 시야가 같은 권위 상태를 따른다. 화면 밖 환경도 계속 tick한다.

새 외부 코드·데이터는 사용하지 않는다. 모든 계수는 현실 측정값이 아닌 게임용 가정값이다. 기존 snapshot v12가 이미 tile terrain·환경 상태와 item definition ID를 저장하므로 wire shape와 버전은 유지한다.
