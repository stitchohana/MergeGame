import type { ActivityDef } from "../storage/interface";

/** Keep source tables separate, and retain the activity_defs wire format. */
export function resolveActivitySettings(activitiesData: any, stairClimb: any, orderSupply: any): { activities: ActivityDef[] } {
  const activities: ActivityDef[] = structuredClone(activitiesData?.activities ?? []);
  for (const [widget, name, data] of [["StairClimb", "stair_climb", stairClimb], ["OrderSupply", "order_supply", orderSupply]] as const) {
    const definitions = activities.filter(activity => activity.widget === widget);
    const rows: Record<string, number>[] = data?.settings ?? [];
    const ids = rows.map(row => row.activity_id);
    if (new Set(ids).size !== ids.length || rows.length !== definitions.length
      || rows.some(row => !definitions.some(activity => activity.id === row.activity_id))) {
      throw new Error(`invalid_${name}_settings`);
    }
    for (const activity of definitions) {
      const row = rows.find(entry => entry.activity_id === activity.id);
      if (!row) throw new Error(`missing_${name}_settings`);
      const { activity_id, ...settings } = row;
      if (widget === "OrderSupply") {
        if (![settings.target_count, settings.reward_count].every(value => Number.isSafeInteger(value) && value > 0)) {
          throw new Error("invalid_order_supply_settings");
        }
        activity.config = settings;
      } else {
        if (settings.group_size !== 20 || ![settings.bot_min_minutes, settings.bot_max_minutes,
          settings.order_points_ratio, settings.bot_order_value].every(value => Number.isFinite(value) && value > 0)
          || settings.bot_max_minutes < settings.bot_min_minutes) throw new Error("invalid_stair_climb_settings");
        const rewards = (data?.rewards ?? []).filter((reward: any) => reward.activity_id === activity_id)
          .map(({ activity_id: _id, ...reward }: any) => reward);
        if (rewards.some((reward: any) => ![reward.min_rank, reward.max_rank, reward.stamina, reward.spirit_stones].every(Number.isSafeInteger)
          || reward.min_rank < 1 || reward.max_rank > 20 || reward.min_rank > reward.max_rank
          || reward.stamina < 0 || reward.spirit_stones < 0)) throw new Error("invalid_stair_climb_rewards");
        activity.config = { ...settings, rewards };
      }
    }
    if (widget === "StairClimb" && (data?.rewards ?? []).some((reward: any) => !ids.includes(reward.activity_id))) {
      throw new Error("invalid_stair_climb_reward_activity");
    }
  }
  return { activities };
}
