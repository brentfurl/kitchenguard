import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({
    super.key,
    required this.title,
    this.videoFile,
    this.networkUrl,
  }) : assert(videoFile != null || networkUrl != null);

  final String title;
  final File? videoFile;
  final String? networkUrl;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final VideoPlayerController _controller;
  String? _initError;

  @override
  void initState() {
    super.initState();
    if (widget.videoFile != null) {
      _controller = VideoPlayerController.file(widget.videoFile!);
    } else {
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.networkUrl!),
      );
    }
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _controller.play();
    }).catchError((Object error) {
      if (!mounted) return;
      setState(() {
        _initError = error.toString();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isCloud => widget.videoFile == null && widget.networkUrl != null;

  @override
  Widget build(BuildContext context) {
    final initialized = _controller.value.isInitialized;
    final position = initialized ? _controller.value.position : Duration.zero;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_isCloud)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.cloud_outlined, size: 20),
            ),
        ],
      ),
      body: _initError != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 40),
                  const SizedBox(height: 8),
                  Text(
                    _isCloud
                        ? 'Failed to load video from cloud'
                        : 'Failed to load video',
                  ),
                ],
              ),
            )
          : initialized
          ? Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _controller.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                        onPressed: () {
                          if (_controller.value.isPlaying) {
                            _controller.pause();
                          } else {
                            _controller.play();
                          }
                          setState(() {});
                        },
                      ),
                      Text(_formatDuration(position)),
                    ],
                  ),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes.toString().padLeft(2, '0');
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
