import { LAMP_REFILL, OLD_KEEPERS, TORCH_BONUS, TORCH_BURN, TORCH_MAX } from '../data/torch.js';
import { G, I, log } from './state.js';
import { META, saveMeta } from './meta.js';
import { hearthGlow } from './visitors.js';
import { T_FLOOR } from '../data/terrain.js';
import { rand } from '../util/rng.js';

export function startTorch() {
  G.torchMax = TORCH_MAX + (hearthGlow() >= 60 ? TORCH_BONUS : 0);
  G.torch = G.torchMax;
  if (META?.hero) META.hero.torch = G.torch;
}
export function burnTorch() {
  const before = G.torch || 0;
  const ps = G.ps, rate = TORCH_BURN * (1 - (ps ? ps.torchSlow : 0) / 100) * (1 + (ps ? ps.torchCost : 0) / 100); // 불씨 품기·기억 목걸이 / 유물의 대가
  G.torch = Math.max(0, Math.round((before - rate) * 100) / 100);
  if (META?.hero) META.hero.torch = G.torch;
  if (before >= 50 && G.torch < 50) log('횃불이 약해져 시야가 좁아진다', 'bad');
  if (before >= 25 && G.torch < 25) log('불씨가 희미하다 — 어둠이 다가온다', 'bad');
  if (before > 0 && G.torch === 0) { G.darkAmbushUsed = false; log('횃불이 꺼졌다! 적이 먼저 알아챈다', 'bad'); }
}
export function refillTorch(amount) {
  const before = G.torch || 0;
  G.torch = Math.min(G.torchMax || TORCH_MAX, before + amount);
  if (META?.hero) META.hero.torch = G.torch;
  return G.torch - before;
}
export function placeLamps() {
  G.lamps = new Map();
  const free = [];
  for (let i = 0; i < G.tile.length; i++) {
    if (G.tile[i] !== T_FLOOR || G.room[i] <= 0 || G.items.has(i) || G.mats.has(i) || G.gear.has(i) || G.chests.has(i) || G.stones.has(i)) continue;
    const x = i % G.W, y = (i / G.W) | 0;
    if (G.ents.some((e) => e.alive && e.x === x && e.y === y) || Math.max(Math.abs(x - G.player.x), Math.abs(y - G.player.y)) < 5) continue;
    free.push(i);
  }
  for (let n = Math.min(free.length, 1 + Math.floor(rand() * 2)); n > 0; n--) {
    const i = free.splice(Math.floor(rand() * free.length), 1)[0];
    G.lamps.set(i, OLD_KEEPERS[Math.floor(rand() * OLD_KEEPERS.length)]);
  }
}
export function useLamp() {
  const i = I(G.player.x, G.player.y), name = G.lamps?.get(i);
  if (!name) return false;
  G.lamps.delete(i);
  const gained = refillTorch(LAMP_REFILL + (G.ps ? G.ps.lampBonus : 0));
  META.rememberedKeepers ||= [];
  const first = !META.rememberedKeepers.includes(name);
  if (first) META.rememberedKeepers.push(name);
  saveMeta();
  log(`${name}의 등잔 — 아직 따뜻하다. 횃불 +${gained}${first ? ' · 기억할 이름이 늘었다' : ''}`, 'good');
  return true;
}
