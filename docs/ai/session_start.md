# KitchenGuard — AI Session Start

Load this document at the start of every AI coding session. It provides project identity, development rules, risk assessment, agent workflow, and testing gates. Load additional context docs only as directed below.

---

# Project Identity

KitchenGuard is a Flutter-based field documentation app for technicians cleaning commercial kitchen hood systems. It captures structured photo/video documentation during cleaning jobs and exports organized media packages.

The app is **offline-first**: the local filesystem + `job.json` is the source of truth. Cloud sync (Firebase) layers on top but never replaces the local model.

The system has **two domains** with opposite data flows:
- **Scheduling** (cloud-first, manager-driven) — jobs, dates, day notes, arrival times
- **Documentation** (offline-first, technician-driven) — photos, videos, field notes

Both domains share the `Job` entity. The mobile app and a Flutter web management console both read/write shared Firestore data.

---

# Golden Rules

- The **local filesystem + job.json** is the source of truth for documentation
- Never reconstruct file paths from names — always use `relativePath`
- `fromJson` must **never crash** on missing fields — tolerate null, tolerate legacy values
- All domain entities use **typed Dart model classes** (not raw maps)
- All entities use **UUID v4** for IDs
- All data access in `JobsService` goes through **repository interfaces** (not raw stores)
- Schema changes follow: **read old + new → write new → migrate if needed → remove old later**
- Prefer incremental improvements — avoid large refactors unless requested

---

# Risk Classifier

Assess every change before starting work.

## Low Risk
- Text/copy changes
- Layout and styling tweaks
- Isolated UI polish
- Single-screen cosmetic changes
- Example: reverse sort order on web schedule job list

## Medium Risk
- Navigation changes
- Counter/state logic
- Controller or service edits
- Multi-file behavior changes
- Model changes without schema changes
- Example: add a new filter chip to the web schedule screen

## High Risk
- Schema changes (job.json fields, Firestore document shape)
- Sync logic or merge behavior
- Auth rules or permissions
- Export logic
- File path changes or storage conventions
- Deletion behavior
- Firebase rules (Firestore or Storage)
- Anything changing source of truth assumptions
- Example: add a new field to job.json for technician signatures

---

# Practical Agent Workflow in Cursor

Each "agent role" in this document maps to a **separate Cursor chat session**. Cursor uses your selected model for the main agent and can only downgrade subagents to a faster model -- it cannot upgrade. So the model you pick in Cursor's model selector is what all roles run on.

## Session handoff pattern

**Low/medium risk** -- the git diff is the context. No handoff doc needed.
- Session 1 (builder): work on a branch, commit when done
- Session 2 (reviewer): new chat, reference `@docs/ai/session_start.md` + paste or `@`-reference the git diff + paste the reviewer prompt from below

**High risk** -- create a lightweight issue doc so each session starts with full context.
- Session 1 (planner/builder): at the end, create `docs/ai/issues/<short-name>.md` using this template:

```
# Issue: <short description>

## Task
<what was requested>

## Risk Level
<low / medium / high>

## Branch
<branch name>

## Changes Made
<files changed, what each change does — 1-2 lines each>

## Open Questions / Risks
<anything the reviewer or safety agent should focus on>

## Review Status
- [ ] Builder complete
- [ ] Reviewer pass
- [ ] Safety pass
- [ ] Test pass
- [ ] Human approval
```

- Session 2 (reviewer): new chat, reference `@docs/ai/session_start.md` + `@docs/ai/issues/<short-name>.md` + the git diff + reviewer prompt
- Session 3 (safety): same pattern, reference the issue doc (now updated with reviewer findings) + safety prompt
- After merge, delete or archive the issue doc

The issue doc is the baton. Each session updates it before handing off.

---

# Agent Workflow by Risk Level

## Low Risk: Build → Review → Human Check

1. Implement the change with minimal surface area
2. Review the diff for correctness and edge cases
3. Human verifies and merges

## Medium Risk: Plan → Build → Review → Test → Human Check

1. Write a short implementation plan (goal, files, risks)
2. Implement the plan
3. Review diff against requested behavior
4. Add regression test coverage for the change
5. Human checks diff, runs app, merges

## High Risk: Plan → Critique → Build → Review → Safety → Test → Human Approval

1. Write implementation plan only (no code yet)
2. Attack the plan — find failure modes, rollback risks, data-integrity issues
3. Implement the revised plan
4. Review diff for correctness, edge cases, stale state
5. Safety review: destructive operations, validation gaps, sync risks, auth assumptions
6. Add regression and rollback-oriented test coverage
7. Human approval required — manual device testing before merge

---

# Teaching Layer: Git & Testing Guidance (Temporary)

> Remove this section once the human is comfortable with git workflow and testing decisions.

For every task, proactively include short guidance blocks at two points. Keep each block scannable — a few lines, not a wall of text. Always include the reasoning so the human learns the "why," not just the commands.

## Before Writing Code — Git Setup

1. **Branch or main?** State whether this task should use a branch or go directly to `main`. Reference the branching criteria in `docs/git/kitchen_guard_git_workflow.md` ("What Should Use a Branch?" list). Explain why in one sentence.
2. **Branch type and name.** If branching, suggest a name using project conventions: `feature/*`, `fix/*`, `ux/*`, `schema/*`, `migration/*`, `experiment/*`.
3. **Exact commands.** Show the git commands to run.

Example:

```
Git setup: This changes web console behavior (sort order), so it should use a branch.
Branch type "ux/" fits since it's a UI improvement with no schema change.

  git checkout main
  git pull
  git checkout -b ux/reverse-schedule-sort
```

