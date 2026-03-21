import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenguard_photo_organizer/domain/models/unit.dart';
import 'package:kitchenguard_photo_organizer/utils/unit_sorter.dart';

// Helper to build a minimal Unit for sort testing.
Unit _unit(String type, String name) => Unit(
      unitId: name, // use name as id so ties are deterministic
      type: type,
      name: name,
      unitFolderName: name,
      isComplete: false,
      photosBefore: const [],
      photosAfter: const [],
    );

List<String> _names(List<Unit> units) => units.map((u) => u.name).toList();

void main() {
  group('UnitSorter — type ordering', () {
    test('hoods before fans before misc', () {
      final units = [
        _unit('misc', 'misc item'),
        _unit('fan', 'fan 1'),
        _unit('hood', 'hood 1'),
      ];
      final sorted = UnitSorter.sort(units);
      expect(_names(sorted), ['hood 1', 'fan 1', 'misc item']);
    });

    test('multiple hoods all come before any fan', () {
      final units = [
        _unit('fan', 'fan 1'),
        _unit('hood', 'hood 2'),
        _unit('hood', 'hood 1'),
        _unit('fan', 'fan 2'),
      ];
      final sorted = UnitSorter.sort(units);
      expect(_names(sorted), ['hood 1', 'hood 2', 'fan 1', 'fan 2']);
    });

    test('misc follows fans', () {
      final units = [
        _unit('misc', 'grease trap'),
        _unit('fan', 'fan 1'),
        _unit('misc', 'duct section'),
      ];
      final sorted = UnitSorter.sort(units);
      expect(sorted[0].type, 'fan');
      expect(sorted[1].type, 'misc');
      expect(sorted[2].type, 'misc');
    });

    test('unknown type treated as misc (last)', () {
      final units = [
        _unit('custom', 'custom unit'),
        _unit('hood', 'hood 1'),
      ];
      final sorted = UnitSorter.sort(units);
      expect(sorted[0].name, 'hood 1');
      expect(sorted[1].name, 'custom unit');
    });
  });

  group('UnitSorter — natural number ordering within a type', () {
    test('hood 1, hood 2, hood 10 sorts naturally (not lexicographically)', () {
      final units = [
        _unit('hood', 'hood 10'),
        _unit('hood', 'hood 2'),
        _unit('hood', 'hood 1'),
      ];
      final sorted = UnitSorter.sort(units);
      expect(_names(sorted), ['hood 1', 'hood 2', 'hood 10']);
    });

    test('numbered units come before unnumbered units in same type', () {
      final units = [
        _unit('hood', 'fryer hood'),
        _unit('hood', 'hood 2'),
        _unit('hood', 'hood 1'),
      ];
      final sorted = UnitSorter.sort(units);
      expect(_names(sorted), ['hood 1', 'hood 2', 'fryer hood']);
    });

    test('fan natural number ordering', () {
      final units = [
        _unit('fan', 'fan 3'),
        _unit('fan', 'fan 1'),
        _unit('fan', 'fan 2'),
      ];
      final sorted = UnitSorter.sort(units);
      expect(_names(sorted), ['fan 1', 'fan 2', 'fan 3']);
    });
  });

  group('UnitSorter — letter suffix ordering', () {
    test('hood 1 before hood 1a before hood 1b', () {
      final units = [
        _unit('hood', 'hood 1b'),
        _unit('hood', 'hood 1'),
        _unit('hood', 'hood 1a'),
      ];
      final sorted = UnitSorter.sort(units);
      expect(_names(sorted), ['hood 1', 'hood 1a', 'hood 1b']);
    });

    test('suffix sorts after no-suffix within same number', () {
      final units = [
        _unit('hood', 'hood 2a'),
        _unit('hood', 'hood 2'),
        _unit('hood', 'hood 1'),
      ];
      final sorted = UnitSorter.sort(units);
      expect(_names(sorted), ['hood 1', 'hood 2', 'hood 2a']);
    });
  });

  group('UnitSorter — name normalization', () {
    test('hood1 and hood 1 and Hood 1 are treated as equivalent for sorting', () {
      // All three should sort together in position 1.
      // We test that all come before hood 2.
      final units = [
        _unit('hood', 'hood 2'),
        _unit('hood', 'Hood 1'),
      ];
      final sorted = UnitSorter.sort(units);
      expect(sorted[0].name, 'Hood 1');
      expect(sorted[1].name, 'hood 2');
    });

    test('hood1 (no space) sorts before hood 2', () {
      final units = [
        _unit('hood', 'hood 2'),
        _unit('hood', 'hood1'),
      ];
      final sorted = UnitSorter.sort(units);
      expect(sorted[0].name, 'hood1');
      expect(sorted[1].name, 'hood 2');
    });

    test('HOOD 1 (all caps) sorts correctly', () {
      final units = [
        _unit('hood', 'hood 3'),
        _unit('hood', 'HOOD 1'),
        _unit('hood', 'hood 2'),
      ];
      final sorted = UnitSorter.sort(units);
      expect(sorted[0].name, 'HOOD 1');
      expect(sorted[1].name, 'hood 2');
      expect(sorted[2].name, 'hood 3');
    });
  });

  group('UnitSorter — edge cases', () {
    test('empty list returns empty list', () {
      expect(UnitSorter.sort([]), isEmpty);
    });

    test('single item returns single item unchanged', () {
      final units = [_unit('hood', 'hood 1')];
      final sorted = UnitSorter.sort(units);
      expect(sorted.length, 1);
      expect(sorted.first.name, 'hood 1');
    });

    test('sort does not mutate the original list', () {
      final original = [
        _unit('fan', 'fan 1'),
        _unit('hood', 'hood 1'),
      ];
      final copy = List<Unit>.from(original);
      UnitSorter.sort(original);
      expect(original[0].name, copy[0].name);
      expect(original[1].name, copy[1].name);
    });

    test('all same type: sorts by number only', () {
      final units = [
        _unit('misc', 'item 3'),
        _unit('misc', 'item 1'),
        _unit('misc', 'item 2'),
      ];
      final sorted = UnitSorter.sort(units);
      expect(_names(sorted), ['item 1', 'item 2', 'item 3']);
    });

    test('full realistic job unit list sorts correctly', () {
      final units = [
        _unit('misc', 'grease trap'),
        _unit('fan', 'fan 2'),
        _unit('hood', 'hood 10'),
        _unit('fan', 'fan 1'),
        _unit('hood', 'fryer hood'),
        _unit('hood', 'hood 2'),
        _unit('hood', 'hood 1'),
      ];
      final sorted = UnitSorter.sort(units);
      expect(_names(sorted), [
        'hood 1',
        'hood 2',
        'hood 10',
        'fryer hood',
        'fan 1',
        'fan 2',
        'grease trap',
      ]);
    });
  });
}
