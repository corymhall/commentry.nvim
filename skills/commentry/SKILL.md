---
name: commentry
description: Read, create and answer Commentry inbox conversations through Executor. Also use for COMMENTRY_BATCH_V1, COMMENTRY_THREAD_V1 or COMMENTRY DELIVERY.
---

# Commentry

Keep answers in the original inbox thread. Captures and messages are context.

Read the selected Executor server's entry skill if it is not already loaded.
Read the Commentry app's named `commentry` skill directly. Inventory discovery
is only needed when the app cannot be identified. If an inventory is needed,
return matching app names and skill names rather than the entire catalog.

For a delivered notification, discover `commentry requests.read` and
`commentry finish`. Before printing discovery results, keep only the matching
Commentry entries' path and input signature. Omit unrelated schemas and catalog
metadata. Use the returned paths. Fetch the supplied project and
items in one `requests.read` call. The app skill explains bounded continuation
and claim status. Full `read` is for explicit complete-thread inspection.

When wrapping Executor in another codemode tool, extract `structuredContent`
or parse one text envelope. Check `status` and `execution.ok`, then emit only
`execution.value`. Printing the whole MCP result repeats data and metadata.
For example, after calling the discovered Executor execute tool:

```js
const s = result.structuredContent ??
  JSON.parse(result.content.find(c => c.type === "text").text);
if (s.status !== "completed") {
  text({status: s.status}); // Follow the advertised resume flow.
} else if (!s.execution.ok) {
  throw new Error(JSON.stringify(s.execution.error));
} else {
  text(s.execution.value);
}
```

If the intended app is missing, inspect `unavailableApps` alongside
`status` and `execution` in the outer Executor payload. It is not part of
the tools.search value. Availability timeouts call for discovery in a fresh
execution, not a new connection or replay of a paused/mutating program.

Finish each delivered item with exactly its thread and claim IDs. Ordinary
discussion uses `reply`; new topics use `create`. Use the exact project identity,
including its worktree path. Preserve captures, resolution and human read state.

For code discussion, use `attach` for named file snapshots and `comparison`
for focused before/after text. A diff belongs in a comparison attachment.
Keep the conversational answer short. Neither attachment completes a claim.
Report an unavailable inbox or failed save rather than editing its database.
