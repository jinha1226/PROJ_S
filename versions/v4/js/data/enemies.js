export const ENEMY = {
  goblin: { name: '고블린', hp: 6, atk: 2, danger: '무리로 에워싼다.', desc: '몰려와서 에워싸는 약한 무리.', tip: '좁은 복도나 문간에 서면 한 번에 한 마리씩만 붙는다.' },
  mage: { name: '마법사', hp: 9, atk: 2, danger: '표식이 뜬 칸에 주문이 떨어진다.', desc: '바닥에 표식을 남기고, 다음 턴에 그 자리에 주문을 떨어뜨린다.', tip: '표식 밖으로 비켜서면 주문은 빗나가고, 얼리거나 기절시키면 아예 끊긴다.' },
  charger: { name: '철갑 멧돼지', hp: 16, atk: 4, danger: '돌진 피해 8.', desc: '일직선에 서면 돌진 경로를 예고하고, 다음 턴에 끝까지 달려온다.', tip: '경로에서 비켜서면 벽에 머리를 박고 피해 5를 입은 채 기절한다.' },
  archer: { name: '해골 궁수', hp: 7, atk: 4, danger: '멀리서 쏜다.', desc: '거리를 두고 조준한 뒤 다음 턴에 쏘고, 붙으면 도망간다.', tip: '벽이나 문, 연기로 시야를 끊으면 쏘지 못한다.' },
  // 1구역에 새로 (docs/설계_던전_확장.md §4.2) — speed: fast(한 턴 두 번 움직임, 공격은 한 번) · slow(두 턴에 한 번)
  rat: { name: '굶주린 쥐', hp: 2, atk: 1, speed: 'fast', desc: '떼로 몰려와 한 턴에 두 칸씩 달린다.', tip: '복도로 물러나면 한 줄로 받아낼 수 있다.', danger: '떼로 에워싼다.' },
  leech: { name: '거머리', hp: 5, atk: 2, speed: 'slow', desc: '물속에 숨어 있다가 붙으면 피를 빨아 출혈 2를 남긴다.', tip: '물에 번개를 치면 숨은 거머리까지 감전된다.', danger: '물속에서는 보이지 않는다.' },
  shaman: { name: '고블린 주술사', hp: 7, atk: 1, desc: '두 턴마다 다친 동료의 HP를 4 채우고, 붙으면 물러난다.', tip: '주술사부터 쓰러뜨리면 싸움이 짧아진다.', danger: '동료를 치유한다.' },

};

export const MAGE = { bolt: { name: '번개 마법사', icon: '⚡', color: 0xffe14a, robe: 0x3a4aa0 }, fire: { name: '화염 마법사', icon: '🔥', color: 0xff6a1a, robe: 0x9a2f3a }, frost: { name: '냉기 마법사', icon: '❄', color: 0x8fdcff, robe: 0x2f6a9a } };

export const CATS = { beast: { name: '짐승', weak: 'slash' }, armor: { name: '갑옷', weak: 'pierce' }, bone: { name: '해골', weak: 'blunt', noBleed: true } };

export const DROPS = {
  goblin: { red: 'r_bleed', purple: 'p_summon', green: 'g_counter' },
  goblin_armor: { red: 'r_extra', purple: 'p_shield', green: 'g_shield' },
  goblin_poison: { red: 'r_poison', purple: 'p_poison', green: 'g_poison' },
  charger: { red: 'r_push', purple: 'p_push', green: 'g_push' },
  archer: { red: 'r_arrow', purple: 'p_heal', green: 'g_heal' },
  mage_bolt: { red: 'r_shock', purple: 'p_shock', green: 'g_shock' },
  mage_fire: { red: 'r_fire', purple: 'p_fire', green: 'g_fire' },
  mage_frost: { red: 'r_freeze', purple: 'p_wet', green: 'g_freeze' },
  rat: { red: 'r_bleed', purple: 'p_poison', green: 'g_poison' },
  leech: { red: 'r_bleed', purple: 'p_heal', green: 'g_heal' },
  shaman: { red: 'r_poison', purple: 'p_heal', green: 'g_shield' },
};

export const BOSSES = {
  chief: { type: 'goblin', name: '고블린 족장', hp: 38, atk: 5, scale: 1.6, desc: '뿔나팔을 들면 다음 턴에 고블린 둘을 부른다.', tip: '부하들을 물가로 끌어들이면 번개 한 번에 쓸어 낼 수 있다.' },
  lich: { type: 'mage', name: '해골 대마법사', hp: 34, atk: 3, scale: 1.4, elem: 'bolt', desc: '원소를 바꿔 가며 넓은 주문을 쓰고, 붙으면 순간이동으로 달아난다.', tip: '해골이라 타격에 약하다.' },
  boarking: { type: 'charger', name: '강철 멧돼지 왕', hp: 48, atk: 6, scale: 1.4, desc: '쉴 틈 없이 돌진을 노리고, 돌진 피해는 11이다.', tip: '벽을 등지고 섰다가 비켜서면 3턴 동안 기절하고, 갑옷에는 찌르기가 잘 든다.' },
  abyss: { type: 'mage', name: '심연의 파수꾼', hp: 58, atk: 4, scale: 1.65, elem: 'fire', desc: '원소를 바꿔 가며 넓은 주문을 쓰고, 때때로 해골 궁수를 부른다.', tip: '불은 잘 듣지 않고, 냉기가 잘 든다.' },
};

export const kindOf = (e) => (e.type === 'goblin' ? (e.armor ? 'goblin_armor' : e.poison ? 'goblin_poison' : 'goblin') : e.type === 'mage' ? 'mage_' + e.elem : e.type);

export const catOf = (e) => (e.type === 'goblin' ? (e.armor ? 'armor' : 'beast') : e.type === 'charger' ? 'armor' : ['rat', 'leech', 'shaman'].includes(e.type) ? 'beast' : 'bone');

/** 몬스터 원소 저항 −3~+3 (docs/밸런스_기준.md §3.1). 보스는 약점 하나를 반드시 둔다 */
export const MON_RES = {
  goblin: {}, rat: {}, leech: { bolt: -1 }, shaman: { poison: 1 }, goblin_poison: { poison: 2 }, goblin_armor: { bolt: -1 }, charger: { bolt: -1 }, archer: { frost: 1, poison: 3 },
  mage_bolt: { bolt: 3, poison: 3 }, mage_fire: { fire: 3, frost: -1, poison: 3 }, mage_frost: { fire: -2, frost: 3, poison: 3 },
  chief: { fire: -1 }, lich: { bolt: 2, fire: -1, poison: 3 }, boarking: { bolt: -1, fire: 1 }, abyss: { fire: 2, frost: -1, poison: 3 },
};
export const monRes = (e, el) => ((e.boss ? MON_RES[e.boss] : MON_RES[e.type === 'mage' && !e.elem ? 'mage_bolt' : kindOf(e)]) || {})[el] || 0;
