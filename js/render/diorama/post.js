import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';

/* ---------------- 후처리 한 패스: 아주 약한 틸트시프트 + 비네트 + 필름 그레인 + 색 보정 ----------------
   색 보정: 어두운 곳은 검푸르게, 채도는 조금 낮게. 밝은 주황(횃불)은 그대로 둔다. */
export const DarkShader = {
  uniforms: { tDiffuse: { value: null }, uRes: { value: new THREE.Vector2(1, 1) }, uFocus: { value: 0.5 }, uBlur: { value: 0.8 },
    uVig: { value: 0.7 }, uGrain: { value: 0.05 }, uTime: { value: 0 }, uShadowTint: { value: new THREE.Color(0.05, 0.07, 0.13) }, uSat: { value: 0.82 } },
  vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
  fragmentShader: `uniform sampler2D tDiffuse; uniform vec2 uRes; uniform float uFocus; uniform float uBlur; uniform float uVig; uniform float uGrain; uniform float uTime; uniform vec3 uShadowTint; uniform float uSat;
varying vec2 vUv;
float rnd(vec2 p){ return fract(sin(dot(p, vec2(12.9898, 78.233)) + uTime * 7.13) * 43758.5453); }
void main(){
  float d = abs(vUv.y - uFocus), amt = smoothstep(0.2, 0.5, d) * uBlur;
  vec4 c = texture2D(tDiffuse, vUv);
  if (amt > 0.01) {
    vec2 st = amt / uRes;
    c = c * 0.36 + (texture2D(tDiffuse, vUv + vec2(st.x, st.y)) + texture2D(tDiffuse, vUv + vec2(-st.x, st.y)) + texture2D(tDiffuse, vUv + vec2(st.x, -st.y)) + texture2D(tDiffuse, vUv - st)) * 0.16;
  }
  float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
  float warm = smoothstep(0.35, 0.9, c.r - c.b);          // 횃불·불빛은 채도를 지킨다
  c.rgb = mix(vec3(l), c.rgb, mix(uSat, 1.0, warm));
  c.rgb += uShadowTint * (1.0 - smoothstep(0.0, 0.35, l)); // 그림자는 검푸르게
  vec2 q = (vUv - 0.5) * vec2(1.0, 0.8);
  c.rgb *= mix(1.0, smoothstep(0.85, 0.12, length(q)), uVig);
  c.rgb += (rnd(vUv * uRes) - 0.5) * uGrain;
  gl_FragColor = c;
}`,
};

export function createPost(renderer, scene, camera) {
  const rt = new THREE.WebGLRenderTarget(2, 2, { type: THREE.HalfFloatType, samples: 4 });
  const composer = new EffectComposer(renderer, rt);
  composer.addPass(new RenderPass(scene, camera));
  const pass = new ShaderPass(DarkShader);
  composer.addPass(pass); composer.addPass(new OutputPass());
  const U = pass.uniforms;
  return {
    composer, pass,
    setSize(w, h, pr) { composer.setPixelRatio(pr); composer.setSize(w, h); U.uRes.value.set(w * pr, h * pr); },
    setFocus(y) { U.uFocus.value = y; },
    setStrength(k) { U.uBlur.value = k; },
    /** 프리셋별 분위기 { vig, grain, blur, sat, shadowTint } */
    setLook(o) { for (const [k, v] of Object.entries(o)) { const u = U['u' + k[0].toUpperCase() + k.slice(1)]; if (!u) continue; if (u.value && u.value.isColor) u.value.set(v); else u.value = v; } },
    render(t) { U.uTime.value = t || 0; composer.render(); },
  };
}
