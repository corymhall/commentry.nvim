import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import type { SQL } from "../integrations/executor/inbox.ts";

export function database(filename = ":memory:") {
  const db = new DatabaseSync(filename);
  if (
    !db
      .prepare(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='threads'",
      )
      .get()
  )
    db.exec(
      readFileSync(
        new URL(
          "../integrations/executor/migrations/0001_inbox.sql",
          import.meta.url,
        ),
        "utf8",
      ),
    );
  // Existing trial databases may already have the inbox tables.
  if (
    !db
      .prepare(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='publications'",
      )
      .get()
  )
    db.exec(
      readFileSync(
        new URL(
          "../integrations/executor/migrations/0002_publications.sql",
          import.meta.url,
        ),
        "utf8",
      ),
    );
  if (
    !db
      .prepare("PRAGMA table_info(threads)")
      .all()
      .some((c) => c.name === "inbox")
  )
    db.exec(
      readFileSync(
        new URL(
          "../integrations/executor/migrations/0003_named_inboxes.sql",
          import.meta.url,
        ),
        "utf8",
      ),
    );
  const sql = {
    exec(query: string, ...args: (string | number | null)[]) {
      const statement = db.prepare(query),
        rows = statement.all(...args);
      return {
        toArray: () => rows,
        one: () => {
          if (rows.length !== 1) throw new Error("Expected one row");
          return rows[0];
        },
        columnNames: statement.columns().map((c) => c.name),
        rowsRead: rows.length,
        rowsWritten: db.prepare("SELECT changes() AS n").get()!.n,
        [Symbol.iterator]: () => rows[Symbol.iterator](),
      };
    },
    transaction(work: (tx: unknown) => unknown) {
      db.exec("BEGIN IMMEDIATE");
      try {
        const result = work(sql);
        db.exec("COMMIT");
        return result;
      } catch (error) {
        db.exec("ROLLBACK");
        throw error;
      }
    },
  } as unknown as SQL;
  return { sql, close: () => db.close() };
}