## After Writing Code — Git & Testing Next Steps

### Git

1. **Commit.** Suggest a commit message using project style (`Fix:`, `Feature:`, `UX:`, `Refactor:`, `Perf:`, `Schema:`). Show the commands.
2. **Merge or keep working?** State whether to merge to `main` now or stay on the branch, with reasoning (e.g., "Single self-contained change, safe to merge" vs. "Part of a larger feature, stay on branch").
3. **Push to remote?** State whether to push and why (e.g., backup, collaboration, or not needed yet).

Example:

```
Git next steps: Change is complete and self-contained — safe to merge.

  git add .
  git commit -m "UX: reverse job date sort on web schedule screen"
  git checkout main
  git merge ux/reverse-schedule-sort
  git branch -d ux/reverse-schedule-sort
```

### Testing

1. **Testing level.** Recommend which level (1–4) from `docs/testing/kitchen_guard_testing_workflow.md` applies and why.
2. **Test mode.** State emulator vs phone vs web browser, referencing "Emulator = Speed, Phone = Truth."
3. **What to verify.** List the 1–3 specific things to check.
4. **Commands.** Show the exact command to run the app in the right mode.

Example:

```
Testing: Level 2 (screen-level behavior) — sort order is a single-screen behavior change.
Mode: Web browser — this is a web console change.
Verify: (1) latest dates appear at top with each filter, (2) job order within a day is unchanged.

  flutter run -d chrome
```

---

# Agent Role Prompts

## Builder
Implement this change with minimal surface area. Preserve existing architecture unless necessary. Do not refactor unrelated files. Keep existing storage and sync semantics intact. After coding, summarize changed files and possible regressions.

## Reviewer
Review this diff only. Do not rewrite the feature. Focus on: correctness bugs, edge cases, stale state, race conditions, navigation regressions, mismatch between requested behavior and actual behavior. Return: critical issues, likely issues, nice-to-fix issues, files needing human review.

## Safety Reviewer
Act as a paranoid security and data-integrity reviewer. Look for: destructive operations, unsafe trust in client state, missing validation, broken auth/sync assumptions, overbroad permissions, dangerous file handling, export/delete risks, rollback hazards. Rank findings by severity.

## Test Agent
Add the smallest high-value regression tests for this diff. Prioritize: the exact bug fixed, adjacent edge cases, state update behavior, sync/persistence invariants if touched. Avoid broad rewrites.

## Planner
Write a minimal implementation plan. List: goal, files likely to change, implementation steps, key risks, regressions to watch for, test plan. Do not write code yet.

## Critic
Attack this implementation plan. Look for: hidden risks, missing cases, rollback problems, emulator-vs-phone differences, data-integrity issues, unsafe assumptions.

---

# Human Testing Gates

## Emulator Sufficient
- UI polish, text, styling, layout
- Isolated screen behavior
- Quick iteration on logic changes

## Phone Test Required (bundle related changes, then test once)
- Navigation and back-flow changes
- Counter logic across screens
- Multi-screen behavior changes

## Phone Test Required (every time)
- Camera capture behavior
- File system operations
- Sync and upload behavior
- Export/share flows
- Permission-gated features
- Anything timing-sensitive or gesture-sensitive

## Full Flow Before Merge
- Finishing a feature
- Before committing major changes
- Any high-risk change

---

# Merge Gate Checklist

Before merging any non-trivial change:

- [ ] Requested behavior is clearly implemented
- [ ] Diff is understandable — no unexplained large refactors
- [ ] Reviewer findings are addressed
- [ ] Risky files got extra scrutiny
- [ ] Tests/lint pass (or known failures are understood)
- [ ] Manual smoke test completed for affected flow
- [ ] If data/sync/storage changed: rollback risk considered
- [ ] If schema changed: `fromJson` handles missing new fields on all platforms

---

# Context Loading Guide

Load additional docs based on what the task touches. Only load what you need.

| Task involves | Load |
|---|---|
| Project architecture, AI guidelines, model patterns | `docs/ai/project_overview.md` |
| job.json, models, IDs, media metadata, notes | `docs/ai/data_model.md` |
| Screens, unit cards, gallery, capture UX | `docs/ai/ui_structure.md` |
| Firebase Auth, Firestore, Storage, sync, merge | `docs/ai/firebase_architecture.md` |
| Web management console | `docs/ai/web_console.md` |
| Export (ZIP or PDF) | `docs/ai/export_and_pdf.md` |
| Schema or migration work | `docs/firebase/kitchen_guard_firebase_schema_change_playbook.md` |
| Git branching, commit style | `docs/git/kitchen_guard_git_workflow.md` |
| Testing workflow, dev mode | `docs/testing/kitchen_guard_testing_workflow.md` |
| Full review protocol, review lanes, prompts | `docs/ai/code_review_protocol.md` |
| Phase history, past bug fixes | `docs/ai/development_history.md` |

---

# KitchenGuard-Specific Danger Zones

Be extra cautious when a diff touches any of these:

- `job.json` structure or `Job` model fields
- Scan/reconciliation logic (`JobScanner`)
- Media path generation or `relativePath` handling
- Export contents (ZIP or PDF)
- Delete/soft-delete behavior
- Counters derived from persisted state
- Navigation after capture flows
- Firebase sync assumptions or merge logic (`JobMerger`)
- Local-vs-remote source of truth boundaries
- Firebase security rules (Firestore or Storage)
- Upload queue or background upload behavior

When these areas change, always use: plan → review → safety check → phone test.
