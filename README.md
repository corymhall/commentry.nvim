# commentry.nvim

Neovim plugin for a project-scoped conversation inbox, local diff reviews,
persisted comments, and optional agent handoff.

## Universal inbox

The inbox works independently of Diffview:

- `:Commentry comment` captures the current file line and opens a multiline
  comment editor. `:'<,'>Commentry comment` captures a visual line range.
- `:Commentry capture-text` comments on text from the unnamed register.
  `:Commentry capture-text +` uses the system clipboard when a clipboard
  provider is available.
- `:Commentry inbox` opens the current project's unresolved threads. The list
  is on the left, the conversation in the middle, and any source or diff on the
  right. Without source content, only the list and conversation are shown.
  `:Commentry inbox all` shows unresolved threads across all projects.
- `:Commentry new-thread` starts a project conversation with no selection,
  clipboard contents, or file anchor. Press `n` inside the inbox for the same action.

New Neovim comments and project threads save as pending reviews. In the inbox,
`ge` edits a pending comment and `gd` discards it after confirmation. `r` also
opens the editor for pending comments. Saving does not queue delivery. `s` sends
one thread and `gs` sends new project comments. Queuing freezes the comment,
even if delivery fails or is cancelled. After sending, `r` adds a reply instead.
The captured source stays unchanged when editing. Existing conversations are
not converted to pending reviews.

The editor uses `Ctrl-s` or normal-mode `Enter` to save. Normal-mode `Esc`,
`q`, or `Ctrl-c` cancels. Insert-mode `Esc` returns to normal mode. The inbox uses
`j`/`k` in its list to select a thread, `r` to reply, `x` to resolve or reopen,
`gs` to send all new project comments to the agent queue,
`za` to fold source sections, `e` to expand or collapse surrounding code,
`i` to inspect capture and Git details, `?` for help, `R` to refresh,
and `q` to close. `Ctrl-h/j/k/l` moves between panels. Plain `h/j/k/l` retains
normal text navigation. Resolving also marks the item read. Reopening preserves
read state, and later incoming activity can make a resolved item unread again.
Closing an inbox panel with a native window command
closes the inbox view; `:Commentry inbox` opens it again.
Message headers use full-width highlighted bands with bold uppercase author
labels and non-italic timestamps. Taller windows add a row of header padding;
short windows keep compact single-row bands. Colors follow the active theme.
The `CommentryInboxMessageHeader`, `CommentryInboxMessageHuman`,
`CommentryInboxMessageAgent`, `CommentryInboxMessageTime` and
`CommentryInboxMessageFoldText` highlight groups can be customized.
The latest message from `You` and the latest agent message stay expanded by
default; older messages collapse into one-line author, time and text summaries.
Consecutive folds stay compact, with one blank row before the next expanded
message. `za` toggles a message and `zR`
expands all messages. Manual fold choices survive refreshes and thread switches.
Messages remain in chronological order, and the reply area is never folded.
Replies live beneath the conversation in the thread buffer. Press `r` to start
editing, `:write` to save the reply, then `s` to send it. In the source pane,
select text visually and press `r` to quote it into the reply with `>` prefixes.
Diff markers are preserved and display-only line numbers are omitted.
In the conversation pane, visual `mc` quotes selected text into the reply.
Visual `mn` opens a new thread composer with the selection quoted and retains
it as a text capture linked to the original thread. Save or send explicitly.
With Snacks animations enabled, jumping to code briefly highlights the target
range and newly arriving agent messages fade into the conversation. Disable
these effects with `vim.g.snacks_animate = false` or its buffer-local equivalent.
Unsaved replies survive thread switches and closing/reopening the inbox during
the current Neovim session. While a reply is modified its displayed history stays
fixed; saving reloads the latest conversation. Changes to existing history are
rejected on save. Undo those changes and write only beneath the reply heading.
The thread buffer keeps normal editing keys such as `i`, `a`, `u`, `d`, and `x`.
Use the list or source pane for filtering, resolution, and other inbox actions.
Below 140 editor columns, source content stacks beneath the conversation.
At larger widths, the conversation is in the middle and source is on the right.
The source pane appears only when there is captured text, code or a comparison
to display. Standalone conversations use the full space beside the list. The
layout adapts when resized without overriding manually resized panes on thread
selection or refresh. No colorscheme overrides are added. Open Commentry in
your normal Neovim configuration to use your theme and configured integrations.

Press `gy` in any inbox panel to copy a reference to the selected thread to
the system clipboard. Paste it into another agent session to ask it to read
the thread. The reference contains the project path and thread ID, not the
conversation contents. It does not send or mark the thread read.

