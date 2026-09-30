import { B } from '../data/balance.js';
import { ENEMIES } from '../data/enemies.js';
import { WEAPONS } from '../data/weapons.js';
export function createUnit(id, options = {}) {
  const def = ENEMIES[options.kind];
  const kind = options.kind || 'hero';
  const hp = options.maxHP || (def ? B.enemyHP[kind] : B.heroHP);
  return { id, kind, name: options.name || def?.name || 'hero',
    team: def ? 'foe' : 'party', ctrl: def ? 'ai' : 'player',
    x: 2.5, y: 2.5, prevX: 2.5, prevY: 2.5, facing: 0, radius: B.radius,
    hp, maxHP: hp, speed: def ? B.enemySpeed[kind] : B.heroSpeed,
    damage: def ? B.enemyDamage[kind] : B.attack, armor: 0, evade: 0,
    weapon: def?.weapon || 'sword', resist: { ...def?.resist },
    statuses: {}, cooldowns: {}, brain: def?.brain || 'ally', threat: {},
    gear: {}, inventory: [], role: null, stance: 'careful', alive: true,
    target: null, windup: null, slide: { x: 0, y: 0 }, xp: 0, level: 1, ...options };
}
export const weaponOf = unit => WEAPONS[unit.weapon];
