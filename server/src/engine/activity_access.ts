import type { GameState } from "../storage/interface";

/** Activities and quests unlock after the first breakthrough (练气一层). */
export function activitiesUnlocked(state: GameState): boolean {
  return Number(state.cultivation?.current_level ?? 1) >= 2;
}
