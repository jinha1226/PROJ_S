# Living World Simulator

Godot 4.6/GDScript로 작성한 헤드리스 우선 결정론적 시뮬레이션 코어입니다. 현재 범위는 턴과 세계시간의 분리, 결정론적 예약 처리, 행동 preview/timeline, 지형·네 방향 MOVE·점유, 불·물·젖음·전기, 종족별 위험 평가, 공통 피해 처리, 저장·복원, 그리고 **종족 관계 기준선이 개인 경험보다 우선하는 관계 기반**입니다. 인지·기억·자율 AI와 최종 대형 월드는 아직 구현하지 않았습니다.

## 결정론과 시간 계약

세 순서는 서로 다른 의미를 가집니다.

```text
step_index  완전히 정착한 유효한 플레이어 결정 수
world_time  세계에서 실제로 경과한 signed 64-bit 정수 시간
event_id    같은 시각까지 포함한 사건의 완전한 안정 순서
```

`LivingWorldSimulator.step(command)`는 `accepted`, `consumes_time`, `processed_step_index`, 시작·종료 시각, 비용·속도 등급, 사건, 실제 timeline을 반환합니다. 잘못된 명령은 세계시간, 결정 수, RNG, 사건·예약 ID와 환경을 전혀 진행시키지 않습니다. 외부에서 세계를 변경하는 진행 API는 원자적 `step()` 하나이며, 호출 전후는 저장 가능한 정착 경계입니다.

```text
명령 검증
→ 현재 world_time에서 행동과 즉시 효과 commit
→ (start_time, end_time]의 예약을 (due_time, priority, schedule_id) 순으로 처리
→ 각 환경 cadence에서 반응·확산·피해·젖음 감소를 완결
→ end_time에서 플레이어 준비
→ step_index 1 증가 후 정착
```

행동 비용은 `POUR_WATER=80(FAST)`, `WAIT=100(NORMAL)`, `IGNITE=120(SLOW)`, `DISCHARGE=160(SLOW)`입니다. MOVE는 목적지 terrain의 비용을 `ActionTimingTable`에서 읽습니다. `wait_for(1..10000)`만 명시적 휴식 기간을 받습니다. 표준 100단위는 달력상 추상 1분이며 환경 cadence도 100단위입니다.

`preview(command)`는 현재 상태를 전혀 바꾸지 않고 행동 시작·종료 시각, 비용·속도, 공개 가능한 예약 marker를 깊은 복사 DTO로 제공합니다. 확률 결과, 확산 성공, 예상 피해는 미리 RNG를 소비해 예언하지 않습니다. 향후 인지 시스템이 생기면 보이지 않거나 감지하지 못한 예약도 노출하지 않아야 합니다. 실제 timeline은 행동 시작 시 생긴 모든 즉시 사건과 각 예약 처리에서 생긴 사건을 marker별로 빠짐없이 귀속합니다.

Phase 1의 저장 가능한 예약 큐는 다음 100 배수에 도래하는 반복 `system.environment_tick` 정확히 1개로 고정됩니다. 공개 `schedule_entry()`는 이 canonical 초기 cadence를 만드는 bootstrap 경로이며, 이미 초기화된 월드에 추가 예약을 넣으려 하면 ID 소비 전 `-1`로 거부합니다. 테스트의 동일시각 정렬·budget 검증만 명시적 `_schedule_fixture_entry()`를 사용하며 그 fixture 큐는 step으로 완전히 소비하기 전 저장 경계가 아닙니다. NPC·상태 예약을 공개 API로 확장할 때 snapshot allowlist와 preview marker 계약을 함께 확장해야 합니다.

달력은 별도 누적 상태가 아니라 `world_time`의 순수 projection입니다. 100단위=1분, 15일=1계절, 4계절=1년이며 현재 낮밤은 표시만 하고 효과를 만들지 않습니다.

## 지형, 점유와 MOVE

지형은 실행 중 바뀌지 않는 `terrain-registry-v1` built-in registry가 해석합니다.

| terrain ID | 통과 | 점유 | MOVE 비용 | 정적 물 노출 | 가연성 | 기본 전도성 |
|---|---:|---:|---:|---:|---:|---:|
| `floor` | 예 | 1 | 100 | 0 | 0 | 0 |
| `stone_floor` | 예 | 1 | 100 | 0 | 0 | 5 |
| `wood_floor` | 예 | 1 | 100 | 0 | 80 | 5 |
| `metal` | 예 | 1 | 100 | 0 | 0 | 25 |
| `rubble` | 예 | 1 | 140 | 0 | 10 | 5 |
| `shallow_water` | 예 | 1 | 130 | 80 | 0 | 60 |
| `wall` | 아니오 | 0 | 0 | 0 | 0 | 0 |

