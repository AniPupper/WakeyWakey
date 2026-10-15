import { ChimePlayer, DEFAULT_VOLUME, TONES, toneFor } from "./chimes.js";
import { lunaSvg } from "./mascot.js";
import {
  ALL_DAYS, DAY_NAMES, WEEKDAYS, WEEKEND,
  bedtimeBefore, defaultSchedule, fromLegacyPlan, inferMode, nextAlarm, sleepMinutes, switchMode, updateDays,
} from "./schedule.js";

const SCHEDULE_KEY = "wakeywakey.schedule";
const LEGACY_PLAN_KEY = "wakeywakey.plan";
const SETTINGS_KEY = "wakeywakey.settings";
// One entry per alarm: { alarmAt, bedtimeAt?, phoneDownAt?, stoppedAt?, ownWake? } (ms timestamps).
const LOG_KEY = "wakeywakey.wakeLog";
// The streak last shown, so the app can celebrate when it goes up.
const SEEN_STREAK_KEY = "wakeywakey.seenStreak";

const DAY_LETTERS = ["S", "M", "T", "W", "T", "F", "S"];
const DAY_SHORT = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
// In the last stretch before the alarm, night mode offers "I'm already up".
const EARLY_WAKE_WINDOW_MS = 90 * MINUTE;
// If the page was asleep through the alarm by more than this, don't ring late.
const LATE_RING_LIMIT_MS = HOUR;
// How long before bedtime the home screen starts nudging toward night mode.
const BEDTIME_NUDGE_MS = 30 * MINUTE;
// Night mode started earlier than this before bedtime arms the alarm but isn't logged as
// "phone down" (e.g. testing in the afternoon).
const PHONE_DOWN_WINDOW_MS = 3 * HOUR;
// Stopping the alarm within this long counts as getting up right away.
const ON_TIME_MINUTES = 2;
// The phone-down bars in Progress are full width at this many minutes early or late.
const PHONE_CHART_MAX_MINUTES = 60;
const HISTORY_ROWS = 7;
// The rhythm chart spans 6 PM the night before to noon on the wake-up day.
const CHART_START_HOURS_BEFORE_MIDNIGHT = 6;
const CHART_SPAN_MS = 18 * HOUR;
// Previewing a chime in Settings plays it this long.
const PREVIEW_MS = 8000;
// Letting go of the volume slider plays the chime this long, at full volume (no ramp).
const VOLUME_PREVIEW_MS = 2500;
// The test alarm rings this long after it's started.
const TEST_ALARM_DELAY_MS = 10_000;

const TAB_SCREENS = ["home", "schedule", "progress"];
const ALL_SCREENS = [...TAB_SCREENS, "settings", "night", "ringing"];

const $ = (id) => document.getElementById(id);
const el = (tag, className, text) => {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
};
const chimes = new ChimePlayer();

// ---- Storage (wrapped: private browsing can make localStorage throw) ----

function load(key, fallback) {
  try {
    const raw = localStorage.getItem(key);
    return raw ? JSON.parse(raw) : fallback;
  } catch {
    return fallback;
  }
}

function save(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // Not fatal: the alarm still works for this session.
  }
}

function loadSchedule() {
  const saved = load(SCHEDULE_KEY, null);
  if (saved) {
    saved.mode ??= inferMode(saved);
    return saved;
  }
  const legacy = load(LEGACY_PLAN_KEY, null);
  return legacy ? fromLegacyPlan(legacy) : defaultSchedule();
}

let schedule = loadSchedule();
let settings = { rotate: true, tone: TONES[0].name, volume: DEFAULT_VOLUME, ...load(SETTINGS_KEY, {}) };

function loadLog() {
  return load(LOG_KEY, []).sort((a, b) => a.alarmAt - b.alarmAt);
}

function updateLogEntry(alarmAt, change) {
  const log = load(LOG_KEY, []);
  let entry = log.find((e) => e.alarmAt === alarmAt);
  if (!entry) log.push((entry = { alarmAt }));
  Object.assign(entry, change);
  save(LOG_KEY, log);
}

// ---- Time helpers ----

function formatTime(date) {
  return date.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}

function formatDuration(minutes) {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (h === 0) return `${m} min`;
  return m === 0 ? `${h} hr` : `${h} hr ${m} min`;
}

function sameDay(a, b) {
  return a.toDateString() === b.toDateString();
}

function daysAgo(n, from = new Date()) {
  const date = new Date(from);
  date.setDate(from.getDate() - n);
  return date;
}

function relativeDay(date, now = new Date()) {
  if (sameDay(date, now)) return "today";
  if (sameDay(date, daysAgo(-1, now))) return "tomorrow";
  return DAY_NAMES[date.getDay()];
}

function describeNight(bedtime, now = new Date()) {
  return sameDay(bedtime, now) ? "tonight" : `${DAY_NAMES[bedtime.getDay()]} night`;
}

function describeDate(date, now = new Date()) {
  if (sameDay(date, now)) return "Today";
  if (sameDay(date, daysAgo(1, now))) return "Yesterday";
  return date.toLocaleDateString([], { weekday: "short", month: "short", day: "numeric" });
}

function capitalize(text) {
  return text[0].toUpperCase() + text.slice(1);
}

// ---- Streak: the incentive to keep a steady sleep schedule ----

function minutesLate(entry) {
  return Math.max(0, Math.round((entry.stoppedAt - entry.alarmAt) / MINUTE));
}

