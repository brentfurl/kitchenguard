import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../application/jobs_service.dart';
import 'controllers/job_detail_controller.dart';
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
  late Map<String, dynamic> _jobData;
  bool _isBusy = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _controller = JobDetailController(
      jobs: widget.jobs,
      jobDir: widget.job.jobDir,
    );
    _jobData = Map<String, dynamic>.from(widget.job.jobData);
    Future<void>.microtask(_reloadJobJson);
  }

  int _countActivePhotos(dynamic list) {
    return _controller.countDisplayablePhotos(list);
  }

  String _bucketLabel(String bucket, int count) => '$bucket ($count)';

  Future<void> _addUnitFlow() async {
    await _reloadJobJson();
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
      await _reloadJobJson();
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

  Future<void> _reloadJobJson() async {
    final fresh = await _controller.loadJob();

    if (!mounted) return;
    setState(() {
      _jobData = fresh;
    });
  }

  Future<void> _setUnitCompletion({
    required String unitId,
    required bool isComplete,
  }) async {
    try {
      await _controller.setUnitCompletion(
        unitId: unitId,
        isComplete: isComplete,
      );
      if (!mounted) return;
      await _reloadJobJson();
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst(
        RegExp(r'^(StateError|ArgumentError|Exception):\s*'),
        '',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message.isEmpty ? 'Failed to update unit completion' : message,
          ),
        ),
      );
    }
  }

  Future<int> _loadUnitVisiblePhotoCount({
    required String unitId,
    required String phase,
  }) async {
    final job = await _controller.loadJob();
    final unit = _controller.findUnitById(job, unitId);
    if (unit == null) {
      return 0;
    }
    final key = phase == 'before' ? 'photosBefore' : 'photosAfter';
    return _countActivePhotos(unit[key]);
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
      await _reloadJobJson();
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

  Future<void> _openBeforeGallery({
    required String unitId,
    required String unitName,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UnitPhotoBucketScreen(
          title: '$unitName — Before',
          jobDir: widget.job.jobDir,
          loadPhotos: () async {
            final job = await _controller.loadJob();
            final u = _controller.findUnitById(job, unitId);
            return (u == null)
                ? <Map<String, dynamic>>[]
                : _controller.bucketPhotos(u, 'before');
          },
          onCapture: () async {
            final job = await _controller.loadJob();
            final u = _controller.findUnitById(job, unitId);
            if (u == null) {
              throw StateError('Unit not found');
            }
            await _controller.capturePhoto(
              unit: u,
              phase: 'before',
              picker: _picker,
            );
          },
          onJobMutated: () async {
            await _reloadJobJson();
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
                    await _reloadJobJson();
                  },
                  reloadPhotos: () async {
                    final job = await _controller.loadJob();
                    final u = _controller.findUnitById(job, unitId);
                    return (u == null)
                        ? <Map<String, dynamic>>[]
                        : _controller.bucketPhotos(u, 'before');
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
    if (!mounted) return;
    await _reloadJobJson();
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
      await _reloadJobJson();
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
          loadPhotos: () async {
            final job = await _controller.loadJob();
            final u = _controller.findUnitById(job, unitId);
            return (u == null)
                ? <Map<String, dynamic>>[]
                : _controller.bucketPhotos(u, 'after');
          },
          onCapture: () async {
            final job = await _controller.loadJob();
            final u = _controller.findUnitById(job, unitId);
            if (u == null) {
              throw StateError('Unit not found');
            }
            await _controller.capturePhoto(
              unit: u,
              phase: 'after',
              picker: _picker,
            );
          },
          onJobMutated: () async {
            await _reloadJobJson();
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
                    await _reloadJobJson();
                  },
                  reloadPhotos: () async {
                    final job = await _controller.loadJob();
                    final u = _controller.findUnitById(job, unitId);
                    return (u == null)
                        ? <Map<String, dynamic>>[]
                        : _controller.bucketPhotos(u, 'after');
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
    if (!mounted) return;
    await _reloadJobJson();
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
      await _reloadJobJson();
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
      await _reloadJobJson();
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

  Map? _findUnitInState(String unitId) {
    final units = (_jobData['units'] as List?) ?? const [];
    for (final entry in units) {
      if (entry is! Map) {
        continue;
      }
      if ((entry['unitId'] ?? '').toString() == unitId) {
        return entry;
      }
    }
    return null;
  }

  bool _unitHasActivePhotos(Map unit) {
    final before = _countActivePhotos(unit['photosBefore']);
    final after = _countActivePhotos(unit['photosAfter']);
    return before > 0 || after > 0;
  }

  List<Map<String, dynamic>> _getWorkflowOrderedUnits(dynamic unitsRaw) {
    if (unitsRaw is! List) {
      return const <Map<String, dynamic>>[];
    }

    final units = <Map<String, dynamic>>[];
    for (final entry in unitsRaw) {
      if (entry is Map<String, dynamic>) {
        units.add(entry);
      } else if (entry is Map) {
        units.add(Map<String, dynamic>.from(entry));
      }
    }

    units.sort((a, b) {
      final typeCmp = _unitTypeRank(
        (a['type'] ?? '').toString(),
      ).compareTo(_unitTypeRank((b['type'] ?? '').toString()));
      if (typeCmp != 0) {
        return typeCmp;
      }

      final aName = _normalizeSortName((a['name'] ?? '').toString());
      final bName = _normalizeSortName((b['name'] ?? '').toString());
      final aNumberPart = _extractNumberPart(aName);
      final bNumberPart = _extractNumberPart(bName);
      final aNum = aNumberPart?.$1;
      final bNum = bNumberPart?.$1;
      final aSuffix = aNumberPart?.$2 ?? '';
      final bSuffix = bNumberPart?.$2 ?? '';

      if (aNum != null && bNum != null) {
        final numCmp = aNum.compareTo(bNum);
        if (numCmp != 0) {
          return numCmp;
        }
        final suffixCmp = aSuffix.compareTo(bSuffix);
        if (suffixCmp != 0) {
          return suffixCmp;
        }
      } else if (aNum != null) {
        return -1;
      } else if (bNum != null) {
        return 1;
      }

      final nameCmp = aName.compareTo(bName);
      if (nameCmp != 0) {
        return nameCmp;
      }

      final aId = (a['unitId'] ?? '').toString();
      final bId = (b['unitId'] ?? '').toString();
      return aId.compareTo(bId);
    });

    return units;
  }

  int _unitTypeRank(String type) {
    switch (type.trim().toLowerCase()) {
      case 'hood':
        return 0;
      case 'fan':
        return 1;
      default:
        return 2;
    }
  }

  String _normalizeSortName(String input) {
    final separated = input
        .replaceAllMapped(RegExp(r'([A-Za-z])(\d)'), (m) => '${m[1]} ${m[2]}')
        .replaceAllMapped(RegExp(r'(\d)([A-Za-z])'), (m) => '${m[1]} ${m[2]}');
    return separated
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  (int, String)? _extractNumberPart(String value) {
    final match = RegExp(r'(\d+)\s*([a-z]*)').firstMatch(value);
    if (match == null) {
      return null;
    }
    final number = int.tryParse(match.group(1)!);
    if (number == null) {
      return null;
    }
    final suffix = (match.group(2) ?? '').trim();
    return (number, suffix);
  }

  String _nextUnitNameSuggestion({
    required String unitType,
    required List units,
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

    for (final entry in units) {
      if (entry is! Map) {
        continue;
      }
      final existingType = (entry['type'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (existingType != normalizedType) {
        continue;
      }
      final existingName = (entry['name'] ?? '').toString().trim();
      final match = pattern.firstMatch(existingName);
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
            await _reloadJobJson();
          },
          softDelete: (relativePath) async {
            await _controller.softDeleteVideo(
              kind: 'exit',
              relativePath: relativePath,
            );
            await _reloadJobJson();
          },
          resolveVideoFile: (relativePath) async {
            final file = _controller.videoFileFromRelativePath(relativePath);
            return await file.exists() ? file : null;
          },
        ),
      ),
    );
    if (!mounted) return;
    await _reloadJobJson();
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
            await _reloadJobJson();
          },
          softDelete: (relativePath) async {
            await _controller.softDeleteVideo(
              kind: 'other',
              relativePath: relativePath,
            );
            await _reloadJobJson();
          },
          resolveVideoFile: (relativePath) async {
            final file = _controller.videoFileFromRelativePath(relativePath);
            return await file.exists() ? file : null;
          },
        ),
      ),
    );
    if (!mounted) return;
    await _reloadJobJson();
  }

  Future<void> _openToolsScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ToolsScreen(
          onPrecleanLayout: _openPreCleanLayoutScreen,
          onNotes: _openNotesScreen,
          onExitVideos: _openExitVideosScreen,
          onOtherVideos: _openOtherVideosScreen,
          preCleanLayoutCount: _controller.preCleanLayoutCount,
          exitVideosCount: _controller.videosExitCount,
          otherVideosCount: _controller.videosOtherCount,
        ),
      ),
    );
    if (!mounted) return;
    await _reloadJobJson();
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
          onJobMutated: _reloadJobJson,
        ),
      ),
    );
    if (!mounted) return;
    await _reloadJobJson();
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
          onMutated: _reloadJobJson,
        ),
      ),
    );
    if (!mounted) return;
    await _reloadJobJson();
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
    final units = (_jobData['units'] as List?) ?? const [];
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
                      if (unit is! Map) {
                        continue;
                      }
                      final existingType = (unit['type'] ?? '')
                          .toString()
                          .trim()
                          .toLowerCase();
                      if (existingType != selectedType.trim().toLowerCase()) {
                        continue;
                      }
                      final existingName = (unit['name'] ?? '').toString();
                      if (_normalizeUnitNameForValidation(existingName) ==
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
    final restaurantName = (_jobData['restaurantName'] ?? 'Unknown').toString();
    final shiftStartDate = (_jobData['shiftStartDate'] ?? '').toString();
    final units = _getWorkflowOrderedUnits(_jobData['units']);

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
            restaurantName: restaurantName,
            shiftStartDate: shiftStartDate,
          ),
          _ToolsCard(onTap: _openToolsScreen),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Units', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
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
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: units.length,
                    itemBuilder: (context, index) {
                      final unit = units[index];
                      final unitId = (unit['unitId'] ?? '').toString();
                      final name = (unit['name'] ?? '').toString();
                      final type = (unit['type'] ?? '').toString();
                      final isComplete = unit['isComplete'] == true;
                      final beforeCount = _countActivePhotos(
                        unit['photosBefore'],
                      );
                      final afterCount = _countActivePhotos(
                        unit['photosAfter'],
                      );

                      return Card(
                        key: ValueKey(unitId),
                        margin: const EdgeInsets.only(bottom: 16),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
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
                                        await _reloadJobJson();
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
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Chip(
                                    avatar: Icon(
                                      isComplete
                                          ? Icons.check_circle_outline
                                          : Icons.pending_outlined,
                                      size: 16,
                                    ),
                                    label: Text(
                                      isComplete ? 'Complete' : 'In Progress',
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: () => _setUnitCompletion(
                                      unitId: unitId,
                                      isComplete: !isComplete,
                                    ),
                                    icon: Icon(
                                      isComplete
                                          ? Icons.undo_outlined
                                          : Icons.check_outlined,
                                      size: 18,
                                    ),
                                    label: Text(
                                      isComplete
                                          ? 'Mark Incomplete'
                                          : 'Mark Complete',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton(
                                      onPressed:
                                          _isBusy || _isOpeningRapidBefore
                                          ? null
                                          : () async {
                                              final unitName =
                                                  (unit['name'] ?? '')
                                                      .toString();
                                              await _openRapidBeforeCapture(
                                                unitId: unitId,
                                                unitName: unitName,
                                              );
                                            },
                                      child: Text(
                                        _bucketLabel('Before', beforeCount),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  IconButton(
                                    onPressed: _isBusy
                                        ? null
                                        : () async {
                                            final unitName =
                                                (unit['name'] ?? '').toString();
                                            await _openBeforeGallery(
                                              unitId: unitId,
                                              unitName: unitName,
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
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _isBusy || _isOpeningRapidAfter
                                          ? null
                                          : () async {
                                              final unitName =
                                                  (unit['name'] ?? '')
                                                      .toString();
                                              await _openRapidAfterCapture(
                                                unitId: unitId,
                                                unitName: unitName,
                                              );
                                            },
                                      child: Text(
                                        _bucketLabel('After', afterCount),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  IconButton(
                                    onPressed: _isBusy
                                        ? null
                                        : () async {
                                            final unitName =
                                                (unit['name'] ?? '').toString();
                                            await _openAfterGallery(
                                              unitId: unitId,
                                              unitName: unitName,
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
    required this.shiftStartDate,
  });

  final String restaurantName;
  final String shiftStartDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            restaurantName,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            shiftStartDate,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                        'Pre-clean layout, notes, and videos',
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