`MOVE=4`는 기존 command wire 숫자 `0..3` 뒤에 추가됐습니다. 생존 actor가 네 방향 인접 칸으로만 움직일 수 있고, 경계 밖·벽·다른 생존 개체가 점유한 칸은 commit 전에 완전 무변경으로 거부됩니다. 죽은 개체는 이동을 막지 않으며, 한 칸에는 생존 개체가 최대 한 명만 있을 수 있습니다.

MOVE 위치는 행동 종료가 아니라 **시작 시각에 즉시 commit**됩니다. 따라서 `(start_time, end_time]` 안의 환경 틱은 새 위치를 봅니다. 불타는 칸으로 이동한 뒤 도래한 틱은 새 위치의 actor에게 피해를 주고, 불타는 출발 칸에서 빠져나오면 이전 위치 피해를 주지 않습니다. 종료 시각과 같은 틱도 `actor.ready`보다 먼저 처리됩니다. 위험 affinity는 설명과 선택 자료일 뿐 MOVE 가능 여부나 비용을 바꾸지 않습니다.

## 원소 규칙

- 원소 명령 위력: `1..100`
- 젖음 자연 감소: 환경 틱당 `2`
- 젖음은 환경 틱의 불을 1:1로 한 번 억제
- 남은 불 자연 감소: 환경 틱당 `5`
- 전도 임계치: 유효 전도성 `25`
- 전기 거리 감쇠: 타일당 `8`
- 불 피해: 타일당·환경 틱당 최대 `20`
- `water_depth`는 제거했고 `wetness`만 사용

물 적용 사건의 `magnitude`는 포화 한도를 반영한 실제 젖음 증가량이며 요청량은 `data.requested_amount`에 기록합니다. 실제 증가량이 `0`이면 기존 젖음 출처를 교체하지 않습니다. 여러 물 출처의 기여도를 동시에 보존하는 ledger는 아직 구현하지 않았습니다.

직접 점화와 확산 점화는 같은 `try_ignite()` 규칙을 사용합니다. 화재 확산은 각 환경 틱 시작 시 타고 있던 타일만 후보가 되며 목표별 승자를 안정적으로 일괄 선택합니다. 행동으로 직접 붙은 불은 도래하는 첫 환경 틱부터 피해 가능하고, 환경 틱 T에서 확산·재점화된 불은 직렬화된 `fire_damage_eligible_time=T+100`에 도달해야 피해를 줍니다. 사건은 `cause_id`와 `instigator_id`를 가지며, 불·젖음 타일 상태도 원인 사건 ID를 보존합니다. 전기 아크와 피해는 행동 시작 시 즉시 완결되고 시스템 객체에 미정착 피해 큐를 남기지 않습니다.

## Exposure와 종족 affinity

`sample_exposure(position)`은 저장 가능한 정착 경계에서 타일을 읽는 순수 projection입니다. 호출해도 snapshot, RNG, 다음 entity/event/schedule ID와 예약 큐가 변하지 않습니다. 결과는 terrain, 현재 불·젖음, 정적 얕은 물, 전도성, 활성 source event ID, 다음 환경 틱과 그 틱의 **현재 화재에 대한 확정 피해**를 담은 detached DTO입니다.

현재 규칙에는 persistent charge가 없습니다. `DISCHARGE`는 행동 시작 시 아크와 피해까지 끝내므로, 금속이나 젖은 칸의 conductivity가 높아도 `electric_risk=0`, `electric_certainty="NONE"`입니다. 전도성은 전기가 실제로 들어왔을 때의 성질이지 미래 감전 피해 예언이 아닙니다. poison도 아직 `0`입니다.

종족 tolerance는 `-100..100`이고 100은 해당 노출을 완전히 무시합니다. 각 점수는 부동소수점 없이 계산합니다.

```text
component(intensity, tolerance)
  = ceil(intensity × (100 - tolerance) / 100)
total_risk = fire + water + electric + poison component
```

| species | fire | water | electric | poison |
|---|---:|---:|---:|---:|
| `default` | 0 | 0 | 0 | 0 |
| `human` | 20 | 25 | 10 | 10 |
| `goblin` | -10 | -10 | -10 | 10 |
| `amphibian` | -25 | 100 | -25 | 30 |
| `dwarf` | 40 | -25 | 20 | 20 |

