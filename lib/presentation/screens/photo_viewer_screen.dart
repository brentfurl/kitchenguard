import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/photo_record.dart';

class PhotoViewerScreen extends StatefulWidget {
  const PhotoViewerScreen({
    super.key,
    required this.jobDir,
    required this.title,
    required this.photos,
    required this.initialIndex,
    required this.onSoftDelete,
    required this.onJobMutated,
    this.reloadPhotos,
  });

  final Directory jobDir;
  final String title;
  final List<PhotoRecord> photos;
  final int initialIndex;
  final Future<void> Function(String relativePath) onSoftDelete;
  final Future<void> Function() onJobMutated;
  final Future<List<PhotoRecord>> Function()? reloadPhotos;

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final PageController _pageController;
  late int _currentIndex;
  late List<PhotoRecord> _photos;

  @override
  void initState() {
    super.initState();
    _photos = widget.photos
        .where((photo) => !photo.isDeleted)
        .toList(growable: true);
    final initial = _photos.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, _photos.length - 1);
    _currentIndex = initial;
    _pageController = PageController(initialPage: initial);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _deleteCurrentPhoto() async {
    if (_photos.isEmpty ||
        _currentIndex < 0 ||
        _currentIndex >= _photos.length) {
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove photo from job?'),
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

    final photo = _photos[_currentIndex];
    final relativePath = photo.relativePath;
    if (relativePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot remove photo: missing path.')),
      );
      return;
    }

    try {
      await widget.onSoftDelete(relativePath);
      await widget.onJobMutated();
      if (widget.reloadPhotos != null) {
        await widget.reloadPhotos!.call();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Removed from job')));
      Navigator.of(context).pop(true);
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
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleteCurrentPhoto,
          ),
        ],
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: _photos.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              final photo = _photos[index];
              final relativePath = photo.relativePath;
              final hasPath = relativePath.isNotEmpty;
              final file = hasPath
                  ? File(p.join(widget.jobDir.path, relativePath))
                  : null;
              final localAvailable =
                  !photo.isMissing &&
                  hasPath &&
                  file != null &&
                  file.existsSync();
              final cloudUrl = photo.cloudUrl;
              final cloudAvailable =
                  cloudUrl != null && cloudUrl.isNotEmpty;

              if (localAvailable) {
                return Center(
                  child: InteractiveViewer(
                    child: Image.file(file, fit: BoxFit.contain),
                  ),
                );
              }

              if (cloudAvailable) {
                return Center(
                  child: InteractiveViewer(
                    child: CachedNetworkImage(
                      imageUrl: cloudUrl,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      errorWidget: (_, __, ___) => const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off_outlined, size: 40),
                          SizedBox(height: 8),
                          Text('Failed to load from cloud'),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image_outlined, size: 40),
                    SizedBox(height: 8),
                    Text('Missing file'),
                  ],
                ),
              );
            },
          ),
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_photos.isEmpty ? 0 : _currentIndex + 1} / ${_photos.length}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
