/// Defines sub-phase metadata for each unit type.
///
/// Hood and fan units have 4 documentation phases (2 sub-phases × before/after).
/// Misc units have no sub-phases (just before/after).
class SubPhaseInfo {
  const SubPhaseInfo({required this.key, required this.label});

  /// Value stored in [PhotoRecord.subPhase] (e.g. 'filters-on', 'closed').
  final String key;

  /// Human-readable label for UI display (e.g. 'Filters On', 'Closed').
  final String label;
}

class UnitPhaseConfig {
  UnitPhaseConfig._();

  static const _hoodSubPhases = [
    SubPhaseInfo(key: 'filters-on', label: 'Filters On'),
    SubPhaseInfo(key: 'filters-off', label: 'Filters Off'),
  ];

  static const _fanSubPhases = [
    SubPhaseInfo(key: 'closed', label: 'Closed'),
    SubPhaseInfo(key: 'open', label: 'Open'),
  ];

  /// Whether [unitType] supports sub-phases.
  static bool hasSubPhases(String unitType) =>
      unitType == 'hood' || unitType == 'fan';

  /// All sub-phases for [unitType] in their canonical order, or empty for misc.
  static List<SubPhaseInfo> subPhasesFor(String unitType) {
    switch (unitType) {
      case 'hood':
        return _hoodSubPhases;
      case 'fan':
        return _fanSubPhases;
      default:
        return const [];
    }
  }

  /// Sub-phases ordered for the Before column.
  /// Hood: Filters On, Filters Off.  Fan: Closed, Open.
  static List<SubPhaseInfo> beforeOrder(String unitType) =>
      subPhasesFor(unitType);

  /// Sub-phases ordered for the After column (reversed from before).
  /// Hood: Filters Off, Filters On.  Fan: Open, Closed.
  static List<SubPhaseInfo> afterOrder(String unitType) =>
      subPhasesFor(unitType).reversed.toList();

  /// Returns the display label for a [subPhaseKey] within [unitType],
  /// or null if not found.
  static String? labelFor(String unitType, String subPhaseKey) {
    for (final sp in subPhasesFor(unitType)) {
      if (sp.key == subPhaseKey) return sp.label;
    }
    return null;
  }
}