/** Minutes the phone went down before bedtime: positive = early, negative = late. */
function minutesEarly(entry) {
  return Math.round((entry.bedtimeAt - entry.phoneDownAt) / MINUTE);
}

function phoneDownOnTime(entry) {
  return entry.phoneDownAt != null && entry.bedtimeAt != null && minutesEarly(entry) >= 0;
}

function wokeOnTime(entry) {
  return entry.stoppedAt != null && minutesLate(entry) <= ON_TIME_MINUTES && entry.ownWake !== false;
}

/**
 * Consecutive days, counting back from today, where she was up on her own right away. Nights logged by hand count the same. A day with no
 * alarm doesn't break the streak, and adds to it if a kept night was logged anyway.
 * (Uses today's schedule for past days, which is close enough for a streak.)
 */
function currentStreak(log, now = new Date()) {
  let streak = 0;
  for (let back = 0; back < 120; back++) {
    const date = daysAgo(back, now);
    const entries = log.filter((e) => e.stoppedAt && sameDay(new Date(e.alarmAt), date));
    if (entries.some(nightKept)) {
      streak++;
      continue;
    }
    const restDay = !schedule.days[date.getDay()].on;
    const notYet = back === 0 && entries.length === 0; // today's alarm may not have rung yet
    if (restDay || notYet) continue;
    break;
  }
  return streak;
}

function nextWakeGoal(streak, now = new Date()) {
  const next = nextAlarm(schedule, now);
  if (!next) return "Turn on an alarm to start a streak.";
  const upBy = new Date(next.getTime() + ON_TIME_MINUTES * MINUTE);
  const when = `${formatTime(upBy)} ${relativeDay(next, now)}`;
  return streak > 0
    ? `Up by ${when} to keep Luna glowing.`
    : `Luna is asleep. Up by ${when} to start a streak.`;
}

/** A morning adds to the streak when she was up on time, on her own. Phone-down time is tracked but doesn't count. */
function nightKept(entry) {
  return Boolean(entry) && wokeOnTime(entry);
}

/**
 * Shows a streak number, celebrating if it went up since it was last shown: the number
 * counts up with a pop, Luna hops, and sparkles burst out.
 */
function showStreak(numberEl, mascotEl, streak, mascotSize) {
  const seen = load(SEEN_STREAK_KEY, streak);
  save(SEEN_STREAK_KEY, streak);
  mascotEl.innerHTML = lunaSvg(streak, mascotSize);
  if (streak > seen) celebrateStreak(numberEl, mascotEl, seen, streak);
  else numberEl.textContent = streak;
}

function celebrateStreak(numberEl, mascotEl, from, to) {
  numberEl.textContent = to;
  if (reducedMotion.matches) return;
  numberEl.textContent = from;
  let value = from;
  const step = () => {
    value++;
    numberEl.textContent = value;
    restartAnimation(numberEl, "bump");
    if (value < to) setTimeout(step, 280);
  };
  setTimeout(step, 450);
  restartAnimation(mascotEl, "cheer");
  for (let i = 0; i < 10; i++) {
    const angle = (i / 10) * 2 * Math.PI;
    const distance = mascotEl.offsetWidth * 0.7 + 10;
    const spark = el("span", "spark");
    spark.style.setProperty("--dx", `${Math.cos(angle) * distance}px`);
    spark.style.setProperty("--dy", `${Math.sin(angle) * distance}px`);
    spark.style.animationDelay = `${300 + (i % 3) * 60}ms`;
    mascotEl.append(spark);
    setTimeout(() => spark.remove(), 1400);
  }
}

function restartAnimation(node, className) {
  node.classList.remove(className);
  void node.offsetWidth; // reflow so the animation plays again
  node.classList.add(className);
}

/** The last 7 wake-up days as small moons: kept, missed, still to come, or no alarm. */
function renderStreakPips(log, now) {
  $("streak-pips").replaceChildren(
    ...Array.from({ length: 7 }, (_, i) => {
      const date = daysAgo(6 - i, now);
      const entry = log.find((e) => sameDay(new Date(e.alarmAt), date));
      const status =
        !schedule.days[date.getDay()].on ? "rest"
        : nightKept(entry) ? "kept"
        : i === 6 && !entry?.stoppedAt ? "tonight"
        : "missed";
      const pip = el("span", `pip ${status}`);
      pip.classList.toggle("today", i === 6);
      pip.append(el("span", "pip-mark"), el("span", "", DAY_LETTERS[date.getDay()]));
      pip.setAttribute("aria-label", `${DAY_NAMES[date.getDay()]}: ${{ kept: "kept", missed: "missed", tonight: "not yet", rest: "no alarm" }[status]}`);
      return pip;
    }),
  );
}

// ---- Alarm tab ----

