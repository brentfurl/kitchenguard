import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Computes canonical filesystem paths for KitchenGuard jobs.
///
/// This class only computes paths and never creates folders.
class AppPaths {
  static const String rootFolderName = 'KitchenCleaningJobs';
  static const String hoodsCategory = 'Hoods';
  static const String fansCategory = 'Fans';
  static const String miscCategory = 'Misc';
  static const String beforeFolderName = 'Before';
  static const String afterFolderName = 'After';

  Future<String> getDocumentsPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<String> getRootPath() async {
    final documentsPath = await getDocumentsPath();
    return p.join(documentsPath, rootFolderName);
  }

  Future<String> getJobPath({
    required String restaurantName,
    required DateTime shiftStartDate,
  }) async {
    final rootPath = await getRootPath();
    final safeRestaurant = sanitizeName(restaurantName);
    final date = _formatDateYyyyMmDd(shiftStartDate);
    return p.join(rootPath, '${safeRestaurant}_$date');
  }

  Future<String> getHoodsPath({
    required String restaurantName,
    required DateTime shiftStartDate,
  }) async {
    final jobPath = await getJobPath(
      restaurantName: restaurantName,
      shiftStartDate: shiftStartDate,
    );
    return p.join(jobPath, hoodsCategory);
  }

  Future<String> getFansPath({
    required String restaurantName,
    required DateTime shiftStartDate,
  }) async {
    final jobPath = await getJobPath(
      restaurantName: restaurantName,
      shiftStartDate: shiftStartDate,
    );
    return p.join(jobPath, fansCategory);
  }

  Future<String> getMiscPath({
    required String restaurantName,
    required DateTime shiftStartDate,
  }) async {
    final jobPath = await getJobPath(
      restaurantName: restaurantName,
      shiftStartDate: shiftStartDate,
    );
    return p.join(jobPath, miscCategory);
  }

  Future<String> getUnitPath({
    required String restaurantName,
    required DateTime shiftStartDate,
    required String categoryName,
    required String unitName,
  }) async {
    final jobPath = await getJobPath(
      restaurantName: restaurantName,
      shiftStartDate: shiftStartDate,
    );
    final safeUnitName = sanitizeName(unitName);
    return p.join(jobPath, categoryName, safeUnitName);
  }

  String unitFolderName({required String unitName, required String unitId}) {
    final safeName = sanitizeName(unitName);
    final safeId = sanitizeName(unitId);
    return '${safeName}__$safeId';
  }

  Future<String> getUnitPathV2({
    required String restaurantName,
    required DateTime shiftStartDate,
    required String categoryName,
    required String unitName,
    required String unitId,
  }) async {
    final jobPath = await getJobPath(
      restaurantName: restaurantName,
      shiftStartDate: shiftStartDate,
    );
    final folder = unitFolderName(unitName: unitName, unitId: unitId);
    return p.join(jobPath, categoryName, folder);
  }

  Future<String> getBeforePath({
    required String restaurantName,
    required DateTime shiftStartDate,
    required String categoryName,
    required String unitName,
  }) async {
    final unitPath = await getUnitPath(
      restaurantName: restaurantName,
      shiftStartDate: shiftStartDate,
      categoryName: categoryName,
      unitName: unitName,
    );
    return p.join(unitPath, beforeFolderName);
  }

  Future<String> getAfterPath({
    required String restaurantName,
    required DateTime shiftStartDate,
    required String categoryName,
    required String unitName,
  }) async {
    final unitPath = await getUnitPath(
      restaurantName: restaurantName,
      shiftStartDate: shiftStartDate,
      categoryName: categoryName,
      unitName: unitName,
    );
    return p.join(unitPath, afterFolderName);
  }

  String sanitizeName(String input) {
    final trimmed = input.trim();
    final withUnderscores = trimmed.replaceAll(RegExp(r'\s+'), '_');
    final onlyAllowed = withUnderscores.replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '',
    );
    final collapsed = onlyAllowed.replaceAll(RegExp(r'_+'), '_');
    return collapsed;
  }

  String _formatDateYyyyMmDd(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
