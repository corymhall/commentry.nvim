# Commentry Executor app

This app owns the universal inbox in Executor's per-app SQLite database.
Neovim and the Go CLI are clients of the same operations agents call from
Executor codemode. Git capture, source comparisons and Rex delivery stay local.

The source pins the host's `apps` framework version. `migrations/` is the schema;
applied migrations must never be edited. Inbox state and its change cursor are
committed in the same synchronous transaction. No transaction waits on a network
request or terminal operation. A stored thread is subject to Executor's 2 MB
SQLite row limit.

Run `mise run setup_executor` once, then use `mise run lint_executor` and
`mise run test_executor` from the repository root. Tests execute these same
operations against isolated Node SQLite databases without a live Executor.

Deploy this directory with Executor's app-management create/commit/deploy
workflow. Use the existing app ID on updates. A Git commit or saved source alone
does not activate a deployment. Do not upload node_modules, credentials, test
fixtures or lockfiles. The canonical source lives in this repository.

Connect a machine with `commentry executor login --url ORIGIN --organization ORG
--app APP_ID`. The browser device flow requests `executor offline_access` for
that origin's API. Private session files live in the selected Commentry directory.
Pending sign-ins resume after interruption; refresh-token rotation is serialized
across CLI processes. Configured remote failures never write to legacy SQLite.

Use the packaged `commentry` skill for the agent workflow. Native tools have
explicit input and output schemas. `rpc` preserves the CLI protocol; its queue
operation persists a snapshot but never reaches local Rex. `finish` completes
only supplied active claims and preserves the conversation's resolution state.

Named cross-project inboxes use optional `inbox` on create, list, changes and
publish, and on publication receipt lookups. `project` remains the originating
project. Project-only queries exclude named inboxes; unscoped queries include all
destinations. Named inboxes do not support agent queueing or delivery. Migration
0003 adds destination indexes and scopes publication receipts by inbox as well as
project and request ID, preserving existing receipts. Deploy this migration and
app together before updating clients. Named inboxes use the existing app access
boundary, not a new cross-account permission model.

Optional acting Pi session metadata is retained in each thread's JSON state as
`session_activity`; no SQL migration is needed. Deploy the updated app before
reloading the native Pi extension to enable automatic attribution. Direct
Executor callers must supply their actual session explicitly. Read-only tools
do not record visits. Existing untagged history stays unknown.

For cutover, keep clients idle, export and back up the old database, import the
snapshot, verify it, then select the remote backend. Imports preserve IDs,
timestamps and original captures. A conflicting existing thread aborts its
entire batch. The legacy Go store remains available for explicit export and
offline tests, and does not share writes with a configured Executor inbox.
