export const ENEMY = {
  goblin: { name: '고블린', hp: 5, atk: 2, desc: '약한 무리. 몰려와서 에워싼다.', tip: '좁은 복도·문간에 서면 한 번에 한 마리만 붙는다. 뭉쳐서 물을 건널 때 번개 한 방.' },
  mage: { name: '마법사', hp: 8, atk: 1, desc: '바닥에 붉은 표식을 남기고, 다음 턴에 그 자리로 주문을 떨어뜨린다. 가까이 오면 물러선다.', tip: '표식 밖으로 비켜서라. 적을 표식 안으로 밀면 대신 맞는다. 얼리거나 기절시키면 주문이 끊긴다.' },
  charger: { name: '철갑 멧돼지', hp: 16, atk: 4, desc: '일직선(가로·세로·대각)에 서면 화살표로 돌진 경로를 예고하고, 다음 턴 끝까지 돌진한다(8 피해).', tip: '경로에서 비켜서면 벽에 머리를 박고 5 피해 + 기절. 경로 위의 다른 적도 들이받는다.' },
  archer: { name: '해골 궁수', hp: 7, atk: 4, desc: '거리를 두고 조준(붉은 점선)한 뒤 다음 턴에 쏜다. 붙으면 도망간다.', tip: '벽·문·연기로 시야를 끊으면 쏘지 못한다. 모퉁이에서 기다렸다가 붙어라.' },
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
};

export const BOSSES = {
  chief: { type: 'goblin', name: '고블린 족장', hp: 38, atk: 5, scale: 1.6, desc: '뿔나팔(📯)을 들면 다음 턴에 고블린 둘을 부른다.', tip: '나팔을 들 때 몰아치거나, 부하들을 물가로 끌어들여 번개로.' },
  lich: { type: 'mage', name: '해골 대마법사', hp: 34, atk: 3, scale: 1.4, elem: 'bolt', desc: '3×3 주문을 원소를 바꿔 가며 쓴다. 붙으면 순간이동으로 달아난다.', tip: '넓은 표식 밖으로. 해골은 타격에 약하다.' },
  boarking: { type: 'charger', name: '강철 멧돼지 왕', hp: 48, atk: 6, scale: 1.4, desc: '돌진 피해 11, 쉴 틈 없이 돌진을 노린다. 벽에 박으면 3턴 기절.', tip: '벽을 등지고 섰다가 비켜서라. 갑옷엔 찌르기.' },
  abyss: { type: 'mage', name: '심연의 파수꾼', hp: 58, atk: 4, scale: 1.65, elem: 'fire', desc: '원소를 바꿔 가며 3×3 주문, 때때로 해골 궁수를 부른다.', tip: '아껴 둔 모든 것을 쏟아부을 때.' },
};

export const kindOf = (e) => (e.type === 'goblin' ? (e.armor ? 'goblin_armor' : e.poison ? 'goblin_poison' : 'goblin') : e.type === 'mage' ? 'mage_' + e.elem : e.type);

export const catOf = (e) => (e.type === 'goblin' ? (e.armor ? 'armor' : 'beast') : e.type === 'charger' ? 'armor' : 'bone');

/** 몬스터 원소 저항 −3~+3 (docs/밸런스_기준.md §3.1). 보스는 약점 하나를 반드시 둔다 */
export const MON_RES = {
  goblin: {}, goblin_poison: { poison: 2 }, goblin_armor: { bolt: -1 }, charger: { bolt: -1 }, archer: { frost: 1, poison: 3 },
  mage_bolt: { bolt: 3, poison: 3 }, mage_fire: { fire: 3, frost: -1, poison: 3 }, mage_frost: { fire: -2, frost: 3, poison: 3 },
  chief: { fire: -1 }, lich: { bolt: 2, fire: -1, poison: 3 }, boarking: { bolt: -1, fire: 1 }, abyss: { fire: 2, frost: -1, poison: 3 },
};
export const monRes = (e, el) => ((e.boss ? MON_RES[e.boss] : MON_RES[e.type === 'mage' && !e.elem ? 'mage_bolt' : kindOf(e)]) || {})[el] || 0;
