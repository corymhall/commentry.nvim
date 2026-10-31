import test from "node:test";
import assert from "node:assert/strict";
import { database } from "./executor_sql.ts";
import {
  mutate,
  read,
  type Thread,
  type Queued,
} from "../integrations/executor/inbox.ts";

test("pending edits use optimistic versions and freeze atomically on queue", () => {
  const { sql, close } = database();
  try {
    const source = {
      kind: "file",
      path: "example.lua",
      first: 1,
      last: 1,
      lines: ["original code"],
    };
    const id = mutate(sql, {
      action: "create",
      project: "/project",
      source,
      body: "Draft",
      pending: true,
    }) as string;
    const get = () => read(sql, { action: "read", thread: id }) as Thread;
    const original = get();
    assert.throws(
      () =>
        mutate(sql, { action: "reply", thread: id, body: "Premature reply" }),
      /before replying/,
    );
    assert.throws(
      () =>
        mutate(sql, {
          action: "edit-pending",
          thread: id,
          author: "agent",
          expected_message: original.messages[0].id,
          body: "Wrong author",
        }),
      /only your unsent/,
    );
    mutate(sql, {
      action: "edit-pending",
      thread: id,
      expected_message: original.messages[0].id,
      body: "Final question\nMore detail",
    });
    assert.throws(
      () =>
        mutate(sql, {
          action: "edit-pending",
          thread: id,
          expected_message: original.messages[0].id,
          body: "Stale edit",
        }),
      /changed/,
    );
    const edited = get();
    assert.equal(edited.title, "Final question");
    assert.equal(edited.pending, true);
    assert.deepEqual(edited.source, source);
    assert.throws(() =>
      mutate(sql, { action: "queue", thread: id, mode: "invalid" }),
    );
    assert.equal(get().pending, true);
    const queued = mutate(sql, { action: "queue", thread: id }) as Queued;
    const snapshot = JSON.parse(
      queued.message.slice(queued.message.indexOf("\n{") + 1),
    );
    assert.equal(snapshot.messages[0].body, "Final question\nMore detail");
    assert.equal(get().pending, false);
    assert.throws(
      () =>
        mutate(sql, {
          action: "edit-pending",
          thread: id,
          expected_message: edited.messages[0].id,
          body: "Too late",
        }),
      /only your unsent/,
    );
    mutate(sql, { action: "cancel", thread: id, queue_id: queued.id });
    assert.throws(
      () =>
        mutate(sql, {
          action: "discard-pending",
          thread: id,
          expected_message: edited.messages[0].id,
        }),
      /only your unsent/,
    );
    mutate(sql, { action: "reply", thread: id, body: "Follow-up" });
    assert.equal(get().messages.length, 2);
    assert.equal(get().messages[0].body, edited.messages[0].body);
  } finally {
    close();
  }
});

test("discarding a pending comment publishes a change without deleting legacy conversations", () => {
  const { sql, close } = database();
  try {
    const id = mutate(sql, {
      action: "create",
      project: "/project",
      body: "Discard",
      pending: true,
    }) as string;
    const original = read(sql, { action: "read", thread: id }) as Thread;
    const cursor = read(sql, { action: "revision" }) as number;
    assert.throws(
      () =>
        mutate(sql, {
          action: "discard-pending",
          thread: id,
          expected_message: "stale",
        }),
      /changed/,
    );
    mutate(sql, {
      action: "discard-pending",
      thread: id,
      expected_message: original.messages[0].id,
    });
    assert.throws(
      () => read(sql, { action: "read", thread: id }),
      /unknown inbox/,
    );
    const changes = read(sql, { action: "changes", cursor }) as {
      changes: { kind: string }[];
    };
    assert.deepEqual(
      changes.changes.map((c) => c.kind),
      ["discard-pending"],
    );
    const legacy = mutate(sql, {
      action: "create",
      project: "/project",
      body: "Existing conversation",
    }) as string;
    assert.throws(
      () =>
        mutate(sql, { action: "edit-pending", thread: legacy, body: "Edit" }),
      /only your unsent/,
    );
  } finally {
    close();
  }
});
