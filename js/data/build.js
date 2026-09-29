/* ================= 정착지 건설 데이터 (docs/설계_정착지_건설.md 1단계) =================
   40×40 격자 · 지형 · 바닥 · 벽 · 가구 · 구역 · 방 종류 · 방 프리셋. 비용 단위: 나무·돌은 정착지 재고, 나머지는 던전 재료(META.mats) */
export const SW = 40, SH = 40, SCX = 20, SCY = 20;
/** 지을 수 있는 반경 = 6 + 모닥불 밝기 ÷ 10 (최대 20) */
export const lightRadius = (glow) => Math.min(20, 6 + Math.floor(Math.max(0, glow) / 10));
export const START_STOCK = { 나무: 40, 돌: 20 };
export const UNDO_MAX = 20;

/** 지형 */
export const TR = { dirt: 0, grass: 1, ruin: 2, water: 3, tree: 4, rock: 5, ore: 6 };
export const TERRAIN = [
  { id: 'dirt', name: '흙', build: true },
  { id: 'grass', name: '풀밭', build: true },
  { id: 'ruin', name: '폐허 돌바닥', build: true, cut: { 돌: 4 }, bonus: ['광석', 0.25], verb: '해체' },
  { id: 'water', name: '물', build: false, why: '물 위에는 지을 수 없다' },
  { id: 'tree', name: '나무', build: false, why: '나무를 먼저 베야 한다', cut: { 나무: 8 }, verb: '베기' },
  { id: 'rock', name: '바위', build: false, why: '바위를 먼저 캐야 한다', cut: { 돌: 6 }, verb: '캐기' },
  { id: 'ore', name: '광맥', build: false, why: '광맥을 먼저 캐야 한다', cut: { 광석: 2 }, verb: '캐기' },
];

/** 바닥 (0 = 없음) */
export const FLOOR_TYPES = {
  dirt: { id: 1, name: '다진 흙', cost: {}, t: 0.5 },
  wood: { id: 2, name: '나무 바닥', cost: { 나무: 1 }, t: 0.5 },
  stone: { id: 3, name: '돌 바닥', cost: { 돌: 1 }, t: 0.5 },
  carpet: { id: 4, name: '카펫', cost: { 가죽: 1 }, t: 0.5 },
};
/** 벽 · 문 (0 = 없음) */
export const WALLS = {
  wood: { id: 1, name: '나무 벽', cost: { 나무: 2 }, t: 1 },
  stone: { id: 2, name: '돌 벽', cost: { 돌: 2 }, t: 1 },
  door: { id: 3, name: '나무 문', cost: { 나무: 4 }, t: 2 },
};
export const FLOOR_BY_ID = Object.fromEntries(Object.entries(FLOOR_TYPES).map(([k, v]) => [v.id, k]));
export const WALL_BY_ID = Object.fromEntries(Object.entries(WALLS).map(([k, v]) => [v.id, k]));

/** 가구: w×h 칸(회전 전), unique = 하나뿐(지을 수 없음) */
export const FURN = {
  bed: { name: '침대', icon: '🛏', w: 1, h: 2, cost: { 나무: 6 }, t: 3 },
  table: { name: '탁자', icon: '🪵', w: 2, h: 1, cost: { 나무: 4 }, t: 2 },
  chair: { name: '의자', icon: '🪑', w: 1, h: 1, cost: { 나무: 2 }, t: 1 },
  shelf: { name: '저장 선반', icon: '🗄', w: 1, h: 1, cost: { 나무: 4 }, t: 2 },
  lamp: { name: '등불', icon: '🏮', w: 1, h: 1, cost: { 나무: 2, 기름: 1 }, t: 1 },
  hearth: { name: '화덕', icon: '♨', w: 1, h: 1, cost: { 돌: 6 }, t: 3 },
  anvil: { name: '모루', icon: '⚒', w: 1, h: 1, cost: { 돌: 4, 광석: 4 }, t: 4 },
  herbtable: { name: '약초대', icon: '🌿', w: 2, h: 1, cost: { 나무: 6, 약초: 2 }, t: 3 },
  leather: { name: '가죽대', icon: '🦌', w: 2, h: 1, cost: { 나무: 6, 가죽: 2 }, t: 3 },
  bookshelf: { name: '서가', icon: '📚', w: 2, h: 1, cost: { 나무: 8 }, t: 3 },
  decor: { name: '뼈 장식', icon: '🦴', w: 1, h: 1, cost: { 뼈: 1 }, t: 1 },
  altar: { name: '영혼석 제단', icon: '💎', w: 1, h: 1, cost: {}, t: 0, unique: true },
  gate: { name: '출발문', icon: '🚪', w: 1, h: 1, cost: {}, t: 0, unique: true },
  heap: { name: '재료 더미', icon: '📦', w: 1, h: 1, cost: {}, t: 0, unique: true },
};
/** 구역 (0 = 없음) */
export const ZONE_TYPES = {
  stock: { id: 1, name: '창고 구역', color: 0xc8a060 },
  field: { id: 2, name: '밭', color: 0x7a5a2a },
  rest: { id: 3, name: '쉼터', color: 0xe0b060 },
};
export const ZONE_BY_ID = Object.fromEntries(Object.entries(ZONE_TYPES).map(([k, v]) => [v.id, k]));

