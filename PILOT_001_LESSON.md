# Pilot 001 — The shared lesson (published intervention)

**Origin:** The Agent Learning Commons project observed that a published button failed to resolve to the expected GitHub Issue form because JavaScript used `lesson.yml` while the actual filename was `discovery.yml`. Correcting the name and checking the user-facing flow fixed that specific problem. This is one observed correction, not a claim about AI performance.

## SHARED LESSON — START

**Cross-file link integrity: what a team learned from a real bug.** A website can look fine and contain all its files, yet a button or link still fails because the **reference** does not match the destination. In one GitHub Pages project, a JavaScript destination pointed to `lesson.yml` when the form actually existed as `discovery.yml`; the link was only repaired after both sides were compared and the real form opened.

When auditing links in a miniature website:

1. Treat the listed file inventory as authoritative. Compare **exact names, extensions, case, and folders**; never silently assume aliases.
2. Resolve a relative URL from the **file that contains the URL** (including CSS URLs), not from the repository root. For a project site hosted below `/project-name/`, a leading slash targets the host root rather than necessarily the project root.
3. For links built by JavaScript, check both the HTML `data-*` key and its lookup-table key; then verify that the generated destination matches the actual file or issue template.
4. For a GitHub Issue `?template=filename.yml` link, the template basename must match the file in `.github/ISSUE_TEMPLATE/` exactly.
5. Test reasoning against **negative cases** as well: don't report a bug when every reference resolves correctly. State the smallest correction and avoid unrelated edits.

This is a *checklist*, not a guarantee that every apparent mismatch is a real bug. Use the case's supplied assumptions.

## SHARED LESSON — END
