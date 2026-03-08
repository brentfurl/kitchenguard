import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class UnitPhotoBucketScreen extends StatefulWidget {
  const UnitPhotoBucketScreen({
    super.key,
    required this.title,
    required this.jobDir,
    required this.loadPhotos,
    required this.onCapture,
    required this.onJobMutated,
    required this.onSoftDelete,
    required this.onOpenViewer,
  });

  final String title;
  final Directory jobDir;
  final Future<List<Map<String, dynamic>>> Function() loadPhotos;
  final Future<void> Function() onCapture;
  final Future<void> Function() onJobMutated;
  final Future<void> Function(String relativePath) onSoftDelete;
  final Future<void> Function(
    int initialIndex,
    List<Map<String, dynamic>> photos,
  )
  onOpenViewer;

  @override
  State<UnitPhotoBucketScreen> createState() => _UnitPhotoBucketScreenState();
}

class _UnitPhotoBucketScreenState extends State<UnitPhotoBucketScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _photos = const [];

  List<Map<String, dynamic>> get _visiblePhotos {
    return _photos
        .where((photo) {
          final status = (photo['status'] ?? 'local').toString();
          final missingLocal = photo['missingLocal'] == true;
          return status != 'deleted' &&
              status != 'missing_local' &&
              !missingLocal;
        })
        .toList(growable: false);
  }

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
      await _reloadPhotos();
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
    final currentPhotosList = _visiblePhotos;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
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
                final status = (photo['status'] ?? 'local').toString();
                final relativePath = (photo['relativePath'] ?? '').toString();
                final file = relativePath.isEmpty
                    ? null
                    : File(p.join(widget.jobDir.path, relativePath));
                final showImage =
                    status == 'local' &&
                    relativePath.isNotEmpty &&
                    file != null &&
                    file.existsSync();
                final isMissing = !showImage;

                return InkWell(
                  onTap: () async {
                    await widget.onOpenViewer(index, currentPhotosList);
                    if (!mounted) return;
                    await _reloadPhotos();
                  },
                  onLongPress: () async {
                    if (relativePath.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Cannot remove photo: missing path.'),
                        ),
                      );
                      return;
                    }
                    await _confirmSoftDelete(relativePath);
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: isMissing
                        ? Container(
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
                          )
                        : AspectRatio(
                            aspectRatio: 1,
                            child: Image.file(file, fit: BoxFit.cover),
                          ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _captureAndReload,
        child: const Icon(Icons.camera_alt),
      ),
    );
  }
}
