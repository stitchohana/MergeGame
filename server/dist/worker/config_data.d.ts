import type { GameConfigTables } from "../engine/config_tables";
export declare const gameConfigTables: {
    activities: {
        activities: ({
            id: number;
            name: string;
            cycle: number;
            widget: string;
            start_time?: undefined;
            end_time?: undefined;
        } | {
            id: number;
            name: string;
            cycle: number;
            widget: string;
            start_time: string;
            end_time: string;
        })[];
    };
    cultivation: {
        stages: ({
            name: string;
            exp: number;
            max_qi: number;
            breakthrough_items: {
                item_id: number;
                count: number;
            }[];
            breakthrough_reward_id?: undefined;
        } | {
            name: string;
            exp: number;
            max_qi: number;
            breakthrough_items?: undefined;
            breakthrough_reward_id?: undefined;
        } | {
            name: string;
            exp: number;
            max_qi: number;
            breakthrough_items: {
                item_id: number;
                count: number;
            }[];
            breakthrough_reward_id: number;
        })[];
    };
    expedition: {
        monsters: {
            id: number;
            name: string;
            hp: number;
            atk: number;
            accept_effect_ids: never[];
            loot: number[];
            describe: string;
        }[];
        maps: {
            id: number;
            name: string;
            describe: string;
            stages: ({
                stage: number;
                name: string;
                monsters: {
                    monster_id: number;
                    count: number;
                }[];
                boss?: undefined;
            } | {
                stage: number;
                name: string;
                monsters: {
                    monster_id: number;
                    count: number;
                }[];
                boss: {
                    monster_id: number;
                };
            })[];
        }[];
    };
    gameConfig: {
        stamina: {
            max: number;
            spawn_cost: number;
            regen_interval: number;
            regen_amount: number;
        };
        reset_hour: number;
        craft_speedup_stone_cost_per_minute: number;
        launcher_speedup_stone_cost_per_minute: number;
    };
    homeMeridians: {
        stages: {
            name: string;
            acupoints: number;
            qi_cost: number;
            acupoint_exp: number;
            circulation_reward: {
                tokens: {
                    token: number;
                    amount: number;
                }[];
                items: {
                    id: number;
                    count: number;
                }[];
            };
        }[];
    };
    initialSetup: {
        main: {
            items: {
                id: number;
                col: number;
                row: number;
                immovable: boolean;
            }[];
        };
    };
    items: {
        regular: ({
            id: number;
            level: number;
            name: string;
            icon: string;
            group_id: number;
            describe: string;
            type: number;
            value: number;
            sell_price: number;
            max_charges?: undefined;
            recharge_time?: undefined;
            spawns?: undefined;
        } | {
            id: number;
            level: number;
            name: string;
            icon: string;
            group_id: number;
            describe: string;
            type: number;
            sell_price: number;
            value?: undefined;
            max_charges?: undefined;
            recharge_time?: undefined;
            spawns?: undefined;
        } | {
            id: number;
            level: number;
            name: string;
            icon: string;
            describe: string;
            type: number;
            value: number;
            group_id?: undefined;
            sell_price?: undefined;
            max_charges?: undefined;
            recharge_time?: undefined;
            spawns?: undefined;
        } | {
            id: number;
            level: number;
            name: string;
            icon: string;
            describe: string;
            type: number;
            value: number;
            max_charges: number;
            recharge_time: number;
            spawns: {
                id: number;
                weight: number;
            }[];
            group_id?: undefined;
            sell_price?: undefined;
        })[];
        launcher: {
            id: number;
            level: number;
            name: string;
            icon: string;
            group_id: number;
            max_charges: number;
            recharge_time: number;
            describe: string;
            type: string;
            spawns: {
                id: number;
                weight: number;
            }[];
        }[];
        crafting: {
            id: number;
            level: number;
            name: string;
            group_id: number;
            icon: string;
            describe: string;
            recipes: number[];
            type: number;
        }[];
        effect: ({
            id: number;
            level: number;
            name: string;
            icon: string;
            group_id: number;
            describe: string;
            effect_type: number;
            effect_value: number;
            type: number;
        } | {
            id: number;
            level: number;
            name: string;
            icon: string;
            group_id: null;
            describe: string;
            effect_type: number;
            effect_value: number;
            type: number;
        })[];
    };
    meridians: {
        order_level_ranges: {
            cultivation_min: number;
            cultivation_max: number;
            items_regular: number[];
            items_recipe_product: number[];
        }[];
        thresholds: ({
            stage: number;
            count_min: number;
            count_max: number;
            acupoint_rewards: number;
            order_count: number;
            fixed_orders: {
                item_ids: number[];
            }[];
        } | {
            stage: number;
            count_min: number;
            count_max: number;
            acupoint_rewards: number;
            order_count: number;
            fixed_orders?: undefined;
        })[];
    };
    quests: {
        quests: {
            id: number;
            type: number;
            name: string;
            description: string;
            target_count: number;
            rewards: number;
            auto_reward: boolean;
            reset_cycle: number;
        }[];
    };
    recipes: {
        recipes: {
            id: number;
            name: string;
            ingredients: number[];
            result: number;
            craft_time: number;
        }[];
    };
    rewards: {
        rewards: {
            "1": {
                tokens: {
                    token: number;
                    amount: number;
                }[];
            };
            "2": {
                tokens: {
                    token: number;
                    amount: number;
                }[];
            };
            "219": {
                tokens: {
                    token: number;
                    amount: number;
                }[];
            };
            "301": {
                items: {
                    id: number;
                    count: number;
                }[];
            };
            "302": {
                items: {
                    id: number;
                    count: number;
                }[];
            };
            "303": {
                items: {
                    id: number;
                    count: number;
                }[];
            };
            "304": {
                items: {
                    id: number;
                    count: number;
                }[];
            };
            "305": {
                items: {
                    id: number;
                    count: number;
                }[];
            };
            "306": {
                items: {
                    id: number;
                    count: number;
                }[];
            };
            "307": {
                items: {
                    id: number;
                    count: number;
                }[];
            };
            "308": {
                items: {
                    id: number;
                    count: number;
                }[];
            };
            "309": {
                items: {
                    id: number;
                    count: number;
                }[];
            };
            "310": {
                items: {
                    id: number;
                    count: number;
                }[];
            };
            "311": {
                items: {
                    id: number;
                    count: number;
                }[];
            };
            "312": {
                items: {
                    id: number;
                    count: number;
                }[];
            };
        };
    };
    shop: {
        items: {
            id: number;
            price: number;
        }[];
    };
    weeklyTasks: {
        weekly_tasks: {
            activity_id: number;
            daily_quests: number[][];
        }[];
    };
};
export type { GameConfigTables };
