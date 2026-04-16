import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:web/web.dart' as web;

import '../../domain/models/job.dart';
import '../../domain/models/job_note.dart';
import '../../domain/models/manager_job_note.dart';
import '../../domain/models/photo_record.dart';
import '../../domain/models/unit.dart';
import '../../domain/models/video_record.dart';
import '../../presentation/widgets/job_dialog.dart' show accessTypeLabels;
import '../web_export_service.dart';
import '../web_job_repository.dart';
import '../web_pdf_export_service.dart';
import '../web_providers.dart';
import '../widgets/web_notes_dialog.dart';
import '../../services/pdf_export_preset.dart';

/// Real-time single-job stream provider, keyed by jobId.
final _webJobDetailProvider = StreamProvider.family<Job?, String>((ref, jobId) {
  return ref.watch(webJobRepositoryProvider).watchJob(jobId);
});

/// Job detail screen for the web dashboard.
///
/// Displays job metadata, units with their photos (from Firebase Storage URLs),
/// pre-clean layout photos, notes, and videos.
class WebJobDetailScreen extends ConsumerWidget {
  const WebJobDetailScreen({
    super.key,
    required this.jobId,
    required this.onBack,
  });

  final String jobId;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobAsync = ref.watch(_webJobDetailProvider(jobId));
    final theme = Theme.of(context);

    return jobAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (job) {
        if (job == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Job not found.'),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
              ],
            ),
          );
        }

        return _JobDetailBody(
          job: job,
          onBack: onBack,
          theme: theme,
          webJobRepo: ref.read(webJobRepositoryProvider),
          onToggleCompletion: () async {
            await ref.read(webJobRepositoryProvider).updateFields(job.jobId, {
              'completedAt': job.isComplete
                  ? FieldValue.delete()
                  : DateTime.now().toUtc().toIso8601String(),
            });
          },
        );
      },
    );
  }
}

class _JobDetailBody extends StatefulWidget {
  const _JobDetailBody({
    required this.job,
    required this.onBack,
    required this.theme,
    required this.webJobRepo,
    required this.onToggleCompletion,
  });

  final Job job;
  final VoidCallback onBack;
  final ThemeData theme;
  final WebJobRepository webJobRepo;
  final VoidCallback onToggleCompletion;

  @override
  State<_JobDetailBody> createState() => _JobDetailBodyState();
}

class _JobDetailBodyState extends State<_JobDetailBody> {
  WebExportProgress? _zipProgress;
  bool _isExportingZip = false;

  WebExportProgress? _pdfProgress;
  bool _isExportingPdf = false;
  PdfExportPreset _selectedPdfPreset = PdfExportPreset.emailFast;

  Job get job => widget.job;
  ThemeData get theme => widget.theme;

