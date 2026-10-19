CREATE TABLE threads (
  position INTEGER PRIMARY KEY AUTOINCREMENT,
  id TEXT NOT NULL UNIQUE,
  project TEXT NOT NULL,
  state TEXT NOT NULL CHECK(json_valid(state))
);
CREATE INDEX threads_project ON threads(project,position);
CREATE TABLE changes (
  sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  thread TEXT NOT NULL,
  project TEXT NOT NULL,
  kind TEXT NOT NULL,
  at TEXT NOT NULL
);
CREATE INDEX changes_project ON changes(project,sequence);
CREATE TABLE agents (
  project TEXT PRIMARY KEY,
  id TEXT NOT NULL,
  state TEXT NOT NULL CHECK(json_valid(state))
);
