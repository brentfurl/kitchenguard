import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'pdf_export_builder.dart';
import 'pdf_export_preset.dart';

class PdfBuildResult {
  const PdfBuildResult({
    required this.bytes,
    required this.targetMet,
    this.targetBytes,
    required this.preset,
  });

  final Uint8List bytes;
  final bool targetMet;
  final int? targetBytes;
  final PdfExportPreset preset;
}

class PdfImageOptimizer {
  PdfImageOptimizer._();

  static const List<_CompressionPass> _emailFriendlyPasses = [
    _CompressionPass(maxLongEdge: 1800, jpegQuality: 84),
    _CompressionPass(maxLongEdge: 1600, jpegQuality: 78),
    _CompressionPass(maxLongEdge: 1400, jpegQuality: 72),
    _CompressionPass(maxLongEdge: 1200, jpegQuality: 66),
    _CompressionPass(maxLongEdge: 1050, jpegQuality: 60),
    _CompressionPass(maxLongEdge: 900, jpegQuality: 54),
  ];

  static Future<PdfBuildResult> buildWithPreset({
    required PdfCoverInfo cover,
    required List<PdfSection> sections,
    required PdfExportPreset preset,
    void Function(String message)? onProgress,
  }) async {
    final targetBytes = preset.targetMaxBytes;
    if (targetBytes == null) {
      onProgress?.call('Building PDF...');
      final bytes = await PdfExportBuilder.build(
        cover: cover,
        sections: sections,
      );
      return PdfBuildResult(bytes: bytes, targetMet: true, preset: preset);
    }

    switch (preset) {
      case PdfExportPreset.emailFast:
        return _buildFastEmailPdf(
          cover: cover,
          sections: sections,
          targetBytes: targetBytes,
          onProgress: onProgress,
        );
      case PdfExportPreset.emailFriendly5mb:
        return _buildStrictEmailPdf(
          cover: cover,
          sections: sections,
          targetBytes: targetBytes,
          onProgress: onProgress,
        );
      case PdfExportPreset.original:
        throw StateError('Unhandled original preset.');
    }
  }

  static Future<PdfBuildResult> _buildFastEmailPdf({
    required PdfCoverInfo cover,
    required List<PdfSection> sections,
    required int targetBytes,
    void Function(String message)? onProgress,
  }) async {
    // Single-pass best effort preset for speed.
    final pass = _emailFriendlyPasses[3];
    onProgress?.call('Compressing images (fast pass)...');
    final compressed = await _compressSections(sections, pass);
    onProgress?.call('Building PDF...');
    final pdfBytes = await PdfExportBuilder.build(
      cover: cover,
      sections: compressed,
    );
    return PdfBuildResult(
      bytes: pdfBytes,
      targetMet: pdfBytes.length <= targetBytes,
      targetBytes: targetBytes,
      preset: PdfExportPreset.emailFast,
    );
  }

  static Future<PdfBuildResult> _buildStrictEmailPdf({
    required PdfCoverInfo cover,
    required List<PdfSection> sections,
    required int targetBytes,
    void Function(String message)? onProgress,
  }) async {
    const maxAttempts = 2;
    Uint8List? smallest;
    var passIndex = 2;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final pass = _emailFriendlyPasses[passIndex];
      onProgress?.call('Compressing images ($attempt/$maxAttempts)...');
      final compressed = await _compressSections(sections, pass);
      onProgress?.call('Building PDF ($attempt/$maxAttempts)...');
      final pdfBytes = await PdfExportBuilder.build(
        cover: cover,
        sections: compressed,
      );

      if (smallest == null || pdfBytes.length < smallest.length) {
        smallest = pdfBytes;
      }
      if (pdfBytes.length <= targetBytes) {
        return PdfBuildResult(
          bytes: pdfBytes,
          targetMet: true,
          targetBytes: targetBytes,
          preset: PdfExportPreset.emailFriendly5mb,
        );
      }

      if (attempt == maxAttempts) break;
      passIndex = _nextAdaptivePassIndex(
        currentPassIndex: passIndex,
        currentBytes: pdfBytes.length,
        targetBytes: targetBytes,
      );
    }

    return PdfBuildResult(
      bytes:
          smallest ??
          (await PdfExportBuilder.build(cover: cover, sections: sections)),
      targetMet: false,
      targetBytes: targetBytes,
      preset: PdfExportPreset.emailFriendly5mb,
    );
  }

  static int _nextAdaptivePassIndex({
    required int currentPassIndex,
    required int currentBytes,
    required int targetBytes,
  }) {
    final ratio = currentBytes / targetBytes;
    var step = 1;
    if (ratio > 2.4) {
      step = 3;
    } else if (ratio > 1.8) {
      step = 2;
    } else if (ratio > 1.3) {
      step = 1;
    }
    final next = currentPassIndex + step;
    if (next >= _emailFriendlyPasses.length) {
      return _emailFriendlyPasses.length - 1;
    }
    return next;
  }

  static Future<List<PdfSection>> _compressSections(
    List<PdfSection> sections,
    _CompressionPass pass,
  ) async {
    final compressedSections = <PdfSection>[];
    for (final section in sections) {
      final compressedImages = <Uint8List>[];
      for (final bytes in section.imageBytes) {
        compressedImages.add(_compressSingle(bytes, pass));
        // Yield between images so web UIs stay responsive during long exports.
        await Future.delayed(Duration.zero);
      }
      compressedSections.add(
        PdfSection(title: section.title, imageBytes: compressedImages),
      );
    }
    return compressedSections;
  }

  static Uint8List _compressSingle(Uint8List bytes, _CompressionPass pass) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    final resized = _resizeIfNeeded(decoded, pass.maxLongEdge);
    final encoded = img.encodeJpg(resized, quality: pass.jpegQuality);
    return Uint8List.fromList(encoded);
  }

  static img.Image _resizeIfNeeded(img.Image source, int maxLongEdge) {
    final width = source.width;
    final height = source.height;
    final longEdge = width > height ? width : height;
    if (longEdge <= maxLongEdge) return source;

    if (width >= height) {
      final newWidth = maxLongEdge;
      final newHeight = ((height * maxLongEdge) / width).round().clamp(
        1,
        maxLongEdge,
      );
      return img.copyResize(source, width: newWidth, height: newHeight);
    }

    final newHeight = maxLongEdge;
    final newWidth = ((width * maxLongEdge) / height).round().clamp(
      1,
      maxLongEdge,
    );
    return img.copyResize(source, width: newWidth, height: newHeight);
  }
}

class _CompressionPass {
  const _CompressionPass({
    required this.maxLongEdge,
    required this.jpegQuality,
  });

  final int maxLongEdge;
  final int jpegQuality;
}
