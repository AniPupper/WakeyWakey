// Gentle wake-up chimes, synthesized live with Web Audio.
//
// PRD: "Only a slight increase in volume; too gradual may result in lack of
// effectiveness. If we vary the ringtone then that might prevent her from getting
// used to and sleeping through the sound." So each chime starts clearly audible,
// rises only a little, and a different melody plays each day of the week.

const C5 = 523.25, D5 = 587.33, E5 = 659.25, G5 = 783.99, A5 = 880.0;
const C6 = 1046.5, D6 = 1174.66, E6 = 1318.51;

// Pentatonic melodies, so every note combination sounds pleasant. null = rest.
export const TONES = [
  { name: "Sunrise", melody: [C5, E5, G5, C6, null, G5, E5, null], noteSeconds: 0.45 },
  { name: "Meadow", melody: [E5, G5, A5, G5, E5, null, D5, null], noteSeconds: 0.5 },
  { name: "Ripple", melody: [G5, A5, C6, D6, E6, null, null, null], noteSeconds: 0.35 },
  { name: "Breeze", melody: [A5, G5, E5, D5, C5, null, E5, null], noteSeconds: 0.55 },
  { name: "Glow", melody: [C6, A5, G5, A5, C6, null, E6, null], noteSeconds: 0.4 },
];

/**
 * The tone for an alarm. By default it rotates by day so it never becomes background
 * noise; turning rotation off in Settings plays the one chosen tone every day.
 */
export function toneFor(date, { rotate = true, tone = TONES[0].name } = {}) {
  if (!rotate) return TONES.find((t) => t.name === tone) ?? TONES[0];
  const dayNumber = Math.floor(date.getTime() / 86_400_000);
  return TONES[dayNumber % TONES.length];
}

// The alarm starts at this share of its final volume and rises to full over the ramp.
const START_RATIO = 0.55;
export const DEFAULT_VOLUME = 0.85;
const RAMP_SECONDS = 60;

export class ChimePlayer {
  #ctx = null;
  #master = null;
  #keepAlive = null;
  #timer = null;

  /** Must be called from a tap: iOS only allows audio that a user gesture started. */
  unlock() {
    // Play through the ringer/silent switch, like a real alarm (Safari 17+).
    if (navigator.audioSession) navigator.audioSession.type = "playback";
    if (!this.#ctx) {
      this.#ctx = new AudioContext();
      this.#master = this.#ctx.createGain();
      this.#master.connect(this.#ctx.destination);
    }
    if (this.#ctx.state !== "running") this.#ctx.resume();
  }

  /** Keep the audio session alive overnight so iOS doesn't suspend it before the alarm. */
  holdAwake() {
    if (this.#keepAlive || !this.#ctx) return;
    const silent = this.#ctx.createGain();
    silent.gain.value = 0;
    const source = this.#ctx.createConstantSource();
    source.connect(silent).connect(this.#ctx.destination);
    source.start();
    this.#keepAlive = source;
  }

  releaseAwake() {
    this.#keepAlive?.stop();
    this.#keepAlive = null;
  }

  /** Loop the tone until stop(), rising slightly to `volume` (0–1) over the first minute. */
  play(tone, { rampSeconds = RAMP_SECONDS, volume = DEFAULT_VOLUME } = {}) {
    this.unlock();
    this.stop();
    const ctx = this.#ctx;
    const now = ctx.currentTime;
    this.#master.gain.cancelScheduledValues(now);
    this.#master.gain.setValueAtTime(volume * START_RATIO, now);
    this.#master.gain.linearRampToValueAtTime(volume, now + rampSeconds);

    const phraseSeconds = (tone.melody.length + 2) * tone.noteSeconds;
    let phraseStart = now + 0.05;
    const schedulePhrase = () => {
      tone.melody.forEach((freq, i) => {
        if (freq !== null) this.#bell(freq, phraseStart + i * tone.noteSeconds);
      });
      phraseStart += phraseSeconds;
      // Schedule the next phrase shortly before this one ends.
      const delay = (phraseStart - ctx.currentTime - 0.3) * 1000;
      this.#timer = setTimeout(schedulePhrase, Math.max(delay, 0));
    };
    schedulePhrase();
  }

  stop() {
    clearTimeout(this.#timer);
    this.#timer = null;
    if (this.#master) {
      const now = this.#ctx.currentTime;
      this.#master.gain.cancelScheduledValues(now);
      this.#master.gain.setTargetAtTime(0, now, 0.05);
    }
  }

  /** A soft bell: a fundamental plus quiet overtones, quick attack, slow decay. */
  #bell(freq, at) {
    const ctx = this.#ctx;
    const env = ctx.createGain();
    env.gain.setValueAtTime(0, at);
    env.gain.linearRampToValueAtTime(0.25, at + 0.01);
    env.gain.exponentialRampToValueAtTime(0.001, at + 1.6);
    env.connect(this.#master);
    for (const [multiple, level] of [[1, 1], [2, 0.3], [3, 0.1]]) {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.frequency.value = freq * multiple;
      gain.gain.value = level;
      osc.connect(gain).connect(env);
      osc.start(at);
      osc.stop(at + 1.7);
    }
  }
}
