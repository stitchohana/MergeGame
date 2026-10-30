/** Game calendar: Beijing time (UTC+8), with each day starting at resetHour. */
export function getResetPeriod(timestamp: number, resetHour: number) {
  const shifted = new Date(timestamp + (8 - resetHour) * 3600000);
  const day = shifted.toISOString().slice(0, 10);
  const weekday = (shifted.getUTCDay() + 6) % 7; // Monday = 0, Sunday = 6.
  shifted.setUTCDate(shifted.getUTCDate() - weekday);
  return { day, week: shifted.toISOString().slice(0, 10), month: day.slice(0, 7), weekday };
}
