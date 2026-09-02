# 플레이어블 5종족 마이그레이션 + 육체 시뮬레이션 B0 구현 계획

기준: `origin/main` 5b47a90

## 목표

1. 플레이어블 종족을 인간·엘프·드워프·오크·수인 다섯 종으로 교체한다.
2. 육체 시뮬레이션 B0의 데이터·value object·순수 피해 계산기를 추가한다.
3. 현재 전투 피해, HP, life state, AI와 치료 동작은 바꾸지 않는다.

## 비범위

- `MIGHT / AGILITY / VITALITY`를 새 스탯으로 교체
- 종족 무기 친숙도의 수치 효과
- 종족 스킬 hook의 실제 전투·탐색 실행
- BodyState를 WorldState와 실제 전투에 연결
- 기존 HP를 BodyState 요약값으로 전환
- 방어구 item schema, 치료 UI, NPC 철수 판단 변경

## 커밋 1 — 플레이어블 5종족 마이그레이션

### 권위 종족

- canonical player IDs: `human`, `elf`, `dwarf`, `orc`, `beastkin`
- 사용자 표시 순서: 인간 → 엘프 → 드워프 → 오크 → 수인
- `amphibian`은 active 코드·콘텐츠·fixture에서 제거한다.
- `goblin`은 몬스터·NPC·세력·drop/mutation family로 유지하되 player species registry에는 넣지 않는다.

### 데이터와 registry

- `growth_builds.json`의 species rows를 다섯 종으로 교체한다.
- 이번 단계에서는 stats rows와 기존 스탯 계산을 바꾸지 않는다. 새 종족 effect가 구형
  MIGHT/AGILITY/VITALITY나 max HP에 의존하지 않게 한다.
- 종족별 고정 패시브와 2갈래 × 2단계 스킬은 데이터 identity·hook 계약으로 등록한다.
  hook 실행은 후속 단계이며 JSON 등록만으로 구현됐다고 보고하지 않는다.
- 무기 친숙도는 종족 정의의 metadata로 보존하되 피해·명중·요구치 보정을 적용하지 않는다.
  최종 효과는 스탯안 확정 뒤 연결한다.
- registry는 exact five-species set, strict keys, unique IDs와 canonical tag rows를 검증한다.
- human의 적응형 무기 친숙도와 나머지 종족의 고정 친숙도는 데이터에서 구분 가능해야 한다.

### 세션과 UI

- 새 run 시작 전에 다섯 종족 중 하나를 선택할 수 있는 modal/picker를 제공한다.
- 기본값은 human이며 선택한 species ID가 session 생성·reset·save/load/replay에 보존된다.
- 360×640과 450×800에서 버튼 최소 44px, 한 번의 touch가 한 번만 commit된다.
- showcase/opening fixture의 `amphibian` actor는 다섯 종족 중 문맥에 맞는 종족으로 교체한다.
- 표시용 species label map에 다섯 종족을 추가한다.
- hazard affinity가 필요한 새 종족은 당분간 human 기준값을 사용한다. 합의하지 않은 별도
  환경 보너스를 발명하지 않는다. dwarf의 기존 값은 유지 가능하다.

### save 정책

- 종족 enum·branch 계약 변경은 HARD_CUT이다. 구버전 성장 state가 조용히 새 종족 효과로
  해석되지 않게 nested growth schema와 필요한 상위 snapshot version을 올린다.
- raw preflight가 구버전 snapshot을 객체 생성 전에 거부한다.
- migration ladder나 암묵 기본값을 추가하지 않는다.

### 수용 테스트

1. player registry의 set은 exact `beastkin,dwarf,elf,human,orc`다.
2. picker 순서는 human, elf, dwarf, orc, beastkin이며 버튼은 정확히 5개다.
3. 다섯 종족 각각 새 session 생성, save/load와 journal replay가 exact하다.
4. `amphibian` player state와 구버전 growth schema는 명시적으로 거부된다.
5. goblin은 player registry에는 없지만 monster family·적 생성·drop 경로에 남는다.
6. stats IDs와 실제 전투 결과는 이번 커밋 전후 동일하다.
7. active 코드·콘텐츠·테스트 fixture에는 `amphibian`이 남지 않는다. 역사 문서는 예외다.

## 커밋 2 — 육체 시뮬레이션 B0

### 신규 경계

