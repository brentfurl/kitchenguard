import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/video_record.dart';
import '../../providers/sync_provider.dart';
import '../../providers/upload_progress_provider.dart';
import 'video_player_screen.dart';

class VideosScreen extends ConsumerStatefulWidget {
  const VideosScreen({
    super.key,
    required this.title,
    required this.kind,
    required this.loadVideos,
    required this.captureVideo,
    required this.resolveVideoFile,
    this.softDelete,
    this.retryUpload,
  });

  final String title;
  final String kind; // 'exit' | 'other'
  final Future<List<VideoRecord>> Function() loadVideos;
  final Future<void> Function() captureVideo;
  final Future<File?> Function(String relativePath) resolveVideoFile;
  final Future<void> Function(String relativePath)? softDelete;
  final Future<void> Function(String videoId)? retryUpload;

  @override
  ConsumerState<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends ConsumerState<VideosScreen> {
  bool _isLoading = true;
  bool _reloadInProgress = false;
  bool _reloadQueued = false;
  bool _queuedShowSpinner = false;
  List<VideoRecord> _videos = const [];
  final Map<String, Future<File?>> _thumbnailFutures = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload({bool showSpinner = true}) async {
    if (_reloadInProgress) {
      _reloadQueued = true;
      _queuedShowSpinner = _queuedShowSpinner || showSpinner;
      return;
    }
    _reloadInProgress = true;
    if (showSpinner && mounted) {
      setState(() {
        _isLoading = true;
      });
    }
    try {
      final videos = await widget.loadVideos();
      if (!mounted) return;
      setState(() {
        _videos = videos;
        _thumbnailFutures.removeWhere(
          (videoId, _) => !videos.any((v) => v.videoId == videoId),
        );
      });
    } finally {
      if (mounted) {
        if (showSpinner) {
          setState(() {
            _isLoading = false;
          });
        }
        _reloadInProgress = false;
        if (_reloadQueued) {
          final queuedShowSpinner = _queuedShowSpinner;
          _reloadQueued = false;
          _queuedShowSpinner = false;
          _reload(showSpinner: queuedShowSpinner);
        }
      } else {
        _reloadInProgress = false;
      }
    }
  }

  Future<void> _captureVideo() async {
    await widget.captureVideo();
    if (!mounted) return;
    await _reload(showSpinner: true);
  }

  Future<void> _confirmDelete({required String relativePath}) async {
    if (widget.softDelete == null) {
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove video?'),
          content: const Text(
            'Remove this video from the job? It will remain on device storage.',
          ),
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
        );
      },
    );

    if (ok != true || !mounted) return;