Press `/` in the list or `g/` in any inbox panel to find a conversation by
search. Search previews never mark threads read. `Tab` and `Shift-Tab` cycle
panels. `gz` maximizes the focused panel and restores its layout on a second
press. These navigation keys work in normal mode, leaving insert-mode editing
unchanged. Panel proportions adapt on every resize, not only at the breakpoint.
Compact status labels distinguish drafts, saved unsent replies, queued work,
requests not yet fetched, and requests awaiting answers. Inbox counters show visible threads and unread
activity. Key hints live in panel statuslines and `?` rather than crowded titles.
Popups use NUI for consistent borders, padding and resize handling.

### From copied text to code

Capture questions, answers or notes from your agent conversation as inbox
items. Agents can answer the same thread and use Executor's `attach` tool to
add named code locations with saved file snapshots and Git information.
The copied text remains the original capture. Supplying `attachment_id`
replaces that location while preserving its ID. Agent attachment updates become
unread, and do not resolve the conversation.

Agents publish new review topics with Executor's `publish` tool. One call saves
1 to 25 separate items with summaries, code locations and comparisons. Each
submission has a durable `request_id` and each topic has a unique `key`.
`publications.read` recovers the compact receipts after a lost response.
Retrying the exact same ID and payload returns the original thread IDs;
different content at that ID is rejected. A submission commits completely or
rolls back completely.

File sources may contain a focused excerpt. `first` and `last` remain absolute
selection lines; `excerpt_first` is the absolute file line of `lines[0]`.
For example, a selection at line 401 can use `first=401`, `last=401`,
`excerpt_first=400` and three lines of text. Omitting `excerpt_first` retains
the complete-file format. Excerpts follow uniquely matching code. Changed or
ambiguous locations remain saved excerpts instead of guessing a destination.
Neovim's own file captures continue to save complete snapshots automatically.

The source pane shows saved agent comparisons, every attached code location,
and the original context together. A review's chosen primary comparison appears
first, with supporting evidence folded. Without an explicit choice, the first
saved comparison stays first as more evidence arrives. Comparisons are labeled
as saved before/after text, which may describe a proposal. Code sections
show current local excerpts, or a focused diff labeled **Changed locally since
attached** when they differ from the saved snapshot. Missing files show a
**Saved snapshot** instead. Original code context and long copied excerpts start
collapsed; `za` folds or unfolds any section. Fold choices survive refreshes.

Agents use `revise` to maintain a short current review title and summary above
the discussion, and choose `primary_comparison` by its saved ID. Updating a
summary requires `expected_review` with its current review ID. The original
capture and messages remain intact. Original findings follow the same
message-folding policy. An original finding stays expanded if it is still the
latest agent message; otherwise it starts folded.
`comparison_id` replaces an agent's own comparison while retaining its ID and
prior content in history. These updates become unread without resolving the
conversation or changing previously submitted requests.
`archiveComparison` withdraws an agent's own misleading comparison from the
active view while preserving its history.

Press `gl` to jump to a section. `gf` opens the file for the code section under
the source cursor in your original editing window. Saved comparisons without a
code location never guess a file. In other panels, `gf` uses the source section
or defaults to the first code location. Changed or ambiguous destinations stay
visible in the inbox. Visual `r` quotes include the section's location or label.

Code buffers show gutter markers for open threads loaded from the inbox, with a
range highlight and short reply preview for the active thread. Markers update
from cached snapshots as you edit, without backend calls on keystrokes. `gC`
returns from a visited code buffer to the thread under the cursor, offering a
picker for overlapping threads. It is installed only if that key is free.
`<Plug>(CommentryThread)` is also available for your own mapping.
Inbox refresh loads new attachments and replies.

The CLI equivalent is `commentry attach t-THREAD --label Implementation
--source-file capture.json --author codex`. The source JSON uses the file capture
shape, with a project-relative path, one-based first/last lines, the entire
file's lines, and optional filetype, modified and Git metadata.

### Executor backend

The Commentry Executor app owns inbox conversations, captures, comparisons,
read state, request claims and agent selections in its SQLite database. Agents
use the same operations through Executor codemode. The local Go CLI handles
capture, Git context, native Pi delivery and Rex terminal delivery, and forwards inbox operations
to the configured app. Executor never starts or controls local terminals.

Deploy the app source in `integrations/executor` to your Executor instance,
then sign this machine in:

```sh
commentry executor login --url https://YOUR_EXECUTOR \
  --organization ORGANIZATION --app APP_ID
commentry executor status
```

Login prints a browser link and code. Approve it in Executor. Credentials stay
in the local private session file and refresh automatically. No credentials are
included in agent prompts. The session grants Executor API account access.
Neovim keeps using the CLI and needs no separate account configuration.

For an existing local inbox, export it before login, keep a backup, then import
that snapshot after connecting:

```sh
commentry executor export > inbox-backup.json
# Run executor login, then:
commentry executor import --file inbox-backup.json
```

