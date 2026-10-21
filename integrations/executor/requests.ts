// Agent reads are separate from the editor's complete thread protocol.
import type { SqlReader } from "apps";
import type { Thread, Queued, Source, Message, Review } from "./inbox.js";

type Snapshot = {
  title?: string;
  review?: Review;
  source: Source & { excerpt_first?: number };
  messages: Message[];
  attachments?: {
    id: string;
    label: string;
    source: Source & { excerpt_first?: number };
  }[];
  context_start?: number;
};
export type RequestRef = { thread: string; claim_id: string };
type Selection = { thread: string; claim_ids: readonly string[] };
export type RequestInput = RequestRef & {
  project: string;
  section?: string;
  id?: string;
  offset?: number;
  limit?: number;
};
export type RequestResult = RequestRef & {
  status: string;
  earlier_messages?: number;
  context?: { text: string; total_chars: number; next_offset?: number };
};
function check(ok: unknown, message: string): asserts ok {
  if (!ok) throw new Error(message);
}
function integer(value: number, min: number, max: number, name: string) {
  check(
    Number.isSafeInteger(value) && value >= min && value <= max,
    "invalid " + name,
  );
}
function selected(sql: SqlReader, input: RequestRef & { project: string }) {
  check(
    typeof input.project === "string" && input.project.length > 0,
    "project is required",
  );
  check(
    typeof input.thread === "string" &&
      input.thread.length > 0 &&
      input.thread.length <= 256,
    "invalid thread",
  );
  check(
    typeof input.claim_id === "string" &&
      input.claim_id.length > 0 &&
      input.claim_id.length <= 256,
    "invalid claim",
  );
  const rows = sql
    .exec<{ state: string }>(
      "SELECT state FROM threads WHERE id=?",
      input.thread,
    )
    .toArray();
  if (!rows.length) return { status: "missing" };
  const thread = JSON.parse(rows[0].state) as Thread;
  if (thread.project !== input.project) return { status: "project-mismatch" };
  const request = thread.queue.find((q) => q.claim_id === input.claim_id);
  if (!request) return { status: "superseded" };
  if (!["claimed", "failed"].includes(request.status))
    return { status: request.status };
  return { status: request.status, thread, request };
}
function snapshot(q: Queued, thread: Thread): Snapshot | undefined {
  if (!q.message.startsWith("COMMENTRY_THREAD_V1\n")) return;
  const start = q.message.indexOf("\n{");
  if (start < 0) return;
  try {
    const value = JSON.parse(q.message.slice(start + 1));
    if (
      value.thread !== thread.id ||
      value.project !== thread.project ||
      !Array.isArray(value.messages) ||
      !value.messages.every(
        (m: Message) =>
          typeof m.body === "string" && typeof m.author === "string",
      ) ||
      !Array.isArray(value.source?.lines)
    )
      return;
    return value;
  } catch {
    return;
  }
}
function sourceText(source: Snapshot["source"]): string {
  // Keep coordinate metadata next to the saved excerpt, not a full-file read.
  const { lines, ...metadata } = source;
  return JSON.stringify(metadata) + "\n" + lines.join("\n");
}
function discussion(messages: Message[]) {
  return messages.map((m) => m.author + ":\n" + m.body).join("\n\n");
}
function supersededFinding(saved: Snapshot) {
  return !!saved.review && saved.messages[0]?.author === saved.review.author;
}
function requestText(saved: Snapshot, start: number) {
  const parts = [
    "Submitted discussion, newest first\n" +
      discussion(
        saved.messages
          .slice(start)
          .filter(
            (_, index) => start + index !== 0 || !supersededFinding(saved),
          )
          .map((message, index, messages) => {
            const chars = Array.from(message.body);
            return message.author !== "You" &&
              index < messages.length - 1 &&
              chars.length > 400
              ? {
                  ...message,
                  body:
                    chars.slice(0, 400).join("") +
                    "\n[Earlier answer abbreviated; use section=history for the rest.]",
                }
              : message;
          })
          .reverse(),
      ),
  ];
  if (saved.review)
    parts.push("Submitted review summary\n" + saved.review.summary);
  parts.push("Original capture\n" + sourceText(saved.source));
  if (saved.title && saved.title !== saved.messages[0]?.body)
    parts.push("Thread title\n" + saved.title);
  if (saved.attachments?.length)
    parts.push(
      "Submitted code locations, use attachment section for code\n" +
        saved.attachments
          .map((a) =>
            JSON.stringify({
              id: a.id,
              label: a.label,
              path: a.source.path,
              first: a.source.first,
              last: a.source.last,
            }),
          )
          .join("\n"),
    );
  return parts.join("\n\n");
}
function contextText(
  thread: Thread,
  q: Queued,
  saved: Snapshot | undefined,
  section: string,
  id?: string,
) {
  if (!saved) {
    check(section === "request", "custom requests have only a request section");
    return q.message;
  }
  switch (section) {
    case "request":
      return requestText(saved, contextStart(saved));
    case "history":
      return discussion(saved.messages);
    case "source":
      return sourceText(saved.source);
    case "attachment": {
      const attachment = saved.attachments?.find((a) => a.id === id);
      check(attachment, "unknown submitted attachment");
      return sourceText(attachment.source);
    }
    case "comparison": {
      // Comparisons are current enrichment, independent of the frozen request.
      if (!id)
        return (
          "Current comparisons\n" +
          thread.comparisons
            .map((c) =>
              JSON.stringify({
                id: c.id,
                label: c.label,
                author: c.author,
                primary:
                  c.id ===
                  (thread.primary_comparison ?? thread.comparisons[0]?.id),
              }),
            )
            .join("\n")
        );
      const c = thread.comparisons.find((c) => c.id === id);
      check(c, "unknown comparison");
      return JSON.stringify({
        label: c.label,
        before: c.before,
        after: c.after,
      });
    }
    default:
      throw new Error("unknown request section");
  }
}
function contextStart(saved: Snapshot) {
  const start = saved.context_start;
  return Number.isSafeInteger(start) &&
    start! >= 0 &&
    start! < saved.messages.length
    ? start!
    : 0;
}
export function requestContext(
  sql: SqlReader,
  input: RequestInput,
): RequestResult {
  const offset = input.offset ?? 0,
    limit = input.limit ?? 2000;
  integer(offset, 0, Number.MAX_SAFE_INTEGER, "offset");
  integer(limit, 1, 4000, "limit");
  const result: RequestResult = {
    thread: input.thread,
    claim_id: input.claim_id,
    status: "",
  };
  const found = selected(sql, input);
  result.status = found.status;
  if (!found.thread || !found.request) return result;
  const saved = snapshot(found.request, found.thread);
  const section = input.section ?? "request";
  const chars = Array.from(
    contextText(found.thread, found.request, saved, section, input.id),
  );
  const end = Math.min(chars.length, offset + limit);
  result.context = {
    text: chars.slice(offset, end).join(""),
    total_chars: chars.length,
  };
  if (end < chars.length) result.context.next_offset = end;
  if (saved)
    result.earlier_messages =
      contextStart(saved) +
      (contextStart(saved) === 0 && supersededFinding(saved) ? 1 : 0);
  return result;
}
export function readRequests(
  sql: SqlReader,
  input: { project: string; items: readonly Selection[]; cursor?: number },
) {
  check(
    Array.isArray(input.items) &&
      input.items.length > 0 &&
      input.items.length <= 100,
    "supply 1 to 100 items",
  );
  const refs: RequestRef[] = [],
    seen = new Set<string>();
  for (const item of input.items) {
    check(
      Array.isArray(item.claim_ids) && item.claim_ids.length > 0,
      "claim_ids are required",
    );
    for (const claim_id of item.claim_ids) {
      const key = item.thread + "/" + claim_id;
      check(!seen.has(key), "duplicate request");
      seen.add(key);
      refs.push({ thread: item.thread, claim_id });
    }
  }
  check(refs.length <= 100, "at most 100 claims");
  const cursor = input.cursor ?? 0;
  integer(cursor, 0, refs.length, "cursor");
  const end = Math.min(cursor + 5, refs.length);
  return {
    items: refs
      .slice(cursor, end)
      .map((ref) => requestContext(sql, { ...ref, project: input.project })),
    ...(end < refs.length ? { next_cursor: end } : {}),
  };
}
