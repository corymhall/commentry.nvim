import test from "node:test";
import assert from "node:assert/strict";
import { database } from "./executor_sql.ts";
import {
  mutate,
  read,
  type Queued,
  type Thread,
  type Event,
} from "../integrations/executor/inbox.ts";
import { receiveRequests } from "../integrations/executor/requests.ts";

test("fetch acknowledges only returned claims, remains idempotent, and finish retries safely", () => {
  const { sql, close } = database();
  try {
    const project = "/delivery";
    const items = Array.from({ length: 6 }, () => {
      const thread = mutate(sql, {
        action: "create",
        project,
        body: "question",
      }) as string;
      const q = mutate(sql, { action: "queue", thread }) as Queued;
      const c = mutate(sql, {
        action: "claim",
        project,
        thread,
        queue_id: q.id,
        author: "worker",
      }) as { claim_id: string };
      return { thread, claim_ids: [c.claim_id] };
    });
    const page = receiveRequests(sql, { project, items });
    assert.equal(page.items.length, 5);
    const revision = read(sql, { action: "revision" });
    receiveRequests(sql, { project, items });
    assert.equal(read(sql, { action: "revision" }), revision);
    for (let i = 0; i < items.length; i++) {
      const t = read(sql, {
        action: "read",
        thread: items[i].thread,
      }) as Thread;
      assert.equal(!!t.queue[0].acknowledged_at, i < 5);
      assert.equal(t.unread, false);
      assert.equal(t.queue[0].status, "claimed");
    }
    const r = {
      action: "finish",
      thread: items[0].thread,
      claim_ids: items[0].claim_ids,
      author: "pi",
      body: "answer",
      request_id: "answer-1",
    };
    const first = mutate(sql, r) as Event;
    assert.equal((mutate(sql, r) as Event).id, first.id);
    assert.throws(
      () => mutate(sql, { ...r, body: "different" }),
      /different reply/,
    );
    const t = read(sql, { action: "read", thread: r.thread }) as Thread;
    assert.equal(t.messages.length, 2);
    assert.equal(t.resolved, false);
    assert.equal(t.unread, true);
  } finally {
    close();
  }
});

test("ordinary reply retries support arbitrary request IDs without inherited receipts", () => {
  const { sql, close } = database();
  try {
    const thread = mutate(sql, {
      action: "create",
      project: "/reply-retries",
      body: "question",
    }) as string;
    for (const request_id of ["constructor", "__proto__"]) {
      const r = {
        action: "reply",
        thread,
        author: "pi",
        body: "answer",
        request_id,
      };
      const first = mutate(sql, r) as Event;
      assert.equal((mutate(sql, r) as Event).id, first.id);
      assert.throws(
        () => mutate(sql, { ...r, body: "changed" }),
        /different reply/,
      );
    }
    assert.equal(
      (read(sql, { action: "read", thread }) as Thread).messages.length,
      3,
    );
  } finally {
    close();
  }
});

test("handoff preserves snapshot, clears acknowledgement and rejects stale completion", () => {
  const { sql, close } = database();
  try {
    const project = "/handoff";
    const thread = mutate(sql, {
      action: "create",
      project,
      body: "original",
    }) as string;
    const q = mutate(sql, { action: "queue", thread }) as Queued;
    const c = mutate(sql, {
      action: "claim",
      project,
      thread,
      author: "old",
    }) as { claim_id: string };
    receiveRequests(sql, {
      project,
      items: [{ thread, claim_ids: [c.claim_id] }],
    });
    mutate(sql, {
      action: "handoff",
      thread,
      queue_id: q.id,
      claim_id: c.claim_id,
    });
    const t = read(sql, { action: "read", thread }) as Thread;
    assert.equal(t.queue[0].message, q.message);
    assert.equal(t.queue[0].acknowledged_at, undefined);
    assert.throws(
      () =>
        mutate(sql, {
          action: "finish",
          thread,
          claim_ids: [c.claim_id],
          body: "stale",
        }),
      /no longer active/,
    );
    const next = mutate(sql, {
      action: "claim",
      project,
      thread,
      author: "new",
    }) as { claim_id: string };
    assert.notEqual(next.claim_id, c.claim_id);
  } finally {
    close();
  }
});
