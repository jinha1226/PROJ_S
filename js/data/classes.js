/* ================= 직업: Role 4 · 기본 Class 6 · 상위 Class 21 (docs/설계_직업.md) =================
   레벨 10을 기본 Class에 나눠 찍는다. 한 Class 10 = 한 우물(MASTERY), 두 Class 각 3 이상 = 두 우물(PAIRS). 스킬은 data/class-skills.js */

export const ROLES = {
  tank: { name: '탱커', icon: '🛡', css: '#6aa8ff' },
  dps: { name: '딜러', icon: '⚔', css: '#ff7a6a' },
  healer: { name: '힐러', icon: '✚', css: '#8fffb0' },
  support: { name: '서포터', icon: '✦', css: '#d6a0ff' },
};

/** 기본 Class: 스킬 셋은 Class 레벨 1 · 3 · 5에 열린다. hpLv = Class 레벨마다 최대 HP */
export const BASE = {
  fighter: { name: '파이터', role: 'tank', epi: '방패의', trait: 'stand', skills: ['f_block', 'f_taunt', 'f_bash'], hpLv: 1, line: '앞을 막는 벽' },
  rogue: { name: '로그', role: 'dps', epi: '그림자의', trait: 'ambush', skills: ['r_stab', 'r_evade', 'r_dash'], hpLv: 0.4, line: '빈틈을 찌르는 암살자' },
  ranger: { name: '레인저', role: 'dps', epi: '사냥의', trait: 'range', skills: ['ra_pierce', 'ra_trap', 'ra_leap'], hpLv: 0.4, line: '거리를 지키는 사냥꾼' },
  wizard: { name: '위저드', role: 'dps', epi: '비전의', trait: 'elem', skills: ['w_fire', 'w_chain', 'w_ray'], hpLv: 0.2, line: '원소를 이어 붙여 터뜨리는 술사' },
  cleric: { name: '클레릭', role: 'healer', epi: '기도의', trait: 'life', skills: ['c_heal', 'c_shield', 'c_ward'], hpLv: 0.6, line: '신앙으로 지키는 사제' },
  bard: { name: '바드', role: 'support', epi: '노래의', trait: 'foresight', skills: ['b_disc', 'b_song', 'b_fog'], hpLv: 0.5, line: '노래로 판을 흔드는 음유시인' },
};
export const BASE_IDS = Object.keys(BASE);

/** 한 우물(한 Class 10): 기본 스킬 셋이 강화판 + 전용 둘, 특성 강 */
export const MASTERY = {
  fighter: { name: '가디언', role: 'tank', skills: ['g_wall', 'g_charge'], line: '몸으로 막는 요새' },
  rogue: { name: '어쌔신', role: 'dps', skills: ['a_mark', 'a_step'], line: '표식을 남기고 뒤를 잡는다' },
  ranger: { name: '스나이퍼', role: 'dps', skills: ['s_aim', 's_volley'], line: '멀리서 한 발로' },
  wizard: { name: '아크메이지', role: 'dps', sub: 'support', skills: ['am_flood', 'am_meteor'], line: '지형을 바꾸는 대마법' },
  cleric: { name: '하이 프리스트', role: 'healer', skills: ['hp_radiance', 'hp_sanct'], line: '모두를 일으키는 빛' },
  bard: { name: '마에스트로', role: 'support', skills: ['ma_cresc', 'ma_silence'], line: '파티의 박자를 지휘한다' },
};

/** 두 우물(두 Class 각 3 이상): 키는 BASE 순서로 'a+b'. 전용 스킬 둘은 각각 기대는 Class가 있다(data/class-skills.js aff) */
export const PAIRS = {
  'fighter+rogue': { name: '소드마스터', skills: ['sm_riposte', 'sm_whirl'], line: '패리와 칼바람' },
  'fighter+ranger': { name: '워든', skills: ['wd_line', 'wd_spear'], line: '선을 지키는 파수꾼' },
  'fighter+wizard': { name: '룬나이트', skills: ['rk_ward', 'rk_runes'], line: '원소를 두른 전사' },
  'fighter+cleric': { name: '팔라딘', skills: ['pa_oath', 'pa_smite'], line: '아군 대신 맞는 기사' },
  'fighter+bard': { name: '워로드', skills: ['wl_duel', 'wl_rally'], line: '전장을 지휘하는 장수' },
  'rogue+ranger': { name: '스토커', skills: ['st_venom', 'st_net'], line: '추적과 독' },
  'rogue+wizard': { name: '나이트블레이드', skills: ['nb_edge', 'nb_blink'], line: '마법 암살자' },
  'rogue+cleric': { name: '섀도 프리스트', skills: ['sp_veil', 'sp_drain'], line: '흡수로 버티는 사제' },
  'rogue+bard': { name: '트릭스터', skills: ['tr_decoy', 'tr_swap'], line: '판을 뒤집는 잔꾀' },
  'ranger+wizard': { name: '아케인 아처', skills: ['aa_storm', 'aa_elem'], line: '원소 화살' },
  'ranger+cleric': { name: '위치 헌터', skills: ['wh_seal', 'wh_bless'], line: '마법을 끊는 사수' },
  'ranger+bard': { name: '스카우트', skills: ['sc_flare', 'sc_mark'], line: '정찰과 표식' },
  'wizard+cleric': { name: '드루이드', skills: ['dr_vine', 'dr_bloom'], line: '덩굴과 자연 치유' },
  'wizard+bard': { name: '인챈터', skills: ['en_hex', 'en_haste'], line: '강화와 약화 마법' },
  'cleric+bard': { name: '오라클', skills: ['or_mend', 'or_foresee'], line: '예지와 치유' },
};
export const pairKey = (a, b) => (BASE_IDS.indexOf(a) <= BASE_IDS.indexOf(b) ? `${a}+${b}` : `${b}+${a}`);

