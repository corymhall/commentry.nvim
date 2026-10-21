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
import { publish, publication } from "../integrations/executor/publish.ts";
import {
  readRequests,
  requestContext,
} from "../integrations/executor/requests.ts";

const [action, directory] = process.argv.slice(2);
if (!directory)
  throw Error(
    "Usage: node scripts/agent-trial.ts seed|seed-review|call|inspect DIRECTORY",
  );
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
    path: "commentry.publish",
    input:
      "{project,request_id,author,items:[{key,title,body,source?,attachments?,comparisons?,primary_comparison?}]}",
    description:
      "Publish complete review topics atomically. Excerpts use excerpt_first, the absolute file line of lines[0]. Comparison keys and primary choice are local to each item. Same request ID and payload return original receipts; changed payload conflicts.",
  },
  {
    path: "commentry.publications.read",
    input: "{project,request_id}",
    description:
      "Recover compact complete receipts after a lost response, or return missing. Does not acknowledge human reads.",
  },
  {
    path: "commentry.create",
    input:
      "{project:string,title?:string,body:string,author?:string,source?:Source}",
    description: "Create an inbox topic, preserving its original capture.",
  },
  {
    path: "commentry.list",
    input: "{project:string,summary?:boolean}",
    description: "List project conversations without marking them read.",
  },
  {
    path: "commentry.attach",
    input:
      "{thread,label,author?,attachment_id?,source:{kind:'file',path,first,last,lines:string[],excerpt_first?,filetype?,git?}}",
    description:
      "Attach a named implementation location. Supply full file lines or excerpt_first for an excerpt. attachment_id refreshes it.",
  },
  {
    path: "commentry.revise",
    input: "{thread,author?,title?,body?,primary_comparison?,expected_review?}",
    description:
      "Maintain current review summary/title and primary comparison. First use requires title/body; subsequent own updates require expected_review=current review.id. Empty primary_comparison clears explicit selection. Preserves discussion and history.",
  },
  {
    path: "commentry.archiveComparison",
    input: "{thread,comparison_id,author?}",
    description:
      "Withdraw your own comparison from active evidence while retaining it in history. Clears explicit primary selection when archived.",
  },
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
    input: "{thread,author,label,before,after,comparison_id?}",
    description:
      "Attach focused comparison or replace your own using comparison_id, retaining history; does not finish claims.",
  },
  {
    path: "commentry.read",
    input: "{thread}",
    description:
      "Full editor thread state, including whole snapshots and queue history. Avoid for delivered requests.",
  },
];
try {
  if (action === "seed-review") {
    // Authors get the broad request and raw trees, without a topic manifest.
    const fixture = JSON.parse(
      readFileSync("tests/fixtures/agent_review_changes.json", "utf8"),
    );
    for (const [tree, files] of Object.entries(fixture.trees)) {
      const destination = join(directory, "source", tree);
      mkdirSync(destination, { recursive: true });
      for (const [path, content] of Object.entries(
        files as Record<string, string>,
      ))
        writeFileSync(join(destination, path), content);
    }
    writeFileSync(join(directory, "request.txt"), fixture.request + "\n");
    console.log(
      JSON.stringify({
        request: join(directory, "request.txt"),
        source: join(directory, "source"),
      }),
    );
  } else if (action === "seed") {
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
        case "commentry.publish":
          value = await publish(sql, input.input);
          break;
        case "commentry.publications.read":
          value = publication(sql, input.input.project, input.input.request_id);
          break;
        case "commentry.list":
          value = read(sql, { ...input.input, action: "list" });
          break;
        case "commentry.create":
        case "commentry.attach":
        case "commentry.revise":
          value = call({
            ...input.input,
            action: input.tool.split(".").at(-1),
          });
          break;
        case "commentry.archiveComparison":
          value = call({ ...input.input, action: "archive-comparison" });
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
