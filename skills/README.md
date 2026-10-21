# Agent skills

`commentry` routes coding agents into the Commentry inbox through Executor.
It covers delivered requests, ongoing inbox discussion and focused code
comparisons. It does not activate for ordinary code comments or plugin work.
The Executor app's packaged skill owns current protocol and recovery details.

Install it in a shared agent skill directory:

```sh
ln -s /absolute/path/to/commentry.nvim/skills/commentry ~/.agents/skills/commentry
```

Example requests include "Read the Commentry inbox for this project" and
"Leave a Commentry note explaining this change." Delivered thread payloads
also select the skill. Loading the skill does not grant tool permissions or
connect an Executor account.

To exercise a broad comparison request without supplying the agent with topics,
seed an isolated trial with:

```sh
mise run agent_trials -- seed-review tmp/my-review-trial
```

Give a fresh author agent the generated `request.txt`, the three raw trees under
`source`, and the Commentry skills. Route its calls through
`mise run agent_trials -- call tmp/my-review-trial`, never the live inbox. Have an
independent reader compare saved topics and evidence against the raw changes.
Check coverage, independently answerable topics, and exclusion of inherited
changes. Judge the grouping rather than requiring a fixed item count or one
item per file. The fixture contains intentional differences and an inherited
parent change so a bug-only review or a combined report is insufficient.
