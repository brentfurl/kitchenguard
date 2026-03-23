import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Displays an image using local-first strategy with cloud fallback.
///
/// Resolution order:
///   1. [localFile] exists on disk → `Image.file`
///   2. [cloudUrl] is non-null → `CachedNetworkImage` (disk-cached by URL)
///   3. Neither available → missing-file placeholder
///
/// Used by all gallery/viewer screens so that photos uploaded by another
/// device (or photos whose local copy was lost) remain viewable.
class CloudAwareImage extends StatelessWidget {
  const CloudAwareImage({
    super.key,
    this.localFile,
    this.cloudUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.showCloudBadge = false,
  });

  final File? localFile;
  final String? cloudUrl;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// When true, a small cloud icon is overlaid on images loaded from the
  /// network (helps the user distinguish local vs. cloud-only photos).
  final bool showCloudBadge;

  bool get _localAvailable => localFile != null && localFile!.existsSync();
  bool get _cloudAvailable => cloudUrl != null && cloudUrl!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (_localAvailable) {
      return Image.file(
        localFile!,
        fit: fit,
        width: width,
        height: height,
      );
    }

    if (_cloudAvailable) {
      final image = CachedNetworkImage(
        imageUrl: cloudUrl!,
        fit: fit,
        width: width,
        height: height,
        placeholder: (_, __) => Container(
          color: Colors.grey.shade100,
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        errorWidget: (_, __, ___) => _missingPlaceholder(),
      );

      if (!showCloudBadge) return image;

      return Stack(
        fit: StackFit.passthrough,
        children: [
          image,
          Positioned(
            bottom: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.cloud_outlined,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ],
      );
    }

    return _missingPlaceholder();
  }

  static Widget _missingPlaceholder() {
    return Container(
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
    );
  }
}