Import preserves thread/message IDs, timestamps, original captures, read state,
resolution state and requests. A conflicting existing thread aborts the batch.
Keep other inbox clients idle during export and cutover. Existing local SQLite
files stay untouched. An unconfigured directory uses the legacy local backend
for migration and offline tests; once configured, unavailable Executor calls
fail visibly and never fall back to local writes. Offline capture is deferred.
`--directory` selects the local connection/configuration directory.

In codemode, discover tools in the installed app namespace, normally
`commentry`. Use `publish`, `publications.read`, `list`, `read`, `create`, `reply`, `finish`, `attach`, `comparison`,
`revise`, `archiveComparison`, `readState`, `resolve`, `changes`, and `revision`.
A delivered request supplies
its thread and claim IDs. `finish` saves the answer and completes those claims
atomically without resolving the conversation. `reply` adds a comment without
completing a delivery claim. The packaged `commentry` skill explains this flow.
Delivered comments use `requests.read` with the notification's project and items.
It returns at most five claims per page and 2000 Unicode characters of context
per claim. Continue with `next_cursor`; use `requests.context` and
`context.next_offset` for more text. Earlier answered discussion is available
through its history section. The saved submission excludes later replies.
Inactive claims return status only. The read mutation acknowledges fetched claims
and includes bounded recent history and section metadata. Full `read` remains the editor's complete
thread protocol. Print Executor's checked execution value rather than both MCP
response representations.

Project identities are canonical checkout paths supplied by the local client;
matching other machines' checkout paths is not automatic.

### Delivery receipts and recovery

Submission to the harness is not proof the agent read a request. Claimed work
shows **Submitted / Not acknowledged** until the agent calls Executor's
`requests.read`. That mutation records `acknowledged_at` only for the returned
page. It does not mark human activity read, complete work, or resolve threads.
Fetched work shows **Fetched / Awaiting answer**.

Press `gn` in the inbox to notify again about an outstanding request, retaining
its snapshot and claim. Repeated notifications are reminders, not new work.
To use a different selected agent, explicitly choose handoff. Handoff invalidates
the old claim before redispatching the same request. A late old answer is rejected.
The CLI equivalent is `commentry agent --project . notify t-THREAD --queue-id
e-REQUEST`, adding `--handoff` only for an intentional change of agent.
A reminder is not a guarantee against an agent independently repeating effects.

Context reads include bounded recent history, available sections, and the
current and submitted last message IDs, separate from the frozen submission. Large context
still requires continuation. Legacy local clients acknowledge with
`commentry acknowledge t-THREAD --claim-id claim-ID`.

Use a durable `request_id` on `reply` and `finish`, or CLI `--request-id`.
Exact retries return the original receipt without another message; changed
content at the same ID is rejected. Finish saves the answer and completes the
specified claims atomically, without resolving the thread. Answer in the original
inbox thread rather than only terminal chat.

### Read state and filters

`*` marks unread activity. Messages, code attachments and comparisons authored by anyone other
than the local `You` label are incoming activity. Own replies do not clear unread
messages. List previews leave unread state intact. `Enter`, or moving into the
conversation panel, marks the displayed activity read. Agent comparisons appear
automatically as labeled sections in the source pane.
A newer concurrent reply
stays unread. `u` explicitly toggles read/unread. Agent CLI reads never consume
the human reader's unread state.

The default filter is **open**, excluding resolved threads in both project and
all-project views. Press `f` for all, unread, read, open, resolved, or queued
filters. Choose **all** or **resolved** to revisit resolved conversations. An
explicitly requested resolved thread remains visible until `R` or a filter
change. Commands such as `:Commentry inbox unread` open a project filter directly. `:Commentry inbox
all` still selects all projects; use `f` to filter that scope. A thread opened
from the unread filter remains visible while you read it. `R` or changing filters
reapplies the filter. External writes refresh approximately every 1.5 seconds
while the inbox is active in normal mode, retaining the selected thread and
scroll position. `R` also refreshes comparisons after source edits.

### Pi session provenance

Threads retain optional `session_activity` entries identifying the Pi session
that performed each recorded mutation or fetched an active request. Entries
include the action, timestamp, event or message ID, and applicable claim IDs.
This is separate from the delivery target. A replacement session can fetch or
answer a request without rewriting the original session attribution.

The native Pi tool supplies the current session ID automatically. Direct
Executor mutations and `requests.read` accept optional
`session: { harness: "pi", id: "<actual Pi session ID>" }`. Omitted identity
remains unknown, including historical actions. These are caller provenance,
not authenticated session ownership or evidence that an agent is working.
Read-only inspection is not logged.

