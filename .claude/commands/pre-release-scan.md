Run the AI slop scan on shipped codebase before release.

Load the scan definition from `.claude/skills/shiki-process/ai-slop-scan.md` for:
- Full list of patterns to scan for
- The scan command template
- Exclusion rules
- Output format
- Remediation steps

If a `project-adapter.md` exists, read it for source directories and language type.

## Execution

1. Read `ai-slop-scan.md` from the shiki-process skill
2. Run the scan command adapted for the project's source directories
3. Report results: CLEAN (0 matches) or FAIL with file:line details
4. If FAIL: list each match and suggest remediation