function renderHome() {
  const now = new Date();
  const next = nextAlarm(schedule, now);
  $("wake-card").classList.toggle("off", !next);
  $("start-night").disabled = !next;

  if (!next) {
    $("wake-time").textContent = "Off";
    $("wake-bedtime").textContent = "No alarms scheduled";
    $("wake-countdown").textContent = "";
    $("start-night").textContent = "Start night mode";
  } else {
    const bed = bedtimeBefore(schedule, next);
    $("wake-time").textContent = formatTime(next);
    $("wake-bedtime").textContent = `${capitalize(relativeDay(next, now))} · Bedtime ${formatTime(bed)}`;
    $("wake-countdown").textContent = `Rings in ${formatDuration(Math.round((next - now) / MINUTE))}`;
    $("start-night").textContent =
      now >= bed ? "It's bedtime · Start night mode"
      : bed - now <= BEDTIME_NUDGE_MS ? "Almost bedtime · Start night mode"
      : "Start night mode";
  }

  const log = loadLog();
  const streak = currentStreak(log, now);
  showStreak($("streak-number"), $("streak-mascot"), streak, 76);
    $("streak-chip").classList.toggle("cold", streak === 0);
  $("streak-chip-detail").textContent = nextWakeGoal(streak, now);
  renderStreakPips(log, now);
  renderRhythm(log, now);
}

function chartPercent(time, wakeDay) {
  const start = new Date(wakeDay);
  start.setHours(-CHART_START_HOURS_BEFORE_MIDNIGHT, 0, 0, 0);
  return Math.min(100, Math.max(0, ((time - start) / CHART_SPAN_MS) * 100));
}

function placeBar(node, from, to, wakeDay) {
  const left = chartPercent(from, wakeDay);
  node.style.left = `${left}%`;
  node.style.width = `${Math.max(chartPercent(to, wakeDay) - left, 1.5)}%`;
}

/** Minutes after the chart start for a time, so nights that cross midnight compare correctly. */
function minutesIntoNight(time, wakeDay) {
  return (chartPercent(time, wakeDay) / 100) * (CHART_SPAN_MS / MINUTE);
}

function spread(values) {
  return values.length < 2 ? null : Math.round(Math.max(...values) - Math.min(...values));
}

function renderRhythm(log, now) {
  const rows = [];
  const phoneDowns = [];
  const wakes = [];
  for (let back = 6; back >= 0; back--) {
    const wakeDay = daysAgo(back, now);
    const day = schedule.days[wakeDay.getDay()];
    const entry = log.find((e) => sameDay(new Date(e.alarmAt), wakeDay));

    const row = el("div", "rhythm-row");
    row.classList.toggle("today", back === 0);
    const track = el("div", "rhythm-track");
    let description = "no night logged";

    if (day.on && schedule.enabled) {
      const [h, m] = day.wake.split(":").map(Number);
      const wake = new Date(wakeDay);
      wake.setHours(h, m, 0, 0);
      const planned = el("span", "rhythm-planned");
      placeBar(planned, bedtimeBefore(schedule, wake), wake, wakeDay);
      track.append(planned);
    }

    if (entry?.phoneDownAt) {
      const end = entry.stoppedAt ?? entry.alarmAt;
      const actual = el("span", "rhythm-actual");
      actual.classList.toggle("unfinished", !entry.stoppedAt);
      placeBar(actual, entry.phoneDownAt, end, wakeDay);
      track.append(actual);
      phoneDowns.push(minutesIntoNight(entry.phoneDownAt, wakeDay));
      description = `night mode ${formatTime(new Date(entry.phoneDownAt))}` +
        (entry.stoppedAt ? `, up ${formatTime(new Date(entry.stoppedAt))}` : "");
    } else if (entry?.stoppedAt) {
      const wakeMark = el("span", "rhythm-wake");
      wakeMark.style.left = `${chartPercent(entry.stoppedAt, wakeDay)}%`;
      track.append(wakeMark);
      description = `up ${formatTime(new Date(entry.stoppedAt))}`;
    }
    if (entry?.stoppedAt) wakes.push(minutesIntoNight(entry.stoppedAt, wakeDay));

    row.setAttribute("role", "img");
    row.setAttribute("aria-label", `${DAY_NAMES[wakeDay.getDay()]}: ${description}`);
    row.append(el("span", "rhythm-day", DAY_SHORT[wakeDay.getDay()]), track);
    rows.push(row);
  }
  $("rhythm-chart").replaceChildren(...rows);

  const phoneSpread = spread(phoneDowns);
  const wakeSpread = spread(wakes);
  $("rhythm-summary").textContent =
    phoneSpread === null && wakeSpread === null
      ? "Use night mode for a few nights to see how steady your routine is."
      : [
          phoneSpread !== null && `Phone-down time varies by ${formatDuration(phoneSpread)}`,
          wakeSpread !== null && `wake-up by ${formatDuration(wakeSpread)}`,
        ].filter(Boolean).join(" · ") + " this week.";
}

// ---- Schedule tab ----

function updateSchedule(change) {
  change();
  save(SCHEDULE_KEY, schedule);
}

function renderSchedule() {
  const modeButtons = [...$("mode-picker").querySelectorAll("button")];
  modeButtons.forEach((button, i) => {
    const selected = button.dataset.mode === schedule.mode;
    button.setAttribute("aria-checked", String(selected));
    if (selected) $("mode-picker").style.setProperty("--selected", i);
  });
  $("alarms-enabled").checked = schedule.enabled;
  $("schedule-editor").classList.toggle("disabled", !schedule.enabled);
  $("schedule-editor").replaceChildren(
    ...(schedule.mode === "everyday" ? [groupCard("Every day", ALL_DAYS)]
      : schedule.mode === "weekdays"
        ? [groupCard("Monday – Friday", WEEKDAYS), groupCard("Saturday & Sunday", WEEKEND, { canTurnOff: true })]
        : [customTable()]),
  );
}

