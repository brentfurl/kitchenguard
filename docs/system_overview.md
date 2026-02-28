# KitchenGuard Photo Organizer – System Overview

## Purpose
Ensure structured, consistent photo documentation for kitchen cleaning jobs.
Eliminate manual sorting into Google Drive.

## Target Users
3–5 field techs.
Each tech uses their own phone.
iOS primary, Android supported.

## Core Architectural Principles
- Filesystem is the source of truth.
- App state must reconstruct from disk on startup.
- Photos must be written immediately to final location.
- Capture and Sync are separate systems.
- System must tolerate crashes without data loss.

## Folder Structure (On Device)

KitchenCleaningJobs/
  {RestaurantName}_{YYYY-MM-DD}/
    job.json
    Hoods/
      Hood_1/
        Before/
        After/
    Fans/
    Misc/

## Photo Naming Convention

{UnitName}_{Before|After}_{YYYY-MM-DD_HH-mm-ss}.jpg

Temp write → rename → update job.json.

## job.json Contains

- jobId
- restaurantName
- shiftStartDate
- createdAt
- units[]
  - unitId
  - type
  - name
  - photosBefore[]
  - photosAfter[]
  - photo status (local/uploaded/failed)

## v1 Scope

- Create job
- Create units
- Capture photos
- Persist to disk
- Reconstruct on startup
- No database
- No Google Drive yet

## Out of Scope (v1)

- Authentication
- Reporting
- GPS
- Renaming jobs or units
- Multi-device sync
