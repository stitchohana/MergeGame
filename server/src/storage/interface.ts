// --- Game data types ---

export interface GridItem {
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
  buffs: Record<string, unknown>[];
  last_tick_time: number;
}

export interface GameState {
  score: number;
  high_score: number;
  grid: GridItem[];
  cultivation: CultivationData;
  stamina: number;
  max_stamina: number;
  last_stamina_tick: number;
  spirit_stones: number;
  version: number;
  saved_grid?: GridItem[];
}

export interface User {
  userId: string;
  deviceId: string;
  createdAt: string;
}

export interface LeaderboardEntry {
  userId: string;
  deviceId: string;
  score: number;
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
