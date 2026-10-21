import test from "node:test";
import assert from "node:assert/strict";
import { database } from "./executor_sql.ts";
import { requestContext } from "../integrations/executor/requests.ts";
import {
  mutate,
  read,
  importThreads,
  selectAgent,
  selectedAgent,
  type Thread,
  type Queued,
} from "../integrations/executor/inbox.ts";

test("claims, replies and read acknowledgements preserve capture and unread versions", () => {
  const { sql, close } = database();
  try {
    const source = {
      kind: "file",
      path: "example.lua",
      first: 2,
      last: 2,
      lines: ["before", "selected", "after"],
    };
    const id = mutate(sql, {
      action: "create",
      project: "/project",
      source,
      body: "Inspect this",
    }) as string;
    const queued = mutate(sql, { action: "queue", thread: id }) as Queued;
    const claim = mutate(sql, {
      action: "claim",
      project: "/project",
      author: "codex",
    }) as { claim_id: string; message: string };
    assert.match(claim.message, /excerpt_first/);
    assert.deepEqual(
      mutate(sql, { action: "claim", project: "/project", author: "pi" }),
      { empty: true },
    );
    const first = mutate(sql, {
      action: "finish",
      thread: id,
      claim_ids: [claim.claim_id],
      author: "codex",
      body: "First answer",
    }) as { id: string };
    mutate(sql, {
      action: "reply",
      thread: id,
      author: "pi",
      body: "Newer answer",
    });
    mutate(sql, {
      action: "read-state",
      thread: id,
      read: true,
      seen: first.id,
    });
    const thread = read(sql, { action: "read", thread: id }) as Thread;
    assert.equal(thread.unread, true);
    assert.equal(thread.resolved, false);
    assert.deepEqual(thread.source, source);
    assert.equal(
      thread.queue.find((q) => q.id === queued.id)!.status,
      "complete",
    );
    assert.throws(() =>
      mutate(sql, {
        action: "finish",
        thread: id,
        claim_ids: [claim.claim_id],
        body: "Duplicate answer",
      }),
    );
    assert.equal(
      (read(sql, { action: "read", thread: id }) as Thread).messages.length,
      3,
    );
  } finally {
    close();
  }
});

test("uncertain delivery suppresses ordinary replay but can accept a late answer or explicit retry", () => {
  const { sql, close } = database();
  try {
    const id = mutate(sql, {
      action: "create",
      project: "/p",
      body: "Task",
    }) as string;
    const q = mutate(sql, { action: "queue", thread: id }) as Queued;
    const claim = mutate(sql, {
      action: "claim",
      project: "/p",
      author: "agent",
    }) as { claim_id: string };
    mutate(sql, {
      action: "fail",
      thread: id,
      claim_id: claim.claim_id,
      body: "Acceptance unknown",
    });
    const duplicate = mutate(sql, { action: "queue", thread: id }) as Queued;
    assert.equal(duplicate.id, q.id);
    assert.equal(duplicate.skipped, true);
    assert.equal(duplicate.delivery_error, "Acceptance unknown");
    mutate(sql, {
      action: "finish",
      thread: id,
      claim_ids: [claim.claim_id],
      author: "codex",
      body: "Accepted after all",
    });
    const next = mutate(sql, { action: "queue", thread: id }) as Queued;
    const again = mutate(sql, {
      action: "claim",
      project: "/p",
      author: "agent",
    }) as { claim_id: string };
    mutate(sql, {
      action: "fail",
      thread: id,
      claim_id: again.claim_id,
      body: "Unknown",
    });
    mutate(sql, { action: "retry", thread: id, queue_id: next.id });
    assert.throws(() =>
      mutate(sql, {
        action: "finish",
        thread: id,
        claim_ids: [again.claim_id],
        body: "Old answer",
      }),
    );
    assert.equal(
      (read(sql, { action: "read", thread: id }) as Thread).queue.at(-1)!
        .status,
      "pending",
    );
  } finally {
    close();
  }
});

test("import preserves identities atomically and selection changes use compare-and-swap", () => {
  const { sql, close } = database();
  try {
    const id = mutate(sql, {
      action: "create",
      project: "/p",
      body: "Existing",
    }) as string;
    const t = read(sql, { action: "read", thread: id }) as Thread;
    const copy = {
      ...t,
      id: "legacy",
      messages: [{ ...t.messages[0], id: "original-message" }],
    };
    assert.deepEqual(importThreads(sql, [copy], []), { imported: 1 });
    assert.deepEqual(read(sql, { action: "read", thread: "legacy" }), copy);
    const rev = read(sql, { action: "revision" });
    assert.throws(() =>
      importThreads(
        sql,
        [
          { ...copy, id: "new" },
          { ...t, title: "Conflict" },
        ],
        [],
      ),
    );
    assert.throws(() => read(sql, { action: "read", thread: "new" }));
    assert.equal(read(sql, { action: "revision" }), rev);
    const a = { id: "session/block/pid", project: "/p", harness: "codex" };
    selectAgent(sql, a, "");
    assert.throws(() => selectAgent(sql, { ...a, id: "other" }, ""));
    assert.deepEqual(selectedAgent(sql, "/p"), a);
  } finally {
    close();
  }
});

