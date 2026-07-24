"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.gameConfigTables = void 0;
const activities_json_1 = __importDefault(require("../../../config/json_output/activities.json"));
const cultivation_json_1 = __importDefault(require("../../../config/json_output/cultivation.json"));
const expedition_json_1 = __importDefault(require("../../../config/json_output/expedition.json"));
const game_config_json_1 = __importDefault(require("../../../config/json_output/game_config.json"));
const home_meridians_json_1 = __importDefault(require("../../../config/json_output/home_meridians.json"));
const initial_setup_json_1 = __importDefault(require("../../../config/json_output/initial_setup.json"));
const items_json_1 = __importDefault(require("../../../config/json_output/items.json"));
const meridians_json_1 = __importDefault(require("../../../config/json_output/meridians.json"));
const quests_json_1 = __importDefault(require("../../../config/json_output/quests.json"));
const recipes_json_1 = __importDefault(require("../../../config/json_output/recipes.json"));
const rewards_json_1 = __importDefault(require("../../../config/json_output/rewards.json"));
const shop_json_1 = __importDefault(require("../../../config/json_output/shop.json"));
const weekly_tasks_json_1 = __importDefault(require("../../../config/json_output/weekly_tasks.json"));
exports.gameConfigTables = {
    activities: activities_json_1.default,
    cultivation: cultivation_json_1.default,
    expedition: expedition_json_1.default,
    gameConfig: game_config_json_1.default,
    homeMeridians: home_meridians_json_1.default,
    initialSetup: initial_setup_json_1.default,
    items: items_json_1.default,
    meridians: meridians_json_1.default,
    quests: quests_json_1.default,
    recipes: recipes_json_1.default,
    rewards: rewards_json_1.default,
    shop: shop_json_1.default,
    weeklyTasks: weekly_tasks_json_1.default,
};
