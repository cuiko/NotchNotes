# Project Conventions

## Changelog

### When to update

Only update `CHANGELOG.md` when cutting a release — never during ongoing
development. Do not edit the changelog as features land mid-development; collect
them under the new version's heading at release time.

### Style

- Based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
- Version headings are `## vX.Y.Z` — keep the leading `v`, no surrounding
  brackets, and no dates.
- Within each version, group entries by change type using these headings only:
  `Added`, `Changed`, `Removed`, `Fixed`. Use the same grouping for every
  version (do not group by feature area).
- This is a fork: the top of the file links the upstream project
  (oil-oil/NotchNotes) and notes its `v0.1.x` releases as the baseline. Upstream
  versions are listed with a link to their release notes.
- Newest version first.
