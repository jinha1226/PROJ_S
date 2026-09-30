export const ITEMS = {
  heal: { name: '회복 물약', line: '상처를 닫는다', kind: 'potion', appearance: '붉은 물약' },
  antidote: { name: '해독 물약', line: '독을 걷어낸다', kind: 'potion', appearance: '맑은 물약' },
  haste: { name: '가속 물약', line: '발걸음이 가벼워진다', kind: 'potion', appearance: '노란 물약' },
  teleport: { name: '순간이동 두루마리', line: '낯선 곳에 선다', kind: 'scroll', appearance: '별무늬 두루마리' },
  fear: { name: '공포 두루마리', line: '적들이 등을 보인다', kind: 'scroll', appearance: '눈무늬 두루마리' },
  flame: { name: '불꽃 두루마리', line: '앞을 태운다', kind: 'scroll', appearance: '그을린 두루마리', element: 'fire' },
  water: { name: '물병', line: '웅덩이를 남긴다', kind: 'throw', appearance: '푸른 병', element: 'water' },
  oil: { name: '기름병', line: '기름을 남긴다', kind: 'throw', appearance: '검은 병' },
  smoke: { name: '연막병', line: '시야를 가린다', kind: 'throw', appearance: '회색 병' },
  frost: { name: '서리 구슬', line: '젖은 발을 얼린다', kind: 'throw', appearance: '흰 구슬', element: 'ice' },
  spark: { name: '번개 구슬', line: '물결을 따라 번진다', kind: 'throw', appearance: '노란 구슬', element: 'lightning' },
  poison: { name: '독병', line: '녹색 얼룩', kind: 'throw', appearance: '녹색 병', element: 'poison' },
  identify: { name: '확인 두루마리', line: '가려진 이름을 읽는다', kind: 'gear', appearance: '글자 두루마리' },
  enhance: { name: '강화 두루마리', line: '날을 벼린다', kind: 'gear', appearance: '칼무늬 두루마리' },
};
export const START_ITEMS = { heal: 2, antidote: 1, haste: 1, teleport: 1, fear: 1, flame: 2, water: 2, oil: 1, smoke: 1, frost: 2, spark: 2, poison: 1, identify: 1, enhance: 1 };
