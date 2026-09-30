export const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
export const distance = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
export const cellKey = (x, y) => `${Math.floor(x)},${Math.floor(y)}`;
export const angleDiff = (a, b) => Math.atan2(Math.sin(a-b), Math.cos(a-b));
export function direction(a, b) {
  const d = distance(a, b) || 1;
  return { x: (b.x-a.x)/d, y: (b.y-a.y)/d };
}
export const weekSeed = date => Math.floor((date.getTime() - Date.UTC(2026, 0, 5)) / 604800000);
