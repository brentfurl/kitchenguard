import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'photo_viewer_screen.dart';
import 'rapid_photo_capture_screen.dart';

class PreCleanLayoutScreen extends StatefulWidget {
  const PreCleanLayoutScreen({
    super.key,
    required this.jobDir,
    required this.loadPhotos,
    required this.onCaptureFile,
    required this.onSoftDelete,
    required this.onJobMutated,
  });

  final Directory jobDir;
  final Future<List<Map<String, dynamic>>> Function() loadPhotos;
  final Future<void> Function(File file) onCaptureFile;
  final Future<void> Function(String relativePath) onSoftDelete;
  final Future<void> Function() onJobMutated;

  @override
  State<PreCleanLayoutScreen> createState() => _PreCleanLayoutScreenState();
}

class _PreCleanLayoutScreenState extends State<PreCleanLayoutScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _photos = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _isLoading = true);
    try {
      final photos = await widget.loadPhotos();
      if (!mounted) return;
      setState(() => _photos = photos);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _capture() async {
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RapidPhotoCaptureScreen(
            unitName: 'Pre-clean Layout',
            phaseLabel: 'Layout',
            loadVisibleCount: () async {
              final photos = await widget.loadPhotos();
              return photos.length;
            },
            onCaptureFile: widget.onCaptureFile,
          ),
        ),
      );
      if (!mounted) return;
      await widget.onJobMutated();
      if (!mounted) return;
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _openGalleryViewer() async {
    if (_photos.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No photos to review yet.')));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoViewerScreen(
          jobDir: widget.jobDir,
          title: 'Pre-clean Layout',
          photos: _photos,
          initialIndex: 0,
          onSoftDelete: widget.onSoftDelete,
          onJobMutated: () async {
            await widget.onJobMutated();
            await _reload();
          },
          reloadPhotos: widget.loadPhotos,
        ),
      ),
    );
    if (!mounted) return;
    await _reload();
  }

  Future<void> _confirmSoftDelete(String relativePath) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove photo?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove from job'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !mounted) {
      return;
    }

    try {
      await widget.onSoftDelete(relativePath);
      await widget.onJobMutated();
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Removed from job')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pre-clean Layout')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _capture,
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Capture Layout Photo'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        onPressed: _openGalleryViewer,
                        tooltip: 'View Layout Photos',
                        icon: const Icon(Icons.photo_library_outlined),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Text(
                    'Photos (${_photos.length})',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (_photos.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'Take photos of equipment placement before moving items for cleaning.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1,
                          ),
                      itemCount: _photos.length,
                      itemBuilder: (context, index) {
                        final photo = _photos[index];
                        final relativePath = (photo['relativePath'] ?? '')
                            .toString();
                        final file = relativePath.isEmpty
                            ? null
                            : File(p.join(widget.jobDir.path, relativePath));
                        final exists = file != null && file.existsSync();

                        return InkWell(
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => PhotoViewerScreen(
                                  jobDir: widget.jobDir,
                                  title: 'Pre-clean Layout',
                                  photos: _photos,
                                  initialIndex: index,
                                  onSoftDelete: widget.onSoftDelete,
                                  onJobMutated: () async {
                                    await widget.onJobMutated();
                                    await _reload();
                                  },
                                  reloadPhotos: widget.loadPhotos,
                                ),
                              ),
                            );
                            if (!mounted) return;
                            await _reload();
                          },
                          onLongPress: () async {
                            if (relativePath.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Cannot remove photo: missing path.',
                                  ),
                                ),
                              );
                              return;
                            }
                            await _confirmSoftDelete(relativePath);
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: exists
                                ? Image.file(file, fit: BoxFit.cover)
                                : Container(
                                    color: Colors.grey.shade200,
                                    child: const Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.broken_image_outlined),
                                          SizedBox(height: 6),
                                          Text('Missing'),
                                        ],
                                      ),
                                    ),
                                  ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}
