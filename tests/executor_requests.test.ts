import test from "node:test";
import assert from "node:assert/strict";
import { database } from "./executor_sql.ts";
import {
  mutate,
  read,
  type SQL,
  type Source,
  type Queued,
} from "../integrations/executor/inbox.ts";
import {
  readRequests,
  requestContext,
} from "../integrations/executor/requests.ts";

const project = "/request-trials";

function create(sql: SQL, body: string, source?: Source) {
  return mutate(sql, {
    action: "create",
    project,
    title: "Review note",
    body,
    source,
  }) as string;
}

function submit(sql: SQL, thread: string, message?: string) {
  const queued = mutate(sql, { action: "queue", thread, message }) as Queued;
  const claim = mutate(sql, {
    action: "claim",
    project,
    thread,
    queue_id: queued.id,
    author: "codex",
  }) as { claim_id: string };
  return {
    thread,
    claim_ids: [claim.claim_id],
    claim_id: claim.claim_id,
    queue_id: queued.id,
  };
}

test("five copied questions need bounded context without queue histories or read side effects", () => {
  const { sql, close } = database();
  try {
    const items = Array.from({ length: 5 }, (_, i) =>
      submit(
        sql,
        create(sql, `Question ${i}: can you explain this?`, {
          kind: "text",
          lines: [`Copied observation ${i}`],
        }),
      ),
    );
    const revision = read(sql, { action: "revision" });
    const result = readRequests(sql, { project, items });
    assert.equal(result.items.length, 5);
    assert.ok(
      JSON.stringify(result).length < 6000,
      "five short questions should not require full thread records",
    );
    result.items.forEach((item, i) => {
      assert.equal(item.status, "claimed");
      assert.match(item.context!.text, new RegExp(`Question ${i}`));
      assert.match(item.context!.text, new RegExp(`Copied observation ${i}`));
      assert.doesNotMatch(
        item.context!.text,
        /COMMENTRY_THREAD_V1|"queue"\s*:/,
      );
    });
    assert.equal(read(sql, { action: "revision" }), revision);
    const more = submit(sql, create(sql, "Sixth question"));
    const first = readRequests(sql, { project, items: [...items, more] });
    assert.equal(first.items.length, 5);
    assert.notEqual(first.next_cursor, undefined);
    const second = readRequests(sql, {
      project,
      items: [...items, more],
      cursor: first.next_cursor,
    });
    assert.equal(second.items.length, 1);
    assert.equal(second.items[0].thread, more.thread);
  } finally {
    close();
  }
});

test("file context preserves saved excerpt coordinates and excludes later replies", () => {
  const { sql, close } = database();
  try {
    const thread = create(sql, "Explain the selected branch", {
      kind: "file",
      path: "src/example.ts",
      first: 500,
      last: 501,
      lines: Array.from({ length: 1000 }, (_, i) => `line ${i + 1}`),
      git: { head: "saved-revision" },
    });
    const claim = submit(sql, thread);
    mutate(sql, { action: "reply", thread, body: "LATER_NOT_SUBMITTED" });
    const item = readRequests(sql, { project, items: [claim] }).items[0];
    assert.match(item.context!.text, /src\/example\.ts/);
    assert.match(item.context!.text, /line 500/);
    assert.doesNotMatch(
      item.context!.text,
      /line 1\b|line 1000\b|LATER_NOT_SUBMITTED/,
    );
    const source = requestContext(sql, {
      project,
      thread,
      claim_id: claim.claim_id,
      section: "source",
    });
    assert.match(source.context!.text, /"first"\s*:\s*500/);
    assert.match(source.context!.text, /"excerpt_first"\s*:\s*496/);
    assert.doesNotMatch(source.context!.text, /line 1000\b/);
  } finally {
    close();
  }
});

test("followups prioritize the new question while answered history stays available on demand", () => {
  const { sql, close } = database();
  try {
    const thread = create(
      sql,
      "OLD_QUESTION_" + "x".repeat(12000) + "_OLD_TAIL",
    );
    const first = submit(sql, thread);
    mutate(sql, {
      action: "finish",
      thread,
      claim_ids: first.claim_ids,
      author: "codex",
      body: "Prior short answer",
    });
    mutate(sql, {
      action: "reply",
      thread,
      body: "CURRENT_QUESTION: what about retries?",
    });
    const second = submit(sql, thread);
    const item = readRequests(sql, { project, items: [second] }).items[0];
    assert.match(item.context!.text, /CURRENT_QUESTION/);
    assert.match(item.context!.text, /Prior short answer/);
    assert.doesNotMatch(item.context!.text, /_OLD_TAIL/);
    assert.ok(item.context!.text.length <= 2000);
    const history = requestContext(sql, {
      project,
      thread,
      claim_id: second.claim_id,
      section: "history",
      limit: 4000,
    });
    assert.match(history.context!.text, /OLD_QUESTION_/);
    assert.notEqual(history.context!.next_offset, undefined);
  } finally {
    close();
  }
});