  Future<void> _retryVideoUpload(String videoId) async {
    final exitList = job.videos.exit.map((v) {
      if (v.videoId != videoId) return v;
      return VideoRecord(
        videoId: v.videoId,
        fileName: v.fileName,
        relativePath: v.relativePath,
        capturedAt: v.capturedAt,
        status: v.status,
        deletedAt: v.deletedAt,
        syncStatus: 'pending',
        sourcePath: v.sourcePath,
        thumbnailPath: v.thumbnailPath,
        thumbnailCloudUrl: v.thumbnailCloudUrl,
      );
    }).toList();
    final otherList = job.videos.other.map((v) {
      if (v.videoId != videoId) return v;
      return VideoRecord(
        videoId: v.videoId,
        fileName: v.fileName,
        relativePath: v.relativePath,
        capturedAt: v.capturedAt,
        status: v.status,
        deletedAt: v.deletedAt,
        syncStatus: 'pending',
        sourcePath: v.sourcePath,
        thumbnailPath: v.thumbnailPath,
        thumbnailCloudUrl: v.thumbnailCloudUrl,
      );
    }).toList();
    final updatedVideos = job.videos.copyWith(exit: exitList, other: otherList);
    await widget.webJobRepo.updateFields(job.jobId, {
      'videos': updatedVideos.toJson(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Retry requested — the phone will re-upload this video.',
          ),
        ),
      );
    }
  }

  Future<void> _startZipExport() async {
    if (_isExportingZip) return;
    setState(() => _isExportingZip = true);

    try {
      final result = await WebExportService.exportJobZip(
        job: job,
        onProgress: (p) {
          if (mounted) setState(() => _zipProgress = p);
        },
      );

      if (!mounted) return;
      final msg = result.skipped > 0
          ? 'ZIP downloaded (${result.skipped} item${result.skipped == 1 ? '' : 's'} skipped — not yet uploaded)'
          : 'ZIP downloaded';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ZIP export failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExportingZip = false;
          _zipProgress = null;
        });
      }
    }
  }

  Future<void> _startPdfExport({required PdfExportPreset preset}) async {
    if (_isExportingPdf) return;
    setState(() => _isExportingPdf = true);

    try {
      final result = await WebPdfExportService.exportJobPdf(
        job: job,
        preset: preset,
        onProgress: (p) {
          if (mounted) setState(() => _pdfProgress = p);
        },
      );

      if (!mounted) return;
      final msg = result.skipped > 0
          ? 'PDF downloaded (${result.skipped} photo${result.skipped == 1 ? '' : 's'} skipped — not yet uploaded)'
          : 'PDF downloaded';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
      );
      if (result.note != null && result.note!.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.note!)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('PDF export failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExportingPdf = false;
          _pdfProgress = null;
        });
      }
    }
  }

  Widget _buildPdfExportControl() {
    if (_isExportingPdf) {
      return _buildExportButton(
        isExporting: true,
        progress: _pdfProgress,
        label: 'Download PDF',
        icon: Icons.picture_as_pdf,
        onPressed: () {},
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.tonalIcon(
          onPressed: () => _startPdfExport(preset: _selectedPdfPreset),
          icon: const Icon(Icons.picture_as_pdf, size: 18),
          label: Text('Download PDF (${_selectedPdfPreset.shortLabel})'),
        ),
        const SizedBox(width: 4),
        PopupMenuButton<PdfExportPreset>(
          tooltip: 'PDF options',
          onSelected: (preset) => setState(() => _selectedPdfPreset = preset),
          itemBuilder: (context) => PdfExportPreset.values
              .map(
                (preset) => PopupMenuItem<PdfExportPreset>(
                  value: preset,
                  child: Text(preset.shortLabel),
                ),
              )
              .toList(growable: false),
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.arrow_drop_down),
          ),
        ),
      ],
    );
  }

  Widget _buildExportButton({
    required bool isExporting,
    required WebExportProgress? progress,
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    if (isExporting) {
      return SizedBox(
        width: 160,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: progress?.fraction),
            const SizedBox(height: 4),
            Text(
              progress?.currentFile ?? 'Preparing…',
              style: theme.textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  void _openManagerNotes() {
    final activeNotes = job.managerNotes.where((n) => n.isActive).toList();
    showDialog(
      context: context,
      builder: (_) => WebNotesDialog(
        title: 'Job Notes',
        initialNotes: activeNotes
            .map((n) => WebNoteItem(n.noteId, n.text))
            .toList(),
        onAdd: (text) async {
          final latest = await widget.webJobRepo.loadJob(job.jobId);
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
          await widget.webJobRepo.updateFields(job.jobId, {
            'managerNotes': updated.map((n) => n.toJson()).toList(),
          });
        },
        onEdit: (noteId, newText) async {
          final latest = await widget.webJobRepo.loadJob(job.jobId);
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
          await widget.webJobRepo.updateFields(job.jobId, {
            'managerNotes': updated.map((n) => n.toJson()).toList(),
          });
        },
        onDelete: (noteId) async {
          final latest = await widget.webJobRepo.loadJob(job.jobId);
          if (latest == null) return;
          final updated = latest.managerNotes.map((n) {
            if (n.noteId == noteId) return n.copyWith(status: 'deleted');
            return n;
          }).toList();
          await widget.webJobRepo.updateFields(job.jobId, {
            'managerNotes': updated.map((n) => n.toJson()).toList(),
          });
        },
        onRefresh: () async {
          final latest = await widget.webJobRepo.loadJob(job.jobId);
          if (latest == null) return [];
          return latest.managerNotes
              .where((n) => n.isActive)
              .map((n) => WebNoteItem(n.noteId, n.text))
              .toList();
        },
      ),
    );
  }

  void _openFieldNotes() {
    final activeNotes = job.notes.where((n) => n.isActive).toList();
    showDialog(
      context: context,
      builder: (_) => WebNotesDialog(
        title: 'Field Notes',
        initialNotes: activeNotes
            .map((n) => WebNoteItem(n.noteId, n.text))
            .toList(),
        onAdd: (text) async {
          final latest = await widget.webJobRepo.loadJob(job.jobId);
          if (latest == null) return;
          final updated = [
            ...latest.notes,
            JobNote(
              noteId: const Uuid().v4(),
              text: text,
              createdAt: DateTime.now().toUtc().toIso8601String(),
              status: 'active',
            ),
          ];
          await widget.webJobRepo.updateFields(job.jobId, {
            'notes': updated.map((n) => n.toJson()).toList(),
          });
        },
        onEdit: (noteId, newText) async {
          final latest = await widget.webJobRepo.loadJob(job.jobId);
          if (latest == null) return;
          final updated = latest.notes.map((n) {
            if (n.noteId == noteId) {
              return n.copyWith(
                text: newText,
                updatedAt: DateTime.now().toUtc().toIso8601String(),
              );
            }
            return n;
          }).toList();
          await widget.webJobRepo.updateFields(job.jobId, {
            'notes': updated.map((n) => n.toJson()).toList(),
          });
        },
        onDelete: (noteId) async {
          final latest = await widget.webJobRepo.loadJob(job.jobId);
          if (latest == null) return;
          final updated = latest.notes.map((n) {
            if (n.noteId == noteId) return n.copyWith(status: 'deleted');
            return n;
          }).toList();
          await widget.webJobRepo.updateFields(job.jobId, {
            'notes': updated.map((n) => n.toJson()).toList(),
          });
        },
        onRefresh: () async {
          final latest = await widget.webJobRepo.loadJob(job.jobId);
          if (latest == null) return [];
          return latest.notes
              .where((n) => n.isActive)
              .map((n) => WebNoteItem(n.noteId, n.text))
              .toList();
        },
      ),
    );
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onPressed) {
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onPressed: onPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    final activeNotes = job.notes.where((n) => n.isActive).toList();
    final activeManagerNotes = job.managerNotes
        .where((n) => n.isActive)
        .toList();
    final exitVideos = job.videos.exit.where((v) => v.isActive).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            job.restaurantName,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (job.isComplete) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.check_circle, size: 22, color: cs.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Complete',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (job.address != null || job.city != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          job.address,
                          job.city,
                        ].where((s) => s != null && s.isNotEmpty).join(', '),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: widget.onToggleCompletion,
                icon: Icon(
                  job.isComplete ? Icons.replay : Icons.check_circle_outline,
                  size: 18,
                ),
                label: Text(job.isComplete ? 'Reopen' : 'Mark Complete'),
              ),
              const SizedBox(width: 8),
              _buildPdfExportControl(),
              const SizedBox(width: 8),
              _buildExportButton(
                isExporting: _isExportingZip,
                progress: _zipProgress,
                label: 'Download ZIP',
                icon: Icons.download,
                onPressed: _startZipExport,
              ),
            ],
          ),
        ),
        // Info chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (job.accessType != null)
                _chip(
                  Icons.vpn_key,
                  accessTypeLabels[job.accessType] ??
                      job.accessType!.replaceAll(RegExp(r'[-_]'), ' '),
                ),
              if (job.hasAlarm == true)
                _chip(
                  Icons.alarm,
                  'Alarm${job.alarmCode != null ? ': ${job.alarmCode}' : ''}',
                ),
              _actionChip(
                Icons.note,
                activeManagerNotes.isEmpty
                    ? 'Add job note'
                    : '${activeManagerNotes.length} job notes',
                _openManagerNotes,
              ),
              _actionChip(
                Icons.edit_note,
                activeNotes.isEmpty
                    ? 'Add field note'
                    : '${activeNotes.length} field notes',
                _openFieldNotes,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Divider(),
        ),
        // Scrollable content
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: [
              // Units
              for (final unit in job.units)
                _UnitSection(
                  unit: unit,
                  jobId: job.jobId,
                  webJobRepo: widget.webJobRepo,
                ),
              // Exit videos
              if (exitVideos.isNotEmpty) ...[
                _sectionHeader('Exit Videos'),
                _VideoList(
                  videos: exitVideos,
                  jobId: job.jobId,
                  onRetryUpload: _retryVideoUpload,
                ),
              ],
              // Manager notes
              if (activeManagerNotes.isNotEmpty) ...[
                _sectionHeader('Manager Job Notes'),
                ...activeManagerNotes.map((n) => _NoteTile(text: n.text)),
              ],
              // Field notes
              if (activeNotes.isNotEmpty) ...[
                _sectionHeader('Field Notes'),
                ...activeNotes.map((n) => _NoteTile(text: n.text)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

// ---------------------------------------------------------------------------
// Unit section
// ---------------------------------------------------------------------------

class _UnitSection extends StatelessWidget {
  const _UnitSection({
    required this.unit,
    required this.jobId,
    required this.webJobRepo,
  });

  final Unit unit;
  final String jobId;
  final WebJobRepository webJobRepo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final beforePhotos = unit.photosBefore.where((p) => p.isActive).toList();
    final afterPhotos = unit.photosAfter.where((p) => p.isActive).toList();

    if (beforePhotos.isEmpty && afterPhotos.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: cs.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_unitIcon(unit.type), size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    unit.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${beforePhotos.length} before, ${afterPhotos.length} after',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (beforePhotos.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Before',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                _PhotoGrid(
                  photos: beforePhotos,
                  jobId: jobId,
                  unitId: unit.unitId,
                  phase: 'before',
                  webJobRepo: webJobRepo,
                ),
              ],
              if (afterPhotos.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'After',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                _PhotoGrid(
                  photos: afterPhotos,
                  jobId: jobId,
                  unitId: unit.unitId,
                  phase: 'after',
                  webJobRepo: webJobRepo,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _unitIcon(String type) {
    switch (type) {
      case 'hood':
        return Icons.kitchen;
      case 'fan':
        return Icons.air;
      default:
        return Icons.category;
    }
  }
}

// ---------------------------------------------------------------------------
// Photo grid — displays photos from Firebase Storage cloudUrl
// ---------------------------------------------------------------------------

class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({
    required this.photos,
    required this.jobId,
    required this.unitId,
    required this.phase,
    required this.webJobRepo,
  });

  final List<PhotoRecord> photos;
  final String jobId;
  final String unitId;
  final String phase;
  final WebJobRepository webJobRepo;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: photos
          .map(
            (photo) => _PhotoThumbnail(
              photo: photo,
              jobId: jobId,
              unitId: unitId,
              phase: phase,
              webJobRepo: webJobRepo,
            ),
          )
          .toList(),
    );
  }
}

class _PhotoThumbnail extends StatefulWidget {
  const _PhotoThumbnail({
    required this.photo,
    required this.jobId,
    required this.unitId,
    required this.phase,
    required this.webJobRepo,
  });

  final PhotoRecord photo;
  final String jobId;
  final String unitId;
  final String phase;
  final WebJobRepository webJobRepo;

  @override
  State<_PhotoThumbnail> createState() => _PhotoThumbnailState();
}

class _PhotoThumbnailState extends State<_PhotoThumbnail> {
  static const double _thumbnailSize = 170;

  bool _loadFailed = false;
  int _retryKey = 0;

  PhotoRecord get photo => widget.photo;

  @override
  void didUpdateWidget(_PhotoThumbnail old) {
    super.didUpdateWidget(old);
    if (old.photo.cloudUrl != photo.cloudUrl) {
      _loadFailed = false;
      _retryKey++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: _loadFailed
          ? () => setState(() {
              _loadFailed = false;
              _retryKey++;
            })
          : () => _showFullImage(context),
      child: Container(
        width: _thumbnailSize,
        height: _thumbnailSize,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: _buildContent(cs),
      ),
    );
  }

  Widget _buildContent(ColorScheme cs) {
    if (photo.cloudUrl != null && !_loadFailed) {
      return Image.network(
        photo.cloudUrl!,
        key: ValueKey('img_${photo.photoId}_$_retryKey'),
        fit: BoxFit.cover,
        width: _thumbnailSize,
        height: _thumbnailSize,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return Container(
            color: cs.surfaceContainerHighest,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
        errorBuilder: (_, _, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _loadFailed = true);
          });
          return _errorPlaceholder(cs);
        },
      );
    }

    if (_loadFailed) return _errorPlaceholder(cs);

    return _statusPlaceholder(cs);
  }

  Widget _statusPlaceholder(ColorScheme cs) {
    final status = photo.syncStatus;
    final IconData icon;
    final String label;

    if (status == 'uploading') {
      icon = Icons.cloud_upload_outlined;
      label = 'Uploading…';
    } else if (status == 'error') {
      icon = Icons.error_outline;
      label = 'Upload error';
    } else if (status == 'pending' || status == null) {
      icon = Icons.cloud_upload_outlined;
      label = 'Pending upload';
    } else {
      icon = Icons.cloud_off;
      label = 'Not uploaded';
    }

    return Container(
      color: cs.surfaceContainerHighest,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24, color: cs.onSurfaceVariant),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _errorPlaceholder(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerHighest,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image_outlined, size: 24, color: cs.error),
          const SizedBox(height: 4),
          Text('Load failed', style: TextStyle(fontSize: 10, color: cs.error)),
          const SizedBox(height: 2),
          Text(
            'Tap to retry',
            style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  void _showFullImage(BuildContext context) {
    if (photo.cloudUrl == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(
                photo.cloudUrl!,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
                errorBuilder: (_, _, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.broken_image_outlined,
                        size: 48,
                        color: Theme.of(ctx).colorScheme.error,
                      ),
                      const SizedBox(height: 8),
                      const Text('Failed to load image'),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filled(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton.filled(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove photo',
                onPressed: () => _confirmDelete(ctx),
              ),
            ),
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  photo.fileName,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext dialogContext) async {
    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove photo?'),
        content: const Text(
          'This photo will be removed from all devices. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await widget.webJobRepo.softDeletePhoto(
        jobId: widget.jobId,
        unitId: widget.unitId,
        phase: widget.phase,
        photoId: photo.photoId,
      );
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Photo removed')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to remove photo: $e')));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Video list
// ---------------------------------------------------------------------------

class _VideoList extends StatefulWidget {
  const _VideoList({
    required this.videos,
    required this.jobId,
    this.onRetryUpload,
  });

  final List<VideoRecord> videos;
  final String jobId;
  final Future<void> Function(String videoId)? onRetryUpload;

  @override
  State<_VideoList> createState() => _VideoListState();
}

enum _VideoDownloadMode { compressed, original }

class _VideoListState extends State<_VideoList> {
  final Map<String, String?> _resolvedUrls = {};
  final Set<String> _resolving = {};
  final Set<String> _downloadingVideoIds = {};

  @override
  void initState() {
    super.initState();
    _resolveAll();
  }

  @override
  void didUpdateWidget(_VideoList old) {
    super.didUpdateWidget(old);
    if (old.jobId != widget.jobId) {
      _resolvedUrls.clear();
      _resolving.clear();
      _resolveAll();
    }
  }

  /// For videos without a cloudUrl, try to look up the download URL
  /// directly from Firebase Storage using the known path convention.
  void _resolveAll() {
    for (final v in widget.videos) {
      if (v.cloudUrl == null && !_resolvedUrls.containsKey(v.videoId)) {
        _resolveVideoUrl(v);
      }
    }
  }

  Future<void> _resolveVideoUrl(VideoRecord video) async {
    if (_resolving.contains(video.videoId)) return;
    _resolving.add(video.videoId);

    try {
      final storagePath =
          'jobs/${widget.jobId}/${video.relativePath.replaceAll('\\', '/')}';
      final url = await FirebaseStorage.instance
          .ref(storagePath)
          .getDownloadURL();
      if (mounted) {
        setState(() => _resolvedUrls[video.videoId] = url);
      }
    } on FirebaseException {
      if (mounted) {
        setState(() => _resolvedUrls[video.videoId] = null);
      }
    } finally {
      _resolving.remove(video.videoId);
    }
  }

  String? _effectiveUrl(VideoRecord v) =>
      v.cloudUrl ?? _resolvedUrls[v.videoId];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: widget.videos.map((v) {
        final url = _effectiveUrl(v);
        final isResolved = url != null && v.cloudUrl == null;
        final uploaded = v.isSynced || url != null;
        final isChecking =
            v.cloudUrl == null && !_resolvedUrls.containsKey(v.videoId);
        final syncStatus = v.syncStatus;
        final String statusLabel;
        Color statusColor = cs.onSurfaceVariant;
        if (isChecking) {
          statusLabel = 'Checking…';
        } else if (uploaded) {
          statusLabel = isResolved ? 'Uploaded (recovered)' : 'Uploaded';
          statusColor = cs.primary;
        } else if (syncStatus == 'uploading') {
          statusLabel = 'Uploading…';
        } else if (syncStatus == 'error') {
          statusLabel = 'Upload failed';
          statusColor = cs.error;
        } else if (syncStatus == 'pending' || syncStatus == null) {
          statusLabel = 'Pending upload';
        } else {
          statusLabel = 'Not uploaded';
        }

        return ListTile(
          leading: Icon(Icons.videocam, color: cs.primary),
          title: Text(v.fileName, overflow: TextOverflow.ellipsis),
          subtitle: isChecking
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(statusLabel, style: TextStyle(color: statusColor)),
                  ],
                )
              : Text(statusLabel, style: TextStyle(color: statusColor)),
          trailing: url != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.play_circle_outline),
                      tooltip: 'Play video',
                      onPressed: () =>
                          _openVideoPlayer(context, url, v.fileName),
                    ),
                    _downloadingVideoIds.contains(v.videoId)
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : PopupMenuButton<_VideoDownloadMode>(
                            icon: const Icon(Icons.download),
                            tooltip: 'Download video',
                            onSelected: (mode) {
                              _downloadVideo(
                                mode: mode,
                                video: v,
                                fallbackUrl: url,
                              );
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: _VideoDownloadMode.compressed,
                                child: Text('Download (~10 MB)'),
                              ),
                              PopupMenuItem(
                                value: _VideoDownloadMode.original,
                                child: Text('Download original'),
                              ),
                            ],
                          ),
                  ],
                )
              : syncStatus == 'error' && widget.onRetryUpload != null
              ? IconButton(
                  icon: Icon(Icons.refresh, color: cs.error),
                  tooltip: 'Retry upload',
                  onPressed: () => widget.onRetryUpload!(v.videoId),
                )
              : null,
        );
      }).toList(),
    );
  }

  void _openVideoPlayer(BuildContext context, String url, String fileName) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 960,
          height: 620,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(
                  children: [
                    const Icon(Icons.play_circle_outline, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Video Playback',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Container(
                  color: Colors.black,
                  child: _WebVideoPlayer(url: url),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadVideo({
    required _VideoDownloadMode mode,
    required VideoRecord video,
    required String fallbackUrl,
  }) async {
    if (_downloadingVideoIds.contains(video.videoId)) return;
    setState(() => _downloadingVideoIds.add(video.videoId));

    try {
      if (mode == _VideoDownloadMode.original) {
        await _downloadOriginal(url: fallbackUrl, fileName: video.fileName);
        return;
      }

      await _downloadCompressed(video: video, fallbackUrl: fallbackUrl);
    } finally {
      if (mounted) {
        setState(() => _downloadingVideoIds.remove(video.videoId));
      }
    }
  }

  Future<void> _downloadOriginal({
    required String url,
    required String fileName,
  }) async {
    try {
      final bytes = await _downloadBytes(url);
      if (bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Video download failed')));
        return;
      }
      _triggerDownload(bytes, fileName);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Video download failed')));
    }
  }

  Future<void> _downloadCompressed({
    required VideoRecord video,
    required String fallbackUrl,
  }) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'prepareCompressedVideoDownload',
        options: HttpsCallableOptions(timeout: const Duration(minutes: 8)),
      );
      final response = await callable.call<Map<String, dynamic>>({
        'jobId': widget.jobId,
        'videoId': video.videoId,
        'relativePath': video.relativePath,
        'fileName': video.fileName,
        'targetMb': 10,
      });
      final data = Map<String, dynamic>.from(response.data);
      final returnedUrl = data['downloadUrl'] as String?;
      final storagePath = data['storagePath'] as String?;
      final resolvedStorageUrl = storagePath != null
          ? await _resolveStorageDownloadUrl(storagePath)
          : null;
      final downloadUrl = returnedUrl ?? resolvedStorageUrl ?? fallbackUrl;
      final outFileName = data['fileName'] as String? ?? video.fileName;
      final note = data['note'] as String?;

      final bytes = await _downloadBytes(downloadUrl);
      if (bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Video download failed')));
        return;
      }

      _triggerDownload(bytes, outFileName);

      if (!mounted) return;
      if (note != null && note.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(note)));
      }
    } catch (_) {
      // If compression pipeline fails, fall back to original download.
      await _downloadOriginal(url: fallbackUrl, fileName: video.fileName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Compression unavailable; downloaded original video.'),
        ),
      );
    }
  }

  Future<String?> _resolveStorageDownloadUrl(String storagePath) async {
    try {
      return await FirebaseStorage.instance.ref(storagePath).getDownloadURL();
    } on FirebaseException {
      return null;
    }
  }

  Future<Uint8List?> _downloadBytes(String url) {
    final completer = Completer<Uint8List?>();
    final xhr = web.XMLHttpRequest();
    xhr.open('GET', url);
    xhr.responseType = 'arraybuffer';
    xhr.onload = (web.Event e) {
      if (xhr.status == 200 && xhr.response != null) {
        final buffer = (xhr.response! as JSArrayBuffer).toDart;
        completer.complete(buffer.asUint8List());
      } else {
        completer.complete(null);
      }
    }.toJS;
    xhr.onerror = (web.Event e) {
      completer.complete(null);
    }.toJS;
    xhr.send();
    return completer.future;
  }

  void _triggerDownload(List<int> bytes, String fileName) {
    final jsArray = Uint8List.fromList(bytes).toJS;
    final blob = web.Blob(
      [jsArray].toJS,
      web.BlobPropertyBag(type: 'video/mp4'),
    );
    final blobUrl = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = blobUrl;
    anchor.download = fileName;
    anchor.click();
    web.URL.revokeObjectURL(blobUrl);
  }
}

class _WebVideoPlayer extends StatefulWidget {
  const _WebVideoPlayer({required this.url});

  final String url;

  @override
  State<_WebVideoPlayer> createState() => _WebVideoPlayerState();
}

class _WebVideoPlayerState extends State<_WebVideoPlayer> {
  late final String _viewType;
  web.HTMLVideoElement? _videoElement;

  @override
  void initState() {
    super.initState();
    _viewType = 'kg-web-video-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final video = web.HTMLVideoElement()
        ..src = widget.url
        ..controls = true
        ..autoplay = true
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = '#000';
      _videoElement = video;
      return video;
    });
  }

  @override
  void dispose() {
    _videoElement
      ?..pause()
      ..src = '';
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}

// ---------------------------------------------------------------------------
// Note tile
// ---------------------------------------------------------------------------

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Card(
        elevation: 0,
        color: cs.surfaceContainerHighest,
        child: Padding(padding: const EdgeInsets.all(12), child: Text(text)),
      ),
    );
  }
}
