import 'dart:developer' as developer;
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as p;

/// Thin wrapper around [FirebaseStorage] for uploading job media.
///
/// Upload paths mirror the local folder structure:
///   jobs/{jobId}/{relativePath}
///
/// Example:
///   jobs/abc-123/Hoods/hood_1__unit-xyz/Before/photo_20260323_091500.jpg
class StorageService {
  StorageService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  /// Uploads a local [file] to Firebase Storage at the canonical path
  /// `jobs/{jobId}/{relativePath}`.
  ///
  /// [relativePath] is the photo/video's path relative to the job folder
  /// (same value stored in `PhotoRecord.relativePath` / `VideoRecord.relativePath`).
  ///
  /// Returns the public download URL on success.
  ///
  /// Throws on network failure; callers should catch and mark the record as
  /// 'error' for retry.
  Future<String> uploadJobFile({
    required String jobId,
    required String relativePath,
    required File file,
    String? contentType,
  }) async {
    final storagePath = 'jobs/$jobId/${_normalizePath(relativePath)}';

    final ref = _storage.ref(storagePath);

    final metadata = contentType != null
        ? SettableMetadata(contentType: contentType)
        : null;

    developer.log(
      'Uploading $storagePath (${file.lengthSync()} bytes)',
      name: 'StorageService',
    );

    await ref.putFile(file, metadata);

    final downloadUrl = await ref.getDownloadURL();

    developer.log(
      'Upload complete: $storagePath',
      name: 'StorageService',
    );

    return downloadUrl;
  }

  /// Uploads a photo file. Convenience wrapper that infers JPEG content type.
  Future<String> uploadPhoto({
    required String jobId,
    required String relativePath,
    required File file,
  }) {
    return uploadJobFile(
      jobId: jobId,
      relativePath: relativePath,
      file: file,
      contentType: 'image/jpeg',
    );
  }

  /// Uploads a video file. Convenience wrapper that infers content type
  /// from the file extension.
  Future<String> uploadVideo({
    required String jobId,
    required String relativePath,
    required File file,
  }) {
    final ext = p.extension(file.path).toLowerCase();
    final contentType = ext == '.mp4' ? 'video/mp4' : 'video/$ext';

    return uploadJobFile(
      jobId: jobId,
      relativePath: relativePath,
      file: file,
      contentType: contentType,
    );
  }

  /// Deletes a file from Storage at `jobs/{jobId}/{relativePath}`.
  ///
  /// Fails silently if the file does not exist.
  Future<void> deleteJobFile({
    required String jobId,
    required String relativePath,
  }) async {
    final storagePath = 'jobs/$jobId/${_normalizePath(relativePath)}';
    try {
      await _storage.ref(storagePath).delete();
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return;
      rethrow;
    }
  }

  /// Returns the download URL for an already-uploaded file, or null if
  /// the file does not exist.
  Future<String?> getDownloadUrl({
    required String jobId,
    required String relativePath,
  }) async {
    final storagePath = 'jobs/$jobId/${_normalizePath(relativePath)}';
    try {
      return await _storage.ref(storagePath).getDownloadURL();
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return null;
      rethrow;
    }
  }

  /// Normalizes backslashes to forward slashes (Windows safety).
  String _normalizePath(String path) => path.replaceAll('\\', '/');
}
