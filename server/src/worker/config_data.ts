import activities from "../../../config/json_output/activities.json";
import secretRealm from "../../../config/json_output/secret_realm.json";
import goldenFinger from "../../../config/json_output/golden_finger.json";
import stairClimb from "../../../config/json_output/stair_climb.json";
import orderSupply from "../../../config/json_output/order_supply.json";
import orderDuel from "../../../config/json_output/order_duel.json";
import cardCollection from "../../../config/json_output/card_collection.json";
import battlePass from "../../../config/json_output/battle_pass.json";
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
import tokens from "../../../config/json_output/tokens.json";
import type { GameConfigTables } from "../engine/config_tables";

export const gameConfigTables = {
  secretRealm,
  goldenFinger,
	activities,
	stairClimb,
	orderSupply,
	orderDuel,
	battlePass,
	cardCollection,
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
	tokens,
};

export type { GameConfigTables };
