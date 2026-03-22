import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../application/jobs_service.dart';
import '../application/startup_service.dart';
import '../domain/models/day_note.dart';
import '../domain/models/manager_job_note.dart';
import '../storage/job_scanner.dart';
import 'job_detail.dart';
import 'screens/manager_notes_screen.dart';

class JobsHome extends StatefulWidget {
  const JobsHome({super.key, required this.startup, required this.jobs});

  final StartupService startup;
  final JobsService jobs;

  @override
  State<JobsHome> createState() => _JobsHomeState();
}

class _JobsHomeState extends State<JobsHome> {
  bool _isLoading = true;
  List<JobScanResult> _results = const [];
  Map<String, List<DayNote>> _activeShiftNotes = const {};
  final Set<String> _expandedShiftNotes = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final loadedJobs = await widget.startup.loadJobs();
      final allNotes = await widget.jobs.loadAllDayNotes();
      final active = <String, List<DayNote>>{};
      for (final entry in allNotes.entries) {
        final activeForDate = entry.value.where((n) => n.isActive).toList();
        if (activeForDate.isNotEmpty) {
          active[entry.key] = activeForDate;
        }
      }
      if (!mounted) return;
      setState(() {
        _results = loadedJobs;
        _activeShiftNotes = active;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Job grouping
  // ---------------------------------------------------------------------------

  Map<String, List<JobScanResult>> get _scheduledByDate {
    final map = <String, List<JobScanResult>>{};
    for (final r in _results) {
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

  List<String> get _sortedScheduledDates {
    return _scheduledByDate.keys.toList()..sort();
  }

  List<JobScanResult> get _unscheduledJobs {
    final list = _results.where((r) => r.job.scheduledDate == null).toList();
    list.sort((a, b) => b.job.createdAt.compareTo(a.job.createdAt));
    return list;
  }

  // ---------------------------------------------------------------------------
  // Create job
  // ---------------------------------------------------------------------------

  Future<_JobDialogResult?> _showCreateJobDialog() {
    final nameController = TextEditingController();
    DateTime? selectedDate;

    return showDialog<_JobDialogResult>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Create Job'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Restaurant name',
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Scheduled date',
                        suffixIcon: selectedDate != null
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  setDialogState(() => selectedDate = null);
                                },
                              )
                            : const Icon(Icons.calendar_today, size: 18),
                      ),
                      child: Text(
                        selectedDate != null
                            ? _formatDate(_toYyyyMmDd(selectedDate!))
                            : 'Not scheduled',
                        style: TextStyle(
                          color: selectedDate != null
                              ? null
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    _JobDialogResult(
                      name: nameController.text,
                      scheduledDate: selectedDate,
                    ),
                  ),
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _createJob() async {
    final result = await _showCreateJobDialog();
    if (result == null || !mounted) return;

    final restaurantName = result.name.trim();
    if (restaurantName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restaurant name required')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final scheduledDate = result.scheduledDate != null
          ? _toYyyyMmDd(result.scheduledDate!)
          : null;
      await widget.jobs.createJob(
        restaurantName: restaurantName,
        shiftStartLocal: DateTime.now(),
        scheduledDate: scheduledDate,
      );
      await _loadAll();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static String _toYyyyMmDd(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  // ---------------------------------------------------------------------------
  // Edit job
  // ---------------------------------------------------------------------------

  Future<_JobDialogResult?> _showEditJobDialog(JobScanResult result) {
    final job = result.job;
    final nameController = TextEditingController(text: job.restaurantName);
    DateTime? selectedDate = job.scheduledDate != null
        ? DateTime.tryParse(job.scheduledDate!)
        : null;

    return showDialog<_JobDialogResult>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Job'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Restaurant name',
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Scheduled date',
                        suffixIcon: selectedDate != null
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  setDialogState(() => selectedDate = null);
                                },
                              )
                            : const Icon(Icons.calendar_today, size: 18),
                      ),
                      child: Text(
                        selectedDate != null
                            ? _formatDate(_toYyyyMmDd(selectedDate!))
                            : 'Not scheduled',
                        style: TextStyle(
                          color: selectedDate != null
                              ? null
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    _JobDialogResult(
                      name: nameController.text,
                      scheduledDate: selectedDate,
                      clearScheduledDate: selectedDate == null,
                    ),
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editJob(JobScanResult result) async {
    final edit = await _showEditJobDialog(result);
    if (edit == null || !mounted) return;

    final name = edit.name.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restaurant name required')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await widget.jobs.updateJobDetails(
        jobDir: result.jobDir,
        restaurantName: name,
        scheduledDate: edit.scheduledDate != null
            ? _toYyyyMmDd(edit.scheduledDate!)
            : null,
        clearScheduledDate: edit.clearScheduledDate,
      );
      await _loadAll();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Job navigation
  // ---------------------------------------------------------------------------

  Future<void> _openJobDetail(JobScanResult result) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => JobDetail(jobs: widget.jobs, job: result),
      ),
    );
    if (!mounted) return;
    await _loadAll();
  }

  Future<void> _openManagerNotesScreen(JobScanResult result) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ManagerNotesScreen(
          loadNotes: () async {
            final file = File(p.join(result.jobDir.path, 'job.json'));
            final job = await widget.jobs.jobStore.readJob(file);
            final notes = job?.managerNotes
                    .where((n) => n.isActive)
                    .toList() ??
                <ManagerJobNote>[];
            notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return notes;
          },
          addNote: (text) =>
              widget.jobs.addManagerNote(jobDir: result.jobDir, text: text),
          editNote: (noteId, newText) => widget.jobs.editManagerNote(
            jobDir: result.jobDir,
            noteId: noteId,
            newText: newText,
          ),
          softDeleteNote: (id) => widget.jobs.softDeleteManagerNote(
            jobDir: result.jobDir,
            noteId: id,
          ),
          onMutated: _loadAll,
        ),
      ),
    );
    if (mounted) await _loadAll();
  }

