import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/models/video_record.dart';
import 'video_player_screen.dart';

class VideosScreen extends StatefulWidget {
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
  State<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends State<VideosScreen> {
  bool _isLoading = true;
  List<VideoRecord> _videos = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final videos = await widget.loadVideos();
      if (!mounted) return;
      setState(() {
        _videos = videos;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _captureVideo() async {
    await widget.captureVideo();
    if (!mounted) return;
    await _reload();
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
      await _reload();
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
      await _reload();
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

  @override
  Widget build(BuildContext context) {
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
                  ..._videos.map((video) {
                    final fileName = video.fileName.isEmpty
                        ? 'Unnamed video'
                        : video.fileName;
                    final relativePath = video.relativePath;
                    final cloudUrl = video.cloudUrl;
                    final hasCloud = cloudUrl != null && cloudUrl.isNotEmpty;
                    final canShowActions =
                        (relativePath.isNotEmpty && widget.softDelete != null) ||
                        (!video.isSynced && widget.retryUpload != null);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(fileName),
                      trailing: hasCloud
                          ? const Icon(Icons.cloud_outlined, size: 16)
                          : null,
                      onTap: () async {
                        if (relativePath.isEmpty && !hasCloud) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Missing relativePath'),
                            ),
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
                      },
                      onLongPress: canShowActions
                          ? () => _showActionsMenu(video: video)
                          : null,
                    );
                  }),
              ],
            ),
    );
  }
}
