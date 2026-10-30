"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.activitiesUnlocked = activitiesUnlocked;
/** Activities and quests unlock after the first breakthrough (练气一层). */
function activitiesUnlocked(state) {
    return Number(state.cultivation?.current_level ?? 1) >= 2;
}