test("agents enrich copied conversations without replacing captures or acknowledging new activity", () => {
  const { sql, close } = database();
  try {
    const original = {
      kind: "text",
      lines: ["Copied from chat"],
      origin: "external",
    };
    const id = mutate(sql, {
      action: "create",
      project: "/project",
      source: original,
      body: "Where is this handled?",
    }) as string;
    const source = {
      kind: "file",
      path: "example.lua",
      first: 2,
      last: 2,
      lines: ["before", "selected", "after"],
      git: { head: "abc" },
    };
    const attachment = mutate(sql, {
      action: "attach",
      thread: id,
      author: "codex",
      label: "Implementation",
      source,
    }) as { id: string };
    let t = read(sql, { action: "read", thread: id }) as Thread;
    assert.deepEqual(t.source, original);
    assert.deepEqual(t.attachments?.[0].source, source);
    assert.equal(t.unread, true);
    assert.equal(t.resolved, false);
    const seen = t.incoming;
    mutate(sql, { action: "read-state", thread: id, read: true, seen });
    mutate(sql, {
      action: "attach",
      thread: id,
      author: "codex",
      label: "Updated implementation",
      attachment_id: attachment.id,
      source: { ...source, first: 3, last: 3 },
    });
    t = read(sql, { action: "read", thread: id }) as Thread;
    assert.equal(t.attachments?.length, 1);
    assert.equal(t.attachments?.[0].id, attachment.id);
    assert.equal(t.attachments?.[0].source.first, 3);
    assert.equal(t.unread, true);
    const revision = read(sql, { action: "revision" });
    assert.throws(() =>
      mutate(sql, {
        action: "attach",
        thread: id,
        label: "Missing",
        attachment_id: "unknown",
        source,
      }),
    );
    assert.throws(() =>
      mutate(sql, {
        action: "attach",
        thread: id,
        label: "Escape",
        source: { ...source, path: "../outside" },
      }),
    );
    assert.equal(read(sql, { action: "revision" }), revision);
    const q = mutate(sql, { action: "queue", thread: id }) as Queued;
    assert.match(q.message, new RegExp(attachment.id));
  } finally {
    close();
  }
});

test("review revisions preserve discussion and submitted claims while rejecting stale or foreign edits", () => {
  const { sql, close } = database();
  try {
    const id = mutate(sql, {
      action: "create",
      project: "/p",
      title: "Original question",
      body: "What is wrong?",
    }) as string;
    const before = read(sql, { action: "read", thread: id }) as Thread;
    const comparison = mutate(sql, {
      action: "comparison",
      thread: id,
      author: "codex",
      before: "literal markup",
      after: "property name",
      label: "Generated documentation",
    }) as { id: string };
    const review = mutate(sql, {
      action: "revise",
      thread: id,
      author: "codex",
      title: "References display literal markup",
      body: "The renderer treats references as code.",
      primary_comparison: comparison.id,
    }) as { id: string };
    const queued = mutate(sql, { action: "queue", thread: id }) as Queued;
    const claimed = mutate(sql, {
      action: "claim",
      project: "/p",
      author: "codex",
    }) as { claim_id: string };
    const revision = read(sql, { action: "revision" });
    for (const change of [
      { author: "pi", expected_review: review.id },
      { author: "codex", expected_review: "stale" },
      {
        author: "codex",
        expected_review: review.id,
        primary_comparison: "missing",
      },
    ])
      assert.throws(() =>
        mutate(sql, {
          action: "revise",
          thread: id,
          body: "Overwrite",
          ...change,
        }),
      );
    assert.equal(read(sql, { action: "revision" }), revision);
    mutate(sql, {
      action: "read-state",
      thread: id,
      read: true,
      seen: review.id,
    });
    mutate(sql, {
      action: "revise",
      thread: id,
      author: "codex",
      expected_review: review.id,
      body: "The local fix resolves the references.",
      primary_comparison: "",
    });
    const current = read(sql, { action: "read", thread: id }) as Thread;
    assert.deepEqual(current.messages, before.messages);
    assert.deepEqual(current.source, before.source);
    assert.equal(
      current.review?.summary,
      "The local fix resolves the references.",
    );
    assert.equal(current.review_history?.[0].title, "Original question");
    assert.equal(
      current.review_history?.[1].summary,
      "The renderer treats references as code.",
    );
    assert.equal(current.primary_comparison, undefined);
    assert.equal(current.unread, true);
    assert.equal(current.resolved, false);
    assert.equal(current.queue[0].message, queued.message);
    const submitted = JSON.parse(
      queued.message.slice(queued.message.indexOf("\n{") + 1),
    );
    assert.equal(
      submitted.review.summary,
      "The renderer treats references as code.",
    );
    const context = requestContext(sql, {
      project: "/p",
      thread: id,
      claim_id: claimed.claim_id,
    });
    assert.match(
      context.context!.text,
      /The renderer treats references as code/,
    );
    assert.doesNotMatch(context.context!.text, /The local fix resolves/);
  } finally {
    close();
  }
});

