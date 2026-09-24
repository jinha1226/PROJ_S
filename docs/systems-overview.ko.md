# 시스템 개요 (2026-09-25, main e606e8b 기준)

지금까지 구축된 것을 한 장으로. 각 절은 "무엇을 하나 → 어디에 있나 → 규칙 수치"의 순서다. 규범은 코드·데이터이고, 설계 근거는 `docs/superpowers/specs/`의 스펙들이다. 마지막 절 §12에 **이중 경로와 부채**를 모아 두었다 — 다음 리팩터링의 출발점이다.

## 1. Run 루프

- **시작**: 시작 화면(`StartScreen`)에서 시작 장비 10개 중 하나(`KitPick`) → `Session.new_run(seed, kit_id)` → `depart()`가 1층을 만든다. 마을·귀환·횃불·빛·유물은 없다(`tests/run_start.gd`가 부재를 단언). 주인공은 고정(아린), 종족은 아직 `human` 고정(종족 선택·광장 장면은 미구현, 스펙 §1.0).
- **단계** `phase`: `IDLE`(시작 화면) → `EXPLORE`(층 위, 적 시야 없음) ↔ `BATTLE`(파티 시야에 적) · `CAMP`(야영) · `DEFEAT`(주인공 사망). `on_floor()` = EXPLORE|BATTLE.
- **층**: `descend()` — EXPLORE·안전·보스 없음·계단 인접일 때. `Floor.theme_for(depth)`: 홀수 `F1_RUINS`, 짝수 `F2_MINES`, 3층부터 몬스터 예산 ×(1+0.25·(depth−2))에 "가장 강한 합법 무리의 80%" 상한, `max_members = min(4, 2+depth/3)`. 3·6·9층은 보스 층(`boss_lair`, 계단 봉인).
- **야영**: `can_camp()` — EXPLORE·안전·`식량 ≥ 인원`. 효과: 식량 −인원, HP +50%, 스트레스 −30, 쿨다운 초기화. **장비·파츠·주문 배우기·준비는 야영에서만.**
- **종료**: 주인공 HP 0 → `DEFEAT` → 결과 카드(도달 층·점수·동료 이력 `companion_rows()`). 점수: 처치 +10, 하강 +20, 보스 +100, 조사 +5.
- 파일: `expedition/session.gd`(1,200줄+, 세션 전부), `continuous_floor.gd`(층 적용·시야·계단), `floor_generator.gd`, `floor_templates.gd`, `data/content/floor_themes.json`(2테마, 80×80), `floor_templates.json`(7 템플릿).

## 2. 시간과 전투 (Model B 이식)

- **tick 스케줄러** `expedition/scheduler.gd`: 주인공이 `Session.submit(kind, target)`으로 행동 하나를 내면 `action_cost`만큼 시간이 흐르고, 그 안에 `ready_at`이 된 동료·NPC·몬스터·환경이 시각순으로 행동한다(`Kernel.advance`, 반개구간). 주인공 행동 1회 = `turn_serial` +1 = 옛 "라운드".
- **비용**: MOVE `move_time`(지형 100/120/140, `max(speed, 지형)`, 최소 40), ATTACK 무기 `delay`(검 120·단검 75·철퇴 145…, 숙련 rank당 −4, 최소 60), 파츠 `delay`(기본 100), CAST 100, WAIT 100. 느림 ×3/2, 빠름 ×2/3.
- **실효 스탯** `combat_stats.gd` `stats(s, actor)` → `{damage, delay, ac, ev, sh, enc, range, brand, trait, res, power}`: 종족 기본 → 장비(무기·방어구·방패·반지) → 숙련 rank → 상태 순. 파티·NPC·몬스터 전원 같은 함수(몬스터는 카탈로그 `speed/ac/ev/res`).
- **공격 규칙** `combat_rules.gd` `attack`: 회피(`EV·2`, 5~45%) → 방패(`sh`) → `Turns.physical`(AC 0~ac 흡수, 관통 특성은 AC 절반) → 숙련 효과 → 브랜드(화염·냉기 +4, 독, 흡혈) → 휩쓸기. `damage`: 원소 저항 → `vulnerable` ×1.3 → `Session.after_damage`(스트레스·기억·NPC 사망·점수·드롭·인터럽트). 모든 굴림은 `CombatRules.roll` → `Hexaco.sample`(결정론).
- **상태**: `slow/haste/freeze/bind/burn/weak/brittle/distort/vulnerable/confuse/dominate/ward/rage/corrode/poison/bleed`. 이동·공격 금지는 `Session.status_blocks`가 `act_as`·`can_submit`·몬스터/보스 차례 입구에서 본다.
- **몬스터** `monster_ai.gd`: 역할 MELEE/RANGED/CASTER, 대칭 시야 5, 예고(`intents[].resolve_at`), 파츠 시전, 궁수 재장전. `boss_ai.gd`: 수렁 포식자·폭탄 암살자·과부하 거인(전력탑). 근접 경로는 `floor_tactics_adapter.gd`(레거시 브리지).
- 데이터: `data/content/combat.json` — 무기 7·방어구 4·반지 6·종족 3·kit 10·이동 비용·전리품·처치 XP·주문 62행(§6)·책 15·소환수 4.