Full thread reads expose the activity log. For delivered requests, fetch
`requests.context` with `section: "sessions"` and follow `next_offset` to
inspect it without loading full captures. Use a recorded session ID with
`evaler session show SESSION_ID` or `evaler session search SESSION_ID --query "phrase"`
when Evaler has access to that session. Transcripts are not uploaded to Commentry.
Retries keep original attribution and do not add duplicate replies or fetches
from the same session for the same claim.

### Native Pi integration

Requires Pi 1.5+ on macOS or Linux. Install the CLI and load the local Pi package:

```sh
mise run install-commentry
pi install /absolute/path/to/commentry.nvim/integrations/pi
```

Install the shared `skills/commentry` skill in your agent's skill directory if
it is not already discoverable. Restart Pi or use `/reload`. The extension
activates its `commentry` tool only in interactive or RPC sessions with a
configured Executor connection. Authentication stays in the Go client.

In Rex, the extension owns a private Unix socket for its foreground process.
The CLI verifies the target, Pi session, project and inbox directory before
submitting through Pi's native follow-up or steering API. It never pastes into
the composer or presses terminal keys. Socket acceptance is separate from
agent fetch acknowledgement and answer completion. Lifecycle shutdown closes
the receiver; a stale or unavailable receiver fails visibly.

Select the running Pi through the existing inbox agent picker. Threads remain
session-independent. Queue and steer controls are unchanged. `/commentry`
opens the project's Neovim inbox through the existing Rex opener. Outside Rex,
the extension provides tools and guidance but no receiver for agent selection.

Pi delivery now requires the native extension by default. For an intentional
terminal-only fallback, set `COMMENTRY_PI_TRANSPORT=rex` in the environment of
the CLI or Neovim. Native errors never trigger fallback. Codex continues through
Rex. A custom `COMMENTRY_INBOX_DIR` must agree between Pi and Neovim.
`COMMENTRY_EXECUTABLE` selects the CLI for the extension; otherwise it prefers
`~/.local/bin/commentry`, then PATH. `COMMENTRY_PI_RUNTIME_DIR` can override the
private socket directory, normally `/tmp/commentry-pi-UID`.

The extension briefs new sessions to use Commentry for decisions and substantial
handoffs. Detailed operation and recovery guidance stays in the skill.
Plannotator is optional. To enable it for one session without globally
installing its extension:

```sh
pi -e npm:@plannotator/pi-extension
```

That opt-in session can receive Plannotator's own tools and guidance. Do not
publish the same question or report into both inboxes by default. No web UI,
cross-machine project identity, or general-purpose background bridge is added.

Run `mise run test_pi` for isolated socket tests. With Pi installed,
`mise run smoke_pi` exercises the real host, native delivery, a controlled
same-thread reply and session replacement without model calls or user inbox data.

### Existing agents through Rex

The inbox sends requests to Pi or Codex already running in Rex. Press `S` to
select an agent in the current worktree. If none is found, the picker shows
agents in other worktrees of the same repository. Separate clones are excluded.
Rex supplies discovery, process identity,
status and terminal delivery for Codex or explicit Pi fallback. Pi normally uses
the native extension. The harness manages its own native queue.
Agent discovery and delivery use the existing Rex session.

Load the reusable actions in Rex `init.lua` and run `rex config reload`:

```lua
dofile("/path/to/commentry.nvim/integrations/rex/agents.lua").setup()
```

The actions work independently of Commentry:

```bash
rex do agent_list
rex do agent_list project=/absolute/project/path
rex do agent_get target='TARGET_ID_FROM_LIST'
rex do agent_queue target='TARGET_ID_FROM_LIST' text='Review this change'
rex do agent_steer target='TARGET_ID_FROM_LIST' text='Also check cancellation'
rex do agent_read target='TARGET_ID_FROM_LIST'
rex do agent_focus target='TARGET_ID_FROM_LIST'
```

Targets from `agent_list` identify the Rex session, pane and foreground process.
A restarted or replaced agent requires selecting its new target. `agent_list`
filters directories by the supplied absolute path and its descendants.
Commentry additionally resolves Git roots when selecting project agents.
`agent_get` reports the current status. `agent_read` returns terminal text,
not a structured conversation transcript. OpenCode is not implemented.

Press `gs` in the inbox to send all open threads with new comments from you,
including threads hidden by the current filter. It always uses the native agent
queue as one compact notification. The agent fetches each thread and its
submitted snapshot through Executor, then replies to each thread separately.
Notifications include up to 1200 Unicode characters of the newest submitted
human message per request, with an explicit truncation flag. Captures and full
history stay behind the context tools. In the all-projects view it uses the selected thread's project.
Resolved threads, agent-only notes and already delivered comments are skipped.
Existing pending requests are delivered without adding copies. With no agent
attached, requests are saved for delivery. Attaching an agent batches pending
queue requests into one notification, with separate claims for each thread.
Pending steer requests remain separate and preserve their delivery order. The
result reports sent, saved and skipped counts, or threads needing attention. Failed requests still require
explicit retry after inspection.

