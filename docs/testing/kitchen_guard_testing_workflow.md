# KitchenGuard — Testing Workflow

This document defines a simple, repeatable testing system for development. The goal is to reduce friction, avoid over-testing, and ensure real-world reliability for a field-use app.

---

# Core Philosophy

**Emulator = Speed**  
**Phone = Truth**

- Use emulator for fast iteration
- Use phone for reality validation
- Test flows, not just individual actions

---

# Testing Levels

## Level 1 — UI Tweaks (Emulator Only)

Examples:
- Padding / spacing
- Colors
- Text labels
- Icon placement
- Minor layout adjustments

**Rule:**
Do NOT test these on phone individually.

---

## Level 2 — Screen-Level Behavior

Examples:
- Counter updates
- Button wiring
- Gallery refresh
- Navigation within a single screen
- Delete behavior

**Process:**
1. Build and refine on emulator
2. After multiple related changes → test once on phone

---

## Level 3 — Device-Sensitive Features (Phone Required)

Examples:
- Camera capture speed
- Image saving
- File system behavior
- Navigation after camera
- Gesture feel
- Share/export

**Rule:**
Always test on phone when these change.

---

## Level 4 — Full Flow / Session Testing

Examples:
- Create job
- Add units
- Take multiple before/after photos
- Add notes
- Take pre-clean layout photos
- Check counters
- Export job

**Rule:**
Run 1–2 full flows per session (not constantly).

---

# Development Loop

## Standard Loop

1. Work in emulator
2. Complete a meaningful chunk
3. Switch to phone
4. Run one full flow
5. Fix issues
6. Commit

---

## What Counts as a “Meaningful Chunk”

- Finished gallery behavior change
- Completed navigation fix
- Updated capture flow
- Implemented counter updates
- Modified export behavior

Avoid testing on phone for every small change.

---

# Dev Mode (Recommended)

Dev mode reduces repetitive setup during testing.

## Minimum Dev Mode Features

### 1. Create Test Job
- Restaurant: "Test Kitchen"
- Date: today
- Pre-seeded units:
  - Hood 1
  - Hood 2
  - Fan 1
  - Misc 1

### 2. Open Most Recent Job
Quick access to last job without navigating menus.

### 3. Add Sample Units
Quickly populate job for testing.

### 4. Reset Test Job
- Clear media
- Delete job
- Recreate fresh state

---

## Optional Enhancements

- Jump to specific screens (gallery, tools, notes)
- Insert dummy images or notes
- Debug overlay showing:
  - unit counts
  - photo counts
  - notes count
  - video counts

---

## Dev Mode Rules

- Must not affect production behavior
- Must not change storage structure
- Should be enabled only in debug builds

---

# Testing Checklist (Repeatable)

Use this for phone testing.

## 1. Capture Flow
- Can I enter camera quickly?
- Can I take multiple photos rapidly?
- Does it feel fast enough?

## 2. State Updates
- Do counters update immediately?
- Do galleries reflect changes instantly?

## 3. Navigation
- Does back return to the correct screen?
- Any unexpected jumps?

## 4. Persistence
- Close app → reopen
- Is all data intact?

## 5. Export / Share
- Export completes
- Files are correct
- Excluded items (e.g. pre-clean layout) are not included

---

# Practical Rules

## Use Emulator When:
- Adjusting UI
- Refactoring code
- Doing quick iterations

## Use Phone When:
- Working on camera
- Working on storage
- Testing performance
- Validating user feel

## Run Full Flow When:
- Finishing a feature
- Before committing major changes
- Before field testing

---

# Common Pitfalls

Avoid these:

- Testing every small change on phone
- Waiting too long to test device-specific features
- Making many unrelated changes before testing
- Relying on "it seems fine" instead of structured checks

---

# Recommended Workflow Summary

1. Default to emulator
2. Bundle related changes
3. Test on phone after meaningful chunk
4. Use dev mode to reduce setup time
5. Run one full realistic flow before commit

---

# Goal

Minimize friction while maximizing confidence.

Testing should feel:
- Fast during development
- Realistic during validation
- Repeatable and predictable

---

**End of Document**