/** 고유 특성: v = [약(두 우물), 보통(기본), 강(한 우물)] */
export const TRAITS = {
  stand: { name: '버팀', v: [1, 1, 2], line: (v) => `멈춰 서 있으면 받는 피해 −${v}` },
  ambush: { name: '기습', v: [2, 3, 5], line: (v) => `힘 모으거나 경직된 적에게 피해 +${v}` },
  range: { name: '원거리', v: [1, 2, 3], line: (v) => `4칸 이상 떨어진 적에게 피해 +${v}` },
  elem: { name: '원소 친화', v: [1.15, 1.3, 1.5], line: (v) => `원소 피해 ×${v}` },
  life: { name: '생명의 권능', v: [1, 2, 4], line: (v) => `치유 +${v}` },
  foresight: { name: '예지', v: [[3, 1.05], [4, 1.1], [5, 1.2]], line: (v) => `곧 예고를 걸 적이 보이고, ${v[0]}칸 안 적의 힘 모으기가 ${Math.round((v[1] - 1) * 100)}% 느리다` },
};

/** 갈래: 그 Class 레벨 7에 둘 중 하나. mod = { 스킬: { 값 덮어쓰기 } }, cdAdd = 쿨타임 더하기 */
export const BRANCHES = {
  fighter: { A: { name: '철벽', line: '방패 세우기 3초, 반각 75°', mod: { f_block: { dur: 3, half: 75 } } }, B: { name: '도전', line: '도발 외침 반경 4, 5초', mod: { f_taunt: { r: 4, dur: 5 } } } },
  rogue: { A: { name: '암살', line: '급소 찌르기가 HP 절반 아래 적에게도 ×2', mod: { r_stab: { low: 1 } } }, B: { name: '곡예', line: '회피 자세 0.9초, 그림자 돌진 쿨타임 −3초', mod: { r_evade: { dur: 0.9 }, r_dash: { cdAdd: -3 } } } },
  ranger: { A: { name: '명사수', line: '관통 사격 쿨타임 −2초', mod: { ra_pierce: { cdAdd: -2 } } }, B: { name: '덫꾼', line: '올가미 덫이 두 번 묶는다', mod: { ra_trap: { n: 2 } } } },
  wizard: { A: { name: '연소', line: '화염구가 화상 +2', mod: { w_fire: { burn: 2 } } }, B: { name: '뇌전', line: '번개 사슬이 두 번 더 튄다', mod: { w_chain: { jumps: 4 } } } },
  cleric: { A: { name: '은총', line: '치유가 해로운 상태이상도 지운다', mod: { c_heal: { cleanse: 1 } } }, B: { name: '수호', line: '신앙의 방패 +4', mod: { c_shield: { shield: 10 } } } },
  bard: { A: { name: '선율', line: '용기의 노래 7초', mod: { b_song: { dur: 7 } } }, B: { name: '교란', line: '불협화음이 1초 기절시킨다', mod: { b_disc: { stun: 1 } } } },
};

/** 교차 성장 수치 */
export const CLASS_RULE = {
  cap: 10, // 총 Class 레벨
  unlock: [1, 3, 5], // 기본 스킬이 열리는 Class 레벨
  branchAt: 7, // 갈래를 고르는 Class 레벨
  pairMin: 3, // 두 우물 상위 Class가 되는 작은 쪽 최소 레벨
  leanGap: 2, // 차이가 이만큼 이상이면 기운 형태(수식어)
  slots: 3, // 장착 스킬 칸
  mastery: { cd: 0.75, amt: 1.25 }, // 한 우물 강화판
  xp: [0, 80, 200, 380, 620, 950, 1400, 2000, 2800, 3800], // 레벨 1~10에 닿는 누적 경험(1구역을 마치면 약 5)
  hpLevel: 2, // 레벨마다 기본 HP
};
/** 위력: 그 스킬이 속한 Class 레벨로 */
export const potencyOf = (lv) => 0.55 + 0.045 * lv;
