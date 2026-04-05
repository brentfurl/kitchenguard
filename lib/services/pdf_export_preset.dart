enum PdfExportPreset { original, emailFriendly5mb }

extension PdfExportPresetX on PdfExportPreset {
  String get label {
    switch (this) {
      case PdfExportPreset.original:
        return 'Original';
      case PdfExportPreset.emailFriendly5mb:
        return 'Email-friendly (5 MB)';
    }
  }

  String get shortLabel {
    switch (this) {
      case PdfExportPreset.original:
        return 'Original';
      case PdfExportPreset.emailFriendly5mb:
        return 'Email 5MB';
    }
  }

  int? get targetMaxBytes {
    switch (this) {
      case PdfExportPreset.original:
        return null;
      case PdfExportPreset.emailFriendly5mb:
        return 5 * 1024 * 1024;
    }
  }
}
