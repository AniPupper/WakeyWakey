// The sleep schedule: for each day, whether the alarm rings, the wake-up time, and the
// bedtime the night before. Times are "HH:MM" strings, the same format <input type="time"> uses.

export const DAY_NAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

export const WEEKDAYS = [1, 2, 3, 4, 5];
export const WEEKEND = [6, 0];
export const ALL_DAYS = [1, 2, 3, 4, 5, 6, 0];

export function defaultSchedule() {
  return {
    enabled: true,
    // How the schedule is edited: "everyday" (one set of times), "weekdays" (Mon–Fri
    // together, weekend together) or "custom" (each day on its own).
    mode: "weekdays",
    // School days on, weekends off.
    days: DAY_NAMES.map((_, day) => ({ on: day >= 1 && day <= 5, bed: "22:00", wake: "06:30" })),
  };
}

/** Sets the same values on every day in a group, e.g. all weekdays at once. */
export function updateDays(schedule, dayIndexes, change) {
  for (const i of dayIndexes) Object.assign(schedule.days[i], change);
}

/**
 * Switches editing mode, making the days consistent with it. The times carry over from
 * the first weekday that has an alarm, so switching never throws away what was set.
 */
export function switchMode(schedule, mode) {
  const template =
    schedule.days.find((d, i) => d.on && WEEKDAYS.includes(i)) ??
    schedule.days.find((d) => d.on) ??
    schedule.days[1];
  const times = { bed: template.bed, wake: template.wake };
  if (mode === "everyday") updateDays(schedule, ALL_DAYS, { on: true, ...times });
  if (mode === "weekdays") {
    updateDays(schedule, WEEKDAYS, { on: true, ...times });
    const saturday = schedule.days[6];
    updateDays(schedule, WEEKEND, { on: saturday.on, bed: saturday.bed, wake: saturday.wake });
  }
  schedule.mode = mode;
}

/** Schedules saved before modes existed: pick the simplest mode that describes them. */
export function inferMode(schedule) {
  const same = (indexes) =>
    indexes.every((i) => JSON.stringify(schedule.days[i]) === JSON.stringify(schedule.days[indexes[0]]));
  if (same(ALL_DAYS) && schedule.days[0].on) return "everyday";
  if (same(WEEKDAYS) && same(WEEKEND)) return "weekdays";
  return "custom";
}

/** Converts the first version's single-time plan ({ hour, minute, days, enabled }). */
export function fromLegacyPlan(plan) {
  const schedule = defaultSchedule();
  const wake = `${String(plan.hour).padStart(2, "0")}:${String(plan.minute).padStart(2, "0")}`;
  schedule.enabled = plan.enabled;
  schedule.days = schedule.days.map((day, i) => ({ ...day, on: plan.days.includes(i), wake }));
  schedule.mode = inferMode(schedule);
  return schedule;
}

function atTime(date, hhmm) {
  const [h, m] = hhmm.split(":").map(Number);
  const result = new Date(date);
  result.setHours(h, m, 0, 0);
  return result;
}

/** The next time the alarm should ring after `now`, or null if none is scheduled. */
export function nextAlarm(schedule, now = new Date()) {
  if (!schedule.enabled) return null;
  for (let offset = 0; offset <= 7; offset++) {
    const date = new Date(now);
    date.setDate(now.getDate() + offset);
    const day = schedule.days[date.getDay()];
    if (!day.on) continue;
    const alarm = atTime(date, day.wake);
    if (alarm > now) return alarm;
  }
  return null;
}

/** The bedtime leading up to an alarm: the latest moment at that day's bedtime before it. */
export function bedtimeBefore(schedule, alarm) {
  const bed = atTime(alarm, schedule.days[alarm.getDay()].bed);
  if (bed >= alarm) bed.setDate(bed.getDate() - 1);
  return bed;
}

/** Minutes between a day's bedtime and wake-up time. */
export function sleepMinutes(day) {
  const wake = atTime(new Date(2000, 0, 2), day.wake);
  const bed = atTime(wake, day.bed);
  if (bed >= wake) bed.setDate(bed.getDate() - 1);
  return Math.round((wake - bed) / 60_000);
}
