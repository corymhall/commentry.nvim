import test from "node:test";
import assert from "node:assert/strict";
import { database } from "./executor_sql.ts";
import { DatabaseSync } from "node:sqlite";
import { readFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mutate, read, type Thread } from "../integrations/executor/inbox.ts";
import {
  publish,
  publication,
  type Publication,
} from "../integrations/executor/publish.ts";

test("named inboxes aggregate origins without leaking into project queues or project views", () => {
  const { sql, close } = database();
  try {
    const project = mutate(sql, {
      action: "create",
      project: "/one",
      body: "Project discussion",
    });
    const ids = ["/one", "/two"].map((origin) =>
      mutate(sql, {
        action: "create",
        project: origin,
        inbox: "agent-friction",
        author: "pi",
        body: "A concrete annoyance",
        session: { harness: "pi", id: "session-" + origin },
      }),
    );
    mutate(sql, {
      action: "create",
      project: "/one",
      inbox: "ideas",
      body: "Other inbox",
    });
    const list = (input: object) =>
      read(sql, { action: "list", ...input }) as Thread[];
    assert.deepEqual(
      list({ project: "/one" }).map((t) => t.id),
      [project],
    );
    const [summary] = list({ project: "/one", summary: true });
    // Executor's JSON RPC output rejects properties with undefined values.
    assert.equal(Object.hasOwn(summary, "inbox"), false);
    const shared = list({ inbox: "agent-friction" });
    assert.deepEqual(
      shared.map((t) => t.id),
      ids,
    );
    assert.deepEqual(
      shared.map((t) => t.project),
      ["/one", "/two"],
    );
    assert.equal(shared[1].session_activity![0].session.id, "session-/two");
    assert.equal(list({ inbox: "agent-friction", project: "/two" }).length, 1);
    assert.equal(list({}).length, 4);
    const changes = read(sql, {
      action: "changes",
      inbox: "agent-friction",
    }) as {
      changes: { thread: string; inbox: string }[];
      cursor: number;
      revision: number;
    };
    assert.deepEqual(
      changes.changes.map((c) => c.thread),
      ids,
    );
    assert.ok(changes.changes.every((c) => c.inbox === "agent-friction"));
    assert.equal(changes.cursor, changes.revision);
    const boundary = read(sql, { action: "revision" });
    assert.throws(
      () => mutate(sql, { action: "queue", thread: ids[0] as string }),
      /named inboxes do not support agent delivery/,
    );
    assert.equal(read(sql, { action: "revision" }), boundary);
    assert.deepEqual(
      mutate(sql, { action: "claim", project: "/one", author: "worker" }),
      { empty: true },
    );
    mutate(sql, {
      action: "reply",
      thread: ids[1] as string,
      body: "Recorded",
      author: "You",
    });
    const current = read(sql, {
      action: "read",
      thread: ids[1] as string,
    }) as Thread;
    assert.equal(current.inbox, "agent-friction");
    assert.equal(current.project, "/two");
    assert.equal(current.messages.length, 2);
    for (const inbox of ["../bad", "Bad", " ", "x".repeat(65)]) {
      assert.throws(
        () =>
          mutate(sql, {
            action: "create",
            inbox,
            project: "/one",
            body: "Invalid",
          }),
        /inbox/,
      );
    }
  } finally {
    close();
  }
});

test("publication retry identity includes destination and retains original provenance", async () => {
  const { sql, close } = database();
  try {
    const input: Publication = {
      project: "/one",
      inbox: "agent-friction",
      request_id: "feedback-1",
      author: "pi",
      items: [
        {
          key: "annoyance",
          title: "Slow discovery",
          body: "Discovery took five calls.",
        },
      ],
    };
    const saved = await publish(sql, input);
    assert.deepEqual(await publish(sql, input), saved);
    assert.deepEqual(
      publication(sql, input.project, input.request_id, input.inbox),
      saved,
    );
    await assert.rejects(
      publish(sql, {
        ...input,
        items: [{ ...input.items[0], body: "Changed" }],
      }),
      /different content/,
    );
    const other = await publish(sql, { ...input, inbox: "ideas" });
    const ordinary = await publish(sql, { ...input, inbox: undefined });
    assert.notEqual(other.items[0].thread, saved.items[0].thread);
    assert.notEqual(ordinary.items[0].thread, saved.items[0].thread);
    assert.equal(saved.inbox, "agent-friction");
    assert.equal(
      (read(sql, { action: "read", thread: saved.items[0].thread }) as Thread)
        .project,
      "/one",
    );
  } finally {
    close();
  }
});

test("migration preserves legacy captures, change cursors and publication receipts", () => {
  const directory = mkdtempSync(join(tmpdir(), "commentry-migration-"));
  const filename = join(directory, "inbox.sqlite3");
  const old = new DatabaseSync(filename);
  const state = {
    id: "t-old",
    project: "/old",
    title: "Existing capture",
    source: { kind: "text", lines: ["original capture"] },
    messages: [
      { id: "e-old", author: "Agent", body: "Original", at: "2026-01-01" },
    ],
    comparisons: [],
    queue: [],
    resolved: false,
    unread: true,
    incoming: "e-old",
    created_at: "2026-01-01",
    updated_at: "2026-01-01",
  };
  const receipt = {
    project: "/old",
    request_id: "old-request",
    status: "complete",
    items: [],
  };
  for (const migration of ["0001_inbox.sql", "0002_publications.sql"])
    old.exec(
      readFileSync(
        new URL(
          "../integrations/executor/migrations/" + migration,
          import.meta.url,
        ),
        "utf8",
      ),
    );
  old
    .prepare("INSERT INTO threads(id,project,state) VALUES(?,?,?)")
    .run(state.id, state.project, JSON.stringify(state));
  old
    .prepare("INSERT INTO changes(thread,project,kind,at) VALUES(?,?,?,?)")
    .run(state.id, state.project, "create", state.created_at);
  old
    .prepare(
      "INSERT INTO publications(project,request_id,fingerprint,receipt) VALUES(?,?,?,?)",
    )
    .run(
      "/old",
      "old-request",
      "original-fingerprint",
      JSON.stringify(receipt),
    );
  old.close();
  const { sql, close } = database(filename);
  try {
    assert.deepEqual(read(sql, { action: "read", thread: state.id }), state);
    assert.deepEqual(publication(sql, "/old", "old-request"), receipt);
    assert.equal(read(sql, { action: "revision" }), 1);
    assert.deepEqual(
      read(sql, { action: "list", inbox: "agent-friction" }),
      [],
    );
  } finally {
    close();
    rmSync(directory, { recursive: true, force: true });
  }
});
