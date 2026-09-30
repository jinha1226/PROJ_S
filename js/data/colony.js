/* ================= 정착지 2단계: 시간 · 일 · 제작 · 전리품 (docs/설계_정착지_2단계.md) ================= */

/** 시간: 1배속 = 1초에 게임 10분. 원정 한 층 = 12시간(최대 3일을 돌린다) */
export const CLOCK = { minPerSec: 10, speeds: [0, 1, 3], floorHours: 12, maxAwayHours: 72, dayStart: 6, night: 22, meals: [7, 18] };
export const MONTHS = ['재의 달', '이끼의 달', '등잔의 달', '서리의 달'];
export const DAYS_PER_MONTH = 10;

/** 일 종류(일 배정 표의 열 순서) */
export const WORKS = {
  build: { name: '짓기', icon: '🔨' },
  haul: { name: '나르기', icon: '📦' },
  farm: { name: '농사', icon: '🌾' },
  cook: { name: '요리', icon: '🍲' },
  craft: { name: '제작', icon: '⚒' },
  gather: { name: '채집', icon: '🪓' },
};
export const WORK_IDS = Object.keys(WORKS);
/** 같은 우선순위면 이 순서로 */
export const WORK_ORDER = ['build', 'craft', 'cook', 'farm', 'haul', 'gather'];

/** 한 시간 일의 양 */
export const RATE = {
  build: 1, // 짓기 점수(= 건설 표의 시간)
  spec: 1.5, // 특기 배율
  cook: 2, cookSpec: 4, // 식량 1 → 식사(시간당)
  plant: 4, harvest: 4, // 밭 칸
  field: 2, // 밭 한 칸 수확 = 식량
  mood: { '-2': 0.75, '-1': 0.9, 0: 1, 1: 1, 2: 1.1 }, // 기분 → 일 배율
  cHigh: 1.1, cLow: 0.9, // 성실성
};
/** 채집: 땅 → 몇 시간 → 무엇 */
export const GATHER = { tree: { h: 2, m: '나무', n: 8 }, rock: { h: 2, m: '돌', n: 6 }, ore: { h: 3, m: '광석', n: 2 } };
/** 다시 자람(일): 모닥불 밝기 60 이상 · 30~59 · 30 미만 */
export const REGROW_DAYS = [6, 8, 10];
export const CROP_DAYS = [4, 6, 8];
/** 목표 재고 기본값(식량·식사는 주민 수로) */
export const TARGETS = { 나무: 40, 돌: 20, 광석: 6 };
export const mealTarget = (people) => people * 2; // 식사: 하루치
export const foodTarget = (people) => people * 10; // 식량: 닷새치
/** 새 땅에 보장하는 근처 자원(빛 반경 + 3칸 안) */
export const NEAR_RES = { tree: 20, rock: 10, ore: 3, pad: 3 };

/** 제작 시설: 방 종류 → 등급 가구(data/build.js FURN.tier) */
export const STATIONS = { forge: '대장간', herb: '연금실', library: '서재', inn: '식당' };

/**
 * 제작 목록. room · tier(필요 등급) · in(재료) · h(시간) · out:
 *   { gear: 기본템 | gearOf: 'weapon1'·'weapon2'·'armorL'… } · { item, n } · { enhance } · { quality } · { brand: 원소 } · { ego: 원소 } · { convert: { 재료: 양 } } · { meal: n } · { buff }
 */
