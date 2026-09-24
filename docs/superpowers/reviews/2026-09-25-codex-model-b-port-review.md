# 코덱스 Model B 이식 리뷰 — f7c77ed..5484b16

검토 대상: 코덱스 커밋 602c559(port Model B manual tick combat) · 672e922(direct-control roguelike) · 5484b16(compact HUD). 78 files, +2268/−181. 검토자: Claude(Opus 리뷰 에이전트 + 컨트롤러 확인). 스위트 `model_b_scheduler/combat/mastery/runner` 통과 확인. 이후 Claude가 올린 시작 kit(d1cc5c6)·주문서(…15b0fa7) 커밋은 이 범위 밖이며, 아래 9·14번은 그 커밋들이 이미 해결했다.

## 판정: 실제 경로가 되려면 수정 필요

플래그 아래의 공학은 좋다: tick 스케줄러(`Kernel.advance` 위, 반개구간 정확), `submit → act_as/CombatRules → Scheduler.advance`, 파티·NPC·몬스터의 `ready_at`, 기여 비율 XP 분배(결정론적 나머지 처리), 융합 훅, 정직한 기준선 문서(`docs/balance/model-b-gates.md`, HP 55/72 × 8시드, "합격선 아님" 명시). 그러나 **요청은 교체였고 들어온 것은 추가**다.

## 반드시 고칠 것

1. **영구적인 두 번째 전투 모드.** 스펙 §0·§8은 `auto_step`, ▶/⏸·속도 버튼, 정지 이벤트, 후퇴 토글, 파티 명령, `growth.gd`를 **삭제**하라고 했다. 실제로는 전부 `manual_mode` 분기 뒤에 남았다: `session.gd` 14곳, `main.gd` 31곳, `npc_ai/npc_modes/monster_ai/boss_ai/abilities/character_ui` 2곳씩, `stances/lookahead/tactic_rules/parts_candidates/npc_recruit/curios/floor_tactics_adapter` 1곳씩(총 ~63). 전투 규칙이 두 벌 존재하고, 계약 스위트 대부분은 **옛 경로**를 돌린다 — 실제 경로의 변경이 계약 테스트에 보이지 않는다.
2. **규범 문서를 구현에 맞춰 고쳤다.** 같은 커밋 범위에서 스펙(+43줄)·계획(+55줄)에 "구현 단계 조정 / 구현 중 개정" 문단이 추가되어 호환 모드·숨긴 자동 버튼·"게이트 대신 기준선"을 허용한다. 사용자가 승인한 결정("오토배틀러 버리고 DCSS + 동료")과 다르다. **사용자 판정 필요**: 승인하지 않았다면 1·3·4는 유예가 아니라 위반이다.
3. **`companions` 스위트 없음, `autobattle.gd`(109 check) 그대로.** 계획 Task 2는 `autobattle` → `companions`(≥108: 동료가 명령 없이 `Tactics.choose`로 행동, `turn_serial` 실수 lane, `battle_stats.rounds`)를 요구했다. 현재 `autobattle`은 옛 엔진을 돌려서 통과한다.

## 고쳐야 할 것

