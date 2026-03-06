# commentry.nvim First Release Checklist

Use this checklist before cutting the first public tag.

## Release Surface

- [ ] `README.md` matches the shipped command/config/dependency surface.
- [ ] `doc/commentry.txt` matches the shipped command/config/dependency surface.
- [ ] `mise run docs` passes.
- [ ] `:checkhealth commentry` reports expected dependency and integration status.

## Validation

- [ ] `mise run format`
- [ ] `mise run lint`
- [ ] `mise run test`
- [ ] `mise run docs`
- [ ] `mise run health`
- [ ] `mise run ci`

## Packaging

- [ ] Choose and add the repository license file.
- [ ] Pick the first public SemVer tag.
- [ ] Draft GitHub release notes summarizing shipped commands, required dependencies, and optional integrations.
- [ ] Confirm the release notes call out v1 boundaries and known non-goals.

## Post-Tag Checks

- [ ] Verify the tag points at the intended commit on `main`.
- [ ] Verify the GitHub release references the same validation evidence used for the tag.
