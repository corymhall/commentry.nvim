import test from "node:test";
import assert from "node:assert/strict";
import { database } from "./executor_sql.ts";
import {
  publish,
  publication,
  type Publication,
} from "../integrations/executor/publish.ts";
import {
  mutate,
  read,
  type Thread,
  type Queued,
} from "../integrations/executor/inbox.ts";
import { readRequests } from "../integrations/executor/requests.ts";

test("publish is atomic, survives lost receipts and refuses changed retries without resetting discussion", async () => {
  const { sql, close } = database();
  try {
    const input: Publication = {
      project: "/project",
      request_id: "review-1",
      author: "codex",
      items: [
        {
          key: "concurrency",
          title: "Concurrency doubles",
          body: "Four workers become eight.",
          source: {
            kind: "file",
            path: "worker.ts",
            first: 400,
            last: 400,
            excerpt_first: 400,
            lines: ["concurrency = 8;"],
          },
          comparisons: [
            { key: "output", label: "Worker count", before: "4", after: "8" },
          ],
          primary_comparison: "output",
        },
        {
          key: "logging",
          title: "Logs become JSON",
          body: "One JSON object per line.",
          attachments: [
            {
              label: "Logger",
              source: {
                kind: "file",
                path: "logger.ts",
                first: 900,
                last: 900,
                excerpt_first: 900,
                lines: ["format = 'json';"],
              },
            },
          ],
        },
      ],
    };
    const invalid = structuredClone(input);
    invalid.items[1].attachments![0].source.last = 901;
    await assert.rejects(publish(sql, invalid), /invalid source range/);
    assert.equal(read(sql, { action: "revision" }), 0);
    assert.equal(
      publication(sql, input.project, input.request_id).status,
      "missing",
    );
    const [receipt, concurrent] = await Promise.all([
      publish(sql, input),
      publish(sql, structuredClone(input)),
    ]);
    assert.deepEqual(receipt, concurrent);
    // The CLI RPC envelope adds action; transport metadata is not new content.
    assert.deepEqual(
      await publish(sql, { ...input, action: "publish" } as Publication),
      receipt,
    );
    assert.equal(
      (read(sql, { action: "list", project: input.project }) as Thread[])
        .length,
      2,
    );
    assert.deepEqual(
      publication(sql, input.project, input.request_id),
      receipt,
    );
    const thread = read(sql, {
      action: "read",
      thread: receipt.items[0].thread,
    }) as Thread;
    assert.equal(thread.review?.summary, input.items[0].body);
    assert.equal(thread.primary_comparison, receipt.items[0].comparisons[0].id);
    mutate(sql, {
      action: "reply",
      thread: thread.id,
      body: "Keep four for now.",
    });
    mutate(sql, { action: "resolve", thread: thread.id, resolved: true });
    const before = read(sql, { action: "revision" });
    assert.deepEqual(await publish(sql, input), receipt);
    const changed = structuredClone(input);
    changed.items[0].body = "Changed review";
    await assert.rejects(publish(sql, changed), /different content/);
    assert.equal(read(sql, { action: "revision" }), before);
    const current = read(sql, { action: "read", thread: thread.id }) as Thread;
    assert.equal(current.messages.at(-1)?.body, "Keep four for now.");
    assert.equal(current.resolved, true);
  } finally {
    close();
  }
});

test("high-line excerpts retain absolute coordinates when submitted to an agent", async () => {
  const { sql, close } = database();
  try {
    const source = {
      kind: "file",
      path: "large.ts",
      first: 10001,
      last: 10002,
      excerpt_first: 10000,
      lines: ["// context", "const n = 8;", "return n;", "// after"],
    };
    const receipt = await publish(sql, {
      project: "/project",
      request_id: "large-file",
      author: "codex",
      items: [
        {
          key: "count",
          title: "Eight workers",
          body: "Inspect this selection.",
          source,
        },
      ],
    });
    const id = receipt.items[0].thread;
    mutate(sql, { action: "queue", thread: id });
    const claim = mutate(sql, {
      action: "claim",
      thread: id,
      project: "/project",
      author: "pi",
    }) as { claim_id: string };
    const t = read(sql, { action: "read", thread: id }) as Thread;
    const queued = t.queue[0] as Queued;
    const saved = JSON.parse(
      queued.message.slice(queued.message.indexOf("\n{") + 1),
    );
    assert.deepEqual(saved.source, source);
    const page = readRequests(sql, {
      project: "/project",
      items: [{ thread: id, claim_ids: [claim.claim_id] }],
    });
    assert.match(JSON.stringify(page), /10001/);
    assert.match(JSON.stringify(page), /const n = 8/);
  } finally {
    close();
  }
});
