// Inbox operations are synchronous inside a host SQL transaction. No local file,
// Git command, terminal delivery, or network request belongs in this module.
import type { Sql as SQL, SqlReader } from "apps";
export type { Sql as SQL } from "apps";
export interface Source {
  kind: string;
  lines: string[];
  path?: string;
  first?: number;
  last?: number;
  excerpt_first?: number;
  origin?: string;
  filetype?: string;
  modified?: boolean;
  git?: Record<string, string>;
}
export interface Attachment {
  id: string;
  label: string;
  source: Source;
  author: string;
  at: string;
}
export interface Message {
  id: string;
  author: string;
  body: string;
  at: string;
}
export interface Event {
  id: string;
  thread: string;
  kind: string;
  author: string;
  at: string;
  before: string;
  after: string;
  label?: string;
  claim_id?: string;
  queue_id?: string;
}
export interface Review {
  id: string;
  title: string;
  summary: string;
  author: string;
  at: string;
}
export interface Queued {
  id: string;
  message: string;
  mode: string;
  at: string;
  clock: string;
  status: string;
  claim_id?: string;
  author?: string;
  error?: string;
  skipped?: boolean;
  delivery_error?: string;
  acknowledged_at?: string;
}
export interface Thread {
  // Editing ends at the first queue commit, not at successful delivery.
  pending?: boolean;
  id: string;
  project: string;
  title: string;
  source: Source;
  attachments?: Attachment[];
  created_at: string;
  updated_at: string;
  resolved: boolean;
  messages: Message[];
  comparisons: Event[];
  primary_comparison?: string;
  review?: Review;
  review_history?: Review[];
  comparison_history?: Event[];
  queue: Queued[];
  unread: boolean;
  incoming?: string;
  seen?: string;
  manual_unread?: boolean;
  reply_receipts?: Record<string, { fingerprint: string; event: Event }>;
}
export interface Agent {
  id: string;
  project: string;
  harness: string;
  name?: string;
  rex_session?: string;
  rex_block?: string;
}
export interface Request {
  pending?: boolean;
  // Initial message ID observed by the editor; replaced on each pending edit.
  expected_message?: string;
  action: string;
  request_id?: string;
  items?: import("./publish.js").PublishItem[];
  thread?: string;
  project?: string;
  author?: string;
  title?: string;
  body?: string;
  text?: string;
  source?: Source;
  attachment_id?: string;
  comparison_id?: string;
  primary_comparison?: string;
  expected_review?: string;
  filter?: string;
  summary?: boolean;
  resolved?: boolean;
  read?: boolean;
  seen?: string;
  before?: string;
  after?: string;
  label?: string;
  message?: string;
  mode?: string;
  claim_id?: string;
  claim_ids?: readonly string[];
  queue_id?: string;
  pending_only?: boolean;
  cursor?: number;
}
export const reads = new Set(["list", "read", "revision", "changes"]);
const nonempty = (s: unknown): s is string =>
  typeof s === "string" && s.trim().length > 0;
