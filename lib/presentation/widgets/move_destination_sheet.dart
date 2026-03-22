import 'package:flutter/material.dart';

import '../../domain/models/unit.dart';
import '../../domain/models/unit_phase_config.dart';

class MoveDestination {
  const MoveDestination({required this.unitId, this.subPhase});
  final String unitId;
  final String? subPhase;
}

/// Shows a modal bottom sheet that lets the user pick a destination unit
/// (and optionally a sub-phase) for a photo move operation.
///
/// Returns a [MoveDestination] if confirmed, or null if dismissed.
Future<MoveDestination?> showMoveDestinationSheet({
  required BuildContext context,
  required List<Unit> allUnits,
  required String currentUnitId,
  required String currentPhase,
  required String? currentSubPhase,
}) {
  return showModalBottomSheet<MoveDestination>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _MoveDestinationBody(
      allUnits: allUnits,
      currentUnitId: currentUnitId,
      currentPhase: currentPhase,
      currentSubPhase: currentSubPhase,
    ),
  );
}

class _MoveDestinationBody extends StatefulWidget {
  const _MoveDestinationBody({
    required this.allUnits,
    required this.currentUnitId,
    required this.currentPhase,
    required this.currentSubPhase,
  });

  final List<Unit> allUnits;
  final String currentUnitId;
  final String currentPhase;
  final String? currentSubPhase;

  @override
  State<_MoveDestinationBody> createState() => _MoveDestinationBodyState();
}

class _MoveDestinationBodyState extends State<_MoveDestinationBody> {
  String? _selectedUnitId;
  String? _selectedSubPhase;

  bool get _isValidDestination {
    if (_selectedUnitId == null) return false;
    if (_selectedUnitId == widget.currentUnitId &&
        _selectedSubPhase == widget.currentSubPhase) {
      return false;
    }
    return true;
  }

  void _onUnitTapped(Unit unit) {
    setState(() {
      _selectedUnitId = unit.unitId;

      if (UnitPhaseConfig.hasSubPhases(unit.type)) {
        // Try to preserve current sub-phase if the target unit supports it.
        final subPhases = UnitPhaseConfig.subPhasesFor(unit.type);
        final hasMatch = subPhases.any((sp) => sp.key == widget.currentSubPhase);
        if (hasMatch) {
          _selectedSubPhase = widget.currentSubPhase;
        } else {
          _selectedSubPhase = UnitPhaseConfig.defaultSubPhaseKey(
            unit.type,
            widget.currentPhase,
          );
        }
      } else {
        _selectedSubPhase = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final phaseLabel =
        widget.currentPhase == 'before' ? 'Before' : 'After';

    // Group units by type for visual clarity.
    final hoods = widget.allUnits.where((u) => u.type == 'hood').toList();
    final fans = widget.allUnits.where((u) => u.type == 'fan').toList();
    final misc = widget.allUnits.where((u) => u.type == 'misc').toList();

    final groups = <(String, List<Unit>)>[
      if (hoods.isNotEmpty) ('Hoods', hoods),
      if (fans.isNotEmpty) ('Fans', fans),
      if (misc.isNotEmpty) ('Misc', misc),
    ];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Move to... ($phaseLabel)',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final (label, units) in groups) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: Text(
                        label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    for (final unit in units) ...[
                      _UnitTile(
                        unit: unit,
                        isCurrent: unit.unitId == widget.currentUnitId,
                        isSelected: unit.unitId == _selectedUnitId,
                        onTap: () => _onUnitTapped(unit),
                      ),
                      if (unit.unitId == _selectedUnitId &&
                          UnitPhaseConfig.hasSubPhases(unit.type))
                        _SubPhasePicker(
                          unitType: unit.type,
                          phase: widget.currentPhase,
                          selectedSubPhase: _selectedSubPhase,
                          onChanged: (sp) =>
                              setState(() => _selectedSubPhase = sp),
                        ),
                    ],
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isValidDestination
                        ? () => Navigator.of(context).pop(
                              MoveDestination(
                                unitId: _selectedUnitId!,
                                subPhase: _selectedSubPhase,
                              ),
                            )
                        : null,
                    child: const Text('Move here'),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _UnitTile extends StatelessWidget {
  const _UnitTile({
    required this.unit,
    required this.isCurrent,
    required this.isSelected,
    required this.onTap,
  });

  final Unit unit;
  final bool isCurrent;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      leading: Icon(
        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: isSelected ? colorScheme.primary : null,
      ),
      title: Row(
        children: [
          Flexible(child: Text(unit.name)),
          if (isCurrent) ...[
            const SizedBox(width: 8),
            Text(
              '(current)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        unit.type[0].toUpperCase() + unit.type.substring(1),
        style: theme.textTheme.bodySmall,
      ),
      selected: isSelected,
      selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
      onTap: onTap,
    );
  }
}

class _SubPhasePicker extends StatelessWidget {
  const _SubPhasePicker({
    required this.unitType,
    required this.phase,
    required this.selectedSubPhase,
    required this.onChanged,
  });

  final String unitType;
  final String phase;
  final String? selectedSubPhase;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subPhases = UnitPhaseConfig.subPhasesFor(unitType);

    return Padding(
      padding: const EdgeInsets.only(left: 56, right: 16, bottom: 8),
      child: Wrap(
        spacing: 8,
        children: [
          for (final sp in subPhases)
            ChoiceChip(
              label: Text(sp.label),
              selected: selectedSubPhase == sp.key,
              labelStyle: theme.textTheme.bodySmall,
              onSelected: (_) => onChanged(sp.key),
            ),
        ],
      ),
    );
  }
}
