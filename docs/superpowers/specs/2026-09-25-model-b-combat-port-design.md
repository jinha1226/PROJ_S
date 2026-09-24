# Model B 전투 이식 설계 — DCSS식 주인공 + 자율 동료

작성일: 2026-09-25 · 상태: 첫 이식 구현 · 기준 코드: `new` main `1c17779`(Plan A·B 병합) · 원본: 부모 저장소 `47d46b8`의 `game/crawl/{world,usage_world,progression_data}.gd`, `data/content/crawl.json`
대체: `docs/superpowers/plans/2026-09-23-model-b-combat-mastery-ui.md`(Codex 초안)의 원칙은 계승하되, "새로 구축"이 아니라 **원본 함수를 옮겨 붙이는 이식표**로 다시 쓴다.

**구현 단계 조정:** 새 Run과 아레나의 게임플레이 경로는 수동 조작과 tick 전투를 사용한다. 기존 자동전투·4축 투자 코드는 과거 계약 테스트와 시뮬레이터의 호환 경로에만 남긴다. 완전 삭제와 해당 테스트의 `submit` 이주는 다음 정리 단계다. 소모품과 조사물 입력은 현재 `Session.use_supply`·`ContinuousFloor.interact`가 처리하며, 전투 중 시간 경과는 내부에서 `Scheduler.advance`를 호출한다. 이 단계의 수치 게이트는 합격선이 아닌 기준선이다.

**수동 화면 보정:** 새 Run의 기본 HUD는 주인공 HP/MP·AC/EV/SH, 지도, 최근 기록과 직접 행동만 표시한다. 파티 카드·태세·물자 아이콘 줄·자동전투 재생은 수동 경로에서 제외한다. 빈 칸 탭은 이동, 보이는 적 탭은 즉시 공격한다. 적을 길게 누르거나 우클릭하면 수치·공격 미리보기를 열며, 준비한 주문만 버튼으로 표시한다. 아레나 기본 인원은 1명이고 태세 설정은 동료에게만 보인다. 이는 아래의 적 탭 후 추가 확정 단계보다 우선한다.

## 0. 결정 사항

1. **오토배틀러를 버린다.** 주인공은 행동을 직접 고른다(DCSS). 동료·던전 NPC는 지금의 AI(태세·효용·룩어헤드·실수·활동 모드)로 스스로 움직인다. `auto_step`, ▶/⏸·속도 버튼, 정지 이벤트, 후퇴 토글, 파티 명령은 제거한다.
2. **시간은 tick.** 액터마다 `ready_at`, 기준 행동 100 tick. 주인공이 행동을 제출하면 그 행동의 지연만큼 시간을 흘리고, 그 사이 준비된 동료·NPC·몬스터·환경이 시각순으로 행동한다. 스케줄러 원시 함수는 이미 있는 `Kernel.advance/earlier`(`sim/combat_kernel.gd`)다.
3. **"라운드" = 주인공의 행동 사이 구간.** 라운드로 세던 것(예고 지연, 태세 유지, 실수 시드, NPC 잠듦, 소음, 쿨다운, 스트레스 tick)은 이 구간 또는 tick으로 재정의한다(§4).
4. **전투 수학은 Model B를 옮긴다.** `stats()`(장비·숙련·종족·상태 → 실효값), `attack()`(회피 → 방패 → AC 흡수 → 브랜드·특성), `damage()`(저항), `movement_time()`. 파티원 전원과 NPC가 같은 함수를 탄다(원본의 `id == 0` 제한 제거).
5. **숙련은 사용 기반 10축**(무기 5·마법 5). `usage_world.gd`와 `progression_data.gd`를 옮긴다. 기존 4축 `growth.gd`(근접/원거리/마법/방어, 포인트 투자)는 삭제. 캐릭터 레벨은 HP/MP 성장만.
6. **데이터는 `crawl.json`을 가져온다**: 무기 7, 방어구 4, 반지 6, 주문 12, 종족 3(적성 포함). 몬스터 24행은 가져오지 않고 우리 8종에 `speed/ac/ev/res` 필드만 붙인다. 수치는 출발값이며 §7 게이트로 재측정한다.
7. **유지**: 하강 Run·야영·계단·보스 층·조사물·식량·소모품 5종·파츠 2칸·성격·기억·스트레스·NPC 명부·영입·2인 조. 층 크기 80·시야 5 유지(Model B의 40×40·시야 6은 안 가져온다).
8. **가져오지 않음**: Model B의 `World` 맵·층 분기·신앙·룬·오브·저장, `game.gd`/`board.gd` UI, 몬스터 `actor_turn`(우리 `MonsterAI`·`BossAI` 유지), 이름만 있고 효과 없는 숙련 보상.