function sleepText(day) {
  return day.on ? `${formatDuration(sleepMinutes(day))} of sleep` : "No alarm";
}

function switchInput(checked, label) {
  const input = el("input", "switch");
  input.type = "checkbox";
  input.checked = checked;
  input.setAttribute("role", "switch");
  input.setAttribute("aria-label", label);
  return input;
}

function timeInput(value, label) {
  const input = el("input");
  input.type = "time";
  input.required = true;
  input.value = value;
  input.setAttribute("aria-label", label);
  return input;
}

/** One card that edits several days at once (all week, Mon–Fri or the weekend). */
function groupCard(title, dayIndexes, { canTurnOff = false } = {}) {
  const first = () => schedule.days[dayIndexes[0]];
  const card = el("div", "card group-card");
  const head = el("div", "group-head");
  const titles = el("div");
  const detail = el("span", "row-detail");
  titles.append(el("span", "row-title", title), detail);
  head.append(titles);

  const refresh = () => {
    card.classList.toggle("off", !first().on);
    detail.textContent = sleepText(first());
  };
  const set = (change) => {
    updateSchedule(() => updateDays(schedule, dayIndexes, change));
    refresh();
  };

  if (canTurnOff) {
    const toggle = switchInput(first().on, `Alarm on ${title}`);
    toggle.addEventListener("change", () => set({ on: toggle.checked }));
    head.append(toggle);
  }

  const times = el("div", "group-times");
  for (const [key, text] of [["bed", "Bedtime"], ["wake", "Wake up"]]) {
    const field = el("label", "time-field", text);
    const input = timeInput(first()[key], `${title} ${text.toLowerCase()}`);
    input.addEventListener("change", () => input.value && set({ [key]: input.value }));
    field.append(input);
    times.append(field);
  }

  card.append(head, times);
  refresh();
  return card;
}

/** Custom mode: a compact line per day. */
function customTable() {
  const table = el("div", "card custom-table");
  const header = el("div", "custom-row header");
  header.append(el("span"), el("span", "", "Bedtime"), el("span", "", "Wake up"), el("span"));
  table.append(header);

  for (const dayIndex of ALL_DAYS) {
    const day = schedule.days[dayIndex];
    const row = el("div", "custom-row");
    const bed = timeInput(day.bed, `${DAY_NAMES[dayIndex]} bedtime`);
    const wake = timeInput(day.wake, `${DAY_NAMES[dayIndex]} wake up`);
    const toggle = switchInput(day.on, `Alarm on ${DAY_NAMES[dayIndex]}`);
    const refresh = () => {
      bed.disabled = wake.disabled = !day.on;
    };
    bed.addEventListener("change", () => bed.value && updateSchedule(() => (day.bed = bed.value)));
    wake.addEventListener("change", () => wake.value && updateSchedule(() => (day.wake = wake.value)));
    toggle.addEventListener("change", () => {
      updateSchedule(() => (day.on = toggle.checked));
      refresh();
    });
    refresh();
    row.append(el("span", "day-short", DAY_SHORT[dayIndex]), bed, wake, toggle);
    table.append(row);
  }
  return table;
}

// ---- Progress tab ----

function renderProgress() {
  const now = new Date();
  const log = loadLog();
  const streak = currentStreak(log, now);
  showStreak($("streak-count"), $("progress-mascot"), streak, 96);
  renderGoals(log, now);

  // Wake-ups: filled dot = up right away, ring = up late, dashed = nothing logged.
  const wakeUps = log.filter((e) => e.stoppedAt);
  $("history-empty").hidden = wakeUps.length > 0;
  $("week-strip").hidden = wakeUps.length === 0;
  $("week-strip").replaceChildren(
    ...Array.from({ length: 7 }, (_, i) => {
      const day = daysAgo(6 - i, now);
      const entry = wakeUps.findLast((e) => sameDay(new Date(e.alarmAt), day));
      const status = entry ? (wokeOnTime(entry) ? "on-time" : "late") : "none";
      const item = el("li");
      item.classList.toggle("today", sameDay(day, now));
      item.append(el("span", `dot ${status}`), el("span", "", DAY_LETTERS[day.getDay()]));
      item.setAttribute(
        "aria-label",
        `${DAY_NAMES[day.getDay()]}: ${{ "on-time": "up right away", late: "up late", none: "no wake-up" }[status]}`,
      );
      return item;
    }),
  );
  $("history-list").replaceChildren(
    ...wakeUps.slice(-HISTORY_ROWS).reverse().map((entry) => {
      const late = minutesLate(entry);
      const onTime = late <= ON_TIME_MINUTES;
      const who = (entry.ownWake === true ? " · On my own" : entry.ownWake === false ? " · Someone woke me" : "") +
        (entry.manual ? " · Added by you" : entry.edited ? " · Edited" : "");
      const row = historyRow(
        describeDate(new Date(entry.alarmAt), now),
        `Alarm ${formatTime(new Date(entry.alarmAt))} · Up ${formatTime(new Date(entry.stoppedAt))}${who}`,
        entry.stoppedAt < entry.alarmAt - MINUTE
          ? `${Math.round((entry.alarmAt - entry.stoppedAt) / MINUTE)} min early`
          : onTime ? "Right away" : `+${late} min`,
        onTime,
      );
      makeEditable(row, entry);
      return row;
    }),
  );

  renderPhoneDown(log, now);
}

