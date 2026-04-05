import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'pdf_export_builder.dart';
import 'pdf_export_preset.dart';

class PdfBuildResult {
  const PdfBuildResult({
    required this.bytes,
    required this.targetMet,
    this.targetBytes,
  });

  final Uint8List bytes;
  final bool targetMet;
  final int? targetBytes;
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
  }) async {
    final targetBytes = preset.targetMaxBytes;
    if (targetBytes == null) {
      final bytes = await PdfExportBuilder.build(
        cover: cover,
        sections: sections,
      );
      return PdfBuildResult(bytes: bytes, targetMet: true);
    }

    Uint8List? smallest;
    for (final pass in _emailFriendlyPasses) {
      final compressed = _compressSections(sections, pass);
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
        );
      }
    }

    return PdfBuildResult(
      bytes:
          smallest ??
          (await PdfExportBuilder.build(cover: cover, sections: sections)),
      targetMet: false,
      targetBytes: targetBytes,
    );
  }

  static List<PdfSection> _compressSections(
    List<PdfSection> sections,
    _CompressionPass pass,
  ) {
    return sections
        .map(
          (section) => PdfSection(
            title: section.title,
            imageBytes: section.imageBytes
                .map((bytes) => _compressSingle(bytes, pass))
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
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
