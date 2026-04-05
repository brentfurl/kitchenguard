import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/day_note.dart';
import '../../domain/models/day_schedule.dart';
import '../../domain/models/job.dart';
import '../../domain/models/manager_job_note.dart';
import '../../domain/models/videos.dart';
import '../web_providers.dart';
import '../widgets/web_notes_dialog.dart';

/// Desktop-optimized schedule management screen.
///
/// Jobs are grouped by date in a day-card layout (similar to mobile Jobs Home).
/// Managers can create, edit, delete, and reorder jobs, and manage day-level
/// notes and schedules.
class WebScheduleScreen extends ConsumerStatefulWidget {
  const WebScheduleScreen({super.key, required this.onJobTap});

  final ValueChanged<String> onJobTap;

  @override
  ConsumerState<WebScheduleScreen> createState() => _WebScheduleScreenState();
}

class _WebScheduleScreenState extends ConsumerState<WebScheduleScreen> {
  final Set<String> _activeFilters = {'today', 'upcoming'};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final jobsAsync = ref.watch(webJobListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Row(
            children: [
              Text('Schedule',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _showCreateJobDialog(context),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('New Job'),
              ),
            ],
          ),
        ),
        // Filter chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 8,
            children: [
              _filterChip('Today', 'today', cs),
              _filterChip('Upcoming', 'upcoming', cs),
              _filterChip('Past', 'past', cs),
              _filterChip('Unscheduled', 'unscheduled', cs),
              _filterChip('Published', 'published', cs),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Job list
        Expanded(
          child: jobsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error loading jobs: $e')),
            data: (jobs) => _buildJobList(context, jobs,
                ref.watch(webDaySchedulesProvider).valueOrNull ?? {}),
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, String value, ColorScheme cs) {
    final isSelected = _activeFilters.contains(value);
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) => setState(() {
        if (selected) {
          if (value == 'published') {
            _activeFilters
              ..clear()
              ..add('published');
          } else {
            _activeFilters.remove('published');
            _activeFilters.add(value);
          }
        } else {
          _activeFilters.remove(value);
        }
      }),
      selectedColor: cs.primaryContainer,
      checkmarkColor: cs.onPrimaryContainer,
    );
  }

  Widget _buildJobList(BuildContext context, List<Job> allJobs,
      Map<String, DaySchedule> daySchedules) {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // Group all jobs by scheduledDate vs unscheduled
    final allGrouped = <String, List<Job>>{};
    final allUnscheduled = <Job>[];
    for (final job in allJobs) {
      if (job.scheduledDate != null) {
        allGrouped.putIfAbsent(job.scheduledDate!, () => []).add(job);
      } else {
        allUnscheduled.add(job);
      }
    }

    final bool isPublishedView = _activeFilters.contains('published');

    // Actual today is deferred to "Upcoming" while earlier days still
    // have incomplete jobs (overnight shifts that cross midnight).
    final hasIncompletePastDays = allGrouped.keys.any((d) =>
        d.compareTo(todayStr) < 0 &&
        allGrouped[d] != null &&
        allGrouped[d]!.any((j) => !j.isComplete));

    bool isEffectiveToday(String date) {
      if (date.compareTo(todayStr) < 0) {
        final jobs = allGrouped[date];
        return jobs != null && jobs.any((j) => !j.isComplete);
      }
      if (date == todayStr) return !hasIncompletePastDays;
      return false;
    }

    final List<String> filteredDates;
    if (isPublishedView) {
      filteredDates = allGrouped.keys
          .where((date) {
            final schedule = daySchedules[date];
            if (schedule == null || !schedule.isPublished) return false;
            return isEffectiveToday(date) ||
                date.compareTo(todayStr) > 0 ||
                (date == todayStr && hasIncompletePastDays);
          })
          .toList()
        ..sort();
    } else {
      filteredDates = allGrouped.keys.where((date) {
        if (_activeFilters.contains('today') && isEffectiveToday(date)) {
          return true;
        }
        if (_activeFilters.contains('upcoming') &&
            (date.compareTo(todayStr) > 0 ||
             (date == todayStr && hasIncompletePastDays))) {
          return true;
        }
        if (_activeFilters.contains('past') &&
            date.compareTo(todayStr) < 0 &&
            !isEffectiveToday(date)) {
          return true;
        }
        return false;
      }).toList()
        ..sort();
    }

    // Sort jobs within each date by sortOrder
    for (final date in filteredDates) {
      allGrouped[date]!.sort(
          (a, b) => (a.sortOrder ?? 999).compareTo(b.sortOrder ?? 999));
    }

    final showUnscheduled = !isPublishedView &&
        _activeFilters.contains('unscheduled') && allUnscheduled.isNotEmpty;

    if (filteredDates.isEmpty && !showUnscheduled) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('No jobs found',
                style: TextStyle(color: Colors.grey[600], fontSize: 16)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        for (final date in filteredDates)
          _DayCard(
            date: date,
            todayStr: todayStr,
            jobs: allGrouped[date]!,
            onJobTap: widget.onJobTap,
            onDeleteJob: _deleteJob,
            onEditJob: (job) => _showEditJobDialog(context, job),
            dayNoteRepo: ref.read(webDayNoteRepositoryProvider),
            dayScheduleRepo: ref.read(webDayScheduleRepositoryProvider),
            dayNotesAsync: ref.watch(webDayNotesProvider),
            daySchedulesAsync: ref.watch(webDaySchedulesProvider),
            onTogglePublish: () => _togglePublish(date),
            isEffectiveToday: isEffectiveToday(date),
            onToggleJobCompletion: _toggleJobCompletion,
            onShiftNotesTap: () => _openShiftNotes(date),
            onJobNotesTap: (job) => _openJobNotes(context, job),
            onReorder: (oldIndex, newIndex) =>
                _reorderJobs(date, allGrouped[date]!, oldIndex, newIndex),
          ),
        if (showUnscheduled) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text('Unscheduled',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          ...allUnscheduled.map((job) => _JobTile(
                job: job,
                onTap: () => widget.onJobTap(job.jobId),
                onDelete: () => _deleteJob(job.jobId),
                onEdit: () => _showEditJobDialog(context, job),
                onToggleCompletion: () => _toggleJobCompletion(job),
                onJobNotesTap: () => _openJobNotes(context, job),
              )),
        ],
      ],
    );
  }

  Future<void> _reorderJobs(
      String date, List<Job> jobs, int oldIndex, int newIndex) async {
    final reordered = List<Job>.from(jobs);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);

    final repo = ref.read(webJobRepositoryProvider);
    for (var i = 0; i < reordered.length; i++) {
      await repo.saveJob(reordered[i].copyWith(sortOrder: i));
    }
  }

  Future<void> _toggleJobCompletion(Job job) async {
    final updated = job.copyWith(
      completedAt: job.isComplete
          ? null
          : DateTime.now().toUtc().toIso8601String(),
    );
    await ref.read(webJobRepositoryProvider).saveJob(updated);
  }

  Future<void> _deleteJob(String jobId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Job?'),
        content: const Text(
            'This will permanently remove the job from the schedule. '
            'Uploaded photos remain in Storage.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(webJobRepositoryProvider).deleteJob(jobId);
    }
  }

  Future<void> _togglePublish(String date) async {
    final repo = ref.read(webDayScheduleRepositoryProvider);
    final allSchedules = await repo.loadAll();
    final existing = allSchedules[date];
    final isCurrentlyPublished = existing != null && existing.isPublished;

    final DaySchedule updated;
    if (isCurrentlyPublished) {
      updated = DaySchedule(
        date: date,
        shopMeetupTime: existing.shopMeetupTime,
        firstRestaurantName: existing.firstRestaurantName,
        firstArrivalTime: existing.firstArrivalTime,
      );
    } else {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      updated = DaySchedule(
        date: date,
        shopMeetupTime: existing?.shopMeetupTime,
        firstRestaurantName: existing?.firstRestaurantName,
        firstArrivalTime: existing?.firstArrivalTime,
        published: true,
        publishedAt: DateTime.now().toUtc().toIso8601String(),
        publishedBy: uid,
      );
    }

    if (updated.isEmpty) {
      allSchedules.remove(date);
    } else {
      allSchedules[date] = updated;
    }
    await repo.saveAll(allSchedules);
    ref.invalidate(webDaySchedulesProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isCurrentlyPublished ? 'Day unpublished' : 'Day published'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _openShiftNotes(String date) async {
    final repo = ref.read(webDayNoteRepositoryProvider);
    final allNotes =
        ref.read(webDayNotesProvider).valueOrNull ??
            const <String, List<DayNote>>{};
    final notes = (allNotes[date] ?? []).where((n) => n.isActive).toList();

    await showDialog(
      context: context,
      builder: (_) => WebNotesDialog(
        title: 'Shift Notes',
        initialNotes:
            notes.map((n) => WebNoteItem(n.noteId, n.text)).toList(),
        onAdd: (text) async {
          final current = await repo.loadAll();
          final list = current[date] ?? [];
          list.add(DayNote(
            noteId: const Uuid().v4(),
            date: date,
            text: text,
            createdAt: DateTime.now().toUtc().toIso8601String(),
            status: 'active',
          ));
          current[date] = list;
          await repo.saveAll(current);
          ref.invalidate(webDayNotesProvider);
        },
        onEdit: (noteId, newText) async {
          final current = await repo.loadAll();
          final list = current[date] ?? [];
          final idx = list.indexWhere((n) => n.noteId == noteId);
          if (idx >= 0) {
            list[idx] = list[idx].copyWith(
              text: newText,
              updatedAt: DateTime.now().toUtc().toIso8601String(),
            );
            current[date] = list;
            await repo.saveAll(current);
            ref.invalidate(webDayNotesProvider);
          }
        },
        onDelete: (noteId) async {
          final current = await repo.loadAll();
          final list = current[date] ?? [];
          final idx = list.indexWhere((n) => n.noteId == noteId);
          if (idx >= 0) {
            list[idx] = list[idx].copyWith(status: 'deleted');
            current[date] = list;
            await repo.saveAll(current);
            ref.invalidate(webDayNotesProvider);
          }
        },
        onRefresh: () async {
          final current = await repo.loadAll();
          return (current[date] ?? [])
              .where((n) => n.isActive)
              .map((n) => WebNoteItem(n.noteId, n.text))
              .toList();
        },
      ),
    );
  }

  Future<void> _openJobNotes(BuildContext context, Job job) async {
    final webJobRepo = ref.read(webJobRepositoryProvider);
    final activeNotes = job.managerNotes.where((n) => n.isActive).toList();

    await showDialog(
      context: context,
      builder: (_) => WebNotesDialog(
        title: 'Job Notes \u2014 ${job.restaurantName}',
        initialNotes:
            activeNotes.map((n) => WebNoteItem(n.noteId, n.text)).toList(),
        onAdd: (text) async {
          final latest = await webJobRepo.loadJob(job.jobId);
          if (latest == null) return;
          final updated = [
            ...latest.managerNotes,
            ManagerJobNote(
              noteId: const Uuid().v4(),
              text: text,
              createdAt: DateTime.now().toUtc().toIso8601String(),
              status: 'active',
            ),
          ];
          await webJobRepo.saveJob(latest.copyWith(managerNotes: updated));
        },
        onEdit: (noteId, newText) async {
          final latest = await webJobRepo.loadJob(job.jobId);
          if (latest == null) return;
          final updated = latest.managerNotes.map((n) {
            if (n.noteId == noteId) {
              return n.copyWith(
                text: newText,
                updatedAt: DateTime.now().toUtc().toIso8601String(),
              );
            }
            return n;
          }).toList();
          await webJobRepo.saveJob(latest.copyWith(managerNotes: updated));
        },
        onDelete: (noteId) async {
          final latest = await webJobRepo.loadJob(job.jobId);
          if (latest == null) return;
          final updated = latest.managerNotes.map((n) {
            if (n.noteId == noteId) return n.copyWith(status: 'deleted');
            return n;
          }).toList();
          await webJobRepo.saveJob(latest.copyWith(managerNotes: updated));
        },
        onRefresh: () async {
          final latest = await webJobRepo.loadJob(job.jobId);
          if (latest == null) return [];
          return latest.managerNotes
              .where((n) => n.isActive)
              .map((n) => WebNoteItem(n.noteId, n.text))
              .toList();
        },
      ),
    );
  }

  void _showCreateJobDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _JobFormDialog(
        onSave: (job) async {
          await ref.read(webJobRepositoryProvider).saveJob(job);
        },
      ),
    );
  }

  void _showEditJobDialog(BuildContext context, Job job) {
    showDialog(
      context: context,
      builder: (ctx) => _JobFormDialog(
        existing: job,
        onSave: (updated) async {
          await ref.read(webJobRepositoryProvider).saveJob(updated);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Day card
// ---------------------------------------------------------------------------

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.date,
    required this.todayStr,
    required this.jobs,
    required this.onJobTap,
    required this.onDeleteJob,
    required this.onEditJob,
    required this.dayNoteRepo,
    required this.dayScheduleRepo,
    required this.dayNotesAsync,
    required this.daySchedulesAsync,
    this.onTogglePublish,
    this.isEffectiveToday = false,
    this.onToggleJobCompletion,
    this.onShiftNotesTap,
    this.onJobNotesTap,
    this.onReorder,
  });

  final String date;
  final String todayStr;
  final List<Job> jobs;
  final ValueChanged<String> onJobTap;
  final ValueChanged<String> onDeleteJob;
  final ValueChanged<Job> onEditJob;
  final dynamic dayNoteRepo;
  final dynamic dayScheduleRepo;
  final AsyncValue<Map<String, List<DayNote>>> dayNotesAsync;
  final AsyncValue<Map<String, DaySchedule>> daySchedulesAsync;
  final VoidCallback? onTogglePublish;
  final bool isEffectiveToday;
  final ValueChanged<Job>? onToggleJobCompletion;
  final VoidCallback? onShiftNotesTap;
  final ValueChanged<Job>? onJobNotesTap;
  final void Function(int oldIndex, int newIndex)? onReorder;

  bool get _isToday => isEffectiveToday;

  String get _formattedDate {
    try {
      final dt = DateTime.parse(date);
      const weekdays = [
        'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
      ];
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${weekdays[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}';
    } catch (_) {
      return date;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final notes = dayNotesAsync.valueOrNull?[date] ?? [];
    final activeNotes = notes.where((n) => n.isActive).toList();
    final schedule = daySchedulesAsync.valueOrNull?[date];
    final isDraft = schedule == null || !schedule.isPublished;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: _isToday ? cs.primary : cs.outlineVariant,
            width: _isToday ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date header
              Row(
                children: [
                  Text(_formattedDate,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  if (_isToday) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('TODAY',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onPrimary)),
                    ),
                  ],
                  if (isDraft) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.tertiaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('DRAFT',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onTertiaryContainer,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          )),
                    ),
                  ],
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.note_outlined, size: 16),
                    label: Text(activeNotes.isEmpty
                        ? 'Add note'
                        : '${activeNotes.length} notes'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onPressed: onShiftNotesTap,
                  ),
                  const Spacer(),
                  if (onTogglePublish != null)
                    TextButton.icon(
                      onPressed: onTogglePublish,
                      icon: Icon(
                        isDraft ? Icons.publish : Icons.unpublished_outlined,
                        size: 18,
                      ),
                      label: Text(isDraft ? 'Publish' : 'Unpublish'),
                    ),
                ],
              ),
              // Schedule info
              if (schedule != null && !schedule.isEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  children: [
                    if (schedule.shopMeetupTime != null)
                      _infoChip(Icons.store, 'Shop: ${schedule.shopMeetupTime}'),
                    if (schedule.firstArrivalTime != null)
                      _infoChip(
                          Icons.restaurant,
                          '${schedule.firstRestaurantName ?? 'First'}: '
                              '${schedule.firstArrivalTime}'),
                  ],
                ),
              ],
              const Divider(height: 20),
              // Job tiles (drag-reorderable)
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: jobs.length,
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex--;
                  onReorder?.call(oldIndex, newIndex);
                },
                proxyDecorator: (child, index, animation) {
                  return Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(8),
                    child: child,
                  );
                },
                itemBuilder: (context, i) {
                  final job = jobs[i];
                  return ReorderableDragStartListener(
                    key: ValueKey(job.jobId),
                    index: i,
                    child: _JobTile(
                      job: job,
                      onTap: () => onJobTap(job.jobId),
                      onDelete: () => onDeleteJob(job.jobId),
                      onEdit: () => onEditJob(job),
                      onToggleCompletion: onToggleJobCompletion != null
                          ? () => onToggleJobCompletion!(job)
                          : null,
                      onJobNotesTap: onJobNotesTap != null
                          ? () => onJobNotesTap!(job)
                          : null,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Job tile
// ---------------------------------------------------------------------------

class _JobTile extends StatelessWidget {
  const _JobTile({
    required this.job,
    required this.onTap,
    required this.onDelete,
    required this.onEdit,
    this.onToggleCompletion,
    this.onJobNotesTap,
  });

  final Job job;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback? onToggleCompletion;
  final VoidCallback? onJobNotesTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final hoodCount = job.units.where((u) => u.type == 'hood').length;
    final fanCount = job.units.where((u) => u.type == 'fan').length;
    final totalPhotos = job.units.fold<int>(
        0, (sum, u) => sum + u.visibleBeforeCount + u.visibleAfterCount);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          job.restaurantName,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (job.isComplete) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.check_circle,
                            size: 18, color: cs.primary),
                      ],
                    ],
                  ),
                  if (job.address != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      [job.address, job.city]
                          .where((s) => s != null && s.isNotEmpty)
                          .join(', '),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      if (hoodCount > 0)
                        _metaChip('$hoodCount hoods'),
                      if (fanCount > 0)
                        _metaChip('$fanCount fans'),
                      if (totalPhotos > 0)
                        _metaChip('$totalPhotos photos'),
                      if (job.accessType != null)
                        _metaChip(job.accessType!),
                      _jobNotesChip(),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit Job')),
                PopupMenuItem(
                  value: 'complete',
                  child: Text(job.isComplete ? 'Reopen Job' : 'Mark Complete'),
                ),
                const PopupMenuItem(value: 'delete', child: Text('Delete Job')),
              ],
              onSelected: (val) {
                if (val == 'edit') onEdit();
                if (val == 'complete') onToggleCompletion?.call();
                if (val == 'delete') onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaChip(String text) {
    return Text(text,
        style: TextStyle(fontSize: 12, color: Colors.grey[600]));
  }

  Widget _jobNotesChip() {
    final count = job.managerNotes.where((n) => n.isActive).length;
    return InkWell(
      onTap: onJobNotesTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.note_outlined, size: 14, color: Colors.grey[600]),
            const SizedBox(width: 3),
            Text(
              count > 0 ? '$count notes' : 'Add note',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create / Edit job dialog
// ---------------------------------------------------------------------------

class _JobFormDialog extends StatefulWidget {
  const _JobFormDialog({this.existing, required this.onSave});

  final Job? existing;
  final Future<void> Function(Job job) onSave;

  @override
  State<_JobFormDialog> createState() => _JobFormDialogState();
}

class _JobFormDialogState extends State<_JobFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _hoodCountCtrl;
  late final TextEditingController _fanCountCtrl;
  String? _scheduledDate;
  String? _accessType;
  late final TextEditingController _accessNotesCtrl;
  bool? _hasAlarm;
  late final TextEditingController _alarmCodeCtrl;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.restaurantName ?? '');
    _addressCtrl = TextEditingController(text: e?.address ?? '');
    _cityCtrl = TextEditingController(text: e?.city ?? '');
    _hoodCountCtrl =
        TextEditingController(text: e?.hoodCount?.toString() ?? '');
    _fanCountCtrl =
        TextEditingController(text: e?.fanCount?.toString() ?? '');
    _scheduledDate = e?.scheduledDate;
    _accessType = e?.accessType;
    _accessNotesCtrl = TextEditingController(text: e?.accessNotes ?? '');
    _hasAlarm = e?.hasAlarm;
    _alarmCodeCtrl = TextEditingController(text: e?.alarmCode ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _hoodCountCtrl.dispose();
    _fanCountCtrl.dispose();
    _accessNotesCtrl.dispose();
    _alarmCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final initial = _scheduledDate != null
        ? DateTime.tryParse(_scheduledDate!) ?? DateTime.now()
        : DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        _scheduledDate =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final now = DateTime.now().toUtc().toIso8601String();
    final hoodCount = int.tryParse(_hoodCountCtrl.text.trim());
    final fanCount = int.tryParse(_fanCountCtrl.text.trim());

    final existing = widget.existing;
    final job = Job(
      jobId: existing?.jobId ?? const Uuid().v4(),
      restaurantName: _nameCtrl.text.trim(),
      shiftStartDate: existing?.shiftStartDate ?? now,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      schemaVersion: existing?.schemaVersion ?? 3,
      scheduledDate: _scheduledDate,
      sortOrder: existing?.sortOrder,
      completedAt: existing?.completedAt,
      address:
          _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
      city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
      accessType: _accessType,
      accessNotes: _accessNotesCtrl.text.trim().isEmpty
          ? null
          : _accessNotesCtrl.text.trim(),
      hasAlarm: _hasAlarm,
      alarmCode: _alarmCodeCtrl.text.trim().isEmpty
          ? null
          : _alarmCodeCtrl.text.trim(),
      hoodCount: hoodCount,
      fanCount: fanCount,
      clientId: existing?.clientId,
      units: existing?.units ?? const [],
      notes: existing?.notes ?? const [],
      managerNotes: existing?.managerNotes ?? const [],
      preCleanLayoutPhotos: existing?.preCleanLayoutPhotos ?? const [],
      videos: existing?.videos ?? const Videos.empty(),
    );

    try {
      await widget.onSave(job);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit Job' : 'Create Job'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Restaurant Name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                // Date picker row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _scheduledDate != null
                            ? 'Date: $_scheduledDate'
                            : 'No date (unscheduled)',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: const Text('Pick Date'),
                    ),
                    if (_scheduledDate != null)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: 'Clear date',
                        onPressed: () =>
                            setState(() => _scheduledDate = null),
                      ),
                  ],
                ),
                const Divider(height: 24),
                // Address section
                Text('Address',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _addressCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Street Address'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _cityCtrl,
                  decoration: const InputDecoration(labelText: 'City'),
                ),
                const Divider(height: 24),
                // Access info
                Text('Access Info',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _accessType,
                  decoration:
                      const InputDecoration(labelText: 'Access Type'),
                  items: const [
                    DropdownMenuItem(
                        value: 'no-key', child: Text('No Key - Meet after closing')),
                    DropdownMenuItem(
                        value: 'get-key-from-shop',
                        child: Text('Get Key from Shop')),
                    DropdownMenuItem(
                        value: 'key-hidden', child: Text('Key Hidden')),
                    DropdownMenuItem(
                        value: 'lockbox', child: Text('Lockbox')),
                  ],
                  onChanged: (v) => setState(() => _accessType = v),
                ),
                if (_accessType == 'key-hidden' ||
                    _accessType == 'lockbox') ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _accessNotesCtrl,
                    decoration: InputDecoration(
                      labelText: _accessType == 'lockbox'
                          ? 'Lockbox Code'
                          : 'Key Location',
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Has Alarm'),
                    const SizedBox(width: 8),
                    Switch(
                      value: _hasAlarm ?? false,
                      onChanged: (v) => setState(() => _hasAlarm = v),
                    ),
                  ],
                ),
                if (_hasAlarm == true)
                  TextFormField(
                    controller: _alarmCodeCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Alarm Code'),
                  ),
                const Divider(height: 24),
                // Unit counts
                Text('Units',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _hoodCountCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Hood Count'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _fanCountCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Fan Count'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(_isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
