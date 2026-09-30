import { CLOUD, SURF } from './codes.js';

/* ================= 상수 · 데이터 ================= */
export const T_WALL = 0, T_FLOOR = 1, T_DOOR = 2, T_OPEN = 3, T_STAIRS = 4;

export const S_NONE = SURF.NONE, S_WATER = SURF.WATER, S_GRASS = SURF.GRASS, S_OIL = SURF.OIL, S_ICE = SURF.ICE, S_ASH = SURF.ASH;

export const C_STEAM = CLOUD.STEAM, C_SMOKE = CLOUD.SMOKE;

export const FLOORS = [
  { name: '물이 스민 지하실', tip: '물이 발목까지 차오른 지하실.',
    pal: { floor: 0x5a6788, floor2: 0x4d5877, wall: 0x7788b0, wall2: 0x61709a, void: 0x04050a, grassFloor: 0x3f5a3a, waterFloor: 0x1b2d5e },
    surf: { water: 0.62, grass: 0.12 }, corr: [S_WATER, 0.1], mage: 'bolt',
    packs: [['goblin', 3, 'shaman'], ['rat', 5], ['mage', 1], ['leech', 2], ['goblin', 2], ['rat', 4]], items: 5 }, // 쥐 떼·거머리·주술사(docs/설계_던전_확장.md §4.2)
  { name: '이끼 덮인 납골당', tip: '이끼와 풀이 뒤덮은 오래된 납골당.',
    pal: { floor: 0x5b6552, floor2: 0x4e5847, wall: 0x78866c, wall2: 0x626f58, void: 0x040604, grassFloor: 0x416e33, waterFloor: 0x1c3048 },
    surf: { grass: 0.62, water: 0.2 }, corr: [S_GRASS, 0.2], mage: 'fire',
    packs: [['goblin', 3], ['archer', 1], ['goblin', 2], ['archer', 1], ['mage', 1], ['goblin', 3]], items: 5 },
  { name: '기름 저장고', tip: '바닥마다 기름이 번들거리는 저장고.',
    pal: { floor: 0x6b5b4d, floor2: 0x5d4f43, wall: 0x877462, wall2: 0x6f5f50, void: 0x060403, grassFloor: 0x4d5a2f, waterFloor: 0x20304a },
    surf: { oil: 0.5, water: 0.2, grass: 0.15 }, corr: [S_OIL, 0.1], mage: 'fire', poison: true,
    packs: [['charger', 1], ['goblin', 3], ['archer', 1], ['charger', 1], ['goblin', 2], ['goblin', 2]], items: 6 },
  { name: '얼어붙은 회랑', tip: '바닥이 얼음으로 뒤덮인 긴 회랑.',
    pal: { floor: 0x6f8199, floor2: 0x62738c, wall: 0x96abc8, wall2: 0x7e93b0, void: 0x04060b, grassFloor: 0x4a6048, waterFloor: 0x1f3d6e, memTint: 0x2a3a66 },
    surf: { ice: 0.55, water: 0.3 }, corr: [S_ICE, 0.25], mage: 'frost',
    packs: [['charger', 1], ['mage', 1], ['archer', 2], ['goblin', 3], ['charger', 1], ['goblin', 2]], items: 6 },
  { name: '심연의 문', tip: '얼어붙은 회랑의 끝. 계단 너머에서 무언가 기다린다.',
    pal: { floor: 0x5b4d72, floor2: 0x4e4264, wall: 0x7867a0, wall2: 0x615386, void: 0x05030a, grassFloor: 0x3f5a44, waterFloor: 0x251f5e, memTint: 0x33255a },
    surf: { water: 0.25, grass: 0.22, oil: 0.22, ice: 0.15 }, corr: [S_WATER, 0.08], mage: 'mix', poison: true,
    packs: [['goblin', 3], ['mage', 1], ['charger', 1], ['archer', 2], ['mage', 1], ['goblin', 3], ['charger', 1], ['goblin', 2]], items: 7 },
];

export const SURF_OF = { water: S_WATER, grass: S_GRASS, oil: S_OIL, ice: S_ICE };

/* ---------- 3차: 구역 · 보스 · 재료 ---------- */
/** 구역 하나 = 층 5개(1~4층 + 5층 보스) — docs/설계_던전_확장.md §6.3 */
export const ZONE_FLOORS = 5;

export const ZONES = [
  { name: '물이 스민 지하실', theme: 0, boss: 'chief' },
  { name: '이끼 덮인 납골당', theme: 1, boss: 'lich' },
  { name: '기름 저장고', theme: 2, boss: 'boarking' },
  { name: '얼어붙은 회랑', theme: 3, boss: 'abyss', lastTheme: 4 },
];