The new-thread composer uses `Ctrl-s` to save and `Ctrl-d` to save and send.
Inline replies use `:write` to save, followed by `s` to send. Press `m` to
choose queue or steer, then `s` to send the selected thread. Both modes submit
immediately, including while the agent is working. Pi normally uses its native
extension APIs. For terminal delivery, the adapter keys are:

| Harness | Queue | Steer |
| --- | --- | --- |
| Codex | Tab | Enter |
| Pi | Alt-Enter | Enter |

Queue uses the harness's native follow-up behavior. Steer uses its direct
submission behavior. When idle, the harness can begin processing immediately.
There is no Commentry worker waiting for idle and no new agent session.
Terminal delivery uses bracketed paste and the submission key in one write.
That fallback uses the existing composer, which should be clear of unfinished
drafts. Native Pi delivery does not touch the composer.
Blocked, unknown and error states require attention before delivery. Status
reports must identify the foreground process. Approvals stay in the agent UI.

For customized harness keybindings, pass adapters to `setup` instead of using
its defaults. Values are terminal byte sequences:

```lua
dofile("/path/to/agents.lua").setup({
  adapters = {
    codex = { queue = "\t", steer = "\r" },
    pi = { queue = "\27[13;3u", steer = "\r" },
  },
})
```

Commentry retains immutable request snapshots, thread IDs and claim IDs for
reply attribution. Delivered requests include instructions for `commentry finish`
or JSON RPC. This saves the answer and completes the specific claim atomically.
Pending means locally waiting for delivery. Sent means submitted to the harness.
Terminal writes and status changes do not automatically complete a request.
Completion does not resolve a conversation. Agents can attach focused comparisons
while preserving the original capture.

Sending an unchanged active request shows "Nothing new to send. There are no
new messages."
With no selected agent, requests remain queued in the inbox. Selecting an agent or
using `a` to deliver pending requests sends them to its native queue. Press `a`
for status, focus, selection and detach. Detaching leaves delivered work intact.
A failed or partial write is never replayed automatically. Inspect the agent
before retrying with `t`. Sending the same failed snapshot keeps its failure
visible. A late agent answer can still finish its original claim until that
request is explicitly retried. Cancelling an inbox claim does not remove work already
submitted to the harness's native queue.

```bash
commentry agent --project . list
commentry agent --project . attach 'TARGET_ID_FROM_LIST'
commentry agent --project . status
commentry agent --project . dispatch
commentry agent --project . steer t-THREAD
commentry agent --project . detach
commentry retry t-THREAD --queue-id e-REQUEST
commentry finish t-THREAD --claim-id claim-ID --author codex --body 'Reply'
```

Agent payloads retain original selection coordinates. `excerpt_first` identifies
the original file line represented by `lines[0]` in a focused excerpt.

### Clipboard capture through Rex

Install the binary with `mise run install-commentry`, then load
`integrations/rex/commentry.lua` from your Rex `init.lua`.
The actions extend Rex's PATH with `~/.local/bin`, `REX_BIN_DIR` or the managed
macOS Rex install directory, and the standard Homebrew directories. This makes
Commentry's nested `rex` and `nvim` commands available even when Rex was launched
without your shell's PATH:


```lua
dofile("/path/to/commentry.nvim/integrations/rex/commentry.lua")
rex.bind("ctrl+a>a", "commentry_capture")
rex.bind("ctrl+a>shift+a", "commentry_new")
rex.bind("ctrl+a>i", "commentry_inbox")
```

The actions also appear in Rex's command palette. `commentry_capture` snapshots
the macOS clipboard immediately, infers the project from the originating pane's
directory, and opens a temporary **New comment** tab. The tab shows the
captured text above a multiline editor. `Ctrl-p` changes the project, `Ctrl-s`
saves, `Ctrl-d` saves and queues, and normal-mode `q` or `:q` cancels. Saving or
cancelling returns to the originating tab. Failed saves retain the draft.
If sending fails after saving, the editor stays open with delivery guidance.
`Ctrl-s` closes the saved capture. Inspect the inbox before retrying delivery.
`commentry_new` opens the same editor without a clipboard attachment.
`commentry_inbox` reuses Neovim in the current pane or an immediately adjacent
pane on either side in the same Rex window. Otherwise it creates a pane to the
right and starts Neovim there. Existing editors receive the inbox through RPC
when available. Editors without a listener receive a Normal-mode command.
Both paths preserve unsaved buffers
and their working directory.
Invoking from a recognized agent pane selects that existing agent for the
project inbox, without submitting pending requests. The equivalent shell
command is `commentry rex inbox`.
The editor uses your normal Neovim configuration and theme.
The Lua entry point also accepts an explicit project with
`require("commentry.inbox").open(nil, { project = "/path/to/project" })`.