예를 들어 얕은 물 노출 80은 human 60, amphibian 0, dwarf 100이고, 불 80은 human 64, amphibian 100입니다. `assess_destination()`은 MOVE traversal·terrain 비용·sample·affinity·component를 함께 반환하지만, 모두 detached 설명 DTO입니다.

## 종족 기준 관계

`species_id`와 `faction_id`는 `kind`와 분리되어 있습니다. `SpeciesRelationTable`은 방향별로 다음 prior를 저장합니다.

```text
base_trust: -100..100
base_fear: 0..100
base_hostility: 0..100
```

실제로 상호작용한 `observer → subject` 쌍만 개인 관계를 만듭니다. 현재 공식은 다음과 같습니다.

```text
personal_trust_delta = clamp(personal_trust_delta, -40, 40)
personal_fear_delta  = clamp(personal_fear_delta, -30, 30)

effective_trust = clamp(base_trust + personal_trust_delta, -100, 100)
effective_fear = clamp(base_fear + personal_fear_delta, 0, 100)
effective_hostility = clamp(base_hostility + floor(grievance / 5) - floor(gratitude / 10), 0, 100)
```

도움 1회는 `gratitude += magnitude`, `personal_trust_delta += ceil(magnitude / 10)`, `personal_fear_delta -= floor(magnitude / 20)`입니다. 피해 1회는 `grievance += magnitude`, `personal_trust_delta -= ceil(magnitude / 5)`, `personal_fear_delta += ceil(magnitude / 4)`입니다. 감사·원한은 `0..100`이며 같은 원인 사건은 한 번만 처리합니다.

예를 들어 `goblin → human = trust -70, fear 35, hostility 75`일 때 규모 50의 구조 1회 후 결과는 `trust -65, fear 33, hostility 70, HOSTILE`입니다. 감사는 남지만 종족 prior를 즉시 뒤집지 않습니다. 명시적 유대·귀화·세력 화해는 아직 비목표입니다.

## 저장과 재현

v3 스냅숏에는 `step_index`, `world_time`, 달력 ruleset, RNG, 다음 ID, 정렬된 예약 큐, 지형 ID, 화재 피해 가능 시각, 타일·개체·사건·관계가 포함됩니다. 헤더는 `phase2-move-exposure-v1`, `terrain-registry-v1`, `hazard-affinity-v1`을 정확히 고정합니다. 불일치와 v1/v2는 의미를 추정하거나 암묵 마이그레이션하지 않고 객체 생성 전에 거부합니다. 시간과 모든 ID 본체·참조는 JSON 정밀도 손실을 막기 위해 canonical signed 64-bit 10진 문자열로 저장합니다. 숫자형 ID, `01`, 지수·소수, 공백, 범위 초과는 거부합니다. 복원 상태에는 다음 100 배수의 `system.environment_tick` 예약이 정확히 하나 있어야 합니다.

동적 맵 크기는 반드시 `LivingWorldSimulator.create(width, height, seed)` checked factory로 만듭니다. 현재 cap은 축마다 `1..4096`, 총 `1,000,000` 타일이며 둘 중 하나라도 넘으면 배열을 할당하기 전에 `null`로 거부합니다. raw `.new()`는 상수 fixture처럼 이미 검증된 내부 경로용이고, 제한 밖 입력은 inert 객체만 반환해 snapshot을 만들 수 없습니다. 개체 최대 체력과 사건 magnitude는 `1..2,147,483,647` 및 `0..2,147,483,647`, 타일 원소 scalar는 `0..100`입니다. 생성 API와 v3 복원은 이 cap을 공유하며, 잘못된 bootstrap 직접 변조가 있으면 `world_state_error()`가 이유를 반환하고 `snapshot()`은 `null`을 반환합니다.

사건 `data`와 예약 payload는 정수·문자열·불리언과 그 컨테이너만 허용하며 숫자 정수는 JSON 안전 범위 안이어야 합니다. 큰 ID·시간 metadata는 canonical 문자열로 기록합니다. `snapshot_restore_error()`는 wire shape부터 사건 인과·시간 단조성·화재 sentinel까지 부작용 없이 검사합니다. 오류가 있으면 `LivingWorldSimulator.from_snapshot()`은 assertion이나 부분 객체 대신 `null`을 반환합니다.

