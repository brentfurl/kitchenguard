import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/photo_record.dart';
import '../../domain/models/unit.dart';
import '../../providers/sync_provider.dart';
import '../widgets/cloud_aware_image.dart';
import '../widgets/move_destination_sheet.dart';

class UnitPhotoBucketScreen extends ConsumerStatefulWidget {
  const UnitPhotoBucketScreen({
    super.key,
    required this.title,
    required this.jobDir,
    required this.loadPhotos,
    required this.onCapture,
    required this.onJobMutated,
    required this.onSoftDelete,
    required this.onOpenViewer,
    this.allUnits = const [],
    this.currentUnitId,
    this.currentPhase,
    this.currentSubPhase,
    this.onMovePhotos,
    this.onBrokenCloudUrl,
  });

  final String title;
  final Directory jobDir;
  final Future<List<PhotoRecord>> Function() loadPhotos;
  final Future<void> Function() onCapture;
  final Future<void> Function() onJobMutated;
  final Future<void> Function(String relativePath) onSoftDelete;
  final Future<void> Function(
    int initialIndex,
    List<PhotoRecord> photos,
  ) onOpenViewer;

  /// All units in the job — needed for the move destination sheet.
  final List<Unit> allUnits;
  final String? currentUnitId;
  final String? currentPhase;
  final String? currentSubPhase;

  /// Called when the user confirms a batch move.
  final Future<void> Function({
    required List<String> photoIds,
    required String destUnitId,
    required String? destSubPhase,
  })? onMovePhotos;

  /// Called when a cloud URL fails to load, for re-upload recovery.
  final Future<void> Function(String photoId)? onBrokenCloudUrl;

  @override
  ConsumerState<UnitPhotoBucketScreen> createState() =>
      _UnitPhotoBucketScreenState();
}

class _UnitPhotoBucketScreenState extends ConsumerState<UnitPhotoBucketScreen> {
  bool _isLoading = true;
  List<PhotoRecord> _photos = const [];
  int? _pressedTileIndex;

  // Multi-select state
  bool _isSelectMode = false;
  final Set<String> _selectedIds = {};

  List<PhotoRecord> get _visiblePhotos =>
      _photos.where((p) => p.isActive).toList(growable: false);

