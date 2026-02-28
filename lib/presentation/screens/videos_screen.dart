import 'dart:io';

import 'package:flutter/material.dart';

import 'video_player_screen.dart';

class VideosScreen extends StatefulWidget {
  const VideosScreen({
    super.key,
    required this.loadExitVideos,
    required this.loadOtherVideos,
    required this.captureExit,
    required this.captureOther,
    required this.resolveVideoFile,
    this.softDelete,
  });

  final Future<List<Map<String, dynamic>>> Function() loadExitVideos;
  final Future<List<Map<String, dynamic>>> Function() loadOtherVideos;
  final Future<void> Function() captureExit;
  final Future<void> Function() captureOther;
  final Future<File?> Function(String relativePath) resolveVideoFile;
  final Future<void> Function(String kind, String relativePath)? softDelete;

  @override
  State<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends State<VideosScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _exitVideos = const [];
  List<Map<String, dynamic>> _otherVideos = const [];

  List<Map<String, dynamic>> _active(List<Map<String, dynamic>> items) {
    return items
        .where((item) {
          final status = (item['status'] ?? 'local').toString();
          return status != 'deleted';
        })
        .toList(growable: false);
  }

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
      final exit = await widget.loadExitVideos();
      final other = await widget.loadOtherVideos();
      if (!mounted) return;
      setState(() {
        _exitVideos = exit;
        _otherVideos = other;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _captureExit() async {
    await widget.captureExit();
    if (!mounted) return;
    await _reload();
  }

  Future<void> _captureOther() async {
    await widget.captureOther();
    if (!mounted) return;
    await _reload();
  }

  Future<void> _confirmDelete({
    required String kind,
    required String relativePath,
  }) async {
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
      await widget.softDelete!(kind, relativePath);
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

  Future<void> _showDeleteMenu({
    required String kind,
    required String relativePath,
  }) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Remove from job'),
            onTap: () => Navigator.of(context).pop('remove'),
          ),
        );
      },
    );

    if (action != 'remove') {
      return;
    }
    await _confirmDelete(kind: kind, relativePath: relativePath);
  }

  Widget _buildSection({
    required String title,
    required String kind,
    required List<Map<String, dynamic>> items,
  }) {
    final active = _active(items);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$title (${active.length})', style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 8),
        if (active.isEmpty)
          const Text('None')
        else
          ...active.map((video) {
            final fileName = (video['fileName'] ?? 'Unnamed video').toString();
            final relativePath = (video['relativePath'] ?? '').toString();
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(fileName),
              onTap: () async {
                if (relativePath.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Missing relativePath')),
                  );
                  return;
                }

                final file = await widget.resolveVideoFile(relativePath);
                if (file == null) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Video file missing')),
                  );
                  return;
                }

                if (!mounted) return;
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        VideoPlayerScreen(title: fileName, videoFile: file),
                  ),
                );
              },
              onLongPress: relativePath.isEmpty || widget.softDelete == null
                  ? null
                  : () =>
                        _showDeleteMenu(kind: kind, relativePath: relativePath),
            );
          }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Videos')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                FilledButton(
                  onPressed: _captureExit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: const Text('Exit Video'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _captureOther,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: const Text('Other Video'),
                ),
                const SizedBox(height: 24),
                _buildSection(
                  title: 'Exit Videos',
                  kind: 'exit',
                  items: _exitVideos,
                ),
                const SizedBox(height: 20),
                _buildSection(
                  title: 'Other Videos',
                  kind: 'other',
                  items: _otherVideos,
                ),
              ],
            ),
    );
  }
}
