// 63c33bf2의 js/core/space.js에서 원형 충돌·연속 좌표 아이디어를 실험실 전용으로 옮겼다.
export const distance = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
export const walls = new Set(['5,5', '10,5', '5,10', '10,10']);
export const solid = (x, y) => x < 1 || y < 1 || x > 14 || y > 14 || walls.has(`${Math.round(x)},${Math.round(y)}`);

// 작은 단계로 훑어서 벽과 몸을 통과하지 않는다. C 모드에서만 사용한다.
export function sweep(unit, dx, dy, units) {
  let { x, y } = unit;
  const n = Math.max(1, Math.ceil(Math.hypot(dx, dy) / 0.12));
  for (let k = 0; k < n; k++) {
    const nx = clamp(x + dx / n, 1.25, 13.75), ny = clamp(y + dy / n, 1.25, 13.75);
    if (!blocked(nx, y, unit, units)) x = nx;
    if (!blocked(x, ny, unit, units)) y = ny;
  }
  return { x, y };
}
function blocked(x, y, unit, units) {
  for (const ox of [-0.27, 0.27]) for (const oy of [-0.27, 0.27]) if (solid(x + ox, y + oy)) return true;
  return units.some((other) => other !== unit && other.hp > 0 && distance({ x, y }, other) < (other.boss ? 0.78 : 0.54));
}

export function labStepToward(unit, target, units, continuous, away = false) {
  const d = distance(unit, target) || 1;
  const s = continuous ? 0.42 : 1;
  const sign = away ? -1 : 1;
  const vx = (target.x - unit.x) / d * s * sign, vy = (target.y - unit.y) / d * s * sign;
  if (continuous) Object.assign(unit, sweep(unit, vx, vy, units));
  else {
    const choices = [[Math.sign(vx), 0], [0, Math.sign(vy)], [Math.sign(vx), Math.sign(vy)]]
      .map(([dx, dy]) => ({ x: unit.x + dx, y: unit.y + dy }))
      .filter((p) => !solid(p.x, p.y) && !units.some((u) => u !== unit && u.hp > 0 && distance(u, p) < 0.8));
    choices.sort((a, b) => (away ? -1 : 1) * (distance(a, target) - distance(b, target)));
    if (choices[0]) Object.assign(unit, choices[0]);
  }
}
