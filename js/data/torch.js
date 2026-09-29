export const TORCH_MAX = 100;
export const TORCH_BONUS = 20;
export const TORCH_BURN = 0.5;
export const LAMP_REFILL = 40;
export const JAR_REFILL = 60;
export const OLD_KEEPERS = ['이솔', '하람', '연우', '서하', '가온', '다인', '유담', '시온', '루아', '태린', '해민', '나린', '도하', '소이', '윤슬', '라온', '은재', '미루', '지안', '새별'];
export const torchTier = (v) => v <= 0 ? 'out' : v < 25 ? 'low' : v < 50 ? 'mid' : 'high';
export const torchSight = (v, base = 7) => v <= 0 ? 1 : v < 25 ? Math.max(1, base - 4) : v < 50 ? Math.max(1, base - 2) : base;