## 1.0 시작 화면 — 모임

- 새 Run → **모임 화면**: 고정 주인공(아린)과 이번 Run의 NPC 명부 **30명**이 한 화면에 모여 있다(`npc_roster.COUNT` 10 → 30; 층당 배치 3~5명은 그대로라 한 Run에 다 만나지 못한다). 토큰을 탭하면 이름·종족·성격 한 줄·들고 있는 무기를 본다. 여기서 영입은 없다(영입은 던전 §5.5).
- 주인공 카드에서 **종족**(인간/드워프/엘프 — HP·MP·STR/INT/DEX·적성 표시)과 **시작 장비 10개 중 하나**(§6 표)를 고르고 "1층으로". 종족과 시작 장비는 Run 동안 바꿀 수 없다.
- NPC의 종족·무기도 같은 표에서 시드로 뽑는다(종족 3, 무기 10). 마법 무기를 든 NPC는 그 학파 첫 주문을 알고 준비한 채 나온다.
- 화면 계약: `GatherScreen`(`GatherToken%d` ×31, `SpeciesPick`, `KitPick`, `Descend`). 결과 화면의 "새 Run"은 이 화면으로 온다. `IDLE` 단계가 이 화면이다.

## 1. 이식표

| 원본 (47d46b8) | 대상 (`new`) | 옮기는 방식 |
| --- | --- | --- |
| `crawl.json` `weapons/armours/rings/spells/species` | `data/content/combat.json` (신규) | 복사. `species.apt`는 `apt` 키 그대로. 우리 `species_catalog.json`의 5종족과 이름이 겹치면 Model B 3종(`human/dwarf/elf`)의 HP·MP·스탯·적성만 `combat.json`에 두고 나머지 2종은 `human` 값으로 시작 |
| `crawl.json` `monsters[*].{speed,ac,ev,res,will}` | `floor_monsters.json` 8종에 필드 추가 | 종별 매핑: rat/lizard ← `rat`, kobold ← `kobold`, goblin ← `goblin`, hobgoblin ← `hobgoblin`, orc ← `orc`, gnoll ← `gnoll`, river_rat ← `rat`(speed 100). 없는 종은 `speed 100, ac 0, ev 3, res {}` |
| `world.stats(a)` | `expedition/combat_stats.gd` `static func stats(s, actor) -> Dictionary` | 복사 후: `int(a.id)==0` 제거(전원), `DATA` → `combat.json`, `inventory[gear.x]` → `actor.gear.{weapon,armour,shield,ring}`에 아이템 dict 직접 보관, 신앙·결속 항 삭제, `skill_rank` → `Mastery.rank`. 반환 키 `damage, delay, ac, ev, sh, enc, range, brand, trait, res, power` 그대로 |
| `world.attack(source,target)` / `world.damage(...)` | `expedition/combat_rules.gd` `attack(s, source, target)`, `damage(s, source, target, raw, element)` | 복사 후: `rng` → `Hexaco.sample(seed, s.time*7+source.id, lane, 100)`(결정론), `message/emit` → `s.message`·`s.effects`, `gain_xp/piety/loot` → `s.on_kill`, `stop_auto` 삭제, 브랜드·특성(`stab/pierce/cleave/reach/ranged/focus`) 그대로, `source.ai` 독/산/흡혈은 몬스터 `passive`로 옮기지 않고 삭제(우리 파츠 패시브가 그 자리). 기존 `Session.damage()`의 스트레스·기억·NPC 사망·점수·드롭 분기는 `combat_rules.damage`가 부르는 `s.after_damage(target, lost, source)`로 남긴다 |
| `world.movement_time(a,cell)` | `combat_rules.move_time(s, actor, cell)` | 복사. `a.speed` → `actor.get("speed",100)`, 지형 비용은 `combat.json.move_cost` |
| `world.advance(cost)` | `expedition/scheduler.gd` `static func advance(s, cost)` | 복사 후: `actors` → `s.party + s.npcs(awake) + s.enemies(alive)`, `actor_turn(a)` → `Scheduler.act(s, a)`(§3), `environment_tick` → 기존 불·물 tick + 상태 만료, `update_sight` → `floor_state.observe`, `boundary` 100 유지 |
| `world.submit(kind,...)` | `Session.submit(kind, target, value) -> bool` | 우리 `act_as` 위에 얇게: MOVE(적 칸이면 공격), ATTACK, WAIT, CAST, USE(소모품), PART(파츠), INTERACT(조사물·계단·NPC 대화), EQUIP(야영에서만) — 각 행동의 `cost`를 §2 표대로 정하고 마지막에 `Scheduler.advance(s, cost)` |
| `usage_world.gd` `USAGE_SKILLS/weapon_skill/aptitude_for/add_skill_xp/refresh_unlocks/record_usage/award_usage_xp/fusion_tier` | `expedition/mastery.gd` | 복사 후 **캐릭터별**: `skills` → `actor.skill_xp`, `combat_usage` → `actor.usage`(적 id → 축 → 횟수), `discovered_*` → `actor.unlocked`, `hero()` → 인자, 신앙 보정 삭제. `skill_rank`는 원본 공식 `min(12, sqrt(xp/25))`를 **Lv 1~10**으로: `rank = clampi(int(sqrt(xp/25.0)), 0, 10)`, 다음 rank XP = `25·(rank+1)²` |
| `progression_data.gd` | `data/content/mastery.json` + `expedition/mastery.gd` 로더 | 복사. `LEVEL_REWARDS` 이름은 데이터로 두되 **`effect_id`가 있는 행만 화면·효과에 쓴다**(§5). `FUSIONS`는 `sword_fire`·`fire_sword`만 `effect_id`를 갖고 나머지는 잠김 |
| `usage_world.stats/attack/damage/cast`의 융합 가지(`apply_weapon_fusions/apply_magic_progression/apply_reverse_fusions/chain_element/spawn_fusion_minion`) | `expedition/mastery_effects.gd` | `sword_fire`(공격에 화염 4 추가 피해, tier2 8)·`fire_sword`(화염 주문 명중 시 인접 적 검 피해 절반)의 두 효과만 옮긴다. 나머지 가지는 옮기지 않는다 |
| `world.cast(id,target)`, `spell_cells`, `failure(id)` | `expedition/spells.gd` | 복사. 12주문 중 첫 단면은 **학파별 첫 주문 하나씩** `bolt`(fire, 단일)·`cone`(ice, 부채꼴 둔화)·`cloud`(air, 구름)·`confuse`(hex, 제어)·`hound`(summon, 소환수) 5개만 `effect`를 연결하고(§1.0 시작 장비가 이 다섯을 요구), `blink`·`mend`는 드롭 주문서로 다음 단면. 나머지는 데이터만. MP는 `actor.mp/max_mp`(종족 `mp`), 실패율 원본 공식 유지(`enc`는 `stats().enc`) |
| `world.gain_xp` | `Session.on_kill(target, source)` | 처치 XP `18 + depth·8`을 교전 기여자에게 `Mastery.award_usage_xp`로 분배(§5.2). 레벨 XP는 HP/MP만 올린다 |

