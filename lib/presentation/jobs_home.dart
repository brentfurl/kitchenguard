import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/jobs_service.dart';
import '../domain/models/day_note.dart';
import '../domain/models/day_schedule.dart';
import '../domain/models/manager_job_note.dart';
import '../providers/app_role_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/role_helpers.dart';
import '../providers/day_notes_provider.dart';
import '../providers/day_schedule_provider.dart';
import '../providers/job_detail_provider.dart';
import '../providers/job_list_provider.dart';
import '../providers/service_providers.dart';
import '../providers/sync_provider.dart';
import '../providers/upload_progress_provider.dart';
import '../storage/job_scanner.dart';
import 'job_detail.dart';
import 'screens/manager_notes_screen.dart';
import 'widgets/day_card.dart';
import 'widgets/job_dialog.dart';
import 'widgets/job_sub_card.dart';
import 'widgets/shift_notes_sheet.dart';

class JobsHome extends ConsumerStatefulWidget {
  const JobsHome({super.key});

  @override
  ConsumerState<JobsHome> createState() => _JobsHomeState();
}

enum _JobFilter { today, upcoming, past, unscheduled }

class _JobsHomeState extends ConsumerState<JobsHome> {
  final Set<_JobFilter> _activeFilters = {_JobFilter.today, _JobFilter.upcoming};

