# Working Agreement

## Commits
- Use Conventional Commits: `<type>: <brief description>`.
- Allowed types: feat, fix, docs, chore, refactor, style, perf, build, ci.
- Keep the description short and in the imperative mood.
  - Examples: `feat: add zoxide installation`, `fix: correct arch detection on arm`,
    `docs: document curl install command`.
- Commit **and push** after every relevant change — do not batch unrelated work
  into one commit, and do not leave finished work unpushed.

## Documentation
- Keep `README.md` up to date with every change that affects usage, behavior,
  the toolset, or the install flow. An out-of-date README is a bug.

## Scope
- Keep the repository simple: one self-contained `install.sh`, plus docs.
- Do not introduce frameworks, build steps, or extra structure without being asked.
