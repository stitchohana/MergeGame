import type { GameConfigTables } from "../engine/config_tables";
export declare const gameConfigTables: {
    secretRealm: {
        settings: {
            activity_id: number;
            period: string;
            cols: number;
            rows: number;
            advance: number;
        }[];
        items: {
            id: string;
            chain: string;
            level: number;
            name: string;
            value: number;
        }[];
        layout: {
            col: number;
            row: number;
            fog: boolean;
            id: string;
            immovable: boolean;
            monster: string;
        }[];
        monsters: {
            id: string;
            name: string;
            boss: boolean;
            costs: {
                id: string;
                count: number;
            }[];
            drops: {
                id: string;
                count: number;
                immovable: boolean;
            }[];
        }[];
        stages: {
            boss: string;
            name: string;
        }[];
        merge_drops: {
            min_level: number;
            max_level: number;
            drops: {
                id: string;
                count: number;
                immovable: boolean;
            }[];
        }[];
        order_supply: {
            id: string;
            count: number;
            immovable: boolean;
        }[];
        order_supply_realms: {
            cultivation_min: number;
            cultivation_max: number;
            drops: {
                id: string;
                count: number;
                immovable: boolean;
            }[];
        }[];
    };
    goldenFinger: {
        artifacts: {
            id: string;
            name: string;
            unlock_level: number;
            unlock_label: string;
            daily_free: number;
            daily_buy_limit: number;
            base_cost: number;
            cost_increment: number;
            description: string;
        }[];
        realms: {
            cultivation_min: number;
            cultivation_max: number;
            level_cap: number;
        }[];
        settings: {
            reset_hour: number;
            rewind_seconds: number;
        }[];
    };
    activities: {
        activities: ({
            id: number;
            name: string;
            cycle: number;
            widget: string;
            start_time: string;
            end_time: string;
            enabled?: undefined;
        } | {
            id: number;
            name: string;
            cycle: number;
            widget: string;
            start_time?: undefined;
            end_time?: undefined;
            enabled?: undefined;
        } | {
            id: number;
            name: string;
            cycle: number;
            widget: string;
            enabled: boolean;
            start_time?: undefined;
            end_time?: undefined;
        } | {
            id: number;
            name: string;
            cycle: number;
            widget: string;
            enabled: boolean;
            start_time: string;
            end_time: string;
        })[];
    };
    stairClimb: {
        settings: {
            activity_id: number;
            group_size: number;
            bot_min_minutes: number;
            bot_max_minutes: number;
            order_points_ratio: number;
            bot_order_value: number;
        }[];
        rewards: {
            activity_id: number;
            min_rank: number;
            max_rank: number;
            stamina: number;
            spirit_stones: number;
        }[];
    };
    orderSupply: {
        settings: {
            activity_id: number;
            target_count: number;
            reward_count: number;
        }[];
    };
    orderDuel: {
        settings: {
            activity_id: number;
            target_points: number;
            order_points_ratio: number;
            win_stamina: number;
            win_points: number;
            matchmaking_seconds: number;
            bot_min_seconds: number;
            bot_max_seconds: number;
            bot_order_value: number;
        }[];
        rewards: {
            activity_id: number;
            tier: number;
            required_points: number;
            stamina: number;
            spirit_stones: number;
        }[];
    };
    battlePass: {
        passes: {
            activity_id: number;
            points_token_id: number;
            tiers: ({
                level: number;
                required_points: number;
                free_rewards: {
                    tokens: {
                        token: number;
                        amount: number;
                    }[];
                    items?: undefined;
                };
                premium_rewards: {
                    tokens: {
                        token: number;
                        amount: number;
                    }[];
                    items?: undefined;
                };
            } | {
                level: number;
                required_points: number;
                free_rewards: {
                    items: {
                        id: number;
                        count: number;
                    }[];
                    tokens?: undefined;
                };
                premium_rewards: {
                    items: {
                        id: number;
                        count: number;
                    }[];
                    tokens?: undefined;
                };
            })[];
        }[];
    };
    cardCollection: {
        collections: {
            collection_id: number;
            activity_id: number;
            name: string;
            duplicate_points_by_star: number[];
            exchange_pack_id: number;
            exchange_cost: number;
        }[];
        card_sets: {
            set_id: number;
            collection_id: number;
            name: string;
            rewards: {
                tokens: {
                    token: number;
                    amount: number;
                }[];
            };
        }[];
        cards: {
            card_id: number;
            set_id: number;
            name: string;
            star: number;
            icon: string;
        }[];
        packs: {
            pack_id: number;
            collection_id: number;
            name: string;
            star: number;
            icon: string;
            card_count: number;
            normal_weights: number[];
        }[];
        source_rewards: {
            collection_id: number;
            source_type: string;
            min_value: number;
            pack_id: number;
            count: number;
            enabled: boolean;
        }[];
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
            breakthrough_reward_id: number;
        } | {
            name: string;
            exp: number;
            max_qi: number;
            breakthrough_reward_id: number;
            breakthrough_items?: undefined;
        } | {
            name: string;
            exp: number;
            max_qi: number;
            breakthrough_items?: undefined;
            breakthrough_reward_id?: undefined;
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
            max: string;
            spawn_cost: string;
            regen_interval: string;
            regen_amount: string;
            multiplier_threshold_base: string;
            multiplier_duration: string;
        };
        reset_hour: string;
        craft_speedup_stone_cost_per_minute: string;
        launcher_speedup_stone_cost_per_minute: string;
        battle_pass: {
            premium_unlock_cost: string;
            points_per_value: string;
        };
        orders: {
            recipe_product_probability: string;
        };
        pouch: {
            initial_slots: string;
            unlock_cost_base: string;
            unlock_cost_increment: string;
        };
        resource_purchase: {
            base_cost: string;
            cost_increment: string;
            amount: string;
        };
    };
    homeMeridians: {
        stages: {
            cultivation_level: number;
            name: string;
            acupoints: number;
            qi_cost: number;
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
            effect_type?: undefined;
            effect_value?: undefined;
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
            effect_type?: undefined;
            effect_value?: undefined;
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
            effect_type: number;
            effect_value: number;
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
            "313": {
                items: {
                    id: number;
                    count: number;
                }[];
            };
            "3": {
                items: {
                    id: number;
                    count: number;
                }[];
            };
            "4": {
                items: {
                    id: number;
                    count: number;
                }[];
            };
            "5": {
                items: {
                    id: number;
                    count: number;
                }[];
            };
        };
    };
    shop: {
        refresh_cost: number;
        items: {
            id: number;
            price: number;
        }[];
    };
    weeklyTasks: {
        weekly_tasks: {
            activity_id: number;
            points_per_task: number;
            milestones: ({
                stage: number;
                required_points: number;
                rewards: {
                    tokens: {
                        token: number;
                        amount: number;
                    }[];
                    items?: undefined;
                };
            } | {
                stage: number;
                required_points: number;
                rewards: {
                    items: {
                        id: number;
                        count: number;
                    }[];
                    tokens?: undefined;
                };
            })[];
            daily_quests: number[][];
        }[];
    };
    tokens: {
        tokens: {
            id: number;
            name: string;
            icon: string;
            describe: string;
        }[];
    };
};
export type { GameConfigTables };
