enum PdfExportPreset { original, emailFast, emailFriendly5mb }

extension PdfExportPresetX on PdfExportPreset {
  String get label {
    switch (this) {
      case PdfExportPreset.original:
        return 'Original';
      case PdfExportPreset.emailFast:
        return 'Email-friendly (fast)';
      case PdfExportPreset.emailFriendly5mb:
        return 'Email-friendly (5 MB, slower)';
    }
  }

  String get shortLabel {
    switch (this) {
      case PdfExportPreset.original:
        return 'Original';
      case PdfExportPreset.emailFast:
        return 'Email Fast';
      case PdfExportPreset.emailFriendly5mb:
        return 'Email 5MB (slower)';
    }
  }

  int? get targetMaxBytes {
    switch (this) {
      case PdfExportPreset.original:
        return null;
      case PdfExportPreset.emailFast:
        return 5 * 1024 * 1024;
      case PdfExportPreset.emailFriendly5mb:
        return 5 * 1024 * 1024;
    }
  }

  bool get enforceStrictTarget {
    switch (this) {
      case PdfExportPreset.original:
      case PdfExportPreset.emailFast:
        return false;
      case PdfExportPreset.emailFriendly5mb:
        return true;
    }
  }
}
