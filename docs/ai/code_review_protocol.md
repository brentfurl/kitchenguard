# KitchenGuard — AI Code Review Protocol

Safer AI-assisted development with structured review, fewer regressions, and clearer merge decisions.

---

# Core Principle

Use **different agents for different jobs**.

Do **not** use multiple agents all making uncontrolled edits to the same branch. Instead, use a pipeline:

1. **Plan** the change
2. **Implement** the change
3. **Review** the diff
4. **Test** the behavior
5. **Approve** manually before merge

---

# Review Lanes

Split review into three separate lanes for thorough coverage.

## Lane A — Product / UX / Correctness

Use when changing screen behavior, counters, navigation, capture flows, or visible behavior for technicians.

Focus:
- does it behave as requested?
- will a field technician understand it?
- do counters update immediately?
- does back navigation feel correct?
- does the change introduce extra taps or friction?
- does it behave correctly on phone, not just emulator?

**Prompt:**

```
Review this diff from a product and field-UX perspective.

Focus on:
- behavior mismatches
- broken navigation
- stale counters
- confusing flows
- added friction
- regressions that would frustrate a technician in the field

Return the most important issues first.
```

## Lane B — Architecture / State / Persistence

Use when changing controllers/services, models, storage logic, sync behavior, or startup reconciliation.

Focus:
- offline-first integrity
- controller/service separation
- state consistency
- race conditions
- fragile assumptions
- local-vs-remote source of truth problems

**Prompt:**

```
Review this diff for architectural and data-integrity risks.

Focus on:
- offline-first assumptions
- source-of-truth violations
- controller/service boundary leaks
- race conditions
- fragile state transitions
- persistence hazards
- sync inconsistency risks
```

## Lane C — Safety / Security / Destructive Operations

Use when touching Firebase rules, auth, exports, deletion, permissions, uploads/downloads, or file paths.

Focus:
- destructive operations
- secrets leakage
- unsafe trust in client data
- over-permissive rules
- accidental data exposure
- bad validation
- rollback difficulty

**Prompt:**

```
Review this diff like a hostile reviewer.

Look for:
- destructive behavior
- weak validation
- accidental data leakage
- overbroad Firebase access
- unsafe file operations
- broken assumptions around authentication or authorization
- failure modes that could lose or expose data
```

---

# Agent Role Definitions

## 1. Planner Agent

**Job:** clarify scope before code is written

Use for medium or large changes, risky changes, anything with multiple files or behavior implications.

**Prompt:**

```
Create a short implementation plan for this change.

Requirements:
- minimize surface area
- preserve existing architecture unless there is a clear reason not to
- identify risky files
- identify possible regressions
- note where tests should be added

Return:
1. goal
2. files likely to change
3. implementation steps
4. key risks
5. test plan
```

## 2. Builder Agent

**Job:** implement the change with minimal unnecessary edits

**Prompt:**

```
Implement this change with minimal surface area.

Constraints:
- preserve existing architecture unless necessary
- do not refactor unrelated code
- avoid renaming unless needed for correctness
- keep existing storage and sync semantics intact
- explain any risky assumption
- summarize changed files and possible regressions after coding
```

## 3. Reviewer Agent

**Job:** review the diff, not rewrite the feature

**Prompt:**

```
Review this diff only.

Do not rewrite the feature.
Do not suggest broad refactors unless a serious issue requires it.

Focus on:
- correctness bugs
- edge cases
- stale state
- race conditions
- navigation regressions
- mismatch between requested behavior and actual behavior
- cases where emulator behavior may differ from phone behavior

Return:
1. critical issues
2. likely issues
3. nice-to-fix issues
4. files needing human review
```

## 4. Safety / Data-Integrity Agent

**Job:** act like a paranoid reviewer

**Prompt:**

```
Act as a paranoid security and data-integrity reviewer.

Inspect this diff for:
- unsafe trust in client state
- accidental destructive operations
- broken sync assumptions
- missing validation
- overbroad permissions
- bad auth assumptions
- dangerous file handling
- export/delete risks
- rollback hazards
- anything that could corrupt local or remote state

Rank findings by severity.
```

## 5. Test Agent

**Job:** add the smallest high-value tests possible

**Prompt:**

```
Given this diff, add the smallest high-value regression tests.

Prioritize:
- the exact bug fixed
- nearby edge cases
- state update behavior
- navigation behavior
- sync/persistence invariants if touched

Avoid broad rewrites of the test suite.

Return:
1. tests added
2. what each test protects against
3. what still requires manual testing
```

## 6. Critic Agent

**Job:** attack an implementation plan before code is written

**Prompt:**

```
Attack this implementation plan.
Look for hidden risks, missing cases, rollback problems, emulator-vs-phone differences, data-integrity issues, and unsafe assumptions.
```

---

# Branch / Worktree Rules

**Rule 1:** Only one builder agent should actively edit a given implementation branch.

**Rule 2:** Reviewer and safety agents should comment on the diff, not directly rewrite the branch.

**Rule 3:** For parallel work, use separate branches, separate worktrees, or separate tightly scoped PRs.

**Rule 4:** Do not let two agents independently refactor overlapping files unless you are intentionally comparing approaches.

---

# Risk Classifications

## Low Risk
- text copy changes
- layout tweaks
- styling changes
- isolated UI polish

## Medium Risk
- navigation changes
- counter logic
- controller updates
- model changes without schema changes
- multi-screen behavior changes

