# KitchenGuard Firebase-Safe Schema Change Playbook

A practical workflow for evolving shared data safely across:

- mobile app
- web console
- Firestore
- Firebase Storage metadata
- local `job.json`
- sync / merge logic

This playbook is designed for KitchenGuard's current architecture:

- local filesystem + `job.json` remain the source of truth for documentation
- Firestore powers scheduling and shared cloud state
- Firebase Storage mirrors media
- mobile and web both read/write shared models
- mixed old/new data must be expected during rollout

---

# Core Rule

Never make a schema change that assumes all data updates at once.

For some period of time, assume all of the following may exist simultaneously:

- old local JSON
- new local JSON
- old Firestore documents
- new Firestore documents
- older app builds still in use
- newer app builds writing new fields

Because of that, the safe pattern is:

**read old + new → write new → migrate if needed → remove old later**

---

# What Counts as a Schema Change?

Use this playbook for changes involving:

- `Job` fields
- `PhotoRecord` / `VideoRecord` fields
- note models
- scheduling data shape
- Firestore document fields
- sync metadata
- merge behavior assumptions
- document IDs or matching rules
- Firebase Storage path assumptions
- query-dependent fields used by web/mobile filtering

---

# Change Risk Levels

## Low Risk

- add nullable field
- add optional metadata
- add timestamp field
- add backward-compatible collection
- add UI that tolerates null / missing data

Examples:

- `priorityLevel: String?`
- `updatedAt: String?`
- `publishedBy: String?`

## Medium Risk

- add enum values
- add query-dependent field
- add fields used by sorting/filtering
- add fields used in merge logic
- change how one screen interprets existing data

Examples:

- new job status values
- priority-based scheduling sort
- new filter chips depending on stored fields

## High Risk

- rename fields
- remove fields
- change field meaning
- split one field into multiple fields
- change nested structure
- change ID semantics
- change merge matching logic
- change Storage path conventions
- change rules that affect both web and mobile assumptions

Examples:

- renaming `scheduledDate`
- changing unit matching strategy
- restructuring notes into a new collection model

High-risk changes should always use a dedicated `schema/*` or `migration/*` branch.

---

# Recommended Branch Types

Use these branch types for shared-data work:

```bash
schema/job-priority-level
schema/status-normalization
migration/manager-notes-model
migration/unit-matching-refactor
```

Rule:

**No shared-data change goes straight to `main`.**

---

# The 6-Step Workflow

## 1. Plan the Change

Before coding, write down:

- what is changing
- why it is needed
- which layers are affected
- whether it is additive or breaking
- whether migration is required

Use this mini template:

```md
Change:
Add job.priorityLevel

Why:
Need better scheduling prioritization in web + mobile

Affected layers:
- Job model
- fromJson / toJson
- Firestore job docs
- mobile Jobs Home
- web schedule filters
- merge logic

Risk:
Low if additive and nullable

Migration:
Not required initially
```

---

## 2. Make Readers Safe First

Readers must handle both old and new data before any new writes begin.

This means updating all relevant `fromJson` and parsing paths so they:

- tolerate missing fields
- tolerate null values
- tolerate legacy field values when possible
- avoid crashes or invalid assumptions
- keep UI behavior safe when the field is absent

Checklist:

- mobile model parsing safe
- web model parsing safe
- merge logic safe
- export logic safe
- filtering/sorting safe when field is null
- local file scan/reconcile safe

Recommended first commit example:

```bash
git commit -m "Schema: read priorityLevel safely from missing or legacy job data"
```

---

## 3. Add Writes Second

Once reads are safe everywhere, begin writing the new field.

Pattern:

- version A: reads old + new, writes old only
- version B: reads old + new, writes new
- version C: migrates/cleans up old data later

This prevents older records from breaking the app while the rollout is in progress.

Recommended commit example:

```bash
git commit -m "Schema: write priorityLevel on job save"
```

---

## 4. Update Product Behavior

After the new field is safely written, update the UI / product behavior that depends on it.

Examples:

- mobile displays new field
- web filters or sorts by new field
- dialogs allow editing the field
- analytics or reporting surfaces it

Recommended commits:

```bash
git commit -m "Mobile: show priorityLevel in jobs home"
git commit -m "Web: add priority filter to schedule board"
```

---

## 5. Migrate or Normalize Only If Needed

Not every schema change requires a full migration.

Use migration only when:

- old data behaves incorrectly without transformation
- normalized structure is required for queries
- multiple clients depend on a canonical shape
- mixed old/new values would create bugs or confusion

Migration styles that fit KitchenGuard well:

### Lazy migration on save
Old data is tolerated on read, then rewritten in the new shape the next time it is saved.

### Repair during scan / reconcile
Useful for documentation integrity and local storage fixes.

### Explicit backfill / admin migration
Useful when Firestore queries or schedule filters depend on consistent data across many records.

