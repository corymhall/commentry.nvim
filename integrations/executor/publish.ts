import type { SqlReader } from "apps";
import {
  mutateInside,
  type SQL,
  type Source,
  type Event,
  type Review,
  type Attachment,
  type Session,
  validateSession,
  validateInbox,
} from "./inbox.js";

export interface PublishItem {
  key: string;
  title: string;
  body: string;
  source?: Source;
  attachments?: { label: string; source: Source }[];
  comparisons?: { key: string; label: string; before: string; after: string }[];
  primary_comparison?: string;
}
export interface Publication {
  inbox?: string;
  session?: Session;
  project: string;
  request_id: string;
  author: string;
  items: PublishItem[];
}
export interface PublishReceipt {
  inbox?: string;
  project: string;
  request_id: string;
  status: "complete";
  items: {
    key: string;
    thread: string;
    title: string;
    review: string;
    attachments: { id: string; label: string }[];
    comparisons: { key: string; id: string; label: string }[];
    primary_comparison?: string;
  }[];
}
function check(ok: unknown, message: string): asserts ok {
  if (!ok) throw Error(message);
}
const label = (value: unknown): value is string =>
  typeof value === "string" && value.trim().length > 0 && !/[\r\n]/.test(value);
function identity(project: string, request: string) {
  check(
    label(project) && label(request) && request.length <= 200,
    "project and request_id are required; request_id must be a single line of at most 200 characters",
  );
}
function canonical(value: unknown): string {
  if (Array.isArray(value)) return "[" + value.map(canonical).join(",") + "]";
  if (value !== null && typeof value === "object") {
    const entries = Object.entries(value)
      .filter(([, v]) => v !== undefined)
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
    return (
      "{" +
      entries
        .map(([k, v]) => JSON.stringify(k) + ":" + canonical(v))
        .join(",") +
      "}"
    );
  }
  return JSON.stringify(value);
}
export function publication(
  sql: SqlReader,
  project: string,
  request_id: string,
  inbox?: string,
): PublishReceipt | { project: string; request_id: string; status: "missing" } {
  identity(project, request_id);
  validateInbox(inbox);
  const rows = sql
    .exec<{ receipt: string }>(
      "SELECT receipt FROM publications WHERE project=? AND request_id=? AND inbox=?",
      project,
      request_id,
      inbox ?? "",
    )
    .toArray();
  return rows.length
    ? JSON.parse(rows[0].receipt)
    : { project, request_id, ...(inbox ? { inbox } : {}), status: "missing" };
}
export async function publish(
  sql: SQL,
  input: Publication,
): Promise<PublishReceipt> {
  identity(input.project, input.request_id);
  validateInbox(input.inbox);
  validateSession(input.session);
  check(label(input.author), "author is required");
  check(
    Array.isArray(input.items) &&
      input.items.length > 0 &&
      input.items.length <= 25,
    "publish requires 1 to 25 topics",
  );
  const keys = new Set<string>();
  for (const item of input.items) {
    check(
      label(item.key) && !keys.has(item.key),
      "topic keys must be nonempty and unique",
    );
    keys.add(item.key);
    check(
      label(item.title) && typeof item.body === "string" && item.body.trim(),
      "each topic requires a title and body",
    );
    const comparisons = item.comparisons ?? [];
    check(
      new Set(comparisons.map((c) => c.key)).size === comparisons.length &&
        comparisons.every((c) => label(c.key)),
      "comparison keys must be nonempty and unique within a topic",
    );
    check(
      item.primary_comparison === undefined ||
        comparisons.some((c) => c.key === item.primary_comparison),
      "primary_comparison must name a comparison key in its topic",
    );
  }
  // Exclude session identity so replacement-session retries keep the first actor.
  // Hash outside the transaction; no transaction waits on an async operation.
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(
      canonical({
        project: input.project,
        ...(input.inbox ? { inbox: input.inbox } : {}),
        request_id: input.request_id,
        author: input.author,
        items: input.items,
      }),
    ),
  );
  const fingerprint = Array.from(new Uint8Array(digest), (b) =>
    b.toString(16).padStart(2, "0"),
  ).join("");
  return sql.transaction((tx) => {
    const rows = tx
      .exec<{ fingerprint: string; receipt: string }>(
        "SELECT fingerprint,receipt FROM publications WHERE project=? AND request_id=? AND inbox=?",
        input.project,
        input.request_id,
        input.inbox ?? "",
      )
      .toArray();
    if (rows.length) {
      check(
        rows[0].fingerprint === fingerprint,
        "request_id already used with different content; inspect publications.read or use a new request_id for a new submission",
      );
      return JSON.parse(rows[0].receipt) as PublishReceipt;
    }
    const receipt: PublishReceipt = {
      project: input.project,
      ...(input.inbox ? { inbox: input.inbox } : {}),
      request_id: input.request_id,
      status: "complete",
      items: [],
    };
    for (const item of input.items) {
      const common = {
        project: input.project,
        inbox: input.inbox,
        author: input.author,
        session: input.session,
      };
      const thread = mutateInside(tx, {
        ...common,
        action: "create",
        title: item.title,
        body: item.body,
        source: item.source,
      }) as string;
      const attachments = (item.attachments ?? []).map((a) => {
        const saved = mutateInside(tx, {
          ...common,
          action: "attach",
          thread,
          ...a,
        }) as Attachment;
        return { id: saved.id, label: saved.label };
      });
      const comparisons = (item.comparisons ?? []).map((c) => {
        const { key, ...data } = c;
        const saved = mutateInside(tx, {
          ...common,
          action: "comparison",
          thread,
          ...data,
        }) as Event;
        return { key, id: saved.id, label: saved.label! };
      });
      const primary = comparisons.find(
        (c) => c.key === item.primary_comparison,
      )?.id;
      const review = mutateInside(tx, {
        ...common,
        action: "revise",
        thread,
        title: item.title,
        body: item.body,
        ...(primary ? { primary_comparison: primary } : {}),
      }) as Review;
      receipt.items.push({
        key: item.key,
        thread,
        title: item.title,
        review: review.id,
        attachments,
        comparisons,
        ...(primary ? { primary_comparison: primary } : {}),
      });
    }
    tx.exec(
      "INSERT INTO publications(project,inbox,request_id,fingerprint,receipt) VALUES(?,?,?,?,?)",
      input.project,
      input.inbox ?? "",
      input.request_id,
      fingerprint,
      JSON.stringify(receipt),
    );
    return receipt;
  });
}
