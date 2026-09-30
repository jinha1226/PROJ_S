import { T_DOOR, T_WALL } from '../data/terrain.js';

/* ================= 상태 ================= */
export const G = { W: 40, H: 40 }; // 층 크기(넓어진 던전)

export const I = (x, y) => y * G.W + x;

export const XY = (i) => [i % G.W, (i / G.W) | 0];

export const inb = (x, y) => x >= 0 && y >= 0 && x < G.W && y < G.H;

export const newSt = () => ({ wet: 0, frozen: 0, burn: 0, poison: 0, stun: 0, fear: 0, haste: 0, immune: 0, bleed: 0, frac: 0, vital: 0 });

export const isFoe = (e) => e !== G.player && !e.ally;

export const isP = (e) => e === G.player;
/** 보이는가: 시야 안이고 숨어 있지 않다(물속 거머리 등) */
export const seesEnt = (e) => isP(e) || (!!G.vis[I(e.x, e.y)] && !e.hidden);

export function entAt(x, y) { for (const e of G.ents) if (e.alive && e.x === x && e.y === y) return e; return null; }

/** 발밑 칸이 (x, y)인 존재 모두: 연속 좌표에서는 한 칸에 둘 이상 설 수 있다 */
export const entsAt = (x, y) => G.ents.filter((e) => e.alive && e.x === x && e.y === y);

export const tileAt = (x, y) => (inb(x, y) ? G.tile[I(x, y)] : T_WALL);

export const standable = (x, y) => { const t = tileAt(x, y); return t !== T_WALL && t !== T_DOOR; };

export const opaque = (i) => { const t = G.tile[i]; return t === T_WALL || t === T_DOOR || G.cloud[i] > 0; };

/* ================= 사건: 그 틱에 바로 화면으로 간다(로직은 연출을 기다리지 않는다) ================= */
export function emit(type, data = {}) { listener(type, data); }

export function log(t, cls = '') { emit('log', { t, cls }); }

export const itemSnap = () => [...G.items.entries()];

export const Game = { mode: 'dungeon' };

/** core는 화면을 모른다: 사건은 main.js가 연결한 듣는 쪽(View.on)으로만 흘러간다. */
let listener = () => {};
export function setListener(fn) { listener = fn; }