Migration commit examples:

```bash
git commit -m "Migration: normalize legacy job status values on load"
git commit -m "Migration: backfill priorityLevel for existing scheduled jobs"
```

---

## 6. Remove Legacy Support Last

Only remove old-field handling after:

- mobile and web are both stable on the new shape
- active users have updated sufficiently
- historical data has been migrated or safely tolerated
- production behavior has been observed long enough

Legacy cleanup is the last step, not the first.

---

# Model Rules

## `fromJson`

- never assume a field exists
- never crash on missing data
- tolerate null
- tolerate legacy values where practical
- prefer explicit parsing over fragile casts

## `toJson`

- write the canonical new shape
- omit nulls if that matches the existing project pattern
- avoid ambiguous mixed writes unless intentionally bridging formats

## IDs

- do not casually change UUID semantics
- preserve stable matching rules unless explicitly migrating them
- treat ID changes as high-risk schema work

## Defaults

- choose defaults that do not silently corrupt behavior
- missing / null is often safer than a fake placeholder value

---

# KitchenGuard-Specific Risk Areas

Be extra careful when a change affects any of these:

- `Job` scheduling fields
- note model shapes
- `PhotoRecord` / `VideoRecord` sync fields
- merge behavior in `JobMerger`
- unit matching / naming assumptions
- `relativePath` handling
- export behavior
- Firestore security rules
- Firebase Storage path assumptions
- web filters and query semantics

If any of these are touched, use a dedicated branch and test across both mobile and web.

---

# Rollout Template

Use this sequence for meaningful shared-data changes.

## A. Create the branch

```bash
git checkout main
git pull
git checkout -b schema/my-change
```

## B. Make readers safe

Examples:

- update models
- tolerate missing fields
- tolerate legacy values
- keep null-safe UI behavior

## C. Add writes

Examples:

- write new field from mobile dialog
- write new field from web form
- persist new field to Firestore / local JSON

## D. Update product behavior

Examples:

- sorting
- filtering
- badges
- dashboard displays

## E. Add migration only if needed

Examples:

- normalize values
- backfill old records
- rewrite legacy records during save

## F. Merge only after compatibility testing

```bash
git checkout schema/my-change
git merge main
# test again

git checkout main
git merge schema/my-change
```

---

# Compatibility Checklist Before Merge

Run through this before merging any schema or migration branch.

- Does `fromJson` handle missing new fields?
- Does mobile read old and new data correctly?
- Does web read old and new data correctly?
- Do Firestore writes still work?
- Do old local `job.json` files still load?
- Does merge logic behave correctly with mixed old/new records?
- Do filters and sorts behave correctly when the field is null?
- Does export still work if relevant?
- Are security rules still correct?
- Are Storage paths / `relativePath` assumptions unchanged?
- Is cleanup deferred until later?

If any answer is uncertain, do not merge yet.

---

# Example 1 — Safe Additive Change

## Add `priorityLevel` to `Job`

Safe rollout:

1. Add nullable field to model
2. Make mobile/web tolerate null
3. Start writing the field from forms
4. Add sorting/filtering behavior
5. Backfill later only if needed

Why this is safe:

- additive
- nullable
- old records still work
- no immediate migration required

---

# Example 2 — Risky Rename

## Rename `scheduledDate` to `serviceDate`

Safer rollout:

1. Readers support both `scheduledDate` and `serviceDate`
2. Writers begin writing `serviceDate`
3. Web/mobile update to prefer `serviceDate`
4. Backfill Firestore and local records if needed
5. Remove `scheduledDate` support later

Why this is risky:

- older clients may still read/write the old field
- filters and queries may break
- mixed data shape can persist for a while

---

# Example 3 — High-Risk Structural Change

## Change unit matching semantics

This affects:

- merge logic
- sync behavior
- move logic
- export ordering
- UI assumptions
- duplicate repair behavior

This should use:

- dedicated `migration/*` or `schema/*` branch
- multiple small commits
- extra device testing
- a release tag before merge if risk is substantial

---

# Suggested Commit Style

Use commit messages that make the rollout stage obvious.

```bash
Schema: read priorityLevel safely from legacy jobs
Schema: write priorityLevel in create/edit job flow
Web: add priority filter to schedule board
Mobile: display priority badge in jobs home
Migration: normalize legacy status values on save
Cleanup: remove legacy scheduledDate fallback
```

---

# Release Safety

For higher-risk schema work, consider tagging the last known-good state before merging.

```bash
git tag v1.2-pre-schema-change
git push origin --tags
```

This gives you a clean restore point if something behaves unexpectedly.

---

# Golden Rule

For shared-data changes, always follow this order:

**read old + new → write new → migrate if needed → remove old later**

That rule should protect KitchenGuard across:

- mobile
- web
- Firestore
- Firebase Storage metadata
- sync engine
- merge logic
- historical local job data

