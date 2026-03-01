# Contributing

## Workflow

1. Create a focused branch.
2. Make scoped changes with tests/docs updates where relevant.
3. Run local validation:
   - `mise run format`
   - `mise run lint`
   - `mise run test`
   - `mise run health`
4. Open a PR using `.github/pull_request_template.md`.

## AI-Assisted Contributions

- Follow `AGENTS.md` as the source-of-truth contract.
- Keep edits limited to requested scope; do not touch unrelated files.
- Report exact validation commands run and pass/fail status.
- Escalate when behavior/API compatibility changes are required.

## Docs Note

`mise run docs` currently executes a stub path via `lua/commentry/docs.lua`. Treat docs automation as partial until that module is fully implemented.
