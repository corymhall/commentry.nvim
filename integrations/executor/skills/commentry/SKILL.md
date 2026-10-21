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
submitted context. Comparison metadata marks primary evidence. A saved review
summary precedes the capture; a superseded initial agent finding stays available
through history rather than repeating in default context. Human questions remain
visible. Full read remains available for explicit complete inspection.

Use finish separately for each answer, passing its thread, claim_ids, author
and body. Return compact saved reply IDs from writes. Chat output alone does not
answer the inbox. Completion does not resolve a thread or acknowledge human reads.
Do not copy one item's answer into another.

## Code and ordinary discussion

For new review topics, discover publish and publications.read. Publish 1 to 25
independent items in one call with project, a durable request_id, author and
items. Each item has a unique key, title and body, plus optional source,
attachments with label/source, and comparisons with key/label/before/after.
primary_comparison is a comparison key within that item. Complete summaries and
evidence are saved together; do not follow publish with duplicate create or
revise calls. Receipts contain topic-to-thread and evidence IDs, not source text.

Save the manifest and request_id before calling. Repeating the same ID and
payload returns the original receipt without adding threads or overwriting
subsequent discussion. Different content at that ID is rejected. Use a new ID
only for a new submission. The entire publication commits or rolls back. After
a timeout or lost response, publications.read with project/request_id returns
complete receipts or missing. Missing while the original call is running does
not prove failure. Retry only the exact original manifest and ID. An Executor
approval/input pause must still use its resume interface, not a retry.

Use reply for discussion without a delivery claim, create for a new topic.
Keep project identities exact, including worktrees. Use attach with a
project-relative file source, one-based first/last selection coordinates and
available Git metadata. For a focused excerpt, set excerpt_first to the absolute
file line of lines[0]; include the selected range and useful nearby context.
For example first=401,last=401,excerpt_first=400,lines=["before","selected","after"].
Omitting excerpt_first means lines contains the entire file, starting at line 1.
Do not embed whole large files into codemode programs just to attach a selection.
Neovim captures full snapshots automatically for its own file selections.
An excerpt can follow uniquely matching code; changed or ambiguous selections
remain visible as saved excerpts instead of guessing a code destination.
attachment_id replaces a read location.
Use comparison for focused before/after text and a label, with a short reply
explaining it. Do not put long diffs in the conversational reply. Preserve the
original capture. Attachments alone do not finish claims.

## After fixing code

When changing code for a Commentry finding or request, refresh its affected code
attachments before posting the completion reply or calling finish. Use attach
with the existing attachment_id, final text, final one-based first/last range,
current project-relative path and available Git metadata. Use complete file
lines or an explicit excerpt with excerpt_first.
Refresh each affected location, including ranges shifted by the edit. Reuse
the existing attachment instead of accumulating old and new copies of it.

Use current attachment IDs and locations. Submitted request source and
section=attachment are frozen snapshots, so they do not prove what is attached
now. If current attachment state is not already known, inspect the thread with
read and project its result to attachments; avoid printing the whole thread.
If the finding only has an original capture, add a named current implementation
attachment. Never replace the original capture or rewrite a submitted request.
If the code was removed, attach a relevant surviving location or explain why
there is no current location rather than inventing a range.

When a previous comparison needs a post-fix view, add a focused comparison
labeled for the fix, with pre-fix code as before and final code as after.
Existing comparisons remain historical. Check attachment/comparison saves
before claiming the inbox is updated. If saving fails, report that the code
changed but its Commentry source could not be refreshed.

## Writing reviews

Publish one thread per independently reviewable topic, including intentional
changes, equivalent refactors and non-bug observations. A numbered report in
one thread is not a substitute. Keep responses to existing topics in their
original threads. When authoring or revising a review or comparison, read
[Writing reviews](references/reviews.md). Choose one clear primary example,
explain the consequence and current outcome, and give each independent decision
its own thread. A short shared overview can link topics and record baselines.
Verify that every identified topic has a saved thread before reporting the
review complete. Ordinary inbox replies do not need a review template.

Discover revise to maintain a current review title and summary without editing
the capture or chronological messages. Select primary_comparison deliberately;
supporting evidence is folded in the inbox. Pass the current review id as
expected_review when updating it. To correct your own comparison, pass its
comparison_id to comparison rather than appending conflicting evidence. Prior
versions are retained. Use archiveComparison to withdraw your own comparison
when it cannot be corrected. It leaves active evidence but stays in history.
Clearing primary_comparison with an empty string only clears the explicit
selection; the inbox otherwise falls back to its first active comparison.
Keep write results compact.

Rex discovery and native queue/steer submission stay on the user's machine.
The app never launches agent sessions. A failed or interrupted write may have
succeeded. Inspect the affected thread before retrying it. Never use migration
tools to modify an existing conversation.
