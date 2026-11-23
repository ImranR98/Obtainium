import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/utils/cache_dir_utils.dart';

void main() {
  late Directory root;
  final readOnlyDirs = <Directory>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('obtainium_cache_test');
  });

  tearDown(() async {
    for (final dir in readOnlyDirs) {
      if (dir.existsSync()) {
        Process.runSync('chmod', ['0755', dir.path]);
      }
    }
    readOnlyDirs.clear();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('uses a writable external cache directory', () {
    final external = Directory('${root.path}/external')..createSync();
    final internal = Directory('${root.path}/internal')..createSync();

    final dirs = resolveCacheDirectories(
      externalCacheRoot: external,
      internalCacheRoot: internal,
    );

    expect(dirs.apkDir.path, external.path);
    expect(dirs.iconsDir.path, '${external.path}/icons');
    expect(dirs.iconsDir.existsSync(), isTrue);
  });

  test('falls back to internal cache when external is not writable', () {
    if (!Platform.isLinux && !Platform.isMacOS) return;

    final external = Directory('${root.path}/external')..createSync();
    final internal = Directory('${root.path}/internal')..createSync();
    final chmod = Process.runSync('chmod', ['0555', external.path]);
    expect(chmod.exitCode, 0);
    readOnlyDirs.add(external);

    final dirs = resolveCacheDirectories(
      externalCacheRoot: external,
      internalCacheRoot: internal,
    );

    expect(dirs.apkDir.path, '${internal.path}/apks');
    expect(dirs.iconsDir.path, '${internal.path}/icons');
    expect(dirs.apkDir.existsSync(), isTrue);
    expect(dirs.iconsDir.existsSync(), isTrue);
  });

  test('creates internal cache directories when external is unavailable', () {
    final internal = Directory('${root.path}/internal')..createSync();

    final dirs = resolveCacheDirectories(
      externalCacheRoot: null,
      internalCacheRoot: internal,
    );

    expect(dirs.apkDir.path, '${internal.path}/apks');
    expect(dirs.iconsDir.path, '${internal.path}/icons');
    expect(dirs.apkDir.existsSync(), isTrue);
    expect(dirs.iconsDir.existsSync(), isTrue);
  });

  test('creates a missing external cache directory', () {
    final external = Directory('${root.path}/external');
    final internal = Directory('${root.path}/internal')..createSync();

    final dirs = resolveCacheDirectories(
      externalCacheRoot: external,
      internalCacheRoot: internal,
    );

    expect(dirs.apkDir.path, external.path);
    expect(dirs.iconsDir.path, '${external.path}/icons');
    expect(dirs.iconsDir.existsSync(), isTrue);
  });
}
