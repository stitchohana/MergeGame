// --- Game data types ---

export enum TokenType {
  SPIRIT_STONES = 1,  // 灵石
  QI = 2,             // 灵力
  STAMINA = 3,        // 体力
  EXP = 4,            // 经验值
}

export enum ResetCycle {
  NEVER = 0,
  DAILY = 1,
  WEEKLY = 2,
}

export enum ActivityCycle {
  ONCE = 0,
  DAILY = 1,
  WEEKLY = 2,
  MONTHLY = 3,
}

export interface ActivityDef {
  id: number;
  name: string;
  cycle: number;
  start_time?: string;
  end_time?: string;
}

export interface WeeklyTask {
  activity_id: number;
  daily_quests: number[][];
}

export interface ActivityProgress {
  completed: boolean;
  claimed: boolean;
  last_reset?: number;
}

export enum QuestType {
  MERGE = 1,
  SPAWN = 2,
  CRAFT = 3,
  SELL = 4,
  BATTLE_ATTACK = 5,
  BATTLE_CLEAR = 6,
  BREAKTHROUGH = 7,
  ANY_ITEM_CONSUME = 8,
  MERIDIAN_CIRCULATION = 9,
}

export interface PendingReward {
  uid: number;
  id: number;
  name: string;
}

export interface RewardToken {
  token: number;
  amount: number;
}

export interface RewardItem {
  id: number;
  count: number;
}

export interface RewardConfig {
  tokens?: RewardToken[];
  items?: RewardItem[];
}

export interface HomeMeridianStageProgress {
  stage: number;
  lit: boolean[];
  circulation_completed: boolean;
}

export interface QuestProgress {
  current_count: number;
  completed: boolean;
  claimed: boolean;
}

export interface GridItem {
  uid?: number;
  id: number;
  col: number;
  row: number;
  immovable?: boolean;
  craft?: CraftState;
  storage?: StorageData;
  charges?: number;
  last_charge_time?: number;
  atk_base?: number;
}

export interface StorageSlot {
  id: number;
}

export interface StorageData {
  items: StorageSlot[];
  max_slots: number;
}

export interface CraftState {
  _craft_init: boolean;
  _craft_state: number;
  _craft_stored: Record<string, unknown>[];
  _craft_recipe: Record<string, unknown>;
  _craft_progress: number;
  _craft_result_id: number;
  _craft_start_time: number;
}

export interface CultivationData {
  current_level: number;
  current_exp: number;
  total_exp: number;
  current_qi: number;
  max_qi: number;
  last_tick_time: number;
}

export interface GameState {
  grid: GridItem[];
  pouch: number[];
  cultivation: CultivationData;
  stamina: number;
  max_stamina: number;
  last_stamina_tick: number;
  spirit_stones: number;
  version: number;
  board_type?: number;
  uid_counter?: number;
  saved_grid?: GridItem[];
  battle_grid?: GridItem[];
  battle_map_id?: number;
  battle_stage?: number;
  battle_monsters?: BattleMonster[];
  battle_player_hp?: number;
  battle_player_max_hp?: number;
  meridian_circulations?: number;
  meridian_acupoints?: { item_id: number; name: string; count: number; completed: boolean }[];
  meridian_threshold_idx?: number;
  /** Number of fixed orders already revealed in the active threshold's waves. */
  meridian_fixed_order_cursor?: number;
  quest_progress?: Record<number, QuestProgress>;
  quests_initialized?: boolean;
  quest_last_reset?: number;
  pending_rewards: PendingReward[];
  home_meridian_progress?: HomeMeridianStageProgress[];
  /** Production facilities acquired at least once; kept after merge/consumption. */
  unlocked_production_item_ids?: number[];
  activity_progress?: Record<number, ActivityProgress>;
  spawn_seed?: number;
  spawn_sequence?: number;
  spawn_history?: SpawnHistoryEntry[];
  crafted_item_ids: number[];
}

export interface SpawnHistoryEntry {
  request_id: string;
  result: Record<string, unknown>;
}

export interface BattleMonster {
  monster_id: number;
  name: string;
  hp: number;
  max_hp: number;
  atk: number;
  accept_effect_types: number[];
  is_boss?: boolean;
}

export interface User {
  userId: string;
  deviceId: string;
  createdAt: string;
}

export interface LeaderboardEntry {
  userId: string;
  deviceId: string;
  updatedAt: string;
}

// --- Storage interface ---

export interface IStorage {
  findUser(deviceId: string): Promise<User | null>;
  createUser(deviceId: string): Promise<User>;
  loadState(userId: string): Promise<GameState | null>;
  saveState(userId: string, state: GameState): Promise<void>;
  getLeaderboard(limit: number): Promise<LeaderboardEntry[]>;
}
