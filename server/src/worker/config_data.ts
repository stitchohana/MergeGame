import activities from "../../../config/json_output/activities.json";
import cultivation from "../../../config/json_output/cultivation.json";
import expedition from "../../../config/json_output/expedition.json";
import gameConfig from "../../../config/json_output/game_config.json";
import homeMeridians from "../../../config/json_output/home_meridians.json";
import initialSetup from "../../../config/json_output/initial_setup.json";
import items from "../../../config/json_output/items.json";
import meridians from "../../../config/json_output/meridians.json";
import quests from "../../../config/json_output/quests.json";
import recipes from "../../../config/json_output/recipes.json";
import rewards from "../../../config/json_output/rewards.json";
import shop from "../../../config/json_output/shop.json";
import weeklyTasks from "../../../config/json_output/weekly_tasks.json";
import type { GameConfigTables } from "../engine/config_tables";

export const gameConfigTables = {
	activities,
	cultivation,
	expedition,
	gameConfig,
	homeMeridians,
	initialSetup,
	items,
	meridians,
	quests,
	recipes,
	rewards,
	shop,
	weeklyTasks,
};

export type { GameConfigTables };
