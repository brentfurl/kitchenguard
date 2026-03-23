import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/job.dart';
import '../../domain/models/photo_record.dart';
import '../../domain/models/unit.dart';
import '../../domain/models/video_record.dart';
import '../web_providers.dart';

/// Real-time single-job stream provider, keyed by jobId.
final _webJobDetailProvider =
    StreamProvider.family<Job?, String>((ref, jobId) {
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

        return _JobDetailBody(job: job, onBack: onBack, theme: theme);
      },
    );
  }
}

class _JobDetailBody extends StatelessWidget {
  const _JobDetailBody({
    required this.job,
    required this.onBack,
    required this.theme,
  });

  final Job job;
  final VoidCallback onBack;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    final activeNotes = job.notes.where((n) => n.isActive).toList();
    final activeManagerNotes =
        job.managerNotes.where((n) => n.isActive).toList();
    final activeLayoutPhotos =
        job.preCleanLayoutPhotos.where((p) => p.isActive).toList();
    final exitVideos =
        job.videos.exit.where((v) => v.isActive).toList();

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
                onPressed: onBack,
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
                          Icon(Icons.check_circle,
                              size: 22, color: cs.primary),
                          const SizedBox(width: 4),
                          Text('Complete',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: cs.primary)),
                        ],
                      ],
                    ),
                    if (job.address != null || job.city != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        [job.address, job.city]
                            .where((s) => s != null && s.isNotEmpty)
                            .join(', '),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
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
                _chip(Icons.vpn_key, job.accessType!),
              if (job.hasAlarm == true)
                _chip(Icons.alarm, 'Alarm${job.alarmCode != null ? ': ${job.alarmCode}' : ''}'),
              if (activeManagerNotes.isNotEmpty)
                _chip(Icons.note, '${activeManagerNotes.length} job notes'),
              if (activeNotes.isNotEmpty)
                _chip(Icons.edit_note, '${activeNotes.length} field notes'),
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
              // Pre-clean layout photos
              if (activeLayoutPhotos.isNotEmpty) ...[
                _sectionHeader('Pre-Clean Layout'),
                _PhotoGrid(photos: activeLayoutPhotos),
                const SizedBox(height: 16),
              ],
              // Units
              for (final unit in job.units) _UnitSection(unit: unit),
              // Exit videos
              if (exitVideos.isNotEmpty) ...[
                _sectionHeader('Exit Videos'),
                _VideoList(videos: exitVideos),
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
      child: Text(title,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600)),
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
  const _UnitSection({required this.unit});

  final Unit unit;

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
                  Text(unit.name,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Text(
                    '${beforePhotos.length} before, ${afterPhotos.length} after',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              if (beforePhotos.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Before',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 8),
                _PhotoGrid(photos: beforePhotos),
              ],
              if (afterPhotos.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('After',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 8),
                _PhotoGrid(photos: afterPhotos),
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
  const _PhotoGrid({required this.photos});

  final List<PhotoRecord> photos;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: photos.map((photo) => _PhotoThumbnail(photo: photo)).toList(),
    );
  }
}

class _PhotoThumbnail extends StatelessWidget {
  const _PhotoThumbnail({required this.photo});

  final PhotoRecord photo;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => _showFullImage(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: photo.cloudUrl != null
            ? CachedNetworkImage(
                imageUrl: photo.cloudUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: cs.surfaceContainerHighest,
                  child: const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                errorWidget: (_, __, ___) => _placeholder(cs),
              )
            : _placeholder(cs),
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerHighest,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, size: 24, color: cs.onSurfaceVariant),
          const SizedBox(height: 4),
          Text('Not uploaded',
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
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
              child: CachedNetworkImage(
                imageUrl: photo.cloudUrl!,
                fit: BoxFit.contain,
                placeholder: (_, __) =>
                    const Center(child: CircularProgressIndicator()),
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
}

// ---------------------------------------------------------------------------
// Video list
// ---------------------------------------------------------------------------

class _VideoList extends StatelessWidget {
  const _VideoList({required this.videos});

  final List<VideoRecord> videos;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: videos
          .map((v) => ListTile(
                leading: Icon(Icons.videocam, color: cs.primary),
                title: Text(v.fileName, overflow: TextOverflow.ellipsis),
                subtitle: Text(v.isSynced ? 'Uploaded' : 'Not uploaded',
                    style: TextStyle(
                        color:
                            v.isSynced ? cs.primary : cs.onSurfaceVariant)),
                trailing: v.cloudUrl != null
                    ? IconButton(
                        icon: const Icon(Icons.open_in_new),
                        tooltip: 'Open video',
                        onPressed: () => _openVideoUrl(context, v.cloudUrl!),
                      )
                    : null,
              ))
          .toList(),
    );
  }

  void _openVideoUrl(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Video Playback'),
        content: const Text(
          'Video streaming in-browser is not yet supported. '
          'The video has been uploaded to Firebase Storage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(text),
        ),
      ),
    );
  }
}
