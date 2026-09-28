import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';

/* ---------------- 후처리: 틸트시프트(위아래 흐림) + 비네트 ---------------- */
export const TiltShader = {
  uniforms: { tDiffuse: { value: null }, uDir: { value: new THREE.Vector2(1, 0) }, uRes: { value: new THREE.Vector2(1, 1) },
    uFocus: { value: 0.5 }, uBand: { value: 0.13 }, uMax: { value: 2.4 }, uVig: { value: 0 } },
  vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
  fragmentShader: `uniform sampler2D tDiffuse; uniform vec2 uDir; uniform vec2 uRes; uniform float uFocus; uniform float uBand; uniform float uMax; uniform float uVig;
varying vec2 vUv;
void main(){
  float d = abs(vUv.y - uFocus);
  float amt = smoothstep(uBand, uBand + 0.32, d) * uMax;
  vec2 st = uDir / uRes * amt;
  vec4 c = texture2D(tDiffuse, vUv) * 0.2270270270;
  c += texture2D(tDiffuse, vUv + st * 1.3846153846) * 0.3162162162;
  c += texture2D(tDiffuse, vUv - st * 1.3846153846) * 0.3162162162;
  c += texture2D(tDiffuse, vUv + st * 3.2307692308) * 0.0702702703;
  c += texture2D(tDiffuse, vUv - st * 3.2307692308) * 0.0702702703;
  if (uVig > 0.0) { vec2 q = (vUv - 0.5) * vec2(1.0, 0.85); c.rgb *= mix(1.0, smoothstep(0.82, 0.18, length(q)), uVig); }
  gl_FragColor = c;
}`,
};

export function createPost(renderer, scene, camera) {
  const rt = new THREE.WebGLRenderTarget(2, 2, { type: THREE.HalfFloatType, samples: 4 });
  const composer = new EffectComposer(renderer, rt);
  composer.addPass(new RenderPass(scene, camera));
  const th = new ShaderPass(TiltShader), tv = new ShaderPass(TiltShader);
  th.uniforms.uDir.value.set(1, 0); tv.uniforms.uDir.value.set(0, 1); tv.uniforms.uVig.value = 0.55;
  composer.addPass(th); composer.addPass(tv); composer.addPass(new OutputPass());
  return {
    composer, th, tv,
    setSize(w, h, pr) {
      composer.setPixelRatio(pr); composer.setSize(w, h);
      for (const p of [th, tv]) { p.uniforms.uRes.value.set(w * pr, h * pr); p.uniforms.uMax.value = 2.1 * pr; }
    },
    setFocus(y) { th.uniforms.uFocus.value = tv.uniforms.uFocus.value = y; },
    setStrength(k) { th.uniforms.uMax.value = tv.uniforms.uMax.value = k; },
    render() { composer.render(); },
  };
}