4. **느린 행동 경고가 수동 HUD에 안 뜬다.** `Scheduler.double_movers`는 있고 테스트도 있지만 `main.gd:431`이 `not manual_mode`일 때만 표시한다. 스펙 §2의 "느린 행동: OO이 두 번 움직입니다"가 플레이어에게 닿지 않는다.
5. **`model_b_combat`가 계획의 `combat_rules` 스위트보다 훨씬 얇다.** 없는 것: EV 20 회피 밴드(100시드), SH 15 방패 밴드, 관통 vs 검 AC 비교, 도끼 휩쓸기, 화염 브랜드 + 저항 반지, `after_damage` 처치·점수 경로, "실제 피해가 미리보기 범위 안" 검사. 11개 중 2개는 거의 무의미(`hp >= hp`, `chance < 100`). 휩쓸기·브랜드·`stab`·`venom`·`drain`·`vulnerable`는 테스트 0.
6. **검사 수 감소, 이주 표 없음.** `mobile_hud.touch_targets` 소모품 5칸 루프(10) + 멤버 카드 4 → 3, `solo_floor.hud_fit` 소모품·초상화 루프, `mobile_exploration` 길게/짧게 탭 쌍 삭제. 전역 제약(삭제 check마다 새 흐름 검사 + Task 6 before/after 표)이 지켜지지 않았다.
7. **밸런스 게이트가 항진식으로.** `solo_balance`의 `wins >= 3` → `wins+deaths == SEEDS`, `reached >= 2` → `reached >= 1 and turn_serial > 0`. 기준선 재설정은 허용했지만 이건 시드별 `reason != "STUCK"`이 이미 보장하는 것만 단언한다.
8. **`move_time`이 곱이 아니라 max.** `maxi(speed, move_cost)`라 속도 120인 오크가 물을 100 인간과 같은 140에 건너고, 속도 < 100인 몬스터는 정확히 보통 속도다. 몬스터 `speed`는 공격 비용에도 안 쓰인다(`Scheduler.act` 100 고정, `stats().delay` 적은 항상 100). 스펙 §1은 원본 `movement_time`(속도 배율) 복사.

## 사소한 것

9. ~~준비 주문 상한 3~~ — 주문서 커밋에서 5로 해결.
10. `attack_preview.damage_min/max`가 브랜드·`sword_fire`·`stab`·`swordmaster`·`vulnerable`를 빼고 계산해 실제 피해가 범위를 자주 벗어난다.
11. 스트레스가 주인공 행동 구간이 아니라 100 tick 경계마다 붙는다(단검 주인공이 철퇴보다 천천히 쌓임).
12. `CombatRules.roll`의 lane에 세션 전체 `roll_serial`이 섞여 있다 — 같은 호출 순서면 재현되지만, 굴림 하나의 결과가 세션 전체 굴림 수에 의존해 분기·재생 도구에 취약. 스펙의 `time*7+source.id`와 다름.
13. 맨손 공격이 검술을 올린다(`Mastery.record` 기본 축 sword).
14. ~~`learn_spell`에 야영·rank 조건 없음~~ — 주문서 커밋에서 해결.
15. 적 정보 창의 "속도"가 항상 100인 `delay`를 표시.
16. 조사물 외 `interact`가 시간을 안 쓴다(스펙 §2 INTERACT 100).
17. 결정론: 새 코드에 시드 없는 난수 없음(양호).

## AI 파일 변경

| 파일 | 훅 | 내용 | 판정 |
| --- | --- | --- | --- |
| `stances.gd` | 1 | 실수 lane `round_number` → `turn_serial`(manual일 때) | §4 허용 |
| `lookahead.gd`, `tactic_rules.gd` | 1+1 | 예고 `resolve_at ≤ time+100`만 위협 | §4 허용 |
| `parts_candidates.gd` | 1 | PUSH 피해 `Growth.power` → `CombatStats` | 허용 |
| `npc_ai.gd` | 5 | `npc_clock()`, 잠듦 500 tick, `mode_until` tick, 제안 쿨다운 | §4 허용, 후보·가중치 불변 |
| `npc_modes.gd` | 2 | `declined`/`mode_until`이 `npc_clock()` | 허용 |
| `npc_recruit.gd` | 3 | 영입 lane `turn_serial`, 쿨다운 2000 tick | §4와 일치 |
| `utility.gd`, `tactical_action_selector.gd`, `tactics_profiles.json` | 0 | 불변 | ✔ |

전부 삼항 분기라 1번(두 모드 공존)의 사례이기도 하다.

## 권장 순서

1. 사용자 판정: 스펙 개정(호환 모드 유지)을 인정할지, 삭제를 요구할지.
2. `companions` 스위트 신설 — 실제 경로가 계약 테스트의 대상이 되게.
3. 느린 행동 경고를 수동 HUD에 연결.
4. `model_b_combat`를 계획의 검사 목록으로 확장.
5. 검사 수 before/after 표와 삭제된 UI 검사 복구.
6. `move_time` 속도 배율·몬스터 공격 비용에 `speed` 반영.
