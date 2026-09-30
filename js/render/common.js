import * as THREE from 'three';

/* ================= 연출 (Three.js) ================= */
export const _w = new THREE.Vector3(), _tv = new THREE.Vector3();

export const W3 = (x, y, h = 0) => new THREE.Vector3(x, h, y);

export const easeInOut = (t) => (t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2);

export const easeOut = (t) => 1 - Math.pow(1 - t, 3);

export const SKIN = 0xffd7b0;
