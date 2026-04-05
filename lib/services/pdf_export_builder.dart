import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;

/// Metadata for the PDF cover page.
class PdfCoverInfo {
  const PdfCoverInfo({
    required this.restaurantName,
    this.address,
    required this.shiftDate,
  });

  final String restaurantName;
  final String? address;
  final String shiftDate;
}

/// A titled group of photos that starts on a new page.
class PdfSection {
  const PdfSection({required this.title, required this.imageBytes});

  final String title;
  final List<Uint8List> imageBytes;
}

/// Builds a structured photo-report PDF from cover info and photo sections.
///
/// Layout: Letter portrait, 3 columns x 2 rows (6 photos per page).
/// Each [PdfSection] starts on a fresh page. Sections with >6 photos
/// continue on subsequent pages with the title repeated.
class PdfExportBuilder {
  PdfExportBuilder._();

  static const _cols = 3;
  static const _rows = 2;
  static const _photosPerPage = _cols * _rows;

  static const _margin = 36.0; // 0.5 inch
  static const _cellGap = 10.0;
  static const _titleHeight = 28.0;
  static const _titleBottomGap = 10.0;
  static const _footerGreen = PdfColor.fromInt(0xFF689523);

  static Future<Uint8List> build({
    required PdfCoverInfo cover,
    required List<PdfSection> sections,
  }) async {
    final doc = pw.Document();
    final logoBytes = await _loadCoverLogoBytes();

    doc.addPage(_buildCoverPage(cover, logoBytes: logoBytes));

    for (final section in sections) {
      if (section.imageBytes.isEmpty) continue;
      _addSectionPages(doc, section);
    }

    return await doc.save();
  }

  static pw.Page _buildCoverPage(
    PdfCoverInfo cover, {
    Uint8List? logoBytes,
  }) {
    final address = cover.address?.trim() ?? '';
    final shiftDateYmd = _toYyyyMmDd(cover.shiftDate);
    return pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: pw.EdgeInsets.zero,
      build: (ctx) {
        return pw.Column(
          children: [
            pw.Expanded(
              child: pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            shiftDateYmd,
                            style: const pw.TextStyle(fontSize: 10.5),
                          ),
                          pw.SizedBox(height: 10),
                          pw.RichText(
                            text: pw.TextSpan(
                              text: 'Prepared for: ',
                              style: const pw.TextStyle(
                                fontSize: 10.5,
                                color: PdfColors.black,
                              ),
                              children: [
                                pw.TextSpan(
                                  text: _titleCase(cover.restaurantName),
                                  style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          pw.SizedBox(height: 10),
                          if (address.isNotEmpty)
                            pw.Text(
                              address,
                              style: const pw.TextStyle(fontSize: 10.5),
                            ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 20),
                    pw.SizedBox(
                      width: 161,
                      child: pw.Padding(
                        // Lift logo block higher to tighten top-right placement.
                        padding: const pw.EdgeInsets.only(top: -32),
                        child: logoBytes == null
                            ? pw.Align(
                                alignment: pw.Alignment.topRight,
                                child: pw.Text(
                                  'KitchenGuard',
                                  style: pw.TextStyle(
                                    fontSize: 24,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                              )
                            : pw.Image(
                                pw.MemoryImage(logoBytes),
                                fit: pw.BoxFit.contain,
                                alignment: pw.Alignment.topRight,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            pw.Container(
              width: double.infinity,
              color: _footerGreen,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 10,
              ),
              child: pw.Text(
                'www.kitchenguard.com/centex/ | 395 Enterprise Blvd Ste. A, Waco, TX 76643',
                style: const pw.TextStyle(
                  fontSize: 11,
                  color: PdfColors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static Future<Uint8List?> _loadCoverLogoBytes() async {
    try {
      final data = await rootBundle.load('assets/pdf/kg_logo_transparent.png');
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  static void _addSectionPages(pw.Document doc, PdfSection section) {
    final images = section.imageBytes;
    final pageCount = (images.length + _photosPerPage - 1) ~/ _photosPerPage;

    for (var page = 0; page < pageCount; page++) {
      final start = page * _photosPerPage;
      final end = start + _photosPerPage;
      final chunk = images.sublist(
        start,
        end > images.length ? images.length : end,
      );

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.letter,
          margin: pw.EdgeInsets.all(_margin),
          build: (ctx) {
            final usableWidth =
                PdfPageFormat.letter.width - _margin * 2;
            final gridTop = _titleHeight + _titleBottomGap;
            final usableGridHeight =
                PdfPageFormat.letter.height - _margin * 2 - gridTop;
            final cellWidth =
                (usableWidth - _cellGap * (_cols - 1)) / _cols;
            final cellHeight =
                (usableGridHeight - _cellGap * (_rows - 1)) / _rows;

            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  height: _titleHeight,
                  child: pw.Align(
                    alignment: pw.Alignment.bottomLeft,
                    child: pw.Text(
                      _titleCase(section.title),
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(height: _titleBottomGap),
                pw.Expanded(
                  child: _buildGrid(chunk, cellWidth, cellHeight),
                ),
              ],
            );
          },
        ),
      );
    }
  }

  /// Builds a fixed 3x2 grid. Empty cells are left blank.
  static pw.Widget _buildGrid(
    List<Uint8List> chunk,
    double cellWidth,
    double cellHeight,
  ) {
    final rows = <pw.Widget>[];
    for (var r = 0; r < _rows; r++) {
      final cells = <pw.Widget>[];
      for (var c = 0; c < _cols; c++) {
        final idx = r * _cols + c;
        if (idx < chunk.length) {
          cells.add(_imageCell(chunk[idx], cellWidth, cellHeight));
        } else {
          cells.add(pw.SizedBox(width: cellWidth, height: cellHeight));
        }
        if (c < _cols - 1) {
          cells.add(pw.SizedBox(width: _cellGap));
        }
      }
      rows.add(pw.Row(children: cells));
      if (r < _rows - 1) {
        rows.add(pw.SizedBox(height: _cellGap));
      }
    }
    return pw.Column(children: rows);
  }

  static pw.Widget _imageCell(
    Uint8List bytes,
    double width,
    double height,
  ) {
    pw.ImageProvider image;
    try {
      image = pw.MemoryImage(bytes);
    } catch (_) {
      return pw.Container(
        width: width,
        height: height,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
        ),
        child: pw.Center(
          child: pw.Text('Image error', style: const pw.TextStyle(fontSize: 9)),
        ),
      );
    }

    return pw.SizedBox(
      width: width,
      height: height,
      child: pw.FittedBox(
        fit: pw.BoxFit.contain,
        child: pw.Image(image),
      ),
    );
  }

  static String _titleCase(String input) {
    if (input.isEmpty) return input;
    return input
        .split(' ')
        .map((w) =>
            w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  static String _toYyyyMmDd(String input) {
    final trimmed = input.trim();
    final parsed = DateTime.tryParse(trimmed);
    if (parsed != null) {
      final month = parsed.month.toString().padLeft(2, '0');
      final day = parsed.day.toString().padLeft(2, '0');
      return '${parsed.year}-$month-$day';
    }
    final match = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(trimmed);
    return match?.group(1) ?? trimmed;
  }
}
