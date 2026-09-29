/* ================= 땅 · 방문자 · 모닥불 밝기 · 등불지기 잇기 ================= */

/** 정착지 바깥의 땅. 그 구역의 등불 조각을 넣으면 밝아지고, 그 땅 출신 방문자가 온다 */
export const LANDS = [
  { id: 'lake', name: '물안개 호숫가', zone: 1, jobs: ['fisher', 'boatman', 'cook'], dir: [0, -1] },
  { id: 'forest', name: '이끼 숲', zone: 2, jobs: ['herbalist', 'gravekeeper', 'scholar'], dir: [-1, 0] },
  { id: 'mine', name: '폐광 언덕', zone: 3, jobs: ['miner', 'blacksmith'], dir: [1, 0] },
  { id: 'pass', name: '서리 고개', zone: 4, jobs: ['hunter', 'pilgrim'], dir: [0, 1] },
];

/** 아직 어느 땅도 밝지 않을 때 떠도는 사람들 */
export const WANDER_JOBS = ['herbalist', 'hunter', 'scholar', 'cook'];

/** 모닥불 밝기(0~100) 수치 */
export const GLOW = {
  base: 2, perNpc: 6, badMood: -4, goodPair: 2, badPair: -2, shard: 10, event: 5, death: -5,
  visitBase: 20, visitPer: 0.6, low: 20, vision: 60, shield: 80, maxVisitors: 2,
};

/** 주민 상한: 4 + 조각 × 2 (최대 12) */
export const residentCap = (shards) => Math.min(12, 4 + shards * 2);

/** 등불지기가 된 주민의 시작 특성(가장 두드러진 성격 하나) */
export const PERKS = {
  'H+': { name: '책임감', desc: '영혼석 가방 +1' },
  'H-': { name: '눈치', desc: '원정 첫 층에서 상자 하나 더' },
  'E+': { name: '조심성', desc: '회복 물약 +1, 최대 HP −2' },
  'E-': { name: '두려움 없음', desc: '첫 보스를 잡을 때까지 최대 HP +4' },
  'X+': { name: '넉살', desc: '길 잃은 사람을 만날 확률 ↑' },
  'A+': { name: '다정함', desc: '영혼 소환수 지속 +1턴' },
  'C+': { name: '꼼꼼함', desc: '소모품을 하나 더 챙긴다' },
  'O+': { name: '호기심', desc: '미확인 소모품 하나를 처음부터 안다' },
};

/** 성실한 방문자가 가져오는 자기 일터 재료 */
export const WORK_GIFT = { forge: { 광석: 2 }, herb: { 약초: 2 }, hunter: { 가죽: 2 }, library: { 뼈: 2 }, inn: { 약초: 1, 가죽: 1 }, altar: { 뼈: 1, 심장: 1 }, storage: { 가죽: 1, 광석: 1 } };

/** 숨은 방: 막힌 것 → 여는 스킬 → 안에 든 것 */
export const HIDDEN = {
  thorn: { name: '가시덤불 벽', skill: 'fire', hint: '불씨로 태울 수 있을 것 같다', inside: '상자 · 재료' },
  water: { name: '물로 막힌 통로', skill: 'frost', hint: '깊은 물 — 얼리면 건널 수 있다', inside: '영혼석' },
  gate: { name: '멈춘 승강문', skill: 'bolt', hint: '녹슨 톱니 — 번개가 닿으면 움직일지도', inside: '장비 상자' },
  rubble: { name: '무너진 돌무더기', skill: 'push', hint: '밀치면 무너질 것 같다', inside: '마석' },
};
export const HIDDEN_BY_SKILL = Object.fromEntries(Object.entries(HIDDEN).map(([k, v]) => [v.skill, k]));
