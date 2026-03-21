import '../domain/models/unit.dart';

/// Sorts units into workflow-friendly display order: Hoods → Fans → Other.
///
/// Within each type group, units are sorted by natural number order
/// (hood 1, hood 2, hood 10) with letter-suffix support (hood 1a, hood 1b).
///
/// Name normalization handles variations like:
///   hood1  →  hood 1  →  Hood 1  →  all treated as equivalent
///
/// This is the single canonical sort used for UI display, export ordering,
/// and future upload preparation.
class UnitSorter {
  UnitSorter._();

  static List<Unit> sort(List<Unit> units) {
    final copy = [...units];
    copy.sort(_compare);
    return copy;
  }

  static int _compare(Unit a, Unit b) {
    final typeCmp = _typeRank(a.type).compareTo(_typeRank(b.type));
    if (typeCmp != 0) return typeCmp;

    final aName = _normalizeName(a.name);
    final bName = _normalizeName(b.name);
    final aPart = _extractNumberPart(aName);
    final bPart = _extractNumberPart(bName);

    if (aPart != null && bPart != null) {
      final numCmp = aPart.$1.compareTo(bPart.$1);
      if (numCmp != 0) return numCmp;
      final suffixCmp = aPart.$2.compareTo(bPart.$2);
      if (suffixCmp != 0) return suffixCmp;
    } else if (aPart != null) {
      return -1;
    } else if (bPart != null) {
      return 1;
    }

    final nameCmp = aName.compareTo(bName);
    if (nameCmp != 0) return nameCmp;

    return a.unitId.compareTo(b.unitId);
  }

  static int _typeRank(String type) {
    switch (type.trim().toLowerCase()) {
      case 'hood':
        return 0;
      case 'fan':
        return 1;
      default:
        return 2;
    }
  }

  /// Normalizes a unit name for sort comparison.
  ///
  /// Inserts spaces between letter/digit boundaries so that "hood1" and
  /// "hood 1" compare identically. Lowercases and strips non-alphanumeric
  /// characters.
  static String _normalizeName(String input) {
    final separated = input
        .replaceAllMapped(
          RegExp(r'([A-Za-z])(\d)'),
          (m) => '${m[1]} ${m[2]}',
        )
        .replaceAllMapped(
          RegExp(r'(\d)([A-Za-z])'),
          (m) => '${m[1]} ${m[2]}',
        );
    return separated
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Extracts the first integer and optional trailing letter suffix from a
  /// normalized name. Returns null if no number is found.
  ///
  /// Examples:
  ///   "hood 1"   → (1, "")
  ///   "hood 1 a" → (1, "a")
  ///   "fryer hood" → null
  static (int, String)? _extractNumberPart(String normalizedName) {
    final match = RegExp(r'(\d+)\s*([a-z]*)').firstMatch(normalizedName);
    if (match == null) return null;
    final number = int.tryParse(match.group(1)!);
    if (number == null) return null;
    return (number, (match.group(2) ?? '').trim());
  }
}
