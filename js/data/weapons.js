export const WEAPONS = {
  sword: { name: '장검', line: '앞을 좁게 벤다', form: 'slash', shape: 'fan', angle: 0.9, reach: 1.25, damage: 8, interval: 1.05, hands: 1 },
  axe: { name: '손도끼', line: '가까운 살을 가른다', form: 'slash', shape: 'fan', angle: 1.2, reach: 1, damage: 9, interval: 1.1, hands: 1 },
  greatsword: { name: '대검', line: '앞의 반원을 벤다', form: 'slash', shape: 'fan', angle: Math.PI, reach: 1.6, damage: 12, interval: 1.65, hands: 2 },
  mace: { name: '철퇴', line: '뼈를 부순다', form: 'blunt', shape: 'fan', angle: 1.1, reach: 1.1, damage: 9, interval: 1.2, hands: 1 },
  flail: { name: '도리깨', line: '넓게 휘두른다', form: 'blunt', shape: 'fan', angle: 2.5, reach: 1.35, damage: 8, interval: 1.2, hands: 1 },
  hammer: { name: '대형 망치', line: '묵직한 반원을 친다', form: 'blunt', shape: 'fan', angle: Math.PI, reach: 1.35, damage: 15, interval: 1.9, hands: 2 },
  dagger: { name: '단검', line: '짧고 빠르게 찌른다', form: 'pierce', shape: 'line', width: 0.6, reach: 0.9, damage: 5, interval: 0.65, hands: 1 },
  spear: { name: '창', line: '긴 한 줄을 찌른다', form: 'pierce', shape: 'line', width: 0.45, reach: 2, damage: 8, interval: 1.2, hands: 1 },
  pike: { name: '장창', line: '먼 줄을 꿰뚫는다', form: 'pierce', shape: 'line', width: 0.5, reach: 2.7, damage: 10, interval: 1.5, hands: 2 },
  sling: { name: '투석구', line: '돌을 멀리 날린다', form: 'blunt', shape: 'projectile', reach: 5, damage: 6, interval: 1.1, hands: 1 },
  bow: { name: '활', line: '멀리 화살을 보낸다', form: 'pierce', shape: 'projectile', reach: 6, damage: 8, interval: 1.25, hands: 2 },
  crossbow: { name: '석궁', line: '느리게 깊이 박힌다', form: 'pierce', shape: 'projectile', reach: 6, damage: 15, interval: 2, hands: 2 },
};
