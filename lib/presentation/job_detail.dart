import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../application/jobs_service.dart';
import '../domain/models/job.dart';
import '../domain/models/photo_record.dart';
import '../domain/models/unit.dart';
import '../utils/unit_sorter.dart';
import 'controllers/job_detail_controller.dart';
import 'screens/manager_notes_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/pre_clean_layout_screen.dart';
import 'screens/photo_viewer_screen.dart';
import 'screens/rapid_photo_capture_screen.dart';
import 'screens/tools_screen.dart';
import 'screens/unit_photo_bucket_screen.dart';
import 'screens/videos_screen.dart';
import '../storage/job_scanner.dart';

class JobDetail extends StatefulWidget {
  const JobDetail({super.key, required this.jobs, required this.job});

  final JobsService jobs;
  final JobScanResult job;

  @override
  State<JobDetail> createState() => _JobDetailState();
}

class _JobDetailState extends State<JobDetail> {
  bool _isExporting = false;
  bool _isOpeningRapidBefore = false;
  bool _isOpeningRapidAfter = false;
  late final JobDetailController _controller;
  late Job _job;
  bool _isBusy = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _controller = JobDetailController(
      jobs: widget.jobs,
      jobDir: widget.job.jobDir,
    );
    _job = widget.job.job;
    Future<void>.microtask(_reloadJob);
  }

  String _bucketLabel(String bucket, int count) => '$bucket ($count)';

  Future<void> _addUnitFlow() async {
    await _reloadJob();
    if (!mounted) return;

    final request = await _showAddUnitDialog();
    if (request == null || !mounted) {
      return;
    }

    setState(() {
      _isBusy = true;
    });

    try {
      await widget.jobs.addUnit(
        jobDir: widget.job.jobDir,
        unitName: request.unitName,
        unitType: request.unitType,
      );
      await _reloadJob();
    } catch (error) {
      if (!mounted) return;
      final raw = error.toString();
      final cleaned = raw.replaceFirst(RegExp(r'^StateError:\s*'), '');
      final message = cleaned.contains('Unit name already exists')
          ? 'Unit "${request.unitName}" already exists.'
          : cleaned;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _reloadJob() async {
    final fresh = await _controller.loadJob();
    if (!mounted) return;
    setState(() {
      _job = fresh;
    });
  }

  Future<void> _openSchedulePicker() async {
    final current = _job.scheduledDate;
    final initial = current != null
        ? DateTime.tryParse(current) ?? DateTime.now()
        : DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked == null || !mounted) return;
    final y = picked.year.toString().padLeft(4, '0');
    final m = picked.month.toString().padLeft(2, '0');
    final d = picked.day.toString().padLeft(2, '0');
    await _controller.setScheduledDate('$y-$m-$d');
    await _reloadJob();
  }

  Future<void> _clearScheduledDate() async {
    await _controller.setScheduledDate(null);
    await _reloadJob();
  }

  Future<int> _loadUnitVisiblePhotoCount({
    required String unitId,
    required String phase,
  }) async {
    final job = await _controller.loadJob();
    try {
      final unit = job.units.firstWhere((u) => u.unitId == unitId);
      return phase == 'before'
          ? unit.visibleBeforeCount
          : unit.visibleAfterCount;
    } on StateError {
      return 0;
    }
  }

  Future<void> _openRapidBeforeCapture({
    required String unitId,
    required String unitName,
  }) async {
    if (_isOpeningRapidBefore) {
      return;
    }
    setState(() {
      _isOpeningRapidBefore = true;
    });
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RapidPhotoCaptureScreen(
            unitName: unitName.isEmpty ? 'Unnamed unit' : unitName,
            phaseLabel: 'Before',
            loadVisibleCount: () =>
                _loadUnitVisiblePhotoCount(unitId: unitId, phase: 'before'),
            onCaptureFile: (file) => _controller.capturePhotoFromFile(
              unitId: unitId,
              phase: 'before',
              sourceImageFile: file,
            ),
          ),
        ),
      );
      if (!mounted) return;
      await _reloadJob();
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningRapidBefore = false;
        });
      } else {
        _isOpeningRapidBefore = false;
      }
    }
  }

  Future<List<PhotoRecord>> _loadUnitPhotos({
    required String unitId,
    required String phase,
  }) async {
    final job = await _controller.loadJob();
    try {
      final unit = job.units.firstWhere((u) => u.unitId == unitId);
      final photos =
          phase == 'before' ? unit.photosBefore : unit.photosAfter;
      return photos.where((p) => p.isActive).toList(growable: false);
    } on StateError {
      return const <PhotoRecord>[];
    }
  }

  Future<void> _openBeforeGallery({
    required String unitId,
    required String unitName,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UnitPhotoBucketScreen(
          title: '$unitName — Before',
          jobDir: widget.job.jobDir,
          loadPhotos: () => _loadUnitPhotos(unitId: unitId, phase: 'before'),
          onCapture: () async {
            await _openRapidBeforeCapture(unitId: unitId, unitName: unitName);
          },
          onJobMutated: () async {
            await _reloadJob();
          },
          onSoftDelete: (relativePath) async {
            await _controller.softDeletePhoto(
              unitId: unitId,
              phase: 'before',
              relativePath: relativePath,
            );
          },
          onOpenViewer: (initialIndex, photos) async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PhotoViewerScreen(
                  jobDir: widget.job.jobDir,
                  title: '$unitName — Before',
                  photos: photos,
                  initialIndex: initialIndex,
                  onSoftDelete: (relativePath) => _controller.softDeletePhoto(
                    unitId: unitId,
                    phase: 'before',
                    relativePath: relativePath,
                  ),
                  onJobMutated: () async {
                    await _reloadJob();
                  },
                  reloadPhotos: () =>
                      _loadUnitPhotos(unitId: unitId, phase: 'before'),
                ),
              ),
            );
          },
        ),
      ),
    );
    if (!mounted) return;
    await _reloadJob();
  }

  Future<void> _openRapidAfterCapture({
    required String unitId,
    required String unitName,
  }) async {
    if (_isOpeningRapidAfter) {
      return;
    }
    setState(() {
      _isOpeningRapidAfter = true;
    });
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RapidPhotoCaptureScreen(
            unitName: unitName.isEmpty ? 'Unnamed unit' : unitName,
            phaseLabel: 'After',
            loadVisibleCount: () =>
                _loadUnitVisiblePhotoCount(unitId: unitId, phase: 'after'),
            onCaptureFile: (file) => _controller.capturePhotoFromFile(
              unitId: unitId,
              phase: 'after',
              sourceImageFile: file,
            ),
          ),
        ),
      );
      if (!mounted) return;
      await _reloadJob();
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningRapidAfter = false;
        });
      } else {
        _isOpeningRapidAfter = false;
      }
    }
  }

  Future<void> _openAfterGallery({
    required String unitId,
    required String unitName,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UnitPhotoBucketScreen(
          title: '$unitName — After',
          jobDir: widget.job.jobDir,
          loadPhotos: () => _loadUnitPhotos(unitId: unitId, phase: 'after'),
          onCapture: () async {
            await _openRapidAfterCapture(unitId: unitId, unitName: unitName);
          },
          onJobMutated: () async {
            await _reloadJob();
          },
          onSoftDelete: (relativePath) async {
            await _controller.softDeletePhoto(
              unitId: unitId,
              phase: 'after',
              relativePath: relativePath,
            );
          },
          onOpenViewer: (initialIndex, photos) async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PhotoViewerScreen(
                  jobDir: widget.job.jobDir,
                  title: '$unitName — After',
                  photos: photos,
                  initialIndex: initialIndex,
                  onSoftDelete: (relativePath) => _controller.softDeletePhoto(
                    unitId: unitId,
                    phase: 'after',
                    relativePath: relativePath,
                  ),
                  onJobMutated: () async {
                    await _reloadJob();
                  },
                  reloadPhotos: () =>
                      _loadUnitPhotos(unitId: unitId, phase: 'after'),
                ),
              ),
            );
          },
        ),
      ),
    );
    if (!mounted) return;
    await _reloadJob();
  }

  Future<void> _renameUnitFlow({
    required String unitId,
    required String currentName,
  }) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Unit Name'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Unit name'),
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
        );
      },
    );

    if (newName == null) return;

    try {
      await _controller.renameUnit(unitId: unitId, newName: newName);
      if (!mounted) return;
      await _reloadJob();
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst(
        RegExp(r'^(StateError|ArgumentError|Exception):\s*'),
        '',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message.isEmpty ? 'Failed to rename unit' : message),
        ),
      );
    }
  }

  Future<void> _showCannotDeleteUnitDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cannot Delete Unit'),
        content: const Text(
          'This unit has photos. Remove unit photos first, then try deleting the unit.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndRemoveUnit({
    required String unitId,
    required String unitName,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Unit?'),
        content: Text('Remove "$unitName" from this job?'),
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

    if (confirmed != true) {
      return;
    }

    try {
      await _controller.deleteUnitIfEmpty(unitId: unitId);
      if (!mounted) return;
      await _reloadJob();
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst(
        RegExp(r'^(StateError|ArgumentError|Exception):\s*'),
        '',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message.isEmpty ? 'Failed to remove unit' : message),
        ),
      );
    }
  }

  Unit? _findUnitInState(String unitId) {
    try {
      return _job.units.firstWhere((u) => u.unitId == unitId);
    } on StateError {
      return null;
    }
  }

  bool _unitHasActivePhotos(Unit unit) {
    return unit.visibleBeforeCount > 0 || unit.visibleAfterCount > 0;
  }

  String _nextUnitNameSuggestion({
    required String unitType,
    required List<Unit> units,
  }) {
    final normalizedType = unitType.trim().toLowerCase();
    if (normalizedType != 'hood' && normalizedType != 'fan') {
      return '';
    }

    final pattern = RegExp(
      '^${RegExp.escape(normalizedType)}\\s*(\\d+)\$',
      caseSensitive: false,
    );
    var highest = 0;

    for (final unit in units) {
      if (unit.type.trim().toLowerCase() != normalizedType) {
        continue;
      }
      final match = pattern.firstMatch(unit.name.trim());
      if (match == null) {
        continue;
      }
      final value = int.tryParse(match.group(1)!);
      if (value != null && value > highest) {
        highest = value;
      }
    }

    return '$normalizedType ${highest + 1}';
  }

  String _normalizeUnitNameForValidation(String name) {
    return name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> _openExitVideosScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideosScreen(
          title: 'Exit Videos',
          kind: 'exit',
          loadVideos: () => _controller.loadVideos(kind: 'exit'),
          captureVideo: () async {
            await _controller.captureVideo(kind: 'exit', picker: _picker);
            await _reloadJob();
          },
          softDelete: (relativePath) async {
            await _controller.softDeleteVideo(
              kind: 'exit',
              relativePath: relativePath,
            );
            await _reloadJob();
          },
          resolveVideoFile: (relativePath) async {
            final file = _controller.videoFileFromRelativePath(relativePath);
            return await file.exists() ? file : null;
          },
        ),
      ),
    );
    if (!mounted) return;
    await _reloadJob();
  }

  Future<void> _openOtherVideosScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideosScreen(
          title: 'Other Videos',
          kind: 'other',
          loadVideos: () => _controller.loadVideos(kind: 'other'),
          captureVideo: () async {
            await _controller.captureVideo(kind: 'other', picker: _picker);
            await _reloadJob();
          },
          softDelete: (relativePath) async {
            await _controller.softDeleteVideo(
              kind: 'other',
              relativePath: relativePath,
            );
            await _reloadJob();
          },
          resolveVideoFile: (relativePath) async {
            final file = _controller.videoFileFromRelativePath(relativePath);
            return await file.exists() ? file : null;
          },
        ),
      ),
    );
    if (!mounted) return;
    await _reloadJob();
  }

  Future<void> _openToolsScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ToolsScreen(
          onPrecleanLayout: _openPreCleanLayoutScreen,
          onNotes: _openNotesScreen,
          onExitVideos: _openExitVideosScreen,
          onOtherVideos: _openOtherVideosScreen,
          preCleanLayoutCount: () => _controller.preCleanLayoutCount,
          notesCount: () => _controller.notesCount,
          exitVideosCount: () => _controller.videosExitCount,
          otherVideosCount: () => _controller.videosOtherCount,
        ),
      ),
    );
    if (!mounted) return;
    await _reloadJob();
  }

  Future<void> _openPreCleanLayoutScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PreCleanLayoutScreen(
          jobDir: widget.job.jobDir,
          loadPhotos: () => _controller.loadPreCleanLayoutPhotos(),
          onCaptureFile: (file) async {
            await _controller.capturePreCleanLayoutPhotoFromFile(
              sourceImageFile: file,
            );
          },
          onSoftDelete: (relativePath) async {
            await _controller.softDeletePreCleanLayoutPhoto(
              relativePath: relativePath,
            );
          },
          onJobMutated: _reloadJob,
        ),
      ),
    );
    if (!mounted) return;
    await _reloadJob();
  }

  Future<void> _openNotesScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotesScreen(
          loadNotes: () async {
            await _controller.loadJob();
            return _controller.activeNotes;
          },
          addNote: (text) => _controller.addNote(text),
          softDeleteNote: (noteId) => _controller.softDeleteNote(noteId),
          onMutated: _reloadJob,
        ),
      ),
    );
    if (!mounted) return;
    await _reloadJob();
  }

  Future<void> _openManagerNotesScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ManagerNotesScreen(
          loadNotes: () async {
            await _controller.loadJob();
            return _controller.activeManagerNotes;
          },
          addNote: (text) => _controller.addManagerNote(text),
          editNote: (noteId, newText) =>
              _controller.editManagerNote(noteId, newText),
          softDeleteNote: (noteId) =>
              _controller.softDeleteManagerNote(noteId),
          onMutated: _reloadJob,
        ),
      ),
    );
    if (!mounted) return;
    await _reloadJob();
  }

  Future<void> _exportJob() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(width: 16),
              Expanded(child: Text('Exporting job...')),
            ],
          ),
        ),
      ),
    );

    var dialogClosed = false;

    try {
      final zipFile = await _controller.exportJob();
      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).pop();
      dialogClosed = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.microtask(() async {
          try {
            await Share.shareXFiles([
              XFile(zipFile.path),
            ], text: 'KitchenGuard job export');
          } catch (error) {
            if (!mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Share failed: $error')));
          }
        });
      });
    } catch (error) {
      if (!mounted) return;

      if (!dialogClosed) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      final message = error.toString().replaceFirst(
        RegExp(r'^(StateError|Exception|PlatformException)\(.*?\):\s*'),
        '',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message.isEmpty ? 'Failed to export job' : message),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      } else {
        _isExporting = false;
      }
    }
  }

  Future<_AddUnitRequest?> _showAddUnitDialog() async {
    final nameController = TextEditingController();
    String selectedType = 'hood';
    final units = _job.units;
    String? lastAutoSuggestion;
    var hasManualOverride = false;
    String? validationError;

    void applyAutoSuggestion({bool force = false}) {
      final suggestion = _nextUnitNameSuggestion(
        unitType: selectedType,
        units: units,
      );
      final current = nameController.text.trim();
      final canAutoFill =
          force ||
          !hasManualOverride ||
          (lastAutoSuggestion != null && current == lastAutoSuggestion);

      if (suggestion.isEmpty) {
        final shouldClear = canAutoFill;
        if (shouldClear && current.isNotEmpty) {
          nameController.value = const TextEditingValue(
            text: '',
            selection: TextSelection.collapsed(offset: 0),
          );
        }
        lastAutoSuggestion = null;
        hasManualOverride = false;
        return;
      }

      final shouldApply = canAutoFill || current.isEmpty;
      if (!shouldApply) {
        return;
      }

      nameController.value = TextEditingValue(
        text: suggestion,
        selection: TextSelection.collapsed(offset: suggestion.length),
      );
      lastAutoSuggestion = suggestion;
      hasManualOverride = false;
    }

    applyAutoSuggestion(force: true);

    return showDialog<_AddUnitRequest>(
      context: context,
      useRootNavigator: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Unit'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Unit name'),
                    autofocus: true,
                    onChanged: (value) {
                      final trimmed = value.trim();
                      hasManualOverride =
                          !(lastAutoSuggestion != null &&
                              trimmed == lastAutoSuggestion);
                      if (validationError != null) {
                        setDialogState(() {
                          validationError = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(labelText: 'Unit type'),
                    items: const [
                      DropdownMenuItem(value: 'hood', child: Text('hood')),
                      DropdownMenuItem(value: 'fan', child: Text('fan')),
                      DropdownMenuItem(value: 'misc', child: Text('misc')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        selectedType = value;
                        validationError = null;
                      });
                      applyAutoSuggestion();
                    },
                  ),
                  if (validationError != null) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        validationError!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final unitName = nameController.text.trim();
                    final normalizedCandidate = _normalizeUnitNameForValidation(
                      unitName,
                    );
                    if (unitName.isEmpty) {
                      setDialogState(() {
                        validationError = 'Please enter a unit name.';
                      });
                      return;
                    }

                    for (final unit in units) {
                      if (unit.type.trim().toLowerCase() !=
                          selectedType.trim().toLowerCase()) {
                        continue;
                      }
                      if (_normalizeUnitNameForValidation(unit.name) ==
                          normalizedCandidate) {
                        setDialogState(() {
                          validationError = 'Unit name already exists.';
                        });
                        return;
                      }
                    }

                    setDialogState(() {
                      validationError = null;
                    });
                    Navigator.of(context).pop(
                      _AddUnitRequest(
                        unitName: unitName,
                        unitType: selectedType,
                      ),
                    );
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final units = UnitSorter.sort(_job.units);
    final listBottomPadding = 120.0 + MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text(''),
        actions: [
          IconButton(
            onPressed: _isExporting ? null : _exportJob,
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Export Job',
          ),
          IconButton(
            onPressed: _openToolsScreen,
            icon: const Icon(Icons.handyman_outlined),
            tooltip: 'Tools',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _JobHeader(
            restaurantName: _job.restaurantName,
            scheduledDate: _job.scheduledDate,
            onSchedule: _openSchedulePicker,
            onClearSchedule: _clearScheduledDate,
          ),
          _ManagerNotesCard(
            count: _job.managerNotes.where((n) => n.isActive).length,
            onTap: _openManagerNotesScreen,
          ),
          _ToolsCard(onTap: _openToolsScreen),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Units', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  'Capture before and after photos for each unit',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: units.isEmpty
                ? const Center(child: Text('No units yet.'))
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, listBottomPadding),
                    itemCount: units.length,
                    itemBuilder: (context, index) {
                      final unit = units[index];
                      final unitId = unit.unitId;
                      final name = unit.name;
                      final type = unit.type;
                      final beforeCount = unit.visibleBeforeCount;
                      final afterCount = unit.visibleAfterCount;

                      return Card(
                        key: ValueKey(unitId),
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      name.isEmpty ? 'Unnamed unit' : name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    tooltip: 'Unit actions',
                                    onSelected: (value) async {
                                      if (value == 'edit') {
                                        await _renameUnitFlow(
                                          unitId: unitId,
                                          currentName: name,
                                        );
                                      } else if (value == 'delete') {
                                        await _reloadJob();
                                        if (!mounted) return;
                                        final latestUnit =
                                            _findUnitInState(unitId) ?? unit;
                                        if (_unitHasActivePhotos(latestUnit)) {
                                          await _showCannotDeleteUnitDialog();
                                        } else {
                                          await _confirmAndRemoveUnit(
                                            unitId: unitId,
                                            unitName: name.isEmpty
                                                ? 'Unnamed unit'
                                                : name,
                                          );
                                        }
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem<String>(
                                        value: 'edit',
                                        child: Text('Edit Name'),
                                      ),
                                      PopupMenuItem<String>(
                                        value: 'delete',
                                        child: Text('Delete Unit'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                type,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton(
                                      onPressed:
                                          _isBusy || _isOpeningRapidBefore
                                          ? null
                                          : () async {
                                              await _openRapidBeforeCapture(
                                                unitId: unitId,
                                                unitName: name,
                                              );
                                            },
                                      child: Text(
                                        _bucketLabel('Before', beforeCount),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  IconButton(
                                    onPressed: _isBusy
                                        ? null
                                        : () async {
                                            await _openBeforeGallery(
                                              unitId: unitId,
                                              unitName: name,
                                            );
                                          },
                                    tooltip: 'View Before Photos',
                                    icon: const Icon(
                                      Icons.photo_library_outlined,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _isBusy || _isOpeningRapidAfter
                                          ? null
                                          : () async {
                                              await _openRapidAfterCapture(
                                                unitId: unitId,
                                                unitName: name,
                                              );
                                            },
                                      child: Text(
                                        _bucketLabel('After', afterCount),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  IconButton(
                                    onPressed: _isBusy
                                        ? null
                                        : () async {
                                            await _openAfterGallery(
                                              unitId: unitId,
                                              unitName: name,
                                            );
                                          },
                                    tooltip: 'View After Photos',
                                    icon: const Icon(
                                      Icons.photo_library_outlined,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isBusy ? null : _addUnitFlow,
        icon: const Icon(Icons.add),
        label: const Text('Add Unit'),
      ),
    );
  }
}

class _AddUnitRequest {
  const _AddUnitRequest({required this.unitName, required this.unitType});

  final String unitName;
  final String unitType;
}

class _JobHeader extends StatelessWidget {
  const _JobHeader({
    required this.restaurantName,
    required this.scheduledDate,
    required this.onSchedule,
    required this.onClearSchedule,
  });

  final String restaurantName;
  final String? scheduledDate;
  final VoidCallback onSchedule;
  final VoidCallback onClearSchedule;

  String _formatScheduledDate(String date) {
    try {
      final dt = DateTime.parse(date);
      const months = [
        '',
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${months[dt.month]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return date;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            restaurantName,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (scheduledDate != null) ...[
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  _formatScheduledDate(scheduledDate!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: onSchedule,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Text(
                      'Change',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                InkWell(
                  onTap: onClearSchedule,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            InkWell(
              onTap: onSchedule,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outline),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Schedule',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ManagerNotesCard extends StatelessWidget {
  const _ManagerNotesCard({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Card(
        elevation: 1.5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.note_alt_outlined,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Text('Job Notes', style: theme.textTheme.titleMedium),
                const SizedBox(width: 8),
                if (count > 0)
                  Chip(
                    label: Text('$count'),
                    labelStyle: theme.textTheme.labelSmall,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    side: BorderSide.none,
                  ),
                const Spacer(),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolsCard extends StatelessWidget {
  const _ToolsCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Card(
        elevation: 2.5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Tools', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        'Pre-clean layout, field notes, and videos',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