## 3. 동료 AI (자율)

파이프라인 `tactical_action_selector.gd choose(s, actor)`: **불길 탈출 → 후퇴선 → 실수 → 효용**. 명령은 없다(옛 파티 명령은 §12).

- **태세** `stances.gd`: `CHARGER/SKIRMISHER/GUARDIAN`. 적성 = HEXACO(돌격 X−E, 거리 E+C−1000, 호위 A+H−1000), 기본 태세 = 최고 적성, 편안 범위 `200 + C/5`. 각 태세는 후보(이동·공격·대기, 태그만) 생성 프로그램.
- **실수**: 확률 `4 + (1000−C)/60 + min(20, 적성 차/40)`, 불안 ×1.5·붕괴 ×2, 상한 40%. 종류 REVERT(기본 태세로)/HESITATE(대기)/RECKLESS(돌격형·posture 100). 시드 lane `depth·100000 + turn_serial·100 + id`.
- **효용** `utility.gd`: 고려 사항 19개(`target_adjacent, any_foe_adjacent, damage, kill, closes/opens_distance, in_band, cell_danger, ally_delta, protectee_near/gap/lethal, rule_ready, contact_penalty, same_as_last, la_self_hit, la_ally_hit, la_enemy_hit, la_lethal_saved`), 태세×행동 태그별 가중치 표 `data/content/tactics_profiles.json`, 성격 노브(`posture/cohesion/retreat_hp`, `knobs.gd`)가 가중치를 밀고, 정수 결정론 점수 + 설명 상위 3(`explain`).
- **룩어헤드** `lookahead.gd`: 공개 정보로 한 구간 예측(자기·아군·적 피해, 살린 수) — 예고 칸·엄호·밀치기·처치가 점수에 반영. 안전 항은 "가만히 있을 때 대비 델타"(부호 있음, 지식 노브로 0까지만).
- **파츠 후보** `parts_candidates.gd`: 장착 파츠(밀치기·엄호·종족 파츠)가 같은 풀에서 경쟁, 규칙 조건은 `rule_ready` 등급 입력.
- 계약: `tests/stances.gd` 113 · `utility.gd` 154 · `companion_tactics`, 게이트 `stance_gate`(혼합 6/6)·`solo_balance`. 튜닝 기록 `docs/balance/utility-tuning.md`.

## 4. 던전 NPC

- **명부** `npc_roster.gd`: Run당 `COUNT 10`(스펙은 30으로 확대 예정), 2인 조 2쌍(`close 60% / strained 40%`), 성격·기본 태세·무기(성격 가중)·파츠 40%. 층당 1층 3명, 이후 4~5명, 상황 교전 중/부상/휴식(교전 중이면 무리 동반), 재등장은 지난 상처 유지, id 1000+.
- **감각** `npc_ai.gd`: 자기 시야(5)로 파티를 보거나 소음 반경 10 안 전투를 들으면 깨어남, 미관측·무소음 500 tick이면 잠듦. 깨어 있으면 파티 시야 밖에서도 행동.
- **행동**: 자기 시야에 적 → 파티와 같은 `Tactics.choose`(`friends()` = 파티 + 깨어 있는 NPC + 소환수; 몬스터도 NPC를 노림). 아니면 활동 모드 `npc_modes.gd`(APPROACH/HOLD/REST/EXPLORE, 소형 효용표, 유지 10구간·80점 전환), 2인 조는 뒤처진 쪽이 파트너에게.
- **영입** `npc_recruit.gd`: 식량 나눔(부상/굶주림) → 확정 동행; 외향형(X ≥ 500)은 인접하면 제안 팝업; 내향형은 탭해서 제안 — 확률 `60 + (X+A−1000)/25 + 부상 15 − 거절당함 25 − 거절함 10`(0~95), 쿨다운 2000 tick, EXPLORE에서만, 최대 3인. 2인 조 close는 둘 다/자리 부족 거절, strained는 한쪽만(남는 쪽 기억·떠나는 쪽 스트레스). 낯선 이의 죽음은 본 사람 +5(도움 준 상대 +10), 동료의 죽음은 `ALLY_LOST`.
- 계약: `npc_roster` 83 · `npc_sense` 18 · `npc_behaviour` 57 · `recruit` 133.

## 5. 성장

