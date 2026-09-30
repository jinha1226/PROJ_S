/* ================= 난수 · 도움 함수 ================= */
export function mulberry32(a) { return function () { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }

export let R = mulberry32(1);

export const rand = () => R();

export const ri = (a, b) => a + Math.floor(rand() * (b - a + 1));

export const pick = (a) => a[Math.floor(rand() * a.length)];

export function shuffle(a) { for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(rand() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; }

export function wpick(list) { let s = 0; for (const [, w] of list) s += w; let r = rand() * s; for (const [k, w] of list) { r -= w; if (r < 0) return k; } return list[0][0]; }

/** 주소에 ?seed=123 이 있으면 판마다 그 씨앗을 쓴다(비교·재현용). 없으면 지금처럼 시각으로. */
export const URL_SEED = (() => { try { const v = new URLSearchParams(location.search).get('seed'); return v == null ? null : (Number(v) >>> 0); } catch (_) { return null; } })();
export const seedOr = (s) => (URL_SEED ?? s);
export function setR(r) { R = r; }
