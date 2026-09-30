/** 생활 직업 다섯 (docs/설계_정착지_2단계.md §2). b = 일하는 방(목수는 어디서나), spec = 특기 일 */
export const JOBS = {
  blacksmith: { name: '대장장이', icon: '🔨', b: 'forge', work: 'hammer', spec: ['craft'] },
  alchemist: { name: '연금술사', icon: '⚗', b: 'herb', work: 'farm', spec: ['craft'] },
  scholar: { name: '학자', icon: '📜', b: 'library', work: 'read', spec: ['craft'] },
  cook: { name: '요리사', icon: '🍲', b: 'inn', work: 'stir', spec: ['cook', 'farm'] },
  carpenter: { name: '목수', icon: '🪚', b: null, work: 'carve', spec: ['build'] },
};
export const JOB_IDS = Object.keys(JOBS);
/** 출신(옛 직업): 모습과 사연 한 줄. 새 주민은 직업마다 이 중 하나로 온다 */
export const ORIGINS = {
  blacksmith: { name: '대장장이', job: 'blacksmith' }, miner: { name: '광부', job: 'blacksmith' },
  herbalist: { name: '약초꾼', job: 'alchemist' },
  scholar: { name: '학자', job: 'scholar' }, keeper: { name: '제단지기', job: 'scholar' }, gravekeeper: { name: '묘지기', job: 'scholar' }, pilgrim: { name: '순례자', job: 'scholar' },
  cook: { name: '요리사', job: 'cook' }, fisher: { name: '어부', job: 'cook' }, hunter: { name: '사냥꾼', job: 'cook' },
  boatman: { name: '뱃사공', job: 'carpenter' },
};
/** 일하는 방 이름(없으면 '어디서나') */
export const jobPlace = (job) => (JOBS[job] && JOBS[job].b ? JOBS[job].b : null);

export const TRAITS = [['H', '정직·겸손'], ['E', '감정성'], ['X', '외향성'], ['A', '원만성'], ['C', '성실성'], ['O', '개방성']];

/** [낮음, 보통(0), 높음] — 0은 부정형이 아니라 보통 */
export const ADJ = { H: ['욕심 많은', '무던한', '정직한'], E: ['담담한', '차분한', '걱정 많은'], X: ['과묵한', '서글서글한', '수다스러운'], A: ['까칠한', '무난한', '너그러운'], C: ['게으른', '제 몫은 하는', '성실한'], O: ['고지식한', '평범한', '호기심 많은'] };

export const adj = (n, k) => ADJ[k][Math.sign(n.t[k]) + 1];

export const NAMES = ['도윤', '서연', '하준', '지우', '민서', '예준', '수아', '시우', '하린', '지호', '유나', '건우', '채원', '이안', '소율', '태오', '나은', '로운', '다온', '미르', '보람', '한결'];

export const HERO_NAMES = ['아린', '로하', '세온', '미카', '단비', '해솔', '가람', '이든', '라온', '새봄'];

export const SKINS = [0xffd7b0, 0xf1c29a, 0xd9a47a, 0xb87a52];

export const HAIRS = [0x3a2618, 0x6a4020, 0xc89a4a, 0x2a2a30, 0xe0e0e0, 0xb04a2a];

export const JOB_CLOTH = { alchemist: 0x6aa04a, carpenter: 0x9a6a3a, keeper: 0x8a7ab0, blacksmith: 0x6a5a4a, herbalist: 0x6aa04a, hunter: 0x8a6a3a, scholar: 0x5a4aa0, cook: 0xe0d8c8, fisher: 0x4a7ab0, boatman: 0x3a6a8a, gravekeeper: 0x5a5a6a, miner: 0x9a7a4a, pilgrim: 0xc8b890 };

export const MOODS = ['😠', '😟', '🙂', '😊', '😄'];

export const BLD = {
  gate: { name: '출발문', icon: '🚪', x: 5, y: 1.3 },
  altar: { name: '영혼석 제단', icon: '💎', x: 2.2, y: 3.6 },
  storage: { name: '창고', icon: '📦', x: 7.9, y: 4.0 },
  plaza: { name: '모닥불', icon: '🔥', x: 5, y: 7 },
  forge: { name: '대장간', icon: '🔨', x: 2.2, y: 9.6 },
  herb: { name: '약초 공방', icon: '🌿', x: 7.9, y: 9.6 },
  hunter: { name: '사냥꾼 오두막', icon: '🏹', x: 2.2, y: 12.4 },
  inn: { name: '모닥불 식당', icon: '🍲', x: 5.2, y: 12.8 },
  library: { name: '서재', icon: '📜', x: 7.9, y: 12.4 },
};

export const CRAFT_B = ['forge', 'herb', 'library', 'inn'];

export const TW = 11, TH = 15;

export const TOWN_PAL = { floor: 0xdcc28e, floor2: 0xd2b682, wall: 0x4f9a45, wall2: 0x62ae52, void: 0x3f6a36, grassFloor: 0x7cc45a, waterFloor: 0x2a6ab0, dim: 1 };
