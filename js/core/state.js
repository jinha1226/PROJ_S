import { T_DOOR, T_WALL } from '../data/terrain.js';

/* ================= 상태 ================= */
export const G = { W: 30, H: 30 };
/** 전투 방식: 격자(칸) / 원형 턴제(자유 위치). 브라우저에 기억한다 */
export const SETTINGS = { free: (() => { try { return localStorage.getItem('torch-mode') === 'free'; } catch (_) { return false; } })() };
export function setFreeSetting(v) { SETTINGS.free = !!v; try { localStorage.setItem('torch-mode', v ? 'free' : 'grid'); } catch (_) { /* 저장 못 함 */ } }

export const I = (x, y) => y * G.W + x;

export const XY = (i) => [i % G.W, (i / G.W) | 0];

export const inb = (x, y) => x >= 0 && y >= 0 && x < G.W && y < G.H;

export const newSt = () => ({ wet: 0, frozen: 0, burn: 0, poison: 0, stun: 0, fear: 0, haste: 0, immune: 0, bleed: 0, frac: 0, vital: 0 });

export const isFoe = (e) => e !== G.player && !e.ally;

export const isP = (e) => e === G.player;

export function entAt(x, y) { for (const e of G.ents) if (e.alive && e.x === x && e.y === y) return e; return null; }

export const tileAt = (x, y) => (inb(x, y) ? G.tile[I(x, y)] : T_WALL);

export const standable = (x, y) => { const t = tileAt(x, y); return t !== T_WALL && t !== T_DOOR; };

export const opaque = (i) => { const t = G.tile[i]; return t === T_WALL || t === T_DOOR || G.cloud[i] > 0; };

/* ================= 타임라인: 로직은 즉시, 연출은 순서대로 ================= */
export const TL = { cur: 0, q: [], reset() { this.cur = 0; this.q = []; }, add(fn, d = 0) { this.q.push({ t: this.cur + d, fn }); }, wait(ms) { this.cur += ms; } };

export function emit(type, data = {}, d = 0) { TL.add(() => listener(type, data), d); }

export function log(t, cls = '') { emit('log', { t, cls }); }

export const itemSnap = () => [...G.items.entries()];

export const Game = { mode: 'dungeon' };

/** core는 화면을 모른다: 사건은 main.js가 연결한 듣는 쪽(View.on)으로만 흘러간다. */
let listener = () => {};
export function setListener(fn) { listener = fn; }
