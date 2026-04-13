import 'dart:io';
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../application/jobs_service.dart';
import '../domain/models/job.dart';
import '../domain/models/photo_record.dart';
import '../domain/models/unit.dart';
import '../domain/models/unit_phase_config.dart';
import '../providers/job_detail_provider.dart';
import '../providers/job_list_provider.dart';
import '../services/pdf_export_preset.dart';
import '../utils/unit_sorter.dart';
import 'controllers/job_detail_controller.dart';
import 'screens/manager_notes_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/pre_clean_layout_screen.dart';
import 'screens/photo_viewer_screen.dart';
import 'screens/rapid_photo_capture_screen.dart';
import 'screens/unit_photo_bucket_screen.dart';
import 'screens/video_capture_screen.dart';
import 'screens/videos_screen.dart';
import '../storage/job_scanner.dart';

class JobDetail extends ConsumerStatefulWidget {
  const JobDetail({super.key, required this.jobs, required this.job});

  final JobsService jobs;
  final JobScanResult job;

  @override
  ConsumerState<JobDetail> createState() => _JobDetailState();
}

class _JobDetailState extends ConsumerState<JobDetail> {
  bool _isExportingZip = false;
  bool _isExportingPdf = false;
  late final JobDetailController _controller;
  bool _isBusy = false;

  String get _jobDirPath => widget.job.jobDir.path;

  Job get _job {
    final asyncJob = ref.read(jobDetailProvider(_jobDirPath));
    return asyncJob.valueOrNull ?? widget.job.job;
  }

  @override
  void initState() {
    super.initState();
    _controller = JobDetailController(
      jobs: widget.jobs,
      jobDir: widget.job.jobDir,
    );
    _controller.loadJob();
  }

  Future<void> _addUnitFlow() async {
    _reloadJob();
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
      _reloadJob();
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
    await _controller.loadJob();
    ref.invalidate(jobDetailProvider(_jobDirPath));
  }

  Future<int> _loadUnitVisiblePhotoCount({
    required String unitId,
    required String phase,
    String? subPhase,
  }) async {
    final job = await _controller.loadJob();
    try {
      final unit = job.units.firstWhere((u) => u.unitId == unitId);
      return unit.visibleCount(phase: phase, subPhase: subPhase);
    } on StateError {
      return 0;
    }
  }

  Future<List<PhotoRecord>> _loadUnitPhotos({
    required String unitId,
    required String phase,
    String? subPhase,
  }) async {
    final job = await _controller.loadJob();
    try {
      final unit = job.units.firstWhere((u) => u.unitId == unitId);
      final photos = phase == 'before' ? unit.photosBefore : unit.photosAfter;
      if (subPhase == null) {
        return photos.where((p) => p.isActive).toList(growable: false);
      }
      final isDefault =
          UnitPhaseConfig.defaultSubPhaseKey(unit.type, phase) == subPhase;
      return photos
          .where(
            (p) =>
                p.isActive &&
                (p.subPhase == subPhase || (isDefault && p.subPhase == null)),
          )
          .toList(growable: false);
    } on StateError {
      return const <PhotoRecord>[];
    }
  }

  bool _isOpeningRapidCapture = false;

