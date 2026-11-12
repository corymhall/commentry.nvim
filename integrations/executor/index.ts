import {
  array,
  boolean,
  defineApp,
  json,
  mutation,
  number,
  object,
  query,
  record,
  router,
  string,
  type JsonValue,
  type Infer,
} from "apps";
import {
  detachAgent,
  importThreads,
  mutate,
  read,
  reads,
  selectAgent,
  selectedAgent,
  type Agent,
  type Event,
  type Request,
  type SQL,
  type Thread,
} from "./inbox.js";

import { receiveRequests, requestContext } from "./requests.js";
import { publish, publication, type Publication } from "./publish.js";

const text = string({ minLength: 1 });
const source = object({
  kind: text,
  lines: array(string()),
  path: string().optional(),
  first: number().optional(),
  last: number().optional(),
  excerpt_first: number().optional(),
  origin: string().optional(),
  filetype: string().optional(),
  modified: boolean().optional(),
  git: json().optional(),
});
const attachment = object({
  id: text,
  label: text,
  source,
  author: text,
  at: text,
});
const message = object({ id: text, author: text, body: text, at: text });
const event = object({
  id: text,
  thread: text,
  kind: text,
  author: text,
  at: text,
  before: string(),
  after: string(),
  label: string().optional(),
  claim_id: string().optional(),
  queue_id: string().optional(),
});
const review = object({
  id: text,
  title: text,
  summary: text,
  author: text,
  at: text,
});
const queued = object({
  id: text,
  message: text,
  mode: text,
  at: text,
  clock: text,
  status: text,
  claim_id: string().optional(),
  author: string().optional(),
  error: string().optional(),
  skipped: boolean().optional(),
  delivery_error: string().optional(),
  acknowledged_at: string().optional(),
});
const thread = object({
  pending: boolean().optional(),
  id: text,
  project: text,
  title: text,
  source,
  attachments: array(attachment).optional(),
  created_at: text,
  updated_at: text,
  resolved: boolean(),
  messages: array(message),
  comparisons: array(event),
  primary_comparison: string().optional(),
  review: review.optional(),
  review_history: array(review).optional(),
  comparison_history: array(event).optional(),
  queue: array(queued),
  unread: boolean(),
  incoming: string().optional(),
  seen: string().optional(),
  manual_unread: boolean().optional(),
  reply_receipts: record(object({ fingerprint: string(), event })).optional(),
});
const requestContextOutput = object({
  thread: text,
  claim_id: text,
  status: text,
  earlier_messages: number().optional(),
  acknowledged_at: string().optional(),
  latest_activity: string().optional(),
  submitted_activity: string().optional(),
  sections: array(string()).optional(),
  recent_history: array(
    object({ author: text, body: string(), abbreviated: boolean() }),
  ).optional(),
  context: object({
    text: string(),
    total_chars: number(),
    next_offset: number().optional(),
  }).optional(),
});
const agent = object({
  id: string(),
  project: string(),
  harness: string(),
  name: string().optional(),
  rex_session: string().optional(),
  rex_block: string().optional(),
});
const publishItem = object({
  key: text,
  title: text,
  body: text,
  source: source.optional(),
  attachments: array(object({ label: text, source })).optional(),
  comparisons: array(
    object({ key: text, label: text, before: string(), after: string() }),
  ).optional(),
  primary_comparison: text.optional(),
});
const publicationOutput = object({
  project: text,
  request_id: text,
  status: text,
  items: array(
    object({
      key: text,
      thread: text,
      title: text,
      review: text,
      attachments: array(object({ id: text, label: text })),
      comparisons: array(object({ key: text, id: text, label: text })),
      primary_comparison: text.optional(),
    }),
  ).optional(),
});
const request = object({
  pending: boolean().optional(),
  expected_message: string().optional(),
  action: text,
  request_id: string().optional(),
  items: array(publishItem).optional(),
  thread: string().optional(),
  project: string().optional(),
  author: string().optional(),
  title: string().optional(),
  body: string().optional(),
  text: string().optional(),
  source: source.optional(),
  attachment_id: string().optional(),
  comparison_id: string().optional(),
  primary_comparison: string().optional(),
  expected_review: string().optional(),
  filter: string().optional(),
  summary: boolean().optional(),
  resolved: boolean().optional(),
  read: boolean().optional(),
  seen: string().optional(),
  before: string().optional(),
  after: string().optional(),
  label: string().optional(),
  message: string().optional(),
  mode: string().optional(),
  claim_id: string().optional(),
  claim_ids: array(string()).optional(),
  queue_id: string().optional(),
  pending_only: boolean().optional(),
  cursor: number().optional(),
});
const change = object({
  sequence: number(),
  thread: text,
  project: text,
  kind: text,
  at: text,
});
const changes = object({
  changes: array(change),
  cursor: number(),
  revision: number(),
});
const author = string().default("codex");
const perform = (sql: SQL, input: Request) => {
  if (input.action === "publish") return publish(sql, input as Publication);
  if (input.action === "publication")
    return publication(sql, input.project ?? "", input.request_id ?? "");
  return reads.has(input.action) ? read(sql, input) : mutate(sql, input);
};

