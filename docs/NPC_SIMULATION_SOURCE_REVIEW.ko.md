# 던전 NPC 시뮬레이션 소스 검토

확인일: 2026-09-12. 현재 게임 기준 `4227de3`와 이번 렌더링/탐험 최적화 작업. 이번에는 **조사와 연결 설계만** 한다. 외부 런타임 설치, NPC 정책 교체, 저장 스키마 변경은 하지 않았다.

## 결론

가장 가까운 후보는 **Godot Utility AI의 행동 점수 구조**다. 기존 독립 탐험자의 행동 선택만 개선하고, 이동·공격·부상·소모품 처리는 지금의 단일 전투 엔진을 계속 사용한다. **Neighborly의 관계/사건 기록**은 별도로 참고한다. 전체 NPC 엔진을 다시 갈아엎을 필요는 없다.

특히 동료 전투에는 이미 점수 기반 선택과 감정·기억 반영이 있다. 외부 Utility AI 플러그인을 병렬로 추가하기보다 **기존 동료 평가 구조를 독립 탐험자에게 확장**하는 것이 우선이다.

아래의 적합성/우선순위는 소스와 우리 코드의 연결 지점을 비교한 판단이지, 외부 프로젝트의 모바일 성능을 측정한 결과가 아니다.

## 확인한 저장소