/** The goals for the next alarm (both still to do until it rings). */
function renderGoals(log, now) {
  const next = nextAlarm(schedule, now);
  if (!next) {
    $("streak-goals").replaceChildren(el("li", "goal", "Turn on an alarm to start a streak"));
    return;
  }
  const upBy = new Date(next.getTime() + ON_TIME_MINUTES * MINUTE);
  const goals = [
    { icon: "alarm", text: `Up by ${formatTime(upBy)} ${relativeDay(next, now)}`, state: "todo" },
    { icon: "smile", text: "On your own", state: "todo" },
  ];
  const icons = {
    moon: '<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>',
    alarm: '<circle cx="12" cy="13" r="8"/><path d="M12 9v4l2.5 2.5M5 3 2 6M19 3l3 3"/>',
    smile: '<circle cx="12" cy="12" r="9"/><path d="M8.5 14.5q3.5 3 7 0M9 9.5h.01M15 9.5h.01"/>',
  };
  const marks = { done: "✓", missed: "✕", todo: "" };
  $("streak-goals").replaceChildren(
    ...goals.map((goal) => {
      const item = el("li", `goal ${goal.state}`);
      item.innerHTML = `<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${icons[goal.icon]}</svg>`;
      item.append(el("span", "goal-text", goal.text), el("span", "goal-mark", marks[goal.state]));
      item.setAttribute("aria-label", `${goal.text}: ${{ done: "done", missed: "missed", todo: "to do" }[goal.state]}`);
      return item;
    }),
  );
}

function signedMinutes(minutes, { compact = false } = {}) {
  if (minutes === 0) return "On time";
  const abs = Math.abs(minutes);
  const amount = !compact ? formatDuration(abs)
    : abs < 60 ? `${abs} min`
    : `${Math.floor(abs / 60)}h${abs % 60 ? ` ${abs % 60}m` : ""}`;
  return `${minutes > 0 ? "+" : "−"}${amount}`;
}

/** The middle value, so one unusual night doesn't skew "usually". */
function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

function usualClock(times, wakeDays) {
  const minutes = median(times.map((t, i) => minutesIntoNight(t, wakeDays[i])));
  const date = new Date(wakeDays[0]);
  date.setHours(-CHART_START_HOURS_BEFORE_MIDNIGHT, Math.round(minutes), 0, 0);
  return date;
}

/**
 * Phone down, made easy to read: three headline numbers, then one line per night with
 * the time and how far it was from bedtime (green + early, red − late).
 */
function renderPhoneDown(log, now) {
  const nights = log.filter((e) => e.phoneDownAt && e.bedtimeAt).slice(-HISTORY_ROWS);
  $("phone-empty").hidden = nights.length > 0;
  $("phone-stats").hidden = nights.length === 0;
  if (nights.length === 0) {
    $("phone-list").replaceChildren();
    return;
  }

  const early = nights.map(minutesEarly);
  const usualEarly = Math.round(median(early));
  const onTime = early.filter((m) => m >= 0).length;
  const usual = usualClock(nights.map((e) => e.phoneDownAt), nights.map((e) => new Date(e.alarmAt)));
  const tile = (value, label, tone = "") => {
    const node = el("div", `stat-tile ${tone}`);
    node.append(el("div", "stat-value", value), el("div", "stat-label", label));
    return node;
  };
  $("phone-stats").replaceChildren(
    tile(formatTime(usual), "Usually down"),
    tile(signedMinutes(usualEarly, { compact: true }), "Vs. your goal", usualEarly >= 0 ? "good" : "bad"),
    tile(`${onTime}/${nights.length}`, "Nights on time"),
  );

  $("phone-list").replaceChildren(
    ...[...nights].reverse().map((entry) => {
      const minutes = minutesEarly(entry);
      const row = el("li", `phone-row ${minutes >= 0 ? "good" : "bad"}`);
      const day = el("div", "phone-day");
      day.append(
        el("span", "phone-day-name", DAY_SHORT[new Date(entry.bedtimeAt).getDay()]),
        el("span", "phone-time", formatTime(new Date(entry.phoneDownAt))),
      );
      const track = el("div", "phone-track");
      const bar = el("span", "phone-bar");
      bar.style.width = `${(Math.min(Math.abs(minutes), PHONE_CHART_MAX_MINUTES) / PHONE_CHART_MAX_MINUTES) * 50}%`;
      track.append(bar);
      row.append(day, track, el("span", "phone-minutes", signedMinutes(minutes, { compact: true })));
      row.setAttribute(
        "aria-label",
        `${DAY_NAMES[new Date(entry.bedtimeAt).getDay()]} night: phone down ${formatTime(new Date(entry.phoneDownAt))}, ${minutes >= 0 ? `${minutes} minutes early` : `${-minutes} minutes late`}. Edit`,
      );
      makeEditable(row, entry);
      return row;
    }),
  );
}

/** Tapping a logged night opens it in the form to change or delete it. */
function makeEditable(row, entry) {
  row.classList.add("editable");
  row.tabIndex = 0;
  row.setAttribute("role", "button");
  row.addEventListener("click", () => openLogNight(entry));
  row.addEventListener("keydown", (event) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      openLogNight(entry);
    }
  });
}

function historyRow(title, detail, badgeText, good) {
  const row = el("li");
  const text = el("div");
  text.append(el("div", "history-day", title), el("div", "history-time", detail));
  row.append(text, el("span", `badge ${good ? "on-time" : "late"}`, badgeText));
  return row;
}