옮기지 않는 원본 함수: `generate/enter_floor/spawn/trigger_trap/pickup/plan_route/start_rest/auto_step/save_data/restore/validation_error/leave_god/summon_guardian/actor_turn`.

## 2. 행동과 시간

| 행동 | 비용(tick) | 비고 |
| --- | --- | --- |
| MOVE | `move_time`(기준 100, 물 140, 잔해 120, 최소 40) | 대상 칸에 적이 있으면 ATTACK으로 |
| ATTACK | `stats().delay`(무기 지연 − 숙련·4, 최소 60) | 원거리 무기는 사거리·사선 검사 |
| PART | 파츠 정의에 `delay`(기본 100) 추가 | 쿨다운은 tick(`cooldown·100`) |
| CAST | 100 (`passwall` 200) | MP 소비, 실패율 굴림 |
| USE | 100 | 소모품 |
| WAIT | 100 | |
| INTERACT | 100 (계단 하강은 시간 정지) | 조사물·NPC 대화(대화 자체는 0) |
| EQUIP | 방어구 200, 그 외 100 — **야영에서만**, 야영은 시간 정지 | |

- 느림/빠름 상태: MOVE 외 비용 ×3/2, ×2/3(원본).
- **동료·NPC·몬스터**의 행동 비용도 같은 표를 쓴다. 동료는 `Tactics.choose`가 고른 `{kind, cell}`을 `Scheduler.act`가 `submit` 없이 실행하고 그 비용만큼 `ready_at`을 민다. 몬스터는 `MonsterAI.turn` 안의 이동/공격/시전에 비용을 붙인다(현행은 라운드당 1행동 = 100 tick 고정; 종별 `speed`가 이동 비용).
- **위험 경고**: 주인공 행동 구간 `[time,time+cost)` 안에 적의 첫 행동과 두 번째 행동이 모두 들어오면(`enemy.ready_at + enemy_cost < time + cost`) 미리보기에 "느린 행동: OO이 두 번 움직입니다"를 띄운다(확정 전 표시, 자동 취소 없음). 새 적의 첫 `ready_at`은 `time+speed`; 잠에서 깬 NPC는 과거의 `ready_at`을 현재 시각으로 올린다.
- `phase`: EXPLORE/BATTLE/CAMP/DEFEAT/IDLE 유지. BATTLE은 파티 시야에 적이 있을 때(현행 `observe`가 정함). 자동 이동(탭 경로·자동 탐험)은 EXPLORE에서만 이어지고, 시야에 적·NPC·조사물·계단이 들어온 **정확한 행동 뒤** 멈춘다. 중단 뒤 추가 자동 행동 0.

