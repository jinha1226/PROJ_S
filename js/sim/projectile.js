import { posOf, rad, solid } from '../core/space.js';
import { G } from '../core/state.js';

/* ================= 투사체: 틱마다 나는 실체. 벽에 막히고, 꿰뚫고, 되돌아온다 (docs/설계_전투_코어.md §2) =================
   G.projs = [{ owner, team, x, y, ang, speed, left, range, pierce, back, hit, onHit(target, proj) }]. 멈춘 동안에는 그 자리에 떠 있다 */

export function spawnProj(p) {
  const pr = { hit: new Set(), returning: false, left: p.range, ...p };
  (G.projs ||= []).push(pr); // 화면은 G.projs를 매 프레임 그린다(render/fx.js syncProjs)
  return pr;
}

function turnBack(pr) {
  pr.returning = true; pr.ang += Math.PI; pr.left = pr.range - pr.left; pr.hit = new Set();
}

/** 한 틱: 조금씩 나아가며 벽·몸에 닿는지 본다 */
export function tickProjs(dt) {
  if (!G.projs || !G.projs.length) return;
  for (const pr of G.projs) {
    pr.ox = pr.x; pr.oy = pr.y; // 화면이 틱 사이를 보간할 이전 자리
    let go = pr.speed * dt;
    while (go > 1e-6 && !pr.dead) {
      const d = Math.min(0.2, go, pr.left); go -= d; pr.left -= d;
      if (pr.returning) { const own = G.ents.find((e) => e.id === pr.owner); if (own) { const [ox, oy] = posOf(own); pr.ang = Math.atan2(oy - pr.y, ox - pr.x); if (Math.hypot(ox - pr.x, oy - pr.y) < 0.4) { pr.dead = true; break; } } }
      pr.x += Math.cos(pr.ang) * d; pr.y += Math.sin(pr.ang) * d;
      if (solid(Math.round(pr.x), Math.round(pr.y))) { if (pr.back && !pr.returning) turnBack(pr); else pr.dead = true; break; }
      for (const e of G.ents) {
        if (!e.alive || e.team === pr.team || e.npc || e.hidden || pr.hit.has(e.id) || e.px == null) continue;
        if (Math.hypot(e.px - pr.x, e.py - pr.y) > rad(e) + 0.12) continue;
        pr.hit.add(e.id); pr.onHit(e, pr);
        if (!pr.pierce) { pr.dead = true; break; }
      }
      if (pr.left <= 1e-6 && !pr.dead) { if (pr.back && !pr.returning) turnBack(pr); else pr.dead = true; }
    }
  }
  G.projs = G.projs.filter((p) => !p.dead);
}