// ---- Log a missed night ----

function toDateValue(date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

function atClock(date, hhmm) {
  const [h, m] = hhmm.split(":").map(Number);
  const result = new Date(date);
  result.setHours(h, m, 0, 0);
  return result;
}

// The entry being edited, or null when adding a new night.
let editing = null;

function clockValue(time) {
  const date = new Date(time);
  return `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`;
}

/** Opens the night form: empty for a missed night, or filled in to edit `entry`. */
function openLogNight(entry = null) {
  editing = entry;
  const morning = entry ? new Date(entry.alarmAt) : daysAgo(1);
  const day = schedule.days[morning.getDay()];
  $("log-night-title").textContent = entry ? "Edit night" : "Log a missed night";
  $("log-night-help").textContent = entry
    ? "Change anything that's wrong, or delete this night."
    : "Forgot night mode? Add what happened. This replaces anything already logged for that morning.";
  $("log-date").value = toDateValue(morning);
  $("log-date").max = toDateValue(new Date());
  $("log-alarm").value = entry ? clockValue(entry.alarmAt) : day.wake;
  $("log-phone-down").value = entry?.phoneDownAt ? clockValue(entry.phoneDownAt) : day.bed;
  $("log-woke").value = entry?.stoppedAt ? clockValue(entry.stoppedAt) : day.wake;
  $("log-own").checked = entry ? entry.ownWake !== false : true;
  $("log-delete").hidden = !entry;
  $("log-night").showModal();
}

function deleteLoggedNight() {
  if (!editing || !confirm("Delete this night?")) return;
  save(LOG_KEY, load(LOG_KEY, []).filter((e) => e.alarmAt !== editing.alarmAt));
  editing = null;
  $("log-night").close();
  renderProgress();
}

/**
 * Saves a night entered by hand, as if night mode and the alarm had been used: the alarm
 * and bedtime come from that day's schedule, and a phone-down time in the afternoon or
 * evening is taken as the night before.
 */
function saveLoggedNight() {
  const [y, mo, d] = $("log-date").value.split("-").map(Number);
  const morning = new Date(y, mo - 1, d);
  const alarm = atClock(morning, $("log-alarm").value);
  // Editing a night on the same morning keeps its original bedtime goal.
  const keepBedtime = editing?.bedtimeAt && sameDay(new Date(editing.alarmAt), morning);
  const bedtimeAt = keepBedtime ? editing.bedtimeAt : bedtimeBefore(schedule, alarm).getTime();
  const phoneDown = atClock(morning, $("log-phone-down").value);
  if (phoneDown.getHours() >= 12) phoneDown.setDate(phoneDown.getDate() - 1);
  const log = load(LOG_KEY, []).filter(
    (e) => !sameDay(new Date(e.alarmAt), morning) && e.alarmAt !== editing?.alarmAt,
  );
  log.push({
    alarmAt: alarm.getTime(),
    bedtimeAt,
    phoneDownAt: phoneDown.getTime(),
    stoppedAt: atClock(morning, $("log-woke").value).getTime(),
    ownWake: $("log-own").checked,
    ...(editing && !editing.manual ? { edited: true } : { manual: true }),
  });
  editing = null;
  save(LOG_KEY, log);
  renderProgress();
}

// ---- Settings ----

let previewing = null;
let previewTimer = null;

function saveSettings(change) {
  Object.assign(settings, change);
  save(SETTINGS_KEY, settings);
  renderSettings();
}

function showVolume(percent) {
  const slider = $("alarm-volume");
  slider.value = percent;
  slider.style.setProperty("--fill", `${((percent - slider.min) / (slider.max - slider.min)) * 100}%`);
  $("volume-value").textContent = `${percent}%`;
}

function renderSettings() {
  showVolume(Math.round(settings.volume * 100));
  $("rotate-tones").checked = settings.rotate;
  $("tones-label").textContent = settings.rotate ? "Chimes in rotation" : "Your chime";
  const todays = toneFor(new Date(), { rotate: true }).name;
  $("tone-list").replaceChildren(
    ...TONES.map((tone) => {
      const row = el("li");
      const pick = el("button", "tone-pick");
      pick.setAttribute("role", "radio");
      pick.setAttribute("aria-checked", String(!settings.rotate && settings.tone === tone.name));
      pick.disabled = settings.rotate;
      const name = el("span", "", tone.name);
      if (settings.rotate && tone.name === todays) name.append(el("span", "muted", " · Today"));
      pick.append(name, el("span", "check", "✓"));
      pick.addEventListener("click", () => saveSettings({ tone: tone.name }));

      const playing = previewing === tone.name;
      const play = el("button", "play-button");
      play.setAttribute("aria-label", `${playing ? "Stop" : "Play"} ${tone.name}`);
      play.innerHTML = playing
        ? '<svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor"><rect x="5" y="5" width="14" height="14" rx="2"/></svg>'
        : '<svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>';
      play.addEventListener("click", () => (playing ? stopPreview() : previewTone(tone)));
      row.append(pick, play);
      return row;
    }),
  );
}

function previewTone(tone) {
  clearTimeout(previewTimer);
  chimes.play(tone, { rampSeconds: PREVIEW_MS / 1000, volume: settings.volume });
  previewing = tone.name;
  previewTimer = setTimeout(stopPreview, PREVIEW_MS);
  renderSettings();
}

function previewVolume() {
  clearTimeout(previewTimer);
  chimes.play(toneFor(new Date(), settings), { rampSeconds: 0.05, volume: settings.volume });
  previewing = null;
  previewTimer = setTimeout(() => chimes.stop(), VOLUME_PREVIEW_MS);
}

function stopPreview() {
  if (!previewing) return;
  clearTimeout(previewTimer);
  chimes.stop();
  previewing = null;
  renderSettings();
}

// ---- Navigation ----

let activeTab = "home";
const renderTab = { home: renderHome, schedule: renderSchedule, progress: renderProgress };
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");

/**
 * Switches screens with an animated transition: "tab" cross-fades the page under a fixed
 * header and tab bar, "push"/"pop" slide like iOS navigation, "fade" cross-fades and "dim"
 * fades slowly to black for night mode. Without View Transitions or with Reduce Motion
 * on, screens just switch.
 */
function showScreen(name, transition = "none") {
  const swap = () => {
    for (const id of ALL_SCREENS) $(id).hidden = id !== name;
    const isTab = TAB_SCREENS.includes(name);
    $("app-header").hidden = $("tab-bar").hidden = !isTab;
    for (const button of $("tab-bar").querySelectorAll("button")) {
      if (button.dataset.tab === name) button.setAttribute("aria-current", "page");
      else button.removeAttribute("aria-current");
    }
    window.scrollTo(0, 0);
  };
  if (transition === "none" || reducedMotion.matches || !document.startViewTransition) {
    swap();
    return;
  }
  const root = document.documentElement;
  root.dataset.transition = transition;
  document.startViewTransition(swap).finished.finally(() => delete root.dataset.transition);
}

function goToTab(tab) {
  if (tab === activeTab && !$(tab).hidden) return;
  activeTab = tab;
  renderTab[tab]();
  showScreen(tab, "tab");
}

function openSettings() {
  renderSettings();
  showScreen("settings", "push");
}

function closeSettings() {
  stopPreview();
  renderTab[activeTab]();
  showScreen(activeTab, "pop");
}

// ---- Night mode ----

let armedFor = null;
let tickTimer = null;
let wakeLock = null;
// True during a test alarm from Settings: nothing is logged and it ends back in Settings.
let testRun = false;

async function keepScreenOn() {
  try {
    wakeLock = await navigator.wakeLock?.request("screen");
  } catch {
    wakeLock = null;
  }
}

function startNight() {
  testRun = false;
  chimes.unlock(); // this tap is what allows audio to play hours later
  chimes.holdAwake();
  armedFor = nextAlarm(schedule);
  const bedtime = armedFor && bedtimeBefore(schedule, armedFor);
  if (bedtime && bedtime - Date.now() <= PHONE_DOWN_WINDOW_MS) {
    // Starting night mode is the "phone down" moment for the consistency log.
    updateLogEntry(armedFor.getTime(), { phoneDownAt: Date.now(), bedtimeAt: bedtime.getTime() });
  }
  showScreen("night", "dim");
  keepScreenOn();
  tick();
  tickTimer = setInterval(tick, 1000);
}

/** Night mode with an alarm 10 seconds away, to try the whole morning without logging. */
function startTestAlarm() {
  stopPreview();
  chimes.unlock();
  chimes.holdAwake();
  testRun = true;
  armedFor = new Date(Date.now() + TEST_ALARM_DELAY_MS);
  showScreen("night", "dim");
  tick();
  tickTimer = setInterval(tick, 250);
}

function exitNight() {
  clearInterval(tickTimer);
  armedFor = null;
  chimes.stop();
  chimes.releaseAwake();
  wakeLock?.release();
  wakeLock = null;
  if (testRun) {
    testRun = false;
    renderSettings();
    showScreen("settings", "fade");
    return;
  }
  activeTab = "home";
  renderHome();
  showScreen("home", "fade");
}

function tick() {
  const now = new Date();
  $("night-clock").textContent = formatTime(now);
  if (!armedFor) return;
  if (now >= armedFor) {
    if (now - armedFor < LATE_RING_LIMIT_MS) {
      ring(armedFor);
      return;
    }
    armedFor = nextAlarm(schedule, now);
  }
  $("night-alarm").textContent = !armedFor ? "No alarm set"
    : testRun ? `Test alarm in ${Math.max(1, Math.ceil((armedFor - now) / 1000))} s`
    : `Alarm ${formatTime(armedFor)}`;
  $("wake-early").hidden = !armedFor || armedFor - now > EARLY_WAKE_WINDOW_MS;
}

// The wake lock is dropped whenever the page is hidden; take it back on return.
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible" && !$("night").hidden) {
    keepScreenOn();
    tick();
  }
});

