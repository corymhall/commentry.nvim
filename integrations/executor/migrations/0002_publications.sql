CREATE TABLE publications (
  project TEXT NOT NULL,
  request_id TEXT NOT NULL,
  fingerprint TEXT NOT NULL,
  receipt TEXT NOT NULL CHECK(json_valid(receipt)),
  PRIMARY KEY(project,request_id)
);
