// Luna, the streak mascot: a little moon drawn in tonight's real moon phase. Her mood
// follows the streak: asleep with no streak, smiling while one is going, and glowing
// with sparkles once it reaches a week.

const SYNODIC_MONTH_DAYS = 29.530588853;
const KNOWN_NEW_MOON = Date.UTC(2000, 0, 6, 18, 14); // Jan 6 2000, 18:14 UTC

/** Where the moon is in its cycle: 0 = new, 0.25 = first quarter, 0.5 = full, 0.75 = last quarter. */
export function moonPhase(date = new Date()) {
  const days = (date.getTime() - KNOWN_NEW_MOON) / 86_400_000;
  return (((days / SYNODIC_MONTH_DAYS) % 1) + 1) % 1;
}

export function phaseName(phase) {
  const names = [
    "New moon", "Waxing crescent", "First quarter", "Waxing gibbous",
    "Full moon", "Waning gibbous", "Last quarter", "Waning crescent",
  ];
  return names[Math.round(phase * 8) % 8];
}

export function moodFor(streak) {
  if (streak === 0) return "sleepy";
  return streak >= 7 ? "glowing" : "happy";
}

const R = 25;
const C = 32;

/**
 * The sunlit part of the disc: the limb on the lit side plus the terminator, a
 * half-ellipse whose width follows the phase (thin crescent → half → nearly full).
 */
function litPath(phase) {
  const k = Math.cos(2 * Math.PI * phase); // 1 at new moon, -1 at full
  const waxing = phase < 0.5; // waxing: lit on the right; waning: lit on the left
  const limbSweep = waxing ? 1 : 0;
  const terminatorSweep = k > 0 ? 1 - limbSweep : limbSweep;
  const rx = Math.max(Math.abs(k) * R, 0.01);
  return `M${C} ${C - R}A${R} ${R} 0 0 ${limbSweep} ${C} ${C + R}` +
    `A${rx} ${R} 0 0 ${terminatorSweep} ${C} ${C - R}Z`;
}

let idCount = 0;

/** Luna as an inline SVG string, `size` px wide, in the moon phase for `date`. */
export function lunaSvg(streak, size, date = new Date()) {
  const mood = moodFor(streak);
  const phase = moonPhase(date);
  const n = idCount++;
  const [light, dark, crater] =
    mood === "sleepy" ? ["#e4e5ee", "#a9abbd", "#9497a8"] : ["#fff6d6", "#f3cf7a", "#e2b55a"];
  const eyes =
    mood === "sleepy"
      ? "M20 31q4.5 3.5 9 0M35 31q4.5 3.5 9 0" // closed, sleeping
      : "M20 32q4.5-5 9 0M35 32q4.5-5 9 0"; // closed, smiling ^^
  const mouth = mood === "sleepy" ? "M29.5 41.5h5" : "M27 39.5q5 5.5 10 0";
  const face = `<path d="${eyes}"/><path d="${mouth}"/>`;
  const cheekOpacity = mood === "sleepy" ? 0.25 : 0.6;
  const extras =
    mood === "sleepy"
      ? '<text x="50" y="14" class="luna-z" font-size="11" font-weight="700" fill="#c9cbe0">z</text>'
      : mood === "glowing"
        ? '<path class="luna-sparkle" d="M55 8l1.6 3.4L60 13l-3.4 1.6L55 18l-1.6-3.4L50 13l3.4-1.6z" fill="#fff3c4"/>' +
          '<path class="luna-sparkle delay" d="M8 46l1.2 2.6L12 50l-2.8 1.4L8 54l-1.2-2.6L4 50l2.8-1.4z" fill="#fff3c4"/>'
        : "";

  return `<svg class="luna luna-${mood}" viewBox="0 0 64 64" width="${size}" height="${size}"
    role="img" aria-label="Luna, ${phaseName(phase).toLowerCase()}">
    <defs>
      <radialGradient id="luna-fill-${n}" cx="38%" cy="32%" r="72%">
        <stop offset="0" stop-color="${light}"/><stop offset="1" stop-color="${dark}"/>
      </radialGradient>
      <clipPath id="luna-lit-${n}"><path d="${litPath(phase)}"/></clipPath>
    </defs>
    <!-- The moon in shadow, faintly lit by earthshine so Luna is always visible -->
    <circle cx="${C}" cy="${C}" r="${R}" fill="#2d2f42" stroke="rgb(255 255 255 / 0.14)" stroke-width="1"/>
    <g fill="none" stroke="#8d90ad" stroke-width="2.4" stroke-linecap="round">${face}</g>
    <!-- The sunlit part, with craters, cheeks and face clipped to it -->
    <g clip-path="url(#luna-lit-${n})">
      <circle cx="${C}" cy="${C}" r="${R}" fill="url(#luna-fill-${n})"/>
      <circle cx="19" cy="20" r="3.6" fill="${crater}" opacity="0.45"/>
      <circle cx="46" cy="21" r="2.2" fill="${crater}" opacity="0.45"/>
      <circle cx="43" cy="49" r="2.8" fill="${crater}" opacity="0.45"/>
      <circle cx="18.5" cy="38" r="3.2" fill="#ff9fb0" opacity="${cheekOpacity}"/>
      <circle cx="45.5" cy="38" r="3.2" fill="#ff9fb0" opacity="${cheekOpacity}"/>
      <g fill="none" stroke="#5b4630" stroke-width="2.4" stroke-linecap="round">${face}</g>
    </g>
    ${extras}
  </svg>`;
}
