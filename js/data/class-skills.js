/* ================= Class 스킬 60 (docs/설계_직업.md §4) =================
   tgt: self(자기) · foe(적) · ally(아군, 자기 포함) · tile(칸) · dir(방향: 칸을 고르면 그쪽으로) · r = 사거리(칸)
   p = 수치(위력이 곱해지는 값: mul·dmg·heal·shield·up·vuln·bonus·burst·poison·bleed · 지속: dur·root·stun·taunt·ward·guard)
   aff = 두 우물 전용 스킬이 기대는 Class, self/other = 기대는 쪽이 높을 때 / 반대쪽이 높을 때 덮어쓰는 값
   ai = 봇·파티 AI가 쓰는 때: foe(사거리 안 적) · winding(힘 모으는 적) · incoming(나를 노리고 힘 모으는 적) · crowd(적 둘 이상) · hurt(다친 아군) · low(위태로운 아군) · fight(전투 중) · close(붙은 적) · aiming(겨누는 적)
   d(p) = 설명 한 줄 */
export const CSKILLS = {
  /* ---------- 기본: 파이터 ---------- */
  f_block: { name: '방패 세우기', icon: '🛡', tgt: 'self', r: 0, cast: 0.1, cd: 6, p: { dur: 2, half: 60 }, ai: 'incoming', d: (p) => `${p.dur}초 동안 앞 ±${p.half}°에서 오는 공격을 막는다` },
  f_taunt: { name: '도발 외침', icon: '📣', tgt: 'self', r: 0, cast: 0.2, cd: 8, p: { r: 3, dur: 4, def: 1 }, ai: 'crowd', d: (p) => `반경 ${p.r}칸 적이 ${p.dur}초 동안 나를 노린다. 그동안 방어 +${p.def}` },
  f_bash: { name: '방패 치기', icon: '💥', tgt: 'foe', r: 1.6, cast: 0.15, cd: 6, p: { mul: 0.6, n: 1 }, ai: 'winding', d: (p) => `무기 ×${p.mul}, 준비 동작을 끊고 ${p.n}칸 밀친다` },
  /* ---------- 기본: 로그 ---------- */
  r_stab: { name: '급소 찌르기', icon: '🗡', tgt: 'foe', r: 1.8, cast: 0.1, cd: 5, p: { mul: 1.3, x: 2, low: 0 }, ai: 'foe', d: (p) => `무기 ×${p.mul}. 힘 모으는 적이면 끊고 ×${p.x}${p.low ? ', HP 절반 아래 적에게도' : ''}` },
  r_evade: { name: '회피 자세', icon: '🌀', tgt: 'self', r: 0, cast: 0, cd: 8, p: { dur: 0.6, mul: 1.5 }, ai: 'incoming', d: (p) => `${p.dur}초 동안 근접 공격을 받으면 피하고 무기 ×${p.mul}로 되친다` },
  r_dash: { name: '그림자 돌진', icon: '💨', tgt: 'dir', r: 3, cast: 0, cd: 9, p: { dist: 3, mul: 1 }, ai: 'foe', d: (p) => `${p.dist}칸 돌진, 지나간 적 모두 무기 ×${p.mul}` },
  /* ---------- 기본: 레인저 ---------- */
  ra_pierce: { name: '관통 사격', icon: '➶', tgt: 'dir', r: 7, cast: 0.2, cd: 6, p: { range: 7, mul: 1.2, bonus: 3 }, ai: 'foe', d: (p) => `꿰뚫는 화살, 무기 ×${p.mul} + ${p.bonus}` },
  ra_trap: { name: '올가미 덫', icon: '🪤', tgt: 'tile', r: 5, cast: 0.3, cd: 10, p: { root: 3, dmg: 2, dur: 20, n: 1 }, ai: 'foe', d: (p) => `${p.dur}초 동안 놓인 덫. 밟은 적 ${p.root}초 묶기 + 피해 ${p.dmg}${p.n > 1 ? ` (${p.n}번)` : ''}` },
  ra_leap: { name: '물러나 쏘기', icon: '↩', tgt: 'self', r: 0, cast: 0, cd: 7, p: { dist: 2, mul: 1 }, ai: 'close', d: (p) => `뒤로 ${p.dist}칸 뛰고 가장 가까운 적에게 화살 무기 ×${p.mul}` },
  /* ---------- 기본: 위저드 ---------- */
  w_fire: { name: '화염구', icon: '🔥', tgt: 'tile', r: 6, cast: 0.4, cd: 7, p: { dmg: 6, burn: 0 }, ai: 'foe', d: (p) => `십자 5칸 불 ${p.dmg}${p.burn ? `, 화상 +${p.burn}` : ''}. 기름이 터지고 풀에 번진다` },
  w_chain: { name: '번개 사슬', icon: '⚡', tgt: 'foe', r: 6, cast: 0.3, cd: 7, p: { dmg: 5, jumps: 2, ratio: 0.6 }, ai: 'foe', d: (p) => `번개 ${p.dmg}, 젖었으면 번진다. 가까운 적 ${p.jumps}에게 튄다(×${p.ratio})` },
  w_ray: { name: '냉기 광선', icon: '❄', tgt: 'dir', r: 5, cast: 0.3, cd: 8, p: { dmg: 4, range: 5 }, ai: 'foe', d: (p) => `직선 ${p.range}칸 냉기 ${p.dmg}, 젖은 적은 얼어붙는다` },
  /* ---------- 기본: 클레릭 ---------- */
  c_heal: { name: '치유', icon: '✚', tgt: 'ally', r: 5, cast: 0.4, cd: 4, p: { heal: 8, cleanse: 0 }, ai: 'hurt', d: (p) => `HP ${p.heal}${p.cleanse ? ', 해로운 상태이상을 지운다' : ''}` },
  c_shield: { name: '신앙의 방패', icon: '🔰', tgt: 'ally', r: 5, cast: 0.2, cd: 7, p: { shield: 6 }, ai: 'incoming', d: (p) => `보호막 ${p.shield}` },
  c_ward: { name: '죽음 유예', icon: '⏳', tgt: 'ally', r: 5, cast: 0.2, cd: 30, p: { ward: 8 }, ai: 'low', d: (p) => `${p.ward}초 안에 쓰러질 피해를 받으면 HP 1로 버틴다` },
  /* ---------- 기본: 바드 ---------- */
  b_disc: { name: '불협화음', icon: '🎵', tgt: 'foe', r: 6, cast: 0.1, cd: 5, p: { dmg: 2, stun: 0, delay: 0.5 }, ai: 'winding', d: (p) => `피해 ${p.dmg}, 준비 동작을 끊는다${p.stun ? `, ${p.stun}초 기절` : ''}. 보스는 힘 모으기 +${p.delay}초` },
  b_song: { name: '용기의 노래', icon: '🎶', tgt: 'self', r: 0, cast: 0.3, cd: 12, p: { r: 4, up: 2, haste: 0.2, dur: 5 }, ai: 'fight', d: (p) => `${p.r}칸 안 아군 ${p.dur}초 동안 피해 +${p.up}, 박자 ${Math.round(p.haste * 100)}% 빠르게` },
  b_fog: { name: '안개 구름', icon: '🌫', tgt: 'tile', r: 6, cast: 0.2, cd: 12, p: { r: 1.5, dur: 6 }, ai: 'aiming', d: (p) => `반경 ${p.r}칸 ${p.dur}초 안개. 궁수·마법사가 겨누지 못한다` },

  /* ---------- 한 우물 전용 ---------- */
  g_wall: { name: '성벽', icon: '🏰', tgt: 'self', r: 0, cast: 0.1, cd: 12, p: { guard: 2, r: 4, taunt: 3 }, ai: 'crowd', d: (p) => `${p.guard}초 동안 사방을 막고, 반경 ${p.r}칸 적이 ${p.taunt}초 나를 노린다` },
  g_charge: { name: '방패 돌격', icon: '🐂', tgt: 'dir', r: 4, cast: 0, cd: 10, p: { dist: 4, n: 2, mul: 1 }, ai: 'foe', d: (p) => `${p.dist}칸 돌진, 앞의 적 모두 무기 ×${p.mul}, ${p.n}칸 밀치고 끊는다` },
  a_mark: { name: '죽음의 표식', icon: '☠', tgt: 'foe', r: 6, cast: 0.1, cd: 12, p: { vuln: 4, dur: 5 }, ai: 'foe', d: (p) => `${p.dur}초 동안 받는 피해 +${p.vuln}` },
  a_step: { name: '그림자 걸음', icon: '👤', tgt: 'foe', r: 5, cast: 0, cd: 9, p: { mul: 1.5 }, ai: 'foe', d: (p) => `적 뒤로 순간이동해 무기 ×${p.mul}` },
  s_aim: { name: '조준 사격', icon: '🎯', tgt: 'dir', r: 9, cast: 0.8, cd: 8, p: { range: 9, mul: 3.2 }, ai: 'foe', d: (p) => `0.8초 조준 뒤 무기 ×${p.mul} 꿰뚫기` },
  s_volley: { name: '화살비', icon: '🌧', tgt: 'tile', r: 7, cast: 0.4, cd: 10, p: { r: 1.5, mul: 1 }, ai: 'crowd', d: (p) => `반경 ${p.r}칸 적 모두 무기 ×${p.mul}` },
  am_flood: { name: '대홍수', icon: '🌊', tgt: 'tile', r: 6, cast: 0.5, cd: 14, p: { size: 2, n: 1 }, ai: 'crowd', d: (p) => `${p.size * 2 + 1}×${p.size * 2 + 1} 물바다, 안의 적 젖고 ${p.n}칸 밀린다` },
  am_meteor: { name: '운석', icon: '☄', tgt: 'tile', r: 7, cast: 1.0, cd: 12, p: { dmg: 16 }, ai: 'foe', d: (p) => `1초 예고 뒤 3×3 불 ${p.dmg}` },
  hp_radiance: { name: '광휘', icon: '☀', tgt: 'self', r: 0, cast: 0.5, cd: 10, p: { r: 5, heal: 14 }, ai: 'hurt', d: (p) => `${p.r}칸 안 아군 모두 HP ${p.heal}` },
  hp_sanct: { name: '성역', icon: '⛪', tgt: 'tile', r: 5, cast: 0.4, cd: 16, p: { r: 2, dur: 6, heal: 3, def: 1 }, ai: 'fight', d: (p) => `반경 ${p.r}칸 ${p.dur}초: 아군 1초마다 HP ${p.heal}, 받는 피해 −${p.def}` },
  ma_cresc: { name: '크레셴도', icon: '🎼', tgt: 'self', r: 0, cast: 0.3, cd: 18, p: { r: 5, up: 3, haste: 0.3, dur: 6 }, ai: 'fight', d: (p) => `${p.r}칸 안 아군 ${p.dur}초 동안 피해 +${p.up}, 박자 ${Math.round(p.haste * 100)}% 빠르게` },
  ma_silence: { name: '침묵의 화음', icon: '🔇', tgt: 'self', r: 0, cast: 0.2, cd: 14, p: { r: 4, stun: 1.5 }, ai: 'winding', d: (p) => `${p.r}칸 안 적 모두 끊고 ${p.stun}초 기절` },

  /* ---------- 두 우물 전용 ---------- */
  sm_riposte: { name: '반격 태세', icon: '⚔', aff: 'fighter', tgt: 'self', r: 0, cast: 0, cd: 9, p: { dur: 1, mul: 1.5 }, self: { dur: 1.4 }, other: { mul: 2.2 }, ai: 'incoming', d: (p) => `${p.dur}초 동안 근접 공격을 받아 무기 ×${p.mul}로 되치고, 화살은 튕긴다` },
  sm_whirl: { name: '칼바람', icon: '🌪', aff: 'rogue', tgt: 'self', r: 0, cast: 0.1, cd: 8, p: { r: 1.8, mul: 1.1, bleed: 0, taunt: 0 }, self: { bleed: 3 }, other: { taunt: 1 }, ai: 'crowd', d: (p) => `둘레 ${p.r}칸 적 모두 무기 ×${p.mul}${p.bleed ? `, 출혈 +${p.bleed}` : ''}${p.taunt ? `, ${p.taunt}초 나를 노린다` : ''}` },
  wd_line: { name: '경계선', icon: '🚧', aff: 'fighter', tgt: 'tile', r: 4, cast: 0.2, cd: 14, p: { r: 1.5, dur: 6, root: 1 }, self: { root: 1.5 }, other: { r: 2.5 }, ai: 'fight', d: (p) => `반경 ${p.r}칸 ${p.dur}초 구역: 들어온 적 ${p.root}초 묶기(한 번씩)` },
  wd_spear: { name: '투창', icon: '🔱', aff: 'ranger', tgt: 'dir', r: 6, cast: 0.2, cd: 7, p: { range: 6, mul: 1.4, root: 1.5, pierce: 0, taunt: 0 }, self: { pierce: 1 }, other: { taunt: 2 }, ai: 'foe', d: (p) => `창 무기 ×${p.mul}, 맞은 적 ${p.root}초 묶기${p.pierce ? ', 꿰뚫는다' : ''}${p.taunt ? `, ${p.taunt}초 나를 노린다` : ''}` },
  rk_ward: { name: '룬 방벽', icon: '🧿', aff: 'fighter', tgt: 'self', r: 0, cast: 0.1, cd: 12, p: { shield: 6, guard: 0.5, burst: 3, br: 1.5 }, self: { shield: 9 }, other: { burst: 5, br: 2.5 }, ai: 'incoming', d: (p) => `보호막 ${p.shield}, ${p.guard}초 사방 막기. 깨지면 둘레 ${p.br}칸 냉기 ${p.burst}` },
  rk_runes: { name: '원소 룬', icon: '🔮', aff: 'wizard', tgt: 'self', r: 0, cast: 0.1, cd: 12, p: { dur: 6, dmg: 1, sh: 0 }, self: { dmg: 2 }, other: { sh: 1 }, ai: 'fight', d: (p) => `${p.dur}초 동안 무기 적중마다 원소 ${p.dmg}(불 → 냉기 → 번개)${p.sh ? `, 보호막 +${p.sh}` : ''}` },
  pa_oath: { name: '수호의 맹세', icon: '🤝', aff: 'fighter', tgt: 'ally', r: 5, cast: 0.1, cd: 12, p: { dur: 6, share: 0.5, shield: 0 }, self: { share: 0.7 }, other: { share: 0.3, shield: 6 }, ai: 'fight', d: (p) => `${p.dur}초 동안 그 아군이 받는 피해의 ${Math.round(p.share * 100)}%를 대신 받는다${p.shield ? `, 보호막 ${p.shield}` : ''}. 자기에게 쓰면 받는 피해 −30%` },
  pa_smite: { name: '신성한 일격', icon: '✨', aff: 'cleric', tgt: 'self', r: 0, cast: 0, cd: 9, p: { mul: 1.8, stun: 1, r: 3, heal: 4 }, self: { heal: 7 }, other: { stun: 2 }, ai: 'foe', d: (p) => `다음 무기 공격 ×${p.mul}, ${p.stun}초 기절, ${p.r}칸 안 아군 HP ${p.heal}` },
  wl_duel: { name: '결투 신청', icon: '🤺', aff: 'fighter', tgt: 'foe', r: 5, cast: 0.1, cd: 10, p: { dur: 6, vuln: 2, def: 0 }, self: { dur: 8, def: 2 }, other: { vuln: 4 }, ai: 'foe', d: (p) => `그 적이 ${p.dur}초 동안 나를 노리고 받는 피해 +${p.vuln}${p.def ? `, 그동안 방어 +${p.def}` : ''}` },
  wl_rally: { name: '집결의 함성', icon: '📯', aff: 'bard', tgt: 'self', r: 0, cast: 0.3, cd: 14, p: { r: 5, shield: 4, up: 2, dur: 5 }, self: { up: 3, dur: 8 }, other: { shield: 7 }, ai: 'fight', d: (p) => `${p.r}칸 안 아군 보호막 ${p.shield}, ${p.dur}초 피해 +${p.up}` },
  st_venom: { name: '독 칼날', icon: '🐍', aff: 'rogue', tgt: 'self', r: 0, cast: 0, cd: 10, p: { dur: 6, poison: 4 }, self: { poison: 6 }, other: { dur: 10 }, ai: 'fight', d: (p) => `${p.dur}초 동안 무기 적중마다 중독 ${p.poison}` },
  st_net: { name: '그물', icon: '🕸', aff: 'ranger', tgt: 'dir', r: 5, cast: 0.2, cd: 9, p: { range: 5, root: 3, vuln: 2, area: 0 }, self: { area: 1 }, other: { vuln: 4 }, ai: 'foe', d: (p) => `그물: 맞은 적 ${p.root}초 묶기, 받는 피해 +${p.vuln}${p.area ? `, 반경 ${p.area}칸 모두` : ''}` },
  nb_edge: { name: '원소 칼날', icon: '🌩', aff: 'rogue', tgt: 'foe', r: 1.8, cast: 0.1, cd: 6, p: { mul: 1.2, dmg: 3 }, self: { mul: 1.6 }, other: { dmg: 5 }, ai: 'foe', d: (p) => `무기 ×${p.mul} + 그 자리 번개 ${p.dmg}(젖으면 번진다)` },
  nb_blink: { name: '비전 점멸', icon: '✴', aff: 'wizard', tgt: 'tile', empty: 1, r: 5, cast: 0, cd: 8, p: { dmg: 3, freeze: 0, next: 0 }, self: { dmg: 5, freeze: 1 }, other: { next: 1.5 }, ai: 'close', d: (p) => `그 칸으로 순간이동, 떠난 자리 냉기 ${p.dmg}${p.freeze ? '(젖은 적 빙결)' : ''}${p.next ? `, 다음 무기 공격 ×${p.next}` : ''}` },
  sp_veil: { name: '그림자 장막', icon: '🌑', aff: 'rogue', tgt: 'self', r: 0, cast: 0.2, cd: 16, p: { r: 3, dur: 5, n: 1, heal: 0 }, self: { n: 2 }, other: { heal: 3 }, ai: 'incoming', d: (p) => `${p.r}칸 안 아군 ${p.dur}초 동안 다음 공격 ${p.n}번 무효${p.heal ? `, 막을 때마다 HP ${p.heal}` : ''}` },
  sp_drain: { name: '생명 흡수', icon: '🩸', aff: 'cleric', tgt: 'foe', r: 5, cast: 0.3, cd: 7, p: { dmg: 5, ratio: 1 }, self: { ratio: 1.5 }, other: { dmg: 8 }, ai: 'foe', d: (p) => `피해 ${p.dmg}, 그 ${p.ratio === 1 ? '만큼' : `×${p.ratio}만큼`} 나와 가장 다친 아군 회복` },
  tr_decoy: { name: '미끼', icon: '🎭', aff: 'rogue', tgt: 'tile', empty: 1, r: 4, cast: 0.2, cd: 16, p: { dur: 4, hp: 10, r: 5, burst: 0 }, self: { burst: 5 }, other: { dur: 7 }, ai: 'crowd', d: (p) => `${p.dur}초 서 있는 미끼(HP ${p.hp}): ${p.r}칸 안 적이 미끼를 노린다${p.burst ? `. 끝나면 둘레 피해 ${p.burst}` : ''}` },
  tr_swap: { name: '자리 바꾸기', icon: '🔄', aff: 'bard', tgt: 'foe', r: 6, cast: 0.1, cd: 12, p: { stun: 0, next: 0 }, self: { stun: 1.5 }, other: { next: 1.5 }, ai: 'winding', d: (p) => `대상과 자리를 바꾸고 끊는다${p.stun ? `, ${p.stun}초 기절` : ''}${p.next ? `, 다음 무기 공격 ×${p.next}` : ''}` },
  aa_storm: { name: '폭풍 화살', icon: '⛈', aff: 'ranger', tgt: 'tile', r: 7, cast: 0.3, cd: 12, p: { r: 1.5, dmg: 3 }, self: { r: 2.5 }, other: { dmg: 5 }, ai: 'crowd', d: (p) => `반경 ${p.r}칸 번개 ${p.dmg}(물·젖음으로 번진다)` },
  aa_elem: { name: '원소 화살', icon: '🏹', aff: 'wizard', tgt: 'dir', r: 7, cast: 0.2, cd: 6, p: { range: 7, mul: 1, dmg: 3, pierce: 0 }, self: { dmg: 5 }, other: { pierce: 1 }, ai: 'foe', d: (p) => `화살 무기 ×${p.mul} + 맞은 곳 원소 ${p.dmg}(불 → 냉기 → 번개)${p.pierce ? ', 꿰뚫는다' : ''}` },
  wh_seal: { name: '봉인 사격', icon: '📿', aff: 'ranger', tgt: 'dir', r: 7, cast: 0.2, cd: 8, p: { range: 7, mul: 1.4, dur: 4, heal: 0 }, self: { dur: 6 }, other: { heal: 3 }, ai: 'aiming', d: (p) => `화살 무기 ×${p.mul}, 맞은 적을 끊고 ${p.dur}초 주문·조준 금지${p.heal ? `, 내 HP ${p.heal}` : ''}` },
  wh_bless: { name: '축복 화살', icon: '💫', aff: 'cleric', tgt: 'ally', r: 6, cast: 0.2, cd: 8, p: { heal: 6 }, self: { heal: 10 }, other: { cd: 5 }, ai: 'hurt', d: (p) => `아군 HP ${p.heal} + 해로운 상태이상 지우기` },
  sc_flare: { name: '조명탄', icon: '🎇', aff: 'ranger', tgt: 'tile', r: 7, cast: 0.2, cd: 16, p: { r: 2.5, dur: 8, vuln: 1 }, self: { r: 3.5 }, other: { vuln: 2 }, ai: 'fight', d: (p) => `반경 ${p.r}칸 ${p.dur}초: 숨은 적이 드러나고, 안의 적 받는 피해 +${p.vuln}` },
  sc_mark: { name: '표식', icon: '🔖', aff: 'bard', tgt: 'foe', r: 8, cast: 0.1, cd: 8, p: { vuln: 3, dur: 6 }, self: { vuln: 5 }, other: { dur: 10 }, ai: 'foe', d: (p) => `${p.dur}초 동안 받는 피해 +${p.vuln}` },
  dr_vine: { name: '휘감는 덩굴', icon: '🌿', aff: 'wizard', tgt: 'tile', r: 5, cast: 0.3, cd: 12, p: { r: 1.5, root: 3, dmg: 0, heal: 0 }, self: { root: 4, dmg: 3 }, other: { heal: 4 }, ai: 'crowd', d: (p) => `반경 ${p.r}칸 적 모두 ${p.root}초 묶기${p.dmg ? ` + 피해 ${p.dmg}` : ''}${p.heal ? `, 안의 아군 HP ${p.heal}` : ''}. 바닥이 풀이 된다` },
  dr_bloom: { name: '재생 덩굴', icon: '🌸', aff: 'cleric', tgt: 'tile', r: 5, cast: 0.3, cd: 12, p: { r: 1.5, dur: 6, heal: 2, poison: 0 }, self: { heal: 3 }, other: { poison: 2 }, ai: 'hurt', d: (p) => `반경 ${p.r}칸 ${p.dur}초: 아군 1초마다 HP ${p.heal}${p.poison ? `, 안의 적 중독 ${p.poison}` : ''}` },
  en_hex: { name: '약화 저주', icon: '🕯', aff: 'wizard', tgt: 'foe', r: 6, cast: 0.2, cd: 10, p: { dur: 5, vuln: 1, r: 0 }, self: { vuln: 3 }, other: { r: 1.5 }, ai: 'foe', d: (p) => `${p.dur}초 동안 주는 피해 절반, 받는 피해 +${p.vuln}${p.r ? `, 반경 ${p.r}칸 모두` : ''}` },
  en_haste: { name: '가속 부여', icon: '⏩', aff: 'bard', tgt: 'ally', r: 5, cast: 0.2, cd: 12, p: { dur: 6, haste: 0.3, elem: 0 }, self: { haste: 0.5 }, other: { elem: 2 }, ai: 'fight', d: (p) => `${p.dur}초 동안 이동·박자 ${Math.round(p.haste * 100)}% 빠르게${p.elem ? `, 무기 적중마다 원소 ${p.elem}` : ''}` },
  or_mend: { name: '운명의 치유', icon: '🌙', aff: 'cleric', tgt: 'ally', r: 5, cast: 0.3, cd: 8, p: { heal: 6, ward: 3 }, self: { heal: 10 }, other: { ward: 6 }, ai: 'hurt', d: (p) => `HP ${p.heal} + ${p.ward}초 죽음 유예` },
  or_foresee: { name: '예지', icon: '👁', aff: 'bard', tgt: 'self', r: 0, cast: 0.2, cd: 16, p: { r: 6, dur: 5, slow: 1.5, shield: 0 }, self: { slow: 2 }, other: { shield: 3 }, ai: 'fight', d: (p) => `${p.dur}초 동안 ${p.r}칸 안 적의 힘 모으기가 ${p.slow}배 느리다${p.shield ? `, 안의 아군 보호막 ${p.shield}` : ''}` },
};
/** 위력이 곱해지는 값 · 지속(초) 값 */
export const AMT_KEYS = ['mul', 'dmg', 'heal', 'shield', 'up', 'vuln', 'bonus', 'burst', 'poison', 'bleed'];
export const DUR_KEYS = ['dur', 'root', 'stun', 'taunt', 'ward', 'guard'];
