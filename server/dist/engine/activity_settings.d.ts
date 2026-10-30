import type { ActivityDef } from "../storage/interface";
/** Keep source tables separate, and retain the activity_defs wire format. */
export declare function resolveActivitySettings(activitiesData: any, stairClimb: any, orderSupply: any): {
    activities: ActivityDef[];
};