## 3. 스케줄러와 AI의 접합

```
Session.submit(kind, target, value):
  입력 검증; 현재 tick에 이미 준비된 환경·NPC·적 행동을 먼저 해소(환경 → actor id)
  cost ← §2 표
  실행(현행 act_as 경로; ATTACK은 CombatRules.attack)
  Scheduler.advance(self, cost)

Scheduler.advance(s, cost):
  end ← s.time + cost; hero.ready_at ← end
  Kernel.advance(end, next_ready, dispatch)   # 원본 글루
  next_ready: s.party[1:] 생존 + 깨어 있는 NPC + 살아 있는 적 중 ready_at < limit 인 가장 이른 액터, 환경 경계(boundary) 포함
  dispatch(actor): Scheduler.act(s, actor)
  s.time ← end; floor_state.observe(s); NpcAI.sense_all(s)

Scheduler.act(s, actor):
  동료:  choice ← Tactics.choose(s, actor); 실행; actor.ready_at += cost(choice)
  NPC:   NpcAI.turn(s, npc) (전투면 Tactics, 아니면 활동 모드); ready_at += cost
  몬스터: MonsterAI.turn / BossAI.turn; ready_at += cost
  환경:  불·물 tick, 상태 만료, 파츠 쿨다운 tick; boundary += 100
```

- **주인공의 한 행동 = 하나의 "구간"**. `s.turn_serial`(주인공 행동 번호)이 옛 `round_number`를 대체한다. 그 구간에서 처음 준비되는 동료는 한 번만 판단한다(무기가 빠르면 두 번 준비될 수 있고, 그때는 두 번 판단한다 — DCSS와 같다).
- `NpcAI.sense`는 구간마다 한 번(`advance` 끝). 소음 `s.noise`는 구간 시작에 비우고 구간 동안 쌓인다(현행 "sense 전부 → clear → turn"을 "advance 끝: sense 전부 → clear"로).
- `Kernel.advance`의 동시각 우선순위(환경 > 액터 id 오름차순, 주인공은 준비된 행동을 모두 처리한 뒤 행동)를 유지한다. 구간 `[time,end)`의 끝 시각에 준비된 행동은 다음 유효 입력 직전에 `flush_ready`로 해소한다. 무효 입력은 시간·행동을 진행하지 않는다.

## 4. 라운드 → tick 재정의

