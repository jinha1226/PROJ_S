export function seeded(seed = 1) {
  let state = seed >>> 0;
  const rng = () => {
    state += 0x6d2b79f5;
    let t = Math.imul(state ^ state >>> 15, state | 1);
    t ^= t + Math.imul(t ^ t >>> 7, t | 61);
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
  rng.pick = list => list[Math.floor(rng() * list.length)];
  rng.int = (lo, hi) => lo + Math.floor(rng() * (hi - lo + 1));
  return rng;
}
