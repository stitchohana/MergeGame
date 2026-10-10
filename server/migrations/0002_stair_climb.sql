CREATE TABLE IF NOT EXISTS stair_climb_events (
  event_id TEXT PRIMARY KEY,
  revision INTEGER NOT NULL,
  registry_json TEXT NOT NULL
);
