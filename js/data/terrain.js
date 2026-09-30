export const TERRAIN = {
  floor: { name: '돌바닥', line: '차가운 돌', color: '#505768' },
  wall: { name: '벽', line: '막힌 길', color: '#353d52' },
  water: { name: '물웅덩이', line: '발목을 적신다', color: '#397cbd' },
  grass: { name: '풀', line: '마른 줄기', color: '#648457' },
  oil: { name: '기름', line: '검은 윤기', color: '#453744' },
  ice: { name: '얼음', line: '발이 미끄러진다', color: '#97dce4' },
  fire: { name: '불', line: '타오르는 바닥', color: '#f5a64f' },
  smoke: { name: '연막', line: '앞이 흐려진다', color: '#8e94a9' },
  door: { name: '문', line: '닫힌 문', color: '#957956' },
};
export const ELEMENT_COLORS = { fire: '#ff9649', ice: '#87d8ff', lightning: '#ffdf63', poison: '#9de568', water: '#5cbfff', steam: '#e1e7ed' };
export const FLOORS = [
  { name: '젖은 동굴', types: ['rat', 'goblin'], terrain: 'water' },
  { name: '좁은 굴', types: ['goblin', 'boar'], terrain: 'grass' },
  { name: '기둥 홀', types: ['mage', 'archer'], terrain: 'oil' },
  { name: '얼어붙은 길', types: ['boar', 'shaman', 'archer'], terrain: 'ice' },
  { name: '족장의 굴', types: ['goblin', 'shaman'], terrain: 'water' },
];
export const REGIONS = ['잊힌 굴', '침묵의 숲', '잠긴 회랑', '서리의 기억', '심연'];
