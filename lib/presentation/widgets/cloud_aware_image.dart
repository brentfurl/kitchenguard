import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Displays an image using local-first strategy with cloud fallback.
///
/// Resolution order:
///   1. [localFile] exists on disk → `Image.file`
///   2. [cloudUrl] is non-null → `CachedNetworkImage` (disk-cached by URL)
///   3. Neither available → missing-file placeholder
///
/// Used by all gallery/viewer screens so that photos uploaded by another
/// device (or photos whose local copy was lost) remain viewable.
class CloudAwareImage extends StatefulWidget {
  const CloudAwareImage({
    super.key,
    this.localFile,
    this.cloudUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.showCloudBadge = false,
    this.onCloudUrlBroken,
    this.syncStatus,
  });

  final File? localFile;
  final String? cloudUrl;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// When true, a small cloud icon is overlaid on images loaded from the
  /// network (helps the user distinguish local vs. cloud-only photos).
  final bool showCloudBadge;

  /// Fired (at most once per [cloudUrl]) when [CachedNetworkImage] fails
  /// to load the URL.
  ///
  /// Callers can use this to reset the photo's sync state and re-queue
  /// the upload from the device that has the local file.
  final VoidCallback? onCloudUrlBroken;

  /// Optional media sync status used to distinguish "not yet uploaded"
  /// from truly missing files when neither local nor cloud URL is available.
  final String? syncStatus;

  @override
  State<CloudAwareImage> createState() => _CloudAwareImageState();
}

class _CloudAwareImageState extends State<CloudAwareImage> {
  /// Tracks the URL for which the error callback has already fired so we
  /// don't re-fire on every rebuild.
  String? _reportedBrokenUrl;

  bool get _localAvailable =>
      widget.localFile != null && widget.localFile!.existsSync();
  bool get _cloudAvailable =>
      widget.cloudUrl != null && widget.cloudUrl!.isNotEmpty;

  @override
  void didUpdateWidget(CloudAwareImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cloudUrl != widget.cloudUrl) {
      _reportedBrokenUrl = null;
    }
  }

  void _handleCloudError() {
    if (widget.onCloudUrlBroken == null) return;
    if (_reportedBrokenUrl == widget.cloudUrl) return;
    _reportedBrokenUrl = widget.cloudUrl;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      widget.onCloudUrlBroken?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_localAvailable) {
      final image = Image.file(
        widget.localFile!,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
      );
      final badge = _syncBadge();
      if (badge == null) return image;
      return Stack(
        fit: StackFit.passthrough,
        children: [
          image,
          Positioned(bottom: 4, right: 4, child: badge),
        ],
      );
    }

    if (_cloudAvailable) {
      final image = CachedNetworkImage(
        imageUrl: widget.cloudUrl!,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        placeholder: (context, url) => Container(
          color: Colors.grey.shade100,
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        errorWidget: (context, url, error) {
          _handleCloudError();
          return _missingPlaceholder();
        },
      );

      if (!widget.showCloudBadge) return image;

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

    if (widget.syncStatus == null ||
        widget.syncStatus == 'pending' ||
        widget.syncStatus == 'uploading') {
      return _syncingPlaceholder();
    }
    if (widget.syncStatus == 'error') {
      return _errorPlaceholder();
    }

    return _missingPlaceholder();
  }

  Widget? _syncBadge() {
    final s = widget.syncStatus;
    if (s == null) {
      return Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(
          Icons.cloud_upload_outlined,
          size: 14,
          color: Colors.orange,
        ),
      );
    }
    final IconData icon;
    final Color color;
    switch (s) {
      case 'synced':
        icon = Icons.cloud_done;
        color = Colors.green;
      case 'uploading':
        icon = Icons.cloud_upload;
        color = Colors.blue;
      case 'pending':
        icon = Icons.cloud_upload_outlined;
        color = Colors.orange;
      case 'error':
        icon = Icons.cloud_off;
        color = Colors.red;
      default:
        return null;
    }
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(icon, size: 14, color: color),
    );
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

  static Widget _syncingPlaceholder() {
    return Container(
      color: Colors.grey.shade100,
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  static Widget _errorPlaceholder() {
    return Container(
      color: Colors.grey.shade200,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined),
            SizedBox(height: 6),
            Text('Sync error'),
          ],
        ),
      ),
    );
  }
}
