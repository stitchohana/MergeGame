import * as fs from "fs";
import * as path from "path";
import { GameState, ActivityDef, WeeklyTask, ActivityCycle, ActivityProgress } from "../storage/interface";
import { GameEngine } from "./game_engine";

export class ActivityEngine {
  private activities: ActivityDef[] = [];
  private weeklyTasks = new Map<number, number[][]>();

  constructor(configDir: string) {
    this.loadActivities(configDir);
    this.loadWeeklyTasks(configDir);
  }

  private loadActivities(configDir: string): void {
    try {
      const data = JSON.parse(fs.readFileSync(path.join(configDir, "json_output", "activities.json"), "utf-8"));
      this.activities = data.activities || [];
      console.log(`[activity] Loaded ${this.activities.length} activities`);
    } catch { /* optional */ }
  }

  private loadWeeklyTasks(configDir: string): void {
    try {
      const data = JSON.parse(fs.readFileSync(path.join(configDir, "json_output", "weekly_tasks.json"), "utf-8"));
      for (const wt of data.weekly_tasks || []) {
        this.weeklyTasks.set(wt.activity_id, wt.daily_quests);
      }
      console.log(`[activity] Loaded ${this.weeklyTasks.size} weekly task sets`);
    } catch { /* optional */ }
  }

  getActivities(): ActivityDef[] { return this.activities; }

  getCurrentDay(activityId: number, resetHour: number): number {
    const quests = this.weeklyTasks.get(activityId);
    if (!quests) return 0;
    const now = new Date(Date.now() - resetHour * 3600000);
    let dow = now.getUTCDay();
    dow = dow === 0 ? 6 : dow - 1;
    return Math.min(dow, quests.length - 1);
  }

  isActive(a: ActivityDef): boolean {
    if (a.cycle === ActivityCycle.ONCE) {
      const now = Date.now();
      if (a.start_time) {
        const st = new Date(a.start_time).getTime();
        if (now < st) return false;
      }
      if (a.end_time) {
        const et = new Date(a.end_time).getTime();
        if (now > et) return false;
      }
      return true;
    }
    return true; // daily/weekly/monthly always active
  }

  getDailyQuestIds(activityId: number, day: number): number[] {
    const quests = this.weeklyTasks.get(activityId);
    if (!quests || day < 0 || day >= quests.length) return [];
    return quests[day];
  }

  initProgress(state: GameState): void {
    state.activity_progress = state.activity_progress || {};
    for (const a of this.activities) {
      if (!state.activity_progress[a.id]) {
        state.activity_progress[a.id] = { completed: false, claimed: false, last_reset: 0 };
      }
    }
  }

  checkAndReset(state: GameState, resetHour: number): void {
    const now = Date.now();
    state.activity_progress = state.activity_progress || {};
    for (const a of this.activities) {
      const p = state.activity_progress![a.id];
      if (!p) continue;
      if (a.cycle === ActivityCycle.ONCE) {
        // Check if one-time activity is active based on start/end time
        const start = a.start_time ? new Date(a.start_time).getTime() : 0;
        const end = a.end_time ? new Date(a.end_time).getTime() : Infinity;
        if (now < start || now > end) continue; // not active
        // One-time: never reset, just check if completed
        continue;
      }
      if (a.cycle === ActivityCycle.DAILY) {
        if (!this.isNewPeriod(p.last_reset ?? 0, now, resetHour, "day")) continue;
        p.completed = false;
        p.claimed = false;
        p.last_reset = now;
      } else if (a.cycle === ActivityCycle.WEEKLY) {
        if (!this.isNewPeriod(p.last_reset ?? 0, now, resetHour, "week")) continue;
        p.completed = false;
        p.claimed = false;
        p.last_reset = now;
      } else if (a.cycle === ActivityCycle.MONTHLY) {
        if (!this.isNewPeriod(p.last_reset ?? 0, now, resetHour, "month")) continue;
        p.completed = false;
        p.claimed = false;
        p.last_reset = now;
      }
    }
  }

  private isNewPeriod(lastTime: number, now: number, resetHour: number, period: string): boolean {
    if (lastTime <= 0) return true;
    const adjustMs = resetHour * 3600000;
    const last = new Date(lastTime - adjustMs);
    const cur = new Date(now - adjustMs);
    if (period === "day") {
      return last.getUTCDate() !== cur.getUTCDate() || last.getUTCMonth() !== cur.getUTCMonth() || last.getUTCFullYear() !== cur.getUTCFullYear();
    }
    if (period === "week") {
      const getWeek = (d: Date) => {
        const jan4 = new Date(Date.UTC(d.getUTCFullYear(), 0, 4));
        const jan4Day = jan4.getUTCDay() || 7;
        const days = (d.getTime() - jan4.getTime()) / 86400000;
        return Math.floor((days + jan4Day + 3) / 7);
      };
      return last.getUTCFullYear() !== cur.getUTCFullYear() || getWeek(last) !== getWeek(cur);
    }
    if (period === "month") {
      return last.getUTCMonth() !== cur.getUTCMonth() || last.getUTCFullYear() !== cur.getUTCFullYear();
    }
    return false;
  }
}
