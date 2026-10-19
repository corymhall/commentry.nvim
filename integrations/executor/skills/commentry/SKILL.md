---
name: commentry
description: Read project conversations and answer delivered Commentry requests with bounded context.
---

Discover exact paths with a focused search for `commentry requests.read` and
`commentry finish`. No complete tool schemas or skills inventory are needed
for normal replies. Project discovery to the selected Commentry app's matching
path and input entries before printing; omit unrelated tools and catalog data.
When wrapping MCP in codemode, check status and execution.ok
and print only execution.value, not the whole text/structured result envelope.

## Delivered requests

Call requests.read with the notification's exact project and items. For an
older single-thread delivery, form one item from its thread and claim_ids.
Split manifests larger than 100 claims into groups of at most 100.
It returns at most five claims per page, with up to 2000 Unicode characters
of context each. Continue next_cursor with the same project and items.

Only claimed and failed statuses are answerable. Failed may be a lost delivery
acknowledgement. Do not resubmit it. Complete, cancelled, missing, superseded
or project-mismatch statuses require no answer or replacement claim.

Context is the saved submission, not messages that arrived later. Recent
submitted discussion comes first, newest message first. Earlier answered history is omitted and
counted in earlier_messages. Long preceding agent answers are explicitly
abbreviated; section=history retrieves them when relevant. Capture excerpts retain first/last and
excerpt_first coordinates. No queue history or full file snapshots are returned.

If context.next_offset is present, requests.context continues the same text
using project, thread, claim_id and offset. Read enough pages to understand the
complete submitted request before acting. Its limit is at most 4000 characters.
For a specific need, section=history gets earlier submitted messages,
source gets the saved excerpt, attachment with an id gets submitted code.
Section comparison lists current comparison metadata; supplying an id gets its
before/after content. These comparisons are current enrichment, not frozen
submitted context. Full read remains available for explicit complete inspection.

Use finish separately for each answer, passing its thread, claim_ids, author
and body. Return compact saved reply IDs from writes. Chat output alone does not
answer the inbox. Completion does not resolve a thread or acknowledge human reads.
Do not copy one item's answer into another.

## Code and ordinary discussion

Use reply for discussion without a delivery claim, create for a new topic.
Keep project identities exact, including worktrees. Use attach with a
project-relative file source, one-based first/last coordinates, complete file
lines and available Git metadata. attachment_id replaces a read location.
Use comparison for focused before/after text and a label, with a short reply
explaining it. Do not put long diffs in the conversational reply. Preserve the
original capture. Attachments alone do not finish claims.

Rex discovery and native queue/steer submission stay on the user's machine.
The app never launches agent sessions. A failed or interrupted write may have
succeeded. Inspect the affected thread before retrying it. Never use migration
tools to modify an existing conversation.
