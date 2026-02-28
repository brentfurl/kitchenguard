import 'dart:io';

/// Writes [contents] to [target] using a temp file in the same directory,
/// then renames the temp file over the target path.
Future<void> atomicWriteString(File target, String contents) async {
  final parent = target.parent;
  if (!await parent.exists()) {
    await parent.create(recursive: true);
  }

  final temp = File(_tempPathForTarget(target));
  RandomAccessFile? raf;

  try {
    raf = await temp.open(mode: FileMode.write);
    await raf.writeString(contents);
    await raf.flush();
    await raf.close();
    raf = null;

    await temp.rename(target.path);
  } catch (_) {
    if (raf != null) {
      await raf.close();
    }
    if (await temp.exists()) {
      await temp.delete();
    }
    rethrow;
  }
}

/// Writes [bytes] to [target] using a temp file in the same directory,
/// then renames the temp file over the target path.
Future<void> atomicWriteBytes(File target, List<int> bytes) async {
  final parent = target.parent;
  if (!await parent.exists()) {
    await parent.create(recursive: true);
  }

  final temp = File(_tempPathForTarget(target));
  RandomAccessFile? raf;

  try {
    raf = await temp.open(mode: FileMode.write);
    await raf.writeFrom(bytes);
    await raf.flush();
    await raf.close();
    raf = null;

    await temp.rename(target.path);
  } catch (_) {
    if (raf != null) {
      await raf.close();
    }
    if (await temp.exists()) {
      await temp.delete();
    }
    rethrow;
  }
}

String _tempPathForTarget(File target) {
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  return '${target.path}.tmp.$pid.$timestamp';
}
