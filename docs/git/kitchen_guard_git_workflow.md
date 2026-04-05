# KitchenGuard Git Workflow Cheat Sheet

> Updated for the current KitchenGuard architecture: Firebase-backed sync, web console, scheduling features, and active users.

A simple, practical Git workflow for safe feature development while maintaining a stable app for real users.

---

# Core Principles

- `main` = stable, runnable, production-safe app
- Use branches for anything meaningful
- Merge `main` into your branch before merging back
- Test after merges
- Treat shared data model and sync changes as higher-risk than UI-only changes
- Prefer smaller, shorter-lived branches over long-running branches

---

# Branch Types

- `main` → stable integrated version
- `feature/*` → new functionality
- `fix/*` → bug fixes
- `ux/*` → UI/UX improvements
- `schema/*` → shared model / Firebase document shape / rules changes
- `migration/*` → larger data evolution work
- `experiment/*` → risky ideas (can be deleted)

Examples:

```
feature/rapid-capture-speed
feature/web-console-job-board
fix/counter-refresh
fix/mobile-sync-conflict
ux/unit-card-polish
schema/job-status-normalization
migration/schedule-assignment-model
experiment/camera-rewrite
```

---

# 1. Start a New Feature

```
git checkout main
git pull
git checkout -b feature/my-feature
```

Work and commit:

```
git add .
git commit -m "Feature: describe change"
```

---

# 2. Make a Bug Fix While Users Are Active

```
git checkout main
git pull
git checkout -b fix/my-fix
```

After fixing:

```
git add .
git commit -m "Fix: describe bug fix"

git checkout main
git merge fix/my-fix
git branch -d fix/my-fix
```

---

# 3. Sync Feature Branch with Main

If `main` has changed while you're working:

```
git checkout feature/my-feature
git merge main
```

If conflicts occur:

- Resolve in files
- Then:

```
git add .
git commit
```

Test the app after this.

---

# 4. Merge Feature Back to Main

When ready:

```
git checkout main
git pull
git merge feature/my-feature
```

Optional cleanup:

```
git branch -d feature/my-feature
```

---

# 5. Daily Workflow

Start session:

```
git checkout main
git pull
git checkout -b feature/your-task
```

End session:

```
git status
git add .
git commit -m "WIP: progress description"
```

---

# 6. Check Your State

```
git branch
git status
```

---

# 7. View Changes

```
git diff
git diff --cached
```

---

# 8. Undo Changes

Discard file changes:

```
git restore path/to/file
```

Discard all uncommitted changes:

```
git restore .
```

---

# 9. Undo Last Commit (Keep Changes)

```
git reset --soft HEAD~1
```

---

# 10. Edit Last Commit Message

```
git commit --amend -m "Better message"
```

---

# 11. Push Branch to GitHub

```
git push -u origin feature/my-feature
```

Then:

```
git push
```

For other branch types, same pattern:

```
git push -u origin schema/my-change
git push -u origin fix/my-fix
```

---

# Commit Message Style (Recommended)

```
Fix: counter refresh after delete
UX: simplify delete dialog
Feature: add notes export
Perf: improve camera latency
Refactor: isolate gallery refresh logic
```

---

# What Should Use a Branch?

Always branch for:

- Camera behavior
- Navigation/back flow
- Counters
- Delete logic
- Export logic
- Storage/persistence
- Notes/videos/layout changes
- Scheduling workflow changes
- Web console behavior changes
- Sync/database/Firebase changes
- Shared model changes
- Firestore rules / permissions changes
- Anything involving deletion, reassignment, or job lifecycle state

Direct to `main` only for:

- Minor text changes
- Small UI tweaks
- Non-risky edits
- Tiny style cleanups that do not affect behavior

---

# Example Real Workflow

## Feature Work

```bash
git checkout main
git pull
git checkout -b feature/web-console-job-board
```

## Production Bug Found Midway

```bash
git checkout main
git pull
git checkout -b fix/mobile-sync-conflict
```

Fix + merge:

```bash
git add .
git commit -m "Fix: prevent duplicate job creation during sync"

git checkout main
git merge fix/mobile-sync-conflict
git branch -d fix/mobile-sync-conflict
```

## Update Feature Branch

```bash
git checkout feature/web-console-job-board
git merge main
```

## Finish Feature

```bash
git checkout main
git merge feature/web-console-job-board
```

---

# Example Schema / Firebase Workflow

Use this for shared document model or sync-sensitive changes.

```bash
git checkout main
git pull
git checkout -b schema/job-status-normalization
```

Make changes in small commits:

```bash
git add .
git commit -m "Schema: add canonical job status values"
git commit -m "Mobile: map legacy job status values"
git commit -m "Web: update jobs board filters for normalized status"
```

Before merging back:

```bash
git checkout schema/job-status-normalization
git merge main
```

Then test:

- mobile reads old + new data correctly
- web console reads old + new data correctly
- sync still works
- scheduling filters still behave correctly
- no unexpected writes or duplicate docs

Then merge:

```bash
git checkout main
git merge schema/job-status-normalization
```

---

# Release Tags

Use tags for known-good milestones.

```bash
git tag v1.0-field-stable
git tag v1.1-firebase-sync-live
git tag v1.2-web-console-scheduling
git push origin --tags
```

This gives you named restore points for real product phases.

---

# Golden Rule

Before merging a feature branch into `main`:

```
git checkout feature/my-feature
git merge main
```

Then test.

---

# Minimal Survival Commands

```
git checkout -b feature/name
git add .
git commit -m "message"
git merge main

git checkout main
git merge feature/name
```

---

# Final Mental Model

- `main` = stable app users rely on
- branches = safe experimentation and controlled delivery
- schema / migration branches = protect shared data assumptions
- merging = controlled integration
- tags = named restore points

If you're unsure:

👉 "Would I be nervous if this broke the app, sync, or shared data?"

If yes → use a branch

---

This workflow is designed for fast iteration, real users, Firebase-backed sync, web console development, scheduling features, and safe progress toward larger multi-surface product changes.