| 후보 | 확인된 구조·상태 | 우리 게임에 쓸 부분 / 한계 |
|---|---|---|
| [godot-utility-ai](https://github.com/viniciusgerevini/godot-utility-ai) | Godot 4.1 설정의 GDScript 예제, MIT. 행동별 consideration 점수를 합성하고 최고 점수 행동을 선택한다. | **1순위:** 탐색/교전/휴식/귀환/구조/전리품 확보의 우선순위. 완성된 던전 시뮬레이터는 아니다. 원본은 매 physics frame 평가하므로 그대로 붙이지 않는다. |
| [Neighborly](https://github.com/ShiJbey/neighborly) | Python 기반 정착지 사회 시뮬레이션, MIT. 특성·관계·생활 사건·위치 선호. README에 2026-04-07 유지보수 종료 공지. 정확한 개체 좌표는 모델링하지 않는다. | **2순위, 구조 참고:** 구해 준 NPC, 함께 탐험한 동료, 원한·평판·기억 기록. 던전의 타일 이동/전투 엔진으로 쓰기는 부적합. Python 의존성을 Web 게임에 넣지 않는다. |
| [ReGoap](https://github.com/luxkun/ReGoap) | C# GOAP, Apache-2.0. 현재 README는 Unity/Godot 어댑터, 상태·센서·기억·목표·행동 전제/결과, A* 계획을 설명한다. | **후순위:** ‘위험 지역에서 벗어나기 → 모닥불로 이동 → 치료 → 재탐색’ 같은 다단계 계획. 지금 네 가지 주요 행동만 위해 도입하면 계획 탐색·어댑터·검증 비용이 늘어난다. |

확인한 revision:

- Utility AI: `bd834c25b04f949b07a809aa3737d03effd0219d`. 실제 평가 루프: [agent.gd](https://github.com/viniciusgerevini/godot-utility-ai/blob/bd834c25b04f949b07a809aa3737d03effd0219d/addons/utility_ai/agent/agent.gd). [LICENSE](https://github.com/viniciusgerevini/godot-utility-ai/blob/bd834c25b04f949b07a809aa3737d03effd0219d/LICENSE), [Godot 설정](https://github.com/viniciusgerevini/godot-utility-ai/blob/bd834c25b04f949b07a809aa3737d03effd0219d/project.godot).
- Neighborly: `1303cee0b8c404b1e3cf439e5c1a4b74d5e4ffe3`. [README의 기능·제약·유지보수 공지](https://github.com/ShiJbey/neighborly/blob/1303cee0b8c404b1e3cf439e5c1a4b74d5e4ffe3/README.md).
- ReGoap: `69eeea4a5489506b2e0d3f2db4a02c288d8d38fa`. [현재 README](https://github.com/luxkun/ReGoap/blob/69eeea4a5489506b2e0d3f2db4a02c288d8d38fa/README.md), [LICENSE](https://github.com/luxkun/ReGoap/blob/69eeea4a5489506b2e0d3f2db4a02c288d8d38fa/LICENSE).

전에 언급한 [PWM](https://github.com/AlayaLab/PWM)은 명시적 세계 상태와 화면 생성을 분리하는 개념이 맞다. 다만 확인 시 README의 inference code/weights는 미공개 체크박스 상태다. 당장 복사해 적용할 NPC 행동 라이브러리로 분류하지 않는다. [공개 범위](https://github.com/AlayaLab/PWM/blob/main/README.md).

라이선스 이름은 저장소 표기를 확인한 것이다. 실제 코드나 에셋을 옮길 때에는 고정 revision, 해당 파일의 고지, 의존성/에셋의 별도 조건을 다시 검토하고 고지를 포함해야 한다. 이번 변경에 이 저장소들의 소스나 에셋은 복사하지 않았다.

## 이미 우리 게임에 있는 것

- `sim/systems/independent_explorer_system.gd`: `EXPLORE/FIGHT/REST/RETURN`, 보급/피로/HP, 적의 거리와 LOS, `busy_until`, 귀환 고정 의사결정, 보관한 이동 경로가 있다. `choose()`는 현재 성격 C/E를 회복·귀환·교전 문턱에 사용한다.
- `sim/dungeon_population/hexaco_profile.gd`: H/E/X/A/C/O 각 0~1000. 기존 4-facet PersonalityProfile도 남아 있으므로 새 정책에서는 타입/스키마를 명시적으로 구분해야 한다.
- `sim/party_member_state.gd`: 성격뿐 아니라 스트레스, 정신 모드, emotion/memory 상태를 보유한다.
- `sim/systems/party_encounter_coordinator.gd`와 `sim/party_companion_appraisal.gd`: 동료 행동의 legal 판정, consideration 점수, 고정 tie-break, 감정/기억/관계 반영이 이미 있다. 독립 탐험자의 단순 `choose()`와 이 전투 평가를 연결하는 것이 실제 빈 부분이다.
- `sim/party_memory_state.gd`: 사건 ID 중복 방지, 최대 8개 기억, 중요도 기반 보존. `sim/party_relationship_model.gd`는 구조/피해/동료 상실 등의 사건을 성격과 연결한다. Neighborly를 참고해도 이 저장 구조를 중복 생성하지 않는다.
- `playtest/dungeon_visitors_service.gd`: 방문자/모집 연결. 이동·공격·아이템은 독립 탐험 시스템에서 기존 authority를 호출한다.
- 독립 탐험 tick에는 활성화/원정 단계/거리 조건이 있다. 현재 `expanded`가 아니면 플레이어에서 16칸보다 먼 탐험자가 건너뛰어질 수 있다. 따라서 ‘모든 원거리 NPC가 이미 동일 정밀도로 영구 시뮬레이션된다’고 볼 수 없다.

## 연결 방식 제안 — 아직 미구현

`NPC 자신의 관측·기억 + 신체/보급 상태 + 성격 → 행동 점수 → 유지/전환 결정 → 기존 명령 실행 → 사건/기억 갱신`

1. **점수는 정책만 결정:** `choose()`를 장면 노드 없는 정수 계산 모듈로 분리하되, 기존 동료의 consideration/고정 tie-break 구현을 재사용한다. 상태 전제조건을 통과한 행동만 채점한다. 실제 이동, 명중, 피해, 치료, 사망, 소모품 소비는 기존 엔진 외부에서 직접 바꾸지 않는다.
2. **성격은 선호이며 능력치가 아님:** O는 새 지역 탐색, C는 보급·안전 경로, E는 위험/부상 반응, A/H는 구조·분배·약속, X는 합류·도움 요청 선호에 활용한다. 이것은 게임 설계상의 매핑 제안이지 심리학적 인과 주장이나 모든 행동에 일률 적용할 배수가 아니다.
3. **부상은 가능 여부부터 제한:** 이동 불가, 기절, 손 사용 불가 등은 점수로 무시할 수 없는 전제조건이다. 남은 행동 사이에서 성격이 선택을 바꾸게 한다.
4. **왕복 방지:** 현재 목표 보너스, 일정 수준 이상의 개선일 때만 목표 전환, 위험 발생 시 즉시 중단, 실패한 목적지의 재시도 제한. 같은 점수는 고정 행동 순서/ID로 결정한다.
5. **모르는 것은 모르게:** NPC의 관측/사건 기억을 사용한다. 플레이어가 보지 못했다는 이유만으로 NPC를 멈추지도, NPC가 플레이어/적의 실제 위치를 전부 알게 하지도 않는다.
6. **판단 주기와 물리 행동 분리:** 가까운 NPC와 교전 중인 NPC는 기존 정밀 행동을 유지한다. 먼 비전투 NPC의 고수준 목표 재평가만 낮은 주기로 실행한다. 보이지 않는다는 이유로 공격·부상·시간 비용을 삭제하거나 임의의 결과를 추가하지 않는다. 기준 시간은 렌더 frame/실시간이 아니라 `world_time`이다.
7. **기록 예산:** 구조·배신·공동 전투처럼 의미 있는 사건만 NPC별 제한된 기억에 넣는다. 오래된 사건은 요약/감쇠한다. 모든 NPC 쌍을 매 tick 비교하지 않고 실제 관련자/주변 후보만 평가한다. 난수 사용 시 seed/호출 순서를 고정하고 저장·재현으로 검증한다.

플레이어에게는 ‘겁이 나서 귀환 중’, ‘동료를 구하러 이동 중’ 정도의 한 줄 이유를 기존 NPC 상세창에 보여주고, 수십 개 점수표는 개발 진단 자료로만 둔다. HUD/지도/로그/초상화/버튼 배치는 건드리지 않는다.

첫 적용 범위로는 **기존 네 행동의 점수화 + 목표 유지 + 이유 한 줄**을 권한다. 구조/전리품 양보/배신은 행동 authority와 사건 계약을 정의한 뒤 늘린다. 검증은 성격만 다른 동일 상황 비교, 목표 왕복 방지, NPC 자체 LOS, 부상 전제조건, 근거리↔원거리 전환 중 중복 행동 없음, 저장 재현, 다수 NPC CPU 비용으로 묶는다.