## High Risk
- schema changes
- sync logic
- auth rules
- exports
- file path changes
- deletion behavior
- migration scripts
- anything changing source of truth

---

# Required Process by Risk Level

## Low Risk
- Builder
- Reviewer
- Human check

## Medium Risk
- Planner
- Builder
- Reviewer
- Test agent
- Human check

## High Risk
- Planner
- Critic
- Builder
- Reviewer
- Safety agent
- Test agent
- Human approval

---

# Merge Gate Checklist

Before merge, all of these should be true:

- [ ] Requested behavior is clearly implemented
- [ ] Diff is understandable
- [ ] No unexplained large refactors
- [ ] Reviewer findings are addressed
- [ ] Risky files got extra scrutiny
- [ ] Tests/lint pass or known failures are understood
- [ ] Manual smoke test completed for affected flow
- [ ] If data/sync/storage changed, rollback risk has been considered

---

# Manual Smoke Test Checklist

## UI / Flow
- Correct screen opens
- Buttons do what label implies
- Back behavior feels right
- No extra taps introduced unnecessarily
- Counters update immediately
- Empty states and edge states behave well

## Persistence
- Data survives app restart
- Local state matches UI state
- Deletes behave correctly
- Renamed items still behave correctly
- Exported content matches expectations

## Phone Reality Check
- Test on actual phone, not emulator only
- Verify timing-sensitive flows on device
- Verify camera and gallery flow on device
- Verify navigation stack on device
- Verify permissions on device

## Sync / Firebase
- Expected writes happen once
- No duplicate documents/records
- Conflict behavior is sensible
- Bad network conditions do not corrupt state
- Unauthorized actions fail safely

---

# KitchenGuard-Specific Guardrails

Always be extra cautious when a diff touches:

- job.json structure
- scan/reconciliation logic
- media path generation
- export contents
- delete/soft delete behavior
- counters derived from persisted state
- navigation after capture flows
- Firebase sync assumptions
- local-vs-remote source of truth

When those areas change, require:
- planner pass
- reviewer pass
- safety/data-integrity pass
- manual phone test

---

# What Not to Do

- Do not let multiple agents freely edit the same branch
- Do not accept AI-generated refactors without a reason
- Do not merge medium/high-risk changes without reviewing the diff
- Do not trust emulator-only validation for capture-heavy app flows
- Do not treat "it compiles" as "it is safe"
- Do not let test generation replace manual field-reality testing

---

# Practical Implementation in Cursor

## How agent roles map to Cursor sessions

Each "agent role" is a **separate Cursor chat session**, not a simultaneously running process. Cursor uses whatever model you've selected in the model picker. Subagents spawned within a session can only downgrade to a faster model, never upgrade. So your model choice in Cursor's UI applies to all roles.

## Session handoff: low/medium risk

The git diff is the context. No extra docs needed.

**Session 1 — Builder:**
- Reference `@docs/ai/session_start.md` (plus any relevant context doc from the loading guide)
- Describe the task
- Work on a feature branch, commit when done

**Session 2 — Reviewer:**
- New chat
- Reference `@docs/ai/session_start.md`
- Paste or `@`-reference the git diff
- Paste the Reviewer prompt (or Safety prompt if the change touches danger zones)

That's it for most changes. Two sessions.

## Session handoff: high risk

Create a lightweight issue doc so each session starts informed. The builder session generates it as its last step.

**Issue doc template** — save to `docs/ai/issues/<short-name>.md`:

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

**Session 1 — Planner/Builder:**
- Reference `@docs/ai/session_start.md` + relevant context docs
- Plan and implement
- Before ending: create the issue doc with changes summary and open risks
- Commit on branch

**Session 2 — Reviewer:**
- New chat
- Reference `@docs/ai/session_start.md` + `@docs/ai/issues/<short-name>.md` + git diff
- Paste the Reviewer prompt
- Update the issue doc with findings

**Session 3 — Safety:**
- New chat
- Reference `@docs/ai/session_start.md` + `@docs/ai/issues/<short-name>.md` + git diff
- Paste the Safety Reviewer prompt
- Update the issue doc with findings

**Session 4 — Test:**
- New chat (or same as safety)
- Reference the issue doc + git diff
- Paste the Test Agent prompt

After merge, delete or archive the issue doc.

## Workflow options by risk level

### Option A — Simple (daily use, low risk)

Two sessions total:
1. Builder session: implement + commit
2. Reviewer session: diff review
3. Run locally, merge if clean

### Option B — Safer (medium risk, state or sync changes)

Three sessions:
1. Builder session: plan first, then implement + commit + create issue doc
2. Reviewer session: diff review against issue doc
3. Test session: add regression coverage
4. Run local checks + manual phone test, merge

### Option C — High-Risk (schema/sync/auth/storage changes)

Four+ sessions:
1. Planner session: plan only, no code
2. Critic session: attack the plan (can be same session if you switch prompts)
3. Builder session: implement revised plan + commit + create issue doc
4. Reviewer session: diff review
5. Safety session: paranoid review of risky paths
6. Test session: regression + rollback coverage
7. Manual validation on real device
8. Merge only after explicit human review

---

# Bottom Line

Use multiple agents as:
- one builder
- one skeptic
- one tester/safety checker

Three agents with sharply different roles, run as separate Cursor chat sessions. The git diff (low/medium risk) or a lightweight issue doc (high risk) is the baton that carries context between sessions. That gives you speed from the builder, protection from the skeptic, and confidence from the tester — simple enough to actually use every time.