export const CRAFT = [
  { id: 'wpn1', room: 'forge', tier: 1, name: '한손 무기', in: { 마석: 3, 광석: 1, 가죽: 1 }, h: 4, out: { pick: ['axe', 'sword', 'mace', 'rapier', 'spear', 'twin', 'flail', 'sling', 'boomerang'] } },
  { id: 'wpn2', room: 'forge', tier: 2, name: '양손 무기', in: { 마석: 5, 광석: 2, 뼈: 1 }, h: 6, out: { pick: ['greatsword', 'hammer', 'crossbow'] } },
  { id: 'arm1', room: 'forge', tier: 1, name: '천·가죽 방어구', in: { 마석: 2, 가죽: 2 }, h: 3, out: { pick: ['body_cloth', 'body_leather', 'head_cloth', 'head_leather', 'cloak', 'gloves', 'boots', 'buckler'] } },
  { id: 'arm2', room: 'forge', tier: 2, name: '사슬 갑옷·투구·방패', in: { 마석: 4, 광석: 3 }, h: 5, out: { pick: ['body_chain', 'head_chain', 'shield'] } },
  { id: 'arm3', room: 'forge', tier: 3, name: '판금 갑옷', in: { 마석: 6, 광석: 5 }, h: 8, out: { pick: ['body_plate'] } },
  { id: 'enh', room: 'forge', tier: 1, name: '강화 +1', in: { 마석: 2 }, h: 2, out: { enhance: true } },
  { id: 'qual', room: 'forge', tier: 2, name: '품질 올리기', in: { 마석: 4, 광석: 1 }, h: 4, out: { quality: true } },
  { id: 'brand', room: 'forge', tier: 2, name: '원소 새기기(무기)', in: { 마석: 3 }, crystal: 3, h: 4, out: { brand: true } },
  { id: 'ego', room: 'forge', tier: 2, name: '저항 새기기(방어구)', in: { 마석: 2, 가죽: 2 }, crystal: 2, h: 4, out: { ego: true } },
  { id: 'p_heal', room: 'herb', tier: 1, name: '회복 물약', in: { 약초: 2 }, h: 1, out: { item: 'heal', n: 1 } },
  { id: 'p_cure', room: 'herb', tier: 1, name: '해독 물약', in: { 약초: 1, 마석: 1 }, h: 1, out: { item: 'cure', n: 1 } },
  { id: 't_oil', room: 'herb', tier: 1, name: '기름병', in: { 마석: 1 }, h: 1, out: { item: 'oil', n: 2 } },
  { id: 't_water', room: 'herb', tier: 1, name: '물병', in: { 마석: 1 }, h: 1, out: { item: 'water', n: 2 } },
  { id: 't_smoke', room: 'herb', tier: 1, name: '연막탄', in: { 약초: 1, 뼈: 1 }, h: 1, out: { item: 'smoke', n: 1 } },
  { id: 'p_haste', room: 'herb', tier: 2, name: '가속 물약', in: { '얼음 결정': 1, 약초: 1 }, h: 2, out: { item: 'haste', n: 1 } },
  { id: 'ember', room: 'herb', tier: 1, name: '불씨 단지', in: { 마석: 1, 약초: 1 }, h: 1, out: { item: 'ember_jar', n: 1 } },
  { id: 'c_wood', room: 'herb', tier: 1, name: '환원: 나무', in: { 마석: 1 }, h: 1, out: { convert: { 나무: 6 } } },
  { id: 'c_stone', room: 'herb', tier: 1, name: '환원: 돌', in: { 마석: 1 }, h: 1, out: { convert: { 돌: 4 } } },
  { id: 'c_herb', room: 'herb', tier: 1, name: '환원: 약초', in: { 마석: 1 }, h: 1, out: { convert: { 약초: 2 } } },
  { id: 'c_ore', room: 'herb', tier: 1, name: '환원: 광석', in: { 마석: 2 }, h: 2, out: { convert: { 광석: 1 } } },
  { id: 's_ident', room: 'library', tier: 1, name: '식별 두루마리', in: { 마석: 1, 약초: 1 }, h: 1, out: { item: 'ident', n: 1 } },
  { id: 's_tele', room: 'library', tier: 2, name: '순간이동 두루마리', in: { 마석: 2, 뼈: 1 }, h: 2, out: { item: 'tele', n: 1 } },
  { id: 's_fear', room: 'library', tier: 2, name: '공포 두루마리', in: { 마석: 2, 뼈: 1 }, h: 2, out: { item: 'fear', n: 1 } },
  { id: 's_blaze', room: 'library', tier: 2, name: '불길 두루마리', in: { '불 결정': 1, 마석: 1 }, h: 2, out: { item: 'blaze', n: 1 } },
  { id: 's_recall', room: 'library', tier: 2, name: '귀환 두루마리', in: { 마석: 3, 심장: 1 }, h: 3, out: { item: 'recall', n: 1 } },
  { id: 'staff', room: 'library', tier: 2, name: '지팡이', in: { 마석: 4 }, crystal: 1, h: 5, out: { pick: ['staff'], brandFromCrystal: true } },
  { id: 'orb', room: 'library', tier: 2, name: '오브', in: { 마석: 4 }, crystal: 1, h: 4, out: { pick: ['orb_red', 'orb_purple', 'orb_green'] } },
  { id: 'jewel', room: 'library', tier: 3, name: '반지·목걸이', in: { 마석: 6, 심장: 1 }, h: 8, out: { pick: ['ring', 'ring', 'neck'] } },
  { id: 'meal', room: 'inn', tier: 1, name: '식사', in: { 식량: 1 }, h: 1, out: { meal: 2 } },
  { id: 'feast', room: 'inn', tier: 2, name: '잔치(다음 원정 보호막 +6)', in: { 식량: 4, 고기: 1 }, h: 3, out: { buff: 'feast' } },
];
export const CRAFT_BY_ID = Object.fromEntries(CRAFT.map((r) => [r.id, r]));
/** 원소 결정 → 브랜드·에고 */
export const CRYSTALS = { '불 결정': { brand: 'fire', ego: 'rFire' }, '얼음 결정': { brand: 'frost', ego: 'rFrost' }, '번개 결정': { brand: 'bolt', ego: 'rBolt' } };
/** 품질 확률 */
export const QUAL = { spec: 0.5, open: 0.15, sloppy: 0.15, moodUp: 0.1, moodDown: 0.15, max: 4 };

/* ---------- 던전 전리품 (§8.1) ---------- */
/** 적 종류 → 마석 · 특별 재료(확률) */
export const LOOT = {
  rat: { stone: [1, 0.5], mats: [['가죽', 0.4], ['고기', 0.3]] },
  leech: { stone: [1, 0.5], mats: [['가죽', 0.4], ['고기', 0.3]] },
  goblin: { stone: [1, 1], mats: [['가죽', 0.4], ['고기', 0.3]] },
  shaman: { stone: [1, 1], mats: [['가죽', 0.4], ['약초', 0.3]] },
  archer: { stone: [2, 1], mats: [['뼈', 0.5]] },
  mage: { stone: [2, 1], mats: [['뼈', 0.5], ['crystal', 0.5]] },
  charger: { stone: [3, 1], mats: [['가죽', 0.6], ['고기', 0.5]] },
  boss: { stone: [10, 1], mats: [['심장', 1], ['crystal', 1], ['crystal', 1]] },
};
export const ELEM_CRYSTAL = { fire: '불 결정', frost: '얼음 결정', bolt: '번개 결정' };
/** 장비 드롭: 층마다 기대 개수 · 속성 장비 비율 */
export const GEAR_DROP = { perFloor: 0.3, special: 0.6, bossSpecial: true };
/** 층 바닥 재료: 약초 · 마석 조각 */
export const FLOOR_MATS = { 약초: [1, 2], 마석: [2, 3] };