From a shell, use `commentry capture --project .`, or add `--empty` for a
standalone conversation. `commentry rex capture` opens a temporary tab when
`REX_SESSION` and `REX_BLOCK` identify the origin. `--client` selects the Rex
app explicitly when needed. The `rex` executable must be on PATH.
This first capture integration is local to macOS and uses Neovim 0.10+ as its
editor. The Rex keybind applies while Rex is focused; it is not an OS-wide hotkey.

The list shows titles above compact location/status labels. Diffs show original
and current line numbers with theme-linked addition and deletion highlights.
Conversations emphasize authors and message bodies; detailed provenance is
available through `i`. Surrounding code expands from four to sixteen lines
with `e`. Highlight groups use the `CommentryInbox` prefix and inherit the
active colorscheme.

File captures preserve the entire buffer, including unsaved changes, the exact
selected range, and available Git HEAD, branch, and original blob identity.
The source pane compares the surrounding region with the current buffer or
file. Changes above the selected region are accounted for. When the selected
code changes, the thread remains in the list with an `Outdated` label and an
explicitly approximate diff. Missing files retain the original excerpt.
Original captures remain in the Original context section. Resolution and location state
are independent. Complex moves can require an agent-authored comparison.

Projects use the canonical Git worktree root, or the containing directory
outside Git. Inbox scope is project-wide across branches. Captured branch
information is provenance, not a filter. Separate worktrees currently have
separate project scopes.

### Capture and agent replies outside Neovim

Build the Go client with `mise run build`, or install it with
`mise run install-commentry`. The checked build fails if a different `commentry`
executable appears first on PATH. Install the new binary or adjust PATH, and
ensure Neovim uses the same PATH. The `commentry` executable must be on PATH for
Neovim, Rex and external tools. For a checkout build, add the checkout's `bin/`
directory to PATH.

`commentry rpc` reads one JSON request from standard input and returns one JSON
response. `scripts/commentry-inbox` forwards to that binary. Neither interface
requires Neovim to run.
Use an absolute project directory to choose a project, or omit it on creation
to use the invoking directory. For example, from this checkout:

```bash
./scripts/commentry-inbox <<'JSON'
{"action":"create","title":"Explain this output","text":"Found two matching excerpts.","body":"Show both candidate locations."}
JSON
```

The response contains `{"ok":true,"result":"t-..."}`. Use that returned ID:

```json
{"action":"list","project":"/absolute/project/path"}
{"action":"read","thread":"t-..."}
{"action":"reply","thread":"t-...","author":"Agent","body":"Here are the two candidates."}
{"action":"comparison","thread":"t-...","author":"Agent","label":"Split implementation","before":"old code\n","after":"new code\n"}
{"action":"resolve","thread":"t-...","resolved":true}
{"action":"list","project":"/absolute/project/path","filter":"unread","summary":true}
{"action":"read-state","thread":"t-...","read":true,"seen":"e-incoming-version-from-read"}
{"action":"queue","thread":"t-..."}
{"action":"claim","project":"/absolute/project/path","author":"Agent"}
{"action":"complete","thread":"t-...","claim_id":"claim-..."}
{"action":"cancel","thread":"t-...","queue_id":"e-queued-request"}
```

To create an editable human comment through RPC, include `pending: true` in
`create` and omit `author` or use `"You"`. Read the thread, then pass its initial
`messages[0].id` as `expected_message` to `edit-pending` with a new `body`, or to
`discard-pending`. Each edit changes that message ID. Stale edits and discards
are rejected. Captured source is never replaced. The first successful `queue`
transaction clears `pending` permanently. Existing conversations and agent
publications are not made editable by this API.

Omit `project` from `list` to list every project. Comparison text is recorded
verbatim. All attached comparisons appear automatically in the source pane,
each labeled with its author and timestamp. This never
overwrites the original capture or edits source files. Authors are
caller-provided labels. Failed requests return
`ok: false` and exit nonzero. `summary: true` excludes full buffer snapshots from
list output. Claims are serialized and project-scoped; a claim returns an
immutable message and a claim ID. Completing it does not resolve its thread.
Cancelled work cannot later be completed. SQLite transactions serialize claims
and recover unfinished writes after a crash. A committed claim remains visible
until completed, explicitly cancelled, or explicitly marked failed after uncertain delivery. It is never automatically reassigned.