    try {
      await widget.softDelete!(relativePath);
      if (!mounted) return;
      await _reload(showSpinner: false);
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst(
        RegExp(r'^(StateError|Exception):\s*'),
        '',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message.isEmpty ? 'Failed to remove video' : message),
        ),
      );
    }
  }

  Future<void> _retryUpload(VideoRecord video) async {
    final retryUpload = widget.retryUpload;
    if (retryUpload == null) return;
    try {
      await retryUpload(video.videoId);
      if (!mounted) return;
      await _reload(showSpinner: false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Retry queued')),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst(
        RegExp(r'^(StateError|Exception):\s*'),
        '',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message.isEmpty ? 'Retry failed' : message)),
      );
    }
  }

  Future<void> _showActionsMenu({required VideoRecord video}) async {
    final canDelete = video.relativePath.isNotEmpty && widget.softDelete != null;
    final canRetry = !video.isSynced && widget.retryUpload != null;
    if (!canDelete && !canRetry) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canRetry)
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('Retry upload'),
                  onTap: () => Navigator.of(context).pop('retry'),
                ),
              if (canDelete)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Remove from job'),
                  onTap: () => Navigator.of(context).pop('remove'),
                ),
            ],
          ),
        );
      },
    );

    if (action == 'retry') {
      await _retryUpload(video);
      return;
    }

    if (action == 'remove') {
      await _confirmDelete(relativePath: video.relativePath);
    }
  }

  Future<void> _openVideo(VideoRecord video) async {
    final relativePath = video.relativePath;
    final cloudUrl = video.cloudUrl;
    final hasCloud = cloudUrl != null && cloudUrl.isNotEmpty;
    final fileName = video.fileName.isEmpty ? 'Unnamed video' : video.fileName;

    if (relativePath.isEmpty && !hasCloud) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing relativePath')),
      );
      return;
    }

    File? file;
    if (relativePath.isNotEmpty) {
      file = await widget.resolveVideoFile(relativePath);
    }

    if (file == null && !hasCloud) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video file missing')),
      );
      return;
    }

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlayerScreen(
          title: fileName,
          videoFile: file,
          networkUrl: file == null ? cloudUrl : null,
        ),
      ),
    );
  }

  Future<File?> _resolveThumbnailFile(VideoRecord video) async {
    final thumbnailPath = video.thumbnailPath;
    if (thumbnailPath == null || thumbnailPath.isEmpty) return null;
    return widget.resolveVideoFile(thumbnailPath);
  }

  Future<File?> _thumbnailFutureFor(VideoRecord video) {
    return _thumbnailFutures.putIfAbsent(
      video.videoId,
      () => _resolveThumbnailFile(video),
    );
  }

  Widget _buildSyncBadge(String? syncStatus) {
    if (syncStatus == null) return const SizedBox.shrink();
    final (IconData icon, Color color) = switch (syncStatus) {
      'synced' => (Icons.cloud_done, Colors.green),
      'uploading' => (Icons.cloud_upload, Colors.blue),
      'pending' => (Icons.cloud_upload_outlined, Colors.orange),
      'error' => (Icons.cloud_off, Colors.red),
      _ => (Icons.help_outline, Colors.transparent),
    };
    if (color == Colors.transparent) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 16, color: color),
    );
  }

  Widget _buildThumbnail(VideoRecord video) {
    final cloudThumb = video.thumbnailCloudUrl;
    return FutureBuilder<File?>(
      future: _thumbnailFutureFor(video),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file != null) {
          return Image.file(file, fit: BoxFit.cover);
        }
        if (cloudThumb != null && cloudThumb.isNotEmpty) {
          return Image.network(
            cloudThumb,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _videoPlaceholder(),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return _videoPlaceholder();
      },
    );
  }

  Widget _videoPlaceholder() {
    return Container(
      color: Colors.black12,
      alignment: Alignment.center,
      child: const Icon(Icons.videocam, size: 30, color: Colors.black45),
    );
  }

  void _requestReload() {
    if (!mounted) return;
    if (_reloadInProgress) {
      _reloadQueued = true;
      return;
    }
    _reload(showSpinner: false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(pullVersionProvider, (_, __) {
      _requestReload();
    });
    ref.listen<UploadProgressState>(uploadProgressProvider, (previous, next) {
      final becameIdle = (previous?.isProcessing ?? false) && !next.isProcessing;
      final pendingChanged = previous?.pendingCount != next.pendingCount;
      if (becameIdle || pendingChanged) {
        _requestReload();
      }
    });

    final count = _videos.length;
    final emptyLabel = widget.kind == 'exit'
        ? 'No exit videos yet.'
        : 'No other videos yet.';
    final captureLabel = widget.kind == 'exit'
        ? 'Capture Exit Video'
        : 'Capture Other Video';

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                FilledButton(
                  onPressed: _captureVideo,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: Text(captureLabel),
                ),
                const SizedBox(height: 16),
                if (count == 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(emptyLabel),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _videos.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 1,
                        ),
                    itemBuilder: (context, index) {
                      final video = _videos[index];
                      final canShowActions =
                          (video.relativePath.isNotEmpty &&
                              widget.softDelete != null) ||
                          (!video.isSynced && widget.retryUpload != null);
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => _openVideo(video),
                          onLongPress: canShowActions
                              ? () => _showActionsMenu(video: video)
                              : null,
                          child: Ink(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.black12),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  _buildThumbnail(video),
                                  Container(color: Colors.black12),
                                  const Center(
                                    child: Icon(
                                      Icons.play_circle_fill,
                                      color: Colors.white70,
                                      size: 34,
                                    ),
                                  ),
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: _buildSyncBadge(video.syncStatus),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }
}