  // ---------------------------------------------------------------------------
  // Shift note operations
  // ---------------------------------------------------------------------------

  Future<String?> _showAddShiftNoteDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Shift Note'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Enter shift note'),
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          textInputAction: TextInputAction.newline,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _addShiftNote(String date) async {
    final text = await _showAddShiftNoteDialog();
    if (text == null || text.isEmpty || !mounted) return;
    try {
      await widget.jobs.addDayNote(date, text);
      await _refreshShiftNotes();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _confirmDeleteShiftNote(
    String date,
    String noteId,
    String noteText,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove shift note?'),
        content: Text(noteText),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await widget.jobs.softDeleteDayNote(date, noteId);
      await _refreshShiftNotes();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _refreshShiftNotes() async {
    final allNotes = await widget.jobs.loadAllDayNotes();
    final active = <String, List<DayNote>>{};
    for (final entry in allNotes.entries) {
      final activeForDate = entry.value.where((n) => n.isActive).toList();
      if (activeForDate.isNotEmpty) {
        active[entry.key] = activeForDate;
      }
    }
    if (mounted) setState(() => _activeShiftNotes = active);
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
        await widget.jobs.setSortOrder(reordered[i].jobDir, i);
      }
      await _loadAll();
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

    setState(() => _isLoading = true);
    try {
      await widget.jobs.deleteJob(jobDir: job.jobDir);
      await _loadAll();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Date formatting (no intl dependency)
  // ---------------------------------------------------------------------------

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  String _formatDate(String yyyyMmDd) {
    final dt = DateTime.tryParse(yyyyMmDd);
    if (dt == null) return yyyyMmDd;
    final weekday = _weekdays[dt.weekday - 1];
    final month = _months[dt.month - 1];
    return '$weekday, $month ${dt.day}, ${dt.year}';
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    Widget body;

    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_results.isEmpty) {
      body = const Center(child: Text('No jobs found.'));
    } else {
      final scheduledByDate = _scheduledByDate;
      final sortedDates = _sortedScheduledDates;
      final unscheduled = _unscheduledJobs;

      body = ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final date in sortedDates)
            _buildDayCard(
              context,
              date: date,
              jobs: scheduledByDate[date]!,
              shiftNotes: _activeShiftNotes[date] ?? const [],
            ),
          if (unscheduled.isNotEmpty)
            _buildUnscheduledSection(context, unscheduled),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('KitchenGuard Jobs')),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _createJob,
        icon: const Icon(Icons.add),
        label: const Text('Create Job'),
      ),
    );
  }

  Widget _buildDayCard(
    BuildContext context, {
    required String date,
    required List<JobScanResult> jobs,
    required List<DayNote> shiftNotes,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Date header
          ColoredBox(
            color: colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 18,
                    color: colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formatDate(date),
                      style: textTheme.titleMedium?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Shift notes section
          _buildShiftNotesSection(context, date: date, notes: shiftNotes),
          // Job tiles
          const Divider(height: 1),
          for (var i = 0; i < jobs.length; i++)
            _buildJobTile(
              context,
              jobs[i],
              onMoveUp: i > 0
                  ? () => _reorderJobs(date, jobs, i, i - 1)
                  : null,
              onMoveDown: i < jobs.length - 1
                  ? () => _reorderJobs(date, jobs, i, i + 1)
                  : null,
            ),
        ],
      ),
    );
  }

  Widget _buildShiftNotesSection(
    BuildContext context, {
    required String date,
    required List<DayNote> notes,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isExpanded = _expandedShiftNotes.contains(date);

    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.assignment_outlined,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: notes.isNotEmpty
                      ? () => setState(() {
                            if (isExpanded) {
                              _expandedShiftNotes.remove(date);
                            } else {
                              _expandedShiftNotes.add(date);
                            }
                          })
                      : null,
                  child: Text(
                    'Shift Notes',
                    style: textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => setState(() {
                      if (isExpanded) {
                        _expandedShiftNotes.remove(date);
                      } else {
                        _expandedShiftNotes.add(date);
                      }
                    }),
                    child: Chip(
                      label: Text('${notes.length}'),
                      labelStyle: textTheme.labelSmall,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      side: BorderSide.none,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    isExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add),
                  iconSize: 20,
                  tooltip: 'Add shift note',
                  onPressed: () => _addShiftNote(date),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (isExpanded && notes.isNotEmpty)
              ...notes.map(
                (note) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: GestureDetector(
                    onLongPress: () =>
                        _confirmDeleteShiftNote(date, note.noteId, note.text),
                    child: Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: colorScheme.outlineVariant,
                          width: 0.5,
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              note.text,
                              style: textTheme.bodyMedium,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            iconSize: 16,
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Remove',
                            onPressed: () => _confirmDeleteShiftNote(
                              date,
                              note.noteId,
                              note.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobTile(
    BuildContext context,
    JobScanResult result, {
    VoidCallback? onMoveUp,
    VoidCallback? onMoveDown,
  }) {
    final job = result.job;
    final restaurant =
        job.restaurantName.isNotEmpty ? job.restaurantName : 'Unknown';
    final activeNoteCount = job.managerNotes.where((n) => n.isActive).length;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasReorder = onMoveUp != null || onMoveDown != null;

    return InkWell(
      onTap: () => _openJobDetail(result),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(restaurant, style: textTheme.bodyLarge),
            ),
            if (activeNoteCount > 0)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: GestureDetector(
                  onTap: () => _openManagerNotesScreen(result),
                  child: Chip(
                    label: Text(
                      '$activeNoteCount '
                      '${activeNoteCount == 1 ? "note" : "notes"}',
                    ),
                    labelStyle: textTheme.labelSmall,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    side: BorderSide.none,
                  ),
                ),
              ),
            if (hasReorder) ...[
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up),
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                tooltip: 'Move up',
                onPressed: onMoveUp,
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down),
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                tooltip: 'Move down',
                onPressed: onMoveDown,
              ),
            ],
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'edit') {
                  await _editJob(result);
                } else if (value == 'delete') {
                  await _confirmDeleteJob(result);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem<String>(
                  value: 'edit',
                  child: Text('Edit Job'),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Text('Delete Job'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnscheduledSection(
    BuildContext context,
    List<JobScanResult> jobs,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: colorScheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule_outlined,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Unscheduled',
                    style: textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          ...jobs.map((result) => _buildJobTile(context, result)),
        ],
      ),
    );
  }
}

class _JobDialogResult {
  const _JobDialogResult({
    required this.name,
    this.scheduledDate,
    this.clearScheduledDate = false,
  });

  final String name;
  final DateTime? scheduledDate;
  final bool clearScheduledDate;
}
