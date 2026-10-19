# Commentry agent experience trials

Validated on 2026-10-19 with fresh consumer subagents, an isolated SQLite inbox,
and the same request-reading operations deployed to Executor. No trial sent
input to a real coding-agent terminal.

## What changed

Delivered notifications point agents to requests.read and finish. requests.read
returns at most five claims and 2000 Unicode context characters per claim.
requests.context continues a page or retrieves a specific submitted history,
source or attachment section. Current comparison content is fetched explicitly.

The submitted snapshot defines the task. Later messages and replaced locations
do not enter it. Inactive claims return status only. The snapshot freezes its
answered-history boundary when queued, so continuation offsets do not change
when another claim completes. Latest messages appear first. Long preceding
agent answers are visibly abbreviated, with full history available on demand.
Independent thread titles are retained when they add information.

The skill avoids global inventories, names the narrow reader, and demonstrates
how to emit the checked execution value without printing both MCP response
representations. Full read remains unchanged for the editor and explicit
complete inspection.

## Iterations

The baseline consumer followed the previous skill through a global skills
inventory and broad discovery. The Commentry inventory, guidance, tool schemas
and duplicated MCP envelopes cost substantially more than the five comments.

The first controlled run completed every task, but found an underspecified
fixture transport and discovery matching. The harness now advertises its
argument envelope and supports ordinary discovery terms. The skill also has a
concrete result-projection example. A fresh second consumer completed all five
scenarios with zero failed calls and two discovery calls.

| Second-run scenario | Outcome | Useful result characters shown |
| --- | --- | ---: |
| Five copied notes/questions | Five replies and one comparison in the correct threads | 2273 |
| Short followup after a long answer | Answered without loading the full answered discussion | 898 |
| Selection from a 10000-line file | Nine excerpt lines with original coordinates | 666 |
| Long custom request | Read three pages and obeyed its final instruction | 7186 |
| Superseded claim | No answer or replacement claim | 141 |

These are consumer-reported character counts of useful result values. They
exclude skill text, the manifest, shell metadata and response envelopes.
The fixture independently recorded operations and response sizes. Its final
state confirmed eight new replies, one comparison, no automatic resolutions
and no write for the superseded claim.

## Replay of the reported session

The exact five stored threads from Evaler session
01a14613-67a7-72a7-88f3-ea0bc22c5e92 were replayed in an isolated database.
The old complete-thread JSON was 9493 characters. The new request result was
2459 characters, with no continuation needed, about 74 percent smaller.

The old recorded visible tool output was 20935 characters because it included
both text and structured MCP representations. Avoiding that duplication and
returning the compact result removes two distinct sources of excess context.
Character counts are not token counts.

## Reproducing consumer trials

Use a fresh output directory:

```sh
mise run agent_trials -- seed tmp/my-agent-trial
```

Give a fresh consumer the local Commentry skill, the packaged app skill, and one
scenario from the generated scenarios.json. Restrict it to the offline fixture.
The fixture accepts a single JSON call on stdin:

```sh
mise run agent_trials -- call tmp/my-agent-trial
```

Start with {"tool":"discover","query":"commentry requests.read"}. Discovery
returns its argument envelope and available paths. Calls use
{"tool":"RETURNED_PATH","input":{...}}. Check status and execution.ok, then show
execution.value only. The trace.jsonl file records calls and result sizes.

A fresh live consumer then read the exact five old claim IDs through the deployed
requests.read. All returned superseded, in a 661-character result, without
loading their contents or making writes. Initial discovery succeeded, but still
returned unrelated tool entries. The skill now explicitly projects discovery
to matching paths and input signatures before emitting it. A subsequent focused
live discovery emitted 204 characters for requests.read and 152 for finish,
356 combined compared with the earlier 4340-character discovery value.

A later discovery probe hit Executor availability timeouts. These occur outside
Commentry's reader. The outer Executor payload's unavailableApps field must be
inspected when the intended app is absent; a tiny empty result is not a
successful discovery. A new execution recovered, and the final skill deployment
succeeded.

The behavioral suite also verifies Unicode continuation, claim-state handling,
project isolation, unchanged human read state, frozen attachment snapshots and
independent titles:

```sh
mise run test_executor
```

## Limits

Offline trials model Executor's tool functions and result contracts. They do not
measure harness token accounting, live server latency, or how every model will
follow the skill. Exact prior claims were checked against the deployed reader
without modifying those real conversations. Deployment and tests do not remove
the need to inspect availability errors or check mutation receipts.
