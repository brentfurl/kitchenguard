import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../application/jobs_service.dart';
import '../domain/models/day_note.dart';
import '../domain/models/day_schedule.dart';
import '../domain/models/manager_job_note.dart';
import '../providers/app_role_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/day_notes_provider.dart';
import '../providers/day_schedule_provider.dart';
import '../providers/job_detail_provider.dart';
import '../providers/job_list_provider.dart';
import '../providers/service_providers.dart';
import '../providers/upload_progress_provider.dart';
import '../storage/job_scanner.dart';
import 'job_detail.dart';
import 'screens/manager_notes_screen.dart';

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

  Future<_JobDialogResult?> _showCreateJobDialog() {
    return _showJobDialog(title: 'Create Job', confirmLabel: 'Create');
  }

  Future<_JobDialogResult?> _showJobDialog({
    required String title,
    required String confirmLabel,
    String? initialName,
    DateTime? initialDate,
    String? initialAddress,
    String? initialCity,
    String? initialAccessType,
    String? initialAccessNotes,
    bool? initialHasAlarm,
    String? initialAlarmCode,
    int? initialHoodCount,
    int? initialFanCount,
    List<String>? existingContacts,
    bool isEdit = false,
  }) {
    final nameController = TextEditingController(text: initialName ?? '');
    final addressController = TextEditingController(text: initialAddress ?? '');
    final cityController = TextEditingController(text: initialCity ?? '');
    final accessNotesController =
        TextEditingController(text: initialAccessNotes ?? '');
    final alarmCodeController =
        TextEditingController(text: initialAlarmCode ?? '');
    final hoodCountController = TextEditingController(
      text: initialHoodCount != null ? '$initialHoodCount' : '',
    );
    final fanCountController = TextEditingController(
      text: initialFanCount != null ? '$initialFanCount' : '',
    );
    final contactController = TextEditingController();

    DateTime? selectedDate = initialDate;
    String? accessType = initialAccessType;
    bool hasAlarm = initialHasAlarm ?? false;
    final contactNotes = <String>[...?existingContacts];

    return showDialog<_JobDialogResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final theme = Theme.of(dialogContext);
            final colorScheme = theme.colorScheme;

            final bool hasAddressData =
                addressController.text.isNotEmpty ||
                cityController.text.isNotEmpty;
            final bool hasAccessData =
                accessType != null || hasAlarm;
            final bool hasUnitData =
                hoodCountController.text.isNotEmpty ||
                fanCountController.text.isNotEmpty;

            final needsAccessNotes =
                accessType == 'key-hidden' || accessType == 'lockbox';
            final accessNotesLabel = accessType == 'lockbox'
                ? 'Lockbox code / location'
                : 'Key description';

            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // --- Top section: always visible ---
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
                            context: dialogContext,
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
                                      setDialogState(
                                          () => selectedDate = null);
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
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // --- Expandable: Address ---
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Row(
                          children: [
                            const Text('Address'),
                            if (hasAddressData) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.check_circle,
                                  size: 16, color: colorScheme.primary),
                            ],
                          ],
                        ),
                        initiallyExpanded: hasAddressData,
                        children: [
                          TextField(
                            controller: addressController,
                            decoration: const InputDecoration(
                              labelText: 'Street address',
                              floatingLabelBehavior: FloatingLabelBehavior.always,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: cityController,
                            decoration: const InputDecoration(
                              labelText: 'City',
                              floatingLabelBehavior: FloatingLabelBehavior.always,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),

                      // --- Expandable: Access Info ---
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Row(
                          children: [
                            const Text('Access Info'),
                            if (hasAccessData) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.check_circle,
                                  size: 16, color: colorScheme.primary),
                            ],
                          ],
                        ),
                        initiallyExpanded: hasAccessData,
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: accessType,
                            decoration: const InputDecoration(
                              labelText: 'Access type',
                              floatingLabelBehavior: FloatingLabelBehavior.always,
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('Not set'),
                              ),
                              ..._accessTypeLabels.entries.map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              setDialogState(() => accessType = value);
                            },
                          ),
                          if (needsAccessNotes) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: accessNotesController,
                              decoration: InputDecoration(
                                labelText: accessNotesLabel,
                                floatingLabelBehavior: FloatingLabelBehavior.always,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Alarm'),
                            value: hasAlarm,
                            onChanged: (v) {
                              setDialogState(() => hasAlarm = v);
                            },
                          ),
                          if (hasAlarm) ...[
                              TextField(
                                controller: alarmCodeController,
                                decoration: const InputDecoration(
                                  labelText: 'Alarm code',
                                  floatingLabelBehavior: FloatingLabelBehavior.always,
                                ),
                              ),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ),

                      // --- Expandable: Contacts ---
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Row(
                          children: [
                            const Text('Contacts'),
                            if (contactNotes.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.check_circle,
                                  size: 16, color: colorScheme.primary),
                            ],
                          ],
                        ),
                        children: [
                          for (var ci = 0; ci < contactNotes.length; ci++)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        final editCtrl = TextEditingController(
                                            text: contactNotes[ci]);
                                        showDialog<String>(
                                          context: dialogContext,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('Edit Contact'),
                                            content: TextField(
                                              controller: editCtrl,
                                              autofocus: true,
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(ctx).pop(),
                                                child: const Text('Cancel'),
                                              ),
                                              FilledButton(
                                                onPressed: () =>
                                                    Navigator.of(ctx)
                                                        .pop(editCtrl.text.trim()),
                                                child: const Text('Save'),
                                              ),
                                            ],
                                          ),
                                        ).then((edited) {
                                          if (edited != null && edited.isNotEmpty) {
                                            setDialogState(
                                                () => contactNotes[ci] = edited);
                                          }
                                        });
                                      },
                                      child: Text(contactNotes[ci],
                                          style: theme.textTheme.bodyMedium),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 16),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () {
                                      setDialogState(
                                          () => contactNotes.removeAt(ci));
                                    },
                                  ),
                                ],
                              ),
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: contactController,
                                  decoration: const InputDecoration(
                                    hintText: 'Name (Role) Phone',
                                    isDense: true,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add),
                                onPressed: () {
                                  final text = contactController.text.trim();
                                  if (text.isNotEmpty) {
                                    setDialogState(() {
                                      contactNotes.add(text);
                                      contactController.clear();
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),

                      // --- Expandable: Units ---
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Row(
                          children: [
                            const Text('Units'),
                            if (hasUnitData) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.check_circle,
                                  size: 16, color: colorScheme.primary),
                            ],
                          ],
                        ),
                        initiallyExpanded: hasUnitData,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: hoodCountController,
                                  decoration: const InputDecoration(
                                    labelText: 'Hoods',
                                    floatingLabelBehavior: FloatingLabelBehavior.always,
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextField(
                                  controller: fanCountController,
                                  decoration: const InputDecoration(
                                    labelText: 'Fans',
                                    floatingLabelBehavior: FloatingLabelBehavior.always,
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final hoodCount =
                        int.tryParse(hoodCountController.text.trim());
                    final fanCount =
                        int.tryParse(fanCountController.text.trim());
                    final address = addressController.text.trim();
                    final city = cityController.text.trim();
                    final notes = accessNotesController.text.trim();
                    final alarm = alarmCodeController.text.trim();

                    Navigator.of(dialogContext).pop(
                      _JobDialogResult(
                        name: nameController.text,
                        scheduledDate: selectedDate,
                        clearScheduledDate: isEdit && selectedDate == null,
                        address: address.isNotEmpty ? address : null,
                        clearAddress:
                            isEdit && address.isEmpty && initialAddress != null,
                        city: city.isNotEmpty ? city : null,
                        clearCity:
                            isEdit && city.isEmpty && initialCity != null,
                        accessType: accessType,
                        clearAccessType:
                            isEdit && accessType == null && initialAccessType != null,
                        accessNotes: notes.isNotEmpty ? notes : null,
                        clearAccessNotes:
                            isEdit && notes.isEmpty && initialAccessNotes != null,
                        hasAlarm: hasAlarm ? true : null,
                        clearHasAlarm:
                            isEdit && !hasAlarm && initialHasAlarm == true,
                        alarmCode: alarm.isNotEmpty ? alarm : null,
                        clearAlarmCode:
                            isEdit && alarm.isEmpty && initialAlarmCode != null,
                        hoodCount: hoodCount,
                        clearHoodCount:
                            isEdit &&
                            hoodCount == null &&
                            initialHoodCount != null,
                        fanCount: fanCount,
                        clearFanCount:
                            isEdit &&
                            fanCount == null &&
                            initialFanCount != null,
                        contactNotes: contactNotes,
                      ),
                    );
                  },
                  child: Text(confirmLabel),
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

    try {
      final scheduledDate = result.scheduledDate != null
          ? _toYyyyMmDd(result.scheduledDate!)
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

      // Save contact entries as manager notes
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
    final existingContacts = job.managerNotes
        .where((n) => n.isActive)
        .map((n) => n.text)
        .toList();
    return _showJobDialog(
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

    try {
      await _jobs.updateJobDetails(
        jobDir: result.jobDir,
        restaurantName: name,
        scheduledDate: edit.scheduledDate != null
            ? _toYyyyMmDd(edit.scheduledDate!)
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

      // Reconcile manager notes: soft-delete removed, edit changed, add new
      final job = result.job;
      final activeNotes = job.managerNotes.where((n) => n.isActive).toList();
      final newContactTexts = edit.contactNotes;

      // Soft-delete notes that were removed from the list
      for (var i = 0; i < activeNotes.length; i++) {
        if (i >= newContactTexts.length ||
            activeNotes[i].text != newContactTexts[i]) {
          // If index is out of range or text changed, delete old
          if (i >= newContactTexts.length) {
            await _jobs.softDeleteManagerNote(
                jobDir: result.jobDir, noteId: activeNotes[i].noteId);
          }
        }
      }

      // Edit notes that changed text
      for (var i = 0; i < activeNotes.length && i < newContactTexts.length; i++) {
        if (activeNotes[i].text != newContactTexts[i]) {
          await _jobs.editManagerNote(
            jobDir: result.jobDir,
            noteId: activeNotes[i].noteId,
            newText: newContactTexts[i],
          );
        }
      }

      // Add notes that are new (beyond the original count)
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
      await _jobs.addDayNote(date, text);
      ref.invalidate(dayNotesProvider);
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
    final jobsAsync = ref.watch(jobListProvider);
    final notesAsync = ref.watch(dayNotesProvider);
    final schedulesAsync = ref.watch(dayScheduleProvider);
    final currentRole = ref.watch(appRoleProvider);

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

      if (results.isEmpty) {
        body = const Center(child: Text('No jobs found.'));
      } else {
        final scheduledByDate = _scheduledByDate(results);
        final sortedDates = _sortDayCards(scheduledByDate);
        final unscheduled = _unscheduledJobs(results);
        final todayStr = _toYyyyMmDd(DateTime.now());

        final filteredDates = sortedDates.where((date) {
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

        final showUnscheduled =
            _activeFilters.contains(_JobFilter.unscheduled) &&
                unscheduled.isNotEmpty;

        body = Column(
          children: [
            _buildFilterRow(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 80),
                children: [
                  for (final date in filteredDates)
                    _buildDayCard(
                      context,
                      date: date,
                      jobs: scheduledByDate[date]!,
                      shiftNotes: activeShiftNotes[date] ?? const [],
                      daySchedule: daySchedules[date],
                    ),
                  if (showUnscheduled)
                    _buildUnscheduledSection(context, unscheduled),
                ],
              ),
            ),
          ],
        );
      }
    }

    final isLoading = jobsAsync is AsyncLoading;

    final uploadProgress = ref.watch(uploadProgressProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('KitchenGuard Jobs'),
        actions: [
          if (uploadProgress.isProcessing)
            const _SyncIndicator(isProcessing: true, pendingCount: 0)
          else if (uploadProgress.hasPending)
            _SyncIndicator(
              isProcessing: false,
              pendingCount: uploadProgress.pendingCount,
              onTap: () => ref
                  .read(uploadProgressProvider.notifier)
                  .triggerUpload(),
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
      body: body,
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
            if (filter != _JobFilter.values.first) const SizedBox(width: 8),
            FilterChip(
              label: Text(_filterLabel(filter)),
              selected: _activeFilters.contains(filter),
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

  Widget _buildDayCard(
    BuildContext context, {
    required String date,
    required List<JobScanResult> jobs,
    required List<DayNote> shiftNotes,
    DaySchedule? daySchedule,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final allComplete =
        jobs.isNotEmpty && jobs.every((r) => r.job.isComplete);
    final isToday = date == _toYyyyMmDd(DateTime.now());

    final Color headerColor;
    final Color headerForeground;
    if (allComplete) {
      headerColor = colorScheme.surfaceContainerHigh;
      headerForeground = colorScheme.onSurfaceVariant;
    } else if (isToday) {
      headerColor = colorScheme.primary;
      headerForeground = colorScheme.onPrimary;
    } else {
      headerColor = colorScheme.primaryContainer;
      headerForeground = colorScheme.onPrimaryContainer;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Day card header
          ColoredBox(
            color: headerColor,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    allComplete ? Icons.check_circle : Icons.calendar_today,
                    size: 18,
                    color: headerForeground,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formatDate(date),
                      style: textTheme.titleMedium?.copyWith(
                        color: headerForeground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isToday && !allComplete)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.onPrimary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'TODAY',
                        style: textTheme.labelSmall?.copyWith(
                          color: headerForeground,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Arrival times section
          _buildArrivalTimesSection(context, date: date, shiftNotes: shiftNotes, schedule: daySchedule, firstJob: jobs.isNotEmpty ? jobs.first : null),
          const Divider(height: 1),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: jobs.length,
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex--;
              _reorderJobs(date, jobs, oldIndex, newIndex);
            },
            itemBuilder: (context, i) {
              return _buildJobSubCard(
                context,
                key: ValueKey(jobs[i].job.jobId),
                result: jobs[i],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildArrivalTimesSection(
    BuildContext context, {
    required String date,
    required List<DayNote> shiftNotes,
    DaySchedule? schedule,
    JobScanResult? firstJob,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasShopTime = schedule?.shopMeetupTime != null;
    final hasArrival = schedule?.firstArrivalTime != null;
    final hasAnyTime = hasShopTime || hasArrival;

    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _showArrivalTimeDialog(date, schedule, firstJob),
                child: hasAnyTime
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (hasShopTime)
                            Row(
                              children: [
                                Icon(Icons.store_outlined,
                                    size: 16, color: colorScheme.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Text(
                                  'Shop meetup: ${schedule!.shopMeetupTime}',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          if (hasArrival) ...[
                            if (hasShopTime) const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.restaurant_outlined,
                                    size: 16, color: colorScheme.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${schedule!.firstRestaurantName ?? "First restaurant"} arrival: ${schedule.firstArrivalTime}',
                                    style: textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      )
                    : Row(
                        children: [
                          Icon(Icons.schedule_outlined,
                              size: 16, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Text(
                            'Add arrival times',
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: shiftNotes.isNotEmpty
                      ? () => _openShiftNotesScreen(date, shiftNotes)
                      : () => _addShiftNote(date),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.assignment_outlined,
                            size: 16, color: colorScheme.onSurfaceVariant),
                        if (shiftNotes.isNotEmpty) ...[
                          const SizedBox(width: 2),
                          Text(
                            '${shiftNotes.length}',
                            style: textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ] else ...[
                          const SizedBox(width: 2),
                          Icon(Icons.add, size: 14, color: colorScheme.onSurfaceVariant),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showArrivalTimeDialog(
    String date,
    DaySchedule? existing,
    JobScanResult? firstJob,
  ) async {
    final arrivalController = TextEditingController(
      text: existing?.firstArrivalTime ?? '',
    );
    final shopController = TextEditingController(
      text: existing?.shopMeetupTime ?? '',
    );
    final restaurantName =
        existing?.firstRestaurantName ??
        firstJob?.job.restaurantName ??
        '';

    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Arrival Times'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: arrivalController,
                decoration: InputDecoration(
                  labelText: restaurantName.isNotEmpty
                      ? '$restaurantName arrival'
                      : 'First restaurant arrival',
                  hintText: 'e.g. 9:45',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: shopController,
                decoration: const InputDecoration(
                  labelText: 'Shop meetup time',
                  hintText: 'e.g. 9:15 (optional)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            if (existing != null && !existing.isEmpty)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop({
                  'clear': 'true',
                }),
                child: const Text('Clear'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop({
                'arrival': arrivalController.text.trim(),
                'shop': shopController.text.trim(),
                'restaurant': restaurantName,
              }),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (result == null || !mounted) return;

    try {
      if (result.containsKey('clear')) {
        await _jobs.setDaySchedule(
          date: date,
          clearShopMeetupTime: true,
          clearFirstRestaurantName: true,
          clearFirstArrivalTime: true,
        );
      } else {
        final arrival = result['arrival'];
        final shop = result['shop'];
        final name = result['restaurant'];
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.5,
              minChildSize: 0.3,
              maxChildSize: 0.85,
              expand: false,
              builder: (_, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                      child: Row(
                        children: [
                          Text(
                            'Shift Notes',
                            style: Theme.of(sheetContext).textTheme.titleMedium,
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: () async {
                              await _addShiftNote(date);
                              if (!mounted) return;
                              ref.invalidate(dayNotesProvider);
                              Navigator.of(sheetContext).pop();
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(sheetContext).pop(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: notes.isEmpty
                          ? const Center(child: Text('No shift notes'))
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: notes.length,
                              padding: const EdgeInsets.all(16),
                              itemBuilder: (_, i) {
                                final note = notes[i];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(note.text),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                            Icons.delete_outline,
                                            size: 18),
                                        onPressed: () async {
                                          await _confirmDeleteShiftNote(
                                            date,
                                            note.noteId,
                                            note.text,
                                          );
                                          if (!mounted) return;
                                          Navigator.of(sheetContext).pop();
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
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

  Widget _buildJobSubCard(
    BuildContext context, {
    required Key key,
    required JobScanResult result,
  }) {
    final job = result.job;
    final restaurant =
        job.restaurantName.isNotEmpty ? job.restaurantName : 'Unknown';
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final hoodCount = job.hoodCount ?? job.units.where((u) => u.type == 'hood').length;
    final fanCount = job.fanCount ?? job.units.where((u) => u.type == 'fan').length;
    final unitSummaryParts = <String>[];
    if (hoodCount > 0) unitSummaryParts.add('$hoodCount ${hoodCount == 1 ? "hood" : "hoods"}');
    if (fanCount > 0) unitSummaryParts.add('$fanCount ${fanCount == 1 ? "fan" : "fans"}');
    final unitSummary = unitSummaryParts.join(', ');

    final accessLabel = job.accessType != null
        ? _accessTypeLabels[job.accessType] ?? job.accessType!
        : null;

    // Build access detail string with notes and alarm code
    final accessDetailParts = <String>[];
    if (accessLabel != null) {
      final accessWithNotes = (job.accessNotes != null && job.accessNotes!.isNotEmpty)
          ? '$accessLabel, ${job.accessNotes}'
          : accessLabel;
      accessDetailParts.add(accessWithNotes);
    }
    if (job.hasAlarm == true) {
      final alarmText = (job.alarmCode != null && job.alarmCode!.isNotEmpty)
          ? 'Alarm, ${job.alarmCode}'
          : 'Alarm';
      accessDetailParts.add(alarmText);
    }
    final accessDetail = accessDetailParts.join(' · ');

    return Card(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 1,
      child: InkWell(
        onTap: () => _openJobDetail(result),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (job.isComplete)
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 2),
                  child: Icon(
                    Icons.check_circle,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurant,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: job.isComplete
                            ? colorScheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                    if (job.address != null && job.address!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        job.city != null && job.city!.isNotEmpty
                            ? '${job.address!}, ${job.city!}'
                            : job.address!,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (unitSummary.isNotEmpty || accessDetail.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (unitSummary.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.grid_view_outlined,
                                    size: 14,
                                    color: colorScheme.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(
                                  unitSummary,
                                  style: textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          if (accessDetail.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.key_outlined,
                                    size: 14,
                                    color: colorScheme.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    accessDetail,
                                    style: textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (job.managerNotes.where((n) => n.isActive).isNotEmpty)
                    GestureDetector(
                      onTap: () => _openManagerNotesScreen(result),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.note_alt_outlined,
                                size: 18, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 2),
                            Text(
                              '${job.managerNotes.where((n) => n.isActive).length}',
                              style: textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'edit') {
                        await _editJob(result);
                      } else if (value == 'delete') {
                        await _confirmDeleteJob(result);
                      } else if (value == 'complete') {
                        await _toggleJobCompletion(result);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem<String>(
                        value: 'edit',
                        child: Text('Edit Job'),
                      ),
                      PopupMenuItem<String>(
                        value: 'complete',
                        child: Text(
                          job.isComplete ? 'Reopen Job' : 'Mark Complete',
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: Text('Delete Job'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJobTile(BuildContext context, JobScanResult result) {
    final job = result.job;
    final restaurant =
        job.restaurantName.isNotEmpty ? job.restaurantName : 'Unknown';
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: () => _openJobDetail(result),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            if (job.isComplete)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.check_circle,
                  size: 18,
                  color: colorScheme.primary,
                ),
              ),
            Expanded(
              child: Text(
                restaurant,
                style: textTheme.bodyLarge?.copyWith(
                  color: job.isComplete
                      ? colorScheme.onSurfaceVariant
                      : null,
                ),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'edit') {
                  await _editJob(result);
                } else if (value == 'delete') {
                  await _confirmDeleteJob(result);
                } else if (value == 'complete') {
                  await _toggleJobCompletion(result);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  value: 'edit',
                  child: Text('Edit Job'),
                ),
                PopupMenuItem<String>(
                  value: 'complete',
                  child: Text(
                    job.isComplete ? 'Reopen Job' : 'Mark Complete',
                  ),
                ),
                const PopupMenuItem<String>(
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
    this.address,
    this.clearAddress = false,
    this.city,
    this.clearCity = false,
    this.accessType,
    this.clearAccessType = false,
    this.accessNotes,
    this.clearAccessNotes = false,
    this.hasAlarm,
    this.clearHasAlarm = false,
    this.alarmCode,
    this.clearAlarmCode = false,
    this.hoodCount,
    this.clearHoodCount = false,
    this.fanCount,
    this.clearFanCount = false,
    this.contactNotes = const [],
  });

  final String name;
  final DateTime? scheduledDate;
  final bool clearScheduledDate;
  final String? address;
  final bool clearAddress;
  final String? city;
  final bool clearCity;
  final String? accessType;
  final bool clearAccessType;
  final String? accessNotes;
  final bool clearAccessNotes;
  final bool? hasAlarm;
  final bool clearHasAlarm;
  final String? alarmCode;
  final bool clearAlarmCode;
  final int? hoodCount;
  final bool clearHoodCount;
  final int? fanCount;
  final bool clearFanCount;
  final List<String> contactNotes;
}

const _accessTypeLabels = <String, String>{
  'no-key': 'No key — meet after closing',
  'get-key-from-shop': 'Get key from shop',
  'key-hidden': 'Key hidden',
  'lockbox': 'Lockbox',
};

/// Compact sync status indicator for the AppBar.
///
/// Shows a spinning cloud icon while uploading, or a cloud-upload icon
/// with a pending-count badge when items are queued. Tapping triggers
/// a manual sync attempt.
class _SyncIndicator extends StatelessWidget {
  const _SyncIndicator({
    required this.isProcessing,
    required this.pendingCount,
    this.onTap,
  });

  final bool isProcessing;
  final int pendingCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (isProcessing) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return IconButton(
      icon: Badge(
        label: Text('$pendingCount'),
        child: const Icon(Icons.cloud_upload_outlined),
      ),
      tooltip: '$pendingCount pending upload${pendingCount == 1 ? '' : 's'}',
      onPressed: onTap,
    );
  }
}
