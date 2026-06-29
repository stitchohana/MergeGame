// --- Game data types ---

export interface GridItem {
  uid?: number;
  id: number;
  col: number;
  row: number;
  craft?: CraftState;
  storage?: StorageData;
  charges?: number;
  last_charge_time?: number;
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
  current_realm_id: number;
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
  uid_counter?: number;
  saved_grid?: GridItem[];
  battle_grid?: GridItem[];
  battle_map_id?: number;
  battle_stage?: number;
  battle_monsters?: BattleMonster[];
  meridian_circulations?: number;
  meridian_acupoints?: { item_id: number; name: string; count: number; completed: boolean }[];
  meridian_threshold_idx?: number;
}

export interface BattleMonster {
  monster_id: number;
  name: string;
  hp: number;
  max_hp: number;
  atk: number;
  accept_effect_ids: number[];
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
