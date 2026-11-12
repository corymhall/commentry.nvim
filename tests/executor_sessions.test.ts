import test from "node:test";
import assert from "node:assert/strict";
import { database } from "./executor_sql.ts";
import {
  mutate,
  read,
  type Thread,
  type Session,
} from "../integrations/executor/inbox.ts";
import {
  receiveRequests,
  requestContext,
} from "../integrations/executor/requests.ts";
import { publish } from "../integrations/executor/publish.ts";

const project = "/sessions";
const first: Session = { harness: "pi", id: "session-one" };
const second: Session = { harness: "pi", id: "session-two" };

test("acting sessions survive handoffs and retries without changing captured or human state", () => {
  const { sql, close } = database();
  try {
    const thread = mutate(sql, {
      action: "create",
      project,
      body: "Question",
      session: first,
    }) as string;
    const get = () => read(sql, { action: "read", thread }) as Thread;
    const original = get();
    assert.equal(
      original.session_activity![0].event_id,
      original.messages[0].id,
    );
    mutate(sql, { action: "queue", thread });
    const claim = mutate(sql, {
      action: "claim",
      project,
      author: "delivery-worker",
    }) as { claim_id: string };
    const input = {
      project,
      items: [{ thread, claim_ids: [claim.claim_id] }],
      session: first,
    };
    receiveRequests(sql, input);
    const acknowledged = get().queue[0].acknowledged_at;
    receiveRequests(sql, input);
    assert.equal(
      get().session_activity!.length,
      2,
      "reminders must not add duplicate visits",
    );
    receiveRequests(sql, { ...input, session: second });
    assert.equal(get().queue[0].acknowledged_at, acknowledged);
    assert.equal(get().unread, original.unread);
    assert.equal(get().incoming, original.incoming);
    assert.equal(get().resolved, original.resolved);
    assert.deepEqual(get().source, original.source);
    assert.deepEqual(get().messages, original.messages);
    const finish = {
      action: "finish",
      thread,
      claim_ids: [claim.claim_id],
      author: "pi",
      body: "Answer",
      request_id: "answer",
      session: second,
    };
    const receipt = mutate(sql, finish);
    assert.deepEqual(mutate(sql, { ...finish, session: first }), receipt);
    const current = get();
    assert.deepEqual(
      current.session_activity!.map((a) => [a.session.id, a.action]),
      [
        [first.id, "create"],
        [first.id, "acknowledge"],
        [second.id, "acknowledge"],
        [second.id, "finish"],
      ],
    );
    assert.equal(
      current.session_activity!.at(-1)!.event_id,
      current.messages.at(-1)!.id,
    );
    assert.deepEqual(current.session_activity!.at(-1)!.claim_ids, [
      claim.claim_id,
    ]);
    assert.equal(current.messages.length, 2);
    assert.equal(
      current.queue[0].author,
      "delivery-worker",
      "target worker is not acting session identity",
    );
    assert.equal(current.queue[0].status, "complete");
  } finally {
    close();
  }
});

test("request pagination records only fetched active claims and exposes bounded session archaeology", () => {
  const { sql, close } = database();
  try {
    const items = Array.from({ length: 6 }, () => {
      const thread = mutate(sql, {
        action: "create",
        project,
        body: "Question",
      }) as string;
      mutate(sql, { action: "queue", thread, message: "custom request" });
      const claim = mutate(sql, {
        action: "claim",
        project,
        thread,
        author: "worker",
      }) as { claim_id: string };
      return { thread, claim_ids: [claim.claim_id] };
    });
    receiveRequests(sql, { project, items, session: first });
    const get = (index: number) =>
      read(sql, { action: "read", thread: items[index].thread }) as Thread;
    assert.equal(get(4).session_activity!.length, 1);
    assert.equal(get(5).session_activity, undefined);
    receiveRequests(sql, { project, items, session: first, cursor: 5 });
    assert.equal(get(5).session_activity![0].session.id, first.id);
    const request = {
      project,
      thread: items[0].thread,
      claim_id: items[0].claim_ids[0],
      section: "sessions",
      limit: 80,
    };
    const page = requestContext(sql, request);
    assert.ok(page.sections!.includes("sessions"));
    let text = page.context!.text,
      offset = page.context!.next_offset;
    while (offset !== undefined) {
      const next = requestContext(sql, { ...request, offset });
      text += next.context!.text;
      offset = next.context!.next_offset;
    }
    assert.deepEqual(JSON.parse(text), get(0).session_activity![0]);
    mutate(sql, {
      action: "cancel",
      thread: items[0].thread,
      queue_id: get(0).queue[0].id,
    });
    receiveRequests(sql, { project, items: [items[0]], session: second });
    assert.equal(get(0).session_activity!.length, 1);
  } finally {
    close();
  }
});

test("failed actions and invalid identities never leave session provenance", () => {
  const { sql, close } = database();
  try {
    const thread = mutate(sql, {
      action: "create",
      project,
      body: "Legacy question",
    }) as string;
    const get = () => read(sql, { action: "read", thread }) as Thread;
    assert.equal(get().session_activity, undefined);
    assert.throws(() =>
      mutate(sql, {
        action: "finish",
        thread,
        body: "No claim",
        claim_ids: ["missing"],
        session: first,
      }),
    );
    for (const session of [
      null,
      { harness: "pi", id: "bad\nidentity" },
      { harness: "codex", id: "not-pi" },
      { harness: "pi", id: "x".repeat(257) },
    ]) {
      assert.throws(
        () =>
          mutate(sql, {
            action: "reply",
            thread,
            body: "invalid",
            session: session as Session,
          }),
        /invalid acting session/,
      );
    }
    assert.equal(get().session_activity, undefined);
    assert.equal(get().messages.length, 1);
  } finally {
    close();
  }
});

test("atomic publications retain original session attribution on a cross-session retry", async () => {
  const { sql, close } = database();
  try {
    const input = {
      project,
      request_id: "publication",
      author: "pi",
      session: first,
      items: [{ key: "one", title: "Finding", body: "Explanation" }],
    };
    const receipt = await publish(sql, input);
    assert.deepEqual(
      await publish(sql, { ...input, session: second }),
      receipt,
    );
    const thread = read(sql, {
      action: "read",
      thread: receipt.items[0].thread,
    }) as Thread;
    assert.deepEqual(
      thread.session_activity!.map((a) => a.session.id),
      [first.id, first.id],
    );
  } finally {
    close();
  }
});