- `data/content/body_templates.json`
- `sim/body_template_registry.gd`
- `sim/body_state.gd`
- `sim/body_damage_resolver.gd`
- 집중 테스트와 전용 runner

### Body template

- parts: HEAD, TORSO, LEFT_ARM, RIGHT_ARM, LEFT_LEG, RIGHT_LEG
- layers: SKIN, SOFT_TISSUE, BONE
- vital tags: HEAD/BRAIN, TORSO/HEART_LUNG
- systemic values: blood capacity, shock threshold, consciousness threshold
- body scalars: skin toughness, soft-tissue cushioning, bone fracture threshold
- player templates: human, elf, dwarf, orc, beastkin
- non-player seam: generic humanoid와 goblin template 또는 명시적 fallback
- human/elf/beastkin은 B0에서 합의하지 않은 육체 보너스를 만들지 않는다.
- dwarf는 bone/fracture 축만, orc는 soft-tissue/blood/shock 축만 baseline과 다르게 한다.

### BodyState value object

- entity ID, species/template ID, body seed, 실제 생성된 body scalar, six part rows,
  wound rows, current blood, shock, consciousness와 revision을 가진다.
- 생성은 integer-only keyed hash를 사용한다. 같은 species+seed는 exact하고 다른 seed의
  개인차는 template이 정한 작은 범위 안에만 있다.
- strict `validation_error / to_dict / from_dict`와 canonical row ordering을 제공한다.
- unknown keys, duplicate parts/wounds, float, bool-as-int, unsafe JSON integer, 잘못된 source
  event와 범위 밖 값을 거부한다.
- B0에서는 WorldState가 BodyState를 소유하지 않는다.

### 순수 피해 계산기

- 입력: 검증된 BodyState/template, 명시적 body part, attack packet, armor protection packet.
- attack packet: form, base force, penetration, contact size, stagger force.
- armor packet: slash protection, pierce protection, impact padding, rigidity.
- 출력: detached resolution DTO. BodyState, RNG와 world를 절대 변경하지 않는다.
- hit location과 armor coverage RNG는 B0 비범위다. 호출자가 확정된 part와 armor packet을 준다.
- 모든 계산은 정수이며 방어가 완전히 막으면 0/t deflected가 가능하다. 최소 1 피해를
  강제하지 않는다.
- SLASH는 열린 피부 상처·출혈 성향, PIERCE는 깊이·vital 위험 성향, IMPACT는 shock·bone
  fracture 성향이 상대적으로 높아야 한다.
- exact 수치는 registry 데이터와 resolver 상수 한 곳에서만 관리하고 UI 문자열을 저장하지 않는다.

### B0 수용 테스트

1. registry strict validation과 다섯 player template exact set.
2. 모든 template에 six parts와 three layers가 있고 canonical order다.
3. 같은 seed는 byte-equivalent BodyState, 다른 seed는 bounded variation을 만든다.
4. BodyState strict round trip과 malformed wire 거부.
5. resolver 호출 전후 BodyState wire가 동일하다.
6. 같은 입력은 같은 resolution이며 float와 global RNG를 사용하지 않는다.
7. 같은 힘에서 SLASH bleed > IMPACT bleed, PIERCE depth > SLASH depth,
   IMPACT shock/fracture > SLASH shock/fracture 관계가 성립한다.
8. 충분한 armor는 damage 0과 deflected/absorbed 결과를 만든다.
9. dwarf의 차이는 bone 결과, orc의 차이는 soft tissue/blood/shock 결과에만 나타난다.
10. 기존 world snapshot, melee event, HP, life state와 AI trace가 B0 추가 전후 동일하다.

## 검증 순서

1. 작업 전 기존 focused suites와 알려진 baseline failure 기록
2. 커밋 1 테스트 작성 → 실패 확인 → 구현 → focused 통과
3. 커밋 1 단일 커밋
4. 커밋 2 테스트 작성 → 실패 확인 → 구현 → focused 통과
5. `git diff --check`, parser/script error와 ObjectDB leak 확인
6. 전체 suite 1회 실행, 기존 failure와 신규 regression 분리 보고

## 보고 형식

- 두 커밋 hash와 변경 파일
- schema/version 변경과 구버전 거부 경로
- 종족 picker를 실제 실행하는 방법
- B0 resolver API와 대표 SLASH/PIERCE/IMPACT 결과
- focused/full test 결과, 기존 실패와 신규 실패 구분
- 다음 단계인 B1 전투 연결에서 남은 seam