// ---- Ringing & morning check-in ----

let ringingFor = null;

function ring(alarmAt) {
  clearInterval(tickTimer);
  ringingFor = alarmAt;
  const tone = toneFor(alarmAt, settings);
  $("ring-clock").textContent = formatTime(new Date());
  $("ring-tone").textContent = testRun ? `Test alarm · ${tone.name}` : `Today's chime: ${tone.name}`;
  $("ring-main").hidden = false;
  $("check-in").hidden = true;
  $("celebrate").hidden = true;
  showScreen("ringing", "fade");
  chimes.play(tone, { volume: settings.volume });
}

function stopAlarm() {
  chimes.stop();
  if (!testRun) updateLogEntry(ringingFor.getTime(), { stoppedAt: Date.now() });
  $("check-in-greeting").textContent = "Nice, you're up!";
  $("ring-main").hidden = true;
  $("check-in").hidden = false;
}

/** Awake before the alarm: log it as up (which counts as on time) and skip the chime. */
function wakeEarly() {
  clearInterval(tickTimer);
  ringingFor = armedFor;
  if (!testRun) updateLogEntry(ringingFor.getTime(), { stoppedAt: Date.now() });
  $("check-in-greeting").textContent = "Up before your alarm!";
  $("ring-main").hidden = true;
  $("celebrate").hidden = true;
  $("check-in").hidden = false;
  showScreen("ringing", "fade");
}