- **숙련** `mastery.gd`: 10축(검·창·둔기·도끼·활·화염·냉기·기류·변이·소환). rank 0~10, 필요 XP `25·Lv²`(새 축 Lv1~2는 절반). XP는 **사용으로만**: 적 처치 시 `18 + depth·8`을 교전 기록(무기 축·주문 학파) 비율로 분배(결정론적 나머지), 종족 적성 배율, NPC는 파티 밖 전투도 자기 기록. 시작 kit은 그 축 XP 25(Lv1).
- **효과** `mastery_effects.gd` + `data/content/mastery.json`: 검 Lv3 출혈·Lv5 반격·Lv7 연속(지연 −20)·Lv10 치명 10%; 화염 Lv3 화상·Lv5 관통·Lv10 위력 ×1.5; 융합 `sword_fire`(공격에 화염 +4/+8)·`fire_sword`(주문 명중 시 인접 검 피해 절반). **나머지 8축의 이정표는 데이터 없음.**
- **레벨**: `Session.gain_level_xp` — HP +4·MP +2/레벨, 상한 12. (병행하는 옛 `growth.gd` 4축은 §12.)

## 6. 주문·아이템·파츠

- **주문**: `docs/spells.ko.md` 참조. 학파 5 × Lv10 = 50, 원시 8(`bolt/line/cone/burst/wall/self/mark/summon`), 상태 10, 소환수 4, 주문서 15권(초급 1~3 / 중급 4~6 / 고급 7~10). 배우기는 야영에서 `책 보유 + rank ≥ Lv−1`, 준비 5, MP `2+Lv`, 실패율 `8 + Lv·9 + 둔중·5 − rank·5 − INT`. 드롭: 중급서 3층~, 고급서 6층~. 파일 `spells.gd`(429줄).
- **장비**: 슬롯 무기·방어구·방패·반지(`actor.gear`), 야영에서 교체, 양손/방패 금지. 시작 kit = 무기 + 로브(마법 kit은 지팡이 + 초급서 + Lv1 주문). 드롭은 조사물(`loot.gear_by_depth`).
- **소모품** 5종(치유·안정제·활력·화염 두루마리·물 두루마리), 조사물에서만.
- **파츠** `abilities.gd`: 17개(밀치기·엄호 기본, 종족 파츠 8 — 각각 패시브, 시험용 7). 슬롯 2, 야영 장착, 처치 시 50% 드롭, 몬스터도 자기 종족 파츠를 예고 시전.
- **조사물** `curios.gd`: 보급 상자(식량 2~3)·버섯(식량 1~2, 독 30%)·죽은 모험가(식량 1, 파츠·소모품·주문서)·부서진 궤짝(파츠/소모품/장비/주문서). 짐승 처치 25% 식량.
- **식량**: 야영에만 쓴다. 시작 2.

## 7. 성격·스트레스·기억

- **HEXACO** `sim/dungeon_population/hexaco_profile.gd`: 6 facet 0~1000, 시드 결정론(SHA-256). 태세 적성·노브·실수·영입·NPC 모드·야영 조력자가 읽는다.
- **스트레스** `Session.stress`: 증가분 `amount·(650+E)/1000 + 트라우마(최강 SELF_HARM/ALLY_LOST 중요도/200)`, 0~200, 불안 ≥100·붕괴 ≥150(실수 ×1.5/×2). 원천: 전투 중 구간마다 +2, 피해, 동료 쓰러짐·상실, 낯선 이 사망 +5, 2인 조 이별. 야영 −30, 안정제 −25.
- **기억** `sim/party_memory_state.gd`: 액터당 8개, 종류 9(`SELF_HARM, ALLY_DOWNED, ALLY_LOST, AID_RECEIVED, COMMAND_CONFLICT, RECRUITED, DECLINED_BY_PLAYER, DECLINED_PLAYER, LEFT_BY_PARTNER`). 사회적 5종은 가지치기·축출에서 마지막까지 보호(도움·영입 약속이 층을 넘어 유지).

## 8. 층 생성

`floor_generator.gd`: 테마별 방 13~16(전투방 4~6, 필수 템플릿 `entry_camp·descent(또는 boss_lair)·sealed_treasury`), 복도 폭 2, 조우 예산(early/mid/deep/optional), 조사물 4종 배치, `npc_rooms` 3~5(보스 층 0), 시드 0~99 검증. 8종 몬스터(`floor_monsters.json`: 쥐·도마뱀·코볼드·고블린·홉고블린·오크·놀·강쥐, 깊이 6까지의 카탈로그를 깊은 층에서 재사용).

## 9. UI (`expedition/main.gd` 1,200줄, `character_ui.gd`, `board.gd`)