Executor owns the configured inbox database. The local connection files live
at `stdpath("data")/commentry/inbox/executor.json` and
`executor-session.json`. The standalone CLI defaults to
`$XDG_DATA_HOME/nvim/commentry/inbox` or `~/.local/share/nvim/commentry/inbox`,
respecting `NVIM_APPNAME`. Set `COMMENTRY_INBOX_DIR` or pass `--directory` to
select another connection directory. Neovim passes its actual data directory.
Mutations and change records commit in the same Executor SQLite transaction.
The legacy `inbox.sqlite3` is retained for explicit export and isolated tests.
Earlier prototype event files remain untouched. There is no deletion interface.

The same operations have shell commands with JSON output:

```bash
./bin/commentry create --project . --title 'Explain this' --body 'How does this work?'
./bin/commentry list --project . --filter unread --summary
./bin/commentry reply t-THREAD --author Codex --body 'Here is the explanation.'
./bin/commentry queue t-THREAD
./bin/commentry claim --project . --author Codex
./bin/commentry complete t-THREAD --claim-id claim-CLAIM
./bin/commentry comparison t-THREAD --author Codex --label 'Updated code' --before-file old.lua --after-file new.lua
./bin/commentry watch --project . --after 0 --timeout 60s
```

`watch` streams JSON lines containing committed changes, an opaque integer
`cursor`, and the latest `revision`. It emits an initial page, then waits for
activity until interrupted or the optional timeout expires. Resume with
`--after CURSOR`, using a cursor from the same database. `changes --after CURSOR`
returns one page of up to 100 changes. `revision` reads the latest sequence.
The equivalent JSON requests use `action: "changes"` with `cursor`, or
`action: "revision"`. Reading threads and watching changes never marks them read.
Use `read-state --read --seen e-VERSION` to acknowledge the version displayed,
or `read-state --read=false` to mark unread. Author labels are not authentication.
Neovim detects committed revisions automatically while the inbox is idle.

OpenCode support, anchor reattachment, branch comparison mode and an OS-wide
capture shortcut remain follow-up work. Removing local connection files does
not delete the Executor inbox.

## Install

Required:

