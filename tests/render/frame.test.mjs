import test from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import { Diorama } from '../../js/render/diorama/index.js';
import { createWorld } from '../../js/sim/world.js';
import { newMeta } from '../../js/town/meta.js';

// Exercise the real frame and doll code without a DOM or WebGL context.
function renderer(world, town = null) {
  const view = new Diorama();
  Object.assign(view, {
    world, town, scene: new THREE.Scene(), props: new THREE.Group(),
    camera: new THREE.PerspectiveCamera(38, 1, 0.1, 100),
    follow: new THREE.Vector3(), dolls: new Map(), tells: new THREE.Group(),
    mat: color => new THREE.MeshBasicMaterial({ color }),
    torch: new THREE.PointLight(), zoom: 15, yaw: 0, tilt: 0, intro: 0,
    effects: { shake: 0, frame() {} }, renderer: { render() {} },
  });
  view.rebuild = () => {};
  return view;
}

test('정지한 0초 던전의 첫 프레임은 마을 상태 없이 그려진다', () => {
  const world = createWorld({ seed: 1, tutorial: true });
  assert.equal(world.time, 0);
  assert.ok(world.units.some(u => u.prevX !== u.x || u.prevY !== u.y));
  const view = renderer(world);
  assert.doesNotThrow(() => view.frame(world, 1, 0.016));
  assert.equal(view.dolls.size, world.units.length);
  for (const doll of view.dolls.values()) {
    for (const leg of doll.legs) assert.ok(Number.isFinite(leg.rotation.x));
  }
});

test('이동 중인 0초 등불지기의 걸음은 유한한 각도로 그려진다', () => {
  const world = createWorld({ seed: 2 });
  world.units[0].prevX -= 0.1;
  const view = renderer(world);
  assert.doesNotThrow(() => view.frame(world, 0.5, 0.016));
  assert.ok(Number.isFinite(view.dolls.get('hero').legs[0].rotation.x));
});

test('던전 없이 마을의 첫 프레임도 그려진다', () => {
  const town = newMeta();
  const view = renderer(null, town);
  assert.doesNotThrow(() => view.frame(town, 1, 0.016));
});