| 항목 | 지금 | 이후 |
| --- | --- | --- |
| 예고(`cast_left`, 보스 `fuse`) | 라운드 수 | `intents[].resolve_at = time + n·100`; `Rules.lethal_threat`·룩어헤드는 `resolve_at ≤ time + 100`인 예고만 "이번 구간" 위협으로 |
| 태세 commitment (`mode_until`, `same_as_last`) | 10라운드 / 직전 행동 | 1000 tick / 직전 행동(변화 없음) |
| 실수 시드 lane | `depth·100000 + round·100 + id` | `depth·100000 + turn_serial·100 + id` |
| 영입 시드 lane | 같음 | 같음(`turn_serial`) |
| NPC 잠듦 | 5라운드 | 500 tick 미관측·무소음 |
| 영입 쿨다운 20라운드 | | 2000 tick |
| 파츠 쿨다운 | 라운드 | `cooldown·100` tick, 환경 tick에서 감소 |
| 스트레스 tick (전투 중 +2/라운드) | | 구간마다 +2(파티 시야에 적이 있을 때) |
| `battle_stats.rounds` | | `turn_serial` 차이 |
| `explains` 창 20 | 최근 20 행동 | 같음 |
| `auto.stops`, `prev_threats`, `remember_round` | | 삭제 |

## 5. 숙련

### 5.1 축과 화면

무기 `sword spear mace axe bow` · 마법 `fire ice air hex summon`. 캐릭터별 `skill_xp[axis]`, `rank 0~10`, `unlocked[key]`. 화면은 Codex 초안 §4의 5×2 그리드 계약을 그대로 쓴다(`MasteryGrid`, 아이콘 68px, 탭 → Lv1~10 상세, `[획득]/[다음]/[잠김]`, `+투자` 버튼 없음). 모든 레벨에 기본 수치 보정을 표시하고, 효과 ID가 없는 고유 보상 행만 숨긴다. 따라서 첫 구현에서 고유 효과가 없는 여덟 축도 빈 상세 화면이 되지 않는다.

### 5.2 XP

- 적 처치 시 `kill_xp = 18 + depth·8`. 그 적과 교전한 아군(`actor.usage[enemy.id]`에 기록이 있는 파티원·NPC)에게 **기여 비율**(기록 횟수)로 나누고, 각자는 자기 축 비율로 `add_skill_xp`. 원본 `award_usage_xp` 그대로, 액터별로.
- 기록되는 사용: 유효 무기 공격(명중·회피·방패 방어 모두 "교전"으로 1회), 주문 시전(효과가 있을 때), 파츠 사용은 파츠의 `axis`(MELEE→무기 축 없음 → 기록 안 함; RANGED→`bow`; MAGIC→주문 학파 대신 `hex`). 허공 공격·효과 없는 반복 시전·소환수 반복 처치는 기록 없음.
- 종족 적성은 XP 획득에만(`amount·apt/100`).
- 무기 교체 따라잡기: 새 축의 Lv1·Lv2 요구 XP를 절반(`25·(r+1)²/2`). 무료 이전 없음.
- NPC는 파티 밖에서 이긴 전투의 XP를 자기에게 기록하고 명부에 유지한다.

### 5.3 효과

`mastery.json`의 각 축 Lv1~10 중 **효과 ID가 있는 행**만 실제 동작:
- 공통 수치 규칙(모든 축): 무기 축 rank당 피해 +1·지연 −4(원본 `stats`); 마법 축 rank당 실패율 −5·위력 +1.
- 이정표 Lv3/5/7/10: 각 축 4개, 첫 단면은 `sword`(Lv3 `deep_cut` 출혈 2턴, Lv5 `riposte` 회피 후 반격, Lv7 `combo` 연속 공격 시 지연 −20, Lv10 `swordmaster` 치명 +10%)와 `fire`(Lv3 `ember` 화염 지속 +1, Lv5 `flare` bolt 범위 1, Lv7 `heat` 저항 −20 관통, Lv10 `inferno` 위력 ×1.5)만 구현. 다른 축의 이정표는 `effect_id` 없음 → 화면에 이름만 잠김으로 표시하지 않는다(행 자체를 숨김).
- 융합: `sword_fire`(main 5 + sub 3) 공격에 화염 4 추가, tier2(8+6) 8; `fire_sword`(main 5 + sub 3) 화염 주문 명중 시 인접 적에게 검 피해 절반. 나머지 융합은 잠김·비표시.

## 6. 장비·주문·아이템

- 장비 슬롯 `gear = {weapon, armour, shield, ring}`(아이템 dict 또는 `{}`). 양손 무기(`trait in [ranged, focus]`가 아닌 `bow/staff`)와 방패 동시 장착 금지(원본 `stats` 조건 그대로).
- 시작 장비는 모임 화면(§1.0)에서 고르는 **10개 중 하나**(숙련 10축에 하나씩). 방어구는 전원 `robe`.

