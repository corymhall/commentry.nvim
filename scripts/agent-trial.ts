// Isolated consumer trials. This script never connects to Executor or Rex.
import {
  mkdirSync,
  readFileSync,
  writeFileSync,
  appendFileSync,
} from "node:fs";
import { join } from "node:path";
import { database } from "../tests/executor_sql.ts";
import { mutate, read, type Thread } from "../integrations/executor/inbox.ts";
import {
  readRequests,
  requestContext,
} from "../integrations/executor/requests.ts";

const [action, directory] = process.argv.slice(2);
if (!directory)
  throw Error("Usage: node scripts/agent-trial.ts seed|call|inspect DIRECTORY");
mkdirSync(directory, { recursive: true });
const { sql, close } = database(join(directory, "inbox.sqlite3"));
const manifest = join(directory, "scenarios.json");
const call = (r: any) => mutate(sql, r);
const get = (thread: string) => read(sql, { action: "read", thread }) as Thread;
function create(
  project: string,
  body: string,
  lines: string[],
  extra: any = {},
) {
  return call({
    action: "create",
    project,
    body,
    source: { kind: "text", origin: "conversation", lines },
    ...extra,
  }) as string;
}
function submit(project: string, thread: string, message?: string) {
  call({ action: "queue", thread, ...(message ? { message } : {}) });
  const claim = call({
    action: "claim",
    project,
    thread,
    author: "trial",
  }) as any;
  return { thread, claim_ids: [claim.claim_id] };
}
const tools = [
  {
    path: "commentry.requests.read",
    input:
      "{project:string,items:[{thread:string,claim_ids:string[]}],cursor?:number}",
    description:
      "Bounded delivered context, five claims/page; does not mark read.",
  },
  {
    path: "commentry.requests.context",
    input:
      "{project,thread,claim_id,section?:request|history|source|attachment|comparison,id?,offset?,limit?}",
    description:
      "Bounded continuation or selected context section, max4000 Unicode chars.",
  },
  {
    path: "commentry.finish",
    input: "{thread,claim_ids,author,body}",
    description:
      "Save answer and finish only supplied claims; preserve resolution.",
  },
  {
    path: "commentry.comparison",
    input: "{thread,author,label,before,after}",
    description: "Attach focused comparison; does not finish claims.",
  },
  {
    path: "commentry.read",
    input: "{thread}",
    description:
      "Full editor thread state, including whole snapshots and queue history. Avoid for delivered requests.",
  },
];
try {
  if (action === "seed") {
    const scenarios: any[] = [];
    const project = "/commentry-trials/five";
    const questions = [
      [
        "Is it fine to keep the provider default?",
        ["The provider uses 40m by default; we need 40m."],
      ],
      [
        "I intended this naming change. Please acknowledge.",
        ["The new namePrefix makes resource names unique."],
      ],
      [
        "Does this return on the first success?",
        [
          "for (const attempt of attempts) { const r = fetch(); if (r.ok) return r; }",
        ],
      ],
      [
        "Attach a focused comparison changing retries from 5 to 3, then briefly confirm.",
        ["before: retries = 5", "after: retries = 3"],
      ],
      ["Are negative inputs clamped to zero?", ["return Math.max(0, count);"]],
    ] as const;
    const items = questions.map(([body, lines]) =>
      submit(project, create(project, body, [...lines])),
    );
    scenarios.push({
      name: "five",
      project,
      items,
      task: "Answer each question or acknowledge its note. Save each answer in its own thread.",
    });
    const follow = "/commentry-trials/followup";
    const thread = create(
      follow,
      "Explain this fallback. " + "old discussion ".repeat(1000),
      ["return input || 3"],
    );
    const old = submit(follow, thread);
    call({
      action: "finish",
      thread,
      claim_ids: old.claim_ids,
      author: "codex",
      body:
        "Using || treats zero as false, so zero selects 3. " +
        "historical explanation ".repeat(700),
    });
    call({
      action: "reply",
      thread,
      body: "Should we use ?? if we want to preserve zero?",
    });
    scenarios.push({
      name: "followup",
      project: follow,
      items: [submit(follow, thread)],
      task: "Answer the short followup without repeating the earlier explanation.",
    });
    const code = "/commentry-trials/code",
      lines = Array.from(
        { length: 10000 },
        (_, i) => "// unrelated line " + (i + 1),
      );
    lines[4999] = "return value ?? 3;";
    const file = create(
      code,
      "Explain this line and whether zero is preserved.",
      [],
      {
        source: {
          kind: "file",
          path: "fallback.ts",
          first: 5000,
          last: 5000,
          lines,
        },
      },
    );
    scenarios.push({
      name: "code",
      project: code,
      items: [submit(code, file)],
      task: "Explain the selected line from this large file. Do not edit code.",
    });
    const long = "/commentry-trials/long";
    const longThread = create(long, "Custom request", []);
    scenarios.push({
      name: "long",
      project: long,
      items: [
        submit(
          long,
          longThread,
          "This is a reading check. " +
            "😀 context ".repeat(650) +
            "\nFinal instruction: reply with the exact words ORANGE LANTERN.",
        ),
      ],
      task: "Follow the entire submitted custom request.",
    });
    const stale = "/commentry-trials/stale",
      st = create(stale, "Check this", ["Nothing to change"]);
    const oldClaim = submit(stale, st);
    call({
      action: "fail",
      thread: st,
      claim_id: oldClaim.claim_ids[0],
      body: "Uncertain",
    });
    call({ action: "retry", thread: st, queue_id: get(st).queue[0].id });
    submit(stale, st);
    scenarios.push({
      name: "stale",
      project: stale,
      items: [oldClaim],
      task: "Handle the supplied delivered item.",
    });
    writeFileSync(manifest, JSON.stringify(scenarios, null, 2));
    writeFileSync(join(directory, "trace.jsonl"), "");
    console.log(
      JSON.stringify({ manifest, scenarios: scenarios.map((s) => s.name) }),
    );
  } else if (action === "call") {
    const input = JSON.parse(readFileSync(0, "utf8"));
    let value: any;
    try {
      switch (input.tool) {
        case "discover": {
          const tokens = [
            ...new Set(
              String(input.query ?? "")
                .split(/[.\s]+/)
                .filter(Boolean),
            ),
          ];
          const matches = tools.map((tool) => ({
            tool,
            score: tokens.filter((token) => tool.path.includes(token)).length,
          }));
          const best = Math.max(...matches.map((m) => m.score));
          value = {
            envelope:
              "Call with {tool: exact returned path, input: argument object}. Check status and execution.ok, then show execution.value only.",
            items: matches
              .filter((m) => !tokens.length || m.score >= Math.max(1, best - 1))
              .sort((a, b) => b.score - a.score)
              .map((m) => m.tool),
          };
          break;
        }
        case "commentry.requests.read":
          value = readRequests(sql, input.input);
          break;
        case "commentry.requests.context":
          value = requestContext(sql, input.input);
          break;
        case "commentry.read":
          value = get(input.input.thread);
          break;
        case "commentry.finish":
          value = call({ ...input.input, action: "finish" });
          break;
        case "commentry.comparison":
          value = call({ ...input.input, action: "comparison" });
          break;
        default:
          throw Error("Unknown trial tool");
      }
      const result = { status: "completed", execution: { ok: true, value } };
      appendFileSync(
        join(directory, "trace.jsonl"),
        JSON.stringify({
          tool: input.tool,
          input: input.input ?? input.query,
          result_chars: JSON.stringify(value).length,
        }) + "\n",
      );
      console.log(JSON.stringify(result));
    } catch (error) {
      appendFileSync(
        join(directory, "trace.jsonl"),
        JSON.stringify({ tool: input.tool, error: String(error) }) + "\n",
      );
      console.log(
        JSON.stringify({
          status: "completed",
          execution: { ok: false, error: String(error) },
        }),
      );
    }
  } else if (action === "inspect") {
    const scenarios = JSON.parse(readFileSync(manifest, "utf8"));
    console.log(
      JSON.stringify(
        scenarios.map((s: any) => ({
          ...s,
          items: s.items.map((i: any) => {
            const t = get(i.thread);
            return {
              thread: t.id,
              messages: t.messages,
              comparisons: t.comparisons,
              queue: t.queue.map((q) => ({
                id: q.id,
                status: q.status,
                claim_id: q.claim_id,
              })),
              resolved: t.resolved,
              unread: t.unread,
            };
          }),
        })),
      ),
    );
  } else throw Error("Unknown trial command");
} finally {
  close();
}