  Future<void> _openRapidCapture({
    required String unitId,
    required String unitName,
    required String phase,
    required String phaseLabel,
    String? subPhase,
    String? subPhaseLabel,
  }) async {
    if (_isOpeningRapidCapture) return;
    setState(() => _isOpeningRapidCapture = true);
    try {
      final displayLabel = subPhaseLabel != null
          ? '$phaseLabel — $subPhaseLabel'
          : phaseLabel;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RapidPhotoCaptureScreen(
            unitName: unitName.isEmpty ? 'Unnamed unit' : unitName,
            phaseLabel: displayLabel,
            loadVisibleCount: () => _loadUnitVisiblePhotoCount(
              unitId: unitId,
              phase: phase,
              subPhase: subPhase,
            ),
            onCaptureFile: (file) => _controller.capturePhotoFromFile(
              unitId: unitId,
              phase: phase,
              sourceImageFile: file,
              subPhase: subPhase,
            ),
          ),
        ),
      );
      if (!mounted) return;
      _reloadJob();
    } finally {
      if (mounted) {
        setState(() => _isOpeningRapidCapture = false);
      } else {
        _isOpeningRapidCapture = false;
      }
    }
  }

  Future<void> _openPhaseGallery({
    required String unitId,
    required String unitName,
    required String phase,
    required String phaseLabel,
    String? subPhase,
    String? subPhaseLabel,
  }) async {
    final initialPhotos = await _loadUnitPhotos(
      unitId: unitId,
      phase: phase,
      subPhase: subPhase,
    );
    if (!mounted) return;
    _precacheGalleryThumbnails(initialPhotos);

    final galleryTitle = subPhaseLabel != null
        ? '$unitName — $phaseLabel $subPhaseLabel'
        : '$unitName — $phaseLabel';
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UnitPhotoBucketScreen(
          title: galleryTitle,
          jobDir: widget.job.jobDir,
          initialPhotos: initialPhotos,
          loadPhotos: () =>
              _loadUnitPhotos(unitId: unitId, phase: phase, subPhase: subPhase),
          onCapture: () async {
            await _openRapidCapture(
              unitId: unitId,
              unitName: unitName,
              phase: phase,
              phaseLabel: phaseLabel,
              subPhase: subPhase,
              subPhaseLabel: subPhaseLabel,
            );
          },
          onJobMutated: () async {
            _reloadJob();
          },
          onSoftDelete: (relativePath) async {
            await _controller.softDeletePhoto(
              unitId: unitId,
              phase: phase,
              relativePath: relativePath,
            );
          },
          onOpenViewer: (initialIndex, photos) async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PhotoViewerScreen(
                  jobDir: widget.job.jobDir,
                  title: galleryTitle,
                  photos: photos,
                  initialIndex: initialIndex,
                  onSoftDelete: (relativePath) => _controller.softDeletePhoto(
                    unitId: unitId,
                    phase: phase,
                    relativePath: relativePath,
                  ),
                  onJobMutated: () async {
                    _reloadJob();
                  },
                  reloadPhotos: () => _loadUnitPhotos(
                    unitId: unitId,
                    phase: phase,
                    subPhase: subPhase,
                  ),
                ),
              ),
            );
          },
          allUnits: _job.units,
          currentUnitId: unitId,
          currentPhase: phase,
          currentSubPhase: subPhase,
          onMovePhotos:
              ({
                required List<String> photoIds,
                required String destUnitId,
                required String? destSubPhase,
              }) async {
                await _controller.movePhotos(
                  sourceUnitId: unitId,
                  sourcePhase: phase,
                  photoIds: photoIds,
                  destUnitId: destUnitId,
                  destSubPhase: destSubPhase,
                );
              },
          onBrokenCloudUrl: (photoId) => widget.jobs.requeueBrokenPhoto(
            jobDir: widget.job.jobDir,
            photoId: photoId,
          ),
        ),
      ),
    );
    if (!mounted) return;
    _reloadJob();
  }

  void _precacheGalleryThumbnails(List<PhotoRecord> photos) {
    final urls = photos
        .map((p) => p.cloudUrl?.trim() ?? '')
        .where((u) => u.isNotEmpty)
        .toSet()
        .take(18);
    for (final url in urls) {
      unawaited(
        precacheImage(CachedNetworkImageProvider(url), context).catchError((_) {
          // Best-effort prefetch only.
        }),
      );
    }
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
      _reloadJob();
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
      _reloadJob();
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
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => VideoCaptureScreen(
                  title: 'Exit Video',
                  loadVideoCount: () async {
                    final videos = await _controller.loadVideos(kind: 'exit');
                    return videos.length;
                  },
                  onCaptureFile: (file) async {
                    await _controller.captureVideoFromFile(
                      kind: 'exit',
                      sourceVideoFile: file,
                    );
                  },
                ),
              ),
            );
            _reloadJob();
          },
          softDelete: (relativePath) async {
            await _controller.softDeleteVideo(
              kind: 'exit',
              relativePath: relativePath,
            );
            _reloadJob();
          },
          retryUpload: (videoId) async {
            await _controller.retryVideoUpload(videoId: videoId);
            _reloadJob();
          },
          resolveVideoFile: (relativePath) async {
            final file = _controller.videoFileFromRelativePath(relativePath);
            return await file.exists() ? file : null;
          },
        ),
      ),
    );
    if (!mounted) return;
    _reloadJob();
  }

  Future<void> _openOtherVideosScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideosScreen(
          title: 'Other Videos',
          kind: 'other',
          loadVideos: () => _controller.loadVideos(kind: 'other'),
          captureVideo: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => VideoCaptureScreen(
                  title: 'Other Video',
                  loadVideoCount: () async {
                    final videos = await _controller.loadVideos(kind: 'other');
                    return videos.length;
                  },
                  onCaptureFile: (file) async {
                    await _controller.captureVideoFromFile(
                      kind: 'other',
                      sourceVideoFile: file,
                    );
                  },
                ),
              ),
            );
            _reloadJob();
          },
          softDelete: (relativePath) async {
            await _controller.softDeleteVideo(
              kind: 'other',
              relativePath: relativePath,
            );
            _reloadJob();
          },
          retryUpload: (videoId) async {
            await _controller.retryVideoUpload(videoId: videoId);
            _reloadJob();
          },
          resolveVideoFile: (relativePath) async {
            final file = _controller.videoFileFromRelativePath(relativePath);
            return await file.exists() ? file : null;
          },
        ),
      ),
    );
    if (!mounted) return;
    _reloadJob();
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
          onBrokenCloudUrl: (photoId) => widget.jobs.requeueBrokenPhoto(
            jobDir: widget.job.jobDir,
            photoId: photoId,
          ),
        ),
      ),
    );
    if (!mounted) return;
    _reloadJob();
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
          editNote: (noteId, newText) => _controller.editNote(noteId, newText),
          softDeleteNote: (noteId) => _controller.softDeleteNote(noteId),
          onMutated: _reloadJob,
        ),
      ),
    );
    if (!mounted) return;
    _reloadJob();
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
          softDeleteNote: (noteId) => _controller.softDeleteManagerNote(noteId),
          onMutated: _reloadJob,
        ),
      ),
    );
    if (!mounted) return;
    _reloadJob();
  }

  Future<void> _toggleJobCompletion() async {
    try {
      if (_job.isComplete) {
        await _controller.reopenJob();
      } else {
        await _controller.markJobComplete();
      }
      _reloadJob();
      ref.invalidate(jobListProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _exportZip() async {
    await _exportAndShare(
      label: 'ZIP',
      dialogText: 'Creating ZIP...',
      export: () => _controller.exportJob(),
      isExporting: () => _isExportingZip,
      setExporting: (v) => _isExportingZip = v,
    );
  }

  Future<void> _exportPdf() async {
    final preset = await _pickPdfPreset();
    if (preset == null) return;
    await _exportAndSharePdf(preset);
  }

  Future<PdfExportPreset?> _pickPdfPreset() async {
    return showModalBottomSheet<PdfExportPreset>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('Standard PDF'),
                subtitle: Text(PdfExportPreset.original.label),
                onTap: () => Navigator.of(ctx).pop(PdfExportPreset.original),
              ),
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: const Text('Email-friendly PDF (fast)'),
                subtitle: Text(PdfExportPreset.emailFast.label),
                onTap: () => Navigator.of(ctx).pop(PdfExportPreset.emailFast),
              ),
              ListTile(
                leading: const Icon(Icons.mark_email_read_outlined),
                title: const Text('Email-friendly PDF'),
                subtitle: Text(PdfExportPreset.emailFriendly5mb.label),
                onTap: () =>
                    Navigator.of(ctx).pop(PdfExportPreset.emailFriendly5mb),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _exportAndSharePdf(PdfExportPreset preset) async {
    if (_isExportingPdf) return;
    setState(() => _isExportingPdf = true);

    final box = context.findRenderObject() as RenderBox?;
    final shareOrigin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : null;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(switch (preset) {
                  PdfExportPreset.original => 'Creating PDF...',
                  PdfExportPreset.emailFast =>
                    'Creating email-friendly PDF (fast)...',
                  PdfExportPreset.emailFriendly5mb =>
                    'Creating email-friendly PDF (5 MB target)...',
                }),
              ),
            ],
          ),
        ),
      ),
    );

    var dialogClosed = false;
    try {
      final result = await _controller.exportPdf(preset: preset);
      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).pop();
      dialogClosed = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.microtask(() async {
          try {
            await Share.shareXFiles(
              [XFile(result.file.path)],
              text: 'KitchenGuard job export',
              sharePositionOrigin: shareOrigin,
            );
            if (!mounted) return;
            if (preset.enforceStrictTarget && !result.targetMet) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Could not reach 5 MB without excessive quality loss. Shared smallest possible PDF.',
                  ),
                ),
              );
            }
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
          content: Text(message.isEmpty ? 'PDF export failed' : message),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isExportingPdf = false);
      } else {
        _isExportingPdf = false;
      }
    }
  }

  Future<void> _exportAndShare({
    required String label,
    required String dialogText,
    required Future<File> Function() export,
    required bool Function() isExporting,
    required void Function(bool) setExporting,
  }) async {
    if (isExporting()) return;
    setState(() => setExporting(true));

    final box = context.findRenderObject() as RenderBox?;
    final shareOrigin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : null;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(dialogText)),
            ],
          ),
        ),
      ),
    );

    var dialogClosed = false;

    try {
      final file = await export();
      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).pop();
      dialogClosed = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.microtask(() async {
          try {
            await Share.shareXFiles(
              [XFile(file.path)],
              text: 'KitchenGuard job export',
              sharePositionOrigin: shareOrigin,
            );
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
          content: Text(message.isEmpty ? '$label export failed' : message),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => setExporting(false));
      } else {
        setExporting(false);
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
    final jobAsync = ref.watch(jobDetailProvider(_jobDirPath));
    final job = jobAsync.valueOrNull ?? widget.job.job;
    final units = UnitSorter.sort(job.units);
    final listBottomPadding = 120.0 + MediaQuery.of(context).padding.bottom;

    final managerNoteCount = job.managerNotes.where((n) => n.isActive).length;
    final fieldNoteCount = job.notes.where((n) => n.status == 'active').length;
    final preCleanCount = job.preCleanLayoutPhotos
        .where((p) => p.isActive)
        .length;
    final exitVideoCount = job.videos.exit.where((v) => v.isActive).length;
    final otherVideoCount = job.videos.other.where((v) => v.isActive).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text(''),
        actions: [
          IconButton(
            onPressed: (_isExportingZip || _isExportingPdf) ? null : _exportZip,
            icon: const Icon(Icons.folder_zip_outlined),
            tooltip: 'Export ZIP',
          ),
          IconButton(
            onPressed: (_isExportingZip || _isExportingPdf) ? null : _exportPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export PDF',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.handyman_outlined),
            tooltip: 'Tools',
            onSelected: (value) async {
              if (value == 'field_notes') {
                await _openNotesScreen();
              } else if (value == 'other_videos') {
                await _openOtherVideosScreen();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'field_notes',
                child: Row(
                  children: [
                    const Icon(Icons.note_outlined, size: 20),
                    const SizedBox(width: 8),
                    Text('Field Notes ($fieldNoteCount)'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'other_videos',
                child: Row(
                  children: [
                    const Icon(Icons.videocam_outlined, size: 20),
                    const SizedBox(width: 8),
                    Text('Other Videos ($otherVideoCount)'),
                  ],
                ),
              ),
            ],
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'complete') {
                await _toggleJobCompletion();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'complete',
                child: Text(job.isComplete ? 'Reopen Job' : 'Mark Complete'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _JobHeader(
            restaurantName: job.restaurantName,
            address: job.address,
            city: job.city,
            accessType: job.accessType,
            accessNotes: job.accessNotes,
            hasAlarm: job.hasAlarm == true,
            alarmCode: job.alarmCode,
            hoodCount:
                job.hoodCount ??
                job.units.where((u) => u.type == 'hood').length,
            fanCount:
                job.fanCount ?? job.units.where((u) => u.type == 'fan').length,
            isComplete: job.isComplete,
            jobNoteCount: managerNoteCount,
            fieldNoteCount: fieldNoteCount,
            onJobNotesTap: _openManagerNotesScreen,
            onFieldNotesTap: _openNotesScreen,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openPreCleanLayoutScreen,
                    icon: const Icon(Icons.grid_view_outlined, size: 18),
                    label: Text('Pre-clean Layout ($preCleanCount)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openExitVideosScreen,
                    icon: const Icon(Icons.videocam_outlined, size: 18),
                    label: Text('Exit Video ($exitVideoCount)'),
                  ),
                ),
              ],
            ),
          ),
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
                      final hasSubPhases = UnitPhaseConfig.hasSubPhases(type);

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
                                        _reloadJob();
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
                              if (hasSubPhases)
                                _SubPhaseUnitBody(
                                  unit: unit,
                                  isBusy: _isBusy || _isOpeningRapidCapture,
                                  onCapture:
                                      ({
                                        required String phase,
                                        required String phaseLabel,
                                        String? subPhase,
                                        String? subPhaseLabel,
                                      }) => _openRapidCapture(
                                        unitId: unitId,
                                        unitName: name,
                                        phase: phase,
                                        phaseLabel: phaseLabel,
                                        subPhase: subPhase,
                                        subPhaseLabel: subPhaseLabel,
                                      ),
                                  onGallery:
                                      ({
                                        required String phase,
                                        required String phaseLabel,
                                        String? subPhase,
                                        String? subPhaseLabel,
                                      }) => _openPhaseGallery(
                                        unitId: unitId,
                                        unitName: name,
                                        phase: phase,
                                        phaseLabel: phaseLabel,
                                        subPhase: subPhase,
                                        subPhaseLabel: subPhaseLabel,
                                      ),
                                )
                              else
                                _SimpleUnitBody(
                                  unit: unit,
                                  isBusy: _isBusy || _isOpeningRapidCapture,
                                  onCapture: ({required String phase}) =>
                                      _openRapidCapture(
                                        unitId: unitId,
                                        unitName: name,
                                        phase: phase,
                                        phaseLabel: phase == 'before'
                                            ? 'Before'
                                            : 'After',
                                      ),
                                  onGallery: ({required String phase}) =>
                                      _openPhaseGallery(
                                        unitId: unitId,
                                        unitName: name,
                                        phase: phase,
                                        phaseLabel: phase == 'before'
                                            ? 'Before'
                                            : 'After',
                                      ),
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
    this.address,
    this.city,
    this.accessType,
    this.accessNotes,
    this.hasAlarm = false,
    this.alarmCode,
    this.hoodCount = 0,
    this.fanCount = 0,
    required this.isComplete,
    required this.jobNoteCount,
    required this.fieldNoteCount,
    required this.onJobNotesTap,
    required this.onFieldNotesTap,
  });

  final String restaurantName;
  final String? address;
  final String? city;
  final String? accessType;
  final String? accessNotes;
  final bool hasAlarm;
  final String? alarmCode;
  final int hoodCount;
  final int fanCount;
  final bool isComplete;
  final int jobNoteCount;
  final int fieldNoteCount;
  final VoidCallback onJobNotesTap;
  final VoidCallback onFieldNotesTap;

  static const _accessTypeLabels = <String, String>{
    'no-key': 'No key — meet after closing',
    'get-key-from-shop': 'Get key from shop',
    'key-hidden': 'Key hidden',
    'lockbox': 'Lockbox',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final unitParts = <String>[];
    if (hoodCount > 0) {
      unitParts.add('$hoodCount ${hoodCount == 1 ? "hood" : "hoods"}');
    }
    if (fanCount > 0) {
      unitParts.add('$fanCount ${fanCount == 1 ? "fan" : "fans"}');
    }
    final unitSummary = unitParts.join(', ');

    final accessLabel = accessType != null
        ? _accessTypeLabels[accessType] ?? accessType!
        : null;
    final accessDetailParts = <String>[];
    if (accessLabel != null) {
      final withNotes = (accessNotes != null && accessNotes!.isNotEmpty)
          ? '$accessLabel, $accessNotes'
          : accessLabel;
      accessDetailParts.add(withNotes);
    }
    if (hasAlarm) {
      final alarmText = (alarmCode != null && alarmCode!.isNotEmpty)
          ? 'Alarm, $alarmCode'
          : 'Alarm';
      accessDetailParts.add(alarmText);
    }
    final accessDetail = accessDetailParts.join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  restaurantName,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (isComplete) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Complete',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
                if (address != null && address!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    city != null && city!.isNotEmpty
                        ? '$address, $city'
                        : address!,
                    style: theme.textTheme.bodySmall?.copyWith(
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
                            Icon(
                              Icons.grid_view_outlined,
                              size: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              unitSummary,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      if (accessDetail.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.key_outlined,
                              size: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                accessDetail,
                                style: theme.textTheme.bodySmall?.copyWith(
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
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: onJobNotesTap,
                borderRadius: BorderRadius.circular(8),
                child: Chip(
                  label: Text(
                    '$jobNoteCount job ${jobNoteCount == 1 ? "note" : "notes"}',
                  ),
                  labelStyle: theme.textTheme.labelSmall,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  side: BorderSide.none,
                ),
              ),
              InkWell(
                onTap: onFieldNotesTap,
                borderRadius: BorderRadius.circular(8),
                child: Chip(
                  label: Text(
                    '$fieldNoteCount field ${fieldNoteCount == 1 ? "note" : "notes"}',
                  ),
                  labelStyle: theme.textTheme.labelSmall,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  side: BorderSide.none,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SubPhaseUnitBody extends StatelessWidget {
  const _SubPhaseUnitBody({
    required this.unit,
    required this.isBusy,
    required this.onCapture,
    required this.onGallery,
  });

  final Unit unit;
  final bool isBusy;
  final void Function({
    required String phase,
    required String phaseLabel,
    String? subPhase,
    String? subPhaseLabel,
  })
  onCapture;
  final void Function({
    required String phase,
    required String phaseLabel,
    String? subPhase,
    String? subPhaseLabel,
  })
  onGallery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final beforeSubs = UnitPhaseConfig.beforeOrder(unit.type);
    final afterSubs = UnitPhaseConfig.afterOrder(unit.type);
    final rows = beforeSubs.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'BEFORE',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Text(
                'AFTER',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < rows; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _SubPhaseRow(
                  label: beforeSubs[i].label,
                  count: unit.visibleCount(
                    phase: 'before',
                    subPhase: beforeSubs[i].key,
                  ),
                  isBusy: isBusy,
                  onTap: () => onCapture(
                    phase: 'before',
                    phaseLabel: 'Before',
                    subPhase: beforeSubs[i].key,
                    subPhaseLabel: beforeSubs[i].label,
                  ),
                  onGallery: () => onGallery(
                    phase: 'before',
                    phaseLabel: 'Before',
                    subPhase: beforeSubs[i].key,
                    subPhaseLabel: beforeSubs[i].label,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SubPhaseRow(
                  label: afterSubs[i].label,
                  count: unit.visibleCount(
                    phase: 'after',
                    subPhase: afterSubs[i].key,
                  ),
                  isBusy: isBusy,
                  onTap: () => onCapture(
                    phase: 'after',
                    phaseLabel: 'After',
                    subPhase: afterSubs[i].key,
                    subPhaseLabel: afterSubs[i].label,
                  ),
                  onGallery: () => onGallery(
                    phase: 'after',
                    phaseLabel: 'After',
                    subPhase: afterSubs[i].key,
                    subPhaseLabel: afterSubs[i].label,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SubPhaseRow extends StatelessWidget {
  const _SubPhaseRow({
    required this.label,
    required this.count,
    required this.isBusy,
    required this.onTap,
    required this.onGallery,
  });

  final String label;
  final int count;
  final bool isBusy;
  final VoidCallback onTap;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            onPressed: isBusy ? null : onTap,
            icon: Icon(
              Icons.camera_alt,
              size: 40,
              color: isBusy
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.primary,
            ),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            tooltip: '$label capture',
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: InkWell(
            onTap: isBusy ? null : onGallery,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '$label ($count)',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isBusy
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SimpleUnitBody extends StatelessWidget {
  const _SimpleUnitBody({
    required this.unit,
    required this.isBusy,
    required this.onCapture,
    required this.onGallery,
  });

  final Unit unit;
  final bool isBusy;
  final void Function({required String phase}) onCapture;
  final void Function({required String phase}) onGallery;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              onPressed: isBusy ? null : () => onCapture(phase: 'before'),
              tooltip: 'Capture Before Photos',
              icon: const Icon(Icons.camera_alt, size: 40),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 2),
            Expanded(
              child: FilledButton(
                onPressed: isBusy ? null : () => onGallery(phase: 'before'),
                child: Text('Before (${unit.visibleBeforeCount})'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              onPressed: isBusy ? null : () => onCapture(phase: 'after'),
              tooltip: 'Capture After Photos',
              icon: const Icon(Icons.camera_alt, size: 40),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 2),
            Expanded(
              child: OutlinedButton(
                onPressed: isBusy ? null : () => onGallery(phase: 'after'),
                child: Text('After (${unit.visibleAfterCount})'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