| 축 | 아이템 | 내용 |
| --- | --- | --- |
| sword | 장검 | `sword` |
| spear | 창 | `spear`(사거리 2) |
| mace | 철퇴 | `mace`(관통) |
| axe | 도끼 | `axe`(휩쓸기) |
| bow | 활 | `bow`(사거리 6) |
| fire | 화염 지팡이 | `staff` + 주문 `bolt` 습득·준비 |
| ice | 서리 지팡이 | `staff` + `cone` |
| air | 폭풍 지팡이 | `staff` + `cloud` |
| hex | 주박 지팡이 | `staff` + `confuse` |
| summon | 소환 지팡이 | `staff` + `hound` |

  NPC 명부 생성 시 같은 표에서 시드로 하나(성격 가중: X ≥ 600 → axe/mace, C ≥ 600 → spear/bow, O ≥ 600 → 마법 5, 나머지 sword).
- 획득: 조사물 `BROKEN_CHEST`·`DEAD_ADVENTURER`가 파츠/소모품 외에 장비도 준다(깊이별 표는 `combat.json.loot`). 장착·해제는 야영에서만.
- 주문: 배운 목록 `actor.spells`와 준비 `actor.prepared`(최대 3, 야영에서 변경). 시작 주문은 시작 장비가 마법 지팡이일 때 그 학파의 첫 주문 하나; 그 외는 `DEAD_ADVENTURER`·보스 드롭 주문서. HUD에는 준비 주문 3개만.
- 소모품 5종 유지. Model B `supplies`(heal/blink/haste/fog/wand)는 가져오지 않는다.
- 몬스터: 8종에 `speed/ac/ev/res`. 역할(MELEE/RANGED/CASTER)과 파츠는 그대로. 보스 3종은 §7에서 재측정.

## 7. 검증·게이트

새 스위트(CI 등록): `combat_stats`(실효값·장비·상태·숙련 보정, 이중 적용 없음), `combat_rules`(회피·방패·AC·관통·절단·브랜드·저항, 결정론), `scheduler`(빠른/느린 무기, 2인 적, 동시각 우선순위, 예고 `resolve_at`, 자동 이동 정지 시점, 야영·계단 시간 정지, 시드 재현), `mastery`(rank 공식, 기여 분배, 따라잡기, NPC 개인 XP, `sword`/`fire` 효과, 두 융합, 미구현 비표시), `mastery_ui`(5×2 그리드, 상세, 320/390px, 3인 전환).
갱신: `autobattle`→ 삭제하고 `companions`로 대체(동료가 자기 차례에 `Tactics.choose`로 행동, 명령 없음), `stances`/`utility`/`npc_*`/`recruit`(라운드 → 구간·tick 재정의, 검사 수 유지), `arena_mode`(전투 시험은 주인공 수동 + 동료 자동으로), `solo_balance`·`stance_gate`·`ranged_probe`·`encounter_sim`(봇이 `submit`으로 주인공을 움직임; 전투 수학이 바뀌므로 옛 승률을 합격선으로 쓰지 않고 새 기준선을 `docs/balance/model-b-gates.md`에 기록).
삭제: `auto_step`·정지 이벤트·명령 검사, `battle_presentation`의 자동 재생 의존 부분(수동 행동마다 재생으로 바꿈).

## 8. 작업 순서 (계획서의 Task 경계)

1. 데이터·`combat_stats`·`combat_rules`·장비 슬롯: `act_as("ATTACK")`과 `attack_preview`가 새 수학을 씀. 아직 라운드제.
2. `scheduler.gd`·`Session.submit`·오토배틀 제거·§4 재정의·HUD(▶/⏸·후퇴 제거, 위험 경고, 준비 주문 3).
3. `mastery.gd`·`mastery.json`·`growth.gd` 삭제·XP 분배·`sword`/`fire` 효과·두 융합.
4. `spells.gd` 5주문·주문서 드롭·장비 드롭·몬스터 필드.
5. 숙련 5×2 UI·장비 창(현재 대비 변화 표시).
6. 게이트 재측정·문서.

## 9. 범위 밖

주문 12종 전부의 효과, 융합 30개, 종족 선택 UI, 신앙, 저장/이어하기, 자동 탐험 고도화, 몬스터 24종 추가, 무기 교체 실험의 따라잡기 수치 확정.
