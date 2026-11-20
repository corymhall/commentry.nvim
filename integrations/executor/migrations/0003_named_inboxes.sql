ALTER TABLE threads ADD COLUMN inbox TEXT NOT NULL DEFAULT '';
CREATE INDEX threads_inbox ON threads(inbox,position);
ALTER TABLE changes ADD COLUMN inbox TEXT NOT NULL DEFAULT '';
CREATE INDEX changes_inbox ON changes(inbox,sequence);
ALTER TABLE publications RENAME TO publications_previous;
CREATE TABLE publications (
  inbox TEXT NOT NULL DEFAULT '',
  project TEXT NOT NULL,
  request_id TEXT NOT NULL,
  fingerprint TEXT NOT NULL,
  receipt TEXT NOT NULL CHECK(json_valid(receipt)),
  PRIMARY KEY(inbox,project,request_id)
);
INSERT INTO publications(project,request_id,fingerprint,receipt)
  SELECT project,request_id,fingerprint,receipt FROM publications_previous;
DROP TABLE publications_previous;