test("Unicode request continuation recovers the entire submitted text without dropping characters", () => {
  const { sql, close } = database();
  try {
    const body = "START_" + "🙂界é".repeat(2500) + "_END";
    const claim = submit(sql, create(sql, body));
    let item = readRequests(sql, { project, items: [claim] }).items[0];
    assert.notEqual(item.context!.next_offset, undefined);
    let text = item.context!.text;
    let offset = item.context!.next_offset;
    let pages = 0;
    while (offset !== undefined) {
      assert.ok(++pages < 100, "continuation must advance");
      item = requestContext(sql, {
        project,
        thread: claim.thread,
        claim_id: claim.claim_id,
        section: "request",
        offset,
        limit: 4000,
      });
      assert.ok(Array.from(item.context!.text).length <= 4000);
      text += item.context!.text;
      const next = item.context!.next_offset;
      assert.ok(next === undefined || next > offset);
      offset = next;
    }
    assert.ok(
      text.includes(body),
      "all Unicode body characters must be recoverable across page boundaries",
    );
  } finally {
    close();
  }
});

test("uncertain claims remain answerable while retried completed and wrong-project claims expose no context", () => {
  const { sql, close } = database();
  try {
    const thread = create(sql, "PRIVATE_REQUEST");
    const first = submit(sql, thread);
    mutate(sql, {
      action: "fail",
      thread,
      claim_id: first.claim_id,
      body: "Acceptance unknown",
    });
    let item = readRequests(sql, { project, items: [first] }).items[0];
    assert.equal(item.status, "failed");
    assert.match(item.context!.text, /PRIVATE_REQUEST/);
    const mismatch = readRequests(sql, {
      project: "/different",
      items: [first],
    }).items[0];
    assert.equal(mismatch.status, "project-mismatch");
    assert.equal(mismatch.context, undefined);
    mutate(sql, { action: "retry", thread, queue_id: first.queue_id });
    item = readRequests(sql, { project, items: [first] }).items[0];
    assert.ok(["superseded", "missing"].includes(item.status));
    assert.equal(item.context, undefined);
    const second = mutate(sql, {
      action: "claim",
      project,
      thread,
      author: "codex",
    }) as { claim_id: string };
    mutate(sql, {
      action: "finish",
      thread,
      claim_ids: [second.claim_id],
      author: "codex",
      body: "Done",
    });
    const done = requestContext(sql, {
      project,
      thread,
      claim_id: second.claim_id,
    });
    assert.equal(done.status, "complete");
    assert.equal(done.context, undefined);
  } finally {
    close();
  }
});

test("custom submitted messages remain readable instead of disappearing during protocol parsing", () => {
  const { sql, close } = database();
  try {
    const claim = submit(
      sql,
      create(sql, "Original capture"),
      "Custom raw request. Please inspect the retry.",
    );
    const item = readRequests(sql, { project, items: [claim] }).items[0];
    assert.match(item.context!.text, /Custom raw request/);
  } finally {
    close();
  }
});

test("batch cursors page individual claims even when they belong to the same thread", () => {
  const { sql, close } = database();
  try {
    const thread = create(sql, "Multiple submissions");
    const claims = Array.from({ length: 6 }, (_, i) =>
      submit(sql, thread, `Custom submitted question ${i}`),
    );
    const items = [{ thread, claim_ids: claims.map((c) => c.claim_id) }];
    const first = readRequests(sql, { project, items });
    const second = readRequests(sql, {
      project,
      items,
      cursor: first.next_cursor,
    });
    assert.equal(first.items.length, 5);
    assert.equal(second.items.length, 1);
    assert.equal(second.items[0].claim_id, claims[5].claim_id);
    assert.equal(second.next_cursor, undefined);
    assert.deepEqual(
      [...first.items, ...second.items].map((item) => item.claim_id),
      claims.map((c) => c.claim_id),
    );
  } finally {
    close();
  }
});

test("submitted attachments stay frozen after agents update the current location", () => {
  const { sql, close } = database();
  try {
    const thread = create(sql, "Explain this code location");
    const source = {
      kind: "file",
      path: "handler.ts",
      first: 2,
      last: 2,
      lines: ["before", "ORIGINAL_SELECTED", "after"],
    };
    const attachment = mutate(sql, {
      action: "attach",
      thread,
      source,
      label: "Request handling",
      author: "codex",
    }) as { id: string };
    const claim = submit(sql, thread);
    mutate(sql, {
      action: "attach",
      thread,
      attachment_id: attachment.id,
      source: { ...source, lines: ["before", "LATER_REPLACEMENT", "after"] },
      label: "Updated request handling",
      author: "codex",
    });
    const result = requestContext(sql, {
      project,
      thread,
      claim_id: claim.claim_id,
      section: "attachment",
      id: attachment.id,
    });
    assert.match(result.context!.text, /ORIGINAL_SELECTED/);
    assert.doesNotMatch(result.context!.text, /LATER_REPLACEMENT/);
    const defaultResult = readRequests(sql, { project, items: [claim] })
      .items[0];
    assert.match(defaultResult.context!.text, /Request handling/);
    assert.doesNotMatch(
      defaultResult.context!.text,
      /ORIGINAL_SELECTED|LATER_REPLACEMENT/,
    );
  } finally {
    close();
  }
});

test("an independent title preserves the subject of a short question", () => {
  const { sql, close } = database();
  try {
    const thread = mutate(sql, {
      action: "create",
      project: "/project",
      title: "Rolling timeout changed to the provider default",
      body: "Is this fine?",
    }) as string;
    mutate(sql, { action: "queue", thread });
    const claim = mutate(sql, {
      action: "claim",
      project: "/project",
      thread,
      author: "agent",
    }) as { claim_id: string };
    const result = readRequests(sql, {
      project: "/project",
      items: [{ thread, claim_ids: [claim.claim_id] }],
    });
    assert.match(result.items[0].context!.text, /Rolling timeout changed/);
    assert.match(result.items[0].context!.text, /Is this fine/);
  } finally {
    close();
  }
});
