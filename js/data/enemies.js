export const ENEMIES = {
  rat: { name: '굴쥐', line: '작은 이빨이 에워싼다', brain: 'melee', color: '#938cbd', weak: 'slash', resist: {}, weapon: 'dagger' },
  goblin: { name: '고블린', line: '칼을 들고 뒤쫓는다', brain: 'melee', color: '#79ab71', weak: 'slash', resist: {}, weapon: 'sword' },
  mage: { name: '잿빛 마법사', line: '발밑에 불이 고인다', brain: 'caster', color: '#a38dcc', weak: 'pierce', resist: { fire: 2 }, weapon: 'sling' },
  boar: { name: '멧돼지', line: '한번 달리면 멈추지 않는다', brain: 'charger', color: '#a17a70', weak: 'slash', resist: { ice: -1 }, weapon: 'mace' },
  archer: { name: '해골 궁수', line: '멀리서 활을 당긴다', brain: 'ranged', color: '#d6ccab', weak: 'blunt', resist: { poison: 3 }, weapon: 'bow' },
  shaman: { name: '주술사', line: '쓰러지는 동료를 붙든다', brain: 'healer', color: '#649d9c', weak: 'pierce', resist: { lightning: -1 }, weapon: 'sling' },
  chief: { name: '고블린 족장', line: '굴 깊은 곳의 주인', brain: 'boss', color: '#ba7951', weak: 'pierce', resist: { fire: 1 }, weapon: 'hammer' },
  keeper: { name: '심연의 파수꾼', line: '새벽 앞에 선 그림자', brain: 'raid', color: '#7771aa', weak: 'blunt', resist: {}, weapon: 'greatsword' },
};
