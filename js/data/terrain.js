import { CLOUD, SURF } from './codes.js';

/* ================= 상수 · 데이터 ================= */
export const T_WALL = 0, T_FLOOR = 1, T_DOOR = 2, T_OPEN = 3, T_STAIRS = 4;

export const S_NONE = SURF.NONE, S_WATER = SURF.WATER, S_GRASS = SURF.GRASS, S_OIL = SURF.OIL, S_ICE = SURF.ICE, S_ASH = SURF.ASH;

export const C_STEAM = CLOUD.STEAM, C_SMOKE = CLOUD.SMOKE;

export const FLOORS = [
  { name: '물이 스민 지하실', tip: '물에 선 적에게 ⚡번개 — 이어진 물 전체가 감전된다. 좁은 복도로 무리를 한 줄로 세워라.',
    pal: { floor: 0x5a6788, floor2: 0x4d5877, wall: 0x7788b0, wall2: 0x61709a, void: 0x04050a, grassFloor: 0x3f5a3a, waterFloor: 0x1b2d5e },
    surf: { water: 0.62, grass: 0.12 }, corr: [S_WATER, 0.1], mage: 'bolt',
    packs: [['goblin', 3], ['goblin', 2], ['mage', 1], ['goblin', 3], ['goblin', 2]], items: 5 },
  { name: '이끼 덮인 납골당', tip: '풀밭은 불이 번진다 — 적도, 나도. 궁수의 붉은 점선이 보이면 벽·문 뒤로 숨어 시야를 끊어라.',
    pal: { floor: 0x5b6552, floor2: 0x4e5847, wall: 0x78866c, wall2: 0x626f58, void: 0x040604, grassFloor: 0x416e33, waterFloor: 0x1c3048 },
    surf: { grass: 0.62, water: 0.2 }, corr: [S_GRASS, 0.2], mage: 'fire',
    packs: [['goblin', 3], ['archer', 1], ['goblin', 2], ['archer', 1], ['mage', 1], ['goblin', 3]], items: 5 },
  { name: '기름 저장고', tip: '멧돼지의 화살표 경로에서 비켜서면 벽에 머리를 박고 기절한다. 기름은 불씨 하나로 연쇄 폭발.',
    pal: { floor: 0x6b5b4d, floor2: 0x5d4f43, wall: 0x877462, wall2: 0x6f5f50, void: 0x060403, grassFloor: 0x4d5a2f, waterFloor: 0x20304a },
    surf: { oil: 0.5, water: 0.2, grass: 0.15 }, corr: [S_OIL, 0.1], mage: 'fire', poison: true,
    packs: [['charger', 1], ['goblin', 3], ['archer', 1], ['charger', 1], ['goblin', 2], ['goblin', 2]], items: 6 },
  { name: '얼어붙은 회랑', tip: '얼음 위에서는 미끄러진다 — 밀치면 끝까지. 젖은 채로 얼면 오래 간다. 불은 얼음을 녹여 증기를 만든다.',
    pal: { floor: 0x6f8199, floor2: 0x62738c, wall: 0x96abc8, wall2: 0x7e93b0, void: 0x04060b, grassFloor: 0x4a6048, waterFloor: 0x1f3d6e, memTint: 0x2a3a66 },
    surf: { ice: 0.55, water: 0.3 }, corr: [S_ICE, 0.25], mage: 'frost',
    packs: [['charger', 1], ['mage', 1], ['archer', 2], ['goblin', 3], ['charger', 1], ['goblin', 2]], items: 6 },
  { name: '심연의 문', tip: '모든 것이 섞인다. 아껴 둔 것을 쓸 때다. 이 층의 계단을 내려가면 탈출.',
    pal: { floor: 0x5b4d72, floor2: 0x4e4264, wall: 0x7867a0, wall2: 0x615386, void: 0x05030a, grassFloor: 0x3f5a44, waterFloor: 0x251f5e, memTint: 0x33255a },
    surf: { water: 0.25, grass: 0.22, oil: 0.22, ice: 0.15 }, corr: [S_WATER, 0.08], mage: 'mix', poison: true,
    packs: [['goblin', 3], ['mage', 1], ['charger', 1], ['archer', 2], ['mage', 1], ['goblin', 3], ['charger', 1], ['goblin', 2]], items: 7 },
];

export const SURF_OF = { water: S_WATER, grass: S_GRASS, oil: S_OIL, ice: S_ICE };

/* ---------- 3차: 구역 · 보스 · 재료 ---------- */
export const ZONES = [
  { name: '물이 스민 지하실', theme: 0, boss: 'chief' },
  { name: '이끼 덮인 납골당', theme: 1, boss: 'lich' },
  { name: '기름 저장고', theme: 2, boss: 'boarking' },
  { name: '얼어붙은 회랑', theme: 3, boss: 'abyss', lastTheme: 4 },
];