/** The PRD's success signal: she wakes up on her own, without her mom waking her. */
function checkIn(ownWake) {
  const alarmAt = ringingFor.getTime();
  ringingFor = null;
  if (testRun) {
    celebrateTest();
    return;
  }
  updateLogEntry(alarmAt, { ownWake });
  celebrate(alarmAt);
}

/** The end of a test alarm: shows the celebration screen without touching the streak. */
function celebrateTest() {
  $("check-in").hidden = true;
  $("celebrate").hidden = false;
  $("celebrate-number").hidden = true;
  $("celebrate-title").textContent = "Test complete";
  $("celebrate-detail").textContent = "That's how mornings will go. Nothing was logged.";
  $("celebrate-mascot").innerHTML = lunaSvg(1, 120);
}

/** The morning payoff: the streak grows with a little celebration (or a gentle reset). */
function celebrate(alarmAt) {
  const log = loadLog();
  const streak = currentStreak(log);
  const kept = nightKept(log.find((e) => e.alarmAt === alarmAt));
  $("check-in").hidden = true;
  $("celebrate").hidden = false;
  $("celebrate-number").hidden = !kept;
  $("celebrate-title").textContent = kept ? " night streak!" : "Fresh start";
  $("celebrate-detail").textContent = kept
    ? streak >= 7 ? "A whole week. Luna is glowing!" : "Luna is proud of you. Same time tonight?"
    : "This one didn't count, but tonight is a new chance to start a streak.";
  if (kept) showStreak($("celebrate-number"), $("celebrate-mascot"), streak, 120);
  else {
    save(SEEN_STREAK_KEY, streak);
    $("celebrate-mascot").innerHTML = lunaSvg(0, 120);
  }
}

// ---- Wiring ----

for (const button of $("tab-bar").querySelectorAll("button")) {
  button.addEventListener("click", () => goToTab(button.dataset.tab));
}
for (const button of $("mode-picker").querySelectorAll("button")) {
  button.addEventListener("click", () => {
    if (button.dataset.mode === schedule.mode) return;
    updateSchedule(() => switchMode(schedule, button.dataset.mode));
    renderSchedule();
  });
}
$("wake-card").addEventListener("click", () => goToTab("schedule"));
$("streak-chip").addEventListener("click", () => goToTab("progress"));
$("open-settings").addEventListener("click", openSettings);
$("settings-back").addEventListener("click", closeSettings);
$("rotate-tones").addEventListener("change", () => saveSettings({ rotate: $("rotate-tones").checked }));
$("alarm-volume").addEventListener("input", () => showVolume(Number($("alarm-volume").value)));
$("alarm-volume").addEventListener("change", () => {
  chimes.unlock();
  saveSettings({ volume: Number($("alarm-volume").value) / 100 });
  previewVolume();
});
$("test-alarm").addEventListener("click", startTestAlarm);
$("alarms-enabled").addEventListener("change", () => {
  updateSchedule(() => (schedule.enabled = $("alarms-enabled").checked));
  $("schedule-editor").classList.toggle("disabled", !schedule.enabled);
});
$("start-night").addEventListener("click", startNight);
$("exit-night").addEventListener("click", exitNight);
$("wake-early").addEventListener("click", wakeEarly);
$("stop-alarm").addEventListener("click", stopAlarm);
$("own-yes").addEventListener("click", () => checkIn(true));
$("own-no").addEventListener("click", () => checkIn(false));
$("celebrate-done").addEventListener("click", exitNight);
$("open-log-night").addEventListener("click", () => openLogNight());
$("clear-history").addEventListener("click", () => {
  if (!confirm("Clear all wake-ups, phone-down times and your streak? Your schedule and settings stay.")) return;
  save(LOG_KEY, []);
  save(SEEN_STREAK_KEY, 0);
  $("clear-history").textContent = "History cleared";
});
$("log-cancel").addEventListener("click", () => $("log-night").close());
$("log-delete").addEventListener("click", deleteLoggedNight);
// Picking another morning for a new night fills in that day's scheduled alarm.
$("log-date").addEventListener("change", () => {
  if (editing || !$("log-date").value) return;
  const [y, mo, d] = $("log-date").value.split("-").map(Number);
  $("log-alarm").value = schedule.days[new Date(y, mo - 1, d).getDay()].wake;
});
$("log-night").addEventListener("close", () => (editing = null));
$("log-night-form").addEventListener("submit", saveLoggedNight);

renderHome();
showScreen("home");
setInterval(() => {
  if (!$("home").hidden) renderHome();
}, 30_000);