  bool get _canMove =>
      widget.onMovePhotos != null &&
      widget.currentUnitId != null &&
      widget.currentPhase != null &&
      widget.allUnits.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _reloadPhotos();
  }

  Future<void> _reloadPhotos() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final photos = await widget.loadPhotos();
      if (!mounted) return;
      setState(() {
        _photos = photos;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _captureAndReload() async {
    await widget.onCapture();
    if (!mounted) return;
    await widget.onJobMutated();
    if (!mounted) return;
    await _reloadPhotos();
  }

  void _exitSelectMode() {
    setState(() {
      _isSelectMode = false;
      _selectedIds.clear();
    });
  }

  void _enterSelectMode(String photoId) {
    setState(() {
      _isSelectMode = true;
      _selectedIds.clear();
      _selectedIds.add(photoId);
    });
  }

  void _toggleSelection(String photoId) {
    setState(() {
      if (_selectedIds.contains(photoId)) {
        _selectedIds.remove(photoId);
        if (_selectedIds.isEmpty) {
          _isSelectMode = false;
        }
      } else {
        _selectedIds.add(photoId);
      }
    });
  }

  Future<void> _batchSoftDelete() async {
    final count = _selectedIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $count ${count == 1 ? 'photo' : 'photos'}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final visible = _visiblePhotos;
    final toDelete = visible
        .where((ph) => _selectedIds.contains(ph.photoId))
        .map((ph) => ph.relativePath)
        .toList();

    for (final rp in toDelete) {
      await widget.onSoftDelete(rp);
    }
    await widget.onJobMutated();
    if (!mounted) return;
    _exitSelectMode();
    await _reloadPhotos();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Removed $count ${count == 1 ? 'photo' : 'photos'}',
        ),
      ),
    );
  }

  Future<void> _batchMove() async {
    if (!_canMove) return;

    final destination = await showMoveDestinationSheet(
      context: context,
      allUnits: widget.allUnits,
      currentUnitId: widget.currentUnitId!,
      currentPhase: widget.currentPhase!,
      currentSubPhase: widget.currentSubPhase,
    );

    if (destination == null || !mounted) return;

    final count = _selectedIds.length;
    try {
      await widget.onMovePhotos!(
        photoIds: _selectedIds.toList(),
        destUnitId: destination.unitId,
        destSubPhase: destination.subPhase,
      );
      await widget.onJobMutated();
      if (!mounted) return;
      _exitSelectMode();
      await _reloadPhotos();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Moved $count ${count == 1 ? 'photo' : 'photos'}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Move failed: $e')),
      );
    }
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final theme = Theme.of(context);

    if (_isSelectMode) {
      final count = _selectedIds.length;
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _exitSelectMode,
        ),
        title: Text('$count selected'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove',
            onPressed: count > 0 ? _batchSoftDelete : null,
          ),
          if (_canMove)
            IconButton(
              icon: const Icon(Icons.drive_file_move_outline),
              tooltip: 'Move',
              onPressed: count > 0 ? _batchMove : null,
            ),
        ],
      );
    }

    final currentPhotosList = _visiblePhotos;
    final photoCount = currentPhotosList.length;
    final countLabel = '$photoCount ${photoCount == 1 ? 'photo' : 'photos'}';

    return AppBar(
      toolbarHeight: 72,
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title),
          Text(
            countLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(pullVersionProvider, (_, __) {
      if (!mounted || _isLoading) return;
      _reloadPhotos();
    });

    final theme = Theme.of(context);
    final currentPhotosList = _visiblePhotos;

    return Scaffold(
      appBar: _buildAppBar(context),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : currentPhotosList.isEmpty
          ? const Center(child: Text('No photos yet.'))
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1,
              ),
              itemCount: currentPhotosList.length,
              itemBuilder: (context, index) {
                final photo = currentPhotosList[index];
                final relativePath = photo.relativePath;
                final file = relativePath.isEmpty
                    ? null
                    : File(p.join(widget.jobDir.path, relativePath));
                final isSelected = _selectedIds.contains(photo.photoId);

                return Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTapDown: _isSelectMode
                        ? null
                        : (_) {
                            if (!mounted) return;
                            setState(() => _pressedTileIndex = index);
                          },
                    onTapCancel: _isSelectMode
                        ? null
                        : () {
                            if (!mounted) return;
                            setState(() => _pressedTileIndex = null);
                          },
                    onTap: () async {
                      if (_isSelectMode) {
                        _toggleSelection(photo.photoId);
                        return;
                      }
                      if (mounted) {
                        setState(() => _pressedTileIndex = null);
                      }
                      await widget.onOpenViewer(index, currentPhotosList);
                      if (!mounted) return;
                      await _reloadPhotos();
                    },
                    onLongPress: () async {
                      if (_isSelectMode) {
                        _toggleSelection(photo.photoId);
                        return;
                      }
                      if (mounted) {
                        setState(() => _pressedTileIndex = null);
                      }
                      _enterSelectMode(photo.photoId);
                    },
                    child: AnimatedScale(
                      scale: _pressedTileIndex == index && !_isSelectMode
                          ? 0.97
                          : 1,
                      duration: const Duration(milliseconds: 90),
                      curve: Curves.easeOut,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          AspectRatio(
                            aspectRatio: 1,
                            child: CloudAwareImage(
                              localFile: file,
                              cloudUrl: photo.cloudUrl,
                              syncStatus: photo.syncStatus,
                              showCloudBadge: true,
                              onCloudUrlBroken: widget.onBrokenCloudUrl != null
                                  ? () => widget.onBrokenCloudUrl!(photo.photoId)
                                  : null,
                            ),
                          ),
                          // Press overlay (non-select mode only)
                          if (!_isSelectMode)
                            AnimatedOpacity(
                              opacity: _pressedTileIndex == index ? 1 : 0,
                              duration: const Duration(milliseconds: 70),
                              child: Container(
                                color: Colors.black.withValues(alpha: 0.14),
                              ),
                            ),
                          // Selection overlay
                          if (_isSelectMode)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              color: isSelected
                                  ? theme.colorScheme.primary
                                      .withValues(alpha: 0.25)
                                  : Colors.transparent,
                            ),
                          if (_isSelectMode)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Icon(
                                isSelected
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                size: 24,
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : Colors.white.withValues(alpha: 0.8),
                                shadows: const [
                                  Shadow(
                                    blurRadius: 4,
                                    color: Colors.black38,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: _isSelectMode
          ? null
          : FloatingActionButton.large(
              onPressed: _captureAndReload,
              child: const Icon(Icons.camera_alt),
            ),
    );
  }
}
