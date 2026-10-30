"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.gameConfigTables = void 0;
const activities_json_1 = __importDefault(require("../../../config/json_output/activities.json"));
const secret_realm_json_1 = __importDefault(require("../../../config/json_output/secret_realm.json"));
const golden_finger_json_1 = __importDefault(require("../../../config/json_output/golden_finger.json"));
const stair_climb_json_1 = __importDefault(require("../../../config/json_output/stair_climb.json"));
const order_supply_json_1 = __importDefault(require("../../../config/json_output/order_supply.json"));
const order_duel_json_1 = __importDefault(require("../../../config/json_output/order_duel.json"));
const card_collection_json_1 = __importDefault(require("../../../config/json_output/card_collection.json"));
const battle_pass_json_1 = __importDefault(require("../../../config/json_output/battle_pass.json"));
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
const tokens_json_1 = __importDefault(require("../../../config/json_output/tokens.json"));
exports.gameConfigTables = {
    secretRealm: secret_realm_json_1.default,
    goldenFinger: golden_finger_json_1.default,
    activities: activities_json_1.default,
    stairClimb: stair_climb_json_1.default,
    orderSupply: order_supply_json_1.default,
    orderDuel: order_duel_json_1.default,
    battlePass: battle_pass_json_1.default,
    cardCollection: card_collection_json_1.default,
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
    tokens: tokens_json_1.default,
};