  JobsService get _jobs => ref.read(jobsServiceProvider);

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(authServiceProvider).signOut();
      ref.read(appRoleProvider.notifier).clearRole();
    }
  }

  // ---------------------------------------------------------------------------
  // Job grouping (pure functions of provider data)
  // ---------------------------------------------------------------------------

  Map<String, List<JobScanResult>> _scheduledByDate(
    List<JobScanResult> results,
  ) {
    final map = <String, List<JobScanResult>>{};
    for (final r in results) {
      final date = r.job.scheduledDate;
      if (date != null) {
        map.putIfAbsent(date, () => []).add(r);
      }
    }
    for (final list in map.values) {
      list.sort((a, b) {
        final aSo = a.job.sortOrder;
        final bSo = b.job.sortOrder;
        if (aSo != null && bSo != null) return aSo.compareTo(bSo);
        if (aSo != null) return -1;
        if (bSo != null) return 1;
        return a.job.createdAt.compareTo(b.job.createdAt);
      });
    }
    return map;
  }

  List<JobScanResult> _unscheduledJobs(List<JobScanResult> results) {
    final list = results.where((r) => r.job.scheduledDate == null).toList();
    list.sort((a, b) => b.job.createdAt.compareTo(a.job.createdAt));
    return list;
  }

  /// Sorts day-card dates:
  /// 1. Days with at least one incomplete job (ascending by date)
  /// 2. Upcoming days with all jobs complete or no activity yet (ascending)
  /// 3. Fully completed days (descending — most recently completed first)
  List<String> _sortDayCards(Map<String, List<JobScanResult>> byDate) {
    final incomplete = <String>[];
    final complete = <String>[];

    for (final entry in byDate.entries) {
      final hasIncomplete = entry.value.any((r) => !r.job.isComplete);
      if (hasIncomplete) {
        incomplete.add(entry.key);
      } else {
        complete.add(entry.key);
      }
    }

    incomplete.sort();
    complete.sort((a, b) => b.compareTo(a));

    return [...incomplete, ...complete];
  }

  // ---------------------------------------------------------------------------
  // Create job
  // ---------------------------------------------------------------------------

  Future<void> _createJob() async {
    final result = await showJobDialog(
      context,
      title: 'Create Job',
      confirmLabel: 'Create',
    );
    if (result == null || !mounted) return;

    final restaurantName = result.name.trim();
    if (restaurantName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restaurant name required')),
      );
      return;
    }

    try {
      final scheduledDate = result.scheduledDate != null
          ? toYyyyMmDd(result.scheduledDate!)
          : null;
      final jobDir = await _jobs.createJob(
        restaurantName: restaurantName,
        shiftStartLocal: DateTime.now(),
        scheduledDate: scheduledDate,
        address: result.address,
        city: result.city,
        accessType: result.accessType,
        accessNotes: result.accessNotes,
        hasAlarm: result.hasAlarm,
        alarmCode: result.alarmCode,
        hoodCount: result.hoodCount,
        fanCount: result.fanCount,
      );

      for (final contact in result.contactNotes) {
        await _jobs.addManagerNote(jobDir: jobDir, text: contact);
      }

      ref.invalidate(jobListProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  // ---------------------------------------------------------------------------
  // Edit job
  // ---------------------------------------------------------------------------

  Future<void> _editJob(JobScanResult result) async {
    final job = result.job;
    final existingContacts = job.managerNotes
        .where((n) => n.isActive)
        .map((n) => n.text)
        .toList();

    final edit = await showJobDialog(
      context,
      title: 'Edit Job',
      confirmLabel: 'Save',
      initialName: job.restaurantName,
      initialDate: job.scheduledDate != null
          ? DateTime.tryParse(job.scheduledDate!)
          : null,
      initialAddress: job.address,
      initialCity: job.city,
      initialAccessType: job.accessType,
      initialAccessNotes: job.accessNotes,
      initialHasAlarm: job.hasAlarm,
      initialAlarmCode: job.alarmCode,
      initialHoodCount: job.hoodCount,
      initialFanCount: job.fanCount,
      existingContacts: existingContacts,
      isEdit: true,
    );
    if (edit == null || !mounted) return;

    final name = edit.name.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restaurant name required')),
      );
      return;
    }

    try {
      await _jobs.updateJobDetails(
        jobDir: result.jobDir,
        restaurantName: name,
        scheduledDate: edit.scheduledDate != null
            ? toYyyyMmDd(edit.scheduledDate!)
            : null,
        clearScheduledDate: edit.clearScheduledDate,
        address: edit.address,
        clearAddress: edit.clearAddress,
        city: edit.city,
        clearCity: edit.clearCity,
        accessType: edit.accessType,
        clearAccessType: edit.clearAccessType,
        accessNotes: edit.accessNotes,
        clearAccessNotes: edit.clearAccessNotes,
        hasAlarm: edit.hasAlarm,
        clearHasAlarm: edit.clearHasAlarm,
        alarmCode: edit.alarmCode,
        clearAlarmCode: edit.clearAlarmCode,
        hoodCount: edit.hoodCount,
        clearHoodCount: edit.clearHoodCount,
        fanCount: edit.fanCount,
        clearFanCount: edit.clearFanCount,
      );

      final activeNotes = job.managerNotes.where((n) => n.isActive).toList();
      final newContactTexts = edit.contactNotes;

      for (var i = 0; i < activeNotes.length; i++) {
        if (i >= newContactTexts.length ||
            activeNotes[i].text != newContactTexts[i]) {
          if (i >= newContactTexts.length) {
            await _jobs.softDeleteManagerNote(
                jobDir: result.jobDir, noteId: activeNotes[i].noteId);
          }
        }
      }

      for (var i = 0; i < activeNotes.length && i < newContactTexts.length; i++) {
        if (activeNotes[i].text != newContactTexts[i]) {
          await _jobs.editManagerNote(
            jobDir: result.jobDir,
            noteId: activeNotes[i].noteId,
            newText: newContactTexts[i],
          );
        }
      }

      for (var i = activeNotes.length; i < newContactTexts.length; i++) {
        await _jobs.addManagerNote(jobDir: result.jobDir, text: newContactTexts[i]);
      }

      ref.invalidate(jobListProvider);
      ref.invalidate(jobDetailProvider(result.jobDir.path));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  // ---------------------------------------------------------------------------
  // Job navigation
  // ---------------------------------------------------------------------------

  Future<void> _openJobDetail(JobScanResult result) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => JobDetail(jobs: _jobs, job: result),
      ),
    );
    if (!mounted) return;
    ref.invalidate(jobListProvider);
    ref.invalidate(dayNotesProvider);
  }

  Future<void> _openManagerNotesScreen(JobScanResult result) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ManagerNotesScreen(
          loadNotes: () async {
            final job = await _jobs.jobRepository.loadJob(result.jobDir);
            final notes = job?.managerNotes
                    .where((n) => n.isActive)
                    .toList() ??
                <ManagerJobNote>[];
            notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return notes;
          },
          addNote: (text) =>
              _jobs.addManagerNote(jobDir: result.jobDir, text: text),
          editNote: (noteId, newText) => _jobs.editManagerNote(
            jobDir: result.jobDir,
            noteId: noteId,
            newText: newText,
          ),
          softDeleteNote: (id) => _jobs.softDeleteManagerNote(
            jobDir: result.jobDir,
            noteId: id,
          ),
          onMutated: () async {
            ref.invalidate(jobListProvider);
            ref.invalidate(jobDetailProvider(result.jobDir.path));
          },
        ),
      ),
    );
    if (mounted) {
      ref.invalidate(jobListProvider);
      ref.invalidate(jobDetailProvider(result.jobDir.path));
    }
  }

  // ---------------------------------------------------------------------------
  // Shift note operations — delegates to shift_notes_sheet.dart
  // ---------------------------------------------------------------------------

  Future<void> _addShiftNote(String date) async {
    final text = await showShiftNoteDialog(context);
    if (text == null || text.isEmpty || !mounted) return;
    try {
      await _jobs.addDayNote(date, text);
      ref.invalidate(dayNotesProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _editShiftNote(String date, String noteId, String currentText) async {
    final newText = await showShiftNoteDialog(context, initialText: currentText);
    if (newText == null || newText.isEmpty || newText == currentText || !mounted) return;
    try {
      await _jobs.editDayNote(date, noteId, newText);
      ref.invalidate(dayNotesProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _deleteShiftNote(String date, String noteId, String noteText) async {
    final confirmed = await confirmDeleteShiftNote(context, noteText);
    if (!confirmed || !mounted) return;
    try {
      await _jobs.softDeleteDayNote(date, noteId);
      ref.invalidate(dayNotesProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  // ---------------------------------------------------------------------------
  // Reordering
  // ---------------------------------------------------------------------------

  Future<void> _reorderJobs(
    String date,
    List<JobScanResult> jobs,
    int fromIndex,
    int toIndex,
  ) async {
    final reordered = List<JobScanResult>.from(jobs);
    final item = reordered.removeAt(fromIndex);
    reordered.insert(toIndex, item);

    try {
      for (var i = 0; i < reordered.length; i++) {
        await _jobs.setSortOrder(reordered[i].jobDir, i);
      }
      ref.invalidate(jobListProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  // ---------------------------------------------------------------------------
  // Job deletion
  // ---------------------------------------------------------------------------

  Future<void> _confirmDeleteJob(JobScanResult job) async {
    final name = job.job.restaurantName.isNotEmpty
        ? job.job.restaurantName
        : 'this job';
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Job?'),
          content: Text(
            'Delete "$name" and all its local files from this device?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true) return;

    try {
      await _jobs.deleteJob(jobDir: job.jobDir);
      ref.invalidate(jobListProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final jobsAsync = ref.watch(jobListProvider);
    final notesAsync = ref.watch(dayNotesProvider);
    final schedulesAsync = ref.watch(dayScheduleProvider);
    final currentRole = ref.watch(appRoleProvider);
    final syncState = ref.watch(syncProvider);

    Widget body;

    if (jobsAsync is AsyncLoading || notesAsync is AsyncLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (jobsAsync is AsyncError) {
      body = Center(child: Text('Error: ${jobsAsync.error}'));
    } else {
      final results = jobsAsync.valueOrNull ?? const [];
      final activeShiftNotes =
          notesAsync.valueOrNull ?? const <String, List<DayNote>>{};
      final daySchedules =
          schedulesAsync.valueOrNull ?? const <String, DaySchedule>{};

      final stillLoadingFromCloud =
          results.isEmpty && syncState.lastPullTime == null;

      if (stillLoadingFromCloud) {
        body = const Center(child: CircularProgressIndicator());
      } else if (results.isEmpty) {
        body = const Center(child: Text('No jobs found.'));
      } else {
        final scheduledByDate = _scheduledByDate(results);
        final sortedDates = _sortDayCards(scheduledByDate);
        final unscheduled = _unscheduledJobs(results);
        final todayStr = toYyyyMmDd(DateTime.now());

        var filteredDates = sortedDates.where((date) {
          if (_activeFilters.contains(_JobFilter.today) && date == todayStr) {
            return true;
          }
          if (_activeFilters.contains(_JobFilter.upcoming) &&
              date.compareTo(todayStr) > 0) {
            return true;
          }
          if (_activeFilters.contains(_JobFilter.past) &&
              date.compareTo(todayStr) < 0) {
            return true;
          }
          return false;
        }).toList();

        if (currentRole.isTechnician) {
          filteredDates = filteredDates.where((date) {
            final schedule = daySchedules[date];
            return schedule != null && schedule.isPublished;
          }).toList();
        }

        final showUnscheduled =
            _activeFilters.contains(_JobFilter.unscheduled) &&
                unscheduled.isNotEmpty;

        body = Column(
          children: [
            _buildFilterRow(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await ref.read(syncProvider.notifier).pullNow();
                  ref.read(uploadProgressProvider.notifier).triggerUpload();
                },
                child: ListView(
                  padding: const EdgeInsets.only(top: 8, bottom: 80),
                  children: [
                    for (final date in filteredDates)
                      DayCard(
                        date: date,
                        jobs: scheduledByDate[date]!,
                        shiftNotes: activeShiftNotes[date] ?? const [],
                        daySchedule: daySchedules[date],
                        isManager: currentRole.isManager,
                        onTogglePublish: currentRole.isManager
                            ? () => _togglePublish(date, daySchedules[date])
                            : null,
                        onReorder: (oldIndex, newIndex) =>
                            _reorderJobs(date, scheduledByDate[date]!, oldIndex, newIndex),
                        onArrivalTimesTap: () => _handleArrivalTimesTap(
                          date,
                          daySchedules[date],
                          scheduledByDate[date]!.isNotEmpty ? scheduledByDate[date]!.first : null,
                        ),
                        onShiftNotesTap: () => _openShiftNotesScreen(
                          date,
                          activeShiftNotes[date] ?? const [],
                        ),
                        onAddShiftNote: () => _addShiftNote(date),
                        jobCardBuilder: (context, i) {
                          final dateJobs = scheduledByDate[date]!;
                          final r = dateJobs[i];
                          return JobSubCard(
                            key: ValueKey(r.job.jobId),
                            result: r,
                            onTap: () => _openJobDetail(r),
                            onEdit: () => _editJob(r),
                            onDelete: () => _confirmDeleteJob(r),
                            onToggleCompletion: () => _toggleJobCompletion(r),
                            onManagerNotes: () => _openManagerNotesScreen(r),
                          );
                        },
                      ),
                    if (showUnscheduled)
                      UnscheduledSection(
                        jobs: unscheduled,
                        onJobTap: _openJobDetail,
                        onJobEdit: _editJob,
                        onJobDelete: _confirmDeleteJob,
                        onJobToggleCompletion: _toggleJobCompletion,
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      }
    }

    final isLoading = jobsAsync is AsyncLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('KitchenGuard Jobs'),
        actions: [
          _SyncIndicator(
            syncState: syncState,
            onTap: () {
              ref.read(syncProvider.notifier).pullNow();
              ref.read(uploadProgressProvider.notifier).triggerUpload();
            },
          ),
          if (currentRole != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Chip(
                label: Text(currentRole.label),
                labelStyle: Theme.of(context).textTheme.labelSmall,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                side: BorderSide.none,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: _signOut,
          ),
        ],
      ),
      body: Column(
        children: [
          if (!syncState.isOnline)
            MaterialBanner(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: const Icon(Icons.cloud_off, size: 20),
              content: const Text('You are offline. Changes will sync when reconnected.'),
              actions: const [SizedBox.shrink()],
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              forceActionsBelow: true,
            ),
          Expanded(child: body),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: isLoading ? null : _createJob,
        icon: const Icon(Icons.add),
        label: const Text('Create Job'),
      ),
    );
  }

  Widget _buildFilterRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          for (final filter in _JobFilter.values) ...[
            if (filter != _JobFilter.values.first) const SizedBox(width: 6),
            FilterChip(
              label: Text(_filterLabel(filter)),
              selected: _activeFilters.contains(filter),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _activeFilters.add(filter);
                  } else {
                    _activeFilters.remove(filter);
                  }
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  static String _filterLabel(_JobFilter filter) {
    switch (filter) {
      case _JobFilter.today:
        return 'Today';
      case _JobFilter.upcoming:
        return 'Upcoming';
      case _JobFilter.past:
        return 'Past';
      case _JobFilter.unscheduled:
        return 'Unscheduled';
    }
  }

  Future<void> _handleArrivalTimesTap(
    String date,
    DaySchedule? existing,
    JobScanResult? firstJob,
  ) async {
    final result = await showArrivalTimeDialog(
      context,
      existing: existing,
      firstJobRestaurantName: firstJob?.job.restaurantName,
    );
    if (result == null || !mounted) return;

    try {
      if (result.clear) {
        await _jobs.setDaySchedule(
          date: date,
          clearShopMeetupTime: true,
          clearFirstRestaurantName: true,
          clearFirstArrivalTime: true,
        );
      } else {
        final arrival = result.arrivalTime;
        final shop = result.shopMeetupTime;
        final name = result.restaurantName;
        await _jobs.setDaySchedule(
          date: date,
          firstArrivalTime: arrival != null && arrival.isNotEmpty ? arrival : null,
          clearFirstArrivalTime: arrival != null && arrival.isEmpty,
          shopMeetupTime: shop != null && shop.isNotEmpty ? shop : null,
          clearShopMeetupTime: shop != null && shop.isEmpty,
          firstRestaurantName: name != null && name.isNotEmpty ? name : null,
          clearFirstRestaurantName: name != null && name.isEmpty,
        );
      }
      ref.invalidate(dayScheduleProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _openShiftNotesScreen(String date, List<DayNote> notes) {
    openShiftNotesSheet(
      context,
      notes: notes,
      onAdd: () => _addShiftNote(date),
      onEdit: (noteId, currentText) => _editShiftNote(date, noteId, currentText),
      onDelete: (noteId, noteText) => _deleteShiftNote(date, noteId, noteText),
    );
  }

  Future<void> _togglePublish(String date, DaySchedule? schedule) async {
    try {
      if (schedule != null && schedule.isPublished) {
        await _jobs.unpublishDay(date);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Day unpublished'), duration: Duration(seconds: 2)),
          );
        }
      } else {
        final uid = ref.read(authServiceProvider).currentUser?.uid ?? '';
        await _jobs.publishDay(date, uid);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Day published'), duration: Duration(seconds: 2)),
          );
        }
      }
      ref.invalidate(dayScheduleProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _toggleJobCompletion(JobScanResult result) async {
    try {
      if (result.job.isComplete) {
        await _jobs.reopenJob(result.jobDir);
      } else {
        await _jobs.markJobComplete(result.jobDir);
      }
      ref.invalidate(jobListProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

/// Combined sync status indicator for the AppBar.
///
/// Shows activity (pulling/uploading), pending upload count, or a
/// fully-synced check. Tapping triggers a manual sync attempt.
class _SyncIndicator extends StatelessWidget {
  const _SyncIndicator({
    required this.syncState,
    this.onTap,
  });

  final SyncState syncState;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (!syncState.isOnline) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Icon(Icons.cloud_off, size: 20),
      );
    }

    if (syncState.hasActivity) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    if (syncState.uploadPending > 0) {
      return IconButton(
        icon: Badge(
          label: Text('${syncState.uploadPending}'),
          child: const Icon(Icons.cloud_upload_outlined),
        ),
        tooltip:
            '${syncState.uploadPending} pending upload${syncState.uploadPending == 1 ? '' : 's'}',
        onPressed: onTap,
      );
    }

    if (syncState.isSynced) {
      return IconButton(
        icon: const Icon(Icons.cloud_done_outlined),
        tooltip: _lastSyncLabel(),
        onPressed: onTap,
      );
    }

    return IconButton(
      icon: const Icon(Icons.sync),
      tooltip: 'Sync now',
      onPressed: onTap,
    );
  }

  String _lastSyncLabel() {
    final t = syncState.lastPullTime;
    if (t == null) return 'Synced';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'Synced just now';
    if (diff.inMinutes < 60) return 'Synced ${diff.inMinutes}m ago';
    return 'Synced ${diff.inHours}h ago';
  }
}