- 시작 화면(`StartScreen/KitPick/NewRun/ArenaButton`) → 층 HUD(위치 "n층", `FoodLabel`, 로그, 멤버 카드, `SpellBar` 5, 공격·대기·파츠 버튼, `CampButton`) → 야영 화면(`CampScreen`: 태세·파츠·장비 `GearScreen`·주문 배우기 `LearnList`·준비 `PrepareScreen`) → 계단 팝업 → 결과 카드.
- 조작: 탭 이동(경로 자동, 위험 시 정지), 적 길게 → 정보·명중·피해·시간(`EnemyInfo`), 공격 확정, NPC 인접 탭 → 대화 팝업(제안·식량 나누기), NPC 제안 팝업(자동 진행 정지).
- 캐릭터 폴리오 탭: 상태·성격(HEXACO + 태세 3버튼 + 실수 확률)·기억·숙련(5×2 그리드 + 상세)·파츠.
- 전투 시험 모드 `arena_setup.gd`: 아레나 6종 + 직접 구성, 시드, 인원, 태세·파츠 — 별도 세션.
- 목업: `docs/mockups/`(캐릭터 탭·수동 UI v1/v2·정착지 등, 참고용 PNG).

## 10. 시뮬·밸런스

- `expedition/sim/encounter_runner.gd`(빌드·아레나·시드 배치, 승률·피해·역할 비율·설명 빈도, Wilson CI), `encounter_arena.gd`(20×20 고정 방), `bot_policy.gd`(옛 `auto_step` 경로), `model_b_runner.gd`(주인공을 `Tactics.choose`+`submit`으로 — 실제 경로).
- 기록: `docs/balance/run-gates.md`(솔로 3/8, 태세 게이트 6/6, 테스트 이주 표), `model-b-gates.md`(Model B 기준선, HP 55/72 × 8시드, "합격선 아님"), `stance-gates.md`, `parts-gates.md`, `utility-tuning.md`(가중치 변경 로그), `action-economy.md`, `skill-value.md`, `docs/balance-method.ko.md`.

## 11. 테스트·CI

`.github/workflows/deploy-pages.yml`: 임포트 검사 + 스위트 **47개**, `SCRIPT ERROR`/`ERROR` 한 줄이면 실패. 계약 수치(줄이지 않는다): stances 113 · utility 154 · parts 338 · protect 38 · skill_rule_conditions 962 · npc_roster 83 · npc_sense 18 · npc_behaviour 57 · recruit 133 · mobile_hud 61 · solo_floor 81 · start_kit 168 · spellbooks 564. CI 밖 수동 도구: `ranged_probe`, `party_guard_probe`, `skill_value`.

## 12. 이중 경로와 부채 (다음 리팩터링 목록)

리뷰 `docs/superpowers/reviews/2026-09-25-codex-model-b-port-review.md`와 인벤토리에서 확인된 것.

1. **전투 엔진 두 벌.** `manual_mode`(tick·`submit`) 옆에 옛 라운드·`auto_step`·정지 이벤트·파티 명령·후퇴 토글·▶/⏸이 살아 있다(15개 파일 ~63 분기, `main.gd` 31). 계약 스위트 대부분(`autobattle` 109 포함)은 옛 경로를 돌린다. 스펙 §0·§8은 삭제를 요구했고, 코덱스 커밋이 스펙·계획에 "호환 모드" 문단을 추가했다 — **사용자 판정 대기**.
2. **성장 두 벌.** `growth.gd`(4축·포인트 투자·레벨 21)와 `mastery.gd`(10축) + `gain_level_xp`(레벨 12)가 공존, `manual_mode`로 갈라짐(`roll_part`, `after_damage`의 `Growth.incoming`).
3. **시간 단위 이중화.** `npc_clock()` = `time if manual_mode else round_number`; 실수·영입 lane도 삼항.
4. **주문 데이터 잔재.** `combat.json.spells`에 옛 12행(유물 7 + 원시 이름 5)이 남아 있다. 시전 불가로 막았지만 데이터 정리 필요. 주문 id와 책 id 철자 동일.
5. **숙련 이정표 8축 미정의**(검·화염만). 무기 5축은 레벨마다 패시브 기술이 필요.
6. **NPC 명부 10명**(스펙 30), **종족 선택·광장 장면 미구현**, **결과 화면**의 동료 이력은 있음.
7. **느린 행동 경고**(`double_movers`)가 수동 HUD에 연결 안 됨. `move_time`이 속도 배율이 아니라 max, 몬스터 `speed`가 공격 비용에 미반영.
8. **테스트**: `combat_rules` 계획 검사(회피·방패 밴드, 휩쓸기, 브랜드+저항, 처치 경로)가 `model_b_combat`에 없음; UI 검사 일부 감소·이주 표 없음; `solo_balance` 항진식.
9. `floor_tactics_adapter.gd`는 레거시 선택기 브리지(몬스터 근접 경로 전용).
10. 소환수 사망 시 파티 스트레스 없음(의도), 지배되지 않은 보스는 파티만 노림(기존).