test("replacing a comparison keeps its selection stable and makes the correction unread", () => {
  const { sql, close } = database();
  try {
    const thread = mutate(sql, {
      action: "create",
      project: "/p",
      body: "Review",
    }) as string;
    const original = mutate(sql, {
      action: "comparison",
      thread,
      author: "codex",
      before: "old",
      after: "new",
      label: "Implementation",
    }) as { id: string };
    mutate(sql, {
      action: "revise",
      thread,
      author: "codex",
      title: "Finding",
      body: "Explanation",
      primary_comparison: original.id,
    });
    let current = read(sql, { action: "read", thread }) as Thread;
    mutate(sql, {
      action: "read-state",
      thread,
      read: true,
      seen: current.incoming,
    });
    assert.throws(() =>
      mutate(sql, {
        action: "comparison",
        thread,
        author: "pi",
        comparison_id: original.id,
        before: "wrong",
        after: "wrong",
        label: "Wrong",
      }),
    );
    const replacement = mutate(sql, {
      action: "comparison",
      thread,
      author: "codex",
      comparison_id: original.id,
      before: "literal markup",
      after: "property name",
      label: "User-visible output",
    }) as { id: string };
    current = read(sql, { action: "read", thread }) as Thread;
    assert.equal(replacement.id, original.id);
    assert.equal(current.primary_comparison, original.id);
    assert.equal(current.comparisons.length, 1);
    assert.equal(current.comparisons[0].label, "User-visible output");
    assert.equal(current.comparison_history?.[0].label, "Implementation");
    assert.equal(current.unread, true);
    assert.notEqual(current.incoming, original.id);
  } finally {
    close();
  }
});

test("archiving misleading primary evidence preserves history and rejects foreign or unknown IDs atomically", () => {
  const { sql, close } = database();
  try {
    const thread = mutate(sql, {
      action: "create",
      project: "/p",
      body: "Review this capture",
    }) as string;
    const comparison = mutate(sql, {
      action: "comparison",
      thread,
      author: "codex",
      before: "Illustrative old",
      after: "Illustrative new",
      label: "Unverified example",
    }) as { id: string };
    mutate(sql, {
      action: "revise",
      thread,
      author: "codex",
      title: "Finding",
      body: "Needs verification",
      primary_comparison: comparison.id,
    });
    const queued = mutate(sql, { action: "queue", thread }) as Queued;
    const before = read(sql, { action: "read", thread }) as Thread;
    mutate(sql, {
      action: "read-state",
      thread,
      read: true,
      seen: before.incoming,
    });
    const revision = read(sql, { action: "revision" });
    assert.throws(() =>
      mutate(sql, {
        action: "archive-comparison",
        thread,
        comparison_id: comparison.id,
        author: "pi",
      }),
    );
    assert.throws(() =>
      mutate(sql, {
        action: "archive-comparison",
        thread,
        comparison_id: "missing",
        author: "codex",
      }),
    );
    assert.equal(read(sql, { action: "revision" }), revision);
    const receipt = mutate(sql, {
      action: "archive-comparison",
      thread,
      comparison_id: comparison.id,
      author: "codex",
    }) as { id: string };
    const after = read(sql, { action: "read", thread }) as Thread;
    assert.deepEqual(after.comparisons, []);
    assert.deepEqual(after.comparison_history, before.comparisons);
    assert.equal(after.primary_comparison, undefined);
    assert.equal(after.incoming, receipt.id);
    assert.equal(after.unread, true);
    assert.deepEqual(after.source, before.source);
    assert.deepEqual(after.messages, before.messages);
    assert.equal(after.queue[0].message, queued.message);
    assert.equal(after.resolved, false);
  } finally {
    close();
  }
});