- Neovim 0.10+
- [`nui.nvim`](https://github.com/MunifTanjim/nui.nvim) for padded, resizable popups
- The Commentry CLI on PATH, configured with `commentry executor login`
- The Commentry Executor app

Optional integrations:

- `diffview.nvim` for reviewing Git changes and capturing either diff side
- `snacks.nvim` for fuzzy conversation search with Markdown previews. Without it,
  conversation search uses your configured `vim.ui.select` provider
- Rex for clipboard capture and delivery to an existing coding agent

```lua
{
  "corymhall/commentry.nvim",
  dependencies = { "MunifTanjim/nui.nvim" },
  opts = {},
}
```

## Setup

```lua
require("commentry").setup({
  diffview = {
    enabled = true,
    auto_attach = true,
    comment_cards = { max_width = 76, max_body_lines = 6, show_markers = true },
    comment_ranges = { enabled = true, line_highlight = true },
  },
  keymaps = {
    add_comment = "mc",
    add_range_comment = "mc",
    list_comments = "ml",
  },
})
```

## Diffview

`:Commentry open` opens Diffview for local changes. Arguments pass through to
Diffview, for example `:Commentry open main...HEAD`. Direct `:DiffviewOpen`
usage also attaches Commentry when `auto_attach` is enabled.

`mc` opens the inbox composer for the current line. In Visual mode it captures
the selected range. `Ctrl-s` saves directly to the project inbox. The saved
source contains the displayed side's text, path and revision, including base
versions, staged changes, renamed paths and deleted files. It never captures
Diffview's scratch-buffer name as a path. Empty and binary sides cannot be
commented on.

Inbox threads show persistent boxed multiline comment cards below matching
diff lines, with start/end gutter marks and subtle range highlighting. Cards
follow the latest reply. `gC` opens the thread at
the cursor, or offers a choice when several threads overlap. `ml` opens the
project inbox, where replies, read state, resolution and Rex delivery work the
same as any other conversation. Comments on changed or deleted code remain in
the inbox with their original source.

### Global keymaps

Calling `setup()` installs these mappings in normal buffers and Diffview.
Set `vim.g.mapleader` before calling `setup()`.

| Action in `global_keymaps` | Default | Mode |
| --- | --- | --- |
| `add_comment` | `<leader>cc` | Normal, comment on current line |
| `add_range_comment` | `<leader>cc` | Visual, comment on selected lines |
| `edit_comment` | `<leader>ce` | Normal, edit pending comment at cursor |
| `new_thread` | `<leader>cn` | Normal, new unanchored project thread |
| `inbox` | `<leader>ci` | Normal, project inbox |
| `unread` | `<leader>cu` | Normal, project unread inbox |
| `all_projects` | `<leader>ca` | Normal, inbox across all projects |
| `clipboard` | `<leader>cp` | Normal, comment on clipboard text |
| `open_diff` | `<leader>cd` | Normal, open Diffview |

Override individual keys or use an empty string to disable them:

```lua
require("commentry").setup({
  global_keymaps = {
    inbox = "<leader>ci",
    clipboard = "",
  },
})
```

Existing mappings are preserved with a warning. Repeating `setup()` removes
old mappings owned by Commentry before applying the new configuration.
Mappings have descriptions for keymap discovery tools such as which-key,
without requiring a dependency. Inbox-local keys are unchanged.

Use `<leader>ce` or `:Commentry edit` on a commented line to edit an unsent
comment's text. This works at the start or anywhere within its range, in normal
buffers and Diffview. Overlapping threads offer a picker. The original range
and capture stay unchanged. Sent comments use replies instead.

Comments on ordinary file buffers also show persistent cards and range marks.
They refresh after saving a comment and follow unchanged code through unsaved
edits. Use `gC` at a marked line to open its conversation. Resolved threads are
hidden unless selected in the inbox. Card appearance uses the same
`diffview.comment_cards` and `diffview.comment_ranges` settings on both surfaces.

### Diffview keymap configuration

The existing `keymaps` options remain optional buffer-local shortcuts.

| Action | Default | Mode |
| --- | --- | --- |
| `add_comment` | `mc` | Normal |
| `add_range_comment` | `mc` | Visual |
| `list_comments` | `ml` | Normal |

Each mapping can be changed or disabled with an empty string. Mappings attach
only to Diffview file buffers. `gC` opens an inbox conversation at the cursor.
Set `diffview.auto_attach = false` to disable automatic Diffview integration.
`comment_cards` controls card width, visible body lines and compact line labels.
Long comments show a continuation hint. `gC` opens their full conversation.
`comment_ranges` controls gutter rails and line highlighting. All decorations
use highlight links from your theme.

### Removed draft workflow

The branch-scoped `commentry.json` review store, draft picker, comment types,
reviewed-file tracking, export and Sidekick handoff have been removed. Existing
files under `~/.commentry` are left untouched and are no longer loaded. There
is no automatic import. All new comments go through the shared inbox backend.

## Commands

- `:Commentry inbox [all|unread|read|open|resolved|queued]` opens the inbox.
- `:Commentry comment` captures a line or command range, including Diffview.
- `:Commentry edit` edits a pending comment at the cursor.
- `:Commentry capture-text [register]` comments on copied text.
- `:Commentry new-thread` creates an unanchored project conversation.
- `:Commentry open [arguments]` opens Diffview.
- `:Commentry diagnostics` shows logging, inbox connection and Diffview state.
- `:Commentry help` opens the vimdoc.

## Development

- Install development tools: `mise install`, then `mise run setup_executor`
- Format Lua, Go and TypeScript: `mise run format`
- Lint Lua, Go and TypeScript: `mise run lint`
- Run Lua, Go, Executor SQLite and Pi receiver tests: `mise run test`
- Validate docs: `mise run docs`
- Full local checks: `mise run ci`
- Build the standalone Go CLI: `mise run build`
- Run its help: `mise run run -- --help`
- Install it to `~/.local/bin/commentry`: `mise run install-commentry`
- First release checklist: `docs/release-checklist.md`
- Canonical feature/design plans: `docs/plans/`
- Legacy Speckit archive (read-only history): `docs/archive/speckit/`

The Executor app owns the configured inbox database and inbox operations.
The Go CLI owns the JSON protocol adapter, browser login, capture and Rex delivery.
Go tooling is adapted from `~/personal/evaler`,
including Go 1.26.5, golangci-lint v2, its lint and formatter rules, hk 1.55,
and the Cobra/Viper skill in `.agents/skills/cobra-viper`.
The legacy export backend uses the pure Go `modernc.org/sqlite` driver.
The Executor app pins its `apps` framework version and uses synchronous SQL
transactions. Viper is not needed yet.
Lua tests build the client automatically. `mise run build_go` compiles it without
running checks.

Use `mise run format_go`, `mise run lint_go`, and `mise run test_go` for Go-only
work. `mise run lint:fix` applies Go lint fixes through hk. Install the optional
git hooks with `mise exec -- hk install`.

## Troubleshooting

- Backend missing or unavailable. Install `commentry` on PATH, or build with
  `mise run build` and add the checkout's `bin/` directory to PATH. Configure
  the Executor connection, then run `:checkhealth commentry`.
- A captured location moved or disappeared. The thread remains in the inbox.
  Its saved source is immutable. Agents can attach current code or a focused
  comparison without losing the discussion.
- A Diffview mapping is missing. Check `diffview.enabled`, `auto_attach` and
  the configured key. Empty or binary diff sides cannot accept file comments.
- Agent delivery fails. Use the inbox agent picker to attach an existing Rex
  agent pane. The inbox retains the saved conversation and delivery status.
