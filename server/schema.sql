-- Current schema for a new database. No incremental upgrades or data conversion.

CREATE TABLE IF NOT EXISTS users (
	user_id TEXT PRIMARY KEY,
	device_id TEXT NOT NULL UNIQUE,
	created_at TEXT NOT NULL
) STRICT;

CREATE TABLE IF NOT EXISTS game_states (
	user_id TEXT PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
	state_json TEXT NOT NULL,
	updated_at INTEGER NOT NULL
) STRICT;

CREATE INDEX IF NOT EXISTS idx_game_states_updated_at ON game_states(updated_at DESC);

CREATE TABLE IF NOT EXISTS stair_climb_events (
  event_id TEXT PRIMARY KEY,
  revision INTEGER NOT NULL,
  registry_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS order_duel_events (
  event_id TEXT PRIMARY KEY,
  revision INTEGER NOT NULL,
  registry_json TEXT NOT NULL
);
