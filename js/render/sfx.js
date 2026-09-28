/* ================= 효과음 (WebAudio 합성) ================= */
export const Sfx = {
  ctx: null, on: true, last: {},
  init() {
    if (this.ctx) { this.ctx.resume?.(); return; }
    try {
      this.ctx = new (window.AudioContext || window.webkitAudioContext)();
      this.master = this.ctx.createGain(); this.master.gain.value = 0.5; this.master.connect(this.ctx.destination);
      const len = this.ctx.sampleRate * 0.6; this.nb = this.ctx.createBuffer(1, len, this.ctx.sampleRate); const dd = this.nb.getChannelData(0); for (let i = 0; i < len; i++) dd[i] = Math.random() * 2 - 1;
    } catch (_) { this.ctx = null; }
  },
  tone(f, dur, type = 'square', vol = 0.08, slide = 0, delay = 0) {
    const c = this.ctx, t = c.currentTime + delay, o = c.createOscillator(), g = c.createGain();
    o.type = type; o.frequency.setValueAtTime(f, t); if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(30, f + slide), t + dur);
    g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur); o.connect(g).connect(this.master); o.start(t); o.stop(t + dur + 0.02);
  },
  noise(dur, vol = 0.2, freq = 1200, q = 0.8, delay = 0) {
    const c = this.ctx, t = c.currentTime + delay, s = c.createBufferSource(), f = c.createBiquadFilter(), g = c.createGain();
    s.buffer = this.nb; f.type = 'bandpass'; f.frequency.value = freq; f.Q.value = q;
    g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur); s.connect(f).connect(g).connect(this.master); s.start(t); s.stop(t + dur + 0.02);
  },
  chime(stage) {
    if (!this.ctx || !this.on) return;
    const f = 660 * Math.pow(2, Math.min(stage - 1, 8) * 3 / 12);
    this.tone(f, 0.16, 'triangle', 0.06); this.tone(f * 1.5, 0.22, 'sine', 0.04, 0, 0.05);
    if (stage >= 3) this.tone(f * 2, 0.3, 'triangle', 0.04, 0, 0.1);
  },
  play(n) {
    if (!this.ctx || !this.on) return;
    const now = performance.now(); if (now - (this.last[n] || 0) < 45) return; this.last[n] = now;
    const T = this.tone.bind(this), N = this.noise.bind(this);
    switch (n) {
      case 'hit': N(0.09, 0.3, 1600, 1); T(180, 0.08, 'square', 0.06, -90); break;
      case 'hurt': N(0.12, 0.3, 900, 1); T(240, 0.18, 'sawtooth', 0.07, -140); break;
      case 'swing': N(0.07, 0.08, 3000, 2); break;
      case 'zap': N(0.16, 0.2, 5200, 1.5); T(880, 0.1, 'sawtooth', 0.035, 700); break;
      case 'thunder': N(0.5, 0.35, 700, 0.6); T(90, 0.4, 'sawtooth', 0.08, -40); break;
      case 'boom': N(0.5, 0.55, 380, 0.7); T(70, 0.45, 'sine', 0.3, -40); break;
      case 'fire': N(0.3, 0.18, 1400, 0.6); break;
      case 'hiss': N(0.35, 0.12, 4200, 0.8); break;
      case 'freeze': T(1500, 0.12, 'triangle', 0.06, 500); T(2200, 0.2, 'triangle', 0.04, 300, 0.05); break;
      case 'shatter': T(1800, 0.1, 'square', 0.04, 600); N(0.25, 0.25, 6000, 1); break;
      case 'step': N(0.035, 0.05, 900, 1.2); break;
      case 'splash': N(0.2, 0.15, 2600, 0.8); break;
      case 'pick': T(880, 0.07, 'square', 0.045); T(1320, 0.09, 'square', 0.04, 0, 0.07); break;
      case 'alert': T(700, 0.08, 'square', 0.05, 250); break;
      case 'cast': T(420, 0.35, 'sine', 0.05, 380); break;
      case 'die': T(360, 0.22, 'square', 0.06, -280); N(0.15, 0.15, 2400, 1); break;
      case 'door': N(0.12, 0.12, 500, 2); T(140, 0.1, 'triangle', 0.05, -30); break;
      case 'push': N(0.1, 0.2, 700, 1); T(160, 0.12, 'square', 0.05, -60); break;
      case 'snort': N(0.2, 0.18, 400, 2); break;
      case 'draw': T(260, 0.25, 'triangle', 0.03, 180); break;
      case 'dash': N(0.3, 0.2, 500, 0.8); break;
      case 'arrow': N(0.12, 0.1, 3500, 3); break;
      case 'throw': N(0.1, 0.08, 1800, 2); break;
      case 'whoosh': N(0.15, 0.1, 2400, 1.5); break;
      case 'glass': T(2400, 0.08, 'square', 0.03); N(0.15, 0.2, 7000, 1.5); break;
      case 'heal': T(520, 0.12, 'sine', 0.06, 200); T(780, 0.2, 'sine', 0.05, 200, 0.1); break;
      case 'drink': T(300, 0.08, 'sine', 0.06, 100); T(360, 0.08, 'sine', 0.05, 100, 0.09); break;
      case 'read': N(0.2, 0.08, 3000, 1); T(600, 0.25, 'triangle', 0.04, 300); break;
      case 'tele': T(300, 0.3, 'sine', 0.06, 900); break;
      case 'tick': T(200, 0.05, 'triangle', 0.03); break;
      case 'stairs': T(330, 0.15, 'triangle', 0.06, -60); T(262, 0.18, 'triangle', 0.06, -60, 0.16); T(196, 0.3, 'triangle', 0.06, -60, 0.32); break;
      case 'ui': T(660, 0.04, 'square', 0.025); break;
      case 'slash': N(0.12, 0.18, 4200, 1.5); T(900, 0.06, 'sawtooth', 0.02, -500); break;
      case 'blunt': N(0.14, 0.35, 500, 1); T(110, 0.14, 'sine', 0.2, -50); break;
      case 'pierce': N(0.06, 0.15, 6500, 3); T(1400, 0.05, 'square', 0.02, 400); break;
      case 'crit': T(1200, 0.08, 'square', 0.05, 800); N(0.12, 0.3, 3000, 1); break;
      case 'gem': T(1320, 0.1, 'triangle', 0.05); T(1760, 0.14, 'triangle', 0.04, 0, 0.08); T(1320, 0.1, 'triangle', 0.03, 0, 0.22); break;
      case 'pickgem': T(988, 0.08, 'sine', 0.06); T(1480, 0.14, 'sine', 0.05, 0, 0.07); break;
      case 'shield': T(520, 0.18, 'triangle', 0.05, 300); break;
      case 'slow': T(220, 0.7, 'sine', 0.12, -120); N(0.6, 0.12, 300, 0.5); break;
      default: break;
    }
  },
};
