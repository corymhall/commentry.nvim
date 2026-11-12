---
name: commentry
description: Use Commentry proactively for project decisions and substantial work handoffs, and to read, create and answer inbox conversations. Also use for COMMENTRY_BATCH_V1, COMMENTRY_THREAD_V1 or COMMENTRY DELIVERY.
---

# Commentry

Keep answers in the original inbox thread. Captures and messages are context.

Use Commentry for decisions only the user can make, substantial finished-work
handoffs, and ongoing code discussions. Keep ordinary progress in chat. A question
left in the inbox should not also block chat. If another agent delegated the work,
report to that agent instead. Do not duplicate reports into Plannotator unless
the user explicitly requests it.

When Pi exposes the native `commentry` tool, use it for common operations:
`{action: "requests.read", input: {items: [{thread, claim_ids}]}}`, followed by
`{action: "finish", input: {thread, claim_ids, body, request_id}}`.
The tool supplies project scope and defaults author to pi. Fetch before acting,
even when a notification preview looks sufficient. Follow continuation cursors.
Use create or reply for ordinary conversation without a delivery claim. Keep
one work stream in one thread, passing its ID for followups. Use the existing
list/read operations to recover context rather than creating duplicate threads.
Do not manage local receivers or terminal keys yourself.

Common native inputs, all scoped to the current project:
- list: `{filter?: "unread" | "open" | "resolved"}`, returns compact summaries.
- read: `{thread}`, explicit complete-thread inspection.
- create: `{title?, body, text?}`, returns the new thread ID.
- reply: `{thread, body, request_id}`, no delivery claim.
- requests.context: `{thread, claim_id, offset?, section?, id?}`.
- publish: `{request_id, items}`, using the review guide's topic format.
Do not blindly retry create after a lost response. Inspect list/read to recover
the thread first. Replies and finish use a retained request_id for safe retries.

With native tools, use their action/input contract instead of discovering
Executor for each call. The remaining discovery guidance applies when the
native tool is absent or a needed operation is not exposed.

When asked to put a review or comparison in the inbox, create one item per
independently reviewable topic, including intentional changes and observations
that are not bugs. A single report with numbered topics is not a substitute.
Keep replies to an existing topic in its original thread. Read
[Writing reviews](references/reviews.md) before publishing review topics.

For new review topics, discover `commentry publish` and `commentry publications.read`.
Publish complete items with evidence in one call, using a saved request_id and
unique item keys. After a lost response, look up that request or retry exactly
the same ID and payload. Do not rebuild it under a fresh ID. Focused file
excerpts use excerpt_first, the one-based file line of lines[0]. See the app
skill for the complete input and retry contract.

Without the native tool, read the selected Executor server's entry skill if it is not already loaded.
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
for focused before/after text. Publish includes both without separate writes.
A diff belongs in a comparison attachment.
When fixing code discussed in Commentry, refresh the affected code attachments
before reporting completion. Reuse their `attachment_id` with final text, path
and line range. Send complete file lines or an explicit excerpt with excerpt_first.
If only an original capture exists, add a current
code attachment instead. Preserve the original capture and submitted requests.
The app skill explains current versus frozen sources and fix comparisons.
Keep the conversational answer short. Neither attachment completes a claim.
Report an unavailable inbox or failed save rather than editing its database.

The review guide covers explanations, evidence and follow-up decisions. Ordinary
questions, notes and replies do not need a review template.