export default defineApp(
  {},
  {
    tools: router(
      {
        publish: mutation(
          {
            description:
              "Publish 1 to 25 independent review topics with summaries, code excerpts and comparisons in one atomic transaction. Use a durable request_id and unique item keys. Repeating the same request returns the original compact receipt; changed content at the same ID is rejected. For source excerpts set excerpt_first to the file line of lines[0]. No separate create/revise calls needed. Check publications.read after a timeout.",
            input: object({
              project: text,
              request_id: text,
              author,
              items: array(publishItem),
            }),
            output: publicationOutput,
          },
          async ({ sql }, input) => publish(sql, input as Publication),
        ),
        publications: router({
          read: query(
            {
              description:
                "Check whether an atomic publish committed using project and request_id. Returns complete with the original topic-to-thread receipts, or missing. Does not change read state. A missing response during an in-flight call is not proof it will fail; retry only the same request_id and payload.",
              input: object({ project: text, request_id: text }),
              output: publicationOutput,
            },
            async ({ sql }, input) =>
              publication(sql, input.project, input.request_id),
          ),
        }),
        requests: router({
          read: mutation(
            {
              description:
                "Start here for delivered comments. Read exact supplied thread/claim IDs in compact pages, without queue history, full files or comparisons. Five claims per page; follow next_cursor with the same items. Context continuation uses requests.context and next_offset. Inactive claims return status only. Atomically acknowledges fetched claims, independently of human read state. Recent history, available sections and latest activity ID accompany submitted context.",
              input: object({
                project: text,
                items: array(object({ thread: text, claim_ids: array(text) })),
                cursor: number().optional(),
              }),
              output: object({
                items: array(requestContextOutput),
                next_cursor: number().optional(),
              }),
            },
            async ({ sql }, input) => receiveRequests(sql, input),
          ),
          context: query(
            {
              description:
                "Read more of one claimed request. Continue request text with next_offset; section history includes earlier submitted discussion, source the captured excerpt, attachment needs a submitted attachment id. Comparison lists current enrichment metadata, or fetches one comparison by id. Offset counts Unicode characters, limit is 1 to 4000. Does not acknowledge or change claims.",
              input: object({
                project: text,
                thread: text,
                claim_id: text,
                section: string().optional(),
                id: string().optional(),
                offset: number().optional(),
                limit: number().optional(),
              }),
              output: requestContextOutput,
            },
            async ({ sql }, input) => requestContext(sql, input),
          ),
        }),
        list: query(
          {
            description:
              "List project conversations. Omitting project includes all projects. Reads do not mark messages read.",
            input: object({
              project: string().optional(),
              filter: string().optional(),
            }),
            output: array(thread),
          },
          async ({ sql }, input) =>
            read(sql, { ...input, action: "list" }) as Thread[],
        ),
        read: query(
          {
            description:
              "Read the complete thread for editor use or explicit inspection. For delivered comments use requests.read to avoid full files and queue history.",
            input: object({ thread: text }),
            output: thread,
          },
          async ({ sql }, input) =>
            read(sql, { ...input, action: "read" }) as Thread,
        ),
        create: mutation(
          {
            description:
              "Create a project conversation with optional copied text or an immutable file snapshot.",
            input: object({
              project: text,
              body: text,
              title: string().optional(),
              text: string().optional(),
              source: source.optional(),
              author,
            }),
            output: text,
          },
          async ({ sql }, input) =>
            mutate(sql, {
              ...input,
              source: input.source as Request["source"],
              action: "create",
            }) as string,
        ),
        reply: mutation(
          {
            description:
              "Add a comment. To answer a delivered request, use finish so its claims also complete. Supply a durable request_id for safe retries; changed content at that ID is rejected.",
            input: object({
              thread: text,
              body: text,
              author,
              request_id: text.optional(),
            }),
            output: event,
          },
          async ({ sql }, input) =>
            mutate(sql, { ...input, action: "reply" }) as Event,
        ),
        finish: mutation(
          {
            description:
              "Atomically save a reply and complete exactly the supplied active claims. Does not resolve the conversation. A retained uncertain-delivery claim may finish until explicitly retried or handed off. Supply a durable request_id; an exact retry returns the original receipt without a duplicate answer.",
            input: object({
              thread: text,
              body: text,
              claim_ids: array(text),
              request_id: text.optional(),
              author,
            }),
            output: event,
          },
          async ({ sql }, input) =>
            mutate(sql, { ...input, action: "finish" }) as Event,
        ),
        attach: mutation(
          {
            description:
              "Add a named file location and snapshot without changing the original capture. Supply attachment_id to replace a previously read attachment. Agent updates become unread.",
            input: object({
              thread: text,
              label: text,
              source,
              attachment_id: text.optional(),
              author,
            }),
            output: attachment,
          },
          async ({ sql }, input) =>
            mutate(sql, {
              ...input,
              source: input.source as Request["source"],
              action: "attach",
            }) as import("./inbox.js").Attachment,
        ),
        comparison: mutation(
          {
            description:
              "Attach a focused before/after comparison. Supply comparison_id to replace your own comparison at its stable ID and retain its previous version in history. Preserves captures and queued requests. Neither text is written to source files.",
            input: object({
              thread: text,
              before: string(),
              after: string(),
              label: text,
              comparison_id: text.optional(),
              author,
            }),
            output: event,
          },
          async ({ sql }, input) =>
            mutate(sql, { ...input, action: "comparison" }) as Event,
        ),
        archiveComparison: mutation(
          {
            description:
              "Withdraw your own misleading or obsolete comparison from the active source view. Keeps the complete comparison in history and clears primary selection if needed. Original capture, discussion and submitted requests remain unchanged.",
            input: object({ thread: text, comparison_id: text, author }),
            output: event,
          },
          async ({ sql }, input) =>
            mutate(sql, { ...input, action: "archive-comparison" }) as Event,
        ),
        revise: mutation(
          {
            description:
              "Set the current human-readable review summary and title without editing conversation messages. Choose primary_comparison by existing comparison ID, or clear with an empty string. First revision requires title and body. Updating your own review requires expected_review equal to its current id. Previous versions remain in history; claims stay frozen. Returns only the current review receipt.",
            input: object({
              thread: text,
              title: text.optional(),
              body: text.optional(),
              primary_comparison: string().optional(),
              expected_review: text.optional(),
              author,
            }),
            output: review,
          },
          async ({ sql }, input) =>
            mutate(sql, {
              ...input,
              action: "revise",
            }) as import("./inbox.js").Review,
        ),
        resolve: mutation(
          {
            description:
              "Explicitly resolve or reopen a conversation. Resolving also marks current activity read. Reopening preserves read state. Replies and completed requests never resolve it automatically.",
            input: object({ thread: text, resolved: boolean(), author }),
            output: event,
          },
          async ({ sql }, input) =>
            mutate(sql, { ...input, action: "resolve" }) as Event,
        ),
        readState: mutation(
          {
            description:
              "Acknowledge the incoming version actually viewed, or mark unread. Stale acknowledgements leave newer replies unread.",
            input: object({
              thread: text,
              read: boolean(),
              seen: string().optional(),
            }),
            output: event,
          },
          async ({ sql }, input) =>
            mutate(sql, { ...input, action: "read-state" }) as Event,
        ),
        changes: query(
          {
            description:
              "Read up to 100 committed changes after a cursor. Continue with the returned cursor.",
            input: object({
              project: string().optional(),
              cursor: number().default(0),
            }),
            output: changes,
          },
          async ({ sql }, input) =>
            read(sql, { ...input, action: "changes" }) as Infer<typeof changes>,
        ),
        revision: query(
          {
            description: "Return the latest committed inbox change cursor.",
            input: object({}),
            output: number(),
          },
          async ({ sql }) => read(sql, { action: "revision" }) as number,
        ),
        // The CLI retains its JSON request contract. Native tools above are preferred
        // by agents; Rex delivery remains local and never executes on this server.
        rpc: mutation(
          {
            description:
              "Execute the Commentry CLI JSON protocol. Queue saves a request; the local CLI handles Rex delivery. Prefer the named tools for agent comments.",
            input: request,
            output: json(),
          },
          async ({ sql }, input) =>
            (await perform(sql, input as Request)) as JsonValue,
        ),
        agents: router({
          get: query(
            {
              description:
                "Read the existing local agent selection for a project. This does not probe or start a terminal.",
              input: object({ project: text }),
              output: agent,
            },
            async ({ sql }, input) => selectedAgent(sql, input.project),
          ),
          select: mutation(
            {
              description:
                "Compare and replace a project agent selection. Existing claims stay intact.",
              input: object({ agent, previous: string() }),
              output: object({ selected: boolean() }),
            },
            async ({ sql }, input) =>
              selectAgent(sql, input.agent as Agent, input.previous),
          ),
          detach: mutation(
            {
              description:
                "Detach the expected selection without cancelling existing claims.",
              input: object({ project: text, expected: string() }),
              output: object({ detached: boolean() }),
            },
            async ({ sql }, input) =>
              detachAgent(sql, input.project, input.expected),
          ),
        }),
        migration: router({
          import: mutation(
            {
              description:
                "Import an explicit legacy snapshot while preserving IDs and source captures. Conflicts abort the entire batch. Never use this to edit existing threads.",
              input: object({ threads: array(json()), agents: array(agent) }),
              output: object({ imported: number() }),
            },
            async ({ sql }, input) =>
              importThreads(
                sql,
                input.threads as unknown as Thread[],
                input.agents as Agent[],
              ),
          ),
        }),
      },
      {
        title: "Commentry",
        description:
          "Universal project inbox shared by Neovim, Rex and coding agents.",
      },
    ),
  },
);