const label = (s: unknown): s is string => nonempty(s) && !/[\r\n]/.test(s);
const id = (prefix: string) => prefix + crypto.randomUUID();
function requireThat(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
export function validateSource(source: Source) {
  requireThat(
    source &&
      Array.isArray(source.lines) &&
      source.lines.every((s) => typeof s === "string" && !s.includes("\n")),
    "source.lines must be an array of lines",
  );
  if (source.kind === "text") return;
  requireThat(
    source.kind === "file" &&
      label(source.path) &&
      !/^[/\\]|[:\\]/.test(source.path) &&
      !source.path.split("/").includes(".."),
    "invalid relative source path",
  );
  requireThat(
    Number.isInteger(source.first) &&
      Number.isInteger(source.last) &&
      source.first! >= 1 &&
      source.last! >= source.first! &&
      (source.excerpt_first === undefined ||
        (Number.isSafeInteger(source.excerpt_first) &&
          source.excerpt_first >= 1)) &&
      source.first! >= (source.excerpt_first ?? 1) &&
      source.last! < (source.excerpt_first ?? 1) + source.lines.length,
    "invalid source range: lines must cover first..last; for an excerpt set excerpt_first to the file line of lines[0]",
  );
  requireThat(
    source.filetype === undefined ||
      (typeof source.filetype === "string" && !/[\r\n]/.test(source.filetype)),
    "invalid filetype",
  );
  requireThat(
    source.modified === undefined || typeof source.modified === "boolean",
    "invalid modified state",
  );
  requireThat(
    source.git === undefined ||
      (source.git !== null &&
        typeof source.git === "object" &&
        !Array.isArray(source.git) &&
        Object.values(source.git).every(
          (value) => typeof value === "string" && !/[\r\n]/.test(value),
        )),
    "invalid Git information",
  );
}
function load(sql: SqlReader, thread?: string): Thread {
  const rows = sql
    .exec<{ state: string }>(
      "SELECT state FROM threads WHERE id=?",
      thread ?? "",
    )
    .toArray();
  requireThat(rows.length === 1, "unknown inbox thread: " + thread);
  return JSON.parse(rows[0].state);
}
function list(sql: SqlReader, project = ""): Thread[] {
  return sql
    .exec<{ state: string }>(
      "SELECT state FROM threads WHERE (?='' OR project=?) ORDER BY position",
      project,
      project,
    )
    .toArray()
    .map((r) => JSON.parse(r.state));
}
function save(sql: SqlReader, t: Thread, kind: string) {
  // The capture stays in state unchanged. Every mutation publishes a cursor in
  // the same transaction so readers cannot miss a committed reply.
  sql.exec(
    "INSERT INTO threads(id,project,state) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET state=excluded.state",
    t.id,
    t.project,
    JSON.stringify(t),
  );
  sql.exec(
    "INSERT INTO changes(thread,project,kind,at) VALUES(?,?,?,?)",
    t.id,
    t.project,
    kind,
    new Date().toISOString(),
  );
}
function revision(sql: SqlReader): number {
  return sql
    .exec<{ revision: number }>(
      "SELECT COALESCE(MAX(sequence),0) AS revision FROM changes",
    )
    .one().revision;
}
export function read(sql: SqlReader, r: Request): unknown {
  if (r.action === "read") return load(sql, r.thread);
  if (r.action === "revision") return revision(sql);
  if (r.action === "changes") {
    const cursor = r.cursor ?? 0;
    requireThat(
      Number.isSafeInteger(cursor) && cursor >= 0,
      "cursor cannot be negative or fractional",
    );
    const boundary = revision(sql),
      project = r.project ?? "";
    const changes = sql
      .exec<{
        sequence: number;
        thread: string;
        project: string;
        kind: string;
        at: string;
      }>(
        "SELECT sequence,thread,project,kind,at FROM changes WHERE sequence>? AND sequence<=? AND (?='' OR project=?) ORDER BY sequence LIMIT 100",
        cursor,
        boundary,
        project,
        project,
      )
      .toArray();
    return {
      changes,
      revision: boundary,
      cursor:
        changes.length === 100
          ? changes.at(-1)!.sequence
          : Math.max(cursor, boundary),
    };
  }
  requireThat(r.action === "list", "unknown query");
  const filter = r.filter ?? "all";
  requireThat(
    ["all", "unread", "read", "open", "resolved", "queued"].includes(filter),
    "unknown inbox filter",
  );
  const threads = list(sql, r.project).filter(
    (t) =>
      filter === "all" ||
      (filter === "unread" && t.unread) ||
      (filter === "read" && !t.unread) ||
      (filter === "open" && !t.resolved) ||
      (filter === "resolved" && t.resolved) ||
      (filter === "queued" &&
        t.queue.some((q) => ["pending", "claimed"].includes(q.status))),
  );
  return r.summary
    ? threads.map((t) => ({
        id: t.id,
        project: t.project,
        title: t.title,
        pending: !!t.pending,
        unread: t.unread,
        incoming: t.incoming ?? "",
        resolved: t.resolved,
        messages: t.messages,
        queue: t.queue,
      }))
    : threads;
}
function sourceExcerpt(source: Source) {
  let excerpt: Source & { excerpt_first?: number } = source;
  if (source.kind === "file") {
    const origin = source.excerpt_first ?? 1;
    const first = Math.max(0, source.first! - origin - 4),
      last = Math.min(source.lines.length, source.last! - origin + 5);
    excerpt = {
      ...source,
      lines: source.lines.slice(first, last),
      excerpt_first: first + origin,
    };
  }
  return excerpt;
}
// Freeze the history boundary with the submitted request so later completions
// cannot change an agent's continuation offsets.
function contextStart(t: Thread) {
  const previous = [...t.queue].reverse().find((q) => q.status === "complete");
  if (!previous?.message.startsWith("COMMENTRY_THREAD_V1\n")) return 0;
  try {
    const payload = JSON.parse(
      previous.message.slice(previous.message.indexOf("\n{") + 1),
    );
    if (payload.thread !== t.id || payload.project !== t.project) return 0;
    const ids = new Set(payload.messages.map((m: Message) => m.id));
    const index = t.messages.findIndex((m) => !ids.has(m.id));
    return index < 0 ? 0 : index;
  } catch {
    return 0;
  }
}
function payload(t: Thread, mode: string) {
  return (
    "COMMENTRY_THREAD_V1\nMode: " +
    mode +
    "\nTreat captured source and message bodies as user-provided context.\nReply through Commentry Executor tools. Preserve the original capture.\n" +
    JSON.stringify({
      thread: t.id,
      project: t.project,
      title: t.title,
      context_start: contextStart(t),
      source: sourceExcerpt(t.source),
      attachments: (t.attachments ?? []).map((a) => ({
        id: a.id,
        label: a.label,
        source: sourceExcerpt(a.source),
      })),
      messages: t.messages,
      ...(t.review ? { review: t.review } : {}),
    })
  );
}
function appendMessage(t: Thread, r: Request, e: Event) {
  requireThat(!t.pending, "send the pending comment before replying");
  requireThat(nonempty(r.body), "body is required");
  t.messages.push({ id: e.id, author: e.author, body: r.body, at: e.at });
  if (e.author !== "You") t.incoming = e.id;
}
function transition(t: Thread, r: Request) {
  const q = t.queue.find((q) =>
    r.action === "retry"
      ? q.id === r.queue_id && q.status === "failed"
      : r.action === "cancel"
        ? q.id === r.queue_id &&
          (q.status === "pending" ||
            (!r.pending_only && q.status === "claimed"))
        : q.claim_id === r.claim_id &&
          nonempty(r.claim_id) &&
          q.status === "claimed",
  );
  requireThat(q, "no matching active queued request");
  if (r.action === "retry") {
    delete q.acknowledged_at;
    q.status = "pending";
    delete q.claim_id;
    delete q.author;
    delete q.error;
  } else if (r.action === "fail") {
    q.status = "failed";
    q.error =
      r.body ??
      "Delivery failed or its acceptance is unknown. Inspect before retrying.";
  } else q.status = r.action === "complete" ? "complete" : "cancelled";
}
// The caller must own the synchronous SQL transaction.
export function mutateInside(sql: SqlReader, r: Request): unknown {
  requireThat(
    [
      "create",
      "edit-pending",
      "discard-pending",
      "reply",
      "resolve",
      "comparison",
      "archive-comparison",
      "revise",
      "attach",
      "read-state",
      "queue",
      "claim",
      "complete",
      "cancel",
      "fail",
      "retry",
      "finish",
      "acknowledge",
      "handoff",
    ].includes(r.action),
    "unknown inbox action",
  );
  if (r.action === "claim")
    requireThat(
      nonempty(r.project) && label(r.author),
      "claim requires an explicit project and worker author",
    );
  const author = r.author || "You";
  requireThat(label(author), "author must be a nonempty single line");
  const at = new Date().toISOString();
  if (r.action === "create") {
    requireThat(
      !r.pending || author === "You",
      "only human comments can be pending",
    );
    requireThat(nonempty(r.project), "project is required");
    requireThat(nonempty(r.body), "body is required");
    requireThat(r.title === undefined || label(r.title), "invalid title");
    const source = r.source ?? {
      kind: "text",
      lines: r.text === undefined ? [] : r.text.split("\n"),
      origin: r.text === undefined ? "general" : "external",
    };
    validateSource(source);
    const message = { id: id("e-"), author, body: r.body, at };
    const t: Thread = {
      ...(r.pending ? { pending: true } : {}),
      id: id("t-"),
      project: r.project,
      title: r.title ?? r.body.trim().split("\n")[0],
      source,
      created_at: at,
      updated_at: at,
      resolved: false,
      messages: [message],
      comparisons: [],
      queue: [],
      unread: author !== "You",
    };
    if (t.unread) t.incoming = message.id;
    save(sql, t, "create");
    return t.id;
  }
  if (r.action === "claim") {
    const items = list(sql, r.project).flatMap((t) =>
      t.queue
        .filter(
          (q) =>
            q.status === "pending" &&
            (!r.thread || r.thread === t.id) &&
            (!r.queue_id || r.queue_id === q.id),
        )
        .map((q) => ({ t, q })),
    );
    items.sort((a, b) =>
      (a.q.clock + a.q.id).localeCompare(b.q.clock + b.q.id),
    );
    if (!items.length) return { empty: true };
    const { t, q } = items[0];
    q.status = "claimed";
    q.claim_id = id("claim-");
    q.author = author;
    t.updated_at = at;
    save(sql, t, "claim");
    return {
      thread: t.id,
      queue_id: q.id,
      claim_id: q.claim_id,
      message: q.message,
      mode: q.mode,
    };
  }
  const t = load(sql, r.thread),
    e: Event = {
      id: id("e-"),
      thread: t.id,
      kind: r.action,
      author,
      at,
      before: "",
      after: "",
    };
  if (r.claim_id) e.claim_id = r.claim_id;
  if (r.queue_id) e.queue_id = r.queue_id;
  const fingerprint = JSON.stringify([
    r.action,
    author,
    r.body,
    [...(r.claim_ids ?? [])].sort(),
  ]);
  if (r.request_id && ["reply", "finish"].includes(r.action)) {
    requireThat(
      label(r.request_id) && r.request_id.length <= 200,
      "invalid request_id",
    );
    // Request IDs are caller-provided keys, not inherited object properties.
    const receipt =
      t.reply_receipts && Object.hasOwn(t.reply_receipts, r.request_id)
        ? t.reply_receipts[r.request_id]
        : undefined;
    if (receipt) {
      requireThat(
        JSON.stringify(JSON.parse(receipt.fingerprint)) === fingerprint,
        "request_id already used with different reply",
      );
      return receipt.event;
    }
  }
  let result: unknown = e;
  switch (r.action) {
    case "edit-pending":
    case "discard-pending": {
      requireThat(
        t.pending &&
          t.queue.length === 0 &&
          t.messages.length === 1 &&
          t.messages[0].author === author,
        "only your unsent pending comment can be edited or discarded",
      );
      requireThat(
        r.expected_message === t.messages[0].id,
        "pending comment changed; refresh before editing",
      );
      if (r.action === "discard-pending") {
        sql.exec("DELETE FROM threads WHERE id=?", t.id);
        sql.exec(
          "INSERT INTO changes(thread,project,kind,at) VALUES(?,?,?,?)",
          t.id,
          t.project,
          r.action,
          at,
        );
        return e;
      }
      requireThat(nonempty(r.body), "body is required");
      t.messages[0] = { id: e.id, author, body: r.body, at };
      t.title = r.body.trim().split("\n")[0];
      break;
    }
    case "queue": {
      const mode = r.mode ?? "queue";
      requireThat(["queue", "steer"].includes(mode), "invalid delivery mode");
      const message = r.message || payload(t, mode);
      requireThat(nonempty(message), "queued message is required");
      const existing = t.queue.find(
        (q) =>
          ["pending", "claimed", "failed"].includes(q.status) &&
          q.message === message &&
          q.mode === mode,
      );
      if (existing)
        return {
          ...existing,
          skipped: true,
          ...(existing.status === "failed"
            ? { delivery_error: existing.error }
            : {}),
        };
      const q: Queued = {
        id: e.id,
        message,
        mode,
        at,
        clock: (BigInt(Date.now()) * 1000000n).toString().padStart(20, "0"),
        status: "pending",
      };
      t.queue.push(q);
      t.pending = false;
      result = q;
      break;
    }
    case "acknowledge": {
      const q = t.queue.find(
        (q) =>
          q.claim_id === r.claim_id &&
          nonempty(r.claim_id) &&
          ["claimed", "failed"].includes(q.status),
      );
      requireThat(q, "no matching active queued request");
      if (q.acknowledged_at) return e;
      q.acknowledged_at = at;
      break;
    }
    case "handoff": {
      const q = t.queue.find(
        (q) =>
          q.id === r.queue_id &&
          q.claim_id === r.claim_id &&
          nonempty(r.claim_id) &&
          ["claimed", "failed"].includes(q.status),
      );
      requireThat(q, "no matching active queued request");
      q.status = "pending";
      delete q.claim_id;
      delete q.author;
      delete q.error;
      delete q.acknowledged_at;
      break;
    }
    case "reply":
      appendMessage(t, r, e);
      break;
    case "finish": {
      requireThat(
        Array.isArray(r.claim_ids) &&
          r.claim_ids.length > 0 &&
          r.claim_ids.every(nonempty),
        "finish requires active claim IDs",
      );
      const remaining = new Set(r.claim_ids);
      for (const q of t.queue)
        if (
          q.claim_id &&
          remaining.has(q.claim_id) &&
          ["claimed", "failed"].includes(q.status)
        ) {
          q.status = "complete";
          remaining.delete(q.claim_id);
        }
      requireThat(
        remaining.size === 0,
        "one or more claims are no longer active",
      );
      appendMessage(t, r, e);
      break;
    }
    case "attach": {
      requireThat(
        label(r.label) && r.source?.kind === "file",
        "attach requires a label and file source",
      );
      validateSource(r.source);
      const attachments = (t.attachments ??= []);
      const index =
        r.attachment_id === undefined
          ? -1
          : attachments.findIndex((a) => a.id === r.attachment_id);
      requireThat(
        r.attachment_id === undefined || index >= 0,
        "unknown attachment",
      );
      const attachment: Attachment = {
        id: r.attachment_id ?? e.id,
        label: r.label,
        source: r.source,
        author,
        at,
      };
      if (index < 0) attachments.push(attachment);
      else attachments[index] = attachment;
      if (author !== "You") t.incoming = e.id;
      result = attachment;
      break;
    }
    case "comparison": {
      requireThat(
        typeof r.before === "string" &&
          typeof r.after === "string" &&
          label(r.label),
        "comparison requires before, after, and a single-line label",
      );
      e.before = r.before;
      e.after = r.after;
      e.label = r.label;
      if (r.comparison_id !== undefined) {
        const index = t.comparisons.findIndex((c) => c.id === r.comparison_id);
        requireThat(index >= 0, "unknown comparison");
        requireThat(
          t.comparisons[index].author === author,
          "cannot replace another author's comparison",
        );
        (t.comparison_history ??= []).push(t.comparisons[index]);
        t.comparisons[index] = { ...e, id: r.comparison_id };
        result = t.comparisons[index];
      } else t.comparisons.push(e);
      if (author !== "You") t.incoming = e.id;
      break;
    }
    case "archive-comparison": {
      const index = t.comparisons.findIndex((c) => c.id === r.comparison_id);
      requireThat(index >= 0, "unknown comparison");
      requireThat(
        t.comparisons[index].author === author,
        "cannot archive another author's comparison",
      );
      const archived = t.comparisons.splice(index, 1)[0];
      (t.comparison_history ??= []).push(archived);
      if (t.primary_comparison === archived.id) delete t.primary_comparison;
      if (author !== "You") t.incoming = e.id;
      break;
    }
    case "revise": {
      const previous = t.review;
      requireThat(
        !previous || previous.author === author,
        "cannot revise another author's review",
      );
      requireThat(
        previous
          ? r.expected_review === previous.id
          : r.expected_review === undefined,
        "review changed; read it before revising",
      );
      const title = r.title ?? previous?.title;
      const summary = r.body ?? previous?.summary;
      requireThat(
        label(title) && nonempty(summary),
        "review requires a title and summary body",
      );
      requireThat(
        r.primary_comparison === undefined ||
          r.primary_comparison === "" ||
          t.comparisons.some((c) => c.id === r.primary_comparison),
        "unknown primary comparison",
      );
      (t.review_history ??= []).push(
        previous ?? {
          id: t.messages[0].id,
          title: t.title,
          summary: t.messages[0].body,
          author: t.messages[0].author,
          at: t.created_at,
        },
      );
      t.review = { id: e.id, title, summary, author, at };
      t.title = title;
      if (r.primary_comparison !== undefined) {
        if (r.primary_comparison) t.primary_comparison = r.primary_comparison;
        else delete t.primary_comparison;
      }
      if (author !== "You") t.incoming = e.id;
      result = t.review;
      break;
    }
    case "resolve":
      requireThat(
        typeof r.resolved === "boolean",
        "resolved must be a boolean",
      );
      t.resolved = r.resolved;
      if (t.resolved) {
        t.seen = t.incoming ?? "";
        t.manual_unread = false;
      }
      break;
    case "read-state":
      requireThat(typeof r.read === "boolean", "read must be a boolean");
      requireThat(
        !r.read || !t.incoming || nonempty(r.seen),
        "marking read requires the incoming version you viewed",
      );
      if ((r.seen ?? "") === (t.incoming ?? "")) t.seen = r.seen ?? "";
      t.manual_unread = !r.read;
      break;
    default:
      transition(t, r);
  }
  if (r.request_id && ["reply", "finish"].includes(r.action))
    t.reply_receipts = {
      ...t.reply_receipts,
      [r.request_id]: { fingerprint, event: e },
    };
  t.unread = !!t.manual_unread || (t.incoming ?? "") !== (t.seen ?? "");
  t.updated_at = at;
  save(sql, t, r.action);
  return result;
}
export function mutate(sql: SQL, r: Request): unknown {
  return sql.transaction((tx) => mutateInside(tx, r));
}
export function selectedAgent(sql: SqlReader, project: string): Agent {
  const rows = sql
    .exec<{ state: string }>(
      "SELECT state FROM agents WHERE project=?",
      project,
    )
    .toArray();
  return rows.length
    ? JSON.parse(rows[0].state)
    : { id: "", project, harness: "" };
}
export function selectAgent(sql: SQL, agent: Agent, previous: string) {
  return sql.transaction((sql) => {
    requireThat(
      nonempty(agent.project) &&
        nonempty(agent.id) &&
        ["codex", "pi"].includes(agent.harness),
      "invalid agent selection",
    );
    requireThat(
      selectedAgent(sql, agent.project).id === previous,
      "project agent changed; inspect its status before trying again",
    );
    sql.exec(
      "INSERT INTO agents(project,id,state) VALUES(?,?,?) ON CONFLICT(project) DO UPDATE SET id=excluded.id,state=excluded.state",
      agent.project,
      agent.id,
      JSON.stringify(agent),
    );
    return { selected: true };
  });
}
export function detachAgent(sql: SQL, project: string, expected: string) {
  return sql.transaction((sql) => {
    requireThat(
      selectedAgent(sql, project).id === expected,
      "project agent changed; inspect its status before trying again",
    );
    sql.exec("DELETE FROM agents WHERE project=? AND id=?", project, expected);
    return { detached: true };
  });
}
// An explicit, atomic import preserves IDs and captures. Conflicting existing
// threads abort the whole batch instead of overwriting remote conversation.
export function importThreads(sql: SQL, threads: Thread[], agents: Agent[]) {
  return sql.transaction((sql) => {
    let imported = 0;
    for (const t of threads) {
      requireThat(
        nonempty(t.id) &&
          nonempty(t.project) &&
          label(t.title) &&
          Array.isArray(t.messages) &&
          t.messages.length > 0 &&
          t.messages.every(
            (m) =>
              label(m.author) &&
              nonempty(m.body) &&
              nonempty(m.id) &&
              nonempty(m.at),
          ) &&
          Array.isArray(t.queue) &&
          Array.isArray(t.comparisons) &&
          typeof t.resolved === "boolean" &&
          typeof t.unread === "boolean" &&
          nonempty(t.created_at) &&
          nonempty(t.updated_at),
        "invalid imported thread",
      );
      validateSource(t.source);
      requireThat(
        t.attachments === undefined || Array.isArray(t.attachments),
        "invalid imported attachments",
      );
      const attachmentIDs = new Set<string>();
      for (const a of t.attachments ?? []) {
        requireThat(
          label(a.id) &&
            label(a.label) &&
            label(a.author) &&
            nonempty(a.at) &&
            !attachmentIDs.has(a.id) &&
            a.source?.kind === "file",
          "invalid imported attachment",
        );
        validateSource(a.source);
        attachmentIDs.add(a.id);
      }
      const existing = sql
        .exec<{ state: string }>("SELECT state FROM threads WHERE id=?", t.id)
        .toArray();
      if (existing.length) {
        requireThat(
          existing[0].state === JSON.stringify(t),
          "import conflicts with existing thread " + t.id,
        );
        continue;
      }
      save(sql, t, "import");
      imported++;
    }
    for (const a of agents) {
      const current = selectedAgent(sql, a.project);
      requireThat(
        !current.id || current.id === a.id,
        "import conflicts with an agent selection",
      );
      if (!current.id) {
        requireThat(
          nonempty(a.id) && nonempty(a.project),
          "invalid agent selection",
        );
        sql.exec(
          "INSERT INTO agents(project,id,state) VALUES(?,?,?)",
          a.project,
          a.id,
          JSON.stringify(a),
        );
      }
    }
    return { imported };
  });
}
