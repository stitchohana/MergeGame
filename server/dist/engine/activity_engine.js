"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ActivityEngine = void 0;
const interface_1 = require("../storage/interface");
class ActivityEngine {
    activities = [];
    weeklyTasks = new Map();
    constructor(activitiesData, weeklyTasksData) {
        this.loadActivities(activitiesData);
        this.loadWeeklyTasks(weeklyTasksData);
    }
    loadActivities(data) {
        try {
            this.activities = data.activities || [];
            console.log(`[activity] Loaded ${this.activities.length} activities`);
        }
        catch { /* optional */ }
    }
    loadWeeklyTasks(data) {
        try {
            for (const wt of data.weekly_tasks || []) {
                this.weeklyTasks.set(wt.activity_id, wt.daily_quests);
            }
            console.log(`[activity] Loaded ${this.weeklyTasks.size} weekly task sets`);
        }
        catch { /* optional */ }
    }
    getActivities() { return this.activities; }
    hasWeeklyTasks(activityId) {
        return this.weeklyTasks.has(activityId);
    }
    getCurrentDay(activityId, resetHour) {
        const quests = this.weeklyTasks.get(activityId);
        if (!quests)
            return 0;
        const rawNow = new Date();
        const now = new Date(rawNow.getTime() - resetHour * 3600000);
        let dow = now.getDay();
        const converted = dow === 0 ? 6 : dow - 1;
        console.log(`[activity] getCurrentDay: local=${rawNow.toLocaleString()} adjusted=${now.toLocaleString()} rawDow=${dow} converted=${converted} resetHour=${resetHour}`);
        return Math.min(converted, quests.length - 1);
    }
    isActive(a) {
        if (a.cycle === interface_1.ActivityCycle.ONCE) {
            const now = Date.now();
            if (a.start_time) {
                const st = new Date(a.start_time).getTime();
                if (now < st)
                    return false;
            }
            if (a.end_time) {
                const et = new Date(a.end_time).getTime();
                if (now > et)
                    return false;
            }
            return true;
        }
        return true; // daily/weekly/monthly always active
    }
    getDailyQuestIds(activityId, day) {
        const quests = this.weeklyTasks.get(activityId);
        if (!quests || day < 0 || day >= quests.length)
            return [];
        return quests[day];
    }
    initProgress(state) {
        state.activity_progress = state.activity_progress || {};
        for (const a of this.activities) {
            if (!state.activity_progress[a.id]) {
                state.activity_progress[a.id] = { completed: false, claimed: false, last_reset: 0 };
            }
        }
    }
    checkAndReset(state, resetHour) {
        const now = Date.now();
        state.activity_progress = state.activity_progress || {};
        for (const a of this.activities) {
            const p = state.activity_progress[a.id];
            if (!p)
                continue;
            if (a.cycle === interface_1.ActivityCycle.ONCE) {
                // Check if one-time activity is active based on start/end time
                const start = a.start_time ? new Date(a.start_time).getTime() : 0;
                const end = a.end_time ? new Date(a.end_time).getTime() : Infinity;
                if (now < start || now > end)
                    continue; // not active
                // One-time: never reset, just check if completed
                continue;
            }
            if (a.cycle === interface_1.ActivityCycle.DAILY) {
                if (!this.isNewPeriod(p.last_reset ?? 0, now, resetHour, "day"))
                    continue;
                p.completed = false;
                p.claimed = false;
                p.last_reset = now;
            }
            else if (a.cycle === interface_1.ActivityCycle.WEEKLY) {
                if (!this.isNewPeriod(p.last_reset ?? 0, now, resetHour, "week"))
                    continue;
                p.completed = false;
                p.claimed = false;
                p.last_reset = now;
            }
            else if (a.cycle === interface_1.ActivityCycle.MONTHLY) {
                if (!this.isNewPeriod(p.last_reset ?? 0, now, resetHour, "month"))
                    continue;
                p.completed = false;
                p.claimed = false;
                p.last_reset = now;
            }
        }
    }
    isNewPeriod(lastTime, now, resetHour, period) {
        if (lastTime <= 0)
            return true;
        const adjustMs = resetHour * 3600000;
        const last = new Date(lastTime - adjustMs);
        const cur = new Date(now - adjustMs);
        if (period === "day") {
            return last.getDate() !== cur.getDate() || last.getMonth() !== cur.getMonth() || last.getFullYear() !== cur.getFullYear();
        }
        if (period === "week") {
            const getWeek = (d) => {
                const jan4 = new Date(d.getFullYear(), 0, 4);
                const jan4Day = jan4.getDay() || 7;
                const days = (d.getTime() - jan4.getTime()) / 86400000;
                return Math.floor((days + jan4Day + 3) / 7);
            };
            return last.getFullYear() !== cur.getFullYear() || getWeek(last) !== getWeek(cur);
        }
        if (period === "month") {
            return last.getMonth() !== cur.getMonth() || last.getFullYear() !== cur.getFullYear();
        }
        return false;
    }
}
exports.ActivityEngine = ActivityEngine;
