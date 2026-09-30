import { distance, cellKey, direction } from '../util/math.js';
export function tileAt(world, x, y) { return world.tiles[cellKey(x, y)]; }
export function blocked(world, x, y) {
  const t = tileAt(world, x, y);
  return !t || t.kind === 'wall' || (t.kind === 'door' && !t.open);
}
export function canStand(world, unit, x, y) {
  const r = unit.radius;
  if ([[x-r,y-r],[x+r,y-r],[x-r,y+r],[x+r,y+r]].some(p => blocked(world,...p))) return false;
  return !world.units.some(u => u.id !== unit.id && u.alive && Math.hypot(x-u.x,y-u.y) < r+u.radius);
}
export function move(world, unit, dx, dy) {
  const old = { x: unit.x, y: unit.y };
  if (canStand(world, unit, unit.x+dx, unit.y)) unit.x += dx;
  if (canStand(world, unit, unit.x, unit.y+dy)) unit.y += dy;
  if (dx || dy) unit.facing = Math.atan2(dy, dx);
  return distance(old, unit);
}
export function visible(world, a, b) {
  const n = Math.ceil(distance(a,b)*5);
  for (let i=1; i<n; i++) {
    const t = tileAt(world, a.x+(b.x-a.x)*i/n, a.y+(b.y-a.y)*i/n);
    if (!t || t.kind === 'wall' || (t.kind === 'door' && !t.open) || t.kind === 'smoke') return false;
  }
  return true;
}
export function path(world, start, end) {
  const source = cellKey(start.x,start.y), goal = cellKey(end.x,end.y);
  const queue = [source], parents = new Map([[source,null]]);
  for (let i=0;i<queue.length;i++) {
    const key = queue[i];
    if (key === goal) {
      const result=[]; let k=key;
      while (parents.get(k)) { const [x,y]=k.split(',').map(Number); result.unshift({x:x+0.5,y:y+0.5}); k=parents.get(k); }
      return result;
    }
    const [x,y] = key.split(',').map(Number);
    for (const [dx,dy] of [[1,0],[-1,0],[0,1],[0,-1]]) {
      const next=cellKey(x+dx,y+dy);
      if (!parents.has(next) && !blocked(world,x+dx+0.5,y+dy+0.5)) { parents.set(next,key); queue.push(next); }
    }
  }
  return [];
}
export function walkToward(world, u, point, dt, backwards = false) {
  let target = point;
  if (!visible(world,u,point)) target = path(world,u,point)[0] || point;
  const dir = direction(u,target);
  const haste = u.statuses.haste ? 1.5 : 1;
  return move(world,u,dir.x*u.speed*dt*haste*(backwards?-1:1),dir.y*u.speed*dt*haste*(backwards?-1:1));
}
export function shapeContains(t, p) {
  const d=distance(t,p), angle=Math.atan2(p.y-t.y,p.x-t.x);
  if (t.shape === 'line') {
    const dx=p.x-t.x, dy=p.y-t.y;
    const along=dx*Math.cos(t.angle)+dy*Math.sin(t.angle);
    const across=Math.abs(-dx*Math.sin(t.angle)+dy*Math.cos(t.angle));
    return along >= -p.radius && along <= t.reach+p.radius && across <= t.width+p.radius;
  }
  if (t.shape === 'fan') return d<=t.reach+p.radius && Math.abs(Math.atan2(Math.sin(angle-t.angle),Math.cos(angle-t.angle)))<=t.arc/2;
  return d <= t.radius+p.radius;
}