명령 journal wire v1의 `actor_id`도 sentinel을 포함한 canonical 문자열입니다. `type`, `power`, WAIT duration, 좌표는 범위가 작은 JSON 정수이며 JSON parser가 만든 정확한 `.0`만 허용합니다. 소수 좌표·비용·종류나 숫자형 actor ID는 `SimCommand.from_dict()`에서 `null`로 거부되고, 이를 `step(null)`에 넘겨도 세계는 변하지 않습니다. 따라서 `2^53+1` 이상의 actor ID도 `to_dict → JSON → from_dict`에서 정확히 보존됩니다. 이전에 숫자형 `actor_id`를 기록한 journal은 wire v1과 **의도적으로 비호환**이며 조용히 변환하지 않습니다. 필요할 경우 별도 명시적 migrator가 canonical 문자열로 바꿔야 합니다.

## 구조와 실행

```text
sim/                 상태·명령·사건·스냅숏 모델
sim/systems/         환경, 피해, 관계, 이동, 노출 시스템
playtest/            UI가 core를 우회하지 않게 하는 headless session facade
tests/               헤드리스 회귀 테스트
examples/            원소·시간·MOVE/노출 데모
docs/                구현 계약과 다음 단계 가이드
```

```bash
godot --path .
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --script res://examples/element_chain_demo.gd
godot --headless --path . --script res://examples/time_timeline_demo.gd
godot --headless --path . --script res://examples/move_exposure_demo.gd
```

`godot --path .`은 450×800 Playtest Sandbox를 바로 실행합니다. 타일을 한 번 클릭하면 해당 칸을 검사하고, 선택된 인접 칸을 다시 클릭하면 MOVE를 제출합니다. 방향키/WASD는 즉시 네 방향 MOVE, `Space` 또는 `.`은 WAIT, `1`/`2`/`3`은 선택 칸에 불/물/방전, `L`은 log drawer 열기·닫기입니다. 메뉴에서는 species·seed reset, SAVE/LOAD와 snapshot 복사를 사용할 수 있습니다.

솔로 모바일 HUD의 `3D 실험`은 기존 2D renderer 위에 여는 presentation-local 실험실입니다.
실제 `Node3D + SubViewport + Camera3D` 15×15 ASCII 방에서 칸을 눌러 이동하고 인접한
`g`를 공격할 수 있습니다. `2D로`를 누르면 같은 본편 session으로 돌아오며, 실험실의
위치·적 체력·효과는 save/journal/RNG에 포함되지 않습니다. 360×640과 450×800 portrait
viewport에서 screen horizontal을 world/grid +X에 고정하고 yaw 없이 Z축 방향을 바라보는
고정 `45° 경사 탑뷰 · 축 정렬` orthographic camera와 44px 이상 조작부를 사용합니다.

주인공 인물 창은 열 때마다 `상태` tab에서 시작하며, 별도 `스킬` tab이 Lv/XP progress
bar, 현재 공격력·flat 방어력·HOLD 방어율, 세 기술의 rank와 훈련 progress/focus를
표시합니다. 집중을 바꾼 뒤에는 스킬 tab을 유지합니다. progression이 없는 동료는 tab을
노출하지 않습니다. MELEE는 rank당 피해 +2, GUARD는 HOLD의 기본
25% 물리 감소에 rank당 5%p를 더해 50%에서 제한합니다. EXPLORATION은 현재 권위 효과가
없음을 명시합니다. character level 자체는 공격·방어 공식에 곱하지 않습니다.

브라우저에서는 [GitHub Pages 플레이테스트](https://jinha1226.github.io/PROJ_S/)를 사용합니다. `main`에 push하면 GitHub Actions가 92개 헤드리스 테스트를 먼저 실행하고, 단일 스레드 Godot Web build를 만들어 Pages에 자동 배포합니다. 로컬 Web export는 아래 명령으로 만들 수 있습니다.

```bash
mkdir -p build/web
godot --headless --path . --export-release Web build/web/index.html
```

Web build는 파일을 직접 열지 말고 HTTP 서버로 제공해야 합니다. 예를 들어 프로젝트 루트에서 `python3 -m http.server 8000 --directory build/web`을 실행한 뒤 `http://localhost:8000`에 접속합니다.

화면의 `DEBUG OMNI`는 시야·인지 제한 없이 개발 정보를 표시한다는 뜻입니다. `PlaytestSession`은 32×48 고정 경기장, 선택 위치, MOVE/WAIT/원소 제출, accepted command journal, snapshot v3 단일 슬롯 저장·복원, HUD용 detached 상태를 제공합니다. 이 경기장은 규칙과 카메라를 검증하는 작은 수직 슬라이스이며 최종 월드 규모를 뜻하지 않습니다. UI는 session DTO만 사용하고 simulator/world를 직접 읽거나 이동·위험 공식을 복제하지 않아야 합니다.

다음 단계는 [개발 가이드](docs/NEXT_DEVELOPMENT_GUIDE.ko.md)를 따릅니다.