/** 방 종류: 안의 가구로 정해진다(위에 있는 것이 먼저). 제작 건물 id(forge·herb·hunter·library·inn)와 같다 */
export const ROOMS = {
  altar: { name: '제단', icon: '💎', need: { altar: 1 } },
  forge: { name: '대장간', icon: '🔨', need: { anvil: 1 } },
  herb: { name: '약초 공방', icon: '🌿', need: { herbtable: 1 } },
  hunter: { name: '사냥꾼 오두막', icon: '🏹', need: { leather: 1 } },
  library: { name: '서재', icon: '📜', need: { bookshelf: 1 } },
  inn: { name: '식당', icon: '🍲', need: { hearth: 1, table: 1 } },
  storage: { name: '창고', icon: '📦', need: { shelf: 1 } },
  bedroom: { name: '침실', icon: '🛏', need: { bed: 1 } },
};
export const ROOM_ORDER = Object.keys(ROOMS);
export const ROOM_MAX = 120; // 이보다 넓으면 방이 아니라 바깥

/** 방 프리셋: 크기(벽 포함 바깥 크기)마다 넣을 가구. 문은 모닥불 쪽 벽 가운데 */
export const PRESETS = {
  bedroom: { S: [4, 5, ['bed', 'lamp']], M: [5, 6, ['bed', 'bed', 'lamp']], L: [7, 6, ['bed', 'bed', 'bed', 'bed', 'lamp']] },
  forge: { S: [4, 4, ['anvil']], M: [5, 5, ['anvil', 'shelf', 'lamp']], L: [6, 5, ['anvil', 'shelf', 'shelf', 'lamp', 'decor']] },
  herb: { S: [4, 4, ['herbtable']], M: [5, 5, ['herbtable', 'shelf', 'lamp']], L: [6, 5, ['herbtable', 'shelf', 'lamp', 'chair']] },
  hunter: { S: [4, 4, ['leather']], M: [5, 5, ['leather', 'shelf', 'decor']], L: [6, 5, ['leather', 'shelf', 'decor', 'lamp']] },
  library: { S: [4, 4, ['bookshelf']], M: [5, 5, ['bookshelf', 'chair', 'lamp']], L: [6, 5, ['bookshelf', 'bookshelf', 'table', 'chair', 'lamp']] },
  inn: { S: [5, 4, ['hearth', 'table']], M: [6, 5, ['hearth', 'table', 'chair', 'chair']], L: [7, 6, ['hearth', 'table', 'table', 'chair', 'chair', 'chair', 'lamp']] },
  storage: { S: [4, 4, ['shelf', 'shelf']], M: [5, 5, ['shelf', 'shelf', 'shelf', 'shelf']], L: [6, 5, ['shelf', 'shelf', 'shelf', 'shelf', 'shelf', 'shelf']] },
  altar: { S: [4, 4, ['altar']] },
};
export const SIZE_NAME = { S: '작은', M: '보통', L: '큰' };

/** 재료 아이콘(나무·돌은 정착지 재고) */
export const RES_ICON = { 나무: '🪵', 돌: '🪨' };
