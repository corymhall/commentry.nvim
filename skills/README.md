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
